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

	HOLD THE KEY TO KEEP THEM ARMED, LET GO TO SET THEM OFF. rowa1 had no
	such thing -- every kunai burned a fixed ~0.6s fuse on its own, so the
	only timing you controlled was when you threw. Holding makes the
	detonation a second decision: pin someone, wait for them to commit, then
	blow it. Tapping still behaves like the original, see MIN_HOLD.

	You hold the HOTBAR key -- the one that cast it. That release did not
	exist: the hotbar bind opened with `if not down then return end`, so
	key-up never left the client. inputEnums.endAbility looks like the
	obvious source and is not; it fires off E, which casts nothing.
	CombatAction:chargeWait is the shared half; anything else that wants a
	hold can use it. ]]
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
	--[[ NO onHit SOUND, deliberately. rowa1's explo3 row ships `sounds = {}`
		-- empty -- because the bang belongs to the EXPLOSION, not to each
		body it catches, and kunaiBoom already plays `explode` with a
		randomised pitch. An earlier pass added HardPunchHit here, so every
		victim in the blast got a dry punch impact layered over the boom.
		That is the "explosion hit sound is weird / wrong sound". ]]
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
--[[ rowa1's fuse was 0.6 +- 0.2 and fixed. MIN_HOLD replaces it: a tap
	behaves like the old move, because the ability fires on the same press
	the charge later watches for, so a normal tap has ALREADY sent
	endAbility by the time the watcher starts. Without a floor every tap
	would read as an instant release and there would be no fuse at all.

	MAX_HOLD is capped by the VISUAL, not by balance: kunaiProj lingers the
	stuck kunai for 4s after it lands, so a longer hold would detonate a
	kunai that is no longer on screen. If this ever needs to be longer, the
	linger has to move with it. ]]
local MIN_HOLD     = 0.6
local MAX_HOLD     = 3

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true

local function vecRand(r: number): Vector3
	return Vector3.new(math.random(-r, r), math.random(-r, r), math.random(-r, r))
end
local function vecAbs(v: Vector3): Vector3
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

--- the blast itself, once the charge is released.
local function blast(action: any, pos: Vector3, fallbackDir: Vector3)
	if action == nil or action._humObj == nil then return end

	fireVFX("kunaiBoom", pos)

	local _, hits = action:hitbox(
		CFrame.new(pos), Vector3.one * BLAST_RADIUS, nil, true)

	for _, enemy in pairs(hits) do
		local eroot = enemy.HRootPart
		if eroot == nil then continue end
		--- OBB query, spherical blast: reject the corners (rowa1 did too)
		local offset = eroot.Position - pos
		if offset.Magnitude > BLAST_RADIUS then continue end

		local dir = if offset.Magnitude > 0 then offset.Unit else fallbackDir
		local attack = action:makeAtk(EXPLO3, enemy, dir)
		-- rowa1 look*16, at the x0.6 knockback ratio (README S7)
		attack.knockback = action:knockback(dir * 9.6, 0.2, false, -1)
		action:executeAttack(attack)
	end
end

--[[ HOLD TO KEEP THEM ARMED, LET GO TO SET THEM OFF.

	rowa1 had no such thing: every kunai burned a ~0.6s fuse and went off on
	its own, so the only timing you controlled was when you threw. Holding
	turns that into a real decision -- pin someone down, wait for them to
	commit, then blow it -- and it is why the ability now runs a charge.

	The state is PER CAST, not per module. Four kunai from one throw share
	one `cast` table so they detonate together, and two players (or one
	player twice) never see each other's. A module-level flag would have
	them cross-triggering, which is the same class of bug the shared
	`aimParams` above still has.

	A kunai that lands while charging is ARMED and waits. One that lands
	AFTER the release -- still in the air when you let go -- goes off on
	arrival instead, which is what you would expect from a thrown bomb whose
	trigger has already been pulled. ]]
local function makeCast(this: any)
	local cast = { armed = {}, charging = true, dir = Vector3.zAxis }

	cast.cfg = {
		speed       = 200,
		--- rowa1 gave it exactly one second of flight
		lifetime    = 1,
		maxDistance = 220,
		size        = Vector3.new(3, 3, 4),
		--- the kunai itself is inert; the blast is the whole payload
		dmgTbl      = nil,
		stopOnWorld = true,
		fxId        = "kunaiProj",

		--[[ MUST NOT YIELD. This runs inside the scheduler's step loop, and
			the fuse used to be a plain `task.wait` right here -- which
			suspended that loop mid-iteration and corrupted its swap-remove,
			silently dropping other projectiles. That is why kunai
			"sometimes stopped exploding forever and just threw".
			BaseProjectile.kill detaches payloads now, but this stays
			non-yielding on purpose: arming is a table insert. ]]
		onExpire = function(proj: any, pos: Vector3, _hitWorld: boolean)
			local action = proj.action
			if action == nil or action._humObj == nil then return end
			cast.dir = proj.dir
			if cast.charging then
				table.insert(cast.armed, pos)
			else
				blast(action, pos, proj.dir)
			end
		end,
	}

	return cast
end

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

	local cast = makeCast(this)

	local origin = hurtbox.Position
	for i = 1, KUNAI_COUNT do
		local spread = CFrame.Angles(
			math.rad(math.random(-10, 10)),
			math.rad(math.random(-10, 10)),
			0)
		local dir = aimAt(origin, (hurtbox.CFrame * spread).LookVector, target, i, char)
		this:projectile(cast.cfg, CFrame.new(origin, origin + dir))
	end

	--[[ DETACHED, and that is the point. The throw is over in 0.18s and you
		should be free to move and fight while the kunai sit there armed --
		holding the action open for the whole charge would lock you out of
		everything for three seconds, which is not a hold, it is a channel.
		So the ability ENDS here and a watcher owns the detonation. ]]
	task.spawn(function()
		this:chargeWait(MAX_HOLD, MIN_HOLD)
		cast.charging = false
		for _, pos in ipairs(cast.armed) do
			blast(this, pos, cast.dir)
		end
	end)

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
