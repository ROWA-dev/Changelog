# GOTCHAS - read before you touch anything
(index: parent ServerStorage/README.md)

Footguns, silent failures and "why is this not working" traps.

## NAMING / STRUCTURE
  * Instance names have NO extension. The `.luau` in tooling paths is the file
    adapter, not the instance name. `require(...ROWA.Weps.WepBase)`,
    not `WepBase.luau`.
  * Heavy / Medium / Light are inherited weight bases, not concrete weapons.
    The chain is WepBase -> weight -> family -> weapon. Every layer requires
    its parent, so reparenting silently changes inheritance and behaviour.
  * `Abilities/AbilityBase/feintwait` and `Weps/Utils/feintwait` are NO LONGER
    separate copies. Both are thin frozen configs over the one implementation,
    `ROWA/Modules/sharedFeintWait`. Fix bugs THERE, once.
    They still differ on purpose (P-6, abilities are more cancel-friendly):
      weapon  cdId "feint",  gates dashing 0.1s, postFeintSlow 0.15 for 0.2s,
              bumpThresholdOnFeint true, stopAnim -> wep:stopLastAnim()
      ability cdId "feint2", does NOT gate dashing, no postFeintSlow,
              bumpThresholdOnFeint false, stopAnim -> ability:StopAnim()
  * `WepBase/defaultAttacks` (dispatch table, zero-arg per-type impls) vs
    `WepBase/attackHelpers` (parameterised helpers weapons call with windup /
    hitbox / dmgTbl args). Different jobs.
    They were named `baseAttacks` / `basicAttacks`; older notes use the old
    names. attackHelpers holds m1, arial, sprint.
  * Typos are load-bearing: `VFXQuiver/inventoryFlaoter`, `arialAtk` (aerial),
    `ReplicatedFirst/Folder/cheapsake` + `cheapstake`. Don't "fix" them
    without grepping every call site.

## IDS ARE PERSISTED, NEVER RENUMBER
  * `ROWA/Weps.luau` wepList and `ROWA/Abilities.luau` abilityList map numeric
    ids to modules. Those ids are saved on player items. Only APPEND.
  * Several abilities are not registered (EarthShot, HitSelf, StrongKick,
    StrongShove), so `getAbilityClass` ERRORs on them. Require the
    module directly, or add it to the list.

## STATS: AdditiveValue on BOTH now
  * WepBase AND AbilityBase: atkRate / range / atkRateOffset / knockbackMult
    are all AdditiveValue objects -> `self.atkRate.Value`, mutate via
    `:SetMod(key, n)`.
  * They used to differ (AbilityBase held plain numbers), and were unified.
    Old notes saying "abilities are plain numbers" are STALE.
  * `AdditiveValue.Value` is READ-ONLY. Assigning throws
    "Value is readonly you stupid, use:setMod instead".
  * Mods are keyed strings. Setting the same key twice REPLACES it, it doesn't
    stack. Two systems using the same key ("feint", "stopMoving", "landhit",
    "antiASwing", "wep") clobber each other.
  * The module warns it's prone to float drift. Keep mods to integers.

## FEINTWAIT SEMANTICS (the #1 source of stuck states)
  * `:feintWait(t)` returns TRUE when the action was CANCELLED.
    `if this:feintWait(0.5) then return end`. Backwards means your attack
    fires during a feint.
  * On the cancelled branch YOU clean up: destroy cloned VFX, `anim:Stop()`,
    remove any walkSpeed/atkRate mods you set, and `:destroy()` any bodyForce
    you created. Nothing does it for you.
  * It also returns true if the humObj vanished, entered stun, or can no
    longer attack, not just on an actual player feint.
  * All wait helpers scale by `(t + atkRateOffset) * atkRate / timeScale`.
    Your literal seconds are NOT wall-clock seconds.
    THE ONE EXCEPTION IS `:sweep`, whose window scales by atkRate/timeScale
    but NOT by atkRateOffset -- that offset is a flat-seconds penalty and
    adding it would DOUBLE a 0.15s window, handing a punished player more
    hitbox forgiveness. A window is a tolerance, not a beat.
  * !! `isFeinted` IS ONLY EVER CLEARED BY feintWait AND channelBreak, and
    feintWait's clear is at the TOP of it (sharedFeintWait,
    "actor.isFeinted = false" before the loop). `CombatAction.feint` sets it;
    nothing else resets it.
    SO: A CHANNEL THAT READS `isFeinted` RAW, WITHOUT GOING THROUGH EITHER,
    INHERITS A STALE ONE and self-cancels on its first iteration.
    Sustained abilities call `:channelBreak()` between beats, which is what
    that helper is for -- Barrage, IceBeam, FlameDance, Huozai, StoneBall,
    Burst, Freeze. FullBlue reads the flag itself because its field appears
    instantly with no windup, and it shipped with exactly this bug: cast one
    worked, every cast afterwards died on frame one and drew no VFX at all,
    with no error anywhere.
    The flag is re-armed by a feint DURING endLag too -- `attacking` is
    still true there, so `feint()` still succeeds -- which is why it
    stuck rather than alternating.
    If your action has no windup, `self.isFeinted = false` at entry.

## HITBOX TRAPS
  * BOTH WepBase:hitbox and AbilityBase:hitbox return TWO values,
    `(hitboxObj, hits)`. AbilityBase used to return the hit list only; it
    now returns the pair, so `local hits = ability:hitbox(...)`
    NOW GETS THE HITBOX OBJECT, not the hits. In-tree call sites were migrated;
    check any out-of-tree script.
  * WepBase:hitbox scales size by `charSize`, adds (1.5,1.5,1.5) while
    `floating > 0`, adds a hardcoded +1 range fudge, and RETRIES against
    HRootPart if the HurtBox query returns zero. AbilityBase:hitbox does NONE
    of that (scaleByCharSize/floatBonus/retryOnMiss all off, no +1). Ability
    hitboxes must be authored at absolute size. Abilities also skip the
    antiASwing whiff penalty (trackPrevHits false) -- and that is NOT a
    balance knob: `prevHits` is read by WepBase's whiff detection and by
    nothing else, so turning it on for abilities writes a field nobody
    reads. An ability is punished for whiffing by its COOLDOWN. Both
    flavours go through ROWA/Class/HitboxQuery.
  * Both filter to `workspace.Entities` with CollisionGroup "hitbox". A rig
    parented anywhere else is NEVER hit, whatever the geometry.
  * `:hitbox` is a one-shot snapshot, not continuous. For ACTIVE FRAMES use
    `CombatAction:sweep`, which re-queries for you and stops on the first
    body it could land on (a DODGE does not count, so i-frames cannot spend
    your window). For a MULTI-HIT sweep -- a beam, a rush, anything that
    hits more than one thing over time -- you still loop and dedupe on
    `entityId` yourself, because sweep is first-contact-wins.
  * `no_entity` is checked in TWO places: on the Model (isRegisterable) and
    on its Humanoid. Either tag means `Entities.Get` returns nil, so any code
    doing `Entities.Get(hum).something` on them errors.
    (The registry is ServerScriptService/Entities.luau. Humanoids.luau is gone.)
    Registration also requires the instance to be a Model.

## ATTACK / DAMAGE FLOW
  * `:makeAtk` only BUILDS the attack. Nothing happens until `:executeAttack`.
  * Assign `.hitbox` and `.knockback` onto the attack BEFORE executing:
    `CalculatePostureDmg` adds `knockbackForce^0.8`, and `ApplyKnockback` runs
    inside HandleAttack.
  * `beforeAttacked:FireSync` runs synchronously before resolution and cards
    can set the status to `aborted`. Execute does not always reach HandleAttack.
  * `beforeAttack` is the ATTACKER's twin of it, fired first: outgoing damage
    cards (Frontliner) belong there, incoming ones (Underdog) in beforeAttacked.
  * `HandleAttack` returns `nil` (not an enum) if the target `isDead`.
  * `parryH` / `dodgeH` are ADDED to the defender's window. NEGATIVE = harder
    to parry. Sign errors here make heavies parry-food.
  * `dmgTbl.onHit` only fires on the HIT branch, not on block, parry or dodge.
  * dmgConfig tables are deep-frozen. Mutating one at runtime throws. Use
    `attack.dmgMult` or build a fresh table.
  * `:Damage(amt)` bypasses every resolution step. Use it only for
    self-damage / DoT.
    It is a raw `Hum.Health -= amt` on EntityBase ONLY. HumObj OVERRIDES it
    to carry the death stall, so on a player or any Humanoid entity a lethal
    amount clamps to Health = 1 and knocks them down instead of killing, and
    damage while down drains `knockedHp`, not health. CLASSES 3.5.
    So `:Damage(9e9)` DOES NOT KILL a HumObj. `:Die()` does.

## DEATH / RAGDOLL / THE CORPSE
  * `RowaRagdoll.new` sets `BreakJointsOnDeath = false` and
    `RequiresNeck = false` on every Humanoid it touches. Both are rowa1
    lines that were missed in the port. BreakJointsOnDeath DEFAULTS TO TRUE,
    so the engine was destroying every Motor6D and the holdTorso weld the
    moment the Humanoid died -- racing onDeath's own ragdoll and separating
    the root from the torso. Do not "clean up" these two lines: without them
    death looks different every time. RequiresNeck is what makes
    ROWA/Modules/execute's decapitation safe.
  * `stopOnGround` is a BARE OVERWRITE in `:ragdoll`, and it is written
    BEFORE the `_ragdollConn` early-return, so the LAST caller wins.
    `lifetime` right above it is protected by `math.max`. This means a late
    `ragdoll(t, true, ...)` can un-pin a body an earlier call pinned --
    knockBreakStuff waits 0.1s and then does exactly that. `doUnragdoll`
    refuses on `Health <= 0` to absorb it. Do NOT "fix" it by making
    stopOnGround monotonic instead: lifetime's math.max has already extended
    the timer, so that turns IceBash-then-wall-smash into a 60s flat ragdoll.
  * THE CORPSE YOU SEE IS NOT THE RAGDOLL. plrObj/makeCorpse clones the
    character on CharacterRemoving and eventually ANCHORS every visible part
    and strips its joints. It now SETTLES FIRST (rest, or a 3s cap) because
    CharacterRemoving fires on the respawn timer, not on "the body stopped
    moving" -- anchoring mid-flight was what left limbs floating detached.
    Anything you change about how a body looks after death belongs there,
    not in RowaRagdoll.

## CLICKING ON A CHARACTER
  * EVERY ENTITY WEARS A 4x7x4 INVISIBLE HURTBOX welded over its whole
    body, and it is queryable. So a plain mouse ray, Mouse.Target or any
    unfiltered raycast aimed at a character hits the HURTBOX essentially
    every time and never a limb. Anything that needs the actual body part
    has to pierce it -- bindFuncs/light does, by CollisionGroup.
  * doRagdoll leaves limbs `CanQuery = true` ON PURPOSE (doUnragdoll sets
    it false). A knocked body has to be clickable so a limb can be grabbed.
    This does NOT leak limbs into combat: ROWA/Class/HitboxQuery builds ONE
    shared OverlapParams for the whole codebase with CollisionGroup
    "hitbox", and character parts live in "hurtbox"/"ragdoll", so the group
    filter decides what hitboxes see, not CanQuery.

## WEAPON LIFECYCLE
  * `:equip(humObj)` calls `:unwield()` internally. Wield order is
    equip -> wield, and `:wield()` evicts whatever was previously in
    `humObj.wielding_weapon` AND in `humObj.heldWeapon` -- both poses share
    the one Right Arm Motor6D.
  * `req = nil` DOES NOT MEAN "no requirement". Class statics inherit through
    __index, so nil picks up the weight family's. The opt-out is `req = {}`.
  * Requirements are FLAT: `req = {hvy = 2}`. Stat names must be UNIQUE across
    weaponStats/baseStats/elements; the registry warns at load if two tracks
    claim one. weaponStats is hvy/med/lht so `light` stays the element's.
  * An unknown stat name FAILS CLOSED -- a typo locks the gate, never opens it.
  * The `req` gate lives ONLY in `HumObj:canWield`, on the COMMIT.
    `EquipWeapon` never fails: a weapon you can't use still draws, inert.
  * NPCs have no `plrObj` and so no stats; `canWield` passes them on purpose,
    and `EquipWeapon` COMMITS instead of holding out for them. They have no
    click, so hold-out is a dead state -- every bot, summon, dummy and the
    Tool template reaches a weapon through EquipWeapon and nothing else.
  * CLONE YOUR MODEL IN `.new()`, NEVER IN `:wield()`. Seven weapons used to
    clone per wield: leaked one every wield, welded a second copy to your arm
    once `:holdOut` reused that weld, and left `:equip`'s ScaleTo hitting nil.
  * `HumObj:destroy` RELEASES weapons (putAway + unequip), never destroys
    them -- wepItem and the NPC Tool script own them and outlive the
    character. It used to `:destroy()` them, which `table.clear`ed the
    instance the ITEM still pointed at: dead weapon item after one respawn.
  * An emote restores a HELD weapon with `:holdOut`, not `:wield`; `:wield`
    there would make emote a requirement bypass.
  * `WepBase:onParried` WARNS if you don't override it ("must be implemented
    by <name> you noob"). Every concrete weapon needs one.
  * Whiff detection reads `self.prevHits`, which `:hitbox` sets. If your
    attack never calls `:hitbox`, EVERY swing counts as a whiff and eats the
    `antiASwing` atkRate debuff.
  * Trails use `_trailVersion` so overlapping swings don't disable early.
    If you touch `_trail` manually, respect the version counter.
  * `:PlayAnim` calls `stopAbilityAnims()`, so a weapon swing kills an
    in-flight ability animation. Intentional.
  * `preloadAnims` walks the CALL STACK (`debug.info`) to find which weapon
    module called `:wield`, then preloads every Animation under it. Wrapping
    `:wield` in extra function layers breaks the lookup, and it silently does
    nothing when it fails.

## MANA
  * `humObj.mana.Value` IS NOT CURRENT MANA. It is the ANCHOR -- mana as of
    the last write. Regen is a closed-form curve solved ON READ, so the live
    number only exists when you ask for it:
        READ   humObj:manaNow()      NEVER  humObj.mana.Value
        WRITE  humObj:setMana(n)     NEVER  humObj.mana.Value = n
    Writing `.Value` directly sets the anchor without restamping the clock,
    so the entity instantly regains every second since the last real write.
  * `mana.Changed` therefore means RE-ANCHORED, not "mana changed". It fires
    on spend/gain/max-change only. That is exactly what drives repli S2C.mana,
    and why regen costs zero bandwidth.
  * Nothing ticks mana on either side. If you find yourself adding a loop or
    a Heartbeat for it, you are reintroducing the desync -- read the MANA
    block in ReplicatedStorage/Class/HumObjClient first.
  * The wire carries the VALUE only; the client stamps its own `t` on
    receipt (same idiom as trueStun). So the client trails the server
    by one ping of regen, <=1 mana at empty, and it does NOT accumulate --
    every re-anchor corrects it.

## ABILITY LIFECYCLE
  * `:use` checks mana but does NOT spend it. Call `this:useMana()` yourself.
    Nearly every ability does, at its commit point. One that never calls it
    is free, and unless its header says so that is a bug.
  * A failed mana check is not silent: it broadcasts the `noMana` quiver id.
    EVERYONE NEARBY HEARS IT (the sound is 3D on your hurtbox); only the
    caster gets the bar. manaUse defaults to 10, so a broke player gets that
    tell from ANY ability.
  * `humObj:UseAbility` RETRY-LOOPS `:use()` every frame for up to 0.2s, and
    IT IGNORES THE RETURN VALUE -- the loop is gated on `attacking`, so a
    useFunc that bails early is simply called again next frame. Guard it with
    a cooldown at the top or it fires multiple times.
  * `UseAbility` ERRORS if `ability._humObj ~= self`. Ability instances are
    per-HumObj, never share them.
  * `:use` pcalls your useFunc, so errors become a `warn`, not a crash. Check
    output before assuming your code ran.

## VFX
  * A VFX id missing from both quivers just `warn`s on the client. No error,
    no visual. Check the client console.
  * `HumObj:FireVFXClient` silently no-ops when `plrObj == nil`, i.e. on every
    NPC. Use `VFX:FireAllClients` if NPCs need the effect.
  * Firing an id via `FireAllClients` while the effect is ALSO spawned inline
    server-side plays it twice. Pick one pattern.
  * The lazy fetch parents a clone of the module INTO the requesting player and
    Debris-removes it after a few seconds. The client has already re-parented
    and required it. Don't "fix" the cleanup.

## MISC
  * Sub-modules are frozen with `table.freeze(module)`. No runtime
    monkey-patching a class.
  * `destroy()` methods `table.clear(self)` and usually strip the metatable.
    Any reference you kept becomes a bare empty table, not nil, so `if obj then`
    still passes. Check `isActive` instead.
  * `cooldowns:canTrigger(id)` returns TRUE for ids that DON'T EXIST. Typo a
    cooldown id and your gate is permanently open.
  * `cooldowns:trigger(id)` on a nonexistent id only creates it if you also
    pass customCD; otherwise it just warns and does nothing.
  * `Enum.Font.Montserrat` DOES NOT EXIST and does not error -- it silently
    resolves to Gotham. Montserrat is FontFace only:
    `label.FontFace = Font.fromName("Montserrat", Enum.FontWeight.Regular)`.
  * A UIStroke defaults to ApplyStrokeMode.Contextual, which on a TEXT object
    strokes the glyphs, not the border. Parented to a TextButton with `Text = ""`
    it draws NOTHING. Set Border to outline the object itself.
  * THE STOCK SHIFTLOCK IS UNREACHABLE FROM GAME CODE. Two dead ends, both
    verified in Studio, do not retry either:
      `LocalPlayer.DevEnableMouseLock = false` -> "Insufficent permissions
        to set DevEnableMouseLockOption". Not client-writable.
      `require(PlayerScripts.PlayerModule):GetCameras()` -> `{}`. The
        vendored CameraModule ends `CameraModule.new()` / `return {}`, so
        it builds the instance and drops the reference. No
        activeMouseLockController, so EnableMouseLock/OnMouseLockToggled
        cannot be called.
    ReplicatedStorage/Modules/ShiftLock therefore NEUTRALISES it (CAS sink
    on shift + a RenderPriority.Last step that out-writes MouseBehavior and
    RotationType) rather than turning it off. Anything that needs the
    cursor back goes through `shiftLock.block(reason, true)`.
  * `stun` / `dodgeThreshold` / `canAtkThreshold` / `attackAt` / `_hyperUntil`
    are absolute `tick()` timestamps, not durations.
  * CLIENT `trueStun` USED TO BE PERMANENTLY 0. `:TrueStun` routes through
    `:Stun`, so the only packet the client ever got was S2C.stun -- a guard
    break and a jab looked identical on the wire. Both client readers of
    `inTrueStun()` were dead code for players: CharController's hard
    `JP = 0 / WS = 0`, and the shiftlock steering freeze. S2C.trueStun now
    carries it (DURATION, 0 = clear; `repl_trueStun` in HumObj -> the
    matching branch in HumObjClient). Note this WOKE UP CharController: true
    stun is now a hard root for its full duration instead of the
    `isStunned` lerp easing movement back over the last 20%. That is what
    the branch was always written to do, but it is a live feel change.
  * `HumObj:TrueStun` maxes against `self.stun.Value`, NOT
    `self.trueStun.Value`, so a long ordinary stun drags the true stun out
    with it. Reads like a typo; anything timing off true stun currently
    depends on it. Left alone: that is a balance change, not a refactor.
  * ...EXCEPT `stun.Value` is ZEROED on parry, to hand the parrier their
    punish (HumObj, the onAttacked isParried branch). So `stun.Value + X` is
    a BROKEN idiom: `tick() < 0 + X` is false forever, and the gate does not
    soften, it SWITCHES OFF. THE COUNTERS NO LONGER USE IT: they ask
    `humObj:canCounter()`, which reads the `_lastHit` / `_lastBlocked`
    stamps instead. Still live at attackHelpers/sprint and
    attackHelpers/arial, which are arguably INTENDED (parry punish,
    COMBAT 5.2) -- decide, don't blanket-fix.
    Do NOT "fix" it by writing `tick()` instead of 0: that 0 is the WIRE
    sentinel BOTH ways (HumObj `repl_stun` encodes `number == 0 ->
    duration 0`, HumObjClient decodes `value == 0 -> clear`).
  * `resolveBlock` NEVER calls `:Stun`. Blocking does not stun you, so
    `stun.Value` goes stale while you hold guard. "Am I under pressure right
    now" is `_lastBlocked`, never `stun`.
  * `_lastBlocked` is stamped on ABSORBED HITS (blocked/parried) as well as
    on `blocking.Value` edges. Edges only was the old behaviour and it let
    the stamp expire mid-combo while the guard was still up.
  * `_lastHit` is its twin, stamped in the onAttacked isHit branch. The pair
    is what `HumObj:canCounter(t)` reads, and the reason it reads stamps
    rather than `stun.Value` is the two entries above: a DEADLINE gets
    overwritten (parry zeroes it, resolveHit's mutual-hit reset bare-writes
    it down to tick()+0.1), a STAMP of when it happened cannot be.
  * `floating` is a duration-ish NumberValue used for air combos, and it also
    inflates weapon hitboxes. Leaving it set makes hitboxes permanently larger.
  * Both hitbox helpers add `AssemblyLinearVelocity/14` to the CFrame when
    running on the CLIENT (`RunService:IsClient()`), for lag compensation.
    Server and client hitboxes are deliberately not identical.
  * `game.Debris:AddItem` is the standard cleanup everywhere. Prefer it over
    naked `:Destroy()` in delayed paths so a mid-swing error can't leak parts.

## HYPER ARMOUR (`_hyperUntil`)
  * needs to be rewritte..

## REQUIRE CYCLES (full detail in ARCHITECTURE.md)
  * A TYPE-ONLY `require` is a REAL dependency. Luau resolves requires
    lexically, so "I only wanted an annotation" and "it's inside a function so
    it's lazy" both still form a cycle. Three such lines in DmgUtils once
    tangled THIRTEEN modules into one component.
  * Need only types? Require the `types` LEAF child, never the class:
    `HitboxClass.types`, `WepBase.types`, `Modules/atkType`. A leaf requires
    nothing. Requiring a CHILD does not pull in its PARENT.
  * TESTED TRAP: pointing `WepBase.types` at `HitboxClass` directly (to "cut
    out the DmgUtils middleman") RE-FORMS the cycle via
    HumObj -> WepBase.types -> HitboxClass -> HitBox -> EntityLookup ->
    Entities -> HumObj. Go to the leaf instead.
  * The lazy in-function requires in `EntityLookup` and `HitBox` are
    belt-and-braces now, not load-bearing. They STAY. Don't hoist them.
  * Roblox prints only ONE arbitrary path through a cycle. The modules it names
    are usually a SUBSET of what's actually tangled.
