--!strict
-- Freeze - slam the ground and send a line of ice erupting forward: two spikes a step across seven steps, each laying its own sheet of ground ice.
-- !! THE STUN IS NOT IN THE DAMAGE TABLE: the payoff is the Freeze METER, filled in ONE application. Other ice moves CHIP it, this DETONATES it.
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

-- an ordinary heavy row: the stun BECOMES the freeze, and posMult stays low because the meter is the payoff, not a posture deletion on top of it.
local FREEZE_HIT = {
	weight  = dmgUtils.weighEnum.Heavy,
	type    = dmgFlag.ice,
	dmg     = 10,
	stun    = 0.4,
	posMult = 3,
	-- committed heavy, same read as IceBash
	parryH  = -0.04,
	onHit   = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "IceSplash")
	end,
}

-- the WHOLE meter in one application. This is the ice kit's detonator.
local FREEZE_FILL = 10
-- fourteen spikes, two per step: the doubling is what makes the line read as a wall instead of a row of posts.
local STEPS       = 7
local PER_STEP    = 2
local STEP_GAP    = 0.05
-- studs the line advances per step, so it reaches ~49
local STEP_REACH  = 7
-- wait after placing a spike before querying for victims
local SPIKE_ARM   = 0.1
-- the IceSpike MeshPart's own size, so visual and hitbox cannot drift
local SPIKE_SIZE  = Vector3.new(8, 8, 20)
-- caps how many the line can catch
local MAX_VICTIMS = 5
local SNOW_SIZE   = 20
-- the PointLight fade
local LFADE = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- clone an asset child onto a host, play/emit it and bin it; returns the clone so a feint can kill it early.
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

	-- LeftGripAttachment is an R6 part name, so this degrades to the arm and then the root rather than throwing on a rig without one. Ability-local, do not promote it.
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
	-- 10 ticks of 2, through the "emit" quiver id
	fireVFX("emit", arm or root, "backdrop", 10, 2)

	-- WINDUP, split across three feintWaits: 0.22 + 0.05 + 0.45 = 0.72.
	if this:feintWait(0.22) then
		cleanup()
		return
	end

	this:useMana()
	-- deliberately not cut the way IceBash's was: this lands a full freeze on everything in a 49-stud lane.
	this:triggerCD(cooldownID, 12, true)

	-- the slam itself
	keep(attach("impact", castHost))
	keep(attach("IceHit", castHost))
	fireVFX("emit", castHost, "Wind", 6, 4)

	if this:feintWait(0.05) then
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		cleanup()
		return
	end

	-- the ground sheet under the caster, on a smaller radius than the line.
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

	if this:feintWait(0.45) then
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		cleanup()
		return
	end
	humObj.walkSpeed:RemoveMod(SLOW_KEY)

	-- measured off the root ONCE: the line does not re-aim, so turning mid-cast does not bend it.
	local rootPos   = root.Position
	local rootLook  = root.CFrame.LookVector
	local rootRight = root.CFrame.RightVector

	-- !! ONE `seen` for the WHOLE line, not one per spike: :hitbox only dedupes within a query, and a second application lands in the refractory, so two spikes would freeze for LESS time than one.
	local seen: {[number]: boolean} = {}
	local victims = 0

	for i = 1, STEPS do
		for _ = 1, PER_STEP do
			-- spread each spike up to 10 studs to either side
			local sideDiff = rootRight * (math.random(-100, 100) / 10)
			local origin = rootPos + rootLook * STEP_REACH * i + Vector3.new(0, 10, 0) + sideDiff
			local res = workspace:Raycast(origin, Vector3.new(0, -40, 0), params)
			local endp = if res then res.Position else origin + Vector3.new(0, -40, 0)
			local norm = if res then res.Normal else Vector3.yAxis

			fireVFX("placeSnow", endp, norm, SNOW_SIZE)

			-- the spike sits slightly BEHIND its ray, rises with the step index, is aimed forward-and-up, then pushed 8 studs along its own -Z.
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

				-- the spike's OWN transform is the hitbox, in world space, so what you see and what hits cannot drift apart.
				local _, hits = this:hitbox(cf, SPIKE_SIZE+Vector3.new(2,2,2), nil, true)
				for _, enemy in pairs(hits) do
					if victims >= MAX_VICTIMS then break end
					if seen[enemy.entityId] then continue end
					seen[enemy.entityId] = true
					victims += 1

					-- !! atkDir is a real WORLD vector, not a local-space flinch selector, so the line's own heading belongs here.
					local attack = this:makeAtk(FREEZE_HIT, enemy, rootLook)
					this:executeAttack(attack)

					if attack:isHit() then
						enemy.statusEffects:apply(statusEffects.Freeze, 4, FREEZE_FILL)
					else
						-- shatter the spike on any defended result
						fireVFX("iceSpike", 1, spikeId)
					end
				end
			end)
		end

		-- fixed-rhythm channel, so the interrupt checks are hand-rolled between beats rather than going through feintWait.
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
	this:endLag(0.3)
	return true
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
