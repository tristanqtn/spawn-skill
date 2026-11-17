# When something fails

Read the message first — most of them name the cause and the fix. This file covers the
ones where the message is not enough, and the failures that look like something else.

## The thing failed and you suspect the network

Check `spawn_audit` (or `spawn audit <env>`) before concluding the tool is broken. Egress
is denied by default, and a denied connection surfaces as a timeout, a DNS failure, or a
TLS error — none of which say "a firewall stopped this".

An empty audit log means nothing was refused, so the network is genuinely not the
problem.

## A package will not resolve

Package names are **nixpkgs attributes**, not apt or brew names. nix's error names the
attribute it could not find. Common mismatches:

| You wanted | nixpkgs calls it |
|---|---|
| `python3-dev`, `python3-pip` | `python3` (pip is included) |
| `node` | `nodejs` |
| `rg` | `ripgrep` |
| `fd-find` | `fd` |
| `build-essential` | `gcc`, `gnumake` |
| `netcat` | `netcat-gnu` or `libressl.nc` |
| `dig` | `dnsutils` |

Search with `nix search nixpkgs <term>` on the host, or `spawn check` on a manifest,
which resolves every name against the pinned revision in seconds without building.

## "burpsuite has an unfree licence"

Set `allow_unfree = true` in the manifest. It is a manifest field rather than something
spawn sets for you because accepting an unfree licence is the user's decision and should
be visible in review. `burpsuite`, `wpscan` and `volatility3` need it.

An archived package that nixpkgs marks insecure needs `allow_insecure = ["<full-name>"]`
instead, naming the package exactly as the error does.

## podman or nix is missing

The error names the tool and how to install it, and points at `spawn doctor`. There is
nothing hidden behind it: spawn needs rootless podman and a nix store, and every command
that shells out refuses up front rather than failing halfway through.

`spawn doctor` checks the host and, given a manifest, checks that manifest against it.

## The build downloaded for ten minutes and then a later step failed

Run `spawn check` first. It validates every field, resolves every package, and verifies
every host path — including mount sources, device paths, secret sources and `files`
sources — **before** anything is fetched. A missing file named in `[secrets]` or
`[files]` is caught there rather than after the download.

## "It installed but it does not work"

Run `spawn smoke <suite>` ([cli.md](cli.md)). It builds the suite and runs every tool,
so it separates "this package is broken" from "I am calling it wrong" without you
having to guess.

Two findings from its first run are worth knowing because they look like tool bugs:

- **A tool needs something the container has no copy of.** `fping` exited
  `fping: icmp: unknown protocol` because the env had no `/etc/protocols`. Anything
  resolving a protocol or service by NAME hits the same wall. spawn now seeds both
  files, but the shape of the error -- a tool complaining about its own input -- is
  worth recognising.
- **A tool needs a driver the container does not get.** `hashcat` started, found zero
  devices and exited, because a container gets no GPU driver and nixpkgs ships the
  OpenCL loader without an implementation. The `creds` suite includes `pocl`, a CPU
  implementation, so it cracks on the CPU. For real speed, pass the GPU's devices
  through.

## A tool needs hardware or privileges the env does not have

Some suites say so themselves. `spawn profiles` and `spawn check` print each suite's
`note`: `recon` needs `caps = ["NET_RAW"]` or nmap's `-sS` fails, `wifi` needs a real
wireless interface, `osint` needs egress.

A profile never grants a capability on its own. That is deliberate -- privileges stay
in the manifest where they can be reviewed -- so the note is telling you what to add,
not describing what you already have.

## sshd rejects a password you know is right

Use a key. Public-key auth into an env works and password auth does not, however
correct the password is. Do not spend time on it -- all the obvious causes have been
eliminated:

- the hash is right (`crypt()` in the env reproduces it exactly) and sshd does read
  `/etc/shadow`;
- with `UsePAM no`, nixpkgs' sshd links libpam and **not** libcrypt, so it has nothing
  to compare a password with;
- with `UsePAM yes` and `pam_unix.so` by absolute path, PAM runs and returns
  "Authentication service cannot retrieve authentication info" -- and that persists
  with a readable `/etc/shadow` and with a setuid `unix_chkpwd`.

It is nixpkgs' OpenSSH/PAM packaging in a minimal environment, not the environment.

An ssh session also starts with sshd's `PATH`, not the profile's, so commands come back
"not found" until it is set. `SPAWN_PROFILE` is exported in the container and points at
the profile.

## A backgrounded process died

`podman exec` reaps its process group when it returns, so a listener started with `&`
inside a `spawn_exec` call does not survive the call. Use `nohup ... > /tmp/log 2>&1 &`,
or run whatever needs the listener in the same command.

## Two environments cannot reach each other

Published ports are not enough for a sustained flow. An environment sits behind pasta's
NAT, and a published UDP port will forward a handshake and then stop — which looks
exactly like a server bug. Put both environments on a shared podman network with
`[network] join = "..."`.

## The VPN came up but nothing works

Check both properties separately. `kill_switch` means nothing leaves except through the
tunnel; `route_all` means traffic actually goes through it. With the switch on and no
default route via the tunnel, the environment is simply offline — safe, and rarely what
was wanted. Both default to on.

An environment whose tunnel never came up is **sealed, not open**: the nftables policy
is installed before the client starts. So "no connectivity" after a failed VPN is the
designed behaviour, not a broken policy.

## The rootfs is on the wrong filesystem

On WSL2, an environment's filesystem must live on a Linux filesystem, not a Windows
drive mounted through drvfs or 9p — overlay semantics and permissions do not survive
them. spawn refuses with the filesystem type named. Keep environments under the Linux
home, not `/mnt/c`.

## CRIU, live migration, `podman commit`

None of these apply. An environment is an exploded rootfs with no base image, so
`podman commit` has nothing to commit; snapshots and forks are directory copies. A fork
is commit-then-start, never a live migration, and on WSL2 CRIU is unavailable anyway.
