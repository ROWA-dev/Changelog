--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local DURATION, CUT = 10, 0.15

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	self:addConnection(humObj.onAttack:Connect(function(attack)
		if not attack:isHit() then return end
		local victim = attack.enemyEntity
		-- never refresh or steal a live charm; that's Charisma's rule, not Charm's
		if victim == nil or victim.statusEffects:get(humObj.statusEffects.Charm) then return end
		victim.statusEffects:apply(humObj.statusEffects.Charm, DURATION, CUT, humObj)
	end), "charisma")

	return self
end

function module.destroy(self:myself)
	self:remConnection("charisma")
	baseClass.destroy(self)
end

return table.freeze(module)
