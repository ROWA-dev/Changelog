--!strict
-- cuts max posture by MAX_POSTURE_CUT, but every hit also drains the victim's posture by POSTURE_PER_DMG of the damage.

-- TODO give this card a visual.. maybe ur posture bar becomes orange instead of red?
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
}

local MAX_POSTURE_CUT = 20
-- share of the damage dealt that ALSO comes off the victim's guard.
local POSTURE_PER_DMG = 0.5

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	self:setMod(humObj.maxPosture, -MAX_POSTURE_CUT)
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
	end))

	return self
end

return table.freeze(module)
