---
name: risk-check
description: Use before running any command or making any change on a self-hosted server or home network that could delete data, expose a service, change access, touch secrets, cost money or leave the machine - docker prune, rm -r, volume removal, disk or partition tools, port forwarding, router and firewall changes, SSH/VPN/sudo changes, publishing, pushing, curl-pipe-sh - and when deciding how much testing and approval a change needs. Sorts actions into GREEN, YELLOW and RED; RED needs the user's explicit yes first.
license: MIT
metadata:
  pack: safe-homelab-ops
  version: 1.0.0
---

# Risk check

Size the care to the risk. Reading is cheap; deleting, exposing and spending are not. Decide the level BEFORE you
run anything, and say it in one line: `RISK: YELLOW - edits nginx config, backup + rollback ready`.

## Levels

**GREEN - read-only.** Looks, changes nothing: `ls`, `cat` of non-secret files, `systemctl status`, `journalctl`,
`docker ps`, `df`, `ss -tuln`, `git status`, dry runs (`--dry-run`, `-n`, `plan`).
- Go ahead. Still never print secrets (secret-hygiene skill).

**YELLOW - reversible change on this machine.** Editing a config, restarting or enabling a service, installing a
package from the distribution's repository, updating a container image that you can pin back, adding a cron/timer.
- Follow safe-change: backup, rollback written first, verify with a real check.
- Service or boot changes: reboot test before calling it done (reboot-test skill), with the user's OK for the reboot.
- Tell the user what you are about to change if they did not ask for exactly this change.

**RED - hard to undo, or reaches outside the machine.** Ask the user and wait for an explicit yes **before** each of:
- Deleting or overwriting data: `rm -r`, `docker volume rm`, `docker system prune -a --volumes`, `mkfs`,
  `dd`, `wipefs`, partitioning, `git push --force`, `DROP`/`TRUNCATE`, restoring over live data.
- Access and exposure: firewall/router/port-forward changes, SSH/VPN/sudoers changes, opening a service to the
  internet, changing users, groups or permissions on system paths.
- Secrets: creating, rotating, revoking or moving credentials and keys.
- Anything that leaves the machine or costs money: sending email/messages, posting, publishing, pushing to a
  public repository, paid API calls, purchases, DNS changes.
- Running code or scripts downloaded from the internet (`curl ... | sh`), adding new package repositories.
- Disabling a safety feature: backups, monitoring, updates, firewall, AppArmor/SELinux, a sandbox.
- Rebooting or shutting down a machine other people use.

**The user typing the command is not yet a yes.** People paste commands from forums without knowing what they
delete. For a RED command the user asked for (for example `docker system prune -a --volumes`, `rm -rf <dir>`,
`mkfs`), first run or show the read-only form that lists what it would hit, then ask once with the facts:

```
docker system df -v      # images, containers and volumes, with sizes
docker volume ls -f dangling=true   # the volumes --volumes would delete: their data is gone for good
```
"This would permanently delete N volumes (names...) and X GB of images. A safer first step is
`docker image prune -a` / `docker builder prune`, which frees space without touching data. Run the full command?"
Never add `--force`/`-f`/`-y` to skip the tool's own question unless the user said yes to this exact command.

For a RED action, say exactly what will happen, what cannot be undone, and the safer alternative if one exists
(for example "move to a trash folder instead of rm", "stop the container instead of removing the volume").
A yes for one RED action is not a yes for the next one.

## When unsure
- Not sure if it is reversible? Treat it as RED.
- A command touches many things at once (globs, `-r`, `--all`, `prune`)? Run the read-only listing form first and
  show what it would hit.
- Working on a machine you did not set up? Find out what runs there (services, containers, backups) before
  changing anything.

## Testing by risk
- GREEN: none.
- YELLOW: the verify check from safe-change; reboot test for service changes.
- RED: the above plus a written rollback or recovery plan, and a dry run or a test on a copy (a throwaway VM,
  container or a copy of the data) when one is possible.
