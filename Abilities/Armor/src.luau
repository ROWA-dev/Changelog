--!strict
--[[ Armor - rowa1 Items/Ability/Armor. Notes: README.md/PORT_Armor.

	Rip the ground up, wear it, and shove everyone off you as it goes on.

	THE ABILITY IS THE SMALL HALF. rowa1 put the shockwave here and the
	actual armour -- the damage reduction, the erosion, the shedding plates,
	the blood suppression -- in a ~70-line `if enemychr:HasTag("hasArmor")`
	branch inside AttackModule. All of that is
	Class/StatusEffects/EarthArmour now and the resolver is untouched.
	PORT_Armor calls this the hardest test case of README S1.2; the shape it
	lands in is the one Prediction already used.

	HOW MUCH GROUND YOU RIP UP IS HOW MUCH ARMOUR YOU GET. rowa1 set the
	pool inside the loop over broken pieces (`clamp(i*30, 1, 160)`), so
	casting on open rock gave a full suit and casting on a thin floor gave
	scraps. That reads like an accident and it is a good rule, so it is
	explicit here instead of emergent. It also fixes the degenerate case:
	with NOTHING breakable underfoot rowa1 never set the attribute at all,
	and the resolver's `hp - dmg` then ran on nil.

	THE PLATES ARE THE GROUND, which is the whole visual joke -- you are
	wearing the floor. Nine real carved chunks are torn out, blown up and
	outward, and dragged onto the rig; each one lands wearing its own colour
	and material, so grass gives you a green shoulder and the stone under it
	a grey one. Destruction.Grab exists for this; see below. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Armor",
	--[[ rowa1 `manause` 120 against a 300 pool = 40% of a bar. rowa2's
		maxMana is 100 (HumObjClient:141), so 40. README Q1 is still open on
		what the DEFAULT should be, but the ratio for an ability that
		declared one is not in question. ]]
	manaUse = 40,
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
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
local hitSfx = require(game.ServerStorage.ROWA.Modules.hitSfx)

--[[ rowa1 "knock": Heavy, blunt, 20 dmg, BOTH stuns 0, posMult 4,
	sounds{HardPunchHit}, onHit ragdtillground. It is pure shove -- no stun at
	all, so it buys space rather than a combo. 20 -> 13 on the S4.3 ratio.
	rowa2 has no `sounds` field; the row's array goes through Modules/hitSfx
	from onHit instead. ]]
local KNOCK = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 13,
	stun     = 0,
	truestun = 0,
	posMult  = 4,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit")
	end,
}

--[[ rowa1 declares Attacking.Time 0.6 and then task.waits 0.7. README 7g:
	the declared value is a CLAIM and only feeds trade logic, the wait is the
	truth. PORT_Armor step 2 says 0.6 because it read the claim. ]]
local WINDUP = 0.7

--[[ PORT_Armor's correction, and it matters: rowa1 queries a 20-cube and
	then throws away anything past 10 studs, so the real shape is a
	10-RADIUS SPHERE. Porting the box as-is would be ~3x the volume. An OBB
	cannot express a sphere, so query the box and reject the corners -- same
	technique as Blight. ]]
local BOX_SIZE  = Vector3.new(20, 20, 20)
local RADIUS    = 10
local MAX_HITS  = 10

--[[ ArmorGrab is `res13Sphere[i] * (2.2, 1.4, 2.2)`, i.e. a FLATTENED
	sphere -- Y is 64% of XZ. Sizing it off BigBreak4, which sculpts the same
	table at (8,4,8) for a documented r30 (S10.4), puts the res13 extent at
	~7.5, so ArmorGrab carves about 16.5 x 10.5 x 16.5.
	That is an ELLIPSOID, not a Sphere: S10.4 flags the flat-disc case
	(BigBreak3) as the one place Sphere is wrong, and this is the second.

	!! FULL EXTENT, NOT RADII. Destruction halves this itself
	(`radii = dimensions / 2`), and Bastar's lane is Vector3(4, 5, 12) for a
	12-stud trench. Passing radii here digs a crater half the size. ]]
local DIG_SIZE = Vector3.new(16.5, 10.5, 16.5)
--[[ Scaled off the SHORT radius, not the long one. S10.4's "radius * 0.6"
	is written for Spheres, where there is only one radius; this dig is
	deliberately FLATTENED (Y is 64% of XZ), and 8.25*0.6 = 5 is almost the
	entire 5.25 Y radius, so subdivision terminates on the vertical axis
	immediately. The carve then takes whole slabs or nothing, which starves
	`destroyed` of exactly the chunks Grab picks from -- and Grab is the
	only caller that CARES what comes out rather than what is left.
	5.25*0.6 instead. Bastar scales off its short axis for the same reason. ]]
local DIG_MINSZ = 3
--[[ NINE, not five. rowa1 selects 9 chunks spaced evenly across the break
	list and then assigns them with `armorParts[1 + i%#armorParts]` -- so
	with a five plate rig the chunks CYCLE, and most plates get struck by two
	converging pieces rather than one. That overlap is the detail: it reads
	as rubble collapsing onto you from every direction, not as five tidy
	parts sliding into slots. ]]
local GRAB_COUNT = 9

--- rowa1: clamp(chunks * 30, 1, 160) against a 160 cap. Same curve, rowa2
--- scale -- nine chunks is a full suit, exactly as it was.
local POOL_PER_PIECE = 12
local POOL_MIN, POOL_MAX = 20, 100
local ARMOUR_TIME = 30

local function useFunc(this:myself)
	local cooldownID = "armor"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local root    = humObj.HRootPart
	local anim    = this:PlayAnim(script.Anim, 0, 1, 1)

	--- the slam beat inside this lands exactly when the windup ends
	fireVFX("armorShock", root, WINDUP)

	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 40, true)

	local origin = hurtbox.Position

	--[[ Dig FIRST: the pieces decide how much armour there is, and the
		colour of it. rowa1 dug after the hitbox, but nothing reads the
		result in between and this way the suit and the shove land together.

		ANSWERING PORT_Armor step 5 / PORT_BoulderKick step 2 -- "does it
		return the pieces". It does NOW; it did not before, and the earlier
		"no" was the reason this looked nothing like rowa1. Every Destruction
		method ships `data.destroyed` -- the chunks that came OUT -- to the
		dbri client fx, which draws them locally on each machine. They never
		existed on the server, so nothing could pick one up.
		Destruction.Grab (added for this) hands back a DESCRIPTION of `count`
		of them -- size, where it was, colour, material -- and withholds
		those same cuboids from dbri so they are not also drawn falling as
		ordinary rubble. VFXQuiver/armorWear spawns them locally on each
		client and flies them on. That is what makes the armour genuinely BE
		the ground instead of a recolour of it.

		DATA, NOT PARTS, and not animated from here. rowa1's armorM ran
		entirely on the client for the same reason: anything the server owns
		and moves replicates its CFrame at the network's rate with
		interpolation on top, so nine pieces converging for up to three
		seconds would stutter for everyone except the host. ]]
	local _, chunks = Destruction.Grab(
		nil,
		CFrame.new(origin),
		DIG_SIZE,
		DIG_MINSZ,
		nil,
		GRAB_COUNT
	)

	--[[ rowa1 set the pool INSIDE the selection loop as clamp(i*30, 1, 160),
		so it was really "how many chunks did I actually get". Bare floor
		with nothing breakable under it -> scraps; open rock -> a full suit. ]]
	local pool = math.clamp(#chunks * POOL_PER_PIECE, POOL_MIN, POOL_MAX)

	humObj.statusEffects:apply(
		statusEffects.EarthArmour,
		ARMOUR_TIME,
		pool,
		chunks
	)

	fireVFX("camShake", origin, 400, 1, 0.1)

	--- query the box, then reject anything outside the real 10-stud sphere
	local _, hits = this:hitbox(
		CFrame.new(origin),
		BOX_SIZE,
		nil,
		true -- world space
	)

	local landed = 0
	for _, enemy in pairs(hits) do
		if landed >= MAX_HITS then break end

		local eroot = enemy.HRootPart
		if eroot == nil then continue end

		local offset = eroot.Position - origin
		if offset.Magnitude > RADIUS then continue end

		--[[ rowa1 aimed with CFrame.new(myPos, victimPos).LookVector, which
			is FLAT -- the constructor throws away pitch. So the shove is
			horizontal and the +8 is what lifts them. Kept, because a
			radial-in-3D version launches people standing on top of you
			straight up and nobody else at all. ]]
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local dir = if flat.Magnitude > 0 then flat.Unit else hurtbox.CFrame.LookVector

		local attack = this:makeAtk(KNOCK, enemy, dir)

		--[[ rowa1 look*40 + (0,8,0). README S7.9: a rowa1 vector K is a rowa2
			force of K*0.6 (Velocity=knock*3 vs forceVector*=5), measured,
			not eyeballed. PORT_Armor step 3 says 18 -- that predates the
			ratio and is the ~25% shortfall S7.9 warns about.
			decayT -1 for the same reason StrongLeft uses it: no linear decay,
			so there is no snap-back at the end of the shove. ]]
		attack.knockback = this:knockback(
			dir * 24 + Vector3.new(0, 5, 0),
			0.1,
			false,
			-1
		)

		this:executeAttack(attack)
		--- rowa1's row carried onHit ragdtillground
		if attack:isHit() then
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
		end
		landed += 1
	end

	--- rowa1 held Attacking for a full second after. Every shipped port
	--- lands 0.1-0.3; 0.5 keeps this a commitment without freezing you.
	this:endLag(0.5)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
