--!strict
--[[
	AbilityHaste — makes the wielder's abilities wind up faster.

	This card is the proof that a card can buff an ABILITY's speed, not just a
	weapon's. It only works because AbilityBase's atkRate / atkRateOffset /
	knockbackMult are AdditiveValues: plain numbers have no mod list to target,
	so a card could only clobber the raw value and hope nothing else wanted a say.

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
