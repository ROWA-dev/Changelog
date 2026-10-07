--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any

	-- BLOCKED only: a parry is its own branch, and a guard that BROKE resolves as a
	-- hit, so the shot that cracks you through pays nothing.
	self:addConnection(humObj.onAttacked:Connect(function(attack)
		if not attack:isBlocked() then return end
		-- setMana re-anchors the curve and clamps to maxMana; nothing ticks.
		humObj:setMana(
			humObj:manaNow() + attack:CalculatePostureDmg() * 0.75
		)
	end))

	return self
end

return table.freeze(module)
