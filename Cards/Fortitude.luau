--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local MAX_HEALTH = 40

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	self:addMaxHealth(MAX_HEALTH)
	return self
end

return table.freeze(module)
