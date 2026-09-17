# VFX - the two VFX patterns
(index: parent ServerStorage/README.md)

Two separate VFX systems live side by side. Pick the right one or you'll
double-play an effect or have it not show up at all.

this is also used for things that would clobber up the network stream... instead of sending alot we just send one...

## A) INLINE VFX (default for weapon attacks & most abilities)
  The attack script `:Clone()`s instances that are CHILDREN OF ITSELF
  (Attachments/Parts holding ParticleEmitters, Sounds, Beams), parents them
  onto the character / weapon model / hitbox, `:Emit()`/`:Play()`s them, and
  cleans up with `game.Debris:AddItem(...)` or `task.delay`.

  Runs on the server, replicates via ordinary Instance replication.

  Examples:
    Abilities/Fulminate           -> vfx (Attachment), ELECTRIC, lighting4
    Weps/.../Claymore/attack/heavy -> vfx, vfx2, FloorFX
    Weps/WepBase/downSlam          -> script.strong (indicator/shock/shine/Swing1)
    Weps/WepBase/indicateAtk       -> blade-tip "indicator" emitter that grows
                                      over 0.2s and self-cancels on feint

  For high-rate effects use a POOL instead of cloning per-frame. Claymore's
  heavy pre-clones 25 copies of `vfx2` into a ring buffer and cycles through
  them (`getVFX()`), then Debris-clears the pool at the end.

  Cost: every Clone is real replication traffic. Several files carry a
  "TODO move vfx to client?" for that reason.

## B) THE VFX QUIVER / MANIFOLD (networked, lazily loaded) design reasoning? vfx is sparse and not every vfx is ever loaded...
  For cosmetic effects that must run ON CLIENTS (camera shake, screen flash,
  Lighting effects, client-authoritative movers), the server fires:

      game.ReplicatedStorage.RemoteEvents.VFX:FireClient(plr, id, ...)
      game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients(id, ...)

  ### Client side - ReplicatedFirst/LocalCore/VFX.luau
  Keeps `Manifold = {[id] = function}`. On VFX.OnClientEvent(id, ...):
    1. `Manifold[id]` exists          -> call it
    2. else `ReplicatedStorage.VFXQuiver:FindFirstChild(id)` -> require, cache, call
    3. else `RemoteFunction:InvokeServer(1, id)` -> server clones the module
       out of the big SERVER quiver, client parents the copy into
       ReplicatedStorage.VFXQuiver, requires it, caches it, calls it
    4. else warn "not found in vfx manifold or quiver"

  !! ONE FETCH PER ID, NOT ONE PER FIRE. Step 3 yields for a round trip,
  and every OnClientEvent fire runs on its OWN thread -- so a staged
  effect whose stages are closer together than the RTT used to fetch
  TWICE. RFHandler/VFX clones PER REQUEST and `require` caches per
  INSTANCE, so that is two module states, and the stages then ran against
  different ones: stage 1 registered in copy A, stage 3 looked in copy B,
  found nothing and returned. Tendrils left its strands welded to a
  victim who was never hit that way (bldtendrils 1 -> 3 is 0.22s on a
  whiff, i.e. one round trip). VFX.luau now parks concurrent fires in
  `pending[id]` and resumes them IN ARRIVAL ORDER off the single fetch.
  Every staged cold id was exposed, not just that one -- bloodcast,
  icebsh, boltp, ststep, bchain, stoneBallRoll. The tell is a first cast
  that half-draws and never cleans up, on ONE client, and only ever the
  first one that client sees.

  ### Server side - ServerScriptService/Core/RFHandler/VFX.luau
  Registered as handler id `1` in RFHandler's manifold. It looks up
  ServerStorage.ROWA.VFXQuiver[id], clones it, parents the clone INTO THE
  REQUESTING PLAYER, and Debris-removes it after ~5s (the client has already
  re-parented/required it by then).

  So the server never replicates a huge folder of VFX modules up front. Each
  id is pulled once, on first use, then cached for that client's session.

  ### Each quiver module is just:
      return function(...) -- particles / sounds / tweens / camera
      end

  ### ReplicatedStorage/VFXQuiver - ALWAYS available on the client
    camShake, dash, dbri, dragIK, feintfx, grabWeld, kb, kbd, parry,
    postureBreak, projSteer, ragdollc, systemMsg
  The hot-path / bootstrap-critical ones. `kb`/`kbd` are how knockback movers
  get created and destroyed on the owning client. `projSteer` is hot because
  its first use is the frame something got PARRIED.
  `ragdollc` takes the char it acts on and is NOT always your own: whoever
  owns a body runs its state machine, so dragBody fires it at the grabber
  for their victim. A rig that is not yours gets its state machine PARKED
  (all states off but Physics and Dead, since Died needs Dead) and is handed
  back to stock on the off switch, never got up -- the server cannot correct
  a body a client owns, so refusing the transition beats re-pinning it.

  ### ServerStorage/ROWA/VFXQuiver - fetched on demand
    The FOLDER is the list (~100 ids); enumerating it here only goes stale.
    hideTool/hideArms hide, showArms is the ONLY restore and it is
    per-CHARACTER, so every exit path of a hiding ability owes one.

  ### ntf - the corner notification
    `FireVFXClient("ntf", message, title?)`. Straight port of rowa1
    FxHandler/Manifold/ntf; BOTH instances are rowa1's own, cloned, not
    re-authored -- the card is `ntf.notif` (a CHILD of the quiver module, so
    it rides the lazy fetch) and the stack is
    StarterGui/notifications/Notifications, rowa1's SettingsGui frame in its
    own ScreenGui so it does not depend on the settings UI. Bottom-aligned,
    right edge, Fantasy font. Restyle in Studio; the module sets no colours.
    Fixed on the way in: rowa1 leaked a Frame per notification (it slid
    `inner` out and left the card in the stack forever) and leaked a global.

  ### Live callers
    Claymore heavy      -> FireAllClients("hshock", humObj.HRootPart)
    Fulminate           -> FireAllClients("speedBeams", vfx)
    Clap                -> FireClient(plr, "clap", root)  for BOTH participants
    HumObj onAttacked   -> FireAllClients("block", root, dmg, weight, atkDir)
    HumObj HandleAttack -> FireAllClients("parry", defRoot, atkRoot, dmg, atkDir)
    HumObj:ChangeState  -> FireClient(plr, "cstate", state)
    both feintwait.luau -> FireAllClients("feintfx", character)
    Knockback.luau      -> FireClient(plr, "kbd", id)

  ### HumObj:FireVFXClient(...)
    Fires VFX to the OWNING player only. NO-OPS silently when
    `self.plrObj == nil`, i.e. on NPCs. Use FireAllClients directly if an
    NPC needs to produce the effect.

  ### A SUSTAINED EFFECT IS CANCELLED WITH duration <= 0
    A channel ENDS EARLY -- on stun, on feint, on the first connect -- and a
    duration fixed at cast time keeps drawing an ability that already
    stopped, which reads as the feint not having worked. So the sustained
    ids take (root, duration) and treat `duration <= 0` as "end the one
    running on this root NOW": icelasers, icelst, fdance, bground, ststep,
    huozai.
    Same shape in all of them -- an `active[root] = token` registry, the
    token re-checked AFTER every yield (the cancel lands during the Wait,
    and the while-condition is not read again until the bottom of the body).
    A CANCELLED one must not merely stop emitting: long-lifetime particles
    hang in the air. Fade with ReplicatedStorage/Modules/fxFade, which
    carries the traps and both callers.
    Server side is one local -- `local function stopX() fireVFX(id, root, 0) end`
    called on every early-exit branch. IceBeam and FlameDance are the models.

  ### A PROJECTILE'S DRAWN COPY IS CORRECTED, NOT RE-SENT
    Class/Projectile holds no Instance, so every client integrates its own
    copy from the spawn numbers. The two things a client cannot derive --
    a PARRY DEFLECT and the DEATH -- come down the `projSteer` id into
    ReplicatedStorage/Modules/projFx, read via `claim(id)`:
      sync.steer   one correction (pos, dir, speed, target). Consume it.
      sync.dead    sticky. The real one is gone, stop drawing.
    Ignore `sync.dead` and the effect outlives its own explosion, which is
    exactly what RPG's rocket did. projFx also owns the shared BOUNCE rule
    both ends apply to a shot deflected into the floor.

## C) OTHER CLIENT CHANNELS (not the quiver)
    ReplicatedStorage/FastRemotes/Hitbox -> LocalCore/VisualHB (debug hitbox draw),
      driven server-side by ROWA/RemoteChannels/Hitboxes (subscribe-only, so
      only players you explicitly Subscribe see them)
    ReplicatedStorage/FastRemotes/blood  -> LocalCore/Blood
    ReplicatedStorage/FastRemotes/Ping   -> latency probe loop
    ReplicatedStorage/RFQuiver           -> the client-side mirror of the
      RemoteFunction quiver (server can InvokeClient by id)

## D) WHICH ONE DO I USE?
    Particle/sound anchored to a part, everyone should see it   -> INLINE (A)
    Camera shake, Lighting, ColorCorrection, screen effects     -> QUIVER (B)
    Anything that must run in the victim's own network ownership
      (velocity zeroing, body movers, ragdoll)                  -> QUIVER (B)
    High-frequency emitters in a loop                           -> INLINE + a pool
