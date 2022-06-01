defmodule Runlet.Cmd.Sh do
  @moduledoc "Run Unix processes in a container"

  defstruct task: nil,
            sh: nil,
            err: nil

  @type t :: %__MODULE__{
          task: pid | nil,
          sh: pid | nil,
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

          {:runlet_signal, "SIGALRM"} ->
            {[
               %Runlet.Event{
                 query: cmd,
                 event: %Runlet.Event.Signal{description: "SIGALRM"}
               }
             ], state}

          # Forward signal to container process group
          {:runlet_signal, sig} ->
            case :prx.pidof(sh) do
              :noproc ->
                Kernel.send(self(), :runlet_exit)

                {[
                   %Runlet.Event{
                     query: cmd,
                     event: %Runlet.Event.Signal{
                       description: "#{sig}: {:error, :esrch}"
                     }
                   }
                 ], state}

              pid ->
                retval = :prx.kill(sh, pid * -1, to_signal(sig))

                {[
                   %Runlet.Event{
                     query: cmd,
                     event: %Runlet.Event.Signal{
                       description: "#{sig}: #{inspect(retval)}"
                     }
                   }
                 ], state}
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

  @doc false
  @spec exec(Enumerable.t(), binary) :: Enumerable.t()
  def exec(stream, cmd) do
    startfun = fn ->
      case fork(cmd) do
        {:ok, state} -> state
        {:error, error} -> %Runlet.Cmd.Sh{err: error}
      end
    end

    transformfun = fn
      %Runlet.Event{event: %Runlet.Event.Signal{}},
      %Runlet.Cmd.Sh{
        sh: sh,
        err: nil
      } = state ->
        {event(sh, cmd), state}

      %Runlet.Event{event: %Runlet.Event.Signal{}}, %Runlet.Cmd.Sh{} = state ->
        {:halt, state}

      %Runlet.Event{} = e,
      %Runlet.Cmd.Sh{
        sh: sh,
        err: nil
      } = state ->
        :ok = :prx.stdin(sh, "#{Poison.encode!(e)}\n")
        {event(sh, cmd), state}

      %Runlet.Event{},
      %Runlet.Cmd.Sh{
        err: err
      } = state ->
        {[
           %Runlet.Event{
             query: cmd,
             event: %Runlet.Event.Stdout{
               service: "stderr",
               description: "error: #{err}"
             }
           }
         ], state}
    end

    endfun = fn %Runlet.Cmd.Sh{
                  task: task
                } ->
      atexit(task)
    end

    stream
    |> Stream.transform(
      startfun,
      transformfun,
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
    _ =
      Enum.map(:prx.cpid(task), fn %{pid: pid} ->
        case :prx.kill(task, pid * -1, :SIGKILL) do
          {:error, :esrch} ->
            :prx.kill(task, pid, :SIGKILL)

          _ ->
            :ok
        end
      end)

    :prx.stop(task)
  end

  @spec event(pid, binary) :: Enumerable.t()
  defp event(sh, cmd), do: event(sh, cmd, [])

  defp event(sh, cmd, x) do
    receive do
      {:stdin, {:error, {:eagain, _}}} ->
        Kernel.send(self(), :runlet_exit)

        Enum.reverse([
          %Runlet.Event{
            query: cmd,
            event: %Runlet.Event.Stdout{
              service: "termsig",
              description: "sigpipe"
            }
          }
          | x
        ])

      {:stdout, ^sh, stdout} ->
        :prx.setcpid(sh, :flowcontrol, 1)

        event(sh, cmd, [
          %Runlet.Event{
            query: cmd,
            event: %Runlet.Event.Stdout{
              service: "",
              description: stdout
            }
          }
          | x
        ])

      {:stderr, ^sh, stderr} ->
        :prx.setcpid(sh, :flowcontrol, 1)

        event(sh, cmd, [
          %Runlet.Event{
            query: cmd,
            event: %Runlet.Event.Stdout{
              service: "stderr",
              description: stderr
            }
          }
          | x
        ])

      {:exit_status, ^sh, status} ->
        Kernel.send(self(), :runlet_exit)

        event(sh, cmd, [
          %Runlet.Event{
            query: cmd,
            event: %Runlet.Event.Stdout{
              service: "exit_status",
              description: "#{status}"
            }
          }
          | x
        ])

      {:termsig, ^sh, sig} ->
        Kernel.send(self(), :runlet_exit)

        event(sh, cmd, [
          %Runlet.Event{
            query: cmd,
            event: %Runlet.Event.Stdout{
              service: "termsig",
              description: "#{sig}"
            }
          }
          | x
        ])
    after
      0 ->
        _ = :timer.send_after(1_000, {:runlet_signal, "SIGALRM"})
        Enum.reverse(x)
    end
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
