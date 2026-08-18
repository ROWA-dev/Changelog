--!strict
--[[ Tendrils - rowa1 Items/Ability/Tendrils. Notes: README.md/PORT_Tendrils.

	Blood tendrils reach out at range, GRAB a target, hoist them 10 studs and
	then break them. A ranged grab, not a projectile (PLAN_PROJECTILE 2F).

	THE PORT DOC'S OPEN QUESTION IS RESOLVED: `blodbreak` DOES exist in DMGS
	(Heavy, magic+blood, 50 dmg, stun 0.7, posMult 4). So this is genuinely a
	two-hit move -- a 2-second-stun catch followed by a 50-damage finisher --
	not grab-plus-visual as the doc guessed. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Tendrils"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils  = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag   = dmgUtils.dmgFlags
local Targeting = require(game.ServerStorage.ROWA.Modules.Targeting)
local fireVFX   = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx    = require(game.ServerStorage.ROWA.Modules.hitSfx)

--[[ !! `blood` MOVED BIT POSITION between the games -- rowa1 1024, rowa2
	4096 (README S4.1). Written by NAME, as everything must be; a copied
	literal here would silently become `wind`. ]]
local BLOOD_MAGIC = bit32.bor(dmgFlag.magic, dmgFlag.blood)

--[[ rowa1 "blodgrab": Heavy, magic+blood, 10 dmg, truestun 1.4 / stun 2.0,
	posMult 5.
	stun 2.0 is joint-longest in the whole table. Halved: the follow-up is
	guaranteed by the hoist anyway, so the extra second only removed the
	victim's ability to react to the FINISHER. ]]
local BLODGRAB = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = BLOOD_MAGIC,
	dmg      = 10,
	stun     = 1,
	posMult  = 5,
	--[[ a ranged catch with no travel time needs an out, and rowa2 has the
		knob rowa1 did not. ]]
	dodgeH   = 0.15,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "grab")
	end,
}

--- rowa1 "blodbreak": Heavy, magic+blood, 50 dmg, truestun 0.1 / stun 0.7.
local BLODBREAK = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = BLOOD_MAGIC,
	dmg      = 32,
	stun     = 0.7,
	posMult  = 4,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "GoreyHit")
	end,
}

local CAST_TIME   = 0.6
local REACH_TIME  = 0.3
local HOLD_TIME   = 1
local RANGE       = 60
local SLOW_KEY    = "tendrils"

local function useFunc(this:myself)
	local cooldownID = "tendrils"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local root = humObj.HRootPart
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	--[[ the correlation token. Two casters at once would otherwise find each
		other's sigil; rowa1 got this right and it is worth copying for any
		staged effect. ]]
	local vfxID = math.random(1, 65536)
	fireVFX("bloodcast", 1, root, vfxID)

	if this:feintWait(CAST_TIME) then
		if anim then anim:Stop() end
		fireVFX("bloodcast", 2, root, vfxID)
		return
	end

	fireVFX("bloodcast", 2, root, vfxID)

	local target = Targeting.nearestInDirection(
		hurtbox.Position, hurtbox.CFrame.LookVector, humObj, RANGE)

	--[[ rowa1 spent NO cooldown on a whiff -- it returns before `cd = tick()`.
		Kept, but a token cost so it cannot be spammed as a free scan. ]]
	if target == nil or target.HRootPart == nil then
		if anim then anim:Stop() end
		this:triggerCD(cooldownID, 1, true)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 16, true)

	local eroot = target.HRootPart
	local movePos = eroot.Position + Vector3.new(0, 10, 0)

	fireVFX("bldtendrils", 1, eroot, movePos)
	fireVFX("bloodcast", 3, root, vfxID)

	if this:feintWait(REACH_TIME) then
		if anim then anim:Stop() end
		fireVFX("bldtendrils", 3, eroot, false)
		return
	end

	local grab = this:makeAtk(BLODGRAB, target, hurtbox.CFrame.LookVector)
	this:executeAttack(grab)

	if not grab:isHit() then
		fireVFX("bldtendrils", 3, eroot, false)
		this:endLag(0.2)
		return
	end

	if anim then anim:Stop(0.4) end
	this:PlayAnim(script.anim2, 0.4, 1, 1)

	--[[ rowa1 froze the CASTER's input and ANCHORED the victim's root for the
		hoist. walkSpeed is the rowa2 equivalent for the caster; the victim is
		held by the client-side bldtendrils tween, which anchors and releases
		its own limbs. Both halves must come off on EVERY exit -- a stranded
		anchor is a permanently frozen player. ]]
	humObj.walkSpeed:SetMod(SLOW_KEY, -13)
	fireVFX("bldtendrils", 2, eroot, movePos)

	local cancelled = this:feintWait(HOLD_TIME)
	humObj.walkSpeed:RemoveMod(SLOW_KEY)

	if cancelled or target.isActive ~= true then
		fireVFX("bldtendrils", 3, eroot, false)
		return
	end

	local finisher = this:makeAtk(BLODBREAK, target, hurtbox.CFrame.LookVector)
	finisher.knockback = this:knockback(
		finisher.atkDir * 6 + Vector3.new(0, 8, 0), 0.2, false, -1)
	this:executeAttack(finisher)

	fireVFX("bldtendrils", 3, eroot, finisher:isHit())

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
