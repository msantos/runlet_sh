defmodule RunletShTest do
  use ExUnit.Case
  doctest Runlet.Cmd.Sh

  test "sh: exec process writing to stdout" do
    assert :ok = sh("echo test", "test\n")
  end

  test "sh: set UID/GID" do
    uidmin = Runlet.Config.get(:runlet, :uidmin, 0xF0000000)

    Application.put_env(:runlet, :uidmin, 65577)
    assert {:error, {{:expected, _}, {:got, uidstr}}} = sh("id -u", "65577\n")
    uid = String.to_integer(String.trim(uidstr))
    assert uid >= 65577 and uid < 65577 + 0xFFFF
    Application.put_env(:runlet, :uidmin, uidmin)

    Application.put_env(:runlet, :uidfun, fn _uidmin -> 65578 end)
    assert :ok = sh("id -a", "uid=65578 gid=65578 groups=65578\n")
    Application.delete_env(:runlet, :uidfun)
  end

  defp sh(cmd, output), do: sh(cmd, output, 1)

  defp sh(cmd, output, n) when n < 3 do
    case Runlet.Cmd.Sh.exec(cmd) |> Enum.take(1) do
      [%Runlet.Event{event: %Runlet.Event.Stdout{description: "error: eperm"}}] ->
        # try using sudo
        Application.put_env(:runlet, :exec, "sudo -n")
        flush()
        sh(cmd, output, n + 1)

      [%Runlet.Event{event: %Runlet.Event.Stdout{description: "error: enoent"}}] ->
        {:error, "/bin/sh not found: see README for test setup"}

      [%Runlet.Event{event: %Runlet.Event.Stdout{description: ^output}}] ->
        :ok

      [%Runlet.Event{event: %Runlet.Event.Stdout{description: description}}] ->
        {:error, {{:expected, output}, {:got, description}}}

      error ->
        {:error, error}
    end
  end

  defp sh(_, _, _), do: {:error, :eperm}

  defp flush() do
    receive do
      :runlet_exit ->
        flush()
    after
      0 ->
        :ok
    end
  end
end
