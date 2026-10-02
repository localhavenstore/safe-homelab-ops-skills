#!/usr/bin/env bash
# snapshot.sh - record the state of this machine before/after a reboot (read-only; writes only into its state dir).
# Part of the reboot-test skill (safe-homelab-ops, MIT).
set -euo pipefail
export LC_ALL=C   # stable sort order for sort/comm

usage() {
  cat <<'EOF'
Usage: snapshot.sh [--dir DIR] [--wait SECONDS] [--label NAME]
  Records failed/active/enabled systemd units, timers, Docker containers (state + health), listening sockets and
  mounts into DIR/<time>-<label>/. Read-only on the system; writes only into DIR.
  --dir DIR       state folder (default: $XDG_STATE_HOME/reboot-test or ~/.local/state/reboot-test)
  --wait SECONDS  first wait until systemd finished booting (default 300; 0 = do not wait)
  --label NAME    short label, e.g. before or after (default: snap)
Run it once before the reboot and once after, then run compare.sh.
EOF
}

DIR=${XDG_STATE_HOME:-$HOME/.local/state}/reboot-test
WAIT=300
LABEL=snap
while [[ $# -gt 0 ]]; do
  case $1 in
    --dir) DIR=${2:?--dir needs a value}; shift 2 ;;
    --wait) WAIT=${2:?--wait needs a value}; shift 2 ;;
    --label) LABEL=${2:?--label needs a value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ $WAIT =~ ^[0-9]+$ ]] || { echo "--wait must be a number" >&2; exit 2; }
[[ $LABEL =~ ^[A-Za-z0-9_-]+$ ]] || { echo "--label: letters, digits, _ and - only" >&2; exit 2; }
command -v systemctl >/dev/null || { echo "systemctl not found: this script needs systemd" >&2; exit 2; }

if (( WAIT > 0 )); then
  # "running" or "degraded" both mean boot finished; degraded = some unit failed (recorded below).
  state=$(timeout "$WAIT" systemctl is-system-running --wait 2>/dev/null || true)
  [[ -n $state ]] || state=$(systemctl is-system-running 2>/dev/null || true)
else
  state=$(systemctl is-system-running 2>/dev/null || true)
fi

# State folder safety (this often runs as root): refuse a symlinked folder or one that other users can write to,
# and write each snapshot into a NEW private folder made by mktemp, so nothing can be redirected or overwritten.
umask 077
[[ -L $DIR ]] && { echo "refusing: $DIR is a symlink" >&2; exit 2; }
mkdir -p -- "$DIR"
[[ -d $DIR && ! -L $DIR ]] || { echo "refusing: $DIR is not a plain folder" >&2; exit 2; }
if [[ $(stat -c %u -- "$DIR") != "$(id -u)" ]] || (( 0$(stat -c %a -- "$DIR") & 022 )); then
  echo "refusing: $DIR must be owned by $(id -un) and not writable by group/others" >&2; exit 2
fi
OUT=$(mktemp -d -- "$DIR/$(date +%Y%m%d-%H%M%S)-$LABEL.XXXXXX")

{
  echo "time: $(date -Is)"
  echo "epoch: $(date +%s.%N)"
  echo "host: $(hostname)"
  echo "boot_id: $(cat /proc/sys/kernel/random/boot_id)"
  echo "kernel: $(uname -r)"
  echo "uptime_s: $(cut -d' ' -f1 /proc/uptime)"
  echo "system_state: $state"
} > "$OUT/meta.txt"

units() { systemctl list-units --no-legend --plain --all "$@" 2>/dev/null | awk '{print $1}' | sort -u; }
units --state=failed > "$OUT/failed-units.txt"
# active services as "name sub-state unit-file-state" (e.g. "foo.service running enabled"); the unit-file state tells
# compare.sh whether a unit is started on demand (static/indirect) or should come back by itself (enabled)
declare -A UFS=()
while read -r name st _; do [[ -n $name ]] && UFS[$name]=$st; done < <(systemctl list-unit-files --type=service --no-legend 2>/dev/null)
while read -r name _load _active sub _; do
  [[ $name == *.service ]] || continue
  tmpl=$name; [[ $name == *@*.service ]] && tmpl=${name%%@*}@.service
  echo "$name $sub ${UFS[$name]:-${UFS[$tmpl]:-unknown}}"
done < <(systemctl list-units --type=service --state=active --no-legend --plain 2>/dev/null) | sort -u > "$OUT/active-services.txt"
units --type=timer --state=active > "$OUT/active-timers.txt"
systemctl list-unit-files --no-legend --state=enabled 2>/dev/null | awk '{print $1}' | sort -u > "$OUT/enabled-units.txt"

# Docker: name + state + health (not the "Up 3 minutes" text, which always changes). Skipped when not usable.
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  ids=$(docker ps -aq)
  if [[ -n $ids ]]; then
    # shellcheck disable=SC2086  # word splitting of the id list is intended
    docker inspect --format '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}} restart={{.HostConfig.RestartPolicy.Name}} rm={{.HostConfig.AutoRemove}}' $ids \
      | sed 's|^/||' | sort > "$OUT/containers.txt"
  else
    : > "$OUT/containers.txt"
  fi
else
  echo "SKIPPED: docker not installed or not usable by this user (try sudo)" > "$OUT/containers.txt"
fi

# Listening sockets: protocol + local address:port (process names need root, so they are left out).
if command -v ss >/dev/null; then
  ss -H -tuln 2>/dev/null | awk '{print $1, $5}' | sort -u > "$OUT/listening.txt"
else
  echo "SKIPPED: ss not found" > "$OUT/listening.txt"
fi

# Real file systems only (no proc/sys/tmpfs/cgroup/overlay noise).
findmnt -rn -o TARGET,FSTYPE 2>/dev/null \
  | awk '$2 !~ /^(proc|sysfs|tmpfs|devtmpfs|devpts|cgroup2?|overlay|nsfs|securityfs|pstore|bpf|tracefs|debugfs|mqueue|hugetlbfs|configfs|fusectl|autofs|binfmt_misc|efivarfs|ramfs|rpc_pipefs|squashfs|fuse\.portal|fuse\.gvfsd-fuse|nfsd)$/' \
  | sort -u > "$OUT/mounts.txt"

echo "snapshot written: $OUT"
echo "system state: ${state:-unknown}; failed units: $(grep -c . "$OUT/failed-units.txt" || true)"
