defmodule Runlet.Cmd.Sh do
  @moduledoc "Run Unix processes in a container"

  defstruct task: nil,
            sh: nil,
            stream_pid: nil,
            err: nil

  @type t :: %__MODULE__{
          task: pid | nil,
          sh: pid | nil,
          stream_pid: pid | nil,
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

    resourcefun = fn
      %Runlet.Cmd.Sh{
        task: task,
        sh: sh,
        err: nil
      } = state ->
        receive do
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

          {:exit_status, ^sh, status} ->
            Kernel.send(self(), :runlet_exit)

            {[
               %Runlet.Event{
                 query: cmd,
                 event: %Runlet.Event.Stdout{
                   service: "exit_status",
                   description: "#{status}"
                 }
               }
             ], state}

          {:termsig, ^sh, sig} ->
            Kernel.send(self(), :runlet_exit)

            {[
               %Runlet.Event{
                 query: cmd,
                 event: %Runlet.Event.Stdout{
                   service: "termsig",
                   description: "#{sig}"
                 }
               }
             ], state}

          {:runlet_stdin, stdin} ->
            :ok = :prx.stdin(sh, stdin)
            {[], state}

          # Forward signal to container process group
          {:runlet_signal, sig} ->
            case :prx.pidof(sh) do
              :noproc ->
                Kernel.send(self(), :runlet_exit)
                {:halt, state}

              pid ->
                _ = :prx.kill(task, pid * -1, to_signal(sig))
                {[], state}
            end

          :runlet_exit ->
            {:halt, state}
        end

      %Runlet.Cmd.Sh{
        err: err
      } = state ->
        Kernel.send(self(), :runlet_exit)

        {[
           %Runlet.Event{
             query: cmd,
             event: %Runlet.Event.Stdout{
               service: "stderr",
               description: "error: #{err}"
             }
           }
         ], %{state | err: nil}}
    end

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

    resourcefun = fn
      %Runlet.Cmd.Sh{
        task: task,
        sh: sh,
        stream_pid: stream_pid,
        err: nil
      } = state ->
        receive do
          :runlet_eof ->
            case :prx.eof(task, sh) do
              :ok ->
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

          {:signal, _, _, _} ->
            {[], state}

          # Discard stdin not originating from the stream
          {:runlet_stdin, _} ->
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

          {:exit_status, ^sh, _status} ->
            {:halt, state}

          {:termsig, ^sh, _sig} ->
            {:halt, state}

          :runlet_exit ->
            {[], state}
        end

      %Runlet.Cmd.Sh{} = state ->
        {:halt, state}
    end

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
