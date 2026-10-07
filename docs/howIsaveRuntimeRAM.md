# howIsaveRuntimeRAM - the allocation playbook
(index: parent ServerStorage/README.md)

Mostly LUAU HEAP. Not save-payload bytes (those are DATASTORE).
!! BUT READ #0 FIRST. The two biggest per-entity allocations in this game are
ENGINE memory, not Luau heap, so `collectgarbage("count")` cannot see them and
every number in this file used to miss them.

## THE ONE IDEA
    PAY WITH ARITHMETIC TO AVOID HOLDING STATE.

A timestamp instead of a timer. A running sum instead of a modifier list.
One shared frozen stub instead of a per-entity object. A nil instead of a
knob most entities never touch. Nearly everything below is an O(1) read
whose cost was pushed to write-time or to first-use. When you add a subsystem, the question
is not "is this clean", it is "what does this hold, per entity, forever".
That question alone lets you reject a design.

## THE PATTERNS, IN THE ORDER THEY ARE WORTH COPYING

### 0. THE BIGGEST ONES ARE INSTANCES, AND LUAU CANNOT WEIGH THEM.
  HumObjClient/CharAnims  +  HumObjClient/setupLimbTrails
  Measured with Stats:GetMemoryUsageMbForTag, per entity, linear in entity
  count -- NOT a shared asset cache, checked in three batches:
      then-11 AnimationTracks (CharAnims)   41.9 KB   ~3.8 KB a track
      16 Instances (limbTrails)             12.7 KB   8 Attachments,
                                                      4 Trails, 4 emitters
  That is 54.6 KB an entity, against ~17.8 KB of Luau heap for a whole NPC.
  Both were built EAGERLY in HumObjClient.new for every entity, and nothing
  outside player input calls Dash/ChangeSprinting/ChangeSliding, so an NPC
  loaded eleven animations it could never play. Both are now built on first
  read / first enable(true).
  limbTrails is worse than it looks: the Instances are parented INTO the
  character, so they replicated to every client too.
  THE LESSON: before optimising a class, ask whether it holds Instances. If
  it does, Stats:GetMemoryUsageMbForTag is the only honest measurement, and
  it will usually dwarf the table you were about to shave.

### 1. Cooldowns are two floats. Nothing ticks, nothing is an object.
  ReplicatedStorage/Class/cooldowns.luau
  No RunService entry, no scheduler slot, no per-frame update:
      Trigger    -> last = math.max(last, now + cd)
      canTrigger -> tick() > last + (offset or 0)
  The `math.max` is load-bearing: a SHORT cooldown can never shorten an
  already-running LONG one. Cooldowns are created LAZILY; `trigger` with a
  customCD makes the entry on first use, they are not pre-registered at
  construction. An entity that never blocks never allocates a block cd.
  This is the model AGENTS.md points at.
  Measured: an id is 3 hash slots across three parallel {[id]: number}
  maps, 64B registered / 96B once fired (624B as a per-entry object).

### 2. StatusEffects allocates only while an effect is ACTIVE.
  ROWA/Class/StatusEffects.luau
  `activeEffects` holds an entry only for a live effect. Expiry is a
  self-RE-ARMING `task.delay` (makeCleanup re-schedules for the remaining
  time if still active), not a poll. On expiry the key is nil'd and the
  effect destroyed. Zero effects = one empty table, zero threads.
  Two scars worth keeping:
    * cancelCleanup is pcall'd. task.cancel on an ALREADY-COMPLETED thread
      raises. apply() knows its thread is pending; remove/clearAll do not.
    * clearAll snapshots keys BEFORE sweeping, because an effect's destroy
      may touch the entity and re-enter apply. Mutating while iterating is
      undefined in Luau.
  This is the reference implementation, and the reference for allocation.

### 3. Null-object SINGLETONS, not per-entity subsystems.
  ReplicatedStorage/Class/Combatant.luau
  applyInertDefaults patches a CLASS TABLE (explicitly not a base class, not
  an inheritance tier). The inert ragdoll / statusEffects / isParry /
  GuardBreak stubs are table.freeze'd and built once (per class at most),
  then shared by every entity lacking the real subsystem. A prop or a
  critter pays ZERO allocation for every OPTIONAL_MEMBER.
  Same trick on the logging: warnedOnce[className.."/"..what] means one
  dev-warn per CLASS, not per hit, so logging survives a 60Hz hitbox instead
  of getting itself switched off.

### 4. AdditiveValue keeps the SUM, never the history, and allocates NOTHING
     it is not asked for.
  ReplicatedStorage/Packages/AdditiveValue.luau
  _mods[key] plus a cached `v`. SetMod does `v -= existing; v += mod`, so
  reads are O(1) with no walk over a modifier list and no recompute.
  LAZY, measured: `_mods` is nil until the first SetMod and onSet/onRemove
  materialize on first access, so an untouched value is ONE table, 144B
  instead of 576B -- the two Signals were 61% of it and are connected in
  exactly two places (initReplicateServer, and hurtboxSize/charSize in
  HumObj.new). A client mirror connects NONE of them.
  Each mod costs one hash slot, 32B. That is why there is no clever packing
  here and should not be: at the 0-2 mods a value actually holds, any key
  registry costs more than the slots it saves.
  Reading `.onSet` ALLOCATES it -- test with rawget, never `if v.onSet then`.
  Declared tradeoff, in its own header: float drift. Prefer integer mods.
  (It says it should have been named AdditiveInteger.)

### 5. A knob only some entities use is NIL until set, not an object.
  HumObj getupMult / manaCostMult / parryPostureMult / slowMult
  Read as `self.x or 1`; a card sets it via its Cards.luau `knobs` row, cardBase.destroy nils it.
  Holders pay one field, everyone else nothing. An AdditiveValue (#4) is
  144B on EVERY entity, so it is only right when nearly every entity reads
  it or several sources stack into it.
  Cost: two setters overwrite instead of stacking. Fine until a second exists.

### 6. Demand-paged CODE, not just data. (the Quiver)
  ReplicatedFirst/LocalCore/VFX  +  ROWA/VFXQuiver  +  ReplicatedStorage/VFXQuiver
  Three tiers, in order:
    1. Manifold[id] already required            -> call it
    2. ReplicatedStorage/VFXQuiver              -> require, cache, call
    3. RemoteFunction:InvokeServer(1, id)       -> server clones it out of
       ServerStorage/ROWA/VFXQuiver, client parents the clone into its
       local quiver, requires, caches, calls
  So a server-quiver module's bytecode + closures never enter a client's VM
  unless that client SEES the effect. You avoid the compile + closure cost,
  not the source bytes.
  Full mechanism and the inline-vs-quiver decision table: VFX.

### 7. Uniform teardown so nothing outlives its owner.
  ROWA/Class/ClassTemplate.luau sets the shape.
      table.clear      -> drops every reference, KEEPS allocated capacity
      setmetatable nil -> post-destroy use fails LOUDLY instead of
                          silently resurrecting a zombie object
  Copy `destroy` from ClassTemplate. Do not invent a new teardown shape.

### 8. debug.setmemorycategory on the classes that can actually leak.
  The per-entity / per-player / per-swing allocators tag themselves (grep
  setmemorycategory), so the Developer Console memory pane attributes
  growth to a CLASS rather than to one anonymous Luau bucket. If you add a
  class that allocates per entity or per swing, tag it too. An untagged
  leak is a bisect.

## WEAK TABLES: READ THIS BEFORE YOU ADD ONE
Three are OFF ON PURPOSE: explicit cleanup already unmaps them, and a weak
map turns a leak into an intermittent nil at GC time. Do not re-enable them:

    Entities.entityMap    __mode="v"
    PlrHandler.plrMap     __mode="v"
    LocalCore._G.hides    __mode="k"

One was REMOVED, not disabled: `cooldowns.cooldowns` had __mode="k"
while every key is a STRING, and strings are never removed from weak tables.
It collected nothing, allocated a fresh metatable per entity, and put the
table on the collector's weak list every cycle. Proven with a control (an
unreachable TABLE key in the same table WAS collected; the string key was
not). Weak keys need collectable keys.

The rule those three encode: WEAK VALUES ON TOP OF CORRECT EXPLICIT
CLEANUP BUY NOTHING AND MAKE THE FAILURE MODE NONDETERMINISTIC. Entities
already destroys+unmaps on both AncestryChanged and Destroying. Adding
weakness there converts a clean reproducible leak into an intermittent nil
that vanishes at GC time. If entries linger, FIX THE CLEANUP PATH.
Weak is for caches you can afford to lose, not for registries you own.

## THE ANTI-PATTERN (measured, in this codebase)
    require(x) ... x:Destroy()   DOES NOT FREE ANYTHING.

Destroy() unparents the Instance; it does NOT evict Luau's require cache.
Measured clone+require+Destroy in a loop: +38 KB per cycle, never reclaimed
(caveat: collectgarbage("collect") is blocked, so "not within ~10 frames").

Live case: RFQuiver/clientInfo pins CountryCodes (249 entries, ~107 KB) to
read TWO fields, and is also a BUG: the first invoke Destroys CountryCodes,
so a second invoke infinite-yields on WaitForChild and InvokeClient never
returns. Fix direction: resolve the country name SERVER-side.

THE GENERAL LAW: lazy require DELAYS cost, it never RETURNS it. The Quiver
(#6) is correct because it defers a FIRST require. clientInfo is wrong
because it assumes you can undo one. Same instinct, opposite result.

## CHECKLIST FOR ANYTHING NEW
  * What does it hold PER ENTITY, at construction? Can it be lazy (#1),
    a shared frozen singleton (#3), or nil until set (#5)?
  * Does it allocate PER SWING or PER FRAME? Justify explicitly. "It is
    cleaner" is not a justification. Proposals have been withdrawn on this
    test before.
  * Can a derived number be a running sum instead of a stored list? (#4)
  * Is it only needed sometimes? Quiver it (#6). Do NOT "unrequire" it.
  * Does it have a destroy that table.clears AND detaches the metatable?
  * If it allocates per entity/player/swing: setmemorycategory it (#8).
  * Reaching for __mode? Re-read the weak-table section first.
