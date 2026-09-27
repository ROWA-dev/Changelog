--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
}

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	
	self:addConnection(humObj.onAttacked:Connect(function(attack)
		if attack:isParried() then self:timedMod(humObj.walkSpeed, 5, 1) end
	end))
	return self
end

return table.freeze(module)
