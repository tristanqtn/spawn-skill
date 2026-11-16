# The manifest

A manifest is a TOML file — by convention `spawn.toml` — that declares an environment
completely. Everything an environment is comes from this file: there is no image to
build, no Containerfile, and no state kept anywhere else.

Reach for one when the work needs something the MCP tools do not expose: a host mount, a
published port, a capability, a device, a VPN, secrets, or resource limits. Write the
file, then drive it with the CLI ([cli.md](cli.md)).

Unknown fields are an error, not a warning. A typo'd key fails at `spawn check` rather
than being silently ignored.

## A minimal one

```toml
schema = 1
name = "lab"
tools = ["python3", "ripgrep"]
```

## Every field

### Identity and contents

| Field | Type | Default | Meaning |
|---|---|---|---|
| `schema` | int | — | **required**, must be `1`. |
| `name` | string | — | **required.** `[A-Za-z0-9][A-Za-z0-9_.+-]*`. Becomes the container name. |
| `tools` | string[] | `[]` | nixpkgs attribute names. |
| `profiles` | string[] | `[]` | built-in suites; `spawn profiles` lists them. Merged with `tools`, deduplicated. Some suites include others, and a tool reached twice still appears once. |
| `nixpkgs` | string | a pinned revision | a flake ref. Leave it alone unless you need a different nixpkgs; the default is a 40-char revision baked into the binary, which is what makes two hosts build the same closure. |
| `allow_unfree` | bool | `false` | permits unfree licences. `burpsuite` and `wpscan` need this. |
| `allow_insecure` | string[] | `[]` | per-package insecurity opt-in, by the package's full name. |

Every environment also gets `bashInteractive`, `coreutils`, `cacert` and `nix`, so a
shell exists and TLS works without declaring them.

### Runtime surface

| Field | Type | Default | Meaning |
|---|---|---|---|
| `workdir` | string | `/root` | where a shell starts. Must be absolute. |
| `env` | table | `{}` | environment variables. Keys must be valid shell identifiers. |
| `mounts` | string[] | `[]` | `host:container` or `host:container:ro`. A relative host path is resolved against the manifest. |
| `ports` | string[] | `[]` | `host:container` or `host:container/udp`. |
| `caps` | string[] | `[]` | Linux capabilities, e.g. `["NET_RAW", "NET_ADMIN"]`. |
| `devices` | string[] | `[]` | host device paths, e.g. `["/dev/net/tun"]`. |
| `persist` | string[] | `[]` | directories that survive `spawn rm` and a rebuild. |

`caps` and `devices` are deliberately visible rather than hidden behind convenience
flags, because the privilege an environment holds is exactly what is worth reviewing.
Without `NET_RAW`, `ping` fails at exec and nmap dies with `dnet: Failed to open device
eth0` — and neither error names the cause.

A host path that does not exist fails **before** the nix build, not after, so a typo
does not cost you a download.

### Limits

```toml
[limits]
cpus = "4"
memory = "8g"
pids = 1024
```

These map to cgroup controllers. On WSL2 `cpus`, `memory` and `pids` are delegated and
work; `io` is not delegated, which is why there is no `limits.io`.

### Hooks

```toml
[hooks]
post_start = ["service postgresql start"]
```

Commands run inside the environment after it starts. A failing hook fails `spawn up`.

### The shell

```toml
[shell]
use = "zsh"              # bash (default) or zsh
prompt = "starship"      # plain (default), starship, or exegol
history = true           # default; persists shell history
aliases = { ll = "eza -l --git", v = "nvim" }
init = '''
export EDITOR=nvim
bindkey -e
'''
```

`prompt = "exegol"` is a built-in Dracula rendering of the Exegol prompt
(`[Nov 16, 2026 - 18:45:06 (CET)] env-name /workspace #`) with no file to edit.
`prompt = "starship"` uses whatever `/root/.config/starship.toml` says, which you supply
through `files`.

Integrations follow the packages: declare `fzf`, `zoxide` or `direnv` and the generated
rc wires them; leave them out and it does not. `init` is appended verbatim, last, so it
overrides everything generated.

### Files

```toml
[files]
"/root/.tmux.conf"   = { from = "./dotfiles/tmux.conf" }
"/root/.config/nvim" = { from = "./dotfiles/nvim" }       # a directory works
"/root/.netrc"       = { content = "machine x login y", mode = "0600" }
```

Keyed by the path inside the environment. `from` is a host file or directory, `content`
is literal text, `mode` is octal and defaults to `0644`. These are copied in and
**writable**, so a tool that rewrites its own config still works.

A file shadowed by a mount is an error rather than a surprise.

### Secrets

```toml
[secrets]
vpn = "age:~/secrets/lab.ovpn.age"
token = "sops:~/secrets/api.yaml"
local = "file:~/secrets/plain.txt"
```

The value names an **encrypted** file on the host. spawn decrypts it into a tmpfs under
`$XDG_RUNTIME_DIR` at 0600 and bind-mounts it read-only at `/run/secrets/<name>`.

It never reaches `/nix/store`, which is world-readable and permanent, and never reaches
container metadata. `file:` exists for a secret you manage yourself; it is still kept out
of the store and the labels.

### Egress policy

```toml
[network]
egress = "deny"                       # allow (default), deny, or vpn
allow = ["1.1.1.1", "10.0.0.0/8", "udp:53"]
join = "labnet"                       # a podman network, for env-to-env traffic
```

`deny` installs an nftables default-drop output chain; `allow` entries are the
exceptions, as CIDRs, bare IPs, or `proto:port`. Refused destinations are recorded in a
dynamic set, which `spawn audit` reads.

`join` matters for anything that needs a sustained flow between two environments.
Without it an environment sits behind pasta's NAT and is reachable only through
published ports — fine for a shell, but a published UDP port forwards a VPN handshake and
then stops, so a VPN datapath between two environments needs `join`.

### VPN

```toml
[vpn]
kind = "openvpn"          # openvpn or wireguard
config = "secret:vpn"     # a secret handle, or a host path
kill_switch = true        # default
route_all = true          # default
dns = ["10.0.0.1"]
```

Declaring a VPN implies `egress = "vpn"`. The policy is installed **before** the client
starts — nftables matches an interface by name, so a rule can reference `tun0` before it
exists — which means an environment whose tunnel never comes up is sealed rather than
open.

`kill_switch` guarantees nothing leaves except through the tunnel. `route_all`
guarantees traffic actually goes through it. They are different properties: with the
switch on and no default route via the tunnel, an environment is simply offline.

Kernel WireGuard works rootless. There is a `wireguard-go` userspace fallback when the
module is unavailable.

## Packages spawn maintains itself

A few attributes are spawn's own build, layered over the pinned nixpkgs as an overlay.
This exists because "wait for nixpkgs" is not an answer when the tool is the job:
nixpkgs ships hashcat 7.1.2 on the pin *and* on unstable, while upstream released 8.0.0
on 2026-10-25.

`spawn check` names any that a manifest is using, under `spawn-maintained`. It matters
because the env is then not running stock nixpkgs, which is exactly the kind of thing
that should never be a surprise when a result is disputed.

An override applies only when the manifest actually resolved that attribute, so a
manifest that does not use one generates a byte-identical expression and rebuilds
nothing.

## Checking one

`spawn check` evaluates a manifest without building anything: it validates every field,
resolves every package name against the pinned nixpkgs, and verifies every host path
exists. Run it before `spawn up` on anything non-trivial — it is seconds, and it catches
the mistakes that otherwise surface after a long download.

`spawn doctor` does the same against the host as well, naming anything missing.
