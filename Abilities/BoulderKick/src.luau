--!strict
-- BoulderKick - rip a chunk of the actual MAP out of the ground and punt it at someone, at its real size, colour and material.
-- the server runs Arcing math and owns no Instance; the rock is client-drawn and the carve happens where it lands.
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
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any
	return self
end

local dmgUtils    = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag     = dmgUtils.dmgFlags
local fireVFX     = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx      = require(game.ServerStorage.ROWA.Modules.hitSfx)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
local Projectile  = require(game.ServerStorage.ROWA.Class.Projectile)

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

local WINDUP = 0.22
local GATHER = 0.7

-- !! FULL EXTENT, not radii: Destruction halves this itself, same trap as Armor's DIG_SIZE.
local DIG_SIZE  = Vector3.new(12, 12, 12)
local DIG_MINSZ = 3.6
-- SIX, not seven.
local GRAB_COUNT = 6

-- thrown flat and hard, then allowed to sag: an arc, not a line.
-- IT SHATTERS ON THE FIRST BODY (pierce 1), so the expiry -- burst, crater and shake -- lands ON the person hit. Ploughing through fights its own onExpire and reads as weightless.
local SPEED    = 110
local GRAVITY  = 40
local MAX_DIST = 400
local LIFETIME = 8

local function useFunc(this:myself)
	local cooldownID = "boulderKick"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Kick, 0, 1, 1)

	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		return
	end

	local forward = hurtbox.CFrame.LookVector
	local digAt = hurtbox.Position + forward * 6 + Vector3.new(0, -2, 0)

	-- DIG, THEN DECIDE: Grab carves the crater, describes the biggest cuboids that came out, and withholds them from the rubble fx so they leave the ground exactly once.
	local _, chunks = Destruction.Grab(
		nil,
		CFrame.new(digAt),
		DIG_SIZE,
		DIG_MINSZ,
		nil,
		GRAB_COUNT
	)

	if chunks == nil or #chunks == 0 then
		-- the whiff: 2s, not the full cd, and no mana spent
		if anim then anim:Stop(0.1) end
		this:triggerCD(cooldownID, 2, true)
		this:endLag(0.2)
		return
	end

	-- where the rock assembles: in front of the caster, at kicking height
	local gatherCF = CFrame.new(
		hurtbox.Position + forward * 6 + Vector3.new(0, 2, 0),
		hurtbox.Position + forward * 12)

	fireVFX("boulderKick", 1, char, chunks, GATHER, gatherCF)
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
	this:triggerCD(cooldownID, 12, true)

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
	forward = (hurtbox.CFrame.LookVector + Vector3.new(0,0.1,0)).Unit
	local originCF = CFrame.new(gatherCF.Position, gatherCF.Position + forward)

	-- built per cast because ONE field varies: the hit volume is sized off the pieces actually torn up, so a rock of big slabs hits wider than one of scraps.
	local avg = Vector3.zero
	for _, c in ipairs(chunks) do
		avg += (c.size + Vector3.new(5, 5, 5)) / 2
	end
	avg /= #chunks
	-- half the magnitude of the average piece size
	local hitSize = Vector3.one * math.clamp(avg.Magnitude * 0.5, 4, 10)

	-- !! THE PROJECTILE IS SPAWNED BEFORE THE FX: the drawn rock needs the projectile's `id` to receive a correction, and the id does not exist until it is spawned.
	local p = this:projectile(table.freeze({
		class       = Projectile.Arcing,
		speed       = SPEED,
		gravity     = GRAVITY,
		maxDistance = MAX_DIST,
		lifetime    = LIFETIME,
		size        = hitSize,
		dmgTbl      = BLDR,
		pierce      = 1,
		stopOnWorld = true,
		knockbackForce = 9.6,
		knockbackTime  = 0.2,

		onExpire = function(proj: any, pos: Vector3, _hitWorld: boolean)
			-- where it really stopped is THE ONLY THING THE CLIENTS COULD NOT PREDICT, so it is the only thing sent.
			fireVFX("boulderKick", 3, char, pos)
			-- r7 where it lands; velo is studs/SECOND, along the direction it was actually travelling
			Destruction.Sphere(nil, pos, 7, 4.2, proj.dir * 70)
			fireVFX("camShake", pos, 300, 1, 0.15)
		end,
	}), originCF)

	fireVFX("boulderKick", 2, char, originCF, SPEED, GRAVITY, MAX_DIST, LIFETIME,
		p and p.id)

	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
