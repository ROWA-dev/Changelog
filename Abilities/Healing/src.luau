--!strict
-- Healing: hold to heal whoever you face (else yourself) until mana drops under manaUse. No anim, no windup, no flat cost: the drain is the price.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Healing",
	manaUse = 5, -- the cast gate AND the channel's floor; useMana is never called
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj: humObj): myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

local CD_ID = "healing"
local TICK_START, TICK_MIN = 0.3, 0.1
local RAMP_SELF, RAMP_OTHER = 2, 1 -- seconds of holding on that target to ease START to MIN
local MANA_PER_TICK, HEAL_SELF, HEAL_OTHER = 1, 1, 2
local BOX_CF, BOX_SZ = CFrame.new(0, 0, -3), Vector3.new(4, 5, 4) -- HurtBox-local: whoever stands right in front
local LEASE, RENEW = 3, 2 -- client fx ceiling, re-sent before it lapses

local function useFunc(this: myself)
	-- no real cooldown: a one-beat re-arm so UseAbility's 0.2s retry cannot recast a tap
	if this:canTriggerCD(CD_ID) ~= true then return end
	this:triggerCD(CD_ID, TICK_START)
	this.isFeinted = false -- no windup, so a stale feint would self-cancel (ABILITIES §7)

	local humObj = this._humObj
	local char = humObj.Model
	local sent: BasePart?, sentAt = nil, 0
	local ramp = 0 -- 0..1, filled at the current target's rate so a retarget never jumps
	repeat
		-- isDead lands yields before isActive drops; a heal in between is onDeath's living corpse
		if humObj.isDead or humObj:manaNow() < this.manaUse then break end
		humObj:setMana(humObj:manaNow() - this:manaCost(MANA_PER_TICK))

		local _, hits = this:hitbox(BOX_CF, BOX_SZ)
		local target: any = humObj
		for _, e in hits do
			if (e :: any).Heal then target = e break end -- SimpleEntity has no Heal
		end
		target:Heal(if target == humObj then HEAL_SELF else HEAL_OTHER)

		local aim = target.Model:FindFirstChild("Head") or target.HRootPart
		if aim ~= sent or tick() - sentAt > RENEW then
			sent, sentAt = aim, tick()
			fireVFX("healHand", char, LEASE, aim)
		end
		local waited = task.wait(math.lerp(TICK_START, TICK_MIN, ramp))
		ramp = math.min(ramp + waited / (if target == humObj then RAMP_SELF else RAMP_OTHER), 1)
	until (humObj :: any)._abilityHeld == false or this:channelBreak(true)
	fireVFX("healHand", char, 0)
end

function module.use(self: myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
