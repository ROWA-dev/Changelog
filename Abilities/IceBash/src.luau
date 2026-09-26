--!strict
-- IceBash - overhead ice block smash: longest reach of the simple set, ragdolls, feeds the Freeze meter.
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
local layIce  = require(game.ServerStorage.ROWA.Modules.layIce)

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

-- icebsh stages
local FX_CHARGE, FX_FIZZLE, FX_CONNECT, FX_WHIFF = 1, 2, 3, 4

local WINDUP = 0.52
local ANIM_HIT = 0.667 -- anim time the fist lands; the track is sped up to hit on WINDUP
local REACH = 7 -- where the block lands
local ICE_SIZE = 16
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.FilterDescendantsInstances = { workspace:WaitForChild("Effects"), workspace:WaitForChild("Entities") } -- permanent folders, set once (GOTCHAS)

local function useFunc(this:myself)
	local cooldownID = "iceBash"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim    = this:PlayAnim(script.Anim, 0, 1, ANIM_HIT / WINDUP)

	fireVFX("icebsh", FX_CHARGE, humObj.Hum, this:scaledTime(WINDUP))

	if this:feintWait(WINDUP) then
		if anim then anim:Stop() end
		fireVFX("icebsh", FX_FIZZLE, humObj.Hum)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 8, true)

	-- range, not a deeper box: it only grows the facing axis
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
			-- flat 0.8s: (60, false) would never end
			attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * 8)
			-- 3 of 10: the setup, never a freeze alone
			attack.enemyEntity.statusEffects:apply(statusEffects.Freeze, 4, 3)
		end
	end

	fireVFX("icebsh", hitAny and FX_CONNECT or FX_WHIFF, humObj.Hum)

	-- ices the ground hit or miss
	local ground = workspace:Raycast(hurtbox.Position + hurtbox.CFrame.LookVector * REACH + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), groundParams)
	if ground then
		layIce(ground.Position, ground.Normal, ICE_SIZE, ground.Instance :: BasePart)
	end

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
