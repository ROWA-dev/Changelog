--!strict
--[[ Prediction - rowa1 Items/Ability/Prediction.
	Notes: README.md/PORT_Prediction.

	A counter STANCE. For a short window every attack that would hit you is
	turned back on whoever threw it, until enough damage breaks through.

	THE ABILITY IS THIS SHORT ON PURPOSE. rowa1's aEvent is also a stub --
	it creates a `pframes` NumberValue on the Humanoid and the actual
	mechanic is ~50 lines inside AttackModule keyed on that value. Here the
	mechanic is Class/StatusEffects/Reflect and the resolver is untouched,
	which is the whole argument in README S1.2.

	NOT the same shape as LionFall/ToshiCounter. Those wait for ONE attack
	and answer it with a move of their own; this reflects EVERYTHING for the
	duration and has no follow-up. So it does not use their
	connect-then-abort pattern -- it just applies an effect and gets out of
	the way. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Prediction"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
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

local function useFunc(this:myself)
	local cooldownID = "prediction"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local char: any = humObj.HurtBox.Parent

	--[[ the same guards ToshiCounter uses: a counter thrown out of hitstun
		is free defence rather than a read. ]]
	local now = tick()
	if now < humObj.stun.Value + 0.4 then return end
	if now < humObj._lastBlocked + 0.4 then return end

	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	--- rowa1 locked input for the stance
	humObj.walkSpeed:SetMod(SLOW_KEY, -13)
	fireVFX("predictStance", humObj.HRootPart, WINDOW)

	local reflect: any = humObj.statusEffects:apply(statusEffects.Reflect, WINDOW, ABSORB_CAP)

	--[[ rowa1 tagged this `noFeint`, so the stance cannot be cancelled once
		committed -- atkWait, not feintWait. See PORT_LionFall step 2 for why
		a framework flag is the wrong way to express that.

		A CORRECT READ ENDS IT EARLY though. `atkWait` is a bare task.wait and
		cannot be interrupted, so this is that same scaled wait rewritten as a
		poll. `use` clears `attacking` the instant useFunc returns, so
		returning early IS the cancel -- no framework support needed. Guessing
		right buys you the turn; guessing wrong still pays the full window.

		Reads `reflected`, not `absorbed`: the hit that SHATTERS the stance
		must not count as a read.

		`or 0` is load-bearing. The effect's cleanup thread can destroy it
		mid-poll (destroy does table.clear), and a nil compare here would
		throw inside useFunc -- which `use` pcalls into a mere warn, leaking
		the walkSpeed mod below and slowing the player forever. ]]
	local total  = this:scaledTime(WINDOW)
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
	if anim then anim:Stop(0.2) end

	--[[ a whiffed stance leaves you open, which is the cost of guessing wrong.
		A landed one skips it entirely -- that IS the reward.

		The reflect itself is still running here, and still extending on every
		hit (HIT_EXTEND). That is rowa1-faithful, since pframes outlived the
		0.8s ability body -- but it does mean you attack WHILE reflecting. If
		you want one read to answer exactly one attack, drop the effect on the
		landed branch: humObj.statusEffects:remove(statusEffects.Reflect) ]]
	if not landed then
		this:endLag(0.3)
	end
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
