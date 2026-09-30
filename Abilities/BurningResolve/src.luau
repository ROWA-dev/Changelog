--!strict
-- toggle: cast to set yourself ablaze (StatusEffects/BurningResolve), cast again to put it out. Free on purpose: health is the price.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "BurningResolve",
	manaUse = 0, -- a mana gate would stop a broke player putting themselves out
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

local BURN_DMG = 0.5 -- per 0.4s, halved while you cannot dash
-- LIT_CD also stops UseAbility's retry loop putting it straight back out
local LIT_CD, OUT_CD = 2, 4

local function useFunc(this:myself)
	local cooldownID = "burningResolve"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj = this._humObj
	local effects = humObj.statusEffects
	if effects:remove(effects.BurningResolve) then
		this:triggerCD(cooldownID, OUT_CD)
		return
	end

	local anim = this:PlayAnim(script.Anim, 0, 1, 1)
	if this:feintWait(0.4) then
		if anim then anim:Stop(0.1) end
		return
	end

	this:triggerCD(cooldownID, LIT_CD)
	local root = humObj.HRootPart
	fireVFX("emperorFlame", root.Position, Vector3.new(0,1,0), humObj.Model)
	effects:apply(effects.BurningResolve, math.huge, BURN_DMG, humObj)
	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
