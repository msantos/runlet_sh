# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers
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

  test "pipe: send events to process stdin" do
    # http://127.0.0.1:8080/event/index?query=
    case System.fetch_env("RUNLET_QUERY_TEST_SERVER") do
      {:error, _} ->
        {:ok, skip: true}

      {:ok, ""} ->
        {:ok, skip: true}

      {:ok, server} ->
        uri = URI.parse(server)

        Application.put_env(:runlet, :riemann_host, uri.host)
        Application.put_env(:runlet, :riemann_port, "#{uri.port}")

        Application.put_env(
          :runlet,
          :riemann_url,
          URI.to_string(%URI{path: uri.path, query: uri.query})
        )

        # "state = \"expired\""
        query =
          "service ~= \"riemann\""
          |> Runlet.Cmd.Query.exec()
          |> Runlet.Cmd.Sh.exec("cat")
          |> Enum.take(1)

        assert [%Runlet.Event{}] = query
    end
  end

  test "pipe: send process stdout to process stdin" do
    result =
      Runlet.Cmd.Sh.exec("while :; do echo test; sleep 1; done")
      |> Runlet.Cmd.Sh.exec("cat")
      |> Enum.take(1)

    assert [
             %Runlet.Event{
               attr: %{},
               event: %Runlet.Event.Stdout{
                 description:
                   "{\"query\":\"while :; do echo test; sleep 1; done\",\"event\":{\"time\":\"\",\"service\":\"\",\"host\":\"\",\"description\":\"test\\n\"},\"attr\":{}}\n",
                 host: "",
                 service: "",
                 time: ""
               },
               query: "cat"
             }
           ] = result
  end

  test "pipe: enumerable to process stdin" do
    e = %Runlet.Event{
      event: %Runlet.Event.Stdout{
        service: "service",
        host: "host",
        description: "test"
      }
    }

    result = [e, e, e] |> Runlet.Cmd.Sh.exec("cat") |> Enum.to_list()

    # events may be merged into 1 event
    assert [
             %Runlet.Event{
               attr: %{},
               event: %Runlet.Event.Stdout{
                 description:
                   <<"{\"query\":\"\",\"event\":{\"time\":\"\",\"service\":\"service\",\"host\":\"host\",\"description\":\"test\"},\"attr\":{}}\n",
                     _::binary>>,
                 host: "",
                 service: "",
                 time: ""
               },
               query: "cat"
             }
             | _
           ] = result
  end

  test "mount: verify mount flags" do
    [e | _] = Runlet.Cmd.Sh.exec("mount") |> Enum.to_list()

    # [
    #   ["/dev/vdb", "on", "/", "type", "btrfs",
    #    "(ro,nosuid,relatime,discard,space_cache,user_subvol_rm_allowed,subvolid=425,subvol=/lxd/storage-pools/default/containers/test)"]
    # ]
    flags =
      e.event.description
      # split mount output into lines
      |> String.split("\n")
      # and each line into words
      |> Enum.map(fn x -> x |> String.split() end)
      # select the root directory mount point
      |> Enum.filter(fn x -> "/" == x |> Enum.at(2) end)
      # flatten to list from list of lists
      |> List.first()
      # mount flags are the last element of the list
      |> List.last()
      # split up the mount flags
      |> String.split([",", "(", ")"], trim: true)
      # select the mount flags being tested
      |> Enum.filter(fn
        "ro" -> true
        "nosuid" -> true
        _ -> false
      end)
      |> Enum.sort()

    assert ["nosuid", "ro"] = flags
  end
end
