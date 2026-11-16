# spawn-skill

The agent-facing half of [spawn](https://github.com/tristanqtn/spawn): a skill that
teaches an LLM agent when to reach for a disposable environment, and how to drive one.

spawn itself is a Go binary that builds environments from a declared tool list using nix
and rootless podman. This repo is only the instructions — it ships no code.

## Why it is a separate repo

The skill is a prompt, versioned against spawn's *behaviour* rather than its source. It
changes when a tool's contract changes, which is not the same cadence as the CLI's
commits, and it is useful to install on its own.

## Install

Needs spawn on `PATH` first — see the [main repo](https://github.com/tristanqtn/spawn).

**The skill**, for Claude Code:

```sh
git clone https://github.com/tristanqtn/spawn-skill ~/.claude/skills/spawn-sandbox
```

Or for a single project, clone it to `.claude/skills/spawn-sandbox` instead. The
directory name is what matters; Claude Code reads `SKILL.md` from it.

**The MCP server**, which is what the skill actually drives:

```sh
claude mcp add spawn -- spawn mcp
```

`spawn mcp` speaks newline-delimited JSON-RPC 2.0 over stdio, so any MCP client works —
nothing in it is Claude-specific.

Verify both:

```sh
spawn doctor          # the host has what spawn needs
claude mcp list       # spawn is connected
```

## What is in here

| File | For |
|---|---|
| `SKILL.md` | the agent. Loaded into context: when to use a sandbox, the loop, what it costs. |
| `reference/mcp-tools.md` | the agent. The eight tools' exact arguments and failure modes. |
| `reference/manifest.md` | the agent. The TOML schema, for work the MCP tools do not cover. |
| `reference/cli.md` | the agent. The CLI surface, for when MCP is not wired up. |
| `reference/troubleshooting.md` | the agent. Failures whose message is not enough. |

The split is deliberate. `SKILL.md` is what gets loaded every time, so it stays short and
says only what changes a decision; the reference files are read on demand and carry the
detail. `SKILL.md` links to each of them with the condition for reading it.

## Keeping it honest

`./check.sh` verifies the parts that can silently rot:

- the frontmatter has a `name` and a `description`
- every relative link in `SKILL.md` resolves to a file that exists
- every reference file is linked from `SKILL.md`, so nothing is orphaned
- every `spawn_*` tool named here exists in the binary, and every tool the binary has is
  documented (skipped when spawn is not installed)

CI runs it on every push. A skill that describes a tool which no longer exists is worse
than no skill, because the agent will call it.

## Licence

Same as spawn.
