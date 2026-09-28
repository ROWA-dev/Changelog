--!strict
-- +20 max health, and a Charm from an owner with no more mind than you bounces off (StatusEffects.resist)
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local MAX_HEALTH = 20

-- live invested mind, 0 for anything not player-backed
local function mindOf(e:any): number
	local slot = e and e.plrObj and e.plrObj.loadedSlot
	return slot and slot.baseStats.mind or 0
end

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any
	self:addMaxHealth(MAX_HEALTH)
	local se = humObj.statusEffects
	local charm = se.Charm
	se.resist = function(effect, _, _, owner)
		return effect == charm and mindOf(owner) <= mindOf(humObj)
	end
	return self
end

function module.destroy(self:myself)
	local humObj = self._humObj
	if humObj and humObj.statusEffects then humObj.statusEffects.resist = nil end
	baseClass.destroy(self)
end

return table.freeze(module)
