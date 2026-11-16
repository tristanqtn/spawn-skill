# The eight MCP tools

Exact arguments, and what each one does when it fails. `name` is the environment's name
throughout: letters, digits, `.`, `_`, `+`, `-`. Nothing else — a name reaches a
container name, so a path separator or a leading dash is refused rather than quoted.

A tool that fails returns an error *result*, not a protocol error, so you will see the
reason as text and can act on it in the same loop.

## spawn_create

| Argument | Type | Meaning |
|---|---|---|
| `name` | string | **required.** The environment's name. |
| `tools` | string[] | nixpkgs package names, e.g. `["python3", "curl"]`. |
| `profiles` | string[] | built-in suites, merged with `tools` and deduplicated. |
| `allow` | string[] | addresses or CIDRs the environment may reach. Omit for no network. |

Egress is **denied** unless `allow` names something. The environment always gets
`bashInteractive`, `coreutils`, `cacert` and `nix`, so TLS works and a shell exists
without declaring them.

Creating an environment that already exists is not an error: spawn reuses it when the
tool list has not changed, and replaces the container while keeping the filesystem when
it has. So `spawn_create` is safe to call again rather than something to guard with
`spawn_list`.

**Built-in profiles:** `general`, `active-directory`, `web`, `ctf`, `forensics`.

A package name that nixpkgs does not have fails at build time with nix's own error,
which names the attribute. Package names are nixpkgs attributes, not apt names:
`python3` not `python3-dev`, `nodejs` not `node`, `ripgrep` not `rg`.

Unfree packages (`burpsuite`, `wpscan`) need a manifest, not this tool — see
[manifest.md](manifest.md).

## spawn_exec

| Argument | Type | Meaning |
|---|---|---|
| `name` | string | **required.** |
| `command` | string | **required.** A shell command, run through the environment's bash. |

Returns stdout, stderr and the exit status. The filesystem persists between calls, so
several `spawn_exec` calls are one session: `cd` does not carry over, but files do.

A command that backgrounds a process needs care — the exec's process group is reaped
when it returns, so a listener started with `&` dies. Start long-running things with
`nohup ... &` and a redirect, or run the thing that needs them in the same command.

## spawn_diff

Takes `name`. Lists every file the environment changed since it was created: added,
modified, deleted. A freshly created environment shows nothing, which is the baseline
that makes the rest meaningful.

It compares the whole tree by content hash, so a same-length edit is caught. It does not
follow symlinks out of the environment.

If the baseline is missing it says so rather than reporting the entire filesystem as
new.

## spawn_audit

Takes `name`. Lists the destinations the egress policy refused, with a count each.

An empty list means nothing was refused — which is a real result, not a missing one. It
distinguishes "this script does not use the network" from "this script tried and was
stopped". Destinations that were *allowed* do not appear.

## spawn_snapshot

| Argument | Type | Meaning |
|---|---|---|
| `name` | string | **required.** |
| `tag` | string | a label; defaults to a timestamp. |

Copies the filesystem aside. A tag containing a path separator is refused, and an
existing tag is refused rather than overwritten.

## spawn_restore

Takes `name` and `tag`, both required. Puts the snapshot back, discarding everything
since, and leaves a **running** environment — so the next `spawn_exec` works without a
create in between.

## spawn_list

No arguments. Every environment with its state, profile and name.

## spawn_destroy

Takes `name`. Removes the container and the filesystem. The container goes first, so a
failure to stop it aborts before anything is deleted — a destroy that reports success
has actually destroyed.

Directories the manifest declared as `persist` survive. Nothing else does.

## What these tools deliberately do not expose

Host mounts, published ports, capabilities, devices, VPNs, secrets and resource limits
are all real features, but reaching them means writing a manifest and using the CLI.
That is not an oversight: an agent-created environment that can mount the host or open a
port is not a sandbox any more. See [manifest.md](manifest.md) when the user asks for
one of those explicitly.
