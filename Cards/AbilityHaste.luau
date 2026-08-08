--!strict
--[[
	AbilityHaste — makes the wielder's abilities wind up faster.

	This card exists to PROVE the PLAN_05 5B exit criterion: "a card can buff
	an ability's speed. Prove it with one real card."

	Before 5B this card was IMPOSSIBLE TO WRITE. AbilityBase stored atkRate /
	atkRateOffset / knockbackMult as plain numbers, so there was no mod list to
	target — a card could only have clobbered the raw value and hoped nothing
	else wanted a say. Weapons had AdditiveValue and abilities did not, which
	read as a style inconsistency but was actually a feature hole.

	Mirrors SpeedOnParry's shape: SetMod on apply, RemoveMod on cleanup, keyed
	by a card-specific string so it stacks correctly with anything else.
]]
local baseClass = require(script.Parent:WaitForChild("cardBase"))

export type myself = baseClass.myself & {}

local MOD_KEY = "abilityHaste"
--- multiplier applied to ability windups. atkRate is a multiplier, so a
--  NEGATIVE mod makes abilities faster. -0.3 = 30% quicker.
local HASTE = -0.3

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	-- Abilities are constructed per use, so the mod is applied when one starts
	-- being used rather than once at card load.
	self:addConnection(
		humObj.onAttackWindup:Connect(function()
			local ability = humObj.using_ability
			if ability and ability.atkRate then
				ability.atkRate:SetMod(MOD_KEY, HASTE)
			end
		end),
		"abilityHaste"
	)

	return self
end

function module.destroy(self:myself)
	local humObj = (self :: any)._humObj
	local ability = humObj and humObj.using_ability
	if ability and ability.atkRate then
		ability.atkRate:RemoveMod(MOD_KEY)
	end
	self:remConnection("abilityHaste")
	baseClass.destroy(self)
end

return table.freeze(module)
