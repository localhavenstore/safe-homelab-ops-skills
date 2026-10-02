#!/usr/bin/env bash
# scan.sh - look for likely secrets in files or in staged git changes, WITHOUT printing them (read-only).
# Part of the secret-hygiene skill (safe-homelab-ops, MIT).
# Exit: 0 = nothing found, 1 = findings, 2 = usage error.
set -euo pipefail
export LC_ALL=C

usage() {
  cat <<'EOF'
Usage: scan.sh PATH...          scan files/folders (skips .git, node_modules, binary files)
       scan.sh --staged         scan the lines added in staged git changes (run inside a git repo)
  Prints file:line, the rule name and a masked hint (first 4 characters + length) - never the secret itself.
  Exit 0 = nothing found, 1 = findings, 2 = usage error.
  It finds common formats only. 0 findings does not prove there is no secret.
EOF
}

# name|extended regex. Keep them specific: false alarms train people to ignore the scanner.
RULES=(
  'private key block|-----BEGIN ([A-Z]+ )?PRIVATE KEY( BLOCK)?-----'
  'AWS access key id|(AKIA|ASIA)[0-9A-Z]{16}'
  'GitHub token|(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{60,}'
  'GitLab token|glpat-[A-Za-z0-9_-]{20,}'
  'Slack token|xox[abposr]-[A-Za-z0-9-]{10,}'
  'Telegram bot token|[0-9]{8,10}:AA[A-Za-z0-9_-]{30,40}'
  'Anthropic API key|sk-ant-[A-Za-z0-9_-]{20,}'
  'OpenAI-style API key|sk-(proj-)?[A-Za-z0-9_-]{32,}'
  'Google API key|AIza[0-9A-Za-z_-]{35}'
  'Stripe live key|(sk|rk)_live_[0-9A-Za-z]{20,}'
  'JSON web token|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  'Tailscale auth key|tskey-[a-z]+-[A-Za-z0-9-]{20,}'
  'URL with password|[a-z][a-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]@]{6,}@'
  'password/secret assignment|(pass(word|wd)?|secret|token|api[_-]?key|access[_-]?key|private[_-]?key)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9+/_.!@#%^&*-]{12,}'
)
# Values that are clearly placeholders (checked against the matched text).
PLACEHOLDER='(example|changeme|change_me|placeholder|your[_-]?|xxxx|<[^>]*>|\$\{?[A-Za-z_]|dummy|redacted|\*\*\*\*)'

FOUND=0
# Show only a well-known PUBLIC prefix of the format (never characters of the secret itself), plus the length.
mask() {
  local s=$1 p=""
  [[ $s =~ ^(-----BEGIN|AKIA|ASIA|gh[pousr]_|github_pat_|glpat-|xox[abposr]-|sk-ant-|sk-proj-|sk-|AIza|sk_live_|rk_live_|eyJ|tskey-) ]] && p=${BASH_REMATCH[1]}
  printf '%s***(%d chars)' "$p" "${#s}"
}
# File names are shown with control characters replaced, so a crafted name cannot fake extra report lines.
safe_name() { printf '%s' "$1" | tr '[:cntrl:]' '?'; }
report() { echo "$(safe_name "$1"):$2: $3: $(mask "$4")"; FOUND=$((FOUND + 1)); }

scan_stream() {  # $1 = label for the file; reads "lineno:text" lines on stdin
  local label=$1 entry rule rx n text m flags
  while IFS= read -r line; do
    n=${line%%:*}; text=${line#*:}
    for entry in "${RULES[@]}"; do
      rule=${entry%%|*}; rx=${entry#*|}
      flags=-oE; [[ $rule == password/secret* ]] && flags=-oiE   # key names in any case (DB_PASSWORD, Token)
      while IFS= read -r m; do
        [[ -n $m ]] || continue
        if [[ $rule == password/secret* ]] && grep -qiE "$PLACEHOLDER" <<<"$m"; then continue; fi
        report "$label" "$n" "$rule" "$m"
      done < <(grep "$flags" -- "$rx" <<<"$text" 2>/dev/null || true)
    done
  done
}

[[ $# -gt 0 ]] || { usage >&2; exit 2; }
case $1 in -h|--help) usage; exit 0 ;; esac

if [[ $1 == --staged ]]; then
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "--staged: not inside a git repository" >&2; exit 2; }
  # file names come NUL-separated (any character is safe); only ADDED lines are scanned, with their new line numbers
  while IFS= read -r -d '' file; do
    ln=0; inhunk=0
    while IFS= read -r line; do
      if [[ $line == '@@ '* ]]; then
        ln=$(sed -E 's/^@@ -[0-9,]+ \+([0-9]+).*/\1/' <<<"$line"); inhunk=1
      elif (( inhunk )) && [[ $line == +* ]]; then   # inside a hunk every "+" line is content, even "+++..."
        scan_stream "$file" <<<"$ln:${line:1}"; ln=$((ln + 1))
      fi
    done < <(git diff --cached --unified=0 --no-color --no-ext-diff --text -- "$file")
  done < <(git diff --cached --name-only --diff-filter=ACMR -z)
else
  SKIPPED=0; FILES=0
  for p in "$@"; do
    [[ -e $p ]] || { echo "not found: $p" >&2; exit 2; }
    while IFS= read -r -d '' f; do
      if [[ -s $f ]] && ! grep -Iq . "$f" 2>/dev/null; then SKIPPED=$((SKIPPED + 1)); continue; fi
      FILES=$((FILES + 1))
      # only lines that contain a hint of a secret go through the slow per-rule loop
      # (process substitution, not a pipe: the counter must survive)
      scan_stream "$f" < <(grep -nIiE -- '-----BEGIN|AKIA|ASIA|gh[pousr]_|github_pat_|glpat-|xox|:AA|sk-|AIza|_live_|eyJ|tskey-|://[^/[:space:]]*:[^/[:space:]]*@|pass|secret|token|api.?key|access.?key|private.?key' "$f" 2>/dev/null || true)
    done < <(find "$p" \( -name .git -o -name node_modules \) -prune -o -type f -print0)
  done
  echo "scanned $FILES text file(s), skipped $SKIPPED binary file(s)" >&2
fi

if (( FOUND > 0 )); then
  echo "RESULT: $FOUND possible secret(s) - check each one; do not paste them anywhere" >&2
  exit 1
fi
echo "RESULT: no known secret formats found (this does not prove there are none)" >&2
exit 0
