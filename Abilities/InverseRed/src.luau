--!strict
--[[ InverseRed - rowa1 Items/Ability/InverseRed. Notes: README.md/PORT_InverseRed.

	Charge a red orb on your arm, then fire it flat out. It sweeps for bodies
	the whole way, and on contact -- or a wall, or expiry -- it detonates
	down the line it travelled.

	IT WAS NEVER UNFINISHED. Three port docs wrote this ability and its two
	siblings off as "spectacle present, mechanics absent". They had only read
	the aEvent, which is the CHARGE and nothing else; its last line is
	`rocket.Active.Value = true`, handing off to a 157-line Script parented to
	the orb Part itself. That Script is the ability. The tell was sitting in
	the aEvent the whole time -- it requires AttackModule, Knockback and
	RegModule and calls none of them. See PORT_InverseRed CORRECTION 2.

	SUBSTEPPING IS THE WHOLE REASON THIS PORTS CLEANLY. At 800 studs/s a
	single 30fps frame is 26 studs, and the hit volume is 6 -- so rowa1 could
	only make it work by raycasting from `last` to the new position every
	frame and running a swept box beside it, by hand, in a Script attached to
	a moving Part. Class/Projectile already does exactly that, correctly, for
	every projectile in the game. This ability is ~90 lines because of it.

	THE ORB DOES NO CONTACT DAMAGE. rowa1's swept box only ever set
	`triggerExplode`; every point of damage is in the blast. Identical shape
	to RPG, and it carries a zeroed dmgTbl for the identical reason -- contact
	still has to RESOLVE so it can be parried and so iframes are respected.

	THE PURPLE COMBO IS CUT -- DECIDED, do not build it. rowa1's orb checks
	every part it sweeps for a `MaxBlue` -- FullBlue's field -- carrying a
	`PurpleReady` attribute, and triggers a 2.2s delayed 95-radius nuke on
	the `purple` dmgID.

	FullBlue (id 41) still SETS that attribute and that is fine: the field
	owns the flag and setting it costs nothing. But the detonation half --
	the `purple` dmgTbl, Destruction's PurpleNukeBreak equivalent, the
	"purpNuke" fx and the corpse-vanish -- is NOT being ported.

	So there is deliberately NO branch here looking for the flag. That is
	the correct end state, not an unfinished one: a branch that finds a flag
	and then does nothing is worse than no branch. If it is ever revived it
	goes on the FIELD, not the orb -- FullBlue already owns the flag, already
	runs a loop and already knows where it is. README S8 Tier D. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "InverseRed",
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
local fireVFX    = require(game.ServerStorage.ROWA.Modules.fireVFX)
local aerialAim  = require(game.ServerStorage.ROWA.Modules.aerialAim)
local Projectile = require(game.ServerStorage.ROWA.Class.Projectile)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

--[[ rowa1 `reverseRed` (DMGS:984): Heavy, magic, 40 dmg with its own comment
	"nerfed from 50 to 40", truestun 0.2, stun 1, posMult 0.5, ragdtillground
	and an EMPTY sounds{} -- the explosion is the sound. 40 -> 24 on the S4.3
	ratio; the stun values carry over unchanged. ]]
local BLAST = table.freeze({
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 24,
	truestun = 0.2,
	stun     = 1,
	posMult  = 0.5,
})

--[[ Contact resolves and deals nothing; `pierce = 1` turns the first touch
	into an expiry, which is how rowa1's `triggerExplode` behaved. A nil
	dmgTbl would make the base skip entity queries and the orb would fly
	straight through people. See RPG's PROXIMITY for the same reasoning. ]]
local PROXIMITY = table.freeze({
	weight  = dmgUtils.weighEnum.Light,
	type    = dmgFlag.magic,
	dmg     = 0,
	stun    = 0,
	posMult = 0,
	--- it should be parryable in flight
	parryH  = 0.2,
})

--[[ rowa1's AoE is RegModule.Box(CFrame.new(hitPos, last), (16,16,25)) --
	CENTRED on the impact and oriented back along the path, so it catches
	people the orb passed as well as the one it hit. Cap 8. ]]
local BLAST_SIZE = Vector3.new(16, 16, 25)
local MAX_HITS   = 8

local function detonate(proj: any, pos: Vector3, _hitWorld: boolean)
	local action = proj.action
	if action == nil or action._humObj == nil then return end

	local dir = proj.dir
	fireVFX("inverseRedBoom", pos, dir)

	--[[ rowa1 broke at `hitPos - norm`, i.e. just INSIDE the surface it hit,
		so the crater bites the wall instead of the air in front of it. That
		normal only exists on a world hit -- rowa1 would have thrown on a
		body hit if it ever reached here with nil, which it could. ]]
	local origin = pos
	local wh = proj.worldHit
	if wh then origin = pos - wh.Normal end
	--- rowa1 BigBreak cuts with a 16^3 cube; r8 is its inscribed sphere (S10.4)
	--- studs/SECOND, not a heading. `dir` alone is 1 stud/s; this is a bomb.
	Destruction.Sphere(nil, origin, 8, 4.8, dir * 90)

	local _, hits = action:hitbox(CFrame.new(pos, pos + dir), BLAST_SIZE, nil, true)

	local landed = 0
	for _, enemy in pairs(hits) do
		if landed >= MAX_HITS then break end
		local eroot = enemy.HRootPart
		if eroot == nil then continue end

		local attack = action:makeAtk(BLAST, enemy, dir)
		--[[ rowa1 `rDir*-30 + (0,2,0)`. `rDir` is the NEGATED facing it flew
			with, so the double negative means the shove points the way the
			orb was going -- away from the caster. Port the motion, not the
			signs. x0.6 to rowa2 force units (README S7.9). ]]
		attack.knockback = action:knockback(
			dir * 18 + Vector3.new(0, 1.2, 0), 0.2, false, -1)
		action:executeAttack(attack)

		--- rowa1's row carried onHit ragdtillground
		if attack:isHit() then
			enemy.ragdoll:ragdoll(60, true, dir * 10)
		end
		landed += 1
	end
end

local ORB_CFG = table.freeze({
	speed       = 800,
	--[[ rowa1 set NO distance cap and a 10 second lifetime -- at 800 studs/s
		that is an eight THOUSAND stud shot that is still live ten seconds
		later. Capped the same way RPG's 30s was. ]]
	maxDistance = 900,
	lifetime    = 2,
	--- rowa1 swept a (6,6,dt*speed) box; the depth WAS the substep, which is
	--- the scheduler's job now, so only the cross-section is ours.
	size        = Vector3.new(6, 6, 6),
	dmgTbl      = PROXIMITY,
	pierce      = 1,
	stopOnWorld = true,
	fxId        = "inverseRedProj",
	onExpire    = detonate,

	--[[ PARRYING IT SENDS IT BACK. It used to DETONATE ON THE PARRIER: the
		orb carries a 0-damage proximity table whose only job is to be
		parryable, and with no onHit a parried touch still spent its single
		pierce, expired, and ran the 16x16x25 blast centred on the person who
		had just read it correctly. The parry reward was a bomb in the face.

		RPG's redirect formula, the same one IceSlash now uses: it leaves
		along the PARRIER's facing, and `newOwner` hands the ignore over so
		the thing can actually reach the person who fired it -- without that
		it flies home and passes straight through them.

		Deflecting does NOT consume pierce (resolveHits skips the decrement
		when `deflected` is set), so the orb survives to detonate wherever it
		ends up, which is the entire point. ]]
	onHit = function(proj: any, attack: any)
		if not attack:isParried() then return end
		local eroot = attack.enemyEntity.HRootPart
		if eroot == nil then return end
		fireVFX("rocketDeflect", proj.pos, eroot.CFrame.LookVector)
		--- rowa1's rocket blend, degeneracy handled. See parryDir.
		proj:deflect(proj:parryDir(eroot.CFrame.LookVector), nil, 0.15,
			attack.enemyEntity)
	end,
})

--- rowa1: 0.1 before committing, then 0.2 + 6x0.1. The DECLARED
--- Attacking.Time is 0.7 and is a claim; 0.8 is the truth (README 7g).
local WINDUP = 0.8

local function useFunc(this:myself)
	local cooldownID = "inverseRed"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Punch, 0, 1, 1)

	local rightArm = char:FindFirstChild("Right Arm")
	fireVFX("inverseRedCharge", 1, rightArm, WINDUP)

	--[[ the charge whine. rowa1 clones particle_style_charge onto the root in
		the same breath as the orb and kills it (Debris 0) the moment the
		cast is interrupted -- the orb spinning up silently was the tell that
		this had been dropped. Server-side and not in inverseRedCharge
		because that is how every other charge in rowa2 does it: StrongLeft,
		StrongerLeft and LionFall all keep the sound on the ability and the
		visuals in the quiver. ]]
	local chargeSnd = script.particle_style_charge:Clone()
	chargeSnd.Parent = humObj.HRootPart
	chargeSnd:Play()
	game.Debris:AddItem(chargeSnd, 4)

	--[[ AERIAL AIM (Modules/aerialAim). rowa1 hovers the caster for the
		charge when they are already airborne, and it matters more here than
		anywhere: the orb leaves at 800 studs/s along the root's facing, so
		without it an air cast fires along whatever heading the jump had.
		No-ops on the ground. ]]
	local releaseAir = aerialAim(humObj, WINDUP + 0.5)

	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		releaseAir()
		--- or the orb hangs off the arm forever
		fireVFX("inverseRedCharge", 0, rightArm)
		--- and the whine outlasts the orb it belongs to (rowa1 bins it here)
		game.Debris:AddItem(chargeSnd, 0)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 16, true)

	local originCF = hurtbox.CFrame * CFrame.new(0, 0, -3)
	--- consume the charge: the release pop, then the orb is the projectile's
	fireVFX("inverseRedCharge", 2, rightArm)
	fireVFX("camShake", hurtbox.Position, 300, 1, 0.2)

	this:projectile(ORB_CFG, originCF)

	--[[ rowa1 releases at the end of the charge loop, one line BEFORE it
		builds the shot. Released after instead, which is the same moment to
		the player and removes a frame race: the aim is read off the root
		here, and rowa1 only got away with reading it post-release because
		the client takes a frame to drop the gyro. ]]
	releaseAir()

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
