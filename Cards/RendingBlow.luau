--!strict
-- breaking someone's guard leaves them bleeding

local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local DURATION, DAMAGE = 10, 1

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any

	-- MY outgoing attack, so it pays the breaker; `guardBroke` is set by resolveBlock on the breaking blow.
	self:addConnection(humObj.onAttack:Connect(function(attack)
		if not attack.guardBroke then return end
		local victim = attack.enemyEntity
		if victim == nil then return end
		-- deferred past this hit's other cards, so Bloodletting/DeepWound only act on a bleed that was already there
		task.defer(victim.statusEffects.apply, victim.statusEffects, humObj.statusEffects.Bleed, DURATION, DAMAGE)
	end))

	return self
end

return table.freeze(module)
