--!strict
--- Prediction - a counter STANCE: for a short window every attack that would
--- hit you is turned back on whoever threw it, until enough damage breaks
--- through. rowa1 port: README.md/PORT_Prediction.
--- Short on purpose -- the mechanic is Class/StatusEffects/Reflect and the
--- resolver is untouched (rowa1 kept ~50 lines of it inside AttackModule).
--- NOT LionFall/ToshiCounter's shape: those answer ONE attack with a move of
--- their own, this reflects everything and has no follow-up, so it applies an
--- effect and gets out of the way rather than using connect-then-abort.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Prediction",
	manaUse = 20,
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj: humObj): myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self: myself = setmetatable(abstract, module) :: any
	return self
end

local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

--[[ rowa1's `pframes` decays from 10 at 14/sec, so the real window is about
	0.71s. The 0.8s wait afterwards is just the ability holding itself open. ]]
local WINDOW = 0.7
--- rowa1 shatters above 1000 absorbed
local ABSORB_CAP = 1000
local SLOW_KEY = "prediction"

local function useFunc(this: myself)
	local cooldownID = "prediction"
	if this:canTriggerCD(cooldownID) ~= true then
		return
	end

	local humObj = this._humObj
	local char: any = humObj.HurtBox.Parent

	--[[ the same guards ToshiCounter uses: a counter thrown out of hitstun
		is free defence rather than a read. ]]
	local now = tick()
	if now < humObj.stun.Value + 0.4 then
		return
	end
	if now < humObj._lastBlocked + 0.4 then
		return
	end

	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	--- rowa1 locked input for the stance
	humObj.walkSpeed:SetMod(SLOW_KEY, -100)
	fireVFX("predictStance", humObj.HRootPart, WINDOW)
	this:atkWait(0.1)

	local reflect: any = humObj.statusEffects:apply(statusEffects.Reflect, WINDOW, ABSORB_CAP)

	--- `noFeint`: the stance cannot be cancelled once committed, so atkWait, not
	--- feintWait. A CORRECT READ still ends it early, which is why the wait is a
	--- poll -- returning early IS the cancel, since `use` clears `attacking` the
	--- moment useFunc returns. Reads `reflected`, not `absorbed`: the hit that
	--- SHATTERS the stance must not count as a read.
	--- `or 0` is load-bearing: cleanup can destroy the effect mid-poll, and a nil
	--- compare throws into use()'s pcall, leaking the walkSpeed mod below.
	local total = this:scaledTime(WINDOW)
	local waited = 0
	local landed = false
	while waited < total do
		if (reflect.reflected or 0) > 0 then
			landed = true
			break
		end
		waited += task.wait()
	end

	humObj.walkSpeed:RemoveMod(SLOW_KEY)
	if anim then
		anim:Stop(0.2)
	end

	--[[ a whiffed stance leaves you open; a landed one skips it, and that IS
		the reward. The reflect is still running here and still extending on
		every hit (HIT_EXTEND), so you attack WHILE reflecting. To make one read
		answer exactly one attack, drop the effect on the landed branch:
		humObj.statusEffects:remove(statusEffects.Reflect) ]]
	if not landed then
		this:endLag(0.6)
	end
end

function module.use(self: myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
