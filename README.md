# safe-homelab-ops - Agent Skills for careful changes on your home server

Six small [Agent Skills](https://agentskills.io) (`SKILL.md` files) that teach an AI coding agent - Claude Code,
Codex CLI, OpenCode and other agents that read SKILL.md - to work on a self-hosted Linux server the way a careful
admin does: rollback first, backups proven by a restore, a reboot test after service changes, secrets never printed.

Most skill packs teach an agent *how to build things*. This one is about *not breaking the box you already have*.

| Skill | What the agent does with it |
|---|---|
| `safe-change` | Backs up what it will change, writes the exact rollback command **before** applying, verifies with a real check, logs the change. Stops and asks when there is no rollback. |
| `restore-drill` | Proves a backup by restoring it into a scratch folder and comparing - never over live data. |
| `reboot-test` | Snapshots units, timers, containers, listening sockets and mounts before a reboot and reports what did not come back (helper scripts included). |
| `secret-hygiene` | Handles keys and passwords without ever printing them; scans folders or staged git changes for leaked secrets without showing them (helper script included). |
| `process-match-safety` | Avoids the `pgrep -f` / `pkill -f` self-match trap, kills only what it listed first, puts a timeout on every wait loop. |
| `risk-check` | Sorts every action into GREEN / YELLOW / RED and asks you before anything that deletes, exposes, spends or leaves the machine. |

## Install

Copy the skill folders where your agent looks for skills:

```bash
git clone https://github.com/localhavenstore/safe-homelab-ops-skills
# Claude Code - for all your projects:
mkdir -p ~/.claude/skills && cp -r safe-homelab-ops-skills/skills/* ~/.claude/skills/
# Codex CLI (and other agents that read .agents/skills) - per project, from the project root:
mkdir -p .agents/skills && cp -r /path/to/safe-homelab-ops-skills/skills/* .agents/skills/
# OpenCode - reads ~/.claude/skills and .agents/skills too, or its own folder:
mkdir -p ~/.config/opencode/skills && cp -r safe-homelab-ops-skills/skills/* ~/.config/opencode/skills/
```

Then add the short block from [`AGENTS-snippet.md`](AGENTS-snippet.md) to your agent's instructions file -
`~/.claude/CLAUDE.md` or the project's `CLAUDE.md` for Claude Code, `AGENTS.md` for Codex and OpenCode - and restart
the agent session.

Why the snippet: agents pick skills from their descriptions, but in our tests a small model often answered "show me
the container's env vars" from memory without loading any skill - and printed every password. The snippet maps
task types to skills and carries the one rule that must always hold (never print secret values). You can also
ask directly: "use the reboot-test skill".

Helper scripts are plain bash with `--help` and need only standard tools (`systemctl`, `ss`, `findmnt`, `grep`,
optionally `docker` and `git`):

```bash
sudo bash ~/.claude/skills/reboot-test/scripts/snapshot.sh --label before
sudo systemctl reboot
sudo bash ~/.claude/skills/reboot-test/scripts/snapshot.sh --label after
sudo bash ~/.claude/skills/reboot-test/scripts/compare.sh          # PROBLEM / INFO lines, exit 1 on problems
bash ~/.claude/skills/secret-hygiene/scripts/scan.sh --staged      # before a commit; never prints the secret
```

## Update and uninstall

- **Update:** `git -C safe-homelab-ops-skills pull`, then copy the skill folders again the same way (it overwrites
  the six folders only). The version is in `VERSION`; changes are listed in `CHANGELOG.md`.
- **Uninstall:** delete the six folders (`safe-change`, `restore-drill`, `reboot-test`, `secret-hygiene`,
  `process-match-safety`, `risk-check`) from the skills folder you copied them to, and remove the snippet block
  from `CLAUDE.md` / `AGENTS.md`. Optional: `~/.local/state/reboot-test` (or `/root/.local/state/reboot-test`)
  holds the reboot snapshots.

## FAQ

**Does anything run automatically?** No. The skills are instructions; the helper scripts run only when you or your
agent start them, and your agent's normal permission prompts still apply.

**Will my agent ask me more questions?** For risky things (deleting, exposing, secrets, reboots) - yes, once, with
the facts. For read-only work nothing changes.

**Do I need Docker?** No. `reboot-test` skips the container part when Docker is not installed and says so.

**Does it work on Debian / Raspberry Pi OS / Proxmox?** The scripts need bash, systemd and the usual tools (`ss`,
`findmnt`), so they should; we tested on Ubuntu 24.04 only.

**The reboot test says PROBLEM for something I stopped on purpose.** Then it is right that it did not come back -
disable it (`systemctl disable`) or ignore that line. Run `compare.sh --help` for what each line means.

**Can I use only some of the skills?** Yes, copy only the folders you want and keep only their lines in the snippet.

## Tested with

Every release is tested before it is published (results in this repository):

- **Helper scripts** - 43 local tests (`scan.sh` with planted test secrets, `compare.sh` with clean and broken
  snapshots) and a test on a **fresh Ubuntu 24.04 VM with real reboots**: a clean reboot (enabled service,
  container with a restart policy, `fstab` loop mount with `nofail`) gives `RESULT: PASS`; a broken one (a service
  started but never enabled, a container without a restart policy) reports exactly those two problems. The
  `secret-hygiene` "names only" Docker command was checked there too, against a container with a planted value.
- **Skills** - 12 scenarios (2 per skill) x 3 runs through **Claude Code** with **Claude Haiku 4.5**, answer-only
  (no command was executed), with the documented install vs. the same prompts without the skills:
  see [`evals/RESULTS.md`](evals/RESULTS.md) for the numbers, [`evals/scenarios.json`](evals/scenarios.json)
  for the prompts and pass rules, and [`evals/results.json`](evals/results.json) for every answer. We only claim what we ran.
- Codex CLI and OpenCode read the same SKILL.md format; we have not run the scenario evals with them yet.

## Safety notes

- The skills are instructions. Your agent's own permission prompts and sandbox still apply - keep them on.
  The skills make the agent ask *more* often, never less.
- The helper scripts make no network connections, change nothing on the system (they only read, and
  `snapshot.sh` writes into its own state folder `~/.local/state/reboot-test`), and are short enough to read in a
  few minutes. Please read them before running them with `sudo` - that is good practice for any script.
- `scan.sh` finds common secret formats only. "No findings" does not prove there is no secret.
- Third-party skills can contain hidden instructions. This repository is checked on every release for invisible
  Unicode characters and network commands in scripts; check any skill you install, including these.

## More

These skills come from the rules of a real private home AI server that runs every day. The full build - local
model, voice, phone approvals, tool gateway, secrets, backups that restore - is a step-by-step course with tested
templates; chapters 1 and 2 are free at **https://localhavenstore.github.io**.
The tools we tested for it (and the ones we did not keep) are listed in
[awesome-private-home-ai](https://github.com/localhavenstore/awesome-private-home-ai).

Made with AI assistance; every skill and script is tested as described under "Tested with".
Not affiliated with Anthropic, OpenAI or the OpenCode project. MIT licence - see `LICENSE`.
