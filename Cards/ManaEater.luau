--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any

	-- non-weapon parries pay what landing that hit would have (HumObj onAttack_mana: dmg/4).
	self:addConnection(humObj.onAttacked:Connect(function(attack)
		if not attack:isParried() or attack:isWep() then return end
		humObj:setMana(humObj:manaNow() + attack:CalculateDamage() * 0.25)
	end))

	return self
end

return table.freeze(module)
