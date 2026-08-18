--!strict
--[[ FlameDance - rowa1 Items/Ability/FlameDance.
	Notes: README.md/PORT_FlameDance.

	A 2-second spinning fire aura. Ticks damage every 0.1s inside 20 studs
	and applies burn between 20 and 40. A zoning tool, not a burst tool.

	!! THE STUN LOCK WARNING FROM THE PORT DOC IS REAL AND IS HANDLED HERE.
	rowa1's "fd" sat in noparrystun AND unparriers AND autoParries -- the
	resolver gave the victim three separate outs, none of which exist in
	rowa2. A 20-stud, 0.5s-stun, 10-per-second aura with none of them is an
	unbreakable two-second lock.
	Three mitigations, all deliberate:
	  1. parryH 0.1 (rowa1 had this too -- it is trivially parryable)
	  2. stunMeOnParried 0, the one-field replacement for `noparrystun`
	  3. a PER-ENTITY re-hit cooldown, so one victim can be hit at most
	     every 0.4s rather than every 0.1s
	Without (3) the move still locks. Do not remove it to "match rowa1". ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "FlameDance"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag  = dmgUtils.dmgFlags
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)

--- rowa1 "fd": Medium, slash+fire, 5 dmg, stun 0.5, posMult 0.5, parryH 0.1.
local FD = {
	weight   = dmgUtils.weighEnum.Medium,
	type     = bit32.bor(dmgFlag.slash, dmgFlag.fire),
	dmg      = 5,
	stun     = 0.5,
	posMult  = 0.5,
	parryH   = 0.1,
	stunMeOnParried = 0,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitSound")
	end,
}

local LIFETIME    = 2
local TICK_RATE   = 0.1
--- rowa1 started `elapse` at -0.4, so the first damage tick lands 0.5s in.
local FIRST_TICK  = 0.5
local INNER       = 20
local OUTER       = 40
--- rowa1 only burned the far band after 0.6s of channel.
local BURN_AFTER  = 0.6
--- see the header. Not in rowa1; without it this is a stun lock.
local REHIT_CD    = 0.4

local function useFunc(this:myself)
	local cooldownID = "flameDance"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	if this:feintWait(0.35) then
		if anim then anim:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	fireVFX("fdance", hurtbox)

	local anim2 = this:PlayAnim(script.Anim2, 0, 1, 1)

	local started    = tick()
	local nextHit    = started + FIRST_TICK
	local lastHitAt: {[number]: number} = {}

	--[[ fixed-rhythm channel -> BARRAGE PATTERN for the interrupt checks.
		feintWait would fight the cadence. ]]
	while tick() < started + LIFETIME do
		local dt = task.wait()

		if humObj:inStun() then break end
		if this.isFeinted then
			this.isFeinted = false
			humObj.cooldowns:trigger("feint2")
			fireVFX("feintfx", char)
			break
		end

		-- rowa1 pulsed the spin speed with a cosine; purely cosmetic, kept,
		-- because it is what makes the move read as a dance rather than a loop.
		if anim2 then
			local wave = (1 - (started + LIFETIME - tick())) * math.pi
			anim2:AdjustSpeed(1.1 + math.cos(wave) / 3)
		end

		if tick() < nextHit then continue end
		nextHit = tick() + TICK_RATE

		--[[ ONE query, split by distance in Luau. rowa1 queried a 60x6x60 box
			for a move whose own logic never reaches past 40 -- that is the
			broadphase scanning half the arena ten times a second. Shrunk to
			just past the outer band. ]]
		local _, hits = this:hitbox(CFrame.new(), Vector3.new(44, 6, 44))
		local elapsed = tick() - started

		for _, enemy in pairs(hits) do
			local eroot = enemy.HRootPart
			if eroot == nil then continue end
			local dist = (eroot.Position - hurtbox.Position).Magnitude

			if dist > OUTER then continue end

			if dist > INNER then
				--[[ the far band is NOT an attack. rowa1 resolved a dmgID
					called "burn" with dmg 0 and stun 0 whose only purpose was
					to make the resolver call BurnEnemy. In rowa2 that is one
					line at the call site and no attack object at all. ]]
				if elapsed > BURN_AFTER then
					enemy.statusEffects:apply(humObj.statusEffects.Burn, 6, 3)
				end
				continue
			end

			local last = lastHitAt[enemy.entityId]
			if last and tick() - last < REHIT_CD then continue end
			lastHitAt[enemy.entityId] = tick()

			local dir = eroot.Position - hurtbox.Position
			dir = if dir.Magnitude > 0 then dir.Unit else hurtbox.CFrame.LookVector

			task.spawn(function()
				local attack = this:makeAtk(FD, enemy, dir)
				this:executeAttack(attack)
			end)
		end
	end

	if anim2 then anim2:Stop(0.8) end
	if anim then anim:Stop(0.3) end
	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
