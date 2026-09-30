--!strict
-- weapon hits move one random non-innate card from the victim to me, once per COOLDOWN. runtime only: a respawn reloads both from the save
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local CARDS = require(script.Parent)

export type myself = baseClass.myself & {
	_next: number,
}

local COOLDOWN = 1

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	self._next = 0

	self:addConnection(humObj.onAttack:Connect(function(attack)
		if tick() < self._next or not (attack:isHit() and attack:isWep()) then return end
		local victim = attack.enemyEntity
		-- the inert stub has no list
		local list = victim and victim.cards.cards
		if list == nil then return end

		-- reservoir pick, so no table per hit
		local pick, n = nil, 0
		for _, v in list do
			local card = CARDS.get(v.id)
			if card and not card.innate then
				n += 1
				if math.random(n) == 1 then pick = v.id end
			end
		end
		if pick == nil then return end

		self._next = tick() + COOLDOWN
		victim.cards:remCard(pick)
		humObj.cards:addCard(pick)
	end))

	return self
end

return table.freeze(module)
