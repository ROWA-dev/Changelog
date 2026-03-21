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


	if humObj and humObj.Hum and humObj.Hum.Parent and humObj.Hum.Parent.Name == "Airzy_Az" then
	else
		error(tostring(humObj).." is not airzy, invalid...")
		return self
	end

	humObj.parryWindow.Value -= 0.02
	self:addConnection(
		humObj.beforeAttacked:Connect(function(attack)
			-- take 10% more from all attacks
			attack.dmgMult += 0.10
		end),
		"nerfAir"
	)


	return self
end

function module.destroy(self:myself)
	self._humObj.parryWindow.Value += 0.02
	self:remConnection("nerfAir")
	baseClass.destroy(self)
end

return table.freeze(module)
