--!strict
-- fire hits +20%, your burns 1.5x, and `fireHue` turns all your fire azure (Modules/fireTint reads it)
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local DmgUtils = require(game.ServerScriptService.Utils.DmgUtils)

export type myself = baseClass.myself

local FIRE_BONUS, BURN_MULT, HUE = 0.2, 1.5, 0.6
local FIRE = DmgUtils.dmgFlags.fire

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any

	self:addConnection(humObj.beforeAttack:Connect(function(attack)
		if attack:hasDmgFlag(FIRE) then attack.dmgMult += FIRE_BONUS end
	end))
	humObj.statusEffects.burnMult = BURN_MULT
	humObj.Model:SetAttribute("fireHue", HUE)

	return self
end

function module.destroy(self:myself)
	local humObj = self._humObj
	if humObj and humObj.statusEffects then humObj.statusEffects.burnMult = nil end
	if humObj and humObj.Model then humObj.Model:SetAttribute("fireHue", nil) end
	baseClass.destroy(self)
end

return table.freeze(module)
