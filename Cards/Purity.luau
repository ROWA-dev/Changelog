--!strict
-- halves the duration and strength of harmful status effects put on you. StatusEffects.apply does the scaling
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local MULT = 0.5

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	humObj.statusEffects.debuffMult = MULT
	return self
end

function module.destroy(self:myself)
	local humObj = self._humObj
	if humObj and humObj.statusEffects then humObj.statusEffects.debuffMult = nil end
	baseClass.destroy(self)
end

return table.freeze(module)
