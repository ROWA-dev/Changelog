# CLASSES - core class hierarchy & combat primitives
(index: parent ServerStorage/README.md)

## 1. THE 3-TIER CHAIN
  ReplicatedStorage/Class/EntityBase.luau     shared base (client + server)
  ReplicatedStorage/Class/HumObjClient.luau   movement/combat state, BOTH sides
  ServerStorage/ROWA/Class/HumObj.luau        SERVER-ONLY authoritative layer

HumObjClient does `setmetatable(module, { __index = baseClass })` where
baseClass = EntityBase. HumObj does the same with baseClass = HumObjClient.
Each `.new(hum)` calls the tier below first, then re-setmetatables that same
table. Types compose the same way (`baseClass.myself & { ... }`).

### a) EntityBase (ReplicatedStorage/Class/EntityBase.luau)
Thin wrapper around any Humanoid, players AND NPCs.
  Fields:  Name, isActive, entityId (auto-incrementing), Hum, HRootPart, Janitor
  Signals: beforeAttacked, beforeAttack (attacker side), onAttacked, onAttack
  Methods: :Damage(amt)            -- flat `Hum.Health -= amt`
           :HandleAttack(atk, src) -- stub, returns 0 ("ready"); overridden by HumObj
           :LoadAnimation(anim)    -- lazily creates an Animator if missing
           :AddConnection/:RemConnection (Janitor passthrough)
           :destroy()              -- destroys playing tracks + signals, clears table

### b) HumObjClient (ReplicatedStorage/Class/HumObjClient.luau)
Adds the state both sides need to read/predict.
  BoolValue-ish:   attacking, blocking, sliding, sprinting
  NumberValue-ish: stun, trueStun, floating, posture (80), mana (0), parryWindow (0.2)
  ObjectValue:     targetFloatY  (who you're air-comboing against)
  AdditiveValue:   timeScale(1), slideSpeed(28), sprintSpeed(14), maxPosture(80),
                   maxMana(100), walkSpeed(13), dashPower(50), postureHeal(2), charSize(1)
  Owns: cooldowns (cooldownsClass), charAnims, limbTrails
  charAnims + limbTrails are LAZY and hold INSTANCES: a track loads on first
  read of the field, the trail set builds on the first enable(true) or
  indicator*(). Test one with rawget; reading is what allocates.
  howIsaveRuntimeRAM #0 has the measurements and why it matters.
  Default cooldowns set here: dashCancel 1.5, dash 1.5, slide 2
  CharAnims solely owns lazy tracks; locomotion profiles override Walk/Sprint
  by one owner-only id and fall back per field.
  Methods: :setupController, :ChangeSprinting, :ChangeSliding, :stopDash,
           :Stun(t, bypassArmour?), :TrueStun, :inStun(offset?), :inTrueStun,
           :isKnocked, :canBeKnocked,
           :isSwimming,
           :canDash, :Dash, :DashCancel, :PlayTrack, :PlayAnim,
           :initReplicateClient
  Children: CharAnims, CharController, setupCharacter, setupLimbTrails,
            replIds (THE wire id registry, S2C + C2S, read by both tiers)
  Signals: onDash, onDashCancel

  HYPER ARMOUR: `_hyperUntil` is an absolute tick() timestamp on the class
  table (default 0 = never). While tick() < _hyperUntil, :Stun REFUSES TO
  WRITE unless bypassArmour is passed. :TrueStun always passes it, so true
  stun pierces armour. Every TrueStun caller is a punish or a grab cinematic,
  so that split needs no per-caller config.
  Owned by Class/StatusEffects/HyperArmour; do not set it by hand.
  Same gate exists on SimpleEntity and TestDummy, so all three Combatant
  implementers behave identically.

  Consumed on the client via ReplicatedFirst/ClientData/ClientClass.luau
  (`self.HumObj = HumObjClass.new(hum)`), and subclassed on the server by HumObj.

### c) HumObj (ServerStorage/ROWA/Class/HumObj.luau) SERVER ONLY
  Extra fields: plrObj, wielding_weapon, using_ability, equippedWeapons,
    maxWeapons (AdditiveValue, 1 -- the WIELDED SET cap, card-modifiable via
    SetMod; Many-Handed is the +1. NOT dual wielding, only one is ever
    wielding_weapon),
    heldWeapon (drawn but uncommitted, in hand, inert),
    sideWep (the OFF HAND, one slot. :EquipSideWep replaces + destroys the
    old one, :useSideWep is the bind entry and is inert without one.
    setWieldingWeapon FORWARDS to sideWep:onWieldChanged, so that hook dies
    with the side weapon instead of needing a connection),
    dmgRecord, cards, ragdoll, statusEffects, grab,
    knockedHp (LAZY, nil unless currently knocked down -- see 3.5),
    hurtboxSize (AdditiveValue), HurtBox (BasePart, cloned from script.hurtbox
    and welded to HRootPart), isDead,
    healthHeal (AdditiveValue, 1 -- UPRIGHT health regen multiplier, server
    only since health regen is; KNOCKED_REGEN ignores it on purpose),
    canAtkThreshold, dodgeThreshold, dodgeWindow (0.3), attackAt
  Extra cooldowns registered in .new(): feint 2, feint2 2, parry 1.2
  Signals: onAttackWindup(t), onStunned(t)

  Key methods:
    :HandleAttack(attack, atkSource) -- THE damage resolver, see section 3
    :canAttack / :canBlock / :canCounter(t?)
    :isParry(atk?) / :isBlock(atk?) / :isDodge(atk?, offset?)
    :GuardBreak, :feint, :Heal, :Die, :setTransparency, :GetBlade
    :isKnocked()       -- derived from health, never stored. see 3.5
    :Damage(amt)       -- OVERRIDES EntityBase: carries the death stall
    :EquipWeapon(wep)   -- SELECT. never fails. in the set -> active; not in
                           the set -> held out (inert). See WEAPONS 4.
    :WieldWeapon(wep?)  -- COMMIT. `req`-gated, joins the wielded set, evicts
                           the oldest when full. Defaults to heldWeapon, which
                           is how M1 turns holding into wielding.
    :canWield(wep)      -- (ok, reason). NPCs (no plrObj) always pass.
    :UnwieldWeapon() / :UseAbility(ability)
    :ChangeBlocking, :ChangeState, :stopAbilityAnims, :bodyForce
    :FireVFXClient(...)  -- only fires if self.plrObj exists (NPCs are no-ops)
    :initReplicateServer(remoteEvent, plr)

  Its `onAttacked` connection (set up in .new) does:
    - blocked  -> FireAllClients("block", root, dmg, weight, atkDir)
    - parried  -> resets parry cooldown, zeroes stun + canAtkThreshold, unragdolls
    - hit      -> stamps `_lastHit` (twin of `_lastBlocked`; the pair is what
                  :canCounter reads, because `stun.Value` is a deadline other
                  code overwrites),
                  cancels your own windup anim if you were about to swing,
                  "feint read" Mambo jeer sound if hit inside the 0.2s to 0.8s
                  window after your enemy feinted,
                  blood emission scaled by damage (slash flag = double count),
                  land-hit walkspeed buff (+4 for ~2s) and dash cooldown reset,
                  air-combo `floating` handoff (both entities float, each one's
                  targetFloatY points at the other's HurtBox)

## 2. THE REGISTRY - ServerScriptService/Entities.luau
  `Entities.Get(inst)` -> entity (lazily registers, memoized).
  Keyed by the MODEL under workspace.Entities; Get() also accepts a Humanoid
  or any child part and resolves it.
  `Entities.Register(inst, classOverride?)`, `Entities.Unregister(inst)`,
  `Entities.GetAll()`.
  Auto-destroys the entity on AncestryChanged/Destroying.
  Instances/Humanoids tagged "no_entity" return nil from Get, and so does
  anything outside workspace (a removed character is never re-registered).
  (Was Humanoids.luau, now DELETED. The CharacterRepli.OnServerEvent hook
  moved to ServerScriptService/CharacterRepliHandler.luau and is started
  EXPLICITLY from Core.luau via `require(sss.CharacterRepliHandler).start()`.
  It routes client-replicated data into `entity.SubscribedEventCB(id, ...)`.)

## 3. AttackClass (ServerStorage/ROWA/Class/AttackClass.luau)
One discrete hit. Built via `wep/ability:makeAtk(dmgTbl, enemyHum, atkDir?)`.
  Fields: dmgTbl, myEntity, enemyEntity (both resolved via Entities.Get),
          atkDir, dmgMult (1), postureMult (1), status (0), plus optional
          .hitbox / .knockback that the attack script assigns after construction.
  Status checks: :isHit :isParried :isBlocked :isDodged :isAborted :isWep
  :hasDmgFlag(flag)
  :CalculatePostureDmg()  -- (dmg * posMult + knockbackForce^0.8) * postureMult
  :CalculateDamage()      -- dmg * dmgMult
  :ApplyKnockback()       -- applies self.knockback, and constructs a secondary
                             "smash" attack (blunt/Heavy/20dmg/0.6stun/posMult 4)
                             for wall-smash impacts
  :Execute(atkSource)     -- aborts if either entity is gone/inactive, fires
                             my.beforeAttack then enemy.beforeAttacked:FireSync
                             (outgoing modifiers first; cards can abort in either),
                             then calls enemyEntity:HandleAttack(attack, atkSource)
  :onAttackReturn(enum, src) -- sets status, fires enemy.onAttacked + my.onAttack

### HandleAttack resolution order (HumObj)
    1. isDead                 -> returns nil
    2. isParry(attack)        -> FireAllClients("parry", ...), stuns the ATTACKER
                                 (Heavy: 0.3s stun + 0.4s threshold, else 0.4s +
                                 0.5s; overridable per-dmgTbl via `stunMeOnParried`),
                                 calls atkSource:onParried(attack),
                                 posture traded both ways minus wep.postureGain
                                 -> returnEnums.parried
    3. isDodge()              -> returnEnums.dodged
    4. isBlock(attack)        -> posture -= postureDmg; if posture still > 0:
                                 plays a block sound picked by weight+slash flag,
                                 :ApplyKnockback(), atkSource:onBlocked(attack)
                                 -> returnEnums.blocked
                                 else falls through to :GuardBreak()
    5. otherwise              -> :ApplyKnockback(), :Damage(CalculateDamage()),
                                 dmgTbl.onHit(attack, atkSource),
                                 dmgRecord:addEntry, :Stun(dmgTbl.stun),
                                 if BOTH are stunned, both stuns reset to +0.1s
                                 (prevents the mutual-stun stare)
                                 -> returnEnums.hit

### 3.5 THE DEATH STALL / KNOCKED DOWN  (HumObj:Damage)
  Port of rowa1 AttackModule:685. A blow that would leave you at or below
  KNOCK_HP (5) does NOT kill: health clamps to 1 and you are pinned in a
  flat ragdoll. Damage after that drains `knockedHp` (40) instead of
  health; the pool hitting 0 sets Health = 0.
    :isKnocked()  DERIVED, `Health <= 5 and MaxHealth > 5 and not isDead`.
                  Never stored, so ANY route to low health knocks you and
                  the state cannot desync.
    knockedHp     LAZY -- nil until first knocked, nil again on getup, so
                  an entity that never goes down holds nothing.
  GETTING UP is the health regen crossing back over KNOCK_HP. There is no
  timer and no extra loop: the check lives inside the health regenLoop step
  that already runs once a second, and KNOCKED_REGEN is the only knob
  deciding how long you lie there.
  TWO THINGS HOLD YOU DOWN, and they fail differently. The ragdoll loop
  RE-ISSUES ChangeState(Physics) whenever the humanoid has slipped out of
  it, because Physics is not sticky -- the state machine returns to Running
  or Landed by itself and then walks an upright body around wearing a
  dangling ragdoll. !! DO NOT "FIX" THAT WITH PlatformStand: it hands the
  character back to the humanoid controller, which takes the limbs'
  collisions with it and drops the arms through the floor. The Physics
  state is load-bearing.
  !! THAT LOOP ONLY HOLDS NPCs. ChangeState from a Script requires the
  SERVER to own the character -- Roblox documents it on the method -- so it
  is a no-op on every player's own body and on any victim being dragged,
  since the grabber owns those. Those are held on the peer that simulates
  them, by VFXQuiver/ragdollc, which is also why SetStateEnabled has to be
  re-sent per peer: it does not replicate in either direction.
  !! ROOTJOINT STAYS ON. The Motor6D loop walks char.Torso -- Neck, both
  Shoulders, both Hips -- and RootJoint hangs off the ROOT, so it is never
  in that set. That looks like an oversight sitting redundantly under the
  holdTorso weld. IT IS NOT: disabling it makes a ragdolled body shiver
  much harder, tested. Redundant rigid joints do not fight -- the solver
  spans a tree and drops the extra edge -- and whatever the engine does
  with that pair, it wants the Motor6D there. Leave it alone.
  And `ragdoll.pinned` (KNOCK_HP) stops the ragdoll being ENDED early: the
  standard hit is `ragdoll(60, true, dir)`, so any attack landing on
  someone already down re-arms the ground release on the flat pin :Damage
  gave them. Both live in RowaRagdoll.
  THE TWO ARE WIRED TOGETHER: a refused unragdoll returns false and the
  Heartbeat above stays connected on it, because it is the only thing
  re-pinning Physics. Disconnecting first left a pinned body ragdolled with
  nothing holding the state and it stood up.
  It is in :Damage, not resolveHit, so SimpleEntity keeps the plain
  EntityBase version and the Combatant contract needs nothing.
  Death sets Health = 0 rather than calling :Die(), so the kill still flows
  through onAttacked -> onDied and the killer keeps credit.
  WHILE DOWN you have no offence, no defence and no movement tech:
  canAttack, Dash and DashCancel refuse, isParry and isDodge refuse
  (isBlock already did, via inRagdoll), and canSlide plus CharController's
  cantSlide refuse, which covers sliding, crouching and sprinting.
  The floating and dash unragdolls are gated too, so none of them is an
  escape -- the parry one needs no gate BECAUSE isParry cannot return true
  down here.
  !! `KNOCK_HP`, `isKnocked` and `canBeKnocked` live on HumObjClient, not
  here, because SLIDING AND SPRINTING ARE CLIENT-AUTHORITATIVE -- the server
  only mirrors `sliding` off C2S.sliding and nothing but StayInPlace reads it,
  so a server-side slide gate would do nothing. Humanoid.Health already
  replicates, so the client derives the same answer for zero wire cost.
  HumObj overrides isKnocked only to add the server-only isDead term.
  ROWA/Modules/execute ignores the pool and kills outright -- that is
  rowa1's `dieNow`, arriving for free.

### 3.6 DRAGGING A DOWNED BODY  (HumObj/dragBody + VFXQuiver/dragIK)
  Haul a knocked body around by ONE limb. NOT HumObj/Grab and not built on
  it: Grab welds a victim rigidly into a fixed pose off the grabber's root,
  this springs a single limb at a torso anchor and lets the rest of the
  body flop, because the victim is ragdolled the whole time.
    dragging / draggedBy   LAZY, nil unless a drag is live.
    :startDrag(victim,limb) / :stopDrag()
  TWO SHAPES, ONE CLICK, picked by the limb the client's ray named. By the
  TORSO they are SHOULDERED: a pose weld, Enabled FALSE so it stays DATA
  (a live one merges both rigs into one assembly), solved per frame by
  VFXQuiver/grabWeld -- the same mover Grab uses, so the carry needed no
  new client code. No pull, no scrape, no arm IK, and only the ROOT is
  placed, so the ragdoll drapes over you. Any other limb is the leash drag.
  NOT routed through Grab itself: Grab holds with PlatformStand, which
  pulls the humanoid out of the Physics state RowaRagdoll re-pins, and it
  restores only the root's ownership where this hands over every part.
  THE LIMBS JITTER A LITTLE AND THAT IS ACCEPTED. A CFrame write is a
  teleport, not something the solver integrates, and it lands in the render
  phase, so the ball-socketed limbs eat a positional error one phase late
  every frame -- loudly, since ragdoll limbs are density 0.1. Grab never
  showed it because its victim is one assembly with joints intact. Enabling
  the weld would delete it (every ragdoll part is Massless, so the merge is
  free once they stop being assembly roots), at the price of a shouldered
  body's knockback moving the carrier. NOT WORTH IT, decided, and not a
  paper cut worth re-deriving: the rest is what a networked ragdoll costs.
  A CARRIED BODY GOES IN THE "no" GROUP and collides with nothing, which is
  what lets the grabber still JUMP: the pose overlaps their own torso and
  root, and unstand's NoCollisionConstraints cannot be trusted to cover it
  because they pair whatever was CanCollide AT GRAB TIME -- and the torso
  only turns collidable when a slide ENDS. Interpenetrating it, the solver
  spends the jump pushing the two apart. The hurtbox keeps its own group,
  so a shouldered body is still hittable; stop() restores the group the
  ragdoll says it should have (inRagdoll -> "ragdoll", else "Default").
  THE TWO TARGETS ARE NOT EACH OTHER, and that is the whole design:
    PULL (physics)  limb -> a LEASH POINT on the grabber's TORSO, arm's
                            length out in the limb's OWN direction
    LOOK (cosmetic) arm  -> wherever the limb actually is
  Point them at each other and the error is zero every frame, so the body
  never moves and the arm tracks a limb that never lags. The anchor is on
  the TORSO rather than the Left Arm because the IK moves the arm, which
  would feed the solve back into itself.
  THE ANCHOR IS A LEASH, DERIVED NOT AUTHORED. It rides at arm's length in
  the limb's own direction, off the arm's rest top (C0 * C1^-1 up half the
  part, the exact point R6IK solves from), and engages ONLY past that
  length. The pull is therefore radial: it reels in, never sideways, so the
  body swings freely instead of being sprung back under your hand.
  IT RELEASES AT A SHORTER RADIUS THAN IT GRABS (SLACK), and the band
  between the two is dead -- no anchor write, no Enabled write. One radius
  toggled the whole hold every time a slow walk or a turn crossed it, which
  read as the hand letting go for an instant, and each toggle is a
  replicated property change against a constraint simulating on the
  grabber's client.
  AND THE RELEASE IS DEBOUNCED (SLACK_POLLS) on top of that, because the
  band answers noise around the radius but not a fast pass through it: the
  pull has no MaxVelocity, so a standing start or a dash reels the limb in
  hard enough to overshoot clean through the band and drop the hand mid-
  yank. Real slack outlives a poll; momentum does not. The AlignPosition is therefore born DISABLED too: in
  the band nothing writes Enabled, so a grab made inside arm's length would
  otherwise keep the resting anchor and pin the body under your hand.
  The radius is arm's length because R6IK AIMS a one-part R6 arm and never
  bends it -- a bend puts that single part on the forearm and slides it a
  stud off the shoulder, which is what "dislocated" looked like -- so the
  solved hand is always exactly arm's length out, i.e. ON the leash.
  Do not shorten it to be safe; that IS the bug. Nor pass R6IK's `stretch`
  here: it lands the hand PAST that radius on purpose, and only pianoIK
  wants that.
  FORCE scales off the victim's WHOLE mass (~10x body weight), not the held
  limb's assembly: a ragdolled limb is its own assembly and a fraction of
  the body, so limb-sized force lost to the friction of the parts it tows.
  THE BODY SCRAPES: a LinearVelocity at zero in the horizontal plane with a
  small MaxForce is friction (constant opposing force, capped) rather than
  a spring, so a dragged body has weight instead of gliding. A constraint,
  not an impulse, because it simulates on whichever peer owns the body --
  the grabber's client, where a server impulse would never land. Sized off
  workspace.Gravity, which is 140 here, not the default 196, and DILUTED:
  it brakes the root's assembly only, so the other five limbs tow freely
  and one body weight there reads as about a quarter across the rig.
  YOU CANNOT STAND ON A BODY YOU HAUL, or you ride it up / get flung. No
  collision group can say that -- a character's only colliding part is its
  root in "Default" and the MAP is "Default", so excluding the player drops
  the body through the floor. NoCollisionConstraint is per PAIR: 7 of them,
  parented to the hold so they die with it.
  THE SLINGSHOT ON RELEASE was not here: CharController brakes a `norepli`
  root every frame, and while dragged that root belongs to the GRABBER, so
  the victim's client walked its own copy backwards and the ownership
  handback made that copy true. It is gated on ReceiveAge == 0 now.
  THE PAUSE IS THE REGEN. Nothing blocks standing up directly: the health
  regen step skips its add while `draggedBy` is set, and getting up IS
  health crossing KNOCK_HP (3.5), so the clock simply stops.
  OWNERSHIP follows Grab's rule (grabber first, their arm is the input to
  the solve) with one difference: a ragdolled body is ONE ASSEMBLY PER
  LIMB, so ownership is set over every part, not just the root.
  THE STATE PIN TRAVELS WITH IT. The humanoid state machine runs on the
  owner, so start() fires `ragdollc` at the grabber's client (which never
  ran setupCharacter on that rig, so every state is stock-enabled there)
  and stop() hands the rig back to stock. Without it the grabber's own
  client got the victim up mid-drag, hip height and all, joints still off.
  THE SERVER CANNOT COVER FOR IT: its re-pin is a ChangeState on a body a
  client owns, which does nothing. So ragdollc PARKS the state machine on a
  foreign rig -- every state disabled but Physics and Dead -- rather than
  pinning it once and hoping. A pin left the controller free to wake on any
  floor contact, which is the body stiffening against the leash for a
  moment when you start running or dash.
  INPUT rides the existing startLight -- bindFuncs/light raycasts, PIERCES
  HURTBOXES, and passes the limb as an argument. No input enum, no keybind,
  no plrData version bump. The drag wins and feints the swing; if startDrag
  refuses, the click falls through and swings normally.
  dragIK is cosmetic on every peer: it writes Motor6D.C0, which does not
  replicate, so each client poses the arm itself and the server never does.
  Nothing in combat reads the arm -- hitboxes resolve against the hurtbox.
  IT CLAMPS THE AIM to the grabber's own left face in torso space, because
  R6IK has no joint limits and a Motor6D constrains nothing, so a body
  swung to their right was drawn as a straight arm through their chest.
  The aim only, never the pull.
  ANIMATIONS DO NOT FIGHT IT ANY MORE: R6IK divides the joint's live
  Transform out of the C0 it writes, so the walk cycle stops composing onto
  the solve. Posing into Transform instead does NOT work -- the Animator
  refills it every frame and the arm just plays the animation. dragIK binds
  at RenderPriority.Character + 1 only so the Transform it divides out is
  the one the animator just wrote. R6IK is the only copy, R6IK_og is deleted.

## 4. HitboxClass / raw hitbox
  ServerStorage/ROWA/Class/HitboxClass.luau: value object holding
  {cf, sz, op, ignoreHum}; :hit() delegates to ServerScriptService/HitBox.luau.
  HitBox.hitbox(cf, sz, overlapParams, ignore) does GetPartBoundsInBox and
  returns ENTITIES deduped on `entityId`, resolved via EntityLookup.fromPart.
  (It used to return {Humanoid} deduped on the Humanoid. HitboxClass.types
  still SAYS `{Humanoid}`; that type is knowingly stale, see
  ARCHITECTURE.md.) `ignore` is the attacker's Humanoid at every current
  call site, compared against the resolved entity's `.Hum`; an entity works too.
  It also fires the Hitboxes RemoteChannel so subscribed players see debug
  hitbox visuals (ReplicatedFirst/LocalCore/VisualHB via FastRemotes.Hitbox).

## 5. KnockbackClass
  ServerStorage/ROWA/Class/KnockbackClass.luau: value object {force, t, isRR, decayT}.
  :apply(root, onSmashAtk) delegates to ServerScriptService/Knockback.luau, which
  builds the actual body mover, and for players fires a "kb"/"kbd" VFX id so the
  owning client runs the mover locally instead of the server fighting replication.

## 6. DmgUtils (ServerScriptService/Utils/DmgUtils.luau)
  dmgFlags (bitflags, combine with bit32.bor):
    blank 1, slash 2, blunt 4, weaponM1 8, weaponHeavy 16, magic 32,
    ice 64, lightning 128, fire 256, earth 512, wind 1024, shadow 2048, blood 4096
  weighEnum: Heavy 1, Medium 2, Light 3
  returnEnum: ready 0, hit 1, parried 2, blocked 3, dodged 4, aborted 5
  Helpers: hasDmgFlag, isWeaponAtk (M1|Heavy mask), isElemental, isPhysical

  dmgType shape:
    { weight, type, dmg, stun, posMult,
      onHit?, stunMeOnParried?, parryH?, dodgeH? }
    parryH/dodgeH are ADDED to the defender's window. Negative = harder to
    parry/dodge, which is how heavies feel scarier.

## 7. cooldowns (ReplicatedStorage/Class/cooldowns.luau)
  ONE class. There is no per-cooldown object any more: three parallel
  {[id]: number} maps (_cd registered duration, _last absolute expiry,
  _lastUsed), so an entry is 3 hash slots and NOT a table + Signal +
  closure + connection. cooldown.luau is DELETED.
  humObj.cooldowns:setCooldown(id, seconds, dontOverwrite?)
                  :trigger(id, customCD?, dontOverwrite?)   -- creates it if
                     it doesn't exist AND customCD was given
                  :quietTrigger(id, customCD?)  -- no Triggered signal
                  :canTrigger(id, offset?)      -- TRUE if the id doesn't exist
                  :Reset(id), :lastUsedAt(id)
                  :duration(id)  -- registered seconds, nil = no such id
                  :remaining(id) -- seconds left, negative when ready
                  :clearLastUsed(id) -- forget the stamp, keep the cooldown
  Signals: CooldownChanged(id, value), CooldownTriggered(id, value)
  !! `trigger` is MONOTONE (`_last = max(_last, now + cd)`) and NEVER rewrites
  a registered duration once the id exists. So a short cooldown can never
  shorten a running long one, and `customCD` passed with dontOverwrite after
  the id exists does nothing at all. A "refund" written the obvious way is a
  silent no-op: tiered cooldowns must go SHORT FIRST, then full. See
  ABILITIES.md section 5, which is where this bit three abilities.

## 8. AdditiveValue (ReplicatedStorage/Packages/AdditiveValue.luau)
  Stackable numeric modifiers: Value = base + sum(mods). O(1) reads.
    v:SetMod("key", n) / v:GetMod("key") / v:RemoveMod("key")
    v.Value is READ-ONLY (assigning throws). Signals: onSet, onRemove --
    LAZY, reading one allocates it, so test with rawget. `_mods` is nil
    until the first SetMod.
  How buffs/debuffs/cards stack without stomping each other. Common mod keys:
  "feint", "Ifeint", "antiASwing", "stopMoving", "landhit", "wep".

## 9. Other server classes
  Class/StatusEffects.luau   :apply(effect, duration, ...) / :remove(effect),
                             auto-cleanup keyed by effect NAME, so applying
                             twice refreshes instead of stacking.
                             `debuffMult` scales a DEBUFFS entry's duration
                             + amp on the way in; that set is the one
                             "is it harmful" list.
                             Burn / Shock / Bleed / Blind / Hemorrhage /
                             HyperArmour / Reflect / EarthArmour / Saringan /
                             Freeze. Freeze is the odd one: a BUILDUP METER,
                             and the full encase CLEARS Burn (one-way, ice
                             beats fire). Nothing else cross-cancels.
  Class/HumObj/cardLoader    :addCard(id) / :hasCard(id) / :remCard(id),
                             card definitions listed in ROWA/Cards.luau.
                             Entries are {id, card}, and `card` is the error
                             STRING when a load failed -- bin one through
                             destroyCard, never `v:destroy()`.
                             HumObj.destroy runs this FIRST, before the
                             AdditiveValues cards RemoveMod on.
  Class/HumObj/damageRecord  who-hit-me log, drives :inCombat()
  Class/HumObj/RowaRagdoll   :ragdoll(t, stopOnGround?, rollForce?) /
                             :unragdoll(getup?). `getup` opts into the
                             orientation-picked getup animation
                             (getupAnims/bellyup|bellyup2|bellydown);
                             only the knockdown getup passes it today.
  Class/HumObj/Grab          :grab(byHumObj) / :release()
  Class/RemoteChannel        subscribe/unsubscribe player lists for a RemoteEvent
