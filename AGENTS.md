# AGENTS — ROWA

Rules for anyone editing this codebase, human or agent. The docs index, the
60-second mental model and the entry points are `ServerStorage/README.md`.
This file is only the rules.

## House style
- Conserve RAM. The cooldown shape (two floats, nothing ticks) is the model.
- Most things are lazy loaded, because there are just too many things/modules
  that arent used most of the time.
- Keep comments and docs terse — one sentence line for changes, not entire
  paragraphs bro. Least code wins.
- Avoid multi line comments/documentation.
- Keep data sent in network minimal.
- We scale for the purpose of writing less code/redundancy in the future.
- Least blast radius as possible.
- YAGNI.

## No redundancy rule
Duplicate / redundant code must be adressed. Always see if its already done
somewhere else.

This includes documentation — remove outdated/redundant documentation and
comments rather than leaving a second copy to drift.

## Preferred call shape
How StatusEffects is CALLED. One line, no ceremony:

    enemy.statusEffects:apply(humObj.statusEffects.Burn, 10, 3)

No nil check (Combatant guarantees an inert stub), no handle to keep, no
cleanup, safe to spam every hit (apply dedupes -> onStack).

Build new subsystems to be called like that one.

## Before you move anything
Use the scripts named in these docs, not random ones you find.

When MOVING, RENAMING or DELETING, **GREP FIRST**, including when a doc says it
already checked. One doc was wrong about that and would have broken a live
summon.

## Tests
AVOID testing, let me play test changes manually.

NEVER RUN dynamic tests like simulating a humObj, since its destructive.

## Docs
Every doc is a markdown FILE and a CHILD of `ServerStorage/README.md`. No Luau
wrapper, no `return true`, and nothing requires one — they are read, not
loaded. A doc may have its own children. This file is the exception: it is
rules, not reference, so it sits beside the README rather than under it.

Expand these docs as the framework evolves.

## Decided against
Do not re-propose without new evidence: mass renames, carving up HumObj,
per-action scopes, data-driven weapon ids.
