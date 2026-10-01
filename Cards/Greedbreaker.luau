--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local Debris = game:GetService("Debris")

export type myself = baseClass.myself

local BONUS = 0.2

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any

	-- outgoing, so beforeAttack like Frontliner; reads the victim before the hit can interrupt them.
	self:addConnection(humObj.beforeAttack:Connect(function(attack)
		local victim = attack.enemyEntity
		if victim == nil or not attack:isWep() or victim.attacking.Value ~= true then return end
		attack.dmgMult += BONUS
		attack.greedbreaker = true
	end))

	-- feedback waits for resolution like Frontliner: a parried or blocked hit never landed.
	self:addConnection(humObj.onAttack:Connect(function(attack)
		if not (attack.greedbreaker and attack:isHit()) then return end
		local victim = attack.enemyEntity
		local at = victim and (victim.getFxPart and victim:getFxPart() or victim.HRootPart)
		if at == nil then return end

		local fx = script.ParticleEmitter:Clone()
		fx.Parent = at
		fx:Emit(math.floor(attack:CalculateDamage())) -- dmg scales emit count
		Debris:AddItem(fx, 4)
	end))

	return self
end

return table.freeze(module)
