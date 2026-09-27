--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local SPEED, DURATION = 5, 10

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any

	-- DECIDE: only beforeAttacked still sees the out-of-combat state, but it cannot
	-- know the blow lands, so the answer rides on the attack (EarthArmour's shape).
	self:addConnection(humObj.beforeAttacked:Connect(function(attack)
		attack._adrenalineOpener = not humObj:inCombat()
	end))

	-- COMMIT: only a HIT puts you in combat, so a parried or dodged opener pays nothing.
	self:addConnection(humObj.onAttacked:Connect(function(attack)
		if not (attack._adrenalineOpener and attack:isHit()) then return end
		self:timedMod(humObj.walkSpeed, SPEED, DURATION)
	end))

	return self
end

return table.freeze(module)
