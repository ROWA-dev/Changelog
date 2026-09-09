--!strict
-- breaking someone's guard leaves them bleeding

local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local DURATION, DAMAGE = 10, 1

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	-- MY outgoing attack- this pays the breaker and not the broken.
	-- `guardBroke` is set in resolveBlock on the blow that broke the guard; the
	self:addConnection(humObj.onAttack:Connect(function(attack)
		if not attack.guardBroke then return end
		local victim = attack.enemyEntity
		if victim == nil then return end
		victim.statusEffects:apply(humObj.statusEffects.Bleed, DURATION, DAMAGE)
	end), "guardBreakBleed")

	return self
end

function module.destroy(self:myself)
	self:remConnection("guardBreakBleed")
	baseClass.destroy(self)
end

return table.freeze(module)
