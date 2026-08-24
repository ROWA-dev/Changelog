--!strict
--- FullBlue - a gravity well. Drifts along your aim for 4s dragging everything
--- inside 23 studs into orbit and chipping it. Control, not burst.
--- rowa1 port: README.md/PORT_FullBlue (whose "SAME FIRST QUESTION" section is
--- wrong; the mechanic lived in a Script on the part, not the aEvent).
--- The server owns the part against the usual rule: its position IS the hitbox
--- origin. Players are pulled via their OWN client (blueAttract) because a
--- server impulse on a player-owned root loses to their physics; NPCs here.
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

--- rowa1 "blue" 6.5 -> 4: this lands ~15 times a channel, so rowa1's value
--- totalled 97 on anyone who never escaped. 4 puts a full channel at ~60.
--- parryH -10 = rowa1's unParryableIds. NOT in `dieNow`, despite the port doc.
local BLUE = table.freeze({
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.magic,
	dmg      = 4,
	stun     = 0.3,
	posMult  = 1,
	parryH   = -10,
	stunMeOnParried = 0,
})

--- every number here is rowa1's. LIFETIME is 4, not the aEvent's declared 8:
--- the field's own `tick() + 4` is the truth (README 7g).
local LIFETIME     = 4
local BLUE_RADIUS  = 23             -- damage + pull radius
--- projectiles are caught 4x further out than bodies: a shot only has to be
--- BENT, and a 23-stud grab would only eat what was going to hit you anyway.
local PROJ_RADIUS_MULT = 4
--- studs/s^2 at the CORE, eased to a quarter at the rim (opposite way round
--- from the body pull -- see gravWells). Tuned against the FASTEST projectile.
local PROJ_PULL    = 800
--- without this the well only SLINGSHOTS: a symmetric radial force bends a
--- shot in and back out again, cancelling most of the deflection.
local PROJ_DRAG    = 2.5
local ATTRACT_SIZE = Vector3.new(60, 60, 60)
local HURT_EVERY   = 16             -- heartbeats between damage ticks
--- !! 180, not rowa1's literal 3: its velocity was studs per FRAME (it stepped
--- `pos += velocity` with no dt), so 3 * 60 is the real acceleration. Reading
--- the 3 literally is 60x too slow and the field looks like it is sitting still.
local DRIFT_ACCEL  = 180            -- studs/s^2 toward the aim point
local DRIFT_DAMP   = 0.98           -- per 1/60s, applied framerate-independently
local AIM_RANGE    = 30             -- raycast ahead of the caster
local AIM_LIFT     = 7              -- the orb chases 7 studs above the aim point
local SPAWN_AHEAD  = 8
local SPAWN_UP     = 12
local MANA_PER_SEC = 5             -- rowa1 drained dt*13 every frame

--- !! the pull is a TARGET VELOCITY, not an accumulating impulse: rowa1's
--- damping term is the only thing bounding its sum, and without it the speed
--- diverges to ~22k studs/s (the "flings everything it touches" bug).
--- The ceiling is |desired|, which includes the field's own velocity, so a
--- victim travels WITH the well instead of being outrun by it.
local PULL_SPEED   = 35             -- studs/s of INWARD pull, before the field's own
local SPIN_SPEED   = 6              -- tangential, so they orbit not collapse
local PULL_BLEND   = 0.25           -- how fast an NPC converges on that
local PULL_EVERY   = 2              -- frames between pulls sent to a PLAYER

--- NO DESTRUCTION HERE, on purpose: rowa1's BlueBreak half is a separate port.
--- Do not re-add it blind or the field will carve twice.

--- the field is PULSE-driven, not a steady stream: every emitter ships
--- Enabled = false and rowa1 pulses all five every 0.05s. Merely enabling them
--- gives a flatter continuous stream at the authored Rate. Keep the pulse.
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

	--- !! this channel has NO WINDUP, so feintWait -- the only thing that clears
	--- isFeinted -- is never called. A stale flag silently kills every cast
	--- after the first. Reset at entry, which feintWait would have done for us.
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

	--- REGISTER THE WELL: the tag and two attributes are everything that bends
	--- projectiles. They replicate WITH the part and die with it, so there is no
	--- packet, no per-frame correction and no teardown to forget.
	field:SetAttribute("wellRadius", BLUE_RADIUS * PROJ_RADIUS_MULT)
	field:SetAttribute("wellPull", PROJ_PULL)
	field:SetAttribute("wellDrag", PROJ_DRAG)
	field:AddTag(gravWells.TAG)

	for _, n in ipairs({ "Fx2", "Sound" }) do
		local s = field:FindFirstChild(n)
		if s and s:IsA("Sound") then s:Play() end
	end

	--- !! DO NOT SEND THIS PART TO A CLIENT MODULE -- StreamingEnabled is true,
	--- so an Instance the receiver has not streamed in arrives as NIL forever,
	--- with no error on either side. No wait closes that race. Driving the fx
	--- from here travels WITH the part instead of racing it (DOC_VFX pattern A).
	local emitters, light = collectFx(field)

	local velocity = Vector3.zero
	local frame = 0
	local pulse = FX_PULSE
	local endt = tick() + LIFETIME
	local manaOwed = 0

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

		--- Barrage pattern (S6.2): a fixed-rhythm channel reads the interrupt
		--- itself rather than calling feintWait, which would fight the loop.
		if humObj:inStun() or this.isFeinted then
			this.isFeinted = false
			break
		end
		--- rowa1 also ended the channel below 5 health
		if humObj.Hum and humObj.Hum.Health <= 5 then break end

		--- !! NEVER `mana.Value`. :setMana rawsets the anchor triple (a,t,m) and
		--- THEN sets Value; writing Value alone moves the number without
		--- restamping its clock, so :manaNow never sees the drain. It also
		--- clamps, so rowa1's math.max is gone. (PORT_FullBlue step 2 predates
		--- the anchor and is wrong now.)
		--- BATCHED ONTO THE DAMAGE TICK: :setMana replicates (id 23), so
		--- charging per frame is ~240 packets a channel against ~15 here.
		local canHurt = frame % HURT_EVERY == 0
		manaOwed += dt * MANA_PER_SEC
		if canHurt then
			--- test the computed value, NOT a second :manaNow -- the anchor is
			--- stamped from its own tick() call, so re-reading right after a
			--- setMana(0) returns ~3e-6, not 0, and the channel never ends.
			local left = humObj:manaNow() - manaOwed
			manaOwed = 0
			humObj:setMana(left)
			if left <= 0 then break end
		end

		local pos = field.Position

		--- accelerate (not lerp) toward a point 7 studs above your aim, with a
		--- 0.98 bleed: that lag and overshoot is the only steering the player gets.
		--- !! `velocity` is studs per SECOND here, so the step is `* dt`.
		local target = aimPoint(hurtbox) + Vector3.new(0, AIM_LIFT, 0)
		velocity += CFrame.new(pos, target).LookVector * DRIFT_ACCEL * dt
		--- framerate-independent: 0.98 is per 1/60s, not per frame
		velocity *= DRIFT_DAMP ^ (dt * 60)
		field.Position = pos + velocity * dt

		local _, hits = this:hitbox(CFrame.new(pos), ATTRACT_SIZE, nil, true)

		for _, enemy in pairs(hits) do
			local eroot = enemy.HRootPart
			if eroot == nil then continue end
			local delta = pos - eroot.Position
			local dist = delta.Magnitude
			if dist > BLUE_RADIUS then continue end

			--- rowa1's "saturn ahh orbit": pull in, tangential kick so they swing
			--- rather than collapse, vertical wobble so victims do not stack.
			--- !! the wobble is keyed on entityId, NOT the frame -- on the frame it
			--- becomes one shared pump applied to everyone at once.
			--- Rim pulls hardest and the centre lets go, which keeps bodies circling.
			local dir = dist > 0 and delta.Unit or Vector3.yAxis
			local look = CFrame.new(pos, eroot.Position)
			local wobble = (enemy.entityId % 7) - 3
			local desired = dir * (PULL_SPEED * math.clamp(dist / BLUE_RADIUS, 0.15, 1))
				+ look.RightVector * SPIN_SPEED
				+ Vector3.new(0, wobble, 0)
				--- carried along with the field, as rowa1 added blue.Velocity
				+ velocity

			--- feature-detected: plrObj/FireVFXClient are HumObj's, not in the
			--- Combatant contract, so a boss would throw inside use()'s pcall.
			if enemy.plrObj ~= nil and enemy.FireVFXClient ~= nil then
				--- their client owns that root; throttled because it converges
				--- over a few messages anyway and damps against its own velocity.
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
					--- stopOnGround means a victim dragged at floor level pops
					--- straight back up and reads as no ragdoll; the PULL lifting
					--- them is what saves it. Raise PULL_SPEED before this call.
					enemy.ragdoll:ragdoll(60, true, -delta.Unit * 10)

					--- the setup half of the purple combo; the flag is all that
					--- ships, the nuke is a separate port. See InverseRed's header.
					if enemy.Hum and enemy.Hum.Health <= 0 then
						field:SetAttribute("PurpleReady", true)
					end
				end
			end
		end
	end

	--- settle the part-tick the loop did not charge, so an interrupt costs what
	--- it actually used instead of rounding down to the last damage tick.
	if manaOwed > 0 then humObj:setMana(humObj:manaNow() - manaOwed) end

	if anim then anim:Stop(0.2) end
	releaseAir()

	--- the pulse stops with the loop; kill the light and let what is already
	--- in the air finish its lifetime rather than vanishing mid-flight
	if light then light.Enabled = false end
	--- nothing reads `Finished` for the VFX any more; it stays as the "well is
	--- spent" marker rowa1's orb checks before the purple nuke.
	field:SetAttribute("Finished", true)
	game.Debris:AddItem(field, 5)

	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
