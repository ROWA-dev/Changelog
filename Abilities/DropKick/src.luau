--!strict
-- DropKick - hop, then dive on a diagonal until a body, the floor or a stun ends it; only the floor carves.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "DropKick"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag  = dmgUtils.dmgFlags
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)
local pinTo    = require(game.ServerStorage.ROWA.Modules.pinTo)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

local DROP_KICK = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.magic, dmgFlag.blunt),
	dmg      = 20,
	stun     = 0.5,
	posMult  = 2,
}

local DIVE_FORCE = 16
local MAX_DIVE   = 2
local AIM        = Vector3.new(0, -10, -8) -- the dive's aim, root space

-- the ride loop runs every frame, so lead only: test where the dive is about to be
local DIVE = table.freeze({ worldSpace = true })
local HOP_FORCE  = 8
local HOP_TIME   = 0.1
local HOP_WIND   = Vector3.new(0, -1.5, 0) -- the takeoff gust, at the feet

-- the contact freeze, pauseF's flash length; Smash's arm so it beats the dive's momentum
local HITSTOP = 0.3
local FREEZE = table.freeze({ axes = Vector3.one, responsiveness = 200, maxTime = HITSTOP })
-- the victim's half of the frame: hitFront's extreme is its first frame
local HIT_POSE = game.ServerStorage.ROWA.Class.HumObj.HitAnims.hitFront
-- the loop pose's soles in root space; the victim is cframed chest-on to them, facing the kick
local SOLES = Vector3.new(0, -1.8, -2.4)
local VICTIM_AT = CFrame.new(SOLES + Vector3.new(0, -0.4, -0.5)) * CFrame.Angles(0, math.pi, 0)

local diveParams = RaycastParams.new()
diveParams.FilterType = Enum.RaycastFilterType.Exclude
diveParams.IgnoreWater = true
-- a body isn't the floor: Entities excluded so only the world ends the ride, the sweep answers people
diveParams.FilterDescendantsInstances = { workspace.Effects, workspace.Entities }

local function useFunc(this:myself)
	local cooldownID = "dropKick"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local first = this:PlayAnim(script.First, 0, 1, 1.2)

	-- the hop, root-relative so it follows your facing
	local hop = this:bodyForce(
		(Vector3.new(0, 1, 0) + Vector3.new(0, 0, -0.25)).Unit * HOP_FORCE,
		HOP_TIME, true)
	fireVFX("windShock", hurtbox, HOP_WIND)

	if this:feintWait(0.4) then
		if first then first:Stop() end
		if hop then hop:destroy() end
		return
	end
	
	first:AdjustSpeed(1)

	fireVFX("dropKickCharge", char:FindFirstChild("Right Leg"), 1.5)

	if this:feintWait(0.2) then
		if first then first:Stop() end
		fireVFX("dropKickCharge", nil, 0)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	local loopAnim = this:PlayAnim(script.loop, 0, 1, 1)

	local root = humObj.HRootPart
	local dive = this:bodyForce(Vector3.new(0, -1.2, -1).Unit * DIVE_FORCE, MAX_DIVE, true)

	local hits, landing
	local started = tick()

	while tick() < started + MAX_DIVE do
		task.wait()
		if humObj:inStun() then break end
		root = humObj.HRootPart
		if root == nil then break end

		local dir = root.CFrame:VectorToWorldSpace(AIM)
		local u = dir.Unit

		-- people first, or the 12.8 stud floor ray ends most dives before the sweep runs
		local _, found = this:sweep(CFrame.new(root.Position + u, root.Position + u * 6), Vector3.new(7,7,7), DIVE)
		if #found > 0 then
			hits = found
			break
		end

		local result = workspace:Raycast(root.Position, dir, diveParams)
		if result and result.Instance.CanCollide then
			landing = result
			break
		end
	end

	if dive then dive:destroy() end
	fireVFX("dropKickCharge", nil, 0)

	root = humObj.HRootPart
	local origin = if landing then landing.Position
		elseif root then root.Position
		else hurtbox.Position
	local dir = if root then root.CFrame:VectorToWorldSpace(AIM).Unit
		else Vector3.new(0, -1, 0)

	if landing then
		Destruction.Sphere(nil, origin, 3.5, 2.1, dir * 40)
	end
	fireVFX("dropKickLand", origin, dir)

	-- a landing still swings, lifted 2 studs off the crater to cover a standing body
	if hits == nil and not humObj:inStun() then
		local _, found = this:hitbox(
			CFrame.new(origin + Vector3.new(0, 2, 0)),
			Vector3.new(6, 6, 6), nil, true)
		if #found > 0 then hits = found end
	end

	local lag = 0.5 -- miss
	if hits and not humObj:inStun() then
		local landed, holds = {}, {}
		for _, enemy in pairs(hits) do
			local attack = this:makeAtk(DROP_KICK, enemy, dir)
			this:executeAttack(attack)
			if attack:isHit() then
				local e = attack.enemyEntity
				local vr = e.HRootPart
				local pose = e.PlayAnim and e:PlayAnim(HIT_POSE, 0, 1, 0)
				landed[attack] = pose or false
				-- lifted to the soles, never sunk into the floor
				if pose and vr and root then
					local cf = root.CFrame * VICTIM_AT
					cf += Vector3.yAxis * math.max(vr.Position.Y - cf.Y, 0)
					vr.CFrame = cf
					table.insert(holds, pinTo(vr, function() return cf.Position end, FREEZE))
				end
				fireVFX("pauseF", char, vr and vr.Parent)
			end
		end

		-- hitstop: both held on contact; crunch and launch wait for the release so the freeze sfx isn't buried
		if next(landed) then
			if loopAnim then loopAnim:AdjustSpeed(0) end
			local sfx = script.parryultrakill:Clone()
			sfx.Parent = hurtbox
			sfx:Play()
			game.Debris:AddItem(sfx, 4)
			if root then
				local at = root.Position
				table.insert(holds, pinTo(root, function() return at end, FREEZE))
				fireVFX("dropKickHit", root.CFrame * SOLES, dir, HITSTOP)
			end
			task.wait(HITSTOP)
			for _, release in holds do release() end

			fireVFX("camShake", hurtbox.Position, 100, 0.3, 0.2)
			for attack, pose in landed do
				if pose then pose:Stop() end
				local e = attack.enemyEntity
				if e.HRootPart == nil then continue end
				hitSfx(e.HRootPart, "HardPunchHit", "HitCrush")
				attack.knockback = this:knockback(dir * 17, 0.2, false, -1)
				attack:ApplyKnockback()
				e.ragdoll:ragdoll(60, true, attack.atkDir*10)
			end
		end
		lag = 0.25
	end

	-- the kick's gust, hit or miss; after the hitstop so it leaves with the launch
	fireVFX("fistHvy", hurtbox, dir)
	if loopAnim then loopAnim:Stop(0.1) end
	this:endLag(lag)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
