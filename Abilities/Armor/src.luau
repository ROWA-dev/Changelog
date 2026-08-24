--!strict
--- Armor - rip the ground up, wear it, and shove everyone off you as it goes on.
--- rowa1 port: README.md/PORT_Armor.
--- THE ABILITY IS THE SMALL HALF: rowa1 kept the damage reduction, erosion,
--- shedding plates and blood suppression in a `hasArmor` branch inside
--- AttackModule. All of that is Class/StatusEffects/EarthArmour now.
--- HOW MUCH GROUND YOU RIP UP IS HOW MUCH ARMOUR YOU GET -- rowa1's emergent
--- `clamp(i*30, 1, 160)` made explicit, which also fixes the nil-pool case
--- when nothing underfoot is breakable.
--- The plates ARE the ground: nine real carved chunks, each keeping its own
--- colour and material. Destruction.Grab exists for this.
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

--- an ELLIPSOID, not a Sphere: rowa1's ArmorGrab flattens Y to 64% of XZ.
--- !! FULL EXTENT, NOT RADII -- Destruction halves this itself, so passing
--- radii digs a crater half the size.
local DIG_SIZE = Vector3.new(16.5, 10.5, 16.5)
--[[ Scaled off the SHORT radius (5.25*0.6), not the long one. S10.4's
	"radius * 0.6" is written for Spheres; this dig is FLATTENED, so 8.25*0.6
	would be almost the whole Y radius and subdivision terminates on the
	vertical axis immediately -- starving `destroyed` of the chunks Grab picks
	from. Bastar scales off its short axis for the same reason. ]]
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

	local SLOW_KEY = "armor"
	humObj.walkSpeed:SetMod(SLOW_KEY, -100)
	
	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		return
	end

	humObj.walkSpeed:RemoveMod(SLOW_KEY)
	
	this:useMana()
	this:triggerCD(cooldownID, 40, true)

	local origin = hurtbox.Position

	--- dig FIRST: the pieces decide how much armour there is and what colour it
	--- is, and this way the suit and the shove land together.
	--- Destruction.Grab (added for this) hands back a DESCRIPTION of `count`
	--- chunks -- size, position, colour, material -- and withholds them from dbri
	--- so they are not also drawn as ordinary rubble. DATA, NOT PARTS: server-owned
	--- parts converging for three seconds would stutter for everyone but the host.
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
