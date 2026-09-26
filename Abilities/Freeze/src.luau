--!strict
-- Freeze - slam the ground and send a line of ice erupting forward: two spikes a step across seven steps, each laying its own sheet of ground ice.
local baseClass = require(script.Parent.AbilityBase)
-- MassFreeze subclasses this and overrides the statics below.
export type myself = baseClass.myself & { cdId: string, cd: number, maxVictims: number, steps: number, crown: number? }
type humObj = baseClass.humObj

local module = {
	Name = "Freeze",
	cdId = "freeze",
	cd = 12,
	maxVictims = 5, -- caps how many the line can catch
	steps = 7,
	crown = nil :: number?, -- spikes ringing a spire where the line ends
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
local layIce        = require(game.ServerStorage.ROWA.Modules.layIce)
local hitSfx        = require(game.ServerStorage.ROWA.Modules.hitSfx)

local FREEZE_HIT = {
	weight  = dmgUtils.weighEnum.Heavy,
	type    = dmgFlag.ice,
	dmg     = 10,
	stun    = 0.4,
	posMult = 4,
	parryH  = -0.04,
	dodgeH  = -0.1,
	onHit   = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "IceSplash")
	end,
}

-- the WHOLE meter in one application. This is the ice kit's detonator.
local FREEZE_FILL = 10
-- two spikes per step: the doubling is what makes the line read as a wall instead of a row of posts.
local PER_STEP    = 2
local STEP_GAP    = 0.05
-- studs the line advances per step, so 7 steps reach ~49
local STEP_REACH  = 7
-- wait after placing a spike before querying for victims
local SPIKE_ARM   = 0.1
-- the IceSpike MeshPart's own size, so visual and hitbox cannot drift
local SPIKE_SIZE  = Vector3.new(8, 8, 20)
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
	local cooldownID = this.cdId
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
	
	-- not "freeze": that is the Freeze status effect's root, and removing it here would thaw a frozen caster.
	local SLOW_KEY = "freezeCast"
	humObj.walkSpeed:SetMod(SLOW_KEY, -100)

	keep(attach("Flare1", castHost, 1))
	keep(attach("PointLight", castHost))
	keep(attach("weird", castHost))
	-- 10 ticks of 2, through the "emit" quiver id
	fireVFX("emit", arm or root, "backdrop", 10, 2)

	-- WINDUP, split across three feintWaits: 0.22 + 0.05 + 0.45 = 0.72.
	if this:feintWait(0.22) then
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		cleanup()
		return
	end

	this:useMana()
	-- deliberately not cut the way IceBash's was: this lands a full freeze on everything in a 49-stud lane.
	this:triggerCD(cooldownID, this.cd, true)

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

	local hurtbox = humObj.HurtBox
	local castOrigin = hurtbox.Position + hurtbox.CFrame.LookVector * 2 - hurtbox.CFrame.RightVector
	local castHit = workspace:Raycast(castOrigin, Vector3.new(0, -10, 0), params)
	keep(attach("Rays", castHost, 1))
	if castHit then
		layIce(castHit.Position, castHit.Normal, 9, castHit.Instance :: BasePart)
	end

	if this:feintWait(0.45) then
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		cleanup()
		return
	end
	humObj.walkSpeed:RemoveMod(SLOW_KEY)

	-- measured off the root ONCE: the line does not re-aim, so turning mid-cast does not bend it.
	local rootPos   = hurtbox.Position
	local rootLook  = hurtbox.CFrame.LookVector
	local rootRight = hurtbox.CFrame.RightVector

	-- !! ONE `seen` for the WHOLE line, not one per spike: :hitbox only dedupes within a query, and a second application lands in the refractory, so two spikes would freeze for LESS time than one.
	local seen: {[number]: boolean} = {}
	local victims = 0

	-- the ground under a point and the part it is, or 30 studs below it over a void.
	local function ground(at: Vector3): (Vector3, Vector3, BasePart?)
		local res = workspace:Raycast(at + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), params)
		if res then return res.Position, res.Normal, res.Instance :: BasePart end
		return at - Vector3.new(0, 30, 0), Vector3.yAxis, nil
	end

	-- one spike of scale s rooted at `at`, pushed out along its own -Z, arming its own hitbox a beat later.
	local function spike(at: CFrame, s: number)
		local cf = at * CFrame.new(0, 0, -8 * s)
		local spikeId = math.random(1, 65536)
		-- scale 1 goes as nil, so plain Freeze's wire is unchanged
		fireVFX("iceSpike", 0, spikeId, cf, if s ~= 1 then s else nil)

		task.spawn(function()
			task.wait(SPIKE_ARM)
			if humObj.isActive ~= true then return end

			-- the spike's OWN transform is the hitbox, in world space, so what you see and what hits cannot drift apart.
			local _, hits = this:hitbox(cf, SPIKE_SIZE * s + Vector3.new(2, 2, 2), nil, true)
			for _, enemy in pairs(hits) do
				if victims >= this.maxVictims then break end
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

	-- Freeze's own length: past it k stops the rise (the base would lift off the ground), s grows the spike and the fan widens as s^2.
	local BASE = module.steps
	for i = 1, this.steps do
		local k = math.min(i, BASE)
		local s = 1 + math.max(0, i - BASE) / BASE
		local w = s * s
		local n = math.round(PER_STEP * w)
		for j = 1, n do
			-- one lane each across 10*w studs either side, so a wide fan fills evenly instead of clumping
			local side = rootRight * (((j - math.random()) / n * 2 - 1) * 10)
			local endp, norm, hitPart = ground(rootPos + rootLook * STEP_REACH * i + side * w)
			-- every other lane, and the last, lays a sheet: that already covers the fan
			if j % 2 == 1 or j == n then
				layIce(endp, norm, SNOW_SIZE * s, hitPart)
			end

			-- sits slightly BEHIND its ray, rises with the step index, aimed forward-and-up; s scales the shape about its ground point.
			local org3 = endp + (Vector3.new(0, k / 1.6 - 3, 0) - rootLook * 4 - side / 2) * s
			local aim = org3
				+ (side * (k / 20) + rootRight * (math.random(-10, 10) / 10) + rootLook * 2 + Vector3.new(0, 1 + k / 2, 0)) * s
			spike(CFrame.lookAt(org3, aim), s)
		end

		-- fixed-rhythm channel, so the interrupt checks are hand-rolled between beats rather than going through feintWait.
		task.wait(STEP_GAP)
		if this:channelBreak() then
			if anim then anim:Stop(0.1) end
			return true
		end
	end

	local crown = this.crown
	if crown then
		local tip, tipNorm, tipPart = ground(rootPos + rootLook * STEP_REACH * (this.steps + 1))
		layIce(tip, tipNorm, SNOW_SIZE * 4, tipPart)
		fireVFX("camShake", tip, 300, 1.5, 0.5)
		local base = tip - Vector3.new(0, 3, 0)
		-- the spire, near upright
		spike(CFrame.lookAt(base, base + rootLook * 0.3 + Vector3.new(0, 1.8, 0)), 2.5)
		-- two tiers round it: `crown` tall ones leaning out, then twice as many lower, wider and flatter
		for ring = 1, 2 do
			local count = crown * ring
			for n = 1, count do
				local out = CFrame.Angles(0, (n + math.random() * 0.5) / count * 2 * math.pi, 0) * rootLook
				local at = base + out * (8 * ring - 2)
				spike(CFrame.lookAt(at, at + out * ring + Vector3.new(0, 1.8, 0)), 2.5 - ring / 2)
			end
		end
	end

	if anim then anim:Stop(0.2) end
	this:endLag(0.1)
	return true
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
