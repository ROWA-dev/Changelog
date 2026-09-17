--!strict
-- this needs to get reworked TODO
--[[ IceBash - a committed overhead ice smash. Longest reach of the simple set,
	ragdolls on hit, and feeds the Freeze meter
	(Class/StatusEffects/Freeze) rather than carrying an ice stun of its
	own. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "IceBash"
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
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx  = require(game.ServerStorage.ROWA.Modules.hitSfx)

local ICE3 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.ice, dmgFlag.blunt),
	dmg      = 18,
	stun     = 0.6,
	posMult  = 2,
	--parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "IceSplash2")
	end,
}

--- the "icebsh" quiver module switches on this first argument.
local FX_CHARGE, FX_FIZZLE, FX_CONNECT = 1, 2, 3

local function useFunc(this:myself)
	local cooldownID = "iceBash"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim    = this:PlayAnim(script.Anim, 0, 1, 1)

	fireVFX("icebsh", FX_CHARGE, humObj.Hum)

	if this:feintWait(0.52) then
		if anim then anim:Stop() end
		fireVFX("icebsh", FX_FIZZLE, humObj.Hum)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 8, true)

	--[[ the longest reach in the simple set. Extending `range` rather than
		inflating the box keeps the shape honest: range grows the OBB along the
		facing axis only, an 11-deep box would also
		catch people beside you. ]]
	this.range:SetMod(cooldownID, 1)
	local _, hits = this:hitbox(CFrame.new(0, 0, -6), Vector3.new(6, 6, 7))
	this.range:RemoveMod(cooldownID)

	local hitAny = false
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(ICE3, enemy, hurtbox.CFrame.LookVector)
		attack.knockback = this:knockback(attack.atkDir * 4.8, 0.15, false, -1)

		this:executeAttack(attack)
		if attack:isHit() then
			hitAny = true
			--[[ !! 0.8 AND false, NOT 60. Every `(60, true)` elsewhere is a CAP
				that stopOnGround ends early -- so `(60, false)` means 60s flat
				and victims never get up. ]]
			attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * 8)
			--[[ 3 of a 10 meter. IceBash is the SETUP in the ice kit -- a
				solid chunk off one committed heavy, but never a freeze on its
				own. See StatusEffects/Freeze. ]]
			attack.enemyEntity.statusEffects:apply(statusEffects.Freeze, 4, 3)
		end
	end

	--- `isHit` is narrow on purpose: an ABORTED attack is not a connect, so the
	--- flourish does not fire on one.
	fireVFX("icebsh", hitAny and FX_CONNECT or FX_FIZZLE, humObj.Hum)

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
