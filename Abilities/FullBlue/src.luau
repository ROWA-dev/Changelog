--!strict
-- FullBlue - a gravity well: drifts along your aim for 4s, drags everything inside 23 studs into orbit and chips it. Control, not burst.
-- !! the server owns the part (its position IS the hitbox origin); players are pulled via their OWN client, since a server impulse on a player root loses to their physics.
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
-- the projectile-bending half of the well. Shared with every client fx.
local gravWells   = require(game.ReplicatedStorage.Modules.gravWells)

-- 4 dmg puts a full channel at ~60 across the ~15 landings; parryH -10 is unparryable.
local BLUE = table.freeze({
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.magic,
	dmg      = 4,
	stun     = 0.3,
	posMult  = 1,
	parryH   = -10,
	stunMeOnParried = 0,
})

-- LIFETIME is 4: the field's own `tick() + 4` is the truth, not any declared 8.
local LIFETIME     = 4
local BLUE_RADIUS  = 23             -- damage + pull radius
-- projectiles are caught 4x further out than bodies: a shot only has to be BENT.
local PROJ_RADIUS_MULT = 4
-- studs/s^2 at the CORE, eased to a quarter at the rim (opposite way round from the body pull, see gravWells).
local PROJ_PULL    = 800
-- without this the well only SLINGSHOTS: a symmetric radial force bends a shot in and back out, cancelling the deflection.
local PROJ_DRAG    = 2.5
local ATTRACT_SIZE = Vector3.new(60, 60, 60)
local HURT_EVERY   = 16             -- heartbeats between damage ticks
-- !! studs per SECOND, so the step is `* dt`; reading this as per-frame is 60x too slow and the field looks stuck.
local DRIFT_ACCEL  = 180            -- studs/s^2 toward the aim point
local DRIFT_DAMP   = 0.98           -- per 1/60s, applied framerate-independently
local AIM_RANGE    = 30             -- raycast ahead of the caster
local AIM_LIFT     = 7              -- the orb chases 7 studs above the aim point
local SPAWN_AHEAD  = 8
local SPAWN_UP     = 12
local MANA_PER_SEC = 5

-- !! the pull is a TARGET VELOCITY, not an accumulating impulse: without the damping bound the speed diverges and flings everything it touches.
local PULL_SPEED   = 35             -- studs/s of INWARD pull, before the field's own
local SPIN_SPEED   = 6              -- tangential, so they orbit not collapse
local PULL_BLEND   = 0.25           -- how fast an NPC converges on that
local PULL_EVERY   = 2              -- frames between pulls sent to a PLAYER

-- NO DESTRUCTION HERE, on purpose: adding it back blind makes the field carve twice.

-- the field is PULSE-driven, not a steady stream; merely enabling the emitters gives a flatter stream at the authored Rate.
local FX_PULSE = 0.05

-- resolve the asset's fx once and force the emitters to the state the pulse expects, not however the asset was last saved.
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
	local hit = workspace:Raycast(origin, hurtbox.CFrame.LookVector * AIM_RANGE, params)
	return hit and hit.Position or (origin + hurtbox.CFrame.LookVector * AIM_RANGE)
end

local function useFunc(this:myself)
	local cooldownID = "fullBlue"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim = this:PlayAnim(script.summon2, 0, 1, 1)

	-- !! no windup means feintWait never runs, so a stale isFeinted silently kills every cast after the first.
	this.isFeinted = false

	-- the field only lives 4s, so budget the hold against that.
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

	-- the tag and two attributes are everything that bends projectiles; they replicate WITH the part, but the tag outlives the channel so teardown must remove it.
	field:SetAttribute("wellRadius", BLUE_RADIUS * PROJ_RADIUS_MULT)
	field:SetAttribute("wellPull", PROJ_PULL)
	field:SetAttribute("wellDrag", PROJ_DRAG)
	field:AddTag(gravWells.TAG)
	-- !! BACKSTOP, not the teardown: useFunc runs inside AbilityBase's pcall, so one throw would leave an immortal invisible well bending shots.
	game.Debris:AddItem(field, LIFETIME + 1)

	for _, n in ipairs({ "Fx2", "Sound" }) do
		local s = field:FindFirstChild(n)
		if s and s:IsA("Sound") then s:Play() end
	end

	-- !! DO NOT SEND THIS PART TO A CLIENT MODULE: with StreamingEnabled an unstreamed Instance arrives as NIL forever, silently (DOC_VFX pattern A).
	local emitters, light = collectFx(field)

	local velocity = Vector3.zero
	local frame = 0
	local pulse = FX_PULSE
	local endt = tick() + LIFETIME
	local manaOwed = 0

	while tick() < endt do
		local dt = task.wait()
		frame += 1

		-- one particle from each emitter, 20 times a second, for as long as the field lives
		pulse += dt
		if pulse > FX_PULSE then
			pulse = 0
			for _, e in ipairs(emitters) do
				e:Emit(1)
			end
		end

		-- a fixed-rhythm channel reads the interrupt itself rather than calling feintWait, which would fight the loop.
		if humObj:inStun() or this.isFeinted then
			this.isFeinted = false
			break
		end
		-- also ends the channel below 5 health
		if humObj.Hum and humObj.Hum.Health <= 5 then break end

		-- !! NEVER write mana.Value; :setMana restamps the anchor clock, and it is batched onto the damage tick because it replicates (~15 packets a channel, not ~240).
		local canHurt = frame % HURT_EVERY == 0
		manaOwed += dt * MANA_PER_SEC
		if canHurt then
			-- test the computed value, NOT a second :manaNow: re-reading right after setMana(0) returns ~3e-6 and the channel never ends.
			local left = humObj:manaNow() - manaOwed
			manaOwed = 0
			humObj:setMana(left)
			if left <= 0 then break end
		end

		local pos = field.Position

		-- accelerate (not lerp) toward a point above the aim with a 0.98 bleed; that lag and overshoot is the only steering the player gets.
		local target = aimPoint(hurtbox) + Vector3.new(0, AIM_LIFT, 0)
		velocity += CFrame.new(pos, target).LookVector * DRIFT_ACCEL * dt
		-- framerate-independent: 0.98 is per 1/60s, not per frame
		velocity *= DRIFT_DAMP ^ (dt * 60)
		field.Position = pos + velocity * dt

		local _, hits = this:hitbox(CFrame.new(pos), ATTRACT_SIZE, nil, true)

		for _, enemy in pairs(hits) do
			local eroot = enemy.HRootPart
			if eroot == nil then continue end
			local delta = pos - eroot.Position
			local dist = delta.Magnitude
			if dist > BLUE_RADIUS then continue end

			-- !! pull in, tangential kick, vertical wobble keyed on entityId NOT the frame -- on the frame it becomes one shared pump on everyone at once.
			local dir = dist > 0 and delta.Unit or Vector3.yAxis
			local look = CFrame.new(pos, eroot.Position)
			local wobble = (enemy.entityId % 7) - 3
			local desired = dir * (PULL_SPEED * math.clamp(dist / BLUE_RADIUS, 0.15, 1))
				+ look.RightVector * SPIN_SPEED
				+ Vector3.new(0, wobble, 0)
				-- carried along with the field
				+ velocity

			-- feature-detected: plrObj/FireVFXClient are HumObj's, not in the Combatant contract, so a boss would throw inside use()'s pcall.
			if enemy.plrObj ~= nil and enemy.FireVFXClient ~= nil then
				-- their client owns that root; throttled because it converges over a few messages anyway.
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
					-- stopOnGround means a victim dragged at floor level pops back up and reads as no ragdoll; the PULL lifting them is what saves it.
					enemy.ragdoll:ragdoll(60, true, -delta.Unit * 10)

					-- the setup half of the purple combo; the flag is all that ships. See InverseRed's header.
					if enemy.Hum and enemy.Hum.Health <= 0 then
						field:SetAttribute("PurpleReady", true)
					end
				end
			end
		end
	end

	-- settle the part-tick the loop did not charge, so an interrupt costs what it actually used.
	if manaOwed > 0 then humObj:setMana(humObj:manaNow() - manaOwed) end

	if anim then anim:Stop(0.2) end
	releaseAir()

	-- !! UNTAG BEFORE THE CORPSE: gravWells finds wells BY TAG and reads nothing else, so the part kept for particles goes on pulling invisibly.
	field:RemoveTag(gravWells.TAG)
	-- the pulse stops with the loop; kill the light and let what is in the air finish its lifetime.
	if light then light.Enabled = false end
	-- `Finished` is the "well is spent" marker checked before the purple nuke, not a VFX flag.
	field:SetAttribute("Finished", true)
	-- the longest emitter Lifetime on MaxBlue is 0.5.
	game.Debris:AddItem(field, 0.5)

	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
