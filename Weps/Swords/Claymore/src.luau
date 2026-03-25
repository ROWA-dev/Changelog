--!strict
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
	Name = "claymore",
	idleAnim = script:WaitForChild("idle")
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
	if self._model then
		self._model:Destroy()
	end
	baseWep.destroy(self)
end

--methods

--- wield
function module.wield(self:myself&any)
	-- wield stuff here
	local humobj = self._humObj
	local char:any = humobj.Hum.Parent
	local model = self._model
	model.mtr.Enabled = true
	model.strap.Enabled = false
	model.mtr.Part0 = char["Right Arm"]
	model.mtr.Part1 = model.Hold
	model.Parent = char

	humobj.cooldowns:setCooldown("heavy", 10)
	baseWep.wield(self)
end

--- uunwield
function module.unwield(self:myself)
	-- unwield stuff here
	if self.lastAnim then
		self.lastAnim:Stop()
	end
	
	local humobj:any = self._humObj
	if humobj and humobj.Hum then
		local char:Model = humobj.Hum.Parent::any
		local torso = char:FindFirstChild("Torso")
		local model = self._model
		model.mtr.Enabled = false
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
