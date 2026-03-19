--!strict
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
	Name = "hands",
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

function module.destroy(self:myself)
	self:unequip()
	baseWep.destroy(self)
end

--methods
--- equip
function module.equip(self:myself&any, humobj)
	-- equip stuff here
	humobj.cooldowns:setCooldown("heavy", 6)
	baseWep.equip(self, humobj)
end


--- unequip
function module:unequip()
	-- uequip stuff here
	baseWep.unequip(self)
end

--- attack
module.attack = require(script.attack)

return table.freeze(module)
