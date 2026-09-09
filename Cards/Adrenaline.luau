--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local SPEED, DURATION = 5, 10
local MOD = "adrenaline"

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	-- DECIDE: only beforeAttacked still sees the out-of-combat state, but it cannot
	-- know the blow lands, so the answer rides on the attack (EarthArmour's shape).
	self:addConnection(humObj.beforeAttacked:Connect(function(attack)
		attack._adrenalineOpener = not humObj:inCombat()
	end), "adrenalineDecide")

	-- COMMIT: only a HIT puts you in combat, so a parried or dodged opener pays nothing.
	self:addConnection(humObj.onAttacked:Connect(function(attack)
		if not (attack._adrenalineOpener and attack:isHit()) then return end
		humObj.walkSpeed:SetMod(MOD, SPEED)
		task.delay(DURATION, function()
			if humObj and humObj.isActive then humObj.walkSpeed:RemoveMod(MOD) end
		end)
	end), "adrenaline")

	return self
end

function module.destroy(self:myself)
	self:remConnection("adrenalineDecide")
	self:remConnection("adrenaline")
	local humObj = self._humObj
	if humObj and humObj.walkSpeed then humObj.walkSpeed:RemoveMod(MOD) end
	baseClass.destroy(self)
end

return table.freeze(module)
