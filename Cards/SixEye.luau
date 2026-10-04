--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
	_low: boolean?,
}

local MAX_HEALTH = 10
local HEAL_BONUS = 0.2 -- 1.2x upright regen
local RCT_BONUS  = 2   -- 3x under LOW_HP, rowa1's "REVERSE CURSED TECHNIQUE"
local LOW_HP     = 10 -- live band is KNOCK_HP(5) < hp <= 10: below that you are down and GETUP owns the rate
local GETUP      = 3   -- knockdowns 3x shorter
local MANA_COST  = 0.75 -- every ability

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

-- written only when the threshold FLIPS: HealthChanged fires on every hit and every regen tick.
local function refresh(self:myself, hum:Humanoid)
	local low = hum.Health <= LOW_HP
	if low == self._low then return end
	self._low = low
	self:setMod(self._humObj.healthHeal, if low then RCT_BONUS else HEAL_BONUS)
end

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	humObj.getupMult = GETUP
	humObj.manaCostMult = MANA_COST

	self:addMaxHealth(MAX_HEALTH)
	local hum:Humanoid? = humObj.Hum
	if hum and hum.Parent then
		refresh(self, hum)
		self:addConnection(hum.HealthChanged:Connect(function()
			refresh(self, hum :: Humanoid)
		end))
	end

	return self
end

function module.destroy(self:myself)
	local humObj = self._humObj
	humObj.getupMult = nil
	humObj.manaCostMult = nil
	baseClass.destroy(self)
end

return table.freeze(module)
