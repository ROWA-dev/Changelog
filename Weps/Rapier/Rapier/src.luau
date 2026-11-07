--!strict
local baseWep = require(script.Parent)

export type myself = baseWep.myself

local module = {
	Name = "rapier",
}
module.__tostring = baseWep.__tostring
module.__index = module
setmetatable(module, { __index = baseWep })

function module.new(): myself&any
	return setmetatable(baseWep.new(script.Model), module) :: any
end

-- WepBase.wield from HERE, so preloadAnims preloads this weapon and not the whole family (GOTCHAS)
function module.wield(self:myself&any)
	baseWep.weldHand(self)
	baseWep.wield(self)
end

module.attack = require(script.attack)

return table.freeze(module)
