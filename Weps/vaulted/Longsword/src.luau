--!strict
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
	Name = "son what is this",
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
	-- wield stuff here
	local humobj = self._humObj
	local char:any = humobj.Hum.Parent
	local model = script.Longsword:Clone()
	model.Joint.Part0 = char["Right Arm"]
	model.Joint.Part1 = model.Handle
	model.Parent = char

	self._model = model

	humobj.cooldowns:setCooldown("heavy", 4)
	baseWep.wield(self)
end

--- unwield
function module.unwield(self:myself)
	print("katana unwield")
	-- unwield stuff here
	if self.lastAnim then
		self.lastAnim:Stop()
	end

	local humObj:any = self._humObj
	if humObj and humObj.chargingAnim then
		humObj.chargingAnim:Stop()
		humObj.chargingAnim = nil
	end

	baseWep.unwield(self)
end



--- attack
module.attack = require(script.attack)



return table.freeze(module)
