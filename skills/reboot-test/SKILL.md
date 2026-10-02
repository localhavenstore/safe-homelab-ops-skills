---
name: reboot-test
description: Use after creating, installing or changing a systemd service, unit or timer, a Docker Compose stack, an /etc/fstab line or mount, network or boot settings, or a kernel update on a self-hosted Linux server - and whenever the user asks what else to do before calling such a change done. Checks the change will survive a reboot (enabled, restart policy, nofail, mount -a), then records state before a reboot, compares it after and reports what did not come back.
license: MIT
metadata:
  pack: safe-homelab-ops
  version: 1.0.0
---

# Reboot test

Many changes work until the next reboot: a service that was started by hand but never enabled, a container whose
restart policy is "no", a mount that is not in fstab, a unit that starts before the network or a disk is ready.
A change to a service is only done after it survived a real reboot.

## When
- After any change to services, units, timers, Compose stacks, mounts, network, kernel or boot settings.
- After a batch of package updates that touched the kernel, systemd, Docker or the network stack.
- Not needed for changes to plain data or documents.

## Steps
0. **First check the change is set up to survive a reboot** - these catch most problems without rebooting:
   - systemd service/timer: `sudo systemctl enable <unit>` (or `enable --now`), then `systemctl is-enabled <unit>`
     must say `enabled`; `systemd-analyze verify /etc/systemd/system/<unit>` shows unit file mistakes.
   - Docker Compose: every service has `restart: unless-stopped` (or `always`); `docker inspect --format
     '{{.HostConfig.RestartPolicy.Name}}' <container>` must not say `no`.
   - `/etc/fstab`: `sudo findmnt --verify`, then `sudo mount -a` (an error here would also stop the boot); add
     `nofail` (and for a USB disk `x-systemd.device-timeout=10s`) to disks that may be missing, so a missing disk
     cannot drop the machine into emergency mode; mount by `UUID=`, not `/dev/sdX`.
   - Kernel/boot changes: keep the previous kernel installed and know how to pick it in the boot menu.
   Then do the real reboot test below - the checks above do not prove the boot order works.
1. **Ask before rebooting.** A reboot stops everything on the machine (other people's sessions, running jobs,
   your own agent session if it runs there). Say how long it usually takes and wait for the user's OK. If the
   machine runs things other people use, suggest a quiet time.
2. **Snapshot before**, as root so Docker and all units are visible:
   `sudo bash scripts/snapshot.sh --label before`
   (records failed/active/enabled units, timers, containers with health, listening sockets and real mounts into
   `~/.local/state/reboot-test/`; read-only on the system).
   If something is already failed before the reboot, tell the user now - it is not caused by the reboot.
3. **Reboot** (the user does it, or you do it after their OK): `sudo systemctl reboot`.
4. **Snapshot after**, once the machine is back: `sudo bash scripts/snapshot.sh --label after`
   (it waits up to 5 minutes for boot to finish first).
5. **Compare**: `sudo bash scripts/compare.sh`
   - `PROBLEM` lines = something that was there before and is not now (a failed unit, a stopped service or
     container, an unhealthy container, a TCP listener on a fixed port, a mount). Exit code 1.
   - `INFO` lines = new things, or things that change on every boot: random ports, UDP sockets, transient units,
     "static" units that only run on demand or once (packagekit, ldconfig), one-off `--rm` containers. Read them,
     but they are not failures.
   - It also refuses a "reboot test" where no reboot happened (same boot id).
6. **Fix and repeat**: for each PROBLEM, find the cause (`systemctl status <unit>`, `journalctl -b -u <unit>`,
   `docker logs <container>`), fix it with the safe-change skill, and run the whole test again. The test passes
   only when compare.sh says `RESULT: PASS`.

## Common causes (check these first)
- Unit started with `systemctl start` but never `enable`d.
- Container restart policy missing (`restart: unless-stopped` or `always` in Compose).
- A unit needs the network or a disk: add `After=`/`Wants=network-online.target` or `RequiresMountsFor=<path>`.
- A mount only in the running system, not in `/etc/fstab` (use `nofail` for disks that may be missing).
- A secret or key that was only in memory (an unlocked keyring, an exported shell variable).
- Docker containers that depend on each other without `depends_on` + a health check.

## Report
Say PASS or FAIL, list each PROBLEM with its cause and the fix, and record the result in the change log
(`<date> reboot test after <change>: PASS`).
