--!strict
--[[ PaperBomb - rowa1 Items/Ability/PaperBomb.
	Notes: README.md/PORT_PaperBomb.

	Throw four explosive kunai. They fly straight, stick in whatever they
	hit, and detonate on a short fuse.

	!! THE PORT DOC CALLED THIS AN ARC. IT IS NOT.
	  There is no gravity anywhere in the original -- the kunai travel dead
	  straight at 200 studs/s for up to one second. What makes them land
	  around a target is the AIMING, not a trajectory: rowa1 predicts where
	  the target will be, then raycasts for a WALL BEHIND THEM, and failing
	  that for the GROUND BENEATH THEM, and aims at that point with scatter.
	  So they pepper the surface a target is standing on or against.
	  That aiming is the whole feel of the move and it is ported below;
	  Projectile.Arcing is not involved.

	The fuse is the other half: a kunai that STICKS waits ~0.6s before going
	off, so a target can walk out of it, while one that flies its full range
	explodes where it ran out. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "PaperBomb"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils   = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag    = dmgUtils.dmgFlags
local Targeting  = require(game.ServerStorage.ROWA.Modules.Targeting)
local fireVFX    = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx     = require(game.ServerStorage.ROWA.Modules.hitSfx)

--[[ rowa1 "explo3": Heavy, fire, 16 dmg, truestun 0 / stun 0.2, posMult 0.5.
	It sits in `unparriers`, `noparrystun` AND `autoParries` -- an explosion
	is not something you parry. `parryH = -10` is the one-field way to say
	that; there is no boolean, and adding one would start rowa1's lookup
	tables over (README S1.2, PORT_PaperBomb WATCH). ]]
local EXPLO3 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.fire,
	dmg      = 10,
	stun     = 0.2,
	posMult  = 0.5,
	parryH   = -10,
	stunMeOnParried = 0,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit")
	end,
}

local KUNAI_COUNT  = 4
local BLAST_RADIUS = 16
--- rowa1 variant 4 capped at 200 studs
local TARGET_RANGE = 200
--- variant 4 == TIGHT, but aiming at the Head
local PAPERBOMB_CONE = table.freeze({
	distWeight = 4, maxAngle = 0.8, closeRange = 20, closeBonus = 1.5,
	requireLOS = true, useHead = true,
})
--- rowa1: 0.6 +- 0.2 after sticking. A flown-out kunai goes off immediately.
local FUSE         = 0.6

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true

local function vecRand(r: number): Vector3
	return Vector3.new(math.random(-r, r), math.random(-r, r), math.random(-r, r))
end
local function vecAbs(v: Vector3): Vector3
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

--- the blast. Runs from the projectile's onExpire, after the fuse.
local function detonate(proj: any, pos: Vector3, hitWorld: boolean)
	local action = proj.action
	if action == nil or action._humObj == nil then return end

	--- a stuck kunai burns down; one that ran out of range goes off at once
	if hitWorld then
		task.wait(FUSE + math.random(-20, 20) / 100)
		if action._humObj == nil then return end
	end

	fireVFX("kunaiBoom", pos)

	local _, hits = action:hitbox(
		CFrame.new(pos), Vector3.one * BLAST_RADIUS, nil, true)

	for _, enemy in pairs(hits) do
		local eroot = enemy.HRootPart
		if eroot == nil then continue end
		--- OBB query, spherical blast: reject the corners (rowa1 did too)
		local offset = eroot.Position - pos
		if offset.Magnitude > BLAST_RADIUS then continue end

		local dir = if offset.Magnitude > 0 then offset.Unit else proj.dir
		local attack = action:makeAtk(EXPLO3, enemy, dir)
		-- rowa1 look*16, at the x0.6 knockback ratio (README S7)
		attack.knockback = action:knockback(dir * 9.6, 0.2, false, -1)
		action:executeAttack(attack)
	end
end

local KUNAI = table.freeze({
	speed       = 200,
	--- rowa1 gave it exactly one second of flight
	lifetime    = 1,
	maxDistance = 220,
	size        = Vector3.new(3, 3, 4),
	--- the kunai itself is inert; the blast is the whole payload
	dmgTbl      = nil,
	stopOnWorld = true,
	fxId        = "kunaiProj",
	onExpire    = detonate,
})

--[[ rowa1's aim: predict where the target will be, then look for a surface
	to pin the kunai to -- a wall BEHIND them first, the ground BENEATH them
	second, and the prediction itself as a fallback. Scatter is applied to
	the surface point, along the axes the surface normal does NOT occupy, so
	the spread hugs the wall or floor instead of drifting off it. ]]
local function aimAt(origin: Vector3, baseDir: Vector3, target: any, i: number, char: Instance): Vector3
	if target == nil or target.HRootPart == nil then
		return baseDir
	end
	local troot = target.HRootPart
	local distance = (origin - troot.Position).Magnitude
	local predicted = troot.Position
		+ (troot.AssemblyLinearVelocity * distance / 200 / i)
		+ troot.CFrame.LookVector * 4

	aimParams.FilterDescendantsInstances = { workspace.Effects, workspace.Entities, char }

	local wall = workspace:Raycast(predicted, baseDir * 12, aimParams)
	if wall then
		local p = wall.Position + vecRand(20) / 2 * (Vector3.one - vecAbs(wall.Normal))
		return (p - origin).Unit
	end

	local falling = troot.AssemblyLinearVelocity / 4
	if falling.Y > 0 then falling *= Vector3.new(1, -1, 1) end
	local ground = workspace:Raycast(predicted, Vector3.new(0, -8, 0) + falling, aimParams)
	if ground then
		local p = ground.Position + vecRand(20) / 2 * (Vector3.one - vecAbs(ground.Normal))
		return (p - origin).Unit
	end

	local d = predicted - origin
	return if d.Magnitude > 0 then d.Unit else baseDir
end

local function useFunc(this:myself)
	local cooldownID = "paperBomb"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	--[[ !! 0.18, NOT 0.7. rowa1 DECLARES `Attacking.Time = 0.7` but then
		waits `task.wait(0.1)` and throws. The declared value is only what
		the trade logic reads; the real throw is basically instant, and that
		snappiness is the move.
		0.18 because feintWait waits t - 0.08 (README S7 note 7f).
		Lesson: Attacking.Time is a CLAIM, the task.wait is the TRUTH --
		JoltKick had the same mismatch in the other direction. ]]
	if this:feintWait(0.18) then
		if anim then anim:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	--[[ rowa1 used GetNearestInDirection4: the TIGHT preset with useHead --
		0.8 rad cone, close-range forgiveness, and a LINE-OF-SIGHT check, so
		you cannot pepper someone through a wall. `useHead` is variant 4's
		one difference from variant 5: it measures the angle to the target's
		head rather than their root. ]]
	local target = Targeting.nearestInDirection(
		hurtbox.Position, hurtbox.CFrame.LookVector, humObj, TARGET_RANGE,
		PAPERBOMB_CONE)

	local origin = hurtbox.Position
	for i = 1, KUNAI_COUNT do
		local spread = CFrame.Angles(
			math.rad(math.random(-10, 10)),
			math.rad(math.random(-10, 10)),
			0)
		local dir = aimAt(origin, (hurtbox.CFrame * spread).LookVector, target, i, char)
		this:projectile(KUNAI, CFrame.new(origin, origin + dir))
	end

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
