--!strict
-- BoulderKick - rip a chunk of the actual MAP out of the ground and punt it at someone, at its real size, colour and material.
-- the server runs the arc (cfg.gravity) and owns no Instance; the rock is client-drawn and the carve happens where it lands.
-- FIZZLE IS A FEATURE: no breakable underfoot means a 2s cooldown instead of 12. The only ability that reads the map before it commits.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "BoulderKick"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local dmgUtils    = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag     = dmgUtils.dmgFlags
local fireVFX     = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx      = require(game.ServerStorage.ROWA.Modules.hitSfx)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
local Targeting   = require(game.ServerStorage.ROWA.Modules.Targeting)

-- kept in step with StoneBall's neighbouring row.
local BLDR = table.freeze({
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.blunt, dmgFlag.earth),
	dmg      = 29,
	stun     = 0.6,
	posMult  = 3,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitCrush")
		-- a long CAP, ended by landing
		attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
	end,
})

-- 0.1s quicker than authored (0.92 -> 0.82 to the kick); the anim is sped to match so the kick stays on its frame.
local ANIM_SPEED = 0.92 / 0.82
local WINDUP = 0.22 / ANIM_SPEED
local GATHER = 0.7 / ANIM_SPEED

-- !! FULL EXTENT, not radii: Destruction halves this itself, same trap as Armor's DIG_SIZE.
-- flat Y: same footprint, ~half the depth, so people stop falling in the hole.
local DIG_SIZE  = Vector3.new(12, 6, 12)
local DIG_MINSZ = 3.6
-- SIX, not seven.
local GRAB_COUNT = 6

-- thrown flat and hard, then allowed to sag: an arc, not a line.
-- IT SHATTERS ON THE FIRST BODY (pierce 1), so the expiry -- burst, crater and shake -- lands ON the person hit. Ploughing through fights its own onExpire and reads as weightless.
local SPEED    = 110
local GRAVITY  = 40
local MAX_DIST = 400
local LIFETIME = 8
module.BLDR = BLDR

-- hard 30 deg cone like Spear's throw, out to as far as the rock flies: soft-locks onto someone above, below or to the side.
local AIM_CONE = table.freeze({ distWeight = 10, maxAngle = math.rad(30) })

-- the exact low arc onto `to` at SPEED; out of reach throws at 45, the farthest it goes.
function module.aimCF(from: Vector3, to: Vector3): CFrame
	local d = to - from
	local x = Vector3.new(d.X, 0, d.Z).Magnitude
	if x < 0.01 then return CFrame.lookAt(from, to) end
	local v2 = SPEED * SPEED
	local disc = v2 * v2 - GRAVITY * (GRAVITY * x * x + 2 * d.Y * v2)
	local tan = if disc < 0 then 1 else (v2 - math.sqrt(disc)) / (GRAVITY * x)
	return CFrame.lookAt(from, Vector3.new(to.X, from.Y + tan * x, to.Z))
end

-- tears a rock out at `digAt` and gathers it to gatherCF (in `follow`'s space if given: it rides that part until launched). nil = nothing breakable there.
-- also how a boss throws one (catherdal giant): .scale on its instance grows the rock, .bldr swaps the dmg table
function module.dig(this: myself, digAt: Vector3, gather: number, gatherCF: CFrame, follow: BasePart?): { any }?
	local k = (this :: any).scale or 1
	-- DIG, THEN DECIDE: Grab carves the crater, describes the biggest cuboids that came out, and withholds them from the rubble fx so they leave the ground exactly once.
	local _, chunks = Destruction.Grab(nil, CFrame.new(digAt), DIG_SIZE * k, DIG_MINSZ * k, nil, GRAB_COUNT)
	if chunks == nil or #chunks == 0 then return nil end
	fireVFX("boulderKick", 1, this._humObj.Model, chunks, gather, gatherCF, follow, if k ~= 1 then k else nil)
	return chunks
end

-- flings a dug rock from originCF
function module.launch(this: myself, chunks: { any }, originCF: CFrame)
	local k = (this :: any).scale or 1
	local char = this._humObj.Model
	-- built per cast because ONE field varies: the hit volume is sized off the pieces actually torn up, so a rock of big slabs hits wider than one of scraps.
	local avg = Vector3.zero
	for _, c in ipairs(chunks) do
		avg += (c.size + Vector3.new(5, 5, 5)) / 2
	end
	avg *= k / #chunks -- the drawn rock is scaled by k too
	-- half the magnitude of the average piece size
	local hitSize = Vector3.one * math.clamp(avg.Magnitude * 0.5, 4, 10 * k)

	-- !! THE PROJECTILE IS SPAWNED BEFORE THE FX: the drawn rock needs the projectile's `id` to receive a correction, and the id does not exist until it is spawned.
	local p = this:projectile(table.freeze({
		speed       = SPEED,
		gravity     = GRAVITY,
		maxDistance = MAX_DIST,
		lifetime    = LIFETIME,
		size        = hitSize,
		dmgTbl      = (this :: any).bldr or BLDR,
		knockbackForce = 9.6,
		knockbackTime  = 0.2,

		onExpire = function(proj: any, pos: Vector3, _hitWorld: boolean)
			-- where it really stopped is THE ONLY THING THE CLIENTS COULD NOT PREDICT, so it is the only thing sent.
			fireVFX("boulderKick", 3, char, pos)
			-- r7 where it lands; velo is studs/SECOND, along the direction it was actually travelling
			Destruction.Sphere(nil, pos, 7 * k, 4.2, proj.dir * 70)
			fireVFX("camShake", pos, 300, 1, 0.15)
		end,
	}), originCF)

	fireVFX("boulderKick", 2, char, originCF, SPEED, GRAVITY, MAX_DIST, LIFETIME,
		p and p.id)
end

local function useFunc(this:myself)
	local cooldownID = "boulderKick"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Kick, 0, 1, ANIM_SPEED)

	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		return
	end

	local forward = hurtbox.CFrame.LookVector
	local digAt = hurtbox.Position + forward * 6 + Vector3.new(0, -2, 0)

	-- where the rock assembles: in front of the caster, at kicking height
	local gatherCF = CFrame.new(
		hurtbox.Position + forward * 6 + Vector3.new(0, 2, 0),
		hurtbox.Position + forward * 12)
	local chunks = module.dig(this, digAt, GATHER, gatherCF)

	if chunks == nil then
		-- the fizzle tier: 2s, no mana spent. The full price below must not pass
		-- dontOverwrite or this pins the id at 2s for the session. See triggerCD.
		if anim then anim:Stop(0.1) end
		this:triggerCD(cooldownID, 2, true)
		this:endLag(0.2)
		return
	end

	-- the telegraph: the kicking leg glows red for the whole gather
	local leftLeg = char:FindFirstChild("Left Leg")
	if leftLeg then
		fireVFX("partOutline", leftLeg, Color3.fromRGB(255, 0, 0), GATHER + 0.2)
	end

	if this:feintWait(GATHER) then
		if anim then anim:Stop(0.1) end
		-- the terrain is client-drawn, so calling it off actually calls it off
		fireVFX("boulderKick", 0, char)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12)

	local snd = script.kicksound:Clone()
	snd.Parent = humObj.HRootPart
	snd:Play()
	game.Debris:AddItem(snd, 6)

	-- the kick ring, four studs ahead, WITH boom
	local ringAt = hurtbox.Position + forward * 4
	fireVFX("shockRing",
		CFrame.new(ringAt, ringAt + forward * 6),
		Vector3.new(7, 7, 0.5), 0.9, true)

	-- re-read: the caster may have turned during the gather
	local from = gatherCF.Position
	local look = hurtbox.CFrame.LookVector
	local target = Targeting.nearestInDirection(from, look, humObj, MAX_DIST, AIM_CONE)
	local originCF = if target then module.aimCF(from, (Targeting.lead(target.HRootPart, from, SPEED)))
		else CFrame.new(from, from + (look + Vector3.new(0, 0.1, 0)).Unit)
	module.launch(this, chunks, originCF)

	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
