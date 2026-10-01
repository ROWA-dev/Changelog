--!strict
-- StormUp - rising lightning spin that launches the victim up with you; air-combo handoff is manual since it starts grounded.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "StormUp"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local dmgUtils  = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag   = dmgUtils.dmgFlags
local Targeting = require(game.ServerStorage.ROWA.Modules.Targeting)
local fireVFX   = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx    = require(game.ServerStorage.ROWA.Modules.hitSfx)

local STORM = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.lightning,
	dmg      = 18,
	stun     = 1.2,
	posMult  = 1,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit", "LightningRelease")
	end,
}

local TARGET_RANGE = 100
-- bodyForce scales by 5, so power 50.
local RISE = 10

-- mirrors HumObj onAttacked's air-combo handoff.
local function startAirCombo(me: any, them: any, stun: number)
	local keep = 0.2 + stun
	if them.floating then
		them.floating.Value = keep
		them.targetFloatY.Value = me.HurtBox or me.HRootPart
	end
	if me.floating then
		me.floating.Value = keep
		me.targetFloatY.Value = them.HurtBox or them.HRootPart
	end
end

local function useFunc(this:myself)
	local cooldownID = "stormUp"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	-- nil target = hop, not a bail.
	local target = Targeting.nearestInDirection(
		hurtbox.Position, hurtbox.CFrame.LookVector, humObj, TARGET_RANGE,
		Targeting.SOFT)

	if target then
		fireVFX("phantom", char, char.PrimaryPart and char.PrimaryPart.CFrame or hurtbox.CFrame)
	end

	-- !! HRootPart, not HurtBox: shockspin's AlignPosition drags this part (massless HurtBox moves nothing).
	local leftArm = char:FindFirstChild("Left Arm")
	fireVFX("shockspin", humObj.HRootPart, leftArm, 0.8, target and target.HRootPart)

	if this:feintWait(0.12) then
		if anim then anim:Stop(0.1) end
		return
	end

	fireVFX("shockspin2", hurtbox)

	if this:feintWait(0.4) then
		if anim then anim:Stop(0.1) end
		return
	end

	fireVFX("camShake", hurtbox.Position, 200, 0.4, 0.2)

	if this:feintWait(0.2) then
		if anim then anim:Stop(0.1) end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	if target == nil then
		this:bodyForce(Vector3.new(0, 1, 0).Unit * RISE + Vector3.new(0, 0, -RISE / 4), 0.2, true)
		this:endLag(0.2)
		return
	end

	local origin = (hurtbox.Position + target.HRootPart.Position) / 2
	local forward = hurtbox.CFrame.LookVector
	local cf = CFrame.new(origin + forward * 5, origin + forward * 10)
	local _, hits = this:hitbox(cf, Vector3.new(8, 8, 8), nil, true)

	local parried = false
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(STORM, enemy, Vector3.new(0, 1, 0))
		attack.knockback = this:knockback(
			Vector3.new(0, 10.8, -1.2), 0.25, true, -1)
		this:executeAttack(attack)

		if attack:isParried() then
			parried = true
		elseif attack:isHit() or attack:isBlocked() or attack:isDodged() then
			attack.enemyEntity.statusEffects:apply(enemy.statusEffects.Shock, 1.5, 1)
			if not attack:isDodged() then startAirCombo(humObj, enemy, STORM.stun) end
		end
	end

	-- parry cancels the follow-up.
	if not parried then
		fireVFX("messySpinShock",
			hurtbox.Position + forward * 2 + Vector3.new(0, 10, 0))
		fireVFX("camShake", hurtbox.Position, 400, 2, 0.2)
		this:bodyForce(Vector3.new(0, 1, 0).Unit * RISE + Vector3.new(0, 0, -RISE / 4), 0.2, true)
	end

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
