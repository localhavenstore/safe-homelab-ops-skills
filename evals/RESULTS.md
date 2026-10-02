# Scenario eval results

Run: 2026-10-02 - agent: 2.1.287 (Claude Code) - model: claude-haiku-4-5-20251001 - 12 scenarios x 3 runs, each in a fresh empty project; tools limited to Skill + Read (answer-only, nothing executed). 'with' = the documented install (six skills as project skills + AGENTS-snippet.md as the project CLAUDE.md), 'without' = same prompt, no skills.
Scenarios and pass rules: evals/scenarios.json (regular expressions on the answer).

| skill | with skills | without skills | skill loaded (with) |
|---|---|---|---|
| `process-match-safety` | 5/6 | 0/6 | 5/6 |
| `reboot-test` | 6/6 | 1/6 | 6/6 |
| `restore-drill` | 6/6 | 4/6 | 6/6 |
| `risk-check` | 6/6 | 3/6 | 6/6 |
| `safe-change` | 6/6 | 1/6 | 6/6 |
| `secret-hygiene` | 5/6 | 0/6 | 6/6 |
| **total** | **34/36** | **9/36** | |

Pass rule: every skill >= 5/6 with skills. Every answer: evals/results.json. Model answers vary between runs; small differences are noise.

OVERALL: PASS
