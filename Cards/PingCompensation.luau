--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
}

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	
	if humObj.plrObj == nil then
		error("ping compensation failed because no plrObj is linked to this HumObj")
	end
	
	self:addConnection(
		humObj.beforeAttacked:Connect(function(atk)
			local plrObj = humObj.plrObj
			if plrObj == nil then return end
		
			local stepper = game:GetService("RunService").Heartbeat
			local endt = tick() + plrObj.ping.Value*0.9 -- weaken ping comp

			while humObj and humObj.isParry and tick() < endt do -- PING COMPENSATION
				if humObj:isParry(atk)
					or humObj:isDodge(atk)
					or humObj.attacking.Value == true
					or humObj:inTrueStun()
				then
					return
				end
				stepper:Wait()
			end
		end)
	)
	
	
	return self
end

return table.freeze(module)
