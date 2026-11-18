# ai-dev-flow

[中文](README.md)

`ai-dev-flow` is a development-workflow skill for AI coding agents (Claude Code, Codex, and others). You decide three things only: **direction** (what you want), **taste** (whether results that need a human eye look right), and **one-way doors** (actions that cannot be undone). Building, proving, independent review, merging, and retrospectives are orchestrated by the skill.

Quality rests on machines, not on process or questions:

- **A project-owned verify command** decides right or wrong. Before merging, only the tests the diff touches run; the full suite runs in the background when the machine is idle.
- **One review by another vendor's model.** Writer and reviewer are different sessions; at most two rounds, otherwise split the item and redo it.
- **Measure the north star weekly** on real acceptance data, so a wrong direction shows up early.
- **Stop when the premise breaks.** When measured numbers show the approach does not work, the agent notifies you instead of piling on patches.

Reversible work is not paused to ask "should I?": the agent does it and shows the result; you can overturn it afterwards.

## How it works

| Tier | When | Who decides |
|---|---|---|
| Self-driving | Reversible, and verify can prove it | Merged according to the project's trust level |
| Take a look | Reversible, but a human must judge the result | You say "ok" before it merges |
| One-way door | Push, release, writing real data, deleting, external messages, spending, security settings | You authorize first |

Trust levels live in the project's `AGENTS.md`: L0 asks you every time (default), L1 stacks finished items for you to merge in a batch, L2 merges directly and you spot-check later. Only you change the level.

The agent comes to you only for: a one-way door, a result you need to look at, a direction choice, being stuck, or measured results that break the premise. Questions are batched into one message, each with a recommended answer.

Daily use is one command: `/next` works through the project queue (`docs/queue.md`) item by item — build, prove, review, merge — until it needs you, then stops and sends a notification. Answer with `/next #7 <reply>`.

## Layout

```
skills/ai-dev-flow/
  SKILL.md               entry point: tiers, when to ask, trust levels, reporting
  modules/               build, verify, land, diagnose, orchestrate, harness,
                         garden, direction, portfolio, hosts (read on demand)
  templates/             decision card, model table example
  scripts/               PowerShell helpers, see scripts/README.md
skills/next/SKILL.md     /next: work the queue until the user is needed
tests/                   script tests: pwsh -NoProfile -File tests/run-all.ps1
```

The rules are written in Chinese. Modern coding agents read them fine in any conversation language; the reports they write follow your language.

## Install

Tell Claude Code or Codex:

```
Install ai-dev-flow following <repo-url>/blob/main/INSTALL.md
```

The agent checks your environment, copies the files, links them into Claude Code, and confirms the install. It asks before overwriting anything already there, and asks you once about the optional extras: phone push, permission-prompt notifications, and a background full test run. The steps are in [INSTALL.md](INSTALL.md) if you prefer to install by hand. Use the same sentence to upgrade.

Scripts require Windows and PowerShell 7. The rules themselves are platform-neutral.

## License

MIT, see [LICENSE](LICENSE).
