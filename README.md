# RunletSh

Generate [runlets](https://github.com/msantos/runlet) from containerized
Unix processes.

## Installation

Add `runlet_sh` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:runlet_sh, git: "https://github.com/msantos/runlet_sh.git"}]
end
```

## Test

### Create chroot

```
mkdir -p priv/root/bin priv/root/sbin \
   priv/root/usr priv/root/lib priv/root/lib64 \
   priv/root/opt priv/root/tmp priv/root/home priv/root/proc
```
