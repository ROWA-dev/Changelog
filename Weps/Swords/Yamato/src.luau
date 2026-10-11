--!strict
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
}

local module = {
	Name = "yamato",
	idleAnim = script:WaitForChild("idle"),
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

local IDLE = 1 -- seconds after the last hit before the blade goes back

-- one pending thread per weapon, re-armed until idle
local function autoSheathe(self:myself&any)
	local humObj = self._humObj
	if humObj == nil or humObj.wielding_weapon ~= self or self._model.Sheathe.Handle.Enabled then
		self._sheathing = nil
		return
	end
	local left = humObj.attackAt + IDLE - tick()
	if left > 0 or humObj.attacking.Value then
		task.delay(math.max(left, 0.1), autoSheathe, self)
		return
	end
	self._sheathing = nil
	humObj:PlayTrack(humObj:LoadAnimation(script.sheathe), 0.1, 1, 1/self.atkRate.Value)
	self:atkWait(0.2)
	if humObj.attacking.Value == false and humObj.wielding_weapon == self then
		self:sheathed(true)
	end
end

function module.sheathed(self:myself&any, on:boolean)
	self._model.Sheathe.Handle.Enabled = on
	if not on and not self._sheathing then
		self._sheathing = true
		task.delay(IDLE, autoSheathe, self)
	end
end

local function seat(self:myself&any, char:any, inHand:boolean)
	local model = self._model
	local hip = model.Sheathe.LeftArm
	model.mtr.Part0 = char:FindFirstChild("Right Arm")
	model.mtr.Enabled = inHand
	hip.Part0 = char:FindFirstChild("Left Arm")
	hip.Enabled = not self._holdOnly -- held out, the sheath rides in the hand
	module.sheathed(self, true)
	model.Parent = char
end

function module.wield(self:myself&any)
	seat(self, self._humObj.Hum.Parent, true)
	baseWep.wield(self)
end

function module.unwield(self:myself&any)
	local humObj:any = self._humObj
	if humObj and humObj.Hum then
		seat(self, humObj.Hum.Parent, false)
	end
	baseWep.unwield(self)
end

-- no shared downslam, the air ender is the spin in attack/m1
function module.flourishHook() end

module.attack = require(script.attack)

return table.freeze(module)
