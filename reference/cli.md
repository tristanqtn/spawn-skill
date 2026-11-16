# The CLI

Use this when the MCP tools are not wired up, or when the work needs a manifest feature
the MCP tools do not expose. The CLI is the full surface; the MCP tools are a deliberate
subset of it.

A command that takes a manifest defaults to `./spawn.toml`.

## Commands

| Command | What it does |
|---|---|
| `spawn init` | write a manifest and editable dotfiles here. `--force` overwrites. |
| `spawn up [manifest.toml\|<env>] [cmd...]` | build an environment and enter it. |
| `spawn check [manifest.toml]` | evaluate a manifest without building. |
| `spawn smoke [--keep] <suite>` | build a suite and run every tool in it. |
| `spawn ls` | list environments with their state. |
| `spawn stop <env>` | stop it, keeping the filesystem. |
| `spawn rm [--purge] <env>` | destroy it. `--purge` also deletes persisted data. |
| `spawn diff <env>` | every file the environment changed. |
| `spawn audit <env>` | destinations the egress policy refused. |
| `spawn snapshot <env> [tag]` | copy the filesystem aside. Tag defaults to a timestamp. |
| `spawn snapshots <env>` | list its snapshots. |
| `spawn restore <env> <tag>` | put a snapshot back. |
| `spawn fork <env> <new-name>` | copy an environment into a new one. |
| `spawn export <env> <file.tar.gz>` | write it to a portable archive. |
| `spawn import <file.tar.gz> [new-name]` | rebuild an environment from an archive. |
| `spawn doctor [manifest.toml]` | check the host, and a manifest against it. |
| `spawn profiles [--names]` | list the built-in suites. |
| `spawn completion <bash\|zsh\|fish>` | print a completion script. |
| `spawn mcp` | serve MCP over stdio. |
| `spawn version` | print the version. |

## `spawn up` takes either a manifest or a name

```
spawn up                  # ./spawn.toml
spawn up lab.toml         # that manifest
spawn up lab              # the env named lab, from anywhere
spawn up lab ls -la       # run a command in it instead of a shell
```

An argument ending in `.toml` is always a manifest path, never a name. A bare word is an
environment name if one exists, and otherwise a command for the default manifest.

`spawn up <name>` **attaches**: no nix build at all, and it starts a stopped
environment. It works after the manifest is gone, because the shell and profile are
recorded on the container. This is the quick way back into a box.

Running `spawn up` again on a changed manifest replaces the container and keeps the
filesystem — so you can iterate on a shell config against a live environment.

## Does the tool actually run?

`spawn check` proves an attribute resolves in nixpkgs. `spawn smoke` proves the tool
runs in a container, which is a different claim:

```
spawn smoke creds          # build the suite, run every tool, table of results
spawn smoke web --keep     # leave the env behind to investigate a failure
```

It builds a throwaway env with egress denied, runs each tool's check, and exits
non-zero if any failed. Every tool in every suite is covered: the suite's `[smoke]`
table, or a `command -v <attr>` default.

Reach for it when a tool behaves as if it is missing or broken and you want to know
whether the packaging or your usage is at fault. The answer is often neither:
`hashcat` needed an OpenCL implementation before it could crack anything, and `fping`
needed `/etc/protocols` to exist.

## Scripting it

`spawn profiles --names` is the parseable contract; the plain output has a header and a
rule and will change. Anything else you want to parse, parse from the environment
instead: `spawn ls` is for humans.

## What state exists

Container labels, and nothing else. There is no database and no state file to get out of
sync: `spawn.name`, `spawn.profile`, `spawn.manifest`, `spawn.shell`, and
`spawn.config`, which is a hash of the rendered create arguments and is how spawn knows
a manifest changed.

Consequently `podman` can see and operate on everything spawn made, and anything spawn
knows can be recovered with `podman inspect`.

## What export does not contain

The nix closure. An archive is the manifest plus whatever the environment wrote —
kilobytes, measured at 2,324 bytes for a real environment — because the manifest pins
the exact nixpkgs revision to rebuild the closure from. That is what pinning is for.

So an export is portable to any host with nix, and tiny. It is *not* portable to a host
without nix.
