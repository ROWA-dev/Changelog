--!strict
-- MassFreeze - Freeze that keeps going: the same first 7 steps, 7 more fanning out and growing to 2x, then a crowned spire.
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
