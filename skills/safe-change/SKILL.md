---
name: safe-change
description: Use for EVERY change on a self-hosted Linux server, even a one-line edit - editing a config file (nginx, Caddy, Apache, SSH, Samba, fstab, sysctl), upgrading or updating a Docker Compose stack or container image (docker compose pull / up), apt upgrades, installing packages, systemd units and timers, cron jobs, firewall rules. Also when the user asks for the commands or steps to make such a change. Backs up first, writes the exact rollback command before applying, verifies with a real check, logs the change; stops when there is no rollback.
license: MIT
metadata:
  pack: safe-homelab-ops
  version: 1.0.0
---

# Safe change

A change on a server you care about follows five steps, in this order. Do not skip or reorder them, even for "a
one-line fix". If the user asks you to hurry, keep the steps and make them short.

## 1. Say what will change
Write one short block before touching anything:

```
CHANGE: <what and why, one sentence>
TOUCHES: <files, units, containers, packages>
RISK: <GREEN / YELLOW / RED - see the risk-check skill if it is installed>
```

## 2. Back up exactly what will change
- Files: copy each file next to itself with a dated suffix, keeping owner and mode:
  `sudo cp -a /etc/foo/foo.conf /etc/foo/foo.conf.before-2026-10-02`
- Docker services: record the image the service runs now **by digest**, not only by tag:
  `docker inspect --format '{{.Image}}' <container>` and `docker compose config > compose.before-<date>.yaml`
- Packages: record the installed version: `dpkg-query -W <package>`
- Database or app data that a migration will rewrite: a real backup that you have restored at least once
  (see the restore-drill skill). A copy that was never restored is not a backup.

## 3. Write the rollback command FIRST
Before applying, write the exact command(s) that put everything back, for example:

```
ROLLBACK: sudo cp -a /etc/foo/foo.conf.before-2026-10-02 /etc/foo/foo.conf && sudo systemctl restart foo
```

Rules:
- The rollback must be concrete and copy-pasteable. "Revert the change" is not a rollback.
- If you cannot write a rollback (a one-way data migration, a firmware flash, deleting data, rotating a key that
  other machines use): **STOP. Tell the user what makes it one-way and ask before going on.**
- If the change can lock the user out (SSH config, firewall, VPN, network config, sudoers): also check the syntax
  first (`sudo sshd -t`, `sudo visudo -c`, `sudo nft -c -f <file>`), keep the current session open, and arrange
  an automatic undo when possible (for example a timer that restores the old file in 5 minutes unless cancelled).

## 4. Apply, then verify with a concrete check
- Apply the smallest change that does the job. One change at a time; do not bundle "while I am here" fixes.
- Verify with a check that can fail, and show its output:
  - service: `systemctl is-active foo` plus `journalctl -u foo -n 20 --no-pager` (look for errors, not just "active")
  - container: `docker ps --filter name=foo --format '{{.Status}}'` (wait for "healthy" when it has a health check)
  - web app: an HTTP request to its health endpoint from the server itself
  - config: the program's own test mode (`nginx -t`, `sshd -t`, `caddy validate`, ...)
- If verification fails: run the rollback, verify the rollback worked, then report. Do not stack a second fix on
  top of a failed first one without telling the user.
- Service or boot-related changes are only done after a reboot test (see the reboot-test skill), or after you have
  told the user that a reboot test is still open.

## 5. Record it
Append one line to the machine's change log (ask once where it is; a common place is `/root/CHANGELOG.md` or a
notes repo):

```
2026-10-02 14:05 foo: <what changed> | backup: <path> | rollback: <command> | verified: <check + result>
```

Keep the backup files until the user says the change is fine (at least a few days); then they may be cleaned up.

## When you only give the user commands to run
Use the same order in the answer, so the user has the rollback before they apply anything:
`CHANGE/TOUCHES/RISK` block -> 1. backup commands -> 2. `ROLLBACK:` command -> 3. apply -> 4. verify -> 5. log line.
Read-only "look first" commands (for example checking whether a setting already exists) come before step 1.

## Report to the user
End with: what changed, how it was verified (with the real output), the rollback command, and anything still open
(for example "reboot test not done yet").
