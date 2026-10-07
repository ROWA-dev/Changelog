--!strict
-- Meteor - call a meteor down where you aim, up to RANGE away (touch and NPCs: the nearest body). It comes in at an angle, so walls take it too, re-angled round anything in its way.
-- A real projectile that only the world stops: a thin roof gives way (what the carve really took decides), anything else is its crater. Bodies on its line are crushed: the blast reaches back up its path.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Meteor",
	manaUse = 40,
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local dmgUtils      = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag       = dmgUtils.dmgFlags
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local Targeting     = require(game.ServerStorage.ROWA.Modules.Targeting)
local fireVFX       = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx        = require(game.ServerStorage.ROWA.Modules.hitSfx)
local partFx        = require(game.ServerStorage.ROWA.Modules.partFx)
local Destruction   = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
local aimPoint      = require(game.ReplicatedStorage.Modules.aimPoint)
local projMotion    = require(game.ReplicatedStorage.Modules.projMotion)
local Projectile    = require(game.ServerStorage.ROWA.Class.Projectile)

local METEOR = table.freeze({
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.blunt, dmgFlag.earth),
	dmg      = 50,
	stun     = 1,
	posMult  = 3,
	parryH   = -0.1,
	dodgeH   = -0.2,
	onHit    = function(attack)
		local enemy = attack.enemyEntity
		hitSfx(enemy.HRootPart, "HitCrush")
		-- a long CAP, ended by landing
		enemy.ragdoll:ragdoll(60, true, attack.atkDir * 24)
		enemy.statusEffects:apply(statusEffects.Burn, 3, 2, attack.myEntity)
	end,
})

local WINDUP   = 0.85 -- the anim's hit marker: the arm hauls it down
local RANGE    = 200
local RADIUS   = 48
local CRUSH    = 56   -- width of the column it crushes on the way down
local FALLOFF  = 0.4  -- damage lost at the rim
local KNOCK    = 30
local SKY      = 200  -- studs up the line it falls along
local ASK_T    = 0.3  -- longest wait on the caster's cursor
local CRATER   = 16   -- the rock's own size: a roof hole it fits through
local SCORCH_T = 30
-- of the crater's sphere, what it may break and still fly on. Measured on the map: a roof ~0.1, a floor ~0.15, the ground ~0.4
local PUNCH    = 0.3
local SPHERE_V = 4 / 3 * math.pi * CRATER ^ 3
-- the first line leans back toward the caster; the rest are tried in order until one is clear
local YAWS    = { 0, 40, -40, 80, -80, 120, -120, 180 }
local PITCHES = { 55, 70, 40, 85 }

-- MAP only. Permanent folder, so set once
local scorchParams = OverlapParams.new()
scorchParams.FilterType = Enum.RaycastFilterType.Include
scorchParams.FilterDescendantsInstances = { workspace:WaitForChild("MAP") }

-- where it falls from. A wall is only reachable from its open side; boxed in, the first line, and Rock decides what gives way.
local function skyFor(to: Vector3, normal: Vector3, from: Vector3): Vector3
	local back = (from - to) * Vector3.new(1, 0, 1)
	back = if back.Magnitude > 0.1 then back.Unit else Vector3.zAxis
	local first
	for _, yaw in YAWS do
		local flat = CFrame.Angles(0, math.rad(yaw), 0):VectorToWorldSpace(back)
		for _, pitch in PITCHES do
			local dir = flat * math.cos(math.rad(pitch)) + Vector3.yAxis * math.sin(math.rad(pitch))
			if dir:Dot(normal) < 0.2 then continue end
			first = first or dir
			if workspace:Raycast(to + normal, dir * SKY, aimPoint.params) == nil then
				return to + dir * SKY
			end
		end
	end
	return to + (first or Vector3.yAxis) * SKY
end

-- charred first, so the pieces inherit it; returns the share of the sphere that was solid AND breakable
local function crater(at: Vector3, normal: Vector3, dir: Vector3): number
	for _, p in workspace:GetPartBoundsInRadius(at, CRATER * 1.8, scorchParams) do
		if math.max(p.Size.X, p.Size.Y, p.Size.Z) <= CRATER * 1.5 then partFx.apply(p, partFx.Burn, SCORCH_T) end
	end
	local took = 0
	-- studs/s: up off the face and on the way it was going
	local along = dir - normal * dir:Dot(normal)
	for _, d in Destruction.Sphere(nil, at, CRATER, 5, normal * 140 + along * 80) do
		for _, c in d.destroyed do took += c[1].X * c[1].Y * c[1].Z end
	end
	return took / SPHERE_V
end

-- the rock: thin roofs give way, the unbreakable, the thick, or a spent punch stop it, and that carve was its crater
local Rock = setmetatable({ Name = "MeteorRock" }, { __index = Projectile.BaseProjectile })
Rock.__index = Rock
Rock.__tostring = Projectile.BaseProjectile.__tostring

function Rock.new(action: any, cfg: any, originCF: CFrame): any
	local self = setmetatable(Projectile.BaseProjectile.new(action, cfg, originCF) :: any, Rock)
	self.punch = 0
	return self
end

function Rock.onWorldHit(self: any, hit: RaycastResult): boolean
	local took = crater(hit.Position, hit.Normal, self.dir)
	self.punch += took
	self.carved = took == 0 or self.punch > PUNCH
	return self.carved
end

local function impact(this: myself, to: Vector3, normal: Vector3, dir: Vector3, carved: boolean?, path: number)
	-- the ground breaks whether or not the caster is still around
	if not carved then crater(to, normal, dir) end

	local humObj = this._humObj
	if humObj == nil or humObj.isActive ~= true then return end
	-- entity -> its distance into the blast. :hitbox is a box and the blast a sphere: query the box, reject the corners
	local dist = {}
	local _, hits = this:hitbox(CFrame.new(to), Vector3.one * (RADIUS * 2), nil, true)
	for _, e in hits do dist[e] = (e.HRootPart.Position - to).Magnitude end
	-- the query always ignores its caster; a meteor does not, same as Blight. spareCaster: a boss raining them round itself
	if not (this :: any).spareCaster then dist[humObj] = (humObj.HRootPart.Position - to).Magnitude end
	-- crushed on the way down: the column back up its path, InverseRed's shape. Full blast, wherever it landed
	local mid = to - dir * path / 2
	local _, crushed = this:hitbox(CFrame.lookAt(mid, mid + dir), Vector3.new(CRUSH, CRUSH, path), nil, true)
	for _, e in crushed do dist[e] = 0 end

	for enemy, d in dist do
		if d > RADIUS then continue end
		local out = (enemy.HRootPart.Position - to + normal * 6).Unit
		local attack = this:makeAtk(METEOR, enemy, out)
		attack.dmgMult *= (1 - FALLOFF * d / RADIUS) * ((this :: any).dmgMult or 1)
		attack.knockback = this:knockback(out * KNOCK, 0.3)
		this:executeAttack(attack)
	end
end

-- comes through slow and lands at ~240 studs/s: ~1.1s down the SKY line
local ROCK = table.freeze({
	speed       = 60,
	accel       = 160,
	maxDistance = SKY + 60,
	-- no dmgTbl: bodies never stop it (impact crushes them), so this only paces its substeps
	size        = Vector3.one * CRUSH,
	class       = Rock,
	onExpire = function(proj: any, pos: Vector3, hitWorld: boolean)
		local wh = proj.worldHit
		impact(proj.action, pos, if hitWorld and wh then wh.Normal else Vector3.yAxis, proj.dir, proj.carved, math.max(proj.travelled, 1))
	end,
})

-- the rock at `k`x pace, same path: a boss sets it as .rock (with .dmgMult) on its own instance
function module.pacedRock(k: number)
	local r = table.clone(ROCK)
	r.speed, r.accel = ROCK.speed * k, ROCK.accel * k * k
	return table.freeze(r)
end

-- one rock down onto `to`, leaning in from `from`'s side. No mana, no cd: also how a boss calls them (catherdal giant)
function module.fall(this: myself, to: Vector3, normal: Vector3, from: Vector3)
	local rock = (this :: any).rock or ROCK
	local originCF = CFrame.lookAt(skyFor(to, normal, from), to)
	-- spawned before the broadcast: the drawn copy needs its id for the end packet
	local p = this:projectile(rock, originCF)
	-- `to` is where the telegraph goes: the line was clear to it, or it is coming through the roof over it
	fireVFX("meteor", 2, this._humObj.HRootPart.Parent, originCF, rock.speed, rock.maxDistance, projMotion.pick(rock), p and p.id, to, normal)
end

local function useFunc(this:myself)
	local cooldownID = "meteor"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj = this._humObj
	local root = humObj.HRootPart
	local char: any = root.Parent
	local plrObj: any = humObj.plrObj
	local cursor = plrObj ~= nil and plrObj.isMobile ~= true
	-- touch and NPCs have no cursor: they aim at the nearest body
	local target = if cursor then nil else Targeting.nearest(root.Position, humObj, RANGE)

	local anim = this:PlayAnim(script.Anim, 0, 1, 1)
	fireVFX("meteor", 1, char)
	if cursor or target then
		humObj:FireVFXClient("aimLock", this:scaledTime(WINDUP) + ASK_T, RANGE, RADIUS, target and target.HRootPart)
	end

	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		fireVFX("meteor", 0, char)
		humObj:FireVFXClient("aimLock", 0)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 40)

	local to, normal
	if cursor then to, normal = aimPoint.ask(plrObj.Plr, ASK_T) end
	humObj:FireVFXClient("aimLock", 0)
	if to == nil then
		target = target or Targeting.nearest(root.Position, humObj, RANGE)
		to = if target and target.isActive then target.HRootPart.Position else root.Position + root.CFrame.LookVector * RANGE / 2
	end
	to, normal = aimPoint.clamp(root.Position, to :: Vector3, normal, RANGE)

	module.fall(this, to :: Vector3, normal, root.Position)

	this:endLag(0.35)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
