--!strict
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
	Name = "fist",
	--- must be a TABLE: nil would inherit Light's {light=2}.
	req = {},
}
module.__tostring = baseWep.__tostring
module.__index = module
setmetatable(module, { __index = baseWep })

function module.new(): myself&any
	local abstract = baseWep.new() :: baseWep.myself
	local self = setmetatable(abstract, module) :: myself&any
	return self
end

function module.destroy(self:myself)
	self:unequip()
	baseWep.destroy(self)
end

--methods
--- wield
function module.wield(self:myself&any)
	-- equip stuff here
	local humobj = self._humObj
	humobj.cooldowns:setCooldown("heavy", 6)
	baseWep.wield(self)
end

--- attack
module.attack = require(script.attack)

return table.freeze(module)
