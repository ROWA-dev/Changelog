--!strict
-- reduces ur max posture by 10
-- but every successful hit also drains the enemys posture by a percentage of the damage dealt.

local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
	_modKey: string,
}

local MAX_POSTURE_CUT = 10
-- share of the damage dealt that ALSO comes off the victim's guard.
local POSTURE_PER_DMG = 0.2 -- 20%... half was too good?

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	self._modKey = "frenzy:" .. tostring(self.randID)

	humObj.maxPosture:SetMod(self._modKey, -MAX_POSTURE_CUT)
	humObj.posture.Value = math.min(humObj.posture.Value, humObj.maxPosture.Value)

	-- a landed hit never touched posture before this card: the block branch was the only
	-- drain, so this is pressure on someone who is not even blocking.
	self:addConnection(humObj.onAttack:Connect(function(attack)
		if not attack:isHit() then return end
		local victim = attack.enemyEntity
		if victim == nil then return end
		-- Combatant guarantees an inert `posture`, so a non-posture defender is safe.
		victim.posture.Value = math.max(0,
			victim.posture.Value - attack:CalculateDamage() * POSTURE_PER_DMG)
	end), "frenzy")

	return self
end

function module.destroy(self:myself)
	self:remConnection("frenzy")
	local humObj = self._humObj
	if humObj then
		humObj.maxPosture:RemoveMod(self._modKey)
	end
	baseClass.destroy(self)
end

return table.freeze(module)
