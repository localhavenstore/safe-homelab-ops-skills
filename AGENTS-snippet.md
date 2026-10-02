## Server safety (safe-homelab-ops skills)
For any task on a server, load the matching skill(s) BEFORE you answer or act, and follow them - also when you only
answer with commands for the user to run:
- editing a config, upgrading/updating packages or containers, any change -> `safe-change` (+ `risk-check`)
- new or changed service, unit, timer, Compose stack, `/etc/fstab` or mount, kernel/boot -> `reboot-test`
- checking, testing or setting up backups or dumps -> `restore-drill`
- passwords, tokens, keys, `.env` files, container env vars, sharing logs/files -> `secret-hygiene`
- finding, killing or waiting for processes -> `process-match-safety`
- deleting, exposing, access/firewall/VPN changes, secrets, money, publishing -> `risk-check` (ask first)
Always, even without loading a skill: never print secret values - no `cat`/`grep` output of `.env` or key files, no
`docker exec <c> env`, `printenv` or `docker inspect` env output; show variable NAMES only, or check with `test -s`/`grep -q`.
