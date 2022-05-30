defmodule RunletShTest do
  use ExUnit.Case
  use Bitwise
  doctest Runlet.Cmd.Sh

  setup_all do
    stat = File.stat!(:prx_drv.progname())

    case stat.mode &&& 0o4000 do
      0 ->
        exec = Runlet.Config.get(:runlet, :exec, "sudo -n")
        Application.put_env(:runlet, :exec, exec)

      _ ->
        # binary is setuid
        :ok
    end
  end

  test "sh: exec process writing to stdout" do
    result = Runlet.Cmd.Sh.exec("echo test") |> Enum.take(1)

    assert [%Runlet.Event{event: %Runlet.Event.Stdout{description: "test\n"}}] =
             result
  end

  test "sh: set UID/GID" do
    uidmin = Runlet.Config.get(:runlet, :uidmin, 0xF0000000)

    Application.put_env(:runlet, :uidmin, 65577)

    assert [
             %Runlet.Event{
               event: %Runlet.Event.Stdout{
                 description: result
               }
             }
           ] = Runlet.Cmd.Sh.exec("id -u") |> Enum.take(1)

    uid = String.to_integer(String.trim(result))
    assert uid >= 65577 and uid < 65577 + 0xFFFF
    Application.put_env(:runlet, :uidmin, uidmin)

    Application.put_env(:runlet, :uidfun, fn _uidmin -> 65578 end)
    result = Runlet.Cmd.Sh.exec("id -a") |> Enum.take(1)

    assert [
             %Runlet.Event{
               event: %Runlet.Event.Stdout{
                 description: "uid=65578 gid=65578 groups=65578\n"
               }
             }
           ] = result

    Application.delete_env(:runlet, :uidfun)
  end
end
