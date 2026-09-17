# howIsaveRuntimeRAM - the allocation playbook
(index: parent ServerStorage/README.md)

Mostly LUAU HEAP. Not save-payload bytes (those are DATASTORE).
!! BUT READ #0 FIRST. The two biggest per-entity allocations in this game are
ENGINE memory, not Luau heap, so `collectgarbage("count")` cannot see them and
every number in this file used to miss them.

## THE ONE IDEA
    PAY WITH ARITHMETIC TO AVOID HOLDING STATE.

A timestamp instead of a timer. A running sum instead of a modifier list.
One shared frozen stub instead of a per-entity object. A packed buffer
instead of a table. Nearly everything below is an O(1) read whose cost was
pushed to write-time or to first-use. When you add a subsystem, the question
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
  This is the shape AGENTS.md means by "conserve ram as seen by
  the shape of the cooldowns".
  TRUE OF HEAP TOO, since the fold: an id is 3 hash slots across three
  parallel {[id]: number} maps, 64B registered / 96B once fired, MEASURED,
  down from 624B when each was a table + Signal + forwarding closure +
  connection. CooldownTriggered fires straight from :trigger, which is all
  the per-entry Signal ever did. cooldown.luau is deleted.
  The holder costs 224B more (two extra maps) and pays that back at the
  first entry. 94% of call sites never held the object anyway.

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
  GuardBreak stubs are table.freeze'd and built ONCE AT MODULE LOAD, then
  shared by every entity lacking the real subsystem. A prop or a critter pays
  ZERO allocation for all eleven OPTIONAL_MEMBERS.
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
  registry costs more than the slots it saves. Compare #5, which pays off at
  hundreds of elements.
  Reading `.onSet` ALLOCATES it -- test with rawget, never `if v.onSet then`.
  Declared tradeoff, in its own header: float drift. Prefer integer mods.
  (It says it should have been named AdditiveInteger.)

### 5. Elias-Fano packed integer sets for saved flags.
  ROWA/Class/SparseBitSet.luau  ->  Packages/EliasFano
  In memory it is a plain {[number]: true}. Serialize() sorts the keys and
  packs them near information-theoretic optimum (~2 + log2(U/k) bits per
  element) into a `buffer`, with k in 16 bits and L in 6 bits as a packed
  header, buffer.copy'd in front of the payload.
  This is a SAVE-SIZE win first (see DATASTORE), but it is here because
  it states the house style clearly: the compact form is the serialized form,
  the ergonomic form is the in-memory one, and you convert at the boundary
  rather than living in either extreme.

### 6. Demand-paged CODE, not just data. (the Quiver)
  ReplicatedFirst/LocalCore/VFX  +  ROWA/VFXQuiver  +  ReplicatedStorage/VFXQuiver
  Three tiers, in order:
    1. Manifold[id] already required            -> call it
    2. ReplicatedStorage/VFXQuiver (11 modules) -> require, cache, call
    3. RemoteFunction:InvokeServer(1, id)       -> server clones it out of
       ServerStorage/ROWA/VFXQuiver (41 modules), client parents the clone
       into its local quiver, requires, caches, calls
  So 41 VFX modules of bytecode + closures never enter a client's VM unless
  that client SEES the effect. You avoid the compile + closure cost, not the
  source bytes.
  Full mechanism and the inline-vs-quiver decision table: VFX.

### 7. Uniform teardown so nothing outlives its owner.
  ROWA/Class/ClassTemplate.luau sets the shape; ~100 `table.clear` and ~62
  `setmetatable(self, nil)` follow it.
      table.clear      -> drops every reference, KEEPS allocated capacity
      setmetatable nil -> post-destroy use fails LOUDLY instead of
                          silently resurrecting a zombie object
  Copy `destroy` from ClassTemplate. Do not invent a new teardown shape.

### 8. debug.setmemorycategory on the classes that can actually leak.
  Seven sites, all deliberate:
      WepBase, HumObj, AttackClass, plrObj, PlrStats,
      PlrHandler, Entities
  These are the per-entity / per-player / per-swing allocators, so the
  Developer Console memory pane attributes growth to a CLASS rather than to
  one anonymous Luau bucket. If you add a class that allocates per entity
  or per swing, tag it too. An untagged leak is a bisect.

## WEAK TABLES: READ THIS BEFORE YOU ADD ONE
Seven `__mode` sites exist. THREE OF THEM ARE COMMENTED OUT ON PURPOSE and
the reasoning is written at the site (Entities.luau, "THE WEAK-MAP
QUESTION, ANSWERED"). Do not re-enable them:

    Entities.entityMap    __mode="v"  COMMENTED OUT, deliberate
    PlrHandler.plrMap     __mode="v"  COMMENTED OUT, same answer
    LocalCore._G.hides    __mode="k"  COMMENTED OUT
    damageRecord.contributions  __mode="k"  ACTIVE
    damageRecord.memberships    __mode="k"  ACTIVE, the reverse index
    HumObjClient.CharController.Animate     ACTIVE

A FOURTH was REMOVED, not disabled: `cooldowns.cooldowns` had __mode="k"
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

RFQuiver/clientInfo.luau does this with CountryCodes, and CountryCodes' own
header endorses it ("use it temporarily"). It does not work. Destroy()
unparents the Instance; it does NOT evict Luau's require cache, and the
returned table is pinned by the module registry.

Measured by clone+require+Destroy in a loop, waiting for the incremental
GC between cycles:
    cycle 1  52464 KB     cycle 4  52578 KB
    cycle 2  52502 KB     cycle 5  52616 KB
    cycle 3  52540 KB     cycle 6  52654 KB
    => +38 KB per cycle, monotonic, never reclaimed.
(Caveat on the method: collectgarbage("collect") is BLOCKED in Roblox --
only "count" is allowed -- so this is "not reclaimed within ~10 frames",
not a proof of permanence. The require-cache semantics predict the same
result independently.)

CountryCodes is 249 entries of {Emoji, Name}, ~107 KB resident once touched,
table.freeze'd, pinned for the session, to read TWO fields once per player,
which then get stringified into plrObj.Data.meta.clientInfo.

It is also a BUG, not just waste. OnClientInvoke does
`require(rfQuiver[id])(...)` on EVERY invoke, and the first call runs
`script.CountryCodes:Destroy()`. A second invoke on the same client hits
`script:WaitForChild("CountryCodes")` on a child that no longer exists ->
infinite yield -> the server's InvokeClient never returns. One-invoke-per-
client is the only reason this has survived.
Fix direction: resolve the country name SERVER-side, or inline the single
pair needed. Do not ship a 249-entry table to a client to read two fields.

THE GENERAL LAW: lazy require DELAYS cost, it never RETURNS it. The Quiver
(#6) is correct because it defers a FIRST require. clientInfo is wrong
because it assumes you can undo one. Same instinct, opposite result.

## CHECKLIST FOR ANYTHING NEW
  * What does it hold PER ENTITY, at construction? Can it be lazy (#1) or
    a shared frozen singleton (#3)?
  * Does it allocate PER SWING or PER FRAME? Justify explicitly. "It is
    cleaner" is not a justification. Proposals have been withdrawn on this
    test before.
  * Can a derived number be a running sum instead of a stored list? (#4)
  * Is it only needed sometimes? Quiver it (#6). Do NOT "unrequire" it.
  * Does it have a destroy that table.clears AND detaches the metatable?
  * If it allocates per entity/player/swing: setmemorycategory it (#8).
  * Reaching for __mode? Re-read the weak-table section first.
