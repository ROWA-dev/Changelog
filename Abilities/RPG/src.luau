--!strict
--[[ RPG - rowa1 Items/Ability/RPG. Notes: README.md/PORT_RPG.

	Shoulder a launcher, fire one homing rocket. Joke ultimate, and the
	cleanest possible demonstration of why Class/Projectile exists.

	!! THE ABILITY FILE IS NOT WHERE THE MOVE LIVED.
	rowa1's aEvent is a SPAWNER: it clones ServerStorage.Effects.Rocket into
	workspace.Effects and sets two ObjectValues on it. The rocket's homing,
	collision, damage and explosion are a 130-line Script PARENTED TO THE
	PART -- one running script per rocket, all its state in upvalues, no
	shared fix path. That pattern is exactly what rowa2 exists to delete, so
	the whole thing is a config here.

	The PARRY REDIRECT survived and is the best thing in the original: a
	rocket parried at the right moment is knocked off course and re-acquires
	someone else instead of exploding. That is now BaseProjectile:deflect,
	shared with IceSlash. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "RPG"
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
local Projectile = require(game.ServerStorage.ROWA.Class.Projectile)
local Targeting  = require(game.ServerStorage.ROWA.Modules.Targeting)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)
local fireVFX    = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx     = require(game.ServerStorage.ROWA.Modules.hitSfx)

--[[ rowa1 "rocket": Heavy, magic, 40 dmg (its own comment says "nerfed from
	50"), truestun 1 / stun 1.6, posMult 1, onHit ragdtillground. ]]
local ROCKET = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 26,
	stun     = 1.6,
	posMult  = 1,
	--[[ a homing rocket with no travel counterplay is not a fun ranged
		option. rowa1's out was the parry redirect; dodgeH gives a second. ]]
	dodgeH   = 0.15,
	parryH   = 0.1,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HardPunchHit")
	end,
}

local BLAST_RADIUS = 12
local TARGET_RANGE = 200
--[[ rowa1 used GetNearestInDirection2 with its DEFAULT maxstAngle of 0.4 rad
	(~23 degrees) -- a rocket only locks onto something you are genuinely
	pointing at, which is much tighter than the soft cone. ]]
local ROCKET_CONE = table.freeze({ distWeight = 10, maxAngle = 0.4 })

--- the AoE the rocket leaves behind. Runs on the projectile's owner.
local function detonate(proj: any, pos: Vector3, _hitWorld: boolean)
	local action = proj.action
	if action == nil or action._humObj == nil then return end

	fireVFX("rocketBoom", pos)
	--- rowa1 BigBreak cut with a 16^3 cube; r8 is its inscribed sphere
	--- studs/SECOND: `proj.dir` is a unit heading and moved nothing
	Destruction.Sphere(nil, pos, 8, 4.8, proj.dir * 90)

	local _, hits = action:hitbox(
		CFrame.new(pos), Vector3.one * (BLAST_RADIUS * 2), nil, true)

	--[[ !! AND THE OWNER, ADDED BY HAND, BECAUSE ROWA1'S BLAST HAS NO OWNER
		CHECK AT ALL:
		    local Stuff2 = RegModule.Box(CFrame.new(endp, last), (12,12,12))
		    for i,v in pairs(Stuff2) do
		        if v.Parent and v.Parent:FindFirstChild("Humanoid")
		            and not table.find(humsH2, v.Parent) then
		Compare InverseRed and PaperBomb, which BOTH carry an explicit
		`v.Parent ~= owner` on the same loop. The rocket does not, and it is
		not an oversight there either: the flight sweep has no owner check
		either, only a 0.05s arming delay (`st = tick() + 0.05`), i.e. the
		rocket is armed against EVERYONE including you the moment it clears
		the launcher. Blowing yourself up with the joke ultimate is the joke.

		It has to be added by hand because HitboxQuery ignores the caster's
		Humanoid on every query in the game (`toIgnore = humObj.Hum`), which
		is correct for every attack except a bomb. Doing it here rather than
		with a new query flag keeps that guarantee intact for everything
		else -- this is the only projectile in the game that wants it.

		The radius reject below still applies, so this is only ever an owner
		genuinely INSIDE their own explosion.

		!! WATCH THE RADIUS. rowa1's box is a TWELVE STUD CUBE -- (12,12,12)
		into GetPartBoundsInBox is a full size, so its blast reaches 6 studs,
		not 12. BLAST_RADIUS here is 12, which is double the original in
		every direction, and it now applies to YOU as well. If the RPG starts
		killing its own user from across the room that number is why, and
		6 is what the original actually was. Left alone because it is a
		balance call, not a port bug to fix silently. ]]
	local me = action._humObj
	if me ~= nil then table.insert(hits, me) end

	for _, enemy in pairs(hits) do
		local eroot = enemy.HRootPart
		if eroot == nil then continue end
		--- the query is an OBB, the blast is a SPHERE. Reject the corners.
		local offset = eroot.Position - pos
		if offset.Magnitude > BLAST_RADIUS then continue end

		local dir = if offset.Magnitude > 0 then offset.Unit else proj.dir
		local attack = action:makeAtk(ROCKET, enemy, dir)
		-- rowa1 look*30 + (0,8,0), at the x0.6 knockback ratio (README S7)
		attack.knockback = action:knockback(
			dir * 18 + Vector3.new(0, 4.8, 0), 0.2, false, -1)
		action:executeAttack(attack)

		if attack:isHit() then
			enemy.ragdoll:ragdoll(60, true, dir * 10)
		end
	end
end

--[[ THE ROCKET DOES NO CONTACT DAMAGE -- the explosion is the whole payload,
	exactly as in rowa1 where touching someone only set `triggerExplode`.

	But it still has to NOTICE people, and it has to be PARRYABLE, and both
	of those mean going through the attack pipeline. So it carries a real
	damage table with everything zeroed: contact resolves, deals nothing, and
	its onHit converts the touch into an expiry. A dmgTbl of nil would make
	the base skip entity queries entirely and the rocket would fly straight
	through its target. ]]
local PROXIMITY = table.freeze({
	weight  = dmgUtils.weighEnum.Light,
	type    = dmgFlag.magic,
	dmg     = 0,
	stun    = 0,
	posMult = 0,
	--- a parry must be able to reach it; that is the redirect window
	parryH  = 0.2,
})

local ROCKET_CFG = table.freeze({
	class       = Projectile.Homing,
	speed       = 200,
	maxDistance = 1200,
	--- rowa1 gave it 30 seconds. Cut hard: a rocket still circling half a
	--- minute later is a bug report waiting to happen.
	lifetime    = 6,
	size        = Vector3.new(4, 4, 12),
	--[[ rowa1 steered by adding lookToTarget/16 to the facing every frame --
		a framerate-DEPENDENT nudge. Expressed as a rate it flies the same at
		30fps and at 144.

		3.75, NOT 2.5. Measure the original instead of calling it "lazy":
		adding a unit vector scaled 1/16 to a unit facing and renormalising
		turns you by atan(1/16) = 3.58 degrees per FRAME, and rowa1 ran that
		off RenderStepped, so at the 60fps it was played at the rocket turned
		~215 deg/s = 3.75 rad/s. 2.5 is a third slower than the move has ever
		been, which is why the homing "felt different" -- it was. ]]
	steer       = 3.75,
	dmgTbl      = PROXIMITY,
	pierce      = 1,
	stopOnWorld = true,
	fxId        = "rocketProj",

	onHit = function(proj, attack)
		--[[ THE PARRY REDIRECT. rowa1 checked ParryWindow > 0.2 directly on
			the victim's Block value; here the resolver has already decided,
			so `isParried` is the same question asked properly.
			The rocket bounces off the parrier's facing and hunts whoever
			THEY were looking at. ]]
		if attack:isParried() then
			local eroot = attack.enemyEntity.HRootPart
			if eroot == nil then return end
			--[[ rowa1's own blend for this exact case (rocket:61): current
				heading + the parrier's facing + a lift. On a head-on parry
				those cancel and it fires almost straight up -- which rowa1
				gets away with because the re-target below takes over within
				a frame. parryDir keeps the blend and handles that collapse. ]]
			local look = eroot.CFrame.LookVector
			local newDir = proj:parryDir(look)
			--[[ the SEARCH uses the raw facing, not the blended heading.
				rowa1 does the same (GetNearestInDirection takes the
				parrier's LookVector) and it matters: the blend carries a
				lift and half the incoming heading, so searching along it
				aims the cone at the sky and picks whoever the parrier is
				NOT looking at. Where it flies and who it hunts are two
				different questions. ]]
			local newTarget = Targeting.nearestInDirection(
				eroot.Position, look, attack.enemyEntity, TARGET_RANGE, ROCKET_CONE)
			fireVFX("rocketDeflect", proj.pos, newDir)
			--[[ the fourth argument is not cosmetic: HitboxQuery ignores the
				projectile's owner, so until now a redirected rocket that
				re-acquired the ORIGINAL CASTER flew home and passed straight
				through them. "The best thing in the original" could not
				actually pay out against the person who fired it. Handing the
				parrier over moves the ignore onto them instead. ]]
			proj:deflect(newDir, newTarget, 0.15, attack.enemyEntity)
			return
		end

		--- anything else it touches sets it off
		Projectile.kill(proj)
	end,

	onExpire = detonate,
})

local function useFunc(this:myself)
	local cooldownID = "rpg"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Punch, 0, 1, 1)

	local rightArm = char:FindFirstChild("Right Arm")
	fireVFX("rpgLauncher", rightArm, 1.4)

	if this:feintWait(0.72) then
		if anim then anim:Stop() end
		fireVFX("rpgLauncher", nil, 0) -- tell the client to bin it early
		return
	end

	--[[ rowa1 took the cooldown BEFORE the windup, so a feinted RPG still
		burned all 18 seconds. Same bug Blight had. Ported correctly. ]]
	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	local target = Targeting.nearestInDirection(
		hurtbox.Position, hurtbox.CFrame.LookVector, humObj, TARGET_RANGE,
		ROCKET_CONE)

	--[[ the config is frozen and shared, so the per-cast target goes on a
		clone. `target` is the only field that varies per shot. ]]
	local cfg = table.clone(ROCKET_CFG)
	cfg.target = target

	this:projectile(table.freeze(cfg), hurtbox.CFrame * CFrame.new(1, 1, -3))

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
