#!/usr/bin/env bash
# compare.sh - compare two snapshots made by snapshot.sh (read-only).
# Part of the reboot-test skill (safe-homelab-ops, MIT).
# Exit: 0 = no problems, 1 = problems found, 2 = usage error.
set -euo pipefail
export LC_ALL=C   # stable sort order for sort/comm

usage() {
  cat <<'EOF'
Usage: compare.sh [--dir DIR] [BEFORE_SNAPSHOT AFTER_SNAPSHOT]
  Without snapshot paths: compares the two newest snapshots in DIR
  (default: $XDG_STATE_HOME/reboot-test or ~/.local/state/reboot-test).
  PROBLEM lines: new failed units, services/timers/containers/listening sockets/mounts that were there before and
  are gone, containers that became unhealthy or stopped. INFO lines: things that are new after the reboot.
  Exit 0 = no problems, 1 = problems, 2 = usage error.
EOF
}

DIR=${XDG_STATE_HOME:-$HOME/.local/state}/reboot-test
ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --dir) DIR=${2:?--dir needs a value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if [[ ${#ARGS[@]} -eq 2 ]]; then
  A=${ARGS[0]}; B=${ARGS[1]}
elif [[ ${#ARGS[@]} -eq 0 ]]; then
  [[ -d $DIR ]] || { echo "no snapshot folder: $DIR" >&2; exit 2; }
  # the two newest by the time recorded inside each snapshot (folder names can tie within one second)
  mapfile -t snaps < <(for d in "$DIR"/[0-9]*/; do [[ -f $d/meta.txt ]] && printf '%s %s\n' "$(sed -n 's/^epoch: //p' "$d/meta.txt")" "${d%/}"; done | sort -n | tail -2 | cut -d' ' -f2-)
  [[ ${#snaps[@]} -eq 2 ]] || { echo "need two snapshots in $DIR (run snapshot.sh before and after)" >&2; exit 2; }
  A=${snaps[0]}; B=${snaps[1]}
else
  usage >&2; exit 2
fi
FILES=(meta failed-units active-services active-timers enabled-units containers listening mounts)
for s in "$A" "$B"; do
  for f in "${FILES[@]}"; do
    [[ -f $s/$f.txt && ! -L $s/$f.txt ]] || { echo "incomplete snapshot: $s ($f.txt missing) - make a new one" >&2; exit 2; }
  done
  grep -q '^boot_id: ' "$s/meta.txt" || { echo "not a snapshot: $s" >&2; exit 2; }
done

PROBLEMS=0
problem() { echo "PROBLEM $*"; PROBLEMS=$((PROBLEMS + 1)); }
info() { echo "INFO    $*"; }
meta() { sed -n "s/^$1: //p" "$2/meta.txt"; }
# lines only in the first file / only in the second (both sorted)
only_in() { comm -23 <(sort -u "$1") <(sort -u "$2"); }

echo "before: $A"
echo "after:  $B"
if [[ $(meta boot_id "$A") == "$(meta boot_id "$B")" ]]; then
  problem "no reboot happened between the two snapshots (same boot id) - this is not a reboot test"
fi
st=$(meta system_state "$B")
[[ $st == running ]] || problem "system state after: ${st:-unknown} (expected running)"

while read -r u; do [[ -n $u ]] && problem "unit failed after the reboot (was not failed before): $u"; done < <(only_in "$B/failed-units.txt" "$A/failed-units.txt")
while read -r u; do [[ -n $u ]] && info "unit no longer failed: $u"; done < <(only_in "$A/failed-units.txt" "$B/failed-units.txt")
# transient units (run-*, user sessions) and periodic jobs come and go by design: INFO only
transient() { [[ $1 =~ ^(run-|user@|user-runtime-dir@|session-|systemd-fsck@|apt-daily|man-db|fwupd-refresh|motd-news) ]]; }
names() { awk '{print $1}' "$1" | sort -u; }
# services: compared by name; columns 2-3 (sub-state, unit-file state) decide PROBLEM vs INFO
while read -r u; do
  [[ -n $u ]] || continue
  sub=""; ufs=""
  read -r _ sub ufs < <(awk -v n="$u" '$1 == n' "$A/active-services.txt") || true
  if transient "$u"; then info "service was active before, not after (transient/periodic): $u"
  elif [[ ${ufs:-} =~ ^(static|indirect|generated|transient|alias)$ ]]; then
    info "service was active before, not after ($ufs = started on demand or once, usually harmless): $u"
  else problem "service was active before, not after: $u${sub:+ (was $sub, ${ufs:-unknown})}"; fi
done < <(comm -23 <(names "$A/active-services.txt") <(names "$B/active-services.txt"))
while read -r u; do [[ -n $u ]] && info "service new after the reboot: $u"; done < <(comm -13 <(names "$A/active-services.txt") <(names "$B/active-services.txt"))
while read -r u; do
  [[ -n $u ]] || continue
  if transient "$u"; then info "timer was active before, not after (transient/periodic): $u"; else problem "timer was active before, not after: $u"; fi
done < <(only_in "$A/active-timers.txt" "$B/active-timers.txt")
while read -r u; do [[ -n $u ]] && info "timer new after the reboot: $u"; done < <(only_in "$B/active-timers.txt" "$A/active-timers.txt")
while read -r u; do
  [[ -n $u ]] || continue
  if transient "$u"; then info "no longer enabled (transient/periodic unit): $u"
  else problem "unit was enabled before, not after - it will not start on the next boot: $u"; fi
done < <(only_in "$A/enabled-units.txt" "$B/enabled-units.txt")

# containers: compare by name
skipA=$(grep -c '^SKIPPED' "$A/containers.txt" || true); skipB=$(grep -c '^SKIPPED' "$B/containers.txt" || true)
if (( skipA == 0 && skipB > 0 )); then
  problem "Docker worked before the reboot but not after ($(head -1 "$B/containers.txt")) - is the docker service running? (or the 'after' snapshot was not run as root)"
elif (( skipA > 0 )); then
  info "container check skipped ($(head -1 "$A/containers.txt"))"
else
  while read -r name st health _restart autorm _; do
    [[ -n $name ]] || continue
    after=$(awk -v n="$name" '$1 == n {print $2, $3}' "$B/containers.txt")
    if [[ -z $after ]]; then
      if [[ $st == running && ${autorm:-} == rm=true ]]; then info "one-off container (--rm) gone after the reboot: $name"
      elif [[ $st == running ]]; then problem "container gone after the reboot: $name"; fi
      continue
    fi
    read -r st2 health2 <<<"$after"
    if [[ $st == running && $st2 != running ]]; then problem "container $name: was running, now $st2"
    elif [[ $health2 == unhealthy && $health != unhealthy ]]; then problem "container $name: now unhealthy"
    elif [[ $health2 == starting && $health != starting ]]; then problem "container $name: health check still starting - wait a minute, then run snapshot.sh --label after and compare.sh again"
    fi
  done < "$A/containers.txt"
fi

# TCP listeners on fixed ports are services. UDP sockets and ports in the kernel's random (ephemeral) range change
# on every boot (VPN daemons, clients), so a missing one is only INFO.
EPH=$(cut -f1 /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null || echo 32768)
while read -r l; do
  [[ -n $l ]] || continue
  port=${l##*:}
  if [[ $l == tcp* && $port =~ ^[0-9]+$ ]] && (( port < EPH )); then problem "listening TCP socket gone: $l"
  else info "socket gone (UDP or random port, usually harmless): $l"; fi
done < <(only_in "$A/listening.txt" "$B/listening.txt" | grep -v '^SKIPPED' || true)
while read -r l; do [[ -n $l ]] && info "new listening socket: $l"; done < <(only_in "$B/listening.txt" "$A/listening.txt" | grep -v '^SKIPPED' || true)
while read -r l; do [[ -n $l ]] && problem "mount gone: $l"; done < <(only_in "$A/mounts.txt" "$B/mounts.txt")
while read -r l; do [[ -n $l ]] && info "new mount: $l"; done < <(only_in "$B/mounts.txt" "$A/mounts.txt")

if (( PROBLEMS == 0 )); then
  echo "RESULT: PASS - no problems after the reboot"
  exit 0
fi
echo "RESULT: FAIL - $PROBLEMS problem(s)"
exit 1
