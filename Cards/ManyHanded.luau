--!strict
-- Many-Handed: carry a second committed weapon. HumObj's cap is 1, so this is
-- what makes the wielded SET a set. Nothing else to do: WieldWeapon reads the
-- AdditiveValue every commit.
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
	_modKey: string,
}

local EXTRA_WEAPONS = 1

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	self._modKey = "manyHanded:" .. tostring(self.randID)

	humObj.maxWeapons:SetMod(self._modKey, EXTRA_WEAPONS)

	return self
end

function module.destroy(self:myself)
	local humObj = self._humObj
	if humObj then
		-- the SET is not trimmed here: the cap is read at commit time, so anything
		-- already holstered stays until the next wield evicts it.
		humObj.maxWeapons:RemoveMod(self._modKey)
	end
	baseClass.destroy(self)
end

return table.freeze(module)
