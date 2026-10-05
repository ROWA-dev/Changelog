--!strict
-- no anim, no windup:lights an infinite StatusEffects/Imbue that hits pay for; recast puts it out, free.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "ImbueMana",
	manaUse = 10,
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj: humObj): myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local CD_ID, CD = "imbueMana", 1

local function useFunc(this: myself)
	if this:canTriggerCD(CD_ID) ~= true then return end
	this:triggerCD(CD_ID, CD)
	this:useMana()
	local effects = this._humObj.statusEffects
	effects:apply(effects.Imbue, math.huge)
end

-- putting it out skips use(), whose 20 mana gate would trap anyone between Imbue's FLOOR and 20; the shared CD stops UseAbility's retry relighting it
function module.use(self: myself)
	local effects = self._humObj.statusEffects
	if effects:get(effects.Imbue) == nil then return baseClass.use(self, useFunc) end
	if self:canTriggerCD(CD_ID) ~= true then return false end
	self:triggerCD(CD_ID, CD)
	return effects:remove(effects.Imbue)
end

return table.freeze(module)
