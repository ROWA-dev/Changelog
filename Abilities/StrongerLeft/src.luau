--!strict
--- StrongerLeft - StrongLeft's big brother: longer charge, three shockwave
--- rings, screen shake, terrain destruction, heaviest non-ultimate hit.
--- Structurally StrongLeft.luau with different numbers, on purpose.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "StrongerLeft"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag  = dmgUtils.dmgFlags
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

--- posMult 4, not 6: the posture pool is 80, and 6 guard-breaks in two
--- connects from full.
--- parryH is matched to StrongLeft, so the HARDER version is not the easier
--- one to parry.
local STR_P2 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 40,
	stun     = 1.6,
	posMult  = 4,
	parryH   = -0.04,
	onHit    = function(attack, _source)
		local eroot = attack.enemyEntity.HRootPart
		fireVFX("strpunch", eroot)
		hitSfx(eroot, "HardPunchHit", "GoreyHit")
	end,
}

local function useFunc(this:myself)
	local cooldownID = "strongerLeft"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent

	--[[ nil-degrade the arm lookup. StrongLeft chains
		FindFirstChild("Left Arm"):FindFirstChild(...) and throws on any rig
		without one -- and because use() pcalls, that silently eats the whole
		ability. Worth fixing there too. ]]
	local leftArm = char:FindFirstChild("Left Arm")
	local grip = leftArm and leftArm:FindFirstChild("LeftGripAttachment")

	local anim = this:PlayAnim(script.Punch, 0, 1, 0.8)

	local startSnd = script.start:Clone()
	startSnd.Parent = hurtbox
	startSnd:Play()
	game.Debris:AddItem(startSnd, 4)

	local sparks, circle
	if grip then
		sparks = script.handsparks:Clone()
		sparks.Parent = grip
		game.Debris:AddItem(sparks, 4)

		circle = script.circle:Clone()
		circle.Parent = grip
		game.Debris:AddItem(circle, 4)
	end

	--[[ !! THE CALLBACK RUNS EVERY FRAME, NOT EVERY 0.05s, so emitting straight
		out of it runs at ~60Hz instead of the 20Hz this wants. The accumulator
		restores the cadence and makes it framerate-independent. ]]
	local sinceEmit, ticks = 0, 0
	local feinted = this:feintWait(0.72, function(dt: number)
		sinceEmit += dt
		if sinceEmit < 0.05 then return end
		sinceEmit -= 0.05
		ticks += 1
		if sparks then sparks:Emit(8) end
		if circle and ticks % 2 == 0 then circle:Emit(1) end
	end)

	if feinted then
		if anim then anim:Stop() end
		game.Debris:AddItem(startSnd, 0)
		if sparks then game.Debris:AddItem(sparks, 0) end
		if circle then game.Debris:AddItem(circle, 0) end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 9, true)
	-- bodyForce scales by 5 internally, so this is a power-40 lunge.
	this:bodyForce(Vector3.new(0, 0, -8), 0.2, true)

	if anim then anim:AdjustSpeed(1.1) end

	local loud = script.lowLoud:Clone()
	loud.Parent = hurtbox
	loud:Play()
	game.Debris:AddItem(loud, 4)

	local forward = hurtbox.CFrame.LookVector
	local origin  = hurtbox.Position

	--[[ the slam body and the three rings are ONE client effect. Do NOT go back
		to cloning a server Part into workspace.Effects and listening for it --
		see VFXQuiver/strongerSlam for the full argument. ]]
	fireVFX("strongerSlam", hurtbox)

	--- r8 is the inscribed sphere of the 16^3 cut this replaced; the
	--- circumscribed one would carve ~40% wider.
	--- velo is studs/SECOND: `forward` alone is 1, which is why the rubble
	--- used to sit there. A punch this size throws it.
	Destruction.Sphere(nil, origin + Vector3.new(0, 8, 0) + forward * 9, 8, 4.8, forward * 60)

	--- camShake takes (pos, range, intensity, dur).
	fireVFX("camShake", origin, 400, 2, 0.3)

	local _, hits = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(7, 7, 7))
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(STR_P2, enemy, forward)
		attack.knockback = this:knockback(
			attack.atkDir * 30 + Vector3.new(0, 5, 0), 0.15, false, -1)

		this:executeAttack(attack)
		if attack:isHit() then
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 12)
		end
	end

	-- the trailing hand smoke deliberately outlives the move.
	if grip then
		local smoke = script.smoke:Clone()
		smoke.Parent = grip
		game.Debris:AddItem(smoke, 4)
		task.spawn(function()
			for _ = 1, 16 do
				if smoke.Parent == nil then return end
				smoke:Emit(1)
				task.wait(0.08)
			end
		end)
	end

	humObj.canAtkThreshold = tick() + 0.3
	this:endLag(0.15)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
