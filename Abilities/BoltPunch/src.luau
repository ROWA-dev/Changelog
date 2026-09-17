--!strict
-- A lunging lightning straight. The dash fires BEFORE the windup and runs
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "BoltPunch"
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
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx  = require(game.ServerStorage.ROWA.Modules.hitSfx)

local BOLT = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.blunt, dmgFlag.magic),
	dmg      = 20,
	stun     = 1,
	posMult  = 2,
	onHit    = function(attack, source: any)
		local eroot = attack.enemyEntity.HRootPart
		hitSfx(eroot, "LightningClash")
		fireVFX("bolthit", eroot, source and source.HRootPart)
	end,
}

local FX_CHARGE, FX_FIZZLE = 1, 2

-- active frames: the straight travels, so one snapshot lands wherever the dash
-- happened to leave you. `lead` is the other half if it still reads short.
local LUNGE = table.freeze({ window = 0.15 })

local function useFunc(this:myself)
	local cooldownID = "boltPunch"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim    = this:PlayAnim(script.Anim, 0, 1, 0.9)

	fireVFX("boltp", FX_CHARGE, humObj.Hum)

	local dash = this:bodyForce(Vector3.new(0, 0, -6), 0.4, true)

	if this:feintWait(0.5) then
		if anim then anim:Stop() end
		if dash then dash:destroy() end
		fireVFX("boltp", FX_FIZZLE, humObj.Hum)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 10, true)

	local _, hits = this:sweep(CFrame.new(0, 0, -4), Vector3.new(6, 6, 6), LUNGE)

	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(BOLT, enemy, hurtbox.CFrame.LookVector)
		--[[ NO KNOCKBACK: the dash already closed the gap and a launch would
			undo it. ]]
		this:executeAttack(attack)
	end

	this:endLag(0.15)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)