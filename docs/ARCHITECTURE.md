# ARCHITECTURE - module dependency shape (the require graph)

One rule. Read it before adding a `require` to anything in the combat
pipeline.

## THE RULE
    NEED ONLY TYPES?  REQUIRE THE `types` LEAF, NOT THE CLASS.

Luau resolves `require` LEXICALLY. It does not care that the call sits
inside a function body, and it does not care that you only wanted a type
annotation out of it. A type-only import is a REAL EDGE in the graph and
forms a REAL cycle.

## WHY THIS DOC EXISTS
`DmgUtils` imported `HitboxClass` for two type aliases: three lines, no value
ever used at runtime. That single edge put THIRTEEN modules into one
strongly-connected component:

    DmgUtils -> HitboxClass -> HitBox -> EntityLookup -> Entities
             -> HumObj -> WepBase.types -> DmgUtils

plus Knockback, knockBreakStuff, SimpleEntity, AttackClass and the three
HumObj.resolution modules hanging off the same loop. All of them dropped out
when that ONE edge was cut. The fix: give HitboxClass a `types` child that
requires NOTHING, and point DmgUtils at the child. HitboxClass re-exports the
same names, so the types are IDENTICAL, not copies, and no annotation had to
change.

## THE LEAF PATTERN
Three modules already follow it. Copy them:
    ROWA/Class/HitboxClass/types.luau     <- hitList, myself, sweepCfg
    ROWA/Weps/WepBase/types.luau          <- the weapon surface
    ReplicatedStorage/Modules/atkType.luau <- atkTyp<entity>, stubbed

A type both attacker halves need goes in the HitboxClass leaf and is
RE-EXPORTED through DmgUtils, which WepBase/types and AbilityBase already
require -- that is how `sweepCfg` reached both sides without a new edge.

A leaf module requires nothing and returns `true`. Requiring a CHILD does
NOT pull in its PARENT. That property is what the whole scheme rests on.

## THE TRAP, TESTED, DO NOT WALK INTO IT
The "obvious tidy" of pointing `WepBase.types` straight at `HitboxClass`
(cutting out the DmgUtils middleman) RE-FORMS the cycle by a new route:

    HumObj -> WepBase.types -> HitboxClass -> HitBox -> EntityLookup
           -> Entities -> HumObj

Anything wanting hitbox types goes to the LEAF. Never to HitboxClass.

## LAZY REQUIRES: DORMANT, NOT ABSENT
`EntityLookup` and `HitBox` require their dependency INSIDE a function and
cache it. Those were load-order deadlock fixes. The deadlock is gone at its
source, so they are belt-and-braces, and THEY STAY. Hoisting them buys
nothing and re-arms the failure the moment someone adds a type import
upstream. Both files say so at the top.

## A LAZY REQUIRE IS A CYCLE YOU AGREED TO KEEP
`HumObj/onDeath` used to hold a third one, and it is GONE. It required
`Entities` inside a function purely to walk the whole registry calling
`dmgRecord:endMembership(self)` on every entity alive, because
`contributions` is keyed by ATTACKER and so cannot answer "whose fights am I
in?". That is a DATA-SHAPE problem wearing a dependency problem's clothes,
and deferring the require only hid it:

    Entities -> HumObj -> onDeath -> Entities        (real, deferred, still there)

The fix was to answer the question locally. `damageRecord` now writes a weak
back-edge in `addEntry` (`memberships`) and `leaveAllFights` reads it, so
onDeath asks the record it already owns. The edge is CUT, not deferred: the
whole HumObj subtree requires `Entities` nowhere, and the walk went from
O(every entity alive) to O(my fights).

So, before writing another lazy require: ASK WHAT DATA THE CALLEE ACTUALLY
WANTED. Twice now the answer has been a couple of fields, not a module. The
two that remain (EntityLookup, HitBox) stay because they are belt-and-braces
over a deadlock already fixed at its source -- not because deferring is a fix.

## HOW TO CHECK YOUR WORK
The type warning is the oracle: open the Script Analysis window. A cycle
shows up as "Cyclic module dependency: a -> b -> c". Roblox prints ONE
arbitrary path through the cycle, so the chain shown is usually a subset of
what is actually tangled. The listed modules are not the only ones involved.

## KNOWN-STALE TYPE, TRACKED
`HitboxClass.types.hitList` says `{Humanoid}`. The hitbox actually returns
ENTITIES deduped on `entityId`. It stays invisible
because HitBox.luau is `--!nonstrict`, so the call yields `any`.
Left alone on purpose so the cycle fix changed no type's MEANING. Fixing it
touches the live hit path, which is not play-tested at that depth, so it
lands as its own commit, with a playtest.
