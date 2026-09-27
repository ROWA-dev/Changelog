--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
}

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any

	humObj.parryWindow.Value += 0.04
	self:addConnection(
		humObj.beforeAttacked:Connect(function(atk)
			local plrObj = humObj.plrObj
			if plrObj == nil then return end

			local stepper = game:GetService("RunService").Heartbeat
			local endt = tick() + 0.04 -- compensation for his reaction time
			while humObj and humObj.isParry and tick() < endt do -- PING COMPENSATION
				if humObj:isParry(atk) or humObj:isDodge(atk) or humObj:inTrueStun() then
					return
				end
				stepper:Wait()
			end
		end)
	)
	
	return self
end

function module.destroy(self:myself)
	self._humObj.parryWindow.Value -= 0.04
	baseClass.destroy(self)
end

return table.freeze(module)
