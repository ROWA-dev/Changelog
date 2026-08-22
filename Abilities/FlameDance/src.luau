--!strict
--[[ FlameDance - rowa1 Items/Ability/FlameDance.
	Notes: README.md/PORT_FlameDance.

	A 2-second spinning fire aura. Ticks damage every 0.1s inside 20 studs
	and sets light to anything in the outer band. A zoning tool, not a burst
	tool.

	!! THE STUN LOCK WARNING FROM THE PORT DOC IS REAL AND IS HANDLED HERE --
	but NOT with a re-hit cooldown. That was tried and it is the wrong shape.
	rowa1's "fd" sat in noparrystun AND unparriers AND autoParries, and the
	third is the one that mattered: a parry against the dancer bought 0.4s in
	which everything auto-parried. THE HITS NEVER SLOWED DOWN, THE VICTIM GOT
	AN OUT. A per-entity 0.4s re-hit cooldown is not that -- it quartered the
	damage (4 hits a cast, not 14), made the aura chug, and did not even break
	the lock, because 0.5s of stun re-applied every 0.44s is still a lock.
	Same three outs, translated:
	  1. parryH 0.1 (rowa1 had this too -- it is trivially parryable)
	  2. stunMeOnParried 0, the one-field replacement for `noparrystun`
	  3. parryH ESCALATES TO 1 the moment the aura makes contact with anyone.
	     That is `autoParries` in rowa2 terms, copied off Barrage -- the other
	     multi-hit that had to solve exactly this. The victim still has to
	     press parry; the press just stays live ~1.2s instead of 0.2s.
	Which is why the dmgTbl is built PER CAST inside useFunc: (3) mutates it,
	and a module-scope table would carry the escalation into every later cast
	by every entity. ]]
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
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)

--- hoisted out of the dmgTbl: it captures nothing, so it stays ONE closure
--- for the whole server even though the table around it is now per cast.
local function fdOnHit(attack: any)
	hitSfx(attack.enemyEntity.HRootPart, "HitSound")
end

local LIFETIME    = 2
local TICK_RATE   = 0.1
--- rowa1 started `elapse` at -0.4, so the first damage tick lands 0.5s in.
local FIRST_TICK  = 0.5
local INNER       = 20
local OUTER       = 40
--- rowa1 only burned the far band after 0.6s of channel.
local BURN_AFTER  = 0.6

local function useFunc(this:myself)
	local cooldownID = "flameDance"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	if this:feintWait(0.27) then
		if anim then anim:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	--[[ !! END THE AURA ON THE REAL END, not on the duration it was started
		with. This channel drops out early on stun and on FEINT, and a client
		told "two seconds" up front kept the fire pouring off someone who had
		already stopped dancing -- so a feinted FlameDance cancelled the
		damage and changed nothing on screen. Same shape, same reason, as
		IceBeam's stopBeam and StoneBall's ststep/bground teardown.
		LIFETIME is passed rather than left to the fx module's default so the
		two cannot drift apart. ]]
	fireVFX("fdance", hurtbox, LIFETIME)
	local function stopDance()
		fireVFX("fdance", hurtbox, 0)
	end

	local anim2 = this:PlayAnim(script.Anim2, 0, 1, 1)

	--[[ rowa1 "fd": Medium, slash+fire, 5 dmg, stun 0.5, posMult 0.5,
		parryH 0.1. PER CAST AND MUTABLE -- parryH escalates on first contact,
		see the header. Same reason Barrage builds its table inside useFunc. ]]
	local FD = {
		weight   = dmgUtils.weighEnum.Medium,
		type     = bit32.bor(dmgFlag.slash, dmgFlag.fire),
		dmg      = 5,
		stun     = 0.5,
		posMult  = 0.5,
		parryH   = 0.1,
		stunMeOnParried = 0,
		onHit    = fdOnHit,
	}

	local started    = tick()
	local nextHit    = started + FIRST_TICK

	--[[ ONE ignite per victim per CAST. rowa1's guard was
		`if not RootPart:FindFirstChild("flameFx")` -- never re-light someone
		already alight. Without it this move's own 0.1s tick stacked Burn into
		itself ~13 times, taking a 3-a-tick DoT to 21 and scaling the emitters
		with it.
		Keyed to THIS CAST on purpose, not to "is the victim burning at all":
		Burn.onStack still stacks, so another move landing on the same victim
		piles onto the fire exactly as before. Only the self-stack was wrong. ]]
	local burned: {[number]: boolean} = {}
	local function ignite(enemy: any)
		local id = enemy.entityId
		if burned[id] then return end
		burned[id] = true
		enemy.statusEffects:apply(humObj.statusEffects.Burn, 6, 3)
	end

	--[[ fixed-rhythm channel -> BARRAGE PATTERN for the interrupt checks.
		feintWait would fight the cadence. ]]
	while tick() < started + LIFETIME do
		task.wait()

		if humObj:inStun() then
			stopDance()
			break
		end
		if this.isFeinted then
			this.isFeinted = false
			humObj.cooldowns:trigger("feint2")
			fireVFX("feintfx", char)
			stopDance()
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
			(±30 studs) ten times a second, which is the broadphase scanning
			half the arena. This one reaches ±22, so OUTER is not actually the
			binding number -- the far band is 20 to ~22 on axis, ~31 across the
			diagonal. Widen the box, not OUTER, if that ring should be real. ]]
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
					ignite(enemy)
				end
				continue
			end

			local dir = eroot.Position - hurtbox.Position
			dir = if dir.Magnitude > 0 then dir.Unit else hurtbox.CFrame.LookVector

			task.spawn(function()
				local attack = this:makeAtk(FD, enemy, dir)
				this:executeAttack(attack)

				--- CONTACT OF ANY KIND OPENS THE OUT (header, mitigation 3).
				--- Barrage's exact shape, including escalating off a parry:
				--- the point is the SECOND parry, not the first.
				if attack:isHit() then
					FD.parryH = 1
					--- rowa1 burned on the "fd" hit too, behind the same guard.
					--- Standing in the fire is what should set you on fire.
					ignite(enemy)
				elseif attack:isParried() then
					FD.parryH = 1
				end
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
