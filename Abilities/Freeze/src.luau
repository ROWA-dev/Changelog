--!strict
--[[ Freeze - rowa1 Items/Ability/Freeze. Port notes: README.md/PORT_Freeze.

	Slam the ground and send a line of ice erupting forward: two spikes a step
	across seven steps, marching seven studs at a time, each one laying its own
	sheet of ground ice. A ground-line AoE, not a projectile.

	!! THE STUN IS NOT IN THE DAMAGE TABLE ANY MORE.
	rowa1's "freeze" row carried truestun 1.3 AND stun 2.0 -- the longest lockup
	in that game. Here the row is an ordinary heavy hit and the payoff is the
	Freeze METER: this ability fills the whole thing in ONE application, so it
	lands the full 1.1s TrueStun and then cannot be re-applied for four seconds.
	IceBash/IceBeam/IceSlash/IceShards CHIP that meter; this DETONATES it, and
	neither side knows the other exists.
	See Class/StatusEffects/Freeze and PORT_Freeze section 1.

	Worth noting for once: "freeze" appears in NONE of rowa1's nine resolver
	string sets, so unlike the rest of the ice kit there were no hidden
	exemptions to translate. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Freeze"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local Debris        = game:GetService("Debris")
local TweenService  = game:GetService("TweenService")
local dmgUtils      = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag       = dmgUtils.dmgFlags
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local fireVFX       = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx        = require(game.ServerStorage.ROWA.Modules.hitSfx)

--[[ rowa1: Heavy / ice / 10 dmg / truestun 1.3 / stun 2.0 / posMult 6,
	sounds { IceSplash }.
	The two stun fields collapse to one (README S4.2) and the 2.0 does NOT
	survive as stun -- it BECOMES the freeze. posMult drops 6 -> 3 for the same
	reason: the meter is the payoff now, not a posture deletion on top of it.
	Damage is left at rowa1's 10; it was never the point of the move. ]]
local FREEZE_HIT = {
	weight  = dmgUtils.weighEnum.Heavy,
	type    = dmgFlag.ice,
	dmg     = 10,
	stun    = 0.4,
	posMult = 3,
	--- committed heavy, same read as IceBash
	parryH  = -0.04,
	onHit   = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "IceSplash")
	end,
}

--- the WHOLE meter in one application. This is the ice kit's detonator.
local FREEZE_FILL = 10
--[[ rowa1 is `for i = 1,7 do for i2 = 1,2 do`. PORT_Freeze says "7 spikes";
	the code says fourteen, two per step, and the doubling is what makes the
	line read as a wall instead of a row of posts. Ported from the code. ]]
local STEPS       = 7
local PER_STEP    = 2
local STEP_GAP    = 0.05
--- studs the line advances per step, so it reaches ~49
local STEP_REACH  = 7
--- rowa1 waited 0.1 after placing a spike before querying for victims
local SPIKE_ARM   = 0.1
--- the IceSpike MeshPart's own size, so visual and hitbox cannot drift
local SPIKE_SIZE  = Vector3.new(8, 8, 20)
--- rowa1 `if #humsH > 4 then break end`
local MAX_VICTIMS = 5
local SNOW_SIZE   = 20
--- lfade: rowa1's two-line PointLight fade, inlined per README S5
local LFADE = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--- clone an asset child onto a host, play/emit it, and bin it. Returns the
--  clone so a feint can kill it early.
local function attach(name: string, host: Instance, emit: number?): Instance?
	local src = script:FindFirstChild(name)
	if src == nil or host.Parent == nil then
		return nil
	end
	local c = src:Clone()
	c.Parent = host
	if c:IsA("Sound") then
		c:Play()
	elseif c:IsA("ParticleEmitter") then
		c:Emit(emit or 1)
	elseif c:IsA("PointLight") then
		c.Enabled = true
		TweenService:Create(c, LFADE, { Brightness = 0 }):Play()
	end
	Debris:AddItem(c, 4)
	return c
end

local function useFunc(this:myself)
	local cooldownID = "freeze"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj = this._humObj
	local root   = humObj.HRootPart
	local char: any = humObj.HurtBox.Parent
	local anim   = this:PlayAnim(script.Anim, 0, 1, 1)

	--[[ rowa1 hung every cast effect off Char["Left Arm"].LeftGripAttachment.
		That is an R6 part name, so it degrades to the arm and then to the root
		rather than throwing on a rig without one. Ability-local quirk, exactly
		like FireStab's blade fallback -- it must NOT grow into the entity
		contract (README S6.3). ]]
	local arm = char:FindFirstChild("Left Arm")
	local castHost: Instance = (arm and arm:FindFirstChild("LeftGripAttachment")) or arm or root

	local spawned: {Instance} = {}
	local function keep(inst: Instance?)
		if inst then table.insert(spawned, inst) end
	end
	local function cleanup()
		if anim then anim:Stop(0.1) end
		for _, inst in ipairs(spawned) do
			Debris:AddItem(inst, 0)
		end
	end
	
	local SLOW_KEY = "freeze"
	humObj.walkSpeed:SetMod(SLOW_KEY, -100)

	keep(attach("Flare1", castHost, 1))
	keep(attach("PointLight", castHost))
	keep(attach("weird", castHost))
	--- rowa1 routed these through the "emit" quiver id; its header already
	--- names Freeze as a customer. 10 ticks of 2.
	fireVFX("emit", arm or root, "backdrop", 10, 2)

	--[[ WINDUP. rowa1 declares Attacking.Time 1.0 but the real waits are
		0.3 + 0.05 + 0.4 + 0.05 = 0.8 (README S5 note 7g -- the claim and the
		truth disagree, port the truth). Split across three feintWaits, and
		only the FIRST one takes the -0.08 lead: the two after it are plain
		beats and are passed n + 0.08, so the move loses 0.08 in TOTAL rather
		than 0.08 per beat (note 7f). 0.22 + 0.05 + 0.45 = 0.72. ]]
	if this:feintWait(0.3) then
		cleanup()
		return
	end

	this:useMana()
	--[[ rowa1 cd12, and NOT cut the way IceBash's 12 -> 8 was: this one lands a
		full freeze on everything in a 49-stud lane. Q2 is still open. ]]
	this:triggerCD(cooldownID, 12, true)

	-- the slam itself
	keep(attach("impact", castHost))
	keep(attach("IceHit", castHost))
	fireVFX("emit", castHost, "Wind", 6, 4)

	if this:feintWait(0.13) then
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		cleanup()
		return
	end

	--- the ground sheet under the caster. rowa1 raycast 10 studs down from
	--- root + look*2 + right*-1 and used a smaller radius here than the line.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		workspace:FindFirstChild("Effects") :: any,
		workspace:FindFirstChild("Entities") :: any,
	}

	local castOrigin = root.Position + root.CFrame.LookVector * 2 - root.CFrame.RightVector
	local castHit = workspace:Raycast(castOrigin, Vector3.new(0, -10, 0), params)
	keep(attach("Rays", castHost, 1))
	if castHit then
		fireVFX("placeSnow", castHit.Position, castHit.Normal, 9)
	end

	if this:feintWait(0.53) then
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		cleanup()
		return
	end
	humObj.walkSpeed:RemoveMod(SLOW_KEY)

	--[[ everything below is measured off the root ONCE, exactly as rowa1 does.
		The line does not re-aim, so turning mid-cast does not bend it. ]]
	local rootPos   = root.Position
	local rootLook  = root.CFrame.LookVector
	local rootRight = root.CFrame.RightVector

	--[[ ONE `seen` for the WHOLE line, not one per spike. :hitbox only dedupes
		WITHIN a single query, and with a meter a second application is worse
		than merely wasted: the first 10 trips the freeze, the next 10 arrives
		during the 4s refractory and is thrown away, so a victim caught by two
		spikes would be frozen for LESS total time than one caught by one.
		PORT_Freeze step 6, same trap as Huozai and Cero. ]]
	local seen: {[number]: boolean} = {}
	local victims = 0

	for i = 1, STEPS do
		for _ = 1, PER_STEP do
			--- rowa1 spreads each spike up to 10 studs to either side
			local sideDiff = rootRight * (math.random(-100, 100) / 10)
			local origin = rootPos + rootLook * STEP_REACH * i + Vector3.new(0, 10, 0) + sideDiff
			local res = workspace:Raycast(origin, Vector3.new(0, -40, 0), params)
			local endp = if res then res.Position else origin + Vector3.new(0, -40, 0)
			local norm = if res then res.Normal else Vector3.yAxis

			fireVFX("placeSnow", endp, norm, SNOW_SIZE)

			--[[ rowa1's placement, unchanged. The spike sits slightly BEHIND
				its ray (-look*4), rises with the step index (i/1.6 - 3) and is
				aimed forward-and-up, then pushed 8 studs along its own -Z. ]]
			local org3 = endp - sideDiff / 2 + Vector3.new(0, i / 1.6 - 3, 0) - rootLook * 4
			local org4 = org3 + sideDiff * (i / 20)
			local aim = org4
				+ rootRight * (math.random(-10, 10) / 10)
				+ rootLook * 2
				+ Vector3.new(0, 1 + i / 2, 0)
			local cf = CFrame.lookAt(org3, aim) * CFrame.new(0, 0, -8)

			local spikeId = math.random(1, 65536)
			fireVFX("iceSpike", 0, spikeId, cf)

			task.spawn(function()
				task.wait(SPIKE_ARM)
				if humObj.isActive ~= true then return end

				--[[ the spike's OWN transform is the hitbox, in world space, so
					what you see and what hits cannot drift apart. That is worth
					keeping; rowa1 got it right. ]]
				local _, hits = this:hitbox(cf, SPIKE_SIZE, nil, true)
				for _, enemy in pairs(hits) do
					if victims >= MAX_VICTIMS then break end
					if seen[enemy.entityId] then continue end
					seen[enemy.entityId] = true
					victims += 1

					--[[ !! rowa1 passed vector.create(0,0,1) here, which is NOT
						a direction -- it is the local-space FRONT FLINCH
						selector (README S7 step 8). rowa2's atkDir is a real
						world vector, so the line's own heading is what belongs
						here. ]]
					local attack = this:makeAtk(FREEZE_HIT, enemy, rootLook)
					this:executeAttack(attack)

					if attack:isHit() then
						enemy.statusEffects:apply(statusEffects.Freeze, 4, FREEZE_FILL)
					else
						--- rowa1 shattered the spike on any defended result
						fireVFX("iceSpike", 1, spikeId)
					end
				end
			end)
		end

		--[[ fixed-rhythm channel, so the interrupt checks are hand-rolled
			between beats rather than going through feintWait -- the Barrage
			block (README S6.2), copied rather than reinvented. ]]
		task.wait(STEP_GAP)
		if humObj:inStun() then
			if anim then anim:Stop(0.1) end
			return true
		end
		if this.isFeinted == true then
			if anim then anim:Stop(0.1) end
			this.isFeinted = false
			humObj.cooldowns:trigger("feint2")
			fireVFX("feintfx", char)
			return true
		end
	end

	if anim then anim:Stop(0.2) end
	--- rowa1 tailed with task.wait(0.1); PORT_Freeze step 8 asks for 0.3
	this:endLag(0.3)
	return true
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
