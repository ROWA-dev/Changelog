--!strict
--[[ StoneBall - rowa1 Items/Ability/StoneBall.
	Notes: README.md/PORT_StoneBall.

	!! THE PORT DOC HAD THIS MOVE WRONG.
	  It said "rip a boulder out of the ground, hold it overhead, then hurl
	  it forward". That is not what happens -- that is closer to BoulderKick.
	  StoneBall is a CHARGE: the caster VANISHES inside a giant stone ball
	  welded to their own root and rolls forward at 90 studs/s for a second,
	  flattening whatever is in front of them.

	  So it is not a projectile either. There is nothing to fire; the caster
	  IS the projectile, which is a dash plus a repeating hitbox, and
	  Class/Projectile is not involved.

	The roll ENDS EARLY on the first thing it hits (rowa1's `breakOut`),
	which is what stops it ploughing through a whole team. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "StoneBall"
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

--- rowa1 "bldr2": Heavy, blunt+earth, 40 dmg, truestun 0.4 / stun 0.6.
local BLDR2 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.blunt, dmgFlag.earth),
	dmg      = 20,
	stun     = 0.6,
	posMult  = 2,
	--- positive on purpose: it is a big slow telegraphed rock. Keep the sign.
	parryH   = 0.1,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitCrush")
	end,
}

local ROLL_TIME = 1
--[[ rowa1 BodyVelocity Velocity = Dir*90; /5 converts to 18, which read far
	too fast in play, so this is deliberately cut to ~2/3.

	THAT IS A TUNING CALL FOR THIS MOVE, NOT A RULE. It was briefly written
	up as "sustained movers want two thirds" and applied to Burst's charge,
	which then came out a third too slow. Start from the literal conversion
	and cut only what actually feels wrong. ]]
local ROLL_SPEED = 12
--- rowa1 Attacking.Time = 0.6, and its task.wait agrees for once
local WINDUP    = 0.6
local SLOW_KEY  = "stoneBall"

local function useFunc(this:myself)
	local cooldownID = "stoneBall"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0.1, 1, 1)

	--- hshock takes a BASEPART in rowa2, not a Humanoid (README S5 step 7e)
	fireVFX("hshock", humObj.HRootPart)

	--- rowa1 froze input for the whole windup and roll
	humObj.walkSpeed:SetMod(SLOW_KEY, -13)

	--[[ THE RUMBLE STARTS WITH THE CAST, not with the roll. rowa1 clones
		bground onto the root and plays groundshake as its FIRST act, so the
		wind-up has a build-up under it; starting it at the roll instead left
		0.52s of total silence and made the launch read as coming out of
		nowhere.
		The reason it had been moved was that a fixed duration kept dusting
		under a cast that never happened -- but bground is cancellable now,
		and rowa1 handles the same case the same way (Debris:AddItem(bground,
		0) on its interrupt path). So: start it early, kill it on the feint. ]]
	fireVFX("bground", humObj.HRootPart, WINDUP + ROLL_TIME)

	if this:feintWait(WINDUP) then
		if anim then anim:Stop() end
		fireVFX("bground", humObj.HRootPart, 0)
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 10, true)

	--[[ the caster VANISHES for the roll -- ststep hides every visible part
		and puts them back. The merged module owns both halves, so a dropped
		unhide can no longer leave someone permanently invisible. ]]
	fireVFX("ststep", char, ROLL_TIME)
	fireVFX("stoneBallRoll", 1, humObj.HRootPart, ROLL_TIME)

	--[[ the launch ring. rowa1 cloned Effects.Shockwave here and the GROWTH
		lived in FxHandler's global ChildAdded listener (README S5). One id
		owns both halves now -- see VFXQuiver/shockRing.
		rowa1's numbers: 6.5 x 6.5 x 0.5, transparency 0.96, stood up 2 studs
		ahead of the root and facing down the lane. No `boom`: StoneBall is
		the one caller that clones this asset without playing it. ]]
	local ringPos = humObj.HRootPart.Position + hurtbox.CFrame.LookVector * 2
	fireVFX("shockRing",
		CFrame.new(ringPos, ringPos + hurtbox.CFrame.LookVector * 8),
		Vector3.new(6.5, 6.5, 0.5), 0.96)

	if anim then anim:Stop(0) end

	--- HRootPart for physics, HurtBox for hitboxes (README S5 step 7d)
	local dash = this:bodyForce(Vector3.new(0, 0, -ROLL_SPEED), ROLL_TIME, true)

	local seen: {[number]: boolean} = {}
	local started = tick()
	local stopped = false

	--- fixed-rhythm channel -> the BARRAGE PATTERN for interrupt checks
	while tick() < started + ROLL_TIME do
		task.wait()

		if humObj:inStun() then break end
		if this.isFeinted then
			this.isFeinted = false
			humObj.cooldowns:trigger("feint2")
			fireVFX("feintfx", char)
			break
		end

		local _, hits = this:hitbox(CFrame.new(), Vector3.new(6, 6, 6))
		for _, enemy in pairs(hits) do
			if seen[enemy.entityId] then continue end
			seen[enemy.entityId] = true

			local attack = this:makeAtk(BLDR2, enemy, hurtbox.CFrame.LookVector)
			-- rowa1 look*16, at the x0.6 knockback ratio (README S7)
			attack.knockback = this:knockback(attack.atkDir * 9.6, 0.2, false, -1)
			this:executeAttack(attack)

			if attack:isHit() then
				--[[ rowa1 used `ragdtillground`: a long CAP that stopOnGround
					ends early. NOT (t, false) -- see IceBash for why that
					meant victims never got up. ]]
				attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
				--- rowa1's `breakOut`: the roll ENDS on the first connect
				stopped = true
			end
		end

		if stopped then break end
	end

	if dash then dash:destroy() end
	humObj.walkSpeed:RemoveMod(SLOW_KEY)

	--[[ END EVERY CHANNEL EFFECT ON THE REAL END, not on the duration they
		were started with. The roll stops early on a connect (`breakOut`), on
		stun and on feint, so anything told "1 second" up front outlives it:
		the rock kept spinning, dust kept pouring, and the caster stayed
		INVISIBLE for the remainder -- which is the bug that made StoneBall
		feel broken even when it worked. ]]
	fireVFX("stoneBallRoll", 2, humObj.HRootPart)
	fireVFX("ststep", char, 0)
	fireVFX("bground", humObj.HRootPart, 0)

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
