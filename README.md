# Spellbook

A bundle of Claude Code skills. Each skill is self-contained under `skills/<name>/`,
so new skills can be added in parallel without coupling.

## Skills

- **[summon](skills/summon/)** — securely teleport a file, folder, whole Claude
  skill, or chunk of context to a teammate's Claude via end-to-end-encrypted
  `croc`, unlocked by a spoken 4-word incantation.

## Layout

```
spellbook/
  .claude-plugin/plugin.json   # makes the bundle installable as a Claude plugin
  skills/
    summon/                    # one skill = one folder (SKILL.md + its code + tests)
  docs/superpowers/{specs,plans}/
```
