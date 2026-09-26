--!strict
--- PaperBomb - four explosive kunai, dead straight (no gravity), stick in walls or limbs; hold the hotbar key to keep them armed, release to set them off in sequence.
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
	dmg      = 10, -- too op bro
	stun     = 0.2,
	posMult  = 0.5,
	parryH   = 0.2,
	stunMeOnParried = 0,
}

local KUNAI_COUNT  = 4
local BLAST_RADIUS = 16
local TARGET_RANGE = 200
--- seconds between blasts in one cast
local BLAST_GAP    = 0.1
local PAPERBOMB_CONE = table.freeze({
	distWeight = 4, maxAngle = 0.8, closeRange = 20, closeBonus = 1.5,
	requireLOS = true, useHead = true,
})
--- the floor stops a tap reading as an instant release; MAX_HOLD must stay under kunaiProj's LINGER
local MIN_HOLD     = 0.6
local MAX_HOLD     = 3

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true
aimParams.FilterDescendantsInstances = { workspace.Effects, workspace.Entities }

local function vecRand(r: number): Vector3
	return Vector3.new(math.random(-r, r), math.random(-r, r), math.random(-r, r))
end
local function vecAbs(v: Vector3): Vector3
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

--- `bomb.p` is local to `bomb.at` (the limb it is stuck in), world space when nil
local function blast(action: any, bomb: any, fallbackDir: Vector3)
	if action == nil or action._humObj == nil then return end

	local pos = if bomb.at then bomb.at.CFrame:PointToWorldSpace(bomb.p) else bomb.p
	fireVFX("kunaiBoom", pos)

	--- full extent, so RADIUS * 2
	local _, hits = action:hitbox(
		CFrame.new(pos), Vector3.one * (BLAST_RADIUS * 2), nil, true)

	for _, enemy in pairs(hits) do
		local eroot = enemy.HRootPart
		if eroot == nil then continue end
		--- OBB query, spherical blast: reject the corners
		local offset = eroot.Position - pos
		if offset.Magnitude > BLAST_RADIUS then continue end

		local dir = if offset.Magnitude > 0 then offset.Unit else fallbackDir
		local attack = action:makeAtk(EXPLO3, enemy, dir)
		attack.knockback = action:knockback(dir * 9.6, 0.2, false, -1)
		action:executeAttack(attack)
	end
end

local function detonate(cast: any, action: any, bomb: any)
	local now = os.clock()
	cast.nextAt = math.max(now, cast.nextAt)
	task.delay(cast.nextAt - now, blast, action, bomb, cast.dir)
	cast.nextAt += BLAST_GAP
end

--- per cast, so two casters never cross-trigger; a kunai landing while charging waits, one landing after release goes off on arrival
local function makeCast()
	local cast = { armed = {}, charging = true, dir = Vector3.zAxis, nextAt = 0 }

	cast.cfg = {
		speed       = 200,
		lifetime    = 1,
		maxDistance = 220,
		size        = Vector3.new(3, 3, 4),
		dmgTbl      = nil,
		stopOnWorld = true,
		stickInBody = true,
		fxId        = "kunaiProj",

		onExpire = function(proj: any, pos: Vector3, _hitWorld: boolean)
			cast.dir = proj.dir
			local at = proj.stuckIn
			local bomb = { at = at, p = if at then at.CFrame:PointToObjectSpace(pos) else pos }
			if cast.charging then
				table.insert(cast.armed, bomb)
			else
				detonate(cast, proj.action, bomb)
			end
		end,
	}

	return cast
end

--- predict the target, then aim at a wall behind them, else the ground beneath, else the prediction; scatter hugs the surface
local function aimAt(origin: Vector3, baseDir: Vector3, target: any, i: number): Vector3
	if target == nil or target.HRootPart == nil then
		return baseDir
	end
	local troot = target.HRootPart
	local distance = (origin - troot.Position).Magnitude
	local predicted = troot.Position
		+ (troot.AssemblyLinearVelocity * distance / 200 / i)
		+ troot.CFrame.LookVector * 4

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
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	if this:feintWait(0.1) then
		if anim then anim:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	local target = Targeting.nearestInDirection(
		hurtbox.Position, hurtbox.CFrame.LookVector, humObj, TARGET_RANGE,
		PAPERBOMB_CONE)

	local cast = makeCast()

	local origin = hurtbox.Position
	for i = 1, KUNAI_COUNT do
		local spread = CFrame.Angles(
			math.rad(math.random(-10, 10)),
			math.rad(math.random(-10, 10)),
			0)
		local dir = aimAt(origin, (hurtbox.CFrame * spread).LookVector, target, i)
		this:projectile(cast.cfg, CFrame.new(origin, origin + dir))
	end

	--- detached so you can fight while they sit armed; the watcher owns the detonation
	task.spawn(function()
		this:chargeWait(MAX_HOLD, MIN_HOLD)
		cast.charging = false
		for _, bomb in ipairs(cast.armed) do
			detonate(cast, this, bomb)
		end
	end)

	this:endLag(0.25)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
