--!strict
local baseWep = require(script.Parent.WepBase)

export type myself = baseWep.myself & {
	m1last: number,
	m1cycle: number,
	lastAttacked: number,
}

local module = {
	Name = "heavywep",
	postureGain = 16
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


function module.onParried(self:myself, atkType:baseWep.atkType)
	--self.m1last = tick() -- can :) m1 instantly right after
end

function module.onBlocked(self:myself, atkType:baseWep.atkType)
	local ehumObj = atkType.enemyEntity
	if ehumObj.Stun then
		ehumObj:Stun(0.1)
		ehumObj.canAtkThreshold = math.max(ehumObj.canAtkThreshold, tick()+0.1)
	end
end

return table.freeze(module)
