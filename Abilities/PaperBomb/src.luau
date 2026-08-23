--!strict
--- PaperBomb - throw four explosive kunai. They fly straight, stick in what
--- they hit, and detonate on a fuse. rowa1 port: README.md/PORT_PaperBomb.
--- !! the doc calls this an ARC and it is not -- no gravity anywhere, dead
--- straight at 200 studs/s. What makes them land around a target is the AIMING:
--- predict the target, raycast for a wall behind them or the ground beneath
--- them, aim at that with scatter. Projectile.Arcing is not involved.
--- HOLD THE HOTBAR KEY to keep them armed, let go to set them off -- a second
--- decision rowa1 never had. Tapping behaves like the original, see MIN_HOLD.
--- CombatAction:chargeWait is the shared half.
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

local EXPLO3 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.fire,
	dmg      = 12,
	stun     = 0.2,
	posMult  = 0.5,
	parryH   = 0.2,
	stunMeOnParried = 0,
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
--- replaces rowa1's fixed 0.6 fuse. The floor is required: the cast fires on
--- the same press the charge watches, so a tap has already sent endAbility by
--- the time the watcher starts and would read as an instant release.
--- MAX_HOLD is capped by the VISUAL -- kunaiProj lingers 4s -- not by balance.
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

--- state is PER CAST, not per module: four kunai share one `cast` table so they
--- detonate together, and two casters never see each other's. A module-level
--- flag would cross-trigger.
--- A kunai landing while charging is ARMED and waits; one landing after the
--- release goes off on arrival.
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

	--[[ !! 0.1, NOT 0.7. rowa1 DECLARES `Attacking.Time = 0.7` but then
		waits `task.wait(0.1)` and throws. The declared value is only what
		the trade logic reads; the real throw is basically instant, and that
		snappiness is the move.
		Lesson: Attacking.Time is a CLAIM, the task.wait is the TRUTH --
		JoltKick had the same mismatch in the other direction. ]]
	if this:feintWait(0.1) then
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
