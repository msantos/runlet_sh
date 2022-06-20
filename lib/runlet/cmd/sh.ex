defmodule Runlet.Cmd.Sh do
  @moduledoc "Run Unix processes in a container"

  defstruct task: nil,
            sh: nil,
            stream_pid: nil,
            status: :running,
            flush_timeout: 0,
            err: nil

  @type t :: %__MODULE__{
          task: pid | nil,
          sh: pid | nil,
          stream_pid: pid | nil,
          status: :running | :flush | :flushing,
          flush_timeout: 0 | :infinity,
          err: atom | nil
        }

  @env [
    ~s(PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/opt/sbin:/opt/bin),
    ~s(HOME=/home)
  ]

  @doc """
  Runs a Unix command in a container.
  """
  @spec exec(binary) :: Enumerable.t()
  def exec(cmd) do
    startfun = fn ->
      case fork(cmd) do
        {:ok, state} -> state
        {:error, error} -> %Runlet.Cmd.Sh{err: error}
      end
    end

    resourcefun = fn state -> stdio(cmd, state) end

    endfun = fn %Runlet.Cmd.Sh{
                  task: task
                } ->
      atexit(task)
    end

    Stream.resource(
      startfun,
      resourcefun,
      endfun
    )
  end

  @spec stream_to_pid(Enumerable.t(), pid) :: Enumerable.t()
  defp stream_to_pid(stream, pid) do
    startfun = fn ->
      :ok
    end

    transformfun = fn
      %Runlet.Event{} = e, state ->
        Kernel.send(pid, e)

        receive do
          :ok ->
            {[], state}

          :halt ->
            {:halt, state}
        end

      _, state ->
        {[], state}
    end

    endfun = fn _state ->
      Kernel.send(pid, :runlet_eof)
      Process.unlink(pid)
    end

    Stream.transform(
      stream,
      startfun,
      transformfun,
      endfun
    )
  end

  @doc false
  @spec exec(Enumerable.t(), binary) :: Enumerable.t()
  def exec(stream, cmd) do
    streamfun = fn pid ->
      fn ->
        stream
        |> stream_to_pid(pid)
        |> Stream.run()
      end
    end

    startfun = fn ->
      case fork(cmd) do
        {:ok, state} ->
          stream_pid = Kernel.spawn_link(streamfun.(self()))
          %{state | stream_pid: stream_pid}

        {:error, error} ->
          %Runlet.Cmd.Sh{err: error}
      end
    end

    resourcefun = fn state -> stdio(cmd, state) end

    endfun = fn
      %Runlet.Cmd.Sh{
        task: task,
        stream_pid: nil
      } ->
        atexit(task)

      %Runlet.Cmd.Sh{
        task: task,
        stream_pid: stream_pid
      } ->
        Process.unlink(stream_pid)
        Kernel.send(stream_pid, :halt)
        Process.exit(stream_pid, :kill)
        atexit(task)
    end

    Stream.resource(
      startfun,
      resourcefun,
      endfun
    )
  end

  defp stdio(
         cmd,
         %Runlet.Cmd.Sh{
           task: task,
           sh: sh,
           stream_pid: stream_pid,
           status: :running,
           err: nil
         } = state
       ) do
    receive do
      :runlet_eof ->
        case :prx.eof(task, sh) do
          :ok ->
            {[], state}

          # subprocess already exited
          {:error, :esrch} ->
            {[], state}

          {:error, _} ->
            {:halt, state}
        end

      {:stdout, ^sh, stdout} ->
        :prx.setcpid(sh, :flowcontrol, 1)

        {[
           %Runlet.Event{
             query: cmd,
             event: %Runlet.Event.Stdout{
               service: "",
               description: stdout
             }
           }
         ], state}

      {:stderr, ^sh, stderr} ->
        :prx.setcpid(sh, :flowcontrol, 1)

        {[
           %Runlet.Event{
             query: cmd,
             event: %Runlet.Event.Stdout{
               service: "stderr",
               description: stderr
             }
           }
         ], state}

      # writes to stdin are asynchronous: errors are returned
      # as messages
      {:stdin, ^sh, error} ->
        {[
           %Runlet.Event{
             query: cmd,
             event: %Runlet.Event.Stdout{
               service: "stderr",
               description: "#{inspect(error)}"
             }
           }
         ], %{state | status: :flush}}

      {:signal, _, _, _} ->
        {[], state}

      # Discard if reading stdin from a stream
      {:runlet_stdin, stdin} ->
        :ok =
          case state.stream_pid do
            nil -> :prx.stdin(sh, stdin)
            _ -> :ok
          end

        {[], state}

      # Forward signal to container process group
      {:runlet_signal, sig} ->
        case :prx.pidof(sh) do
          :noproc ->
            {:halt, state}

          pid ->
            _ = :prx.kill(task, pid * -1, to_signal(sig))
            {[], state}
        end

      %Runlet.Event{event: %Runlet.Event.Signal{}} = e ->
        Kernel.send(stream_pid, :ok)
        {[e], state}

      %Runlet.Event{} = e ->
        :ok = :prx.stdin(sh, "#{Poison.encode!(e)}\n")
        Kernel.send(stream_pid, :ok)
        {[], state}

      {:exit_status, ^sh, status} ->
        {[
           %Runlet.Event{
             query: cmd,
             event: %Runlet.Event.Stdout{
               service: "exit_status",
               description: "#{status}"
             }
           }
         ], %{state | status: :flush}}

      {:termsig, ^sh, sig} ->
        {[
           %Runlet.Event{
             query: cmd,
             event: %Runlet.Event.Stdout{
               service: "termsig",
               description: "#{sig}"
             }
           }
         ], %{state | status: :flush}}
    end
  end

  defp stdio(_cmd, %Runlet.Cmd.Sh{status: :running} = state), do: {:halt, state}

  defp stdio(
         cmd,
         %Runlet.Cmd.Sh{
           task: task,
           sh: sh,
           stream_pid: nil,
           status: :flush
         } = state
       ) do
    flush_timeout =
      case :prx.pidof(sh) do
        :noproc ->
          0

        pid ->
          _ =
            case :prx.kill(task, pid * -1, :SIGKILL) do
              {:error, :esrch} ->
                :prx.kill(task, pid, :SIGKILL)

              _ ->
                :ok
            end

          :infinity
      end

    stdio(cmd, %{state | status: :flushing, flush_timeout: flush_timeout})
  end

  defp stdio(
         cmd,
         %Runlet.Cmd.Sh{
           stream_pid: stream_pid,
           status: :flush
         } = state
       ) do
    Process.unlink(stream_pid)
    Kernel.send(stream_pid, :halt)
    Process.exit(stream_pid, :kill)

    stdio(cmd, %{state | stream_pid: nil})
  end

  defp stdio(
         cmd,
         %Runlet.Cmd.Sh{
           sh: sh,
           stream_pid: nil,
           status: :flushing,
           flush_timeout: flush_timeout
         } = state
       ) do
    receive do
      :runlet_eof ->
        {[], state}

      {:stdout, ^sh, stdout} ->
        {[
           %Runlet.Event{
             query: cmd,
             event: %Runlet.Event.Stdout{
               service: "",
               description: stdout
             }
           }
         ], state}

      {:stderr, ^sh, stderr} ->
        {[
           %Runlet.Event{
             query: cmd,
             event: %Runlet.Event.Stdout{
               service: "stderr",
               description: stderr
             }
           }
         ], state}

      {:stdin, ^sh, _} ->
        {[], state}

      {:signal, _, _, _} ->
        {[], state}

      {:runlet_stdin, _} ->
        {[], state}

      {:runlet_signal, _} ->
        {[], state}

      %Runlet.Event{event: %Runlet.Event.Signal{}} = e ->
        {[e], state}

      %Runlet.Event{} ->
        {[], state}

      {:exit_status, ^sh, status} ->
        {[
           %Runlet.Event{
             query: cmd,
             event: %Runlet.Event.Stdout{
               service: "exit_status",
               description: "#{status}"
             }
           }
         ], %{state | flush_timeout: 0}}

      {:termsig, ^sh, sig} ->
        {[
           %Runlet.Event{
             query: cmd,
             event: %Runlet.Event.Stdout{
               service: "termsig",
               description: "#{sig}"
             }
           }
         ], %{state | flush_timeout: 0}}
    after
      flush_timeout ->
        {:halt, state}
    end
  end

  @spec fork(binary) :: {:ok, t} | {:error, atom}
  defp fork(cmd) do
    root = Runlet.Config.get(:runlet, :root, "priv/root")
    env = Runlet.Config.get(:runlet, :env, @env)
    exec = Runlet.Config.get(:runlet, :exec, "") |> to_charlist()

    uidmin = Runlet.Config.get(:runlet, :uidmin, 0xF0000000)

    uidfun =
      Runlet.Config.get(:runlet, :uidfun, fn uidmin ->
        :erlang.phash2(self(), 0xFFFF) + uidmin
      end)

    uid = uidfun.(uidmin)

    fstab =
      Runlet.Config.get(:runlet, :fstab, [])
      |> Enum.reject(fn t -> t == "" end)
      |> Enum.map(fn t -> t |> to_charlist end)

    _ = :prx.sudo(exec)

    with {:ok, task} <- :prx.fork(),
         {:ok, sh} <-
           :runlet_task.start_link(task,
             root: root,
             fstab: fstab,
             uid: uid
           ),
         true <- :prx.setcpid(sh, :flowcontrol, 1),
         :ok <- :prx.execve(sh, ["/bin/sh", "-c", cmd], env) do
      {:ok,
       %Runlet.Cmd.Sh{
         task: task,
         sh: sh
       }}
    end
  end

  defp atexit(nil) do
    :ok
  end

  defp atexit(task) do
    :prx.cpid(task)
    |> Enum.each(fn %{pid: pid} ->
      case :prx.kill(task, pid * -1, :SIGKILL) do
        {:error, :esrch} ->
          :prx.kill(task, pid, :SIGKILL)

        _ ->
          :ok
      end
    end)

    :prx.stop(task)
  end

  @spec to_signal(String.t()) ::
          :SIGCONT
          | :SIGHUP
          | :SIGINT
          | :SIGKILL
          | :SIGQUIT
          | :SIGSTOP
          | :SIGTERM
          | :SIGUSR1
          | :SIGUSR2
          | :SIGPWR
          | 0
  defp to_signal(<<"SIG", sig::binary>>), do: to_signal(String.downcase(sig))
  defp to_signal(<<"sig", sig::binary>>), do: to_signal(sig)
  defp to_signal("cont"), do: :SIGCONT
  defp to_signal("hup"), do: :SIGHUP
  defp to_signal("int"), do: :SIGINT
  defp to_signal("kill"), do: :SIGKILL
  defp to_signal("quit"), do: :SIGQUIT
  defp to_signal("stop"), do: :SIGSTOP
  defp to_signal("term"), do: :SIGTERM
  defp to_signal("usr1"), do: :SIGUSR1
  defp to_signal("usr2"), do: :SIGUSR2
  defp to_signal("pwr"), do: :SIGPWR
  defp to_signal(_), do: 0
end
