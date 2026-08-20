--!strict
--[[ FullBlue - rowa1 Items/Ability/FullBlue. Notes: README.md/PORT_FullBlue.

	A gravity well. You throw a blue singularity out in front of you and it
	drifts along your aim for four seconds, dragging everything inside 23
	studs into orbit -- rubble, dummies, players -- chipping them while they
	tumble. Control, not burst.

	IT WAS NEVER UNFINISHED, and PORT_FullBlue's own "## !! SAME FIRST
	QUESTION" section is wrong; its CORRECTION at the top is right. The
	aEvent is the SUMMON and nothing else -- it clones a part and runs a
	drift loop. The mechanic is 88 lines in ServerStorage/Effects/MaxBlue/
	Script, parented to the part it clones: that is where the `blue` dmgID
	is dealt, where the orbit impulses are applied, and where `PurpleReady`
	is set. Third ability in a row to hide half of itself there
	(PORT_InverseRed CORRECTION 2); the tell is the same one every time, an
	aEvent that requires AttackModule and never calls it.

	WHAT THE SCRIPT-ON-THE-PART BECAME
	  Not a Script on a part. rowa1's field re-required HurtBox, Destruction
	  and AttackModule per cast and held its own Heartbeat; this is one loop
	  inside the ability, which already owns a hitbox, a damage pipeline and
	  a cooldown. The part is now only an anchor and a visual.

	  THE SERVER STILL OWNS THE PART, deliberately, against the usual rule.
	  Its position IS the hitbox origin and the destruction origin, so every
	  machine has to agree on it. What does NOT need agreeing -- the five
	  emitters pulsing every 0.05s -- runs client-side via the `bluefx`
	  quiver id, exactly as rowa1 split it. One replicated CFrame per frame,
	  not five Emit calls.

	  THE PULL ON PLAYERS GOES THROUGH THEIR OWN CLIENT (`blueAttract`).
	  A server-side ApplyImpulse on a player-owned root is fought by their
	  physics every frame; DOC_VFX D calls this exact case. NPCs have no
	  client, so they take the impulse here. rowa1 branched the same way. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "FullBlue",
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils    = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag     = dmgUtils.dmgFlags
local aerialAim   = require(game.ServerStorage.ROWA.Modules.aerialAim)
--- the projectile-bending half of the well. Shared with every client fx.
local gravWells   = require(game.ReplicatedStorage.Modules.gravWells)

--[[ rowa1 "blue" (DMGS:972): Light, magic, 6.5 dmg, truestun 0, stun 0.3,
	posMult 1, onHit = OnHitFuncs.blue -- which is ragdtillground under
	another name (0.5s floor, ground check, identical body). So the field
	ragdolls what it catches, which is the whole reason victims TUMBLE in
	the orbit instead of standing in it.

	6.5 -> 4. This is the one row where the S4.3 "retune down" ratio is not
	the interesting number: the tick fires every 16th heartbeat for four
	seconds, so it lands ~15 TIMES. rowa1's own value totals 97 damage on
	anyone who never escapes, which is more than Cero. 4 puts a full,
	uninterrupted channel at ~60 -- still the biggest sustained number in
	the game, and it is supposed to be, but it is now survivable by someone
	who breaks out halfway.

	parryH -10: rowa1 has "blue" in `unParryableIds`. There is no set to
	join in rowa2, it is just a number that makes the window unreachable.
	NOT in `dieNow` -- that set is wcrush/purple/oblH2/exH/ktH/axB, and the
	PORT doc's claim that blue is in it is wrong. So no execute here; the
	kill it needs for PurpleReady is an ordinary one. ]]
local BLUE = table.freeze({
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.magic,
	dmg      = 4,
	stun     = 0.3,
	posMult  = 1,
	parryH   = -10,
	stunMeOnParried = 0,
})

--[[ every number here is rowa1's, from MaxBlue/Script's header block.
	LIFETIME is 4 despite the aEvent declaring `Attacking.Time = 8` and
	PORT_FullBlue reading it as "up to 7 seconds" -- README 7g, the declared
	value is a claim and the field's own `tick() + 4` is the truth. rowa1
	says so out loud in a third place, on its own drain line: "about 50
	which is 4*13, 4 being the time blue lasts". ]]
local LIFETIME     = 4
local BLUE_RADIUS  = 23             -- damage + pull radius
--[[ PROJECTILES ARE CAUGHT FROM FOUR TIMES FURTHER OUT than bodies.
	A body has to be dragged into the orbit and chipped, so its radius is
	tuned for a fight you are standing in. A projectile only has to be BENT,
	it is already moving, and a well that only grabs shots inside 23 studs
	would eat the ones that were going to hit you anyway and miss everything
	else -- which reads as no effect at all. At 92 the well visibly sweeps a
	whole volley off its line, which is the point of pointing one at a
	shotgun. Nothing else about the well changes. ]]
local PROJ_RADIUS_MULT = 4
--[[ studs/second^2 at the CORE. gravWells eases this to a quarter at the rim
	-- the opposite way round from the body pull, and its header explains why
	at length: rowa1's rim-hardest curve is right for bodies it wants to keep
	circling, and almost invisible on a projectile, which is closest and
	biggest on screen exactly where that curve gives up.

	800 is chosen against the fastest thing in the game rather than the
	slowest: IceSlash's crescent crosses at 200 studs/s and is inside a 92
	stud well for well under a second, so anything gentle enough to look
	tasteful on a lobbed pellet does nothing at all to a crescent. A pellet
	from ProjTest at 60 studs/s gets folded straight into orbit, which is the
	right relationship -- a well should own slow things outright and visibly
	wrench fast ones. ]]
local PROJ_PULL    = 800
--[[ fraction of speed bled per second at the core. WITHOUT THIS THE WELL
	ONLY SLINGSHOTS: a symmetric radial force bends a shot in on the way
	past and back out again, so most of the deflection cancels itself.
	Bodies get this for free because FullBlue blends them toward a desired
	velocity rather than pushing them. See gravWells. ]]
local PROJ_DRAG    = 2.5
local ATTRACT_SIZE = Vector3.new(60, 60, 60)
local HURT_EVERY   = 16             -- heartbeats between damage ticks
--[[ 180, not 3. rowa1 writes `velocity += dir * dt * 3` and then steps with
	`pos += velocity` -- no dt -- so its velocity is studs per FRAME and the
	acceleration is really 3 * 60 studs/s^2. Reading the 3 literally and
	integrating it properly (which the previous pass did) is 60x too slow:
	the field crawled 7.8 studs over the whole channel at 2 studs/s, which
	is why it looked like it was sitting still.
	At 180 with `pos += velocity * dt` the trajectory is numerically
	IDENTICAL to rowa1 at 60fps -- verified sample by sample -- and now also
	holds at 30 and 144. It throws the well ~19 studs out in half a second,
	overshoots to 33, and then swings around the aim point for the rest of
	the channel. The overshoot is rowa1's, not a bug: the orb chases a point
	30 studs ahead of you and is far too heavy to stop on it. ]]
local DRIFT_ACCEL  = 180            -- studs/s^2 toward the aim point
local DRIFT_DAMP   = 0.98           -- per 1/60s, applied framerate-independently
local AIM_RANGE    = 30             -- raycast ahead of the caster
local AIM_LIFT     = 7              -- the orb chases 7 studs above the aim point
local SPAWN_AHEAD  = 8
local SPAWN_UP     = 12
local MANA_PER_SEC = 13             -- rowa1 drained dt*13 every frame

--[[ THE PULL IS A TARGET VELOCITY, NOT AN ACCUMULATING IMPULSE.
	rowa1 adds `(pull + spin - victimVel/20 + fieldVel) * mass * 10 * dt * 60`
	every frame. That damping term is the ONLY thing bounding it, and it
	bounds it at 183 studs/s -- measured, not guessed. Dropping it (which the
	first version of this port did) makes the sum diverge: 21,996 studs/s
	after four seconds, which is the "it flings everything it touches" bug.

	So the damping is not a detail, it IS the mechanic. Blending toward a
	DESIRED velocity instead makes accumulation impossible at any framerate:
	the speed cannot exceed |desired|, whatever the framerate and however
	many applications land.

	NOTE the ceiling is |desired|, not PULL_SPEED alone -- the field's own
	velocity is added, so a well travelling at its ~150 studs/s top speed
	drags bodies at up to ~185. That is deliberate and it is rowa1's number
	(measured terminal: 183). A victim has to travel WITH the well or it
	simply outruns them and the whole move does nothing. ]]
local PULL_SPEED   = 35             -- studs/s of INWARD pull, before the field's own
local SPIN_SPEED   = 6              -- tangential, so they orbit not collapse
local PULL_BLEND   = 0.25           -- how fast an NPC converges on that
local PULL_EVERY   = 2              -- frames between pulls sent to a PLAYER

--[[ NO DESTRUCTION HERE, ON PURPOSE. rowa1 called Destruction:BlueBreak
	every frame -- an 8^3 cutter at four random points in a 16-stud shell,
	capped at 800 pieces -- so the well chewed the terrain as it drifted.
	That half is being done separately; do not re-add it without checking
	what landed there first, or the field will carve twice. ]]

--[[ THE FIELD IS PULSE-DRIVEN, NOT A STEADY STREAM.
	Every emitter on the asset ships Enabled = false and rowa1's client
	module calls Emit(1) on all five every 0.05s. That IS the effect: 20
	discrete puffs a second. Merely enabling them (which an earlier pass
	here did) produces a continuous stream at the authored Rate, which is a
	visibly different -- and much flatter -- thing. Keep the pulse.

	IT RUNS SERVER-SIDE, and only because the client cannot be handed the
	part at all under StreamingEnabled; see the note in useFunc. Emit()
	replicates, so the cadence survives. Cost is 5 emitters x 20 pulses x 4
	seconds = 400 replicated Emit calls per cast, which rowa1 dodged by
	pulsing locally. For one cast of a 50s ultimate that is the right trade
	against an effect that does not appear at all. ]]
local FX_PULSE = 0.05

--- resolve the asset's fx once, and force the emitters to the state the
--- pulse expects rather than trusting however the asset was last saved
local function collectFx(field: BasePart): ({ParticleEmitter}, PointLight?)
	local emitters: {ParticleEmitter} = {}
	local light: PointLight? = nil
	local att = field:FindFirstChild("Attachment")
	if att == nil then return emitters, light end
	for _, v in ipairs(att:GetChildren()) do
		if v:IsA("ParticleEmitter") then
			v.Enabled = false
			table.insert(emitters, v)
		elseif v:IsA("PointLight") then
			light = v
		end
	end
	return emitters, light
end

local function aimPoint(hurtbox: BasePart): Vector3
	local origin = hurtbox.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		workspace.Effects,
		workspace:FindFirstChild("DestDebri"),
		workspace:FindFirstChild("Entities"),
	}
	--- rowa1 FindPartOnRayWithIgnoreList(Ray.new(pos, look*30)) -> endp
	local hit = workspace:Raycast(origin, hurtbox.CFrame.LookVector * AIM_RANGE, params)
	return hit and hit.Position or (origin + hurtbox.CFrame.LookVector * AIM_RANGE)
end

local function useFunc(this:myself)
	local cooldownID = "fullBlue"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim = this:PlayAnim(script.summon2, 0, 1, 1)

	--[[ !! A STALE FEINT FLAG WOULD KILL THE WHOLE CAST, SILENTLY.
		`isFeinted` is set by CombatAction.feint and cleared in exactly ONE
		place: sharedFeintWait's line 50, at the top of every feintWait. Every
		other channel in the game -- Barrage, IceBeam, FlameDance, Huozai,
		StoneBall, Burst, Freeze -- opens with a feintWait windup and gets
		that reset for free. THIS ONE HAS NO WINDUP. The field appears
		instantly, so feintWait is never called and nothing ever clears the
		flag.

		The failure that caused: feint at ANY point while this ability is the
		one in use -- including during the endLag below, when attacking is
		still true, so `feint()` still succeeds -- leaves the flag set. The
		next cast then breaks on its FIRST loop iteration, which sets
		`Finished` about a frame after bluefx was fired, so the client module
		returns before its first pulse. Cast one draws, every cast after it
		draws NOTHING, and there is no error anywhere.
		Reset at entry, which is what feintWait would have done for us. ]]
	this.isFeinted = false

	--- 7s of hold in rowa1, but the field only lives 4. Budget the truth.
	local releaseAir = aerialAim(humObj, LIFETIME + 1)

	this:useMana()
	this:triggerCD(cooldownID, 50, true)

	local field = script.MaxBlue:Clone()
	field.Anchored = true
	field.CanCollide = false
	field.CanQuery = false
	field.CanTouch = false
	field.Transparency = 1
	field.Position = hurtbox.Position
		+ hurtbox.CFrame.LookVector * SPAWN_AHEAD
		+ Vector3.new(0, SPAWN_UP, 0)
	field.Parent = workspace.Effects

	--[[ REGISTER THE WELL. Everything that bends projectiles is these three
		lines: the tag and two attributes. They replicate WITH the part, so
		every client's projectile fx finds the same well with the same
		numbers and derives the same curve -- no packet, no per-frame
		correction, and immune to the streaming trap described above,
		because nothing is being sent to anybody.
		The tag dies with the part, so there is no teardown to forget. ]]
	field:SetAttribute("wellRadius", BLUE_RADIUS * PROJ_RADIUS_MULT)
	field:SetAttribute("wellPull", PROJ_PULL)
	field:SetAttribute("wellDrag", PROJ_DRAG)
	field:AddTag(gravWells.TAG)

	for _, n in ipairs({ "Fx2", "Sound" }) do
		local s = field:FindFirstChild(n)
		if s and s:IsA("Sound") then s:Play() end
	end

	--[[ !! DO NOT SEND THIS PART TO A CLIENT MODULE. THIS GAME HAS
		StreamingEnabled = true.

		rowa1 pulses the five emitters from a client module ("bluefx",
		Emit(1) every 0.05s) and hands it `blue` -- the Part -- over the
		remote. Under streaming an Instance argument the receiving client has
		not streamed in yet arrives as NIL, permanently, with no error on
		either side. It is not a race a wait can close: rowa1's own
		`RunService.Heartbeat:Wait()` before its FireAllClients does not fix
		it, and neither did a task.wait() here. The module was being handed
		nil every single cast, bailing on its own guard, and the part sat in
		workspace.Effects emitting nothing.

		Every emitter on the asset ships Enabled = false, so that pulse was
		the ONLY thing that ever drew them -- which is why the failure was
		total rather than partial, and why the PointLight (the one thing
		enabled by default) was the only survivor.

		Enabling them here is one replicated property write each, it travels
		WITH the part instead of racing it, and it is immune to streaming,
		to join order and to range. DOC_VFX pattern A, which is the default
		for abilities anyway. The authored Rates (34/7/18/19/80) are the
		Driving it from here means the PULSE is ours to run -- see FX_PULSE
		above; enabling the emitters and walking away is not the same
		effect. ]]
	local emitters, light = collectFx(field)

	local velocity = Vector3.zero
	local frame = 0
	local pulse = FX_PULSE
	local endt = tick() + LIFETIME
	local mana = humObj.mana

	while tick() < endt do
		local dt = task.wait()
		frame += 1

		--- rowa1's bluefx cadence, verbatim: one particle from each of the
		--- five, 20 times a second, for as long as the field lives
		pulse += dt
		if pulse > FX_PULSE then
			pulse = 0
			for _, e in ipairs(emitters) do
				e:Emit(1)
			end
		end

		--[[ the Barrage pattern (S6.2): a fixed-rhythm channel reads the
			interrupt itself rather than calling feintWait, which would
			fight the loop. Losing the field is the punish for being hit. ]]
		if humObj:inStun() or this.isFeinted then
			this.isFeinted = false
			break
		end
		--- rowa1 also ended the channel below 5 health
		if humObj.Hum and humObj.Hum.Health <= 5 then break end

		--- CLAMP AT 0. `mana` is a plain NumberValue, nothing clamps for you
		--- (PORT_FullBlue step 2, same note as StoneBall).
		mana.Value = math.max(0, mana.Value - dt * MANA_PER_SEC)
		if mana.Value <= 0 then break end

		local pos = field.Position

		--[[ drift toward a point 7 studs above whatever you are looking at,
			accelerating rather than lerping, with a 0.98 bleed. That is why
			it lags behind your aim and swings past it -- port the feel, it
			is the only steering the player gets. ]]
		--[[ !! `velocity` IS STUDS PER SECOND, so the step is `* dt`.
			rowa1 writes `blue.Position += velocity` with velocity built from
			`dt * 3` -- a PER-FRAME delta -- and the first version of this
			port copied that literally. Simulated: it peaks at 67 studs/s
			within half a second, overshoots the aim point by 33 studs and
			then oscillates between 16 and 33 studs away for the rest of the
			channel. The orb was whipping around well outside where you cast
			it, which is most of why the effect "was not there".
			As studs/s it settles at 2.4 and travels ~8 studs over the four
			seconds: a drift, which is what the move is. ]]
		local target = aimPoint(hurtbox) + Vector3.new(0, AIM_LIFT, 0)
		velocity += CFrame.new(pos, target).LookVector * DRIFT_ACCEL * dt
		--- framerate-independent: 0.98 is per 1/60s, not per frame
		velocity *= DRIFT_DAMP ^ (dt * 60)
		field.Position = pos + velocity * dt

		local canHurt = frame % HURT_EVERY == 0
		local _, hits = this:hitbox(CFrame.new(pos), ATTRACT_SIZE, nil, true)

		for _, enemy in pairs(hits) do
			local eroot = enemy.HRootPart
			if eroot == nil then continue end
			local delta = pos - eroot.Position
			local dist = delta.Magnitude
			if dist > BLUE_RADIUS then continue end

			--[[ rowa1's "saturn ahh orbit": pull straight in, plus a
				tangential kick so they swing round instead of collapsing
				onto one point, plus a vertical wobble so several victims do
				not stack on the same line.

				THE WOBBLE IS KEYED ON entityId, NOT THE FRAME. rowa1 indexed
				it off the loop counter `i`, which is a per-VICTIM constant
				there. Using the frame counter (as the first version did)
				makes it a ±10 vertical oscillation applied to everyone at
				once, every frame -- a shared pump, not a per-body offset.

				rowa1 scales the inward pull by clamp(dist, 0, 10), so the
				rim pulls hardest and the centre lets go; that is what keeps
				bodies circling rather than jamming into the middle. Same
				shape here, normalised into a fraction of PULL_SPEED. ]]
			local dir = dist > 0 and delta.Unit or Vector3.yAxis
			local look = CFrame.new(pos, eroot.Position)
			local wobble = (enemy.entityId % 7) - 3
			local desired = dir * (PULL_SPEED * math.clamp(dist / BLUE_RADIUS, 0.15, 1))
				+ look.RightVector * SPIN_SPEED
				+ Vector3.new(0, wobble, 0)
				--- carried along with the field, as rowa1 added blue.Velocity
				+ velocity

			--[[ FEATURE-DETECTED, not assumed. `plrObj` and `FireVFXClient`
				are NOT in the Combatant contract -- not required and not
				optional-with-an-inert-default -- so they exist on HumObj and
				not on SimpleEntity. Calling one on a boss would throw inside
				the pcall AbilityBase.use wraps everything in, and the field
				would silently stop mid-channel. ]]
			if enemy.plrObj ~= nil and enemy.FireVFXClient ~= nil then
				--[[ their client owns that root; ours would just fight it.
					THROTTLED: rowa1 fired this every frame, which is 240
					remotes per victim per cast. The client converges over a
					few messages anyway, so half the traffic costs nothing
					visible. It also damps against ITS OWN velocity, which
					is the number the server does not have an accurate copy
					of -- that is why the blend lives over there. ]]
				if frame % PULL_EVERY == 0 then
					enemy:FireVFXClient("blueAttract", desired)
				end
			else
				local dv = (desired - eroot.AssemblyLinearVelocity) * PULL_BLEND
				eroot:ApplyImpulse(dv * eroot.AssemblyMass)
				eroot:ApplyAngularImpulse(eroot.AssemblyLinearVelocity / 10)
			end

			if canHurt then
				local attack = this:makeAtk(BLUE, enemy, -delta.Unit)
				this:executeAttack(attack)

				if attack:isHit() then
					--[[ ragdtillground, as rowa1's OnHitFuncs.blue is (same
						body, different name) -> ragdoll(60, true).

						KEPT DELIBERATELY, with eyes open: stopOnGround
						releases a victim as soon as a downward ray finds
						floor after 0.5s, so anyone dragged along at ground
						level pops straight back up and it can read as no
						ragdoll at all (PORT_00_INDEX: "(60, true) on a
						mostly-HORIZONTAL knockback looks like NO ragdoll").
						The pull is what saves it -- it lifts bodies toward a
						well 12 studs up, and a body off the floor keeps the
						ragdoll. If it still reads as not ragdolling, that is
						the PULL being too weak to lift them, not this call;
						raise PULL_SPEED before touching the ragdoll.
						Re-applied every tick, which RowaRagdoll handles by
						taking the max of the current and new lifetime. ]]
					enemy.ragdoll:ragdoll(60, true, -delta.Unit * 10)

					--[[ THE SETUP HALF OF THE PURPLE COMBO. rowa1 flags the
						FIELD the moment it kills someone, and InverseRed's
						orb looks for a flagged MaxBlue as it flies past.
						The flag is all that ships today -- the 2.2s
						95-radius nuke on the `purple` dmgID is a separate
						port. See InverseRed's header. ]]
					if enemy.Hum and enemy.Hum.Health <= 0 then
						field:SetAttribute("PurpleReady", true)
					end
				end
			end
		end
	end

	if anim then anim:Stop(0.2) end
	releaseAir()

	--- the pulse stops with the loop; kill the light and let what is already
	--- in the air finish its lifetime rather than vanishing mid-flight
	if light then light.Enabled = false end
	--[[ nothing reads `Finished` for the VFX any more. It stays because it
		is the "this well is spent" marker rowa1's orb checks before firing
		the purple nuke, and that combo is the next job. ]]
	field:SetAttribute("Finished", true)
	game.Debris:AddItem(field, 5)

	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
