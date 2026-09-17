--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Saringan",
	manaUse = 40,
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj: humObj): myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local Entities = require(game.ServerScriptService.Entities)
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

local DURATION = 40
local RECENT_HIT = 30

local function recentVictims(owner: humObj): {any}
	local out = {}
	local now = tick()
	for _, enemy in Entities.GetAll() do
		local record = enemy.dmgRecord
		local entry = record and record.contributions and record.contributions[owner]
		if enemy ~= owner and enemy.isActive == true and entry and now - entry.updateAt < RECENT_HIT then
			table.insert(out, enemy)
		end
	end
	return out
end

local function useFunc(this: myself)
	local cooldownID = "saringan"
	if not this:canTriggerCD(cooldownID) then return end

	local humObj = this._humObj
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)
	local head = humObj.Model and humObj.Model:FindFirstChild("Head")
	local bill = if head then script.eyeAbove:Clone() else nil
	if bill then
		bill.Parent = head
		game.Debris:AddItem(bill, 6)
	end

	if this:feintWait(0.4) then
		if anim then anim:Stop(0.1) end
		if bill then bill:Destroy() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 50, true)
	fireVFX("saringan", bill)
	humObj.statusEffects:apply(statusEffects.Saringan, DURATION, recentVictims(humObj))
	this:endLag(0.6)
end

function module.use(self: myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)