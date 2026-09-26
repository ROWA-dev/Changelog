# AGENTS

entry points and context about the game in `ServerStorage/README.md`

skills in `ServerStorage/Skills/<name>/SKILL.md`

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

## Building
in `BUILDING.md`. Read it before touching the map.

## Tests
NEVER RUN dynamic tests like simulating a humObj, since its destructive.
Those will be playtested manually
