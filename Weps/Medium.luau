--!strict
local baseWep = require(script.Parent.WepBase)

export type myself = baseWep.myself & {
	m1last: number,
	m1cycle: number,
	lastAttacked: number,
}

local module = {
	Name = "mediumwep",
	--postureGain = 4
}
module.__tostring = baseWep.__tostring
module.__index = module
setmetatable(module, { __index = baseWep })

function module.new(): myself&any
	local abstract = baseWep.new() :: baseWep.myself
	local self = setmetatable(abstract, module) :: myself&any
	self.m1cycle = 0
	self.m1last = 0
	self.lastAttacked = 0
	return self
end

function module.destroy(self:myself)
	self:unequip()
	baseWep.destroy(self)
end

---

function module.onParried(self:myself, atkType:baseWep.atkType)
	self.m1last = tick() + 0.05 -- cant m1 instantly right after
end

return table.freeze(module)
