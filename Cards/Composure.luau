--!strict
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself

local BOOST = 0.25
local MOD = "composure"

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	-- read off the live rate so the base stays HumObj's business, not a copy here.
	-- postureHeal replicates its mods, so the client's own posture step follows.
	humObj.postureHeal:SetMod(MOD, humObj.postureHeal.Value * BOOST)

	return self
end

function module.destroy(self:myself)
	local humObj = self._humObj
	if humObj and humObj.postureHeal then humObj.postureHeal:RemoveMod(MOD) end
	baseClass.destroy(self)
end

return table.freeze(module)
