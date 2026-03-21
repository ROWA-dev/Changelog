--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
}

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	humObj.parryWindow.Value += 0.04
	self:addConnection(
		humObj.beforeAttacked:Connect(function(atk)
			local plrObj = humObj.plrObj
			if plrObj == nil then return end

			local stepper = game:GetService("RunService").Heartbeat
			local endt = tick() + 0.04 -- compensation for his reaction time
			while humObj and humObj.isParry and tick() < endt do -- PING COMPENSATION
				if humObj:isParry(atk) or humObj:isDodge(atk) then
					return
				end
				stepper:Wait()
			end
		end),
		"nickCompensator"
	)
	
	return self
end

function module.destroy(self:myself)
	local humObj = self._humObj
	self:remConnection("nickCompensator")
	humObj.parryWindow.Value -= 0.04
	baseClass.destroy(self)
end

return table.freeze(module)
