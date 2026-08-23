--!strict
--- BoulderKick - rip a chunk of the actual MAP out of the ground and punt it at
--- someone. rowa1 port: README.md/PORT_BoulderKick, PLAN_PROJECTILE.
--- The doc said to CUT this; the blocker was that rowa2's Destruction returned
--- nothing. Destruction.Grab (added for Armor) closes it, so this throws the
--- ground it actually dug up, at its real size, colour and material.
--- NOT ported: rowa1's flying assembly of six unanchored network-owned terrain
--- parts (PLAN_PROJECTILE 3.1 refuses exactly that). Server runs Arcing math
--- and owns no Instance. rowa1 ground a trench as the rock flew; ours carves
--- where it lands.
--- FIZZLE IS A FEATURE: no breakable underfoot means a 2s cooldown instead of
--- 12. The only ability in the game that reads the map before it commits.
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

--[[ rowa1 "bldr": Heavy, blunt+earth, 45 dmg, truestun 0.4 / stun 0.6,
	posMult 3, onHit ragdtillground, sounds HitCrush + Smash.
	45 -> 29 on the same ratio StoneBall's neighbouring "bldr2" row took
	(40 -> 26), which is also what the port doc predicted. ]]
local BLDR = table.freeze({
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.blunt, dmgFlag.earth),
	dmg      = 29,
	stun     = 0.6,
	posMult  = 3,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HitCrush")
		--- rowa1's row carries ragdtillground: a long CAP, ended by landing
		attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
	end,
})

--- rowa1 Attacking.Time 0.7; its waits are 0.3 to the dig, 0.5 to the kick
local WINDUP = 0.22
local GATHER = 0.7

--[[ BoulderGrab cuts THREE overlapping boxes at 1.5 x smallBreakSizes --
	(12,6,6), (6,12,6), (6,6,12) -- a three-axis star centred 6 studs ahead
	and 2 down. The union of that star is about a 12-stud blob, so: 12 FULL
	EXTENT (Destruction halves it itself -- see Armor's DIG_SIZE note, this
	is the same trap), and minSz off the 6 radius at S10.4's 0.6. ]]
local DIG_SIZE  = Vector3.new(12, 12, 12)
local DIG_MINSZ = 3.6
--[[ SIX. rowa1 writes `if count < 7` over a 1-based counter, so it keeps
	1..6 and breaks on the seventh. Not seven. ]]
local GRAB_COUNT = 6

--- rowa1 threw flat and hard at look*160 and let it sag -- an arc, not a line.
--- 110/40 keeps that read at rowa2's shorter ranges.
--- IT SHATTERS ON THE FIRST BODY: pierce 1 so the expiry -- burst, crater and
--- shake -- lands ON the person hit. rowa1 ploughed through the first victim,
--- which fights its own onExpire and reads as weightless.
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

	--[[ DIG, THEN DECIDE. Grab both carves the crater and hands back a
		description of the biggest `count` cuboids that came out -- size,
		where it was, colour, material -- and withholds those same cuboids
		from the dbri rubble fx so they are not ALSO drawn tumbling away as
		ordinary debris. They leave the ground exactly once, in our hands. ]]
	local _, chunks = Destruction.Grab(
		nil,
		CFrame.new(digAt),
		DIG_SIZE,
		DIG_MINSZ,
		nil,
		GRAB_COUNT
	)

	if chunks == nil or #chunks == 0 then
		--- rowa1's whiff: 2s, not the full cd, and no mana spent
		if anim then anim:Stop(0.1) end
		this:triggerCD(cooldownID, 2, true)
		this:endLag(0.2)
		return
	end

	--- where the rock assembles: in front of the caster, at kicking height
	local gatherCF = CFrame.new(
		hurtbox.Position + forward * 6 + Vector3.new(0, 2, 0),
		hurtbox.Position + forward * 12)

	fireVFX("boulderKick", 1, char, chunks, GATHER, gatherCF)
	--- rowa1's telegraph: the kicking leg glows red for the whole gather
	local leftLeg = char:FindFirstChild("Left Leg")
	if leftLeg then
		fireVFX("partOutline", leftLeg, Color3.fromRGB(255, 0, 0), GATHER + 0.2)
	end

	if this:feintWait(GATHER) then
		if anim then anim:Stop(0.1) end
		--- rowa1 LEAKED the half-lifted terrain here. Ours is client-drawn,
		--- so calling it off actually calls it off (PORT step 5).
		fireVFX("boulderKick", 0, char)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	local snd = script.kicksound:Clone()
	snd.Parent = humObj.HRootPart
	snd:Play()
	game.Debris:AddItem(snd, 6)

	--- rowa1's kick ring: 7 x 7 x 0.5 at 0.9, four studs ahead, WITH boom
	local ringAt = hurtbox.Position + forward * 4
	fireVFX("shockRing",
		CFrame.new(ringAt, ringAt + forward * 6),
		Vector3.new(7, 7, 0.5), 0.9, true)

	--- re-read: the caster may have turned during the gather
	forward = (hurtbox.CFrame.LookVector + Vector3.new(0,0.1,0)).Unit
	local originCF = CFrame.new(gatherCF.Position, gatherCF.Position + forward)

	--[[ built per cast, not frozen at module scope like every other config in
		the port, because ONE field genuinely varies: rowa1 sizes the hit
		volume off `averageSize` of the pieces it actually tore up, so a rock
		made of big slabs hits wider than a rock made of scraps. Everything
		else is the frozen constants above. ]]
	local avg = Vector3.zero
	for _, c in ipairs(chunks) do
		avg += (c.size + Vector3.new(5, 5, 5)) / 2
	end
	avg /= #chunks
	--- rowa1's hit volume is (0.5,0.5,0.5) * magnitude(averageSize)
	local hitSize = Vector3.one * math.clamp(avg.Magnitude * 0.5, 4, 10)

	fireVFX("boulderKick", 2, char, originCF, SPEED, GRAVITY, MAX_DIST, LIFETIME)

	this:projectile(table.freeze({
		class       = Projectile.Arcing,
		speed       = SPEED,
		gravity     = GRAVITY,
		maxDistance = MAX_DIST,
		lifetime    = LIFETIME,
		size        = hitSize,
		dmgTbl      = BLDR,
		pierce      = 1,
		stopOnWorld = true,
		--- rowa1 Knockback(main.Velocity.Unit * 16), at the x0.6 ratio (S7)
		knockbackForce = 9.6,
		knockbackTime  = 0.2,

		onExpire = function(proj: any, pos: Vector3, _hitWorld: boolean)
			--[[ THE ONLY THING THE CLIENTS COULD NOT PREDICT is where it
				really stopped, so it is the only thing sent. Stage 3 parks
				the drawn rock at `pos` and bursts it there. ]]
			fireVFX("boulderKick", 3, char, pos)
			--- rowa1's commented-out BigBreak, honoured: r7 where it lands
			--- studs/SECOND, along the direction it was actually travelling
			Destruction.Sphere(nil, pos, 7, 4.2, proj.dir * 70)
			fireVFX("camShake", pos, 300, 1, 0.15)
		end,
	}), originCF)

	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
