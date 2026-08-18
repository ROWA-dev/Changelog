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
	dmg      = 26,
	stun     = 0.6,
	posMult  = 2,
	--- positive on purpose: it is a big slow telegraphed rock. Keep the sign.
	parryH   = 0.1,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitCrush")
	end,
}

local ROLL_TIME = 1
--[[ rowa1 BodyVelocity Velocity = Dir*90, and bodyForce scales by 5, so the
	literal conversion is 18. It reads far too fast.

	WHY THE /5 RATIO UNDER-DELIVERS HERE: every other caller uses bodyForce
	as a short IMPULSE (0.1-0.4s), where the character never reaches the
	commanded velocity before it expires. StoneBall holds it for a FULL
	SECOND, so it actually gets there -- the same number is a shove
	everywhere else and a top speed here.
	Sustained movers want roughly two thirds of the converted value. ]]
local ROLL_SPEED = 12
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
	fireVFX("bground", humObj.HRootPart, 0.6 + ROLL_TIME)

	--- rowa1 froze input for the whole windup and roll
	humObj.walkSpeed:SetMod(SLOW_KEY, -13)

	if this:feintWait(0.6) then
		if anim then anim:Stop() end
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
	--- stage 2 whenever the roll REALLY ended, including an early break
	fireVFX("stoneBallRoll", 2, humObj.HRootPart)

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
