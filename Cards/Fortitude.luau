--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
	_healthApplied: boolean,
}

local MAX_HEALTH = 40

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	self._healthApplied = false

	local hum:Humanoid? = humObj.Hum
	if hum and hum.Parent then
		hum.MaxHealth += MAX_HEALTH
		hum.Health = math.min(hum.Health + MAX_HEALTH, hum.MaxHealth)
		self._healthApplied = true
	end

	return self
end

function module.destroy(self:myself)
	local humObj = self._humObj
	local hum:Humanoid? = humObj and humObj.Hum
	if self._healthApplied and hum and hum.Parent then
		hum.MaxHealth = math.max(1, hum.MaxHealth - MAX_HEALTH)
		hum.Health = math.min(hum.Health, hum.MaxHealth)
	end
	baseClass.destroy(self)
end

return table.freeze(module)
