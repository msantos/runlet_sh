defmodule RunletShTest do
  use ExUnit.Case
  doctest Runlet.Cmd.Sh

  test "process writing to stdout" do
    assert :ok = echo()
  end

  defp echo(), do: echo(1)

  defp echo(n) when n < 3 do
    case Runlet.Cmd.Sh.exec("echo test") |> Enum.take(1) do
      [%Runlet.Event{event: %Runlet.Event.Stdout{description: "error: eperm"}}] ->
        # try using sudo
        Application.put_env(:runlet, :exec, "sudo -n")
        flush()
        echo(n + 1)

      [%Runlet.Event{event: %Runlet.Event.Stdout{description: "error: enoent"}}] ->
        {:error, "/bin/sh not found: see README for test setup"}

      [%Runlet.Event{event: %Runlet.Event.Stdout{description: "test\n"}}] ->
        :ok

      error ->
        {:error, error}
    end
  end

  defp echo(_), do: {:error, :eperm}

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
