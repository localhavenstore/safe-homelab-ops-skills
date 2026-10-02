---
name: restore-drill
description: Use when the user asks whether backups work or are OK, how to check, verify or test a backup, or when setting up or changing backups on a self-hosted server - restic, borg, tar, rsync, Proxmox/PBS, database dumps (pg_dump, mysqldump, SQLite), Docker volumes. Proves a backup by restoring it into a scratch folder or a separate throwaway database/container and comparing it - never over live data.
license: MIT
metadata:
  pack: safe-homelab-ops
  version: 1.0.0
---

# Restore drill

A backup counts only after a restore from it has worked. "The backup job finished" or "the file is 2 GB" proves
nothing. Do a restore drill after setting up a backup, after changing what it covers, and about once a month.

## Hard rules
- **Never restore over live data.** Restore into a new scratch folder (for example `/var/tmp/restore-drill-<date>`)
  or a throwaway VM/container. Check that the target folder is new and empty before restoring.
- Never print the backup password or key. Use the tool's password-file or environment option and say only that
  the key was found (see the secret-hygiene skill).
- Check free space first (`df -h <scratch-dir>`); stop if the restore would fill the disk.
- Restore the **newest** backup unless the user asks for another one: the newest one is the one they would need.

## Steps
1. **Find what is backed up**: read the backup job (script, systemd unit/timer, cron line) and list the sources it
   covers and what it excludes. Point out anything important that is NOT covered (databases copied as raw files
   while running, Docker volumes, `/etc`, secrets the restore would need).
2. **List the snapshots** and show the date of the newest one. Older than the schedule promises = report it.
3. **Restore** the newest snapshot (or a meaningful part of it) into the scratch folder:
   - restic: `restic -r <repo> --password-file <file> restore latest --target <scratch>` (always pass the password
     file or `RESTIC_PASSWORD_FILE`, so the command cannot hang on a password prompt; never print the file)
   - borg: `cd <scratch> && BORG_PASSCOMMAND='cat <passfile>' borg extract <repo>::<archive>`
   - Long restores: run them with a time limit (`timeout 2h ...`) and report if it was reached.
   - tar: `tar -xf <archive> -C <scratch>`
   - database dumps: load into a **new, separate** database or a throwaway container, never the live one.
4. **Compare** with something that can fail:
   - checksums of a sample of files vs the live files that did not change since the backup
     (`sha256sum`), or the tool's own check (`restic check --read-data-subset=5%`, `borg check`)
   - key files present and non-empty (configs, the database dump, documents the user cares about)
   - for a database: row counts of a few main tables, or the app starting against the restored copy
5. **Clean up** the scratch folder (show the exact path before removing it; never a path built from an empty
   variable).
6. **Record** one line in the change log or backup log:

```
2026-10-02 restore drill: snapshot <id/date> -> <scratch> | <N> files, sample checksums 20/20 match | db rows OK | PASS
```

## Report
Say PASS or FAIL with the evidence, the age of the newest backup, and the gaps you found (things not covered, a
missing off-site copy, no encryption, no automatic schedule). Suggest fixes; do not change the backup job without
following the safe-change skill.
