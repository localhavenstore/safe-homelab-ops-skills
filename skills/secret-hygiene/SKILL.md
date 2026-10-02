---
name: secret-hygiene
description: Use whenever a task would read, show, check, debug, copy or share a password, API key, token, private key, .env file, credentials file or a container's environment variables (docker exec env, docker inspect, printenv) - including 'check the token is set', 'show me the env vars' and 'why does the database login fail'. Also before committing or pasting files and logs. Checks secrets without printing their values and scans for leaked secrets without showing them.
license: MIT
metadata:
  pack: safe-homelab-ops
  version: 1.0.0
---

# Secret hygiene

Everything you print can end up in a chat transcript, a log, a screenshot or a model provider's records. So the
rule is simple: **you may handle secrets, but you never show their values.**

## Never
- Never `cat`, `echo`, `printenv`, `env`, `set`, `docker inspect` (it shows container env vars) or `grep` a file or
  variable that holds a secret in a way that prints the value.
- Never put a secret on a command line (`--password hunter2`): it shows up in `ps` and shell history. Use the
  program's password-file, stdin or environment-file option.
- Never write a secret into a file inside a git repository, a backup-excluded place the user does not know about,
  a world-readable file, or a log.
- Never paste a secret back to the user "to confirm it". Confirm with a fingerprint instead.
- Never "test" a token by sending it to a service other than the one it belongs to.

## Check secrets without showing them
- Exists and non-empty: `sudo test -s /etc/app/token && echo present`
- Permissions: `sudo stat -c '%U:%G %a %n' /etc/app/token` (should be owned by the service user, mode 600 or 400)
- Same value in two places: compare hashes, `sudo sha256sum /etc/app/token /srv/app/.env.token | cut -c1-12`
- A variable is set: `[ -n "${API_KEY:-}" ] && echo set`
- Which keys a .env file defines - print **only the names**, never transformed lines (a "mask the value" filter
  misses multi-line values, lines without `=` and comments with pasted keys):
  `sudo grep -oE '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' /srv/app/.env | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//; s/=$//'`
  (a quoted value that spans several lines could still show one word of its next line as a "name" - rare, but
  check the list before you paste it anywhere)
- Is one key set and non-empty: `sudo grep -qE '^[[:space:]]*(export[[:space:]]+)?DB_PASSWORD=.+' /srv/app/.env && echo set`
- Container env, names only: `docker inspect --format '{{range .Config.Env}}{{index (split . "=") 0}}{{println}}{{end}}' <c>`
- Debugging a connection: check the names are present, compare a value with its expected hash, and read the
  service's own error message (`docker logs <c> --tail 50`) - the error usually says what is wrong without the value.

## Store them properly
- One secret per service, readable only by that service's user (`chmod 600`, owned by the service user).
- In Docker Compose prefer `secrets:` or an `env_file:` outside the repo with mode 600 over inline `environment:`.
- `.env` and key files go in `.gitignore` before the first commit, not after.
- Ask the user to type or paste new secrets themselves into the file or a hidden prompt
  (`read -rs VAR`), not into the chat.

## Scan before sharing or committing
Run the helper (read-only, never prints values; shows `file:line: rule: abcd***(40 chars)`):

- A folder or file: `bash scripts/scan.sh <path>`
- Staged git changes, before a commit: `bash scripts/scan.sh --staged`

Exit 0 = no known secret format found (which is not a proof), 1 = findings. It skips `.git`, `node_modules` and
binary files and tells you how many binaries it skipped.

## If a secret leaked
1. Tell the user right away: what leaked, where (file, commit, log, chat) and since when.
2. The fix is **rotation**: create a new secret at the provider, put it in place, then revoke the old one.
   Deleting the file or rewriting git history alone is not enough - assume the old value is known.
3. Check the provider's logs for use of the old secret if they offer them.
4. Record it in the change log (without the value).
