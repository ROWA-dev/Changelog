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
	
	if humObj.plrObj == nil then
		error(tostring(humObj).." does not have a player to measure...")
	end
	
	local plrData = humObj.plrObj.Data
	if plrData.wins > 30 then
		error("plr is already experienced")
	end
	
	local scale = 0.04 * (1 - (plrData.wins / 30))
	humObj.parryWindow.Value += scale--0.04
	
	if plrData.wins < 2 then
		self:addConnection(
			humObj.beforeAttacked:Connect(function(atk)
				local plrObj = humObj.plrObj
				if plrObj == nil then return end

				local stepper = game:GetService("RunService").Heartbeat
				local endt = tick() + 0.04 -- compensation for beginners reaction time
				while humObj and humObj.isParry and tick() < endt do -- PING COMPENSATION
					if humObj:isParry(atk) or humObj:isDodge(atk) then
						return
					end
					stepper:Wait()
				end
			end),
			"heavenlyEqualizer"
		)
	end
	return self
end

function module.destroy(self:myself)
	--local humObj = self._humObj
	--humObj.parryWindow.Value -= 0.04
	baseClass.destroy(self)
end

return table.freeze(module)
