--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

-- share of the posture damage the guard ate, returned as mana. SCALED, not flat:
-- a chip m1 is a trickle and a heavy is most of a cast, so the card rewards
-- blocking the thing you were afraid of rather than blocking constantly.
local MANA_PER_POSTURE = 0.25

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	-- BLOCKED only: a parry is its own branch, and a guard that BROKE resolves as a
	-- hit, so the shot that cracks you through pays nothing.
	self:addConnection(humObj.onAttacked:Connect(function(attack)
		if not attack:isBlocked() then return end
		-- setMana re-anchors the curve and clamps to maxMana; nothing ticks.
		humObj:setMana(humObj:manaNow() + attack:CalculatePostureDmg() * MANA_PER_POSTURE)
	end), "manaPores")

	return self
end

function module.destroy(self:myself)
	self:remConnection("manaPores")
	baseClass.destroy(self)
end

return table.freeze(module)
