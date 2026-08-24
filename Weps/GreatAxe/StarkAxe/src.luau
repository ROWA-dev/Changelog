--!strict
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
	postureGain = 4,
	Name = "Stark Axe",
}
module.__tostring = baseWep.__tostring
module.__index = module
setmetatable(module, { __index = baseWep })

function module.new(): myself&any
	local abstract = baseWep.new() :: baseWep.myself
	local self = setmetatable(abstract, module) :: myself&any
	local model = script.Model:Clone()
	self._model = model
	return self
end

function module.destroy(self:myself)
	self:unequip()
	baseWep.destroy(self)
end

--methods
--- wield
function module.wield(self:myself&any)
	local humobj = self._humObj
	humobj.cooldowns:setCooldown("heavy", 6)
	
	local char:any = humobj.Hum.Parent
	local model = self._model --local model = script.Model--:Clone()
	
	model.strap.Enabled = false
	model.Motor6D.Enabled = true
	
	model.Motor6D.Part0 = char["Right Arm"]
	model.Motor6D.Part1 = model.Hold
	model.Parent = char
	
	self._model = model
	self._trail = model:WaitForChild("Trail1")
	baseWep.wield(self)
end

--- unwield
function module:unwield()
	if self.lastAnim then
		self.lastAnim:Stop()
	end
	
	local humobj:any = self._humObj
	if humobj and humobj.Hum then
		local char:Model = humobj.Hum.Parent::any
		local torso = char:FindFirstChild("Torso")
		local model = self._model
		
		model.Motor6D.Enabled = false
		model.strap.Enabled = true
		model.strap.Part1 = model.Hold
		model.strap.Part0 = torso
		model.Parent = char
	end

	baseWep.unwield(self)
end


--- attack
module.attack = require(script.attack)



return table.freeze(module)
