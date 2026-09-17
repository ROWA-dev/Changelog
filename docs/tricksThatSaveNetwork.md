# tricksThatSaveNetwork - the wire playbook
(index: parent ServerStorage/README.md)

WIRE BYTES ONLY. Not Luau heap (howIsaveRuntimeRAM), not save payload
(DATASTORE), not which VFX system to pick (VFX). This is what
leaves a machine, how often, and why it is that small.

## THE ONE IDEA
    SEND THE CAUSE, NOT THE CONSEQUENCE.

A parameter instead of a sample stream. An edge instead of a poll. An
operation instead of a snapshot. A duration instead of a clock. Almost
every entry below is the same move: hand the receiver enough to DERIVE the
rest, then say nothing until the derivation stops being true. When you add
a channel, the question is not "is this small", it is "how many times does
this fire per second per player". That question alone kills most designs.

## THE PATTERNS, IN THE ORDER THEY ARE WORTH COPYING

### 1. Mana is a solved ODE. Regen costs ZERO packets.
  ReplicatedStorage/Class/HumObjClient (manaNow/setMana)  +  S2C.mana
  Regen is dv/dt = K*(1 - v/M)^3, K = 3, solved exactly:
      u = 1 - a/M
      v(now) = M * (1 - u / sqrt(1 + (2K/M) * u^2 * (now - t)))
  So the wire carries ONE anchor -- the value at the last real write --
  and both sides evaluate the same closed form on read. Nothing ticks on
  either side. `mana.Changed` means RE-ANCHORED, not "mana changed", so
  the only packets are spend, gain and max-change.
  THE VALUE GOES DOWN, NOT THE TIMESTAMP: the client stamps its own `t`
  on receipt, so no clock-sync protocol is needed (that would be traffic
  of its own). Cost, stated: the client trails by one ping of regen, <=1
  mana at empty, and it does NOT accumulate -- every re-anchor corrects.
  Change the exponent and the 2K/M term has to be re-derived.

### 2. The Changed signal IS the wire, so a no-op write is free.
  ReplicatedStorage/Packages/valueBase  +  HumObj:initReplicateServer
  `__newindex` compares `old ~= new` before it fires. Every row of HumObj's
  `valueRepl` table is a `.Changed` connection, so an identical write is
  not a small packet, it is NO packet. (Ids live in HumObjClient/replIds.)
  This composes with MONOTONE MAX. `stun.Value = math.max(stun.Value,
  tick() + t)` returns the OLD value when the incoming stun is shorter,
  so spamming a short stun inside a long one is literally free. Same
  shape in cooldown.Trigger (`last = math.max(last, now + cd)`).
  Write the accumulate-and-compare in that order and the dedupe is
  automatic; write `if new > old then set end` by hand and it is not.

### 3. rawset to integrate without replicating.
  HumObj regenLoop (posture)  +  HumObjClient/CharController:301
  Posture regen is linear and both sides run it. Both sides therefore
  write it with `rawset(posture, "v", ...)`, deliberately going AROUND
  __newindex so a 60Hz integration never fires Changed. The comment at
  the client site says it plainly: "using rawset so serverside doesnt
  send client updates to save bandwidth". Discrete events (a hit) still
  go through `.Value` and re-anchor both ends.
  Known cost, in-source: a client hitch loses regen the server granted.
  The mana anchor shape (#1) is the fix if that ever matters.

### 4. AdditiveValue replicates the OPERATION, not the total.
  ReplicatedStorage/Packages/AdditiveValue
      SetMod    -> (id, 2, key, num)
      RemoveMod -> (id, 1, key)          <- carries no number at all
  Both ends keep the same O(1) running sum, so the resulting total is
  never transmitted, and a mod changing does not re-broadcast the other
  eight. Nine AdditiveValues ride ONE RemoteEvent, each filtering on its
  own `repli_id` -- the AdditiveValue rows of replIds.S2C.
  Declared tradeoff, in its own header: replication MISSES drift, same
  as float drift. Prefer integer mods.

### 5. Durations on the wire, timestamps locally. 0 is the sentinel.
  HumObj repl_stun / repl_trueStun  ->  HumObjClient S2C.stun / S2C.trueStun
  Locally these are absolute `tick()` stamps; on the wire they are
  seconds remaining, and the receiver does `tick() + value`. Two clocks
  never have to agree. `0` means CLEAR in both directions and both
  encoders/decoders know it -- see the GOTCHAS warning about not
  "fixing" that 0 into a `tick()`.

### 6. Combat membership is an EDGE, and the timer that expires it is
     also the client's clock correction.
  S2C.combatEdge  +  HumObj/damageRecord  +  StarterGui/combat/combatantsUI
  `(enemyModel, joined, remaining?)`. Two packets per enemy per fight
  plus one correction per TTL -- never a stream. DEATH is the other leave:
  onDeath -> dmgRecord:leaveAllFights, because the timer cannot see a kill.
  That reads the `memberships` back-edge that addEntry writes, so it costs
  O(my fights) and needs no walk over every entity alive.
  Refreshes on every hit
  are SILENT by design, because a packet per hit is exactly what this
  shape avoids.
  THE SELF-CORRECTION IS THE CLEVER HALF. Silent refreshes make the
  client's countdown drift SHORT. The self-re-arming expiry `task.delay`
  wakes at the deadline the client is counting to, notices time is left,
  and re-sends the remainder -- so the correction always lands on exactly
  the frame the client needed it, at one packet per TTL per enemy.
  ONLY THE MODEL GOES DOWN. Health, posture, name and position are read
  off the Model, which is already replicated. Client-side `combatDeadline`
  is ONE float (the max), not a per-enemy table, because combat ends when
  the last entry expires.
  `onEdge` is nil by default, so NPC-vs-NPC arms no timer and sends
  nothing. Being inside initReplicateServer IS the player gate.

### 7. The server holds no projectile Instance.
  ROWA/Class/Projectile  +  ReplicatedStorage/Modules/projFx
  A projectile is a table in a flat array. Clients integrate their own
  copy from the spawn numbers. rowa1 moved a Part from the server every
  frame -- a physics and replication packet per projectile per frame.
  The two things a client CANNOT derive come back down `projSteer`:
      sync.steer  a parry DEFLECT (pos, dir, speed, target). Consumed.
      sync.dead   the flight being over. Sticky.
  ONE packet per deflect, not per frame, and nothing at all for the
  overwhelming majority never deflected. `ended` rides the same packet
  because it wants the same two fields.
  THE BOUNCE RULE IS SHARED CODE, NOT A MESSAGE. Both ends already know
  a deflect happened and both raycast the same geometry, so a parried
  shot reflecting off the floor replicates nothing.
  Cost, stated plainly in the header: a projectile can visually miss and
  mechanically hit by roughly one ping.

### 8. Fields are FOUND BY TAG, never sent.
  ReplicatedStorage/Modules/gravWells  +  Abilities/FullBlue
  A gravity well is not a thing that pushes, it is a thing that EXISTS.
  `apply` is a pure function of position and the tagged parts, called
  once per frame by the server's projectile step AND by every client's
  fx. No packets, no enumeration, no new channel. Registering one is a
  tag plus three attributes, which replicate WITH the part instead of
  racing it -- "no packet, no per-frame correction and no teardown to
  forget".
  !! THE REASON IT IS A TAG AND NOT AN ARGUMENT: StreamingEnabled is on,
  and an Instance handed to a client over a remote arrives PERMANENTLY
  NIL if that client has not streamed it in -- silently, both sides. No
  wait closes that race. Anything a far-away client cannot see, it also
  does not need.
  CAVEAT, so this is not read as free: the QUERY costs no packets, the
  well's MOTION does. FullBlue steers `field.Position` from the server
  every frame for its 4s life. That is a DECLARED exception, not an
  oversight -- its header: "The server owns the part against the usual
  rule: its position IS the hitbox origin." One part, bounded.

### 9. Hand the body to its owner and send PARAMETERS.
  ServerScriptService/Knockback  +  VFXQuiver/kb, kbd  +  Utils/bodymover,
  decaymover
  If the root has a network owner, the server fires ONE `kb` packet --
  (forceVector, root, t, isRootRelative, decayT, decayBias, id) -- and
  that client builds the LinearVelocity locally and runs the decay curve
  `v0 * ((endT - now)/decayT)^bias` on its own frames. Zero per-frame
  traffic for the whole knockback. The server only builds the mover when
  `GetNetworkOwner() == nil`.
  Teardown is ONE INTEGER: `kbd`, id, resolved through Modules/kbTable.
  HumObj:ChangeState is the same instinct -- tell the owning client to
  change its own Humanoid state rather than writing it server-side and
  replicating the result. NPCs (no plrObj) take the direct branch.
  Grab extends it: `weld.Enabled = false` keeps the joint as DATA,
  ownership goes grabber -> victim -> nil, and EXACTLY ONE PEER solves
  it. Two writers on one body is where the strobe came from.

### 10. VELOCITY IS THE COMPRESSION. (dead reckoning)
  VFXQuiver/grabWeld  +  HumObj/Grab.velocityFor -- keep the two in step
  A driven body only LEAVES its owner at the replication rate, not at the
  rate you write it, and every other peer fills the gaps by extrapolating
  from the velocity that came with the packet.
  So `AssemblyLinearVelocity = Vector3.zero` on a CFrame-driven body says
  "stopped here": receivers park on each received point and jump to the
  next, and the send tick becomes visible no matter how smooth the writer
  is. Handing over the REAL frame-to-frame motion lets that extrapolation
  land on the truth.
  You buy smoothness with a field you are ALREADY SENDING, not with a
  higher send rate. Do not put the zero back.

### 11. The fast lane is ONE PART, not the rig.
  ReplicatedFirst/init/FastRootRepliClient  +  Core.luau FAST REPLI
  +  FastRemotes/FastRoot (UnreliableRemoteEvent)
  Outbound, the owner sends its own HRP CFrame through three gates:
      rate cap    1/128s
      dead band   0.05 studs, or LookVector/UpVector dot < 0.9998
                  (~1.15 degrees)
      liveness    IsSlotLoaded()
  Standing still sends NOTHING. The server writes it onto the `hurtbox`
  part only -- so the fast channel costs one part, and the other rig
  parts follow through Motor6D on each client for free.
  Inbound, peers anchor the other player's HRP and lerp it at
  `alpha = 1 - exp(-20*dt)`, the framerate-independent form of a
  per-frame lerp, computed ONCE per frame because dt is loop-invariant.
  UNRELIABLE IS CORRECT HERE: a dropped pose is superseded by the next
  one, so retransmission would deliver stale news late.
  HitboxQuery queries the hurtbox FIRST ("it is the fast-replicated
  box") and only retries from the real root on a miss -- lag comp bought
  with a second local query instead of more traffic.
  Known scar, in-source: the client reparents a SERVER instance to keep
  it out of streaming. Clean fix is server-side (park hurtboxes in a
  workspace folder); read that file's ponytail notes first.

### 12. Send the DISTRIBUTION, not the samples.
  FastRemotes/blood (unreliable)  +  ReplicatedFirst/LocalCore/Blood
      (emitCount, root, spread{}, speed{}, size{}, extraVelo?)
  One small packet describes a whole spray; each client rolls its own
  math.random per droplet and spreads the work across frames. N particles
  cost one packet, not N replicated Parts. Guard-break bleed is the same
  call at 10Hz with emitCount 1.
  Destruction is the same move at a bigger scale: `Grab` RETURNS DATA,
  NOT PARTS, because anything the server owns and animates has its CFrame
  replicated with interpolation on top -- a nine-piece assembly would
  stutter for everyone but the host AND spend bandwidth doing it. Callers
  build their own from the descriptors and "the effect costs one event".
  The same cuboids are then WITHHELD from the dbri payload so nobody
  draws a second ghost copy.

### 13. Sustained effects are a LEASE plus a cancel sentinel.
  VFX section B  +  Modules/fxFade  +  Modules/aerialAim
  A channel sends `(root, duration)` once and `duration <= 0` means "end
  the one running on this root NOW". A whole channel is two packets, and
  one if it runs to completion -- never a per-frame keepalive.
  aerialAim states the general rule: MAXTIME IS A CEILING, NOT A
  DURATION. The client releases itself when it expires, so an error
  upstream cannot strand a player and the failure path needs no stop
  packet at all. Server side is one local `stopX()` called on every
  early-exit branch.

### 14. PULL, don't push.
  Modules/ReplicateEnums (C2S.RequestSlotInfo)  +  plrObj/replication
  plrStats increments on every hit, so pushing it would be a packet per
  swing. The settings Slot tab ASKS once when it opens; the server gates
  it to 1/s and answers with everything that tab shows, resolved
  server-side (SparseBitSet, Cards and StatPair never have to reach the
  client at all). NewSlot and RenameSlot have their own gates; rename's
  is longer because it also makes a TextService call.
  Same instinct in processXp: MIN_SHARE 0.05 means chip damage earns
  nothing, which "also saves a packet, since giveExp applyPatches".

### 15. Patches, not snapshots.
  PlrData/Slots/slotSS.giveExp  ->  S2C.SlotStatUpdate  ->
  plrObjClient/slot.applyPatch
  giveExp builds `{ exp = n }` and only widens to lvl/lives/allocPts/
  baseStats on the frames that actually level up. The FULL slot goes
  down exactly once, at load. Everything after that is a diff.

### 16. One remote per concern, demuxed by a small integer.
  Inputs/enums (17 verbs), Inventory/enums (9), ReplicateEnums S2C/C2S,
  RFHandler manifold, HumObj repli ids (Class/HumObjClient/replIds).
  Instead of dozens of RemoteEvent Instances, each concern gets one and
  the first argument is an integer verb. Two shapes worth copying:
      S2C containers  (containerID, enumId, ...)
      C2S containers  (enumId, ...)     no container id -- every C2S verb
                                        is about the player's own slot
  HumObj declares its two directions as SEPARATE spaces in `replIds`, so
  S2C 1 (stun) and C2S 1 (sprinting) are not a collision. The numbers are
  the wire: the C2S gaps at 13/14 are historical, not reservations.
  Both ends compare against the same frozen table, so a dead branch is a
  missing FIELD, not a number nobody noticed. Append only.

### 17. Compress at the boundary, and only send the summary.
  Utils/ZstdUtil  +  PlrData/Slots.ToClient  +  Class/SparseBitSet
  S2C.SlotData is `ZstdUtil.compress(slot:ToClient())` -- JSON, then zstd
  level 22. Slots:ToClient is a SUMMARY ONLY: name/lvl/xp/pts/elo/wins
  per slot, keyed BY ID, with no seed, cards, inventory or stats. Those
  ride S2C.SlotData for the ONE slot actually loaded.
  Containers serialize array-of-pairs `{ {i, payload}, ... }` rather than
  a gapped array, because JSON/zstd cannot round-trip holes -- the
  correct form and the compact form happen to be the same one.
  Card ids go through SparseBitSet -> EliasFano, ~2 + log2(U/k) bits per
  element with k in 16 bits and L in 6 as a packed header. That buffer
  sits INSIDE slot:ToClient, so it is a wire win as well as a save win
  (howIsaveRuntimeRAM #5, DATASTORE).
  msgPack is still in Packages but is NOT on this path: Container's
  header records it going in 3/13/2026 and coming back out 3/24/2026 in
  favour of zstd higher up. Do not re-add a second encoder.

### 18. The ping probe has no payload.
  Core.luau  +  LocalCore.luau  +  plrObj (CanPing/TriggerPing/PostPing)
  Server `FireClient(plr)` with no arguments; client `FireServer()` with
  no arguments. The packet's EXISTENCE is the message, and the server
  times its own round trip. Unreliable, gated by one float at 2s on top
  of a 10Hz GameLoop tick.
  `stablePing` is an EMA (lerp 0.3), so no history is kept, and the
  BROADCAST copy -- `Plr:SetAttribute("p", ...)`, which every client
  receives -- is throttled to once per 12s while the unicast S2C.Ping
  tracks every probe.

### 19. Unicast by default; broadcast only what everyone must see.
  HumObj:FireVFXClient no-ops when `plrObj == nil`, so an NPC never
  broadcasts an owner-only effect. Debug channels are OPT-IN: the hitbox
  visualiser is a RemoteChannel with an explicit subscriber list
  (ROWA/RemoteChannels/Hitboxes), so it sends to nobody until
  `/hitboxShow` subscribes someone, and it drops dead players lazily by
  swap-remove while iterating.
  Draw arbitration stays LOCAL: CooldownClaims decides whether the
  cooldown list or the inventory slot renders an id, entirely on the
  client, rather than the server sending a "who draws this" flag.

### 20. Demand-paged CODE. (the Quiver)
  ReplicatedFirst/LocalCore/VFX  +  Core/RFHandler/VFX
  12 modules ship to every client in ReplicatedStorage/VFXQuiver; the
  ~126 in ServerStorage/ROWA/VFXQuiver are pulled ONE PER ID PER SESSION
  over the RemoteFunction, cloned into the requesting Player and
  Debris-removed once the client has re-parented it.
  !! ONE FETCH PER ID, NOT ONE PER FIRE. Every OnClientEvent runs on its
  own thread, so two fires of a cold id inside one round trip both asked
  -- and RFHandler/VFX clones PER REQUEST while `require` caches per
  INSTANCE, so a staged effect ended up with two module states. VFX.luau
  parks concurrent fires in `pending[id]` and resumes them IN ARRIVAL
  ORDER off the single fetch.
  Honest framing (see howIsaveRuntimeRAM, THE GENERAL LAW): this DEFERS
  a transfer, it does not delete one. What it deletes is the transfer for
  every id a given client never sees.

### 21. A STATIC catalogue is built once, frozen, and shared by everyone.
  ROWA/Cards `catalogue()`     +  Core/RFHandler/cardCatalogue
  ROWA/Abilities `catalogue()` +  Core/RFHandler/abilityCatalogue
  The Encyclopedia's lists are identical for every player, so each is built on
  first ask, `table.freeze`d, and the SAME table is returned forever after --
  the server does no per-call work no matter how many people open it.
  `describe()` is run HERE, not client-side, because the `card` namer is
  pushed by the ServerStorage registry and a client would print "card #17".
  Emotes.catalogue is the same shape, and both obey the array rule: NEVER
  keyed by id. Card ids are gapped, and a gapped numeric table does not
  survive a remote intact -- see EMOTES 4 for the bug that shipped.
  Rows are DENSE for the same reason: a nil desc mid-row gaps the row, so it
  is "" instead.
  BOTH CATALOGUES SHARE ONE COLUMN ORDER, which is what lets the codex draw
  one page for two spaces, and what makes its third page free: coverage
  crosses the two tables the client already holds and asks the server nothing.
  !! The ability one names rows off the MODULESCRIPT, never `nameOf`, which
  reads class.Name and so REQUIRES the class -- naming every row through it
  would load every ability module on the first tap of a tab.

## THE ONE REAL DEFECT  (FIXED -- NEEDS A PLAYTEST)
One finding survived a steelman. The others had reasons written in their
own headers -- see CHECKED AND CLEARED, and read it before "fixing"
anything there.

### FullBlue drained mana by writing `.Value` in a per-frame loop.
  ROWA/Abilities/FullBlue:201   -- ability id 41, REGISTERED AND LIVE
      mana.Value = math.max(0, mana.Value - dt * MANA_PER_SEC)   -- WAS

  NOW: accumulate into `manaOwed`, settle on the existing HURT_EVERY
  tick with :setMana, and settle the remainder once after the loop.
  ~240 packets a channel -> ~15.
  !! THIS IS A BALANCE CHANGE, NOT JUST A FIX. The old line never
  touched the anchor, so :manaNow never saw it and the channel was
  effectively FREE after the flat :useMana(). It now really costs
  MANA_PER_SEC 13/s. Playtest before shipping; if it bites, the dial is
  MANA_PER_SEC, not the batching.

  THE BANDWIDTH IS THE SYMPTOM, NOT THE DISEASE. `v` changes every frame,
  so Changed fires, so S2C.mana goes out at frame rate -- ~240 unicast
  packets over LIFETIME 4s where the design intends one. Small packets to
  one player, so the traffic alone would be a shrug. It is listed at all
  because the same line is a CORRECTNESS bug:
    * `setMana` rawsets the anchor triple (a, t, m) and THEN sets .Value.
      `manaNow()` reads a/t/m. This line writes only `v`.
    * So the SERVER's mana never moves. AbilityBase's own gate,
      `humObj:manaNow() < self.manaUse`, cannot see the drain.
    * The client receives S2C.mana and calls setMana, which DOES re-anchor.
      So the client empties and the server does not, and the next real
      spend re-anchors from the server's untouched value and hands the
      bar straight back.

  IT WAS A MISSED MIGRATION, NOT A DECISION. The comment above it said
  "`mana` is a plain NumberValue, nothing clamps for you" and cited
  PORT_FullBlue step 2 -- which said the same thing, and was TRUE WHEN
  WRITTEN. The anchor landed after. Two more tells: it cited "same note as
  StoneBall" and shipped StoneBall has no mana code at all; and
  AbilityBase, the base class this file inherits, gets it right twice with
  an explicit ":manaNow, NOT .Value" comment.
  BOTH PORT NOTES ARE CORRECTED (PORT_FullBlue step 2, PORT_StoneBall
  step 3) -- they prescribed the stale idiom and would have reintroduced
  it on the next port.

  TWO TRAPS IF YOU TOUCH THIS AGAIN:
    * `setMana` per frame is CORRECT and still ~240 packets. Correctness
      and the packet count are separate problems; batching fixes the
      second.
    * Do NOT re-read :manaNow to test for empty. The anchor is stamped
      from its own tick() call, so reading straight back after
      setMana(0) returns ~3e-6, not 0, and the channel never ends. Test
      the value you computed.

## CHECKED AND CLEARED
Things that LOOK like violations, walked, and are not. Recorded so the
next reader does not re-open them.

  * FullBlue writing `field.Position` every frame on an anchored server
    part. Its header DECLARES the exception and gives the reason: "The
    server owns the part against the usual rule: its position IS the
    hitbox origin." The well must also be a real tagged Instance for #8
    to work, and sending it instead would arrive nil under streaming.
    Bounded to ONE part. The remote in the same loop IS gated
    (`frame % PULL_EVERY`), which shows the author was counting.
  * GuardBreak's 16 blood broadcasts (HumObj:868). The drip has to be
    PACED across the 1.6s of TrueStun, and the blood verb carries
    (count, root, spread, speed, size) with NO rate or duration. Client
    Blood.luau paces at >=0.02s per droplet, so one packet of 16 would
    finish in ~0.32s -- a burst, not a bleed. The loop is the only way to
    get the effect out of the CURRENT protocol, and it rides an
    UnreliableRemoteEvent, so the packets are cheap and droppable.
    OPPORTUNITY, not a bug: add a duration to the blood verb and this
    collapses to one packet (#12 + #13). Costs a wire change.
  * bloodChain rewriting two AlignPosition goals per frame. The midpoint
    of two MOVING roots is not fixed, so it has to be recomputed, and the
    constraint needs server authority because either end may be an NPC.
    Faithful to rowa1's two BodyPositions, as its header says.
    UNVERIFIED alternative: crossed TwoAttachment AlignPositions converge
    the pair with zero per-frame writes -- but the force profile and
    YANK_STOP behaviour differ, so that is a FEEL change, not a refactor.
  * EarthShot moving 15 anchored parts per frame. NOT REGISTERED --
    Abilities.luau names it scratch in its own comment, so nothing can
    cast it. Left as a landmine note: it is the purest form of the
    anti-pattern and would need rewriting before promotion. Still uses
    BodyVelocity too.
  * All bindFuncs inputs are key EDGES, not held streams. The sprint/slide
    C2S round trip has no echo back (the server sets no `sprint`
    walkSpeed mod). Posture DAMAGE goes through `.Value` while only regen
    uses rawset, which is exactly #2 + #3. Every other `while` loop in
    Abilities fires its VFX on the `break` path, not per iteration.

## WHERE IT SPENDS BY DESIGN
Known, accepted, not bugs -- do not "fix" these without a measurement.

  * INLINE VFX IS REAL TRAFFIC. VFX pattern A clones Instances on the
    server; every Clone replicates. Several attack scripts carry a
    "TODO move vfx to client?" for exactly this. Claymore's heavy at
    least pools 25 copies instead of cloning per frame.
  * The `hurtbox` fast lane is a server property write per received
    packet. It is one part instead of a rig, not free.
  * Nearly every VFX broadcast passes a BasePart, which #8 warns about.
    Benign for the same reason gravWells gives: a client that has not
    streamed the part in is too far away to need the effect. It would
    NOT be benign for anything gameplay-carrying.
  * `Container.onEquipped` / `onCooldown` linear-scan the slots to
    recover an index. CPU, not bytes -- but it is flagged TODO in source.
  * RFQuiver/clientInfo ships a 249-entry CountryCodes table to a client
    to read TWO fields. It is the worst payload in the game and it is
    also a bug; the write-up lives in howIsaveRuntimeRAM (THE
    ANTI-PATTERN). Fix direction: resolve it server-side.

## CHECKLIST FOR ANY NEW CHANNEL
  * How many times per second per player? If the answer is "per frame",
    you are sending a consequence -- find the cause (#1, #7, #9).
  * Can the receiver DERIVE it from something it already has? A tagged
    part (#8), an already-replicated Model (#6), the spawn numbers (#7).
  * Is it an EDGE or a POLL? Edges dedupe for free through valueBase (#2)
    and cost nothing when nothing happens.
  * Does a value-write path bypass Changed when it should (#3), or fire
    it when it should not?
  * Duration or timestamp? Duration, and let the receiver stamp (#5).
  * Would a drop be superseded by the next message? Then UNRELIABLE.
    Would a drop desync state? Then reliable, and make it an edge.
  * Sending an Instance? StreamingEnabled will hand a far client a
    permanent nil (#8). Send a number, or use a tag.
  * Broadcast or unicast? FireAllClients is a per-player cost times the
    server population.
  * Sustained? Give it a self-expiring lease and a `<= 0` cancel (#13).
  * PUSH or PULL? If the source increments in a hot loop, make the client
    ask (#14).
