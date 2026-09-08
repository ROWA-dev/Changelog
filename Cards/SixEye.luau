--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
	_modKey: string,
	_healthApplied: boolean,
	_low: boolean?,
}

local MAX_HEALTH = 10
local HEAL_BONUS = 0.2 -- 1.2x upright regen
local RCT_BONUS  = 3   -- 4x under LOW_HP, rowa1's "REVERSE CURSED TECHNIQUE"
local LOW_HP     = 10 -- live band is KNOCK_HP(5) < hp <= 10: below that you are down and the getup clock owns the rate

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

-- written only when the threshold FLIPS: HealthChanged fires on every hit and every regen tick.
local function refresh(self:myself, hum:Humanoid)
	local low = hum.Health <= LOW_HP
	if low == self._low then return end
	self._low = low
	self._humObj.healthHeal:SetMod(self._modKey, if low then RCT_BONUS else HEAL_BONUS)
end

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	self._modKey = "sixeye:" .. tostring(self.randID)
	self._healthApplied = false

	local hum:Humanoid? = humObj.Hum
	if hum and hum.Parent then
		hum.MaxHealth += MAX_HEALTH
		hum.Health = math.min(hum.Health + MAX_HEALTH, hum.MaxHealth)
		self._healthApplied = true

		refresh(self, hum)
		self:addConnection(hum.HealthChanged:Connect(function()
			refresh(self, hum :: Humanoid)
		end), "sixeye")
	end

	return self
end

function module.destroy(self:myself)
	self:remConnection("sixeye")
	local humObj = self._humObj
	if humObj then
		humObj.healthHeal:RemoveMod(self._modKey)

		local hum:Humanoid? = humObj.Hum
		if self._healthApplied and hum and hum.Parent then
			hum.MaxHealth = math.max(1, hum.MaxHealth - MAX_HEALTH)
			hum.Health = math.min(hum.Health, hum.MaxHealth)
		end
	end
	baseClass.destroy(self)
end

return table.freeze(module)
