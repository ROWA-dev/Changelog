--!strict
-- util: fires when MY weapon heavy lands on a BLEEDING victim
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local DmgUtils  = require(game.ServerScriptService.Utils.DmgUtils)

local HEAVY = DmgUtils.dmgFlags.weaponHeavy

return function(onBleeding: (humObj: any, victim: any, bleed: any) -> ())
	local module = {}
	module.__index = module
	setmetatable(module, { __index = baseClass })

	function module.new(humObj)
		local self = setmetatable(baseClass.new(humObj), module) :: any

		self:addConnection(humObj.onAttack:Connect(function(attack)
			if not (attack:isHit() and attack:hasDmgFlag(HEAVY)) then return end
			local victim = attack.enemyEntity
			if victim == nil then return end
			-- :get is nil on the inert stub too, which never bleeds
			local bleed = victim.statusEffects:get(humObj.statusEffects.Bleed)
			if bleed == nil then return end
			onBleeding(humObj, victim, bleed)
		end))

		return self
	end

	return table.freeze(module)
end
