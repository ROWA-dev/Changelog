--!strict
-- MassFreeze - Freeze with a shorter line (6 steps, easier up close), no victim cap, and a crowned spire.
local baseClass = require(script.Parent.Freeze)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "MassFreeze",
	cdId = "massFreeze",
	cd = 16,
	maxVictims = math.huge,
	steps = 6,
	crown = 8,
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

return table.freeze(module)
