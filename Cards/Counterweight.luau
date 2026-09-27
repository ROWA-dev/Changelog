--!strict
-- parrying restores 25% more posture

local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

--- multiplies the parrier's half of the posture trade, read live in
--- HumObj/resolution/resolveParry. The math stays THERE, this only sets a knob.
local MULT = 1.25

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any

	-- a plain lazy field, not an AdditiveValue: one card owns it, nothing else
	-- writes it, and nil is the default for every entity that lacks the card.
	humObj.parryPostureMult = MULT

	return self
end

function module.destroy(self:myself)
	local humObj = self._humObj
	if humObj then
		humObj.parryPostureMult = nil
	end
	baseClass.destroy(self)
end

return table.freeze(module)
