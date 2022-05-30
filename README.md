# RunletSh

Generate [runlets](https://github.com/msantos/runlet) from containerized
Unix processes.

## Installation

Add `runlet_sh` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:runlet_sh, github: "msantos/runlet_sh"}]
end
```

## Configuration

### UID/GID

The UID/GID of the containerized processes is selected from one of
65535 UIDs beginning from 0xF0000000. Systems may limit the maximum UID:
setting a UID above the limit will fail with `{:error, :einval}`.

#### config/config.exs: Set Minimum UID

To set a lower UID offset:

```
import Config

config :runlet,
  uidmin: 0x80000
```

### config/config.exs: Set Function to Select UID

```
import Config

config :runlet,
  uidfun: fn _uidmin -> 65577 end
```

## Test

### Privileges

```
youruser ALL = NOPASSWD: /path/to/runlet_sh/deps/prx/priv/prx
```

### Create chroot

```
mkdir -p priv/root/bin priv/root/sbin \
   priv/root/usr priv/root/lib priv/root/lib64 \
   priv/root/opt priv/root/tmp priv/root/home priv/root/proc
```
