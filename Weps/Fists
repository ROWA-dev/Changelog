--!strict
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
	Name = "fists",
	WepType = "Fist",
	blockAnim = script:WaitForChild("block"),
	parryAnim = script:WaitForChild("parry"),
	idleAnim = script:WaitForChild("idle")
}
module.__tostring = baseWep.__tostring
module.__index = module
setmetatable(module, { __index = baseWep })

function module.new(): myself&any
	local abstract = baseWep.new() :: baseWep.myself
	local self = setmetatable(abstract, module) :: myself&any
	-- fist stuff here
	return self
end

return table.freeze(module)
