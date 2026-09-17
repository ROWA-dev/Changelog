--!strict
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
	arialCD = 2,
	postureGain = 6,
	Name = "Slayer",
}
module.__tostring = baseWep.__tostring
module.__index = module
setmetatable(module, { __index = baseWep })

function module.new(): myself&any
	local abstract = baseWep.new() :: baseWep.myself
	local self = setmetatable(abstract, module) :: myself&any
	self._model = script.Model:Clone()

	self.atkRate:SetMod("slayer", 0.18)
	return self
end

--[[ unequip FIRST -- Heavy.destroy calls it and Greatsword.unequip re-parents
	the model, which throws on an instance we already destroyed. PORTW_00
	trap 1's sibling; see Oblitar for the long version. ]]
function module.destroy(self:myself)
	self:unequip()
	if self._model then
		self._model:Destroy()
	end
	baseWep.destroy(self)
end

--methods

--- wield
function module.wield(self:myself&any)
	local humobj = self._humObj
	humobj.cooldowns:setCooldown("heavy", 10)

	local char:any = humobj.Hum.Parent
	local model = self._model
	model.Motor6D.Part0 = char["Right Arm"]
	model.Motor6D.Part1 = model.Hold
	model.Parent = char

	self._trail = model:WaitForChild("Trail1")
	baseWep.wield(self)
end

--- unwield
function module.unwield(self:myself&any)
	if self.lastAnim then
		self.lastAnim:Stop()
	end

	local model = self._model
	if model then
		model.Parent = script
	end

	baseWep.unwield(self)
end

--- attack
module.attack = require(script.attack)

return table.freeze(module)