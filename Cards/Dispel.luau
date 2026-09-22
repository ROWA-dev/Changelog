--!strict
-- landing a weapon heavy puts the victim's current or last ability on a 4 minute cooldown
local baseClass = require(script.Parent:WaitForChild("cardBase"))
local DmgUtils  = require(game.ServerScriptService.Utils.DmgUtils)

export type myself = baseClass.myself

local HEAVY, LOCK = DmgUtils.dmgFlags.weaponHeavy, 240
local CHAIN = script.dispelchain

local module = {}
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj):myself
	local self:myself = setmetatable(baseClass.new(humObj), module) :: any

	self:addConnection(humObj.onAttack:Connect(function(attack: any)
		if not (attack:isHit() and attack:hasDmgFlag(HEAVY)) then return end
		local victim = attack.enemyEntity
		-- a destroyed ability is a cleared table, so its _cdId reads nil
		local ability = victim and victim.last_ability
		local id = ability and ability._cdId
		-- unregistered id: trigger would pin 240 as its permanent duration
		if id == nil or victim.cooldowns:duration(id) == nil then return end
		-- through the ABILITY, not cooldowns, so their hotbar slot draws it
		ability:triggerCD(id, LOCK)

		-- one chain per victim, re-cloned so it lasts as long as the newest lock. makeCorpse strips its beams
		local root = victim.HRootPart
		local old = root:FindFirstChild(CHAIN.Name)
		if old then old:Destroy() end
		local chain = CHAIN:Clone()
		chain.Parent = root
		chain.chains_break:Play()
		game.Debris:AddItem(chain, LOCK)
	end), "dispel")

	return self
end

function module.destroy(self:myself)
	self:remConnection("dispel")
	baseClass.destroy(self)
end

return table.freeze(module)
