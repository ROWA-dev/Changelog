--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {
}

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

local BOOST = 0.05

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	-- basic attacks only: AttackClass seeds dmgMult from this and ONLY for weapon attacks.
	humObj.wepDmgMult:SetMod(tostring(self.randID), BOOST)
	return self
end

function module.destroy(self:myself)
	local humObj = self._humObj
	if humObj then
		humObj.wepDmgMult:RemoveMod(tostring(self.randID))
	end
	baseClass.destroy(self)
end

return table.freeze(module)
