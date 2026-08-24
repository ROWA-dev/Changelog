--!strict
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
	Name = "dagger",
}
module.__tostring = baseWep.__tostring
module.__index = module
setmetatable(module, { __index = baseWep })

function module.new(): myself&any
	local abstract = baseWep.new() :: baseWep.myself
	local self = setmetatable(abstract, module) :: myself&any
	local model = script.Model:Clone()
	self._model = model
	self._trail = model:WaitForChild("Trail1")
	return self
end

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
	local char:any = humobj.Hum.Parent
	local model = self._model
	model.mtr.Part0 = char["Right Arm"]
	model.mtr.Part1 = model.Hold
	model.Parent = char

	humobj.cooldowns:setCooldown("heavy", 4)
	baseWep.wield(self)
end

--- unwield
function module:unwield()
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
