--!strict
-- Quake - op strongest left
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Quake",
	manaUse = 25,
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

-- the fist that catches them; the quake is the payoff
local PUNCH = table.freeze({
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 10,
	stun     = 1,
	posMult  = 2,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HeavyHit")
	end,
})

local QUAKE = table.freeze({
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 40,
	stun     = 1,
	posMult  = 4,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitCrush")
		-- a long CAP, ended by landing
		attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 30)
	end,
})

-- Smash's freeze: all three axes, so it wins against anything moving them
local FREEZE = table.freeze({
	axes = Vector3.one,
	responsiveness = 200,
	maxTime = 0.5,
})

-- marks on the track: the fist lands, holds, the quake lets go, the clip ends
local HIT, RELEASE, TRACK_END = 1.18, 1.37, 1.97
-- the scene's quake reaches its DustBack, 55 studs out
local LANE = Vector3.new(14, 10, 55)
local FIST = CFrame.new(0, 0, -4)

local function useFunc(this:myself)
	local cooldownID = "quake"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)
	humObj.walkSpeed:SetMod(cooldownID, -100)
	fireVFX("quake", 1, char)

	-- every early exit owes the walkSpeed back
	local function bail()
		if anim then anim:Stop(0.1) end
		humObj.walkSpeed:RemoveMod(cooldownID)
	end

	if this:feintWait(HIT) then
		bail()
		fireVFX("quake", 0, char)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 15)
	fireVFX("quake", 2, char)

	-- the grab: the first body the fist lands on hangs there through the hold
	local release:(()->())? = nil
	local at = (hurtbox.CFrame * FIST).Position
	local _, reach = this:hitbox(FIST, Vector3.new(7, 7, 7))
	for _, enemy in reach do
		local attack = this:makeAtk(PUNCH, enemy, hurtbox.CFrame.LookVector)
		this:executeAttack(attack)
		-- blocked, parried, dodged or reflected is not a catch
		if not attack:isHit() or attack.enemyEntity ~= enemy or enemy.HRootPart == nil then continue end

		release = pinTo(enemy.HRootPart, function() return at end, FREEZE)
		-- TrueStun, not :Stun, or hyper armour walks out of the hold
		if enemy.TrueStun then enemy:TrueStun(this:scaledTime(RELEASE - HIT) + 0.2) end
		fireVFX("pauseF", char, enemy.HRootPart.Parent)
		break
	end

	-- the hold is the clip's freeze frame: committed, so atkWait
	this:atkWait(RELEASE - HIT)
	if release then release() end

	-- stunned out of the hold (parried, hit): no quake. A feint here is a release, it still goes
	if this:channelBreak(true) == "stun" then
		bail()
		return
	end

	fireVFX("quake", 3, char)
	local forward = hurtbox.CFrame.LookVector
	local _, hits = this:hitbox(CFrame.new(0, 0, -LANE.Z / 2), LANE)
	for _, enemy in hits do
		local attack = this:makeAtk(QUAKE, enemy, forward)
		attack.knockback = this:knockback(forward * 50 + Vector3.new(0, 10, 0), 0.25, false, -1)
		this:executeAttack(attack)
	end

	this:endLag(TRACK_END - RELEASE)
	humObj.walkSpeed:RemoveMod(cooldownID)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
