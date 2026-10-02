---
name: process-match-safety
description: Use whenever a command would find, stop, kill or wait for a process by name or command line - a hung or stuck script or job, pkill, pgrep, killall, kill, 'ps aux | grep', wait-until-finished loops, timeouts around long jobs. Avoids the pgrep -f / pkill -f self-match trap, killing the wrong process, and wait loops that never end.
license: MIT
metadata:
  pack: safe-homelab-ops
  version: 1.0.0
---

# Process match safety

## The self-match trap
`pgrep -f backup.sh` searches the **full command line of every process** - including the shell that runs your
own command. When your command text contains `backup.sh` (for example `bash -c 'while pgrep -f backup.sh; do sleep 5; done'`),
pgrep finds your own shell and the loop waits forever. `pkill -f backup.sh` can kill your own shell or agent
session in the same way. `ps aux | grep backup` shows the grep itself for the same reason.

## Rules
1. **Bracket the first letter** in every `-f` pattern: `pgrep -f '[b]ackup.sh'`. The regex `[b]ackup.sh` matches
   the text `backup.sh` in other processes, but not the command line that contains `[b]ackup.sh` itself.
   Same for grep: `ps aux | grep '[b]ackup'`.
   This only removes the match on **your own pgrep command line**. A parent process can still contain the plain
   text - for example the agent or wrapper that was given the task "stop backup.sh", or a `bash -c "..."` that
   mentions it. So the bracket trick alone is never enough before a kill: also do rules 2 and 3.
   - Pattern starts with `-` or a regex character? Bracket a later plain letter: `pgrep -f -- '--confi[g] /etc/x'`.
   - Dots and other regex characters in names should be escaped when the exact text matters: `'[b]ackup\.sh'`.
2. **Prefer exact matches** when you know the program name: `pgrep -x nginx` matches the process name only
   (no command lines, no self-match). Or use the service manager: `systemctl is-active foo`,
   `docker ps --filter name=^foo$`. Or a PID file / `$!` of a job you started yourself.
3. **Look before you kill.** First list what matches, with full command lines: `pgrep -af '[b]ackup.sh'`.
   Kill only when the list is exactly what you expect, by PID, and never a PID of your own shell, its parents or
   the agent itself (check with `echo $$ $PPID` and `ps -o pid,ppid,args -p <pid>`). Never `pkill -f` a short or common word
   (`python`, `node`, `java`, `ssh`, `docker`, `sleep`): it hits unrelated work, including other users' and
   your own session.
4. **Kill gently first**: `kill <pid>` (SIGTERM), wait a few seconds, check again, then `kill -9` only for the
   PIDs that are still there - and say that you used it. Prefer `systemctl stop` / `docker stop` for services:
   a plain kill gets the process restarted or leaves state broken.
5. **Every wait loop has a timeout.** Never `while pgrep ...; do sleep 1; done` without an end:

```bash
deadline=$((SECONDS + 600))            # 10 minutes
while pgrep -f '[b]ackup.sh' >/dev/null; do
  (( SECONDS >= deadline )) && { echo "still running after 10 min - giving up"; exit 1; }
  sleep 5
done
```

   Or wrap the job itself: `timeout 600 ./backup.sh`, and check its exit code (124 = timed out).
6. **Do not kill what you did not start** without asking the user: a process you do not recognise may be their
   work, another person's job or a system service.

## Quick check
Before running a command with pgrep/pkill/killall/grep on processes, ask yourself: "Does my own command line
contain this pattern?" If yes, bracket it or use `-x`.
