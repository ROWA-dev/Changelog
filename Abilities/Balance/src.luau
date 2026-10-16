--!strict
-- needs someone in combat with you: each timed effect's time left is split evenly between you and every one of them, posture evens out, and you borrow one card.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Balance",
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local Combatant = require(game.ReplicatedStorage.Class.Combatant)
local CARDS = require(game.ServerStorage.ROWA.Cards)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

local CD = 45
local BORROW = 60

-- nil = nothing to split: over, or infinite (BurningResolve/Imbue are stances their own ability ends)
local function leftOf(e:any): number?
	local left = e.startedAt + e.duration - tick()
	return if left > 0 and left < math.huge then left else nil
end

-- the combat HUD's list (hurt me inside the TTL), minus corpses and anything that can't hold an effect
local function enemiesOf(humObj:humObj): {any}
	local out, now = {}, tick()
	for enemy:any, entry in humObj.dmgRecord.contributions do
		if enemy.isActive and not enemy.isDead and now < entry.expireAt and Combatant.hasRealStatusEffects(enemy) then
			table.insert(out, enemy)
		end
	end
	return out
end

local function useFunc(this:myself)
	local cooldownID = "balance"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj = this._humObj
	local effects:any = humObj.statusEffects
	local enemies = enemiesOf(humObj)
	if #enemies == 0 then return end

	local anim = this:PlayAnim(script.Anim, 0, 1, 1)
	if this:feintWait(0.4) then
		if anim then anim:Stop(0.1) end
		return
	end

	this:triggerCD(cooldownID, CD)
	this:useMana()
	--fireVFX("scaleAnim",humObj.Hum)
	local n = #enemies + 1
	for key, e in effects.activeEffects do
		local left = leftOf(e)
		if left == nil then continue end
		local effect, share = effects[key], left / n
		effects:setLeft(effect, share)
		for _, enemy in enemies do
			enemy.statusEffects:apply(effect, share, e._amp, e.owner) -- owner: Charm's charmer, nil on the rest
		end
	end
	-- borrow a card you lack off a random enemy that has one; runtime only, so a respawn on either side settles it from the save
	local from:any, id, m = nil, nil, 0
	for _, enemy in enemies do
		local pick = CARDS.randomTakeable(enemy.cards, humObj.cards)
		if pick then
			m += 1
			if math.random(m) == 1 then from, id = enemy, pick end
		end
	end
	if from then
		from.cards:remCard(id)
		humObj.cards:addCard(id)
		task.delay(BORROW, function()
			local slot = humObj.plrObj and humObj.plrObj.loadedSlot
			if humObj.isActive and not (slot and slot.cards:getIndex(id)) then humObj.cards:remCard(id) end -- drafted it meanwhile = yours
			if from.isActive then from.cards:addCard(id) end
		end)
	end
	-- posture: everyone ends on the group's mean fraction of their own max
	table.insert(enemies, humObj)
	local mean = 0
	for _, x in enemies do mean += x.posture.Value / x.maxPosture.Value / n end
	for _, x in enemies do x.posture.Value = mean * x.maxPosture.Value end
	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
