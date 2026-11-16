---
name: spawn-sandbox
description: Run untrusted or destructive work in a disposable environment instead of on this machine. Use when about to execute code you did not write or have not read, install or try out a package, run a destructive or irreversible command, reproduce a bug that needs a specific toolchain, or test something that wants network access you would rather deny. Also use when asked to "try", "test", "check whether", or "see if" something works, where the answer is worth more than the environment it was found in.
---

# spawn: disposable environments

spawn builds an environment from a declared tool list, runs things in it, shows exactly
what changed, and throws it away. Its MCP tools are `spawn_create`, `spawn_exec`,
`spawn_diff`, `spawn_audit`, `spawn_snapshot`, `spawn_restore`, `spawn_list`,
`spawn_destroy`.

## When to reach for one

The test is not "is this dangerous". It is **"would I want this undone in one step?"**

Reach for a sandbox when:

- **You are about to run code you did not write or have not read.** A dependency's
  install script, a gist, a proof of concept from an issue thread.
- **You want to try a tool rather than adopt it.** Installing to find out whether it
  helps leaves the machine changed either way; in a sandbox the answer costs nothing.
- **The command is destructive or hard to reverse.** Anything recursive, anything that
  rewrites files in place, anything whose dry-run mode you are not certain about.
- **You need a toolchain this machine does not have,** or a different version of one it
  does. Installing a second Python is how a working machine stops working.
- **You are reproducing a bug** and the interesting part is the environment.
- **The work should not touch the network,** and you would like that enforced rather
  than promised.

Do **not** reach for one when the work is reading or editing files in the project you
were asked to work on. A sandbox cannot see the host filesystem, which is the point; it
is the wrong tool for a code change the user is waiting on.

## The loop

```
spawn_create  name="probe", tools=["python3", "curl"]
spawn_exec    name="probe", command="python3 suspect.py"
spawn_diff    name="probe"
spawn_destroy name="probe"
```

**Always finish with `spawn_diff` before you draw a conclusion, and `spawn_destroy`
when done.** The diff is the part that makes the exercise worth anything: it lists every
file the environment changed, so "the script worked" becomes "the script worked and also
wrote to three places nobody mentioned".

## Network access is denied by default

A new environment cannot reach the network at all. That is deliberate: a sandbox with
general network access is not a sandbox.

If the work genuinely needs the network, name the addresses:

```
spawn_create name="probe", tools=["curl"], allow=["1.1.1.1"]
```

Then use `spawn_audit` afterwards. It lists every destination the policy refused, so you
can tell the difference between "the script does not need the network" and "the script
tried to phone somewhere and was stopped". If a tool fails in a way that smells like
connectivity, check the audit log before assuming the tool is broken.

Package installation is the common case that needs this. Prefer declaring the tools in
`spawn_create` — they are fetched while the environment is built, so the environment
itself still needs no network.

## Snapshots, for a step you expect to go wrong

```
spawn_snapshot name="probe", tag="before-upgrade"
spawn_exec     name="probe", command="...the risky step..."
spawn_restore  name="probe", tag="before-upgrade"     # if it went badly
```

Restore discards everything after the snapshot and returns a running environment.

## What it costs

Almost nothing, and that should change how readily you use it. Environments built from
the same tool list share one copy on disk: measured at 232 MB shared between two
environments, with the second environment's own files coming to 3,264 bytes. Creating a
second sandbox to isolate a second question is cheaper than reasoning carefully about
whether the first one was contaminated.

Building a tool list the machine has not seen before does take time — it is fetching
packages. Reuse an existing environment with `spawn_exec` across several steps rather
than creating one per command; the filesystem persists between calls, so it is a
session.

## Reporting back

Say what you ran, what the diff showed, and what the audit showed if anything was
refused. "It worked" is not a result from a sandbox. "It worked, wrote only to
`/root/out.json`, and tried to reach `8.8.8.8`" is.

## Going further

Read these only when you need them — the loop above covers most work.

| File | Read it when |
|---|---|
| [reference/mcp-tools.md](reference/mcp-tools.md) | you need a tool's exact arguments, its failure mode, or the tool-suites `profiles` accepts |
| [reference/manifest.md](reference/manifest.md) | the work needs something the MCP tools do not expose: a host mount, a port, a capability, a VPN, secrets, resource limits |
| [reference/cli.md](reference/cli.md) | the MCP tools are not available and you are driving `spawn` as a command |
| [reference/troubleshooting.md](reference/troubleshooting.md) | a call failed and the message was not self-explanatory |
