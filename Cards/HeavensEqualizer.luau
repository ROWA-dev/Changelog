--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
	_scale: number,
}

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	
	if humObj.plrObj == nil then
		error(tostring(humObj).." does not have a player to measure...")
	end
	
	local plrData = humObj.plrObj.Data
	if plrData.wins > 30 then
		error("plr is already experienced")
	end
	
	local scale = 0.04 * (1 - (plrData.wins / 30))
	humObj.parryWindow.Value += scale
	self._scale = scale
	
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
			end)
		)
	end
	return self
end

-- parryWindow is a plain value, not an AdditiveValue, so the bump is undone by hand
function module.destroy(self:myself)
	self._humObj.parryWindow.Value -= self._scale
	baseClass.destroy(self)
end

return table.freeze(module)
