--!strict
-- FlameDance - a 2s spinning fire aura: ticks damage every 0.1s inside 20 studs and ignites anything in the outer band. Zoning, not burst.
-- !! the stun-lock is handled by giving the victim an OUT, not by slowing the hits: trivially parryable, no parry stun on the caster, and parryH ESCALATES to 1 on first contact.
-- that escalation mutates the table, which is why the dmgTbl is built PER CAST inside useFunc -- a module-scope one would carry it into every cast.
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

-- hoisted out of the dmgTbl: it captures nothing, so it stays ONE closure for the whole server even though the table around it is per cast.
local function fdOnHit(attack: any)
	hitSfx(attack.enemyEntity.HRootPart, "HitSound")
end

local LIFETIME    = 2
local TICK_RATE   = 0.1
-- the first damage tick lands 0.5s in.
local FIRST_TICK  = 0.5
local INNER       = 20
local OUTER       = 40
-- the far band only burns after this much channel.
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

	-- !! END THE AURA ON THE REAL END, not the duration it started with: this channel drops out early on stun and on FEINT, so fire would keep pouring off someone who already stopped.
	fireVFX("fdance", hurtbox, LIFETIME)
	local function stopDance()
		fireVFX("fdance", hurtbox, 0)
	end

	local anim2 = this:PlayAnim(script.Anim2, 0, 1, 1)

	-- PER CAST AND MUTABLE: parryH escalates on first contact, see the header.
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

	-- ONE ignite per victim per CAST, or the 0.1s tick stacks Burn into itself ~13 times. Keyed to THIS CAST, so another move still piles on as before.
	local burned: {[number]: boolean} = {}
	local function ignite(enemy: any)
		local id = enemy.entityId
		if burned[id] then return end
		burned[id] = true
		enemy.statusEffects:apply(humObj.statusEffects.Burn, 6, 3)
	end

	-- fixed-rhythm channel, so the interrupt checks are hand-rolled: feintWait would fight the cadence.
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

		-- the spin speed pulses with a cosine: cosmetic, but it is what makes this read as a dance rather than a loop.
		if anim2 then
			local wave = (1 - (started + LIFETIME - tick())) * math.pi
			anim2:AdjustSpeed(1.1 + math.cos(wave) / 3)
		end

		if tick() < nextHit then continue end
		nextHit = tick() + TICK_RATE

		-- ONE query, split by distance in Luau; the box reaches ~22 on axis, so widen the BOX, not OUTER, if the far ring should be real.
		local _, hits = this:hitbox(CFrame.new(), Vector3.new(44, 6, 44))
		local elapsed = tick() - started

		for _, enemy in pairs(hits) do
			local eroot = enemy.HRootPart
			if eroot == nil then continue end
			local dist = (eroot.Position - hurtbox.Position).Magnitude

			if dist > OUTER then continue end

			if dist > INNER then
				-- the far band is NOT an attack: it is one ignite call, with no attack object at all.
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

				-- CONTACT OF ANY KIND OPENS THE OUT, including a parry: the point is the SECOND parry, not the first.
				if attack:isHit() then
					FD.parryH = 1
					-- standing in the fire is what should set you on fire.
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
