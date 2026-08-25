--!strict
--- Zoltraak - a lock-on piercing bolt. Acquire, charge 0.6s, fire; on a connect
--- inside 60 studs, follow up with a 10-shot volley at randomised offsets.
--- rowa1 port: README.md/PORT_Zoltraak.
--- THERE IS NO PROJECTILE: rowa1 resolved instantly on the target and let the
--- client draw a beam. PLAN_PROJECTILE 2D -- do not build one for something
--- that never had one.
--- STUN IS ZERO, DELIBERATELY: eleven bolts with the victim fully mobile IS the
--- counterplay. Adding stun turns it into an eleven-hit lock.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Zoltraak"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils  = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag   = dmgUtils.dmgFlags
local Targeting = require(game.ServerStorage.ROWA.Modules.Targeting)
local fireVFX   = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx    = require(game.ServerStorage.ROWA.Modules.hitSfx)

--[[ rowa1 "ztr": Heavy, blunt, 10 dmg, truestun 0 / stun 0, posMult 2.
	stunMeOnParried 0 replaces rowa1's `noparrystun` membership -- without it,
	parrying bolt 1 punishes the caster for the remaining ten. ]]
local ZTR = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 8,
	stun     = 0,
	posMult  = 1,
	dodgeH   = 0.1, -- rowa2-only knob: a no-travel lock-on needs SOME out
	stunMeOnParried = 0,
	--[[ rowa1's "ztr" row carries onHit = ragdollWait: 0.8s FLAT per bolt.
		With eleven bolts each extending the lifetime, the victim stays down
		for the whole volley -- which is rowa1's behaviour and is why the
		move can afford ZERO stun. ]]
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitSound")
		attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * 6)
	end,
}

--- rowa1 variant 5 capped at 200 studs
local TARGET_RANGE = 200
local CHARGE      = 0.6
local VOLLEY      = 10
--- rowa1 task.wait(0.15) between volley launches.
local VOLLEY_STAGGER = 0.15
local VOLLEY_RANGE = 60
local CD          = 18
--- rowa1 refunded a whiff down to a 1 second cooldown. Good design, kept.
local WHIFF_CD    = 6

--- one bolt: it CHARGES, then it fires. Shared by the opener and every volley shot.
--- !! EVERY BOLT HAS ITS OWN 0.6s CHARGE -- the volley is ten overlapping
--- charges staggered 0.15s across 1.5s, not ten instant hits. Resolving them
--- immediately collapses a ~2.1s sequence into ~0.6 (the "zoltraak is so fast"
--- read; it is here, not in the windup).
local function resolveBolt(this: myself, target: any, offset: Vector3): boolean
	local humObj = this._humObj
	if humObj == nil or humObj.isActive ~= true then return false end
	if target == nil or target.isActive ~= true then return false end

	local root = humObj.HRootPart
	local eroot = target.HRootPart
	if root == nil or eroot == nil then return false end

	fireVFX("zoltrak2", root, eroot, offset)

	local dir = (eroot.Position - (root.Position + offset))
	dir = if dir.Magnitude > 0 then dir.Unit else root.CFrame.LookVector

	local attack = this:makeAtk(ZTR, target, dir)
	-- rowa1 lookVector*12, at the x0.6 knockback ratio (README S7)
	attack.knockback = this:knockback(dir * 7.2, 0.15, false, -1)
	this:executeAttack(attack)
	return attack:isHit()
end

--- charge THEN resolve. The volley uses this; the opener drives its own
--- charge through feintWait so it stays cancellable.
local function chargedBolt(this: myself, target: any, offset: Vector3)
	local humObj = this._humObj
	if humObj == nil or humObj.isActive ~= true then return end
	if target == nil or target.isActive ~= true or target.HRootPart == nil then return end

	fireVFX("zoltrak", humObj.HRootPart, target.HRootPart, offset, CHARGE)
	task.wait(CHARGE)
	resolveBolt(this, target, offset)
end

local function useFunc(this:myself)
	local cooldownID = "zoltraak"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local anim    = this:PlayAnim(script.Anim, 0, 1, 1)

	--- rowa1 used GetNearestInDirection5: the TIGHT preset -- 0.8 rad cone,
	--- close-range forgiveness, and a line-of-sight check so a bolt cannot
	--- lock through a wall.
	local target = Targeting.nearestInDirection(
		hurtbox.Position, hurtbox.CFrame.LookVector, humObj,
		TARGET_RANGE, Targeting.TIGHT)

	--[[ WHIFF REFUND, and it happens BEFORE the mana is spent. rowa1 charged
		the full 28s only on a lock; an empty cast cost 1s. ]]
	if target == nil then
		if anim then anim:Stop() end
		this:triggerCD(cooldownID, WHIFF_CD, true)
		return
	end

	fireVFX("zoltrak", humObj.HRootPart, target.HRootPart, Vector3.zero, CHARGE)

	if this:feintWait(CHARGE) then
		if anim then anim:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, CD, true)

	local hit = resolveBolt(this, target, Vector3.zero)

	--[[ the volley. rowa1 spawned ten coroutines that each re-read the
		character's state; here each shot re-checks `target.isActive` and the
		distance itself, because a destroyed entity is a bare empty table
		(DOC_GOTCHAS) and rowa1 would happily keep shooting a corpse. ]]
	if not hit then
		this:endLag(0.2)
		return
	end

	local root = humObj.HRootPart
	if root == nil or (root.Position - target.HRootPart.Position).Magnitude >= VOLLEY_RANGE then
		this:endLag(0.2)
		return
	end

	task.wait(0.1)
	for _ = 1, VOLLEY do
		if humObj:inStun() or humObj.isActive ~= true then break end
		if target.isActive ~= true or target.HRootPart == nil then break end
		root = humObj.HRootPart
		if root == nil then break end

		local lookCf = CFrame.new(root.Position, target.HRootPart.Position)
		local offset = Vector3.new(0, math.random(8, 20), 0)
			+ lookCf.RightVector * math.random(-24, 24)
			+ lookCf.LookVector * -10

		task.spawn(chargedBolt, this, target, offset)
		--[[ 0.15, rowa1's stagger. Ten bolts therefore LAUNCH across 1.5s and,
			with each one's 0.6s charge, the last lands at ~2.1s. ]]
		task.wait(VOLLEY_STAGGER)
	end

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
