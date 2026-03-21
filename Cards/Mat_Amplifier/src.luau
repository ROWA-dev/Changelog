--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
}

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	humObj.parryWindow.Value += 0.04	
	return self
end

function module.destroy(self:myself)
	local humObj = self._humObj
	humObj.parryWindow.Value -= 0.04
	baseClass.destroy(self)
end

return table.freeze(module)
