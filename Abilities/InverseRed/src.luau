--!strict
-- InverseRed - charge a red orb on your arm, then fire it flat at 800 studs/s; it sweeps for bodies and detonates on contact, a wall, or expiry.
-- the orb does NO contact damage, it is all in the blast, but it carries a zeroed dmgTbl so contact RESOLVES and can be parried.
-- THE PURPLE COMBO IS CUT, decided: FullBlue still sets PurpleReady, but nothing here reads it. If revived it goes on the FIELD, not the orb.
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

-- no sounds: the explosion is the sound.
local BLAST = table.freeze({
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 20,
	truestun = 0.2,
	stun     = 1,
	posMult  = 1,
})

-- !! contact resolves and deals nothing; a nil dmgTbl would skip entity queries entirely and fly through people.
local PROXIMITY = table.freeze({
	weight  = dmgUtils.weighEnum.Light,
	type    = dmgFlag.magic,
	dmg     = 0,
	stun    = 0,
	posMult = 0,
	-- it should be parryable in flight
	parryH  = 0.2,
})

-- centred on the impact and oriented back along the path, so it catches people the orb passed as well as the one it hit.
local BLAST_SIZE = Vector3.new(16, 16, 25)
local MAX_HITS   = 8

local function detonate(proj: any, pos: Vector3, _hitWorld: boolean)
	local action = proj.action
	if action == nil or action._humObj == nil then return end

	local dir = proj.dir

	-- !! it goes off ON THE BODY, not where the orb was: the orb's position is only where a 6-stud volume first touched a hurtbox, which lands the blast short.
	local vr = proj.victimRoot
	if vr ~= nil and vr.Parent ~= nil then pos = vr.Position end

	fireVFX("inverseRedBoom", pos, dir)

	-- bite just INSIDE the surface, or the crater eats the air in front of it. The normal only exists on a world hit.
	local origin = pos
	local wh = proj.worldHit
	if wh then origin = pos - wh.Normal end
	-- r8 is the inscribed sphere of the 16^3 cut; velo is studs/SECOND, since `dir` alone is 1 stud/s and this is a bomb.
	Destruction.Sphere(nil, origin, 8, 4.8, dir * 90)

	local _, hits = action:hitbox(CFrame.new(pos, pos + dir), BLAST_SIZE, nil, true)

	local landed = 0
	for _, enemy in pairs(hits) do
		if landed >= MAX_HITS then break end
		local eroot = enemy.HRootPart
		if eroot == nil then continue end

		local attack = action:makeAtk(BLAST, enemy, dir)
		-- the shove points the way the orb was going, away from the caster.
		attack.knockback = action:knockback(
			dir * 18 + Vector3.new(0, 1.2, 0), 0.2, false, -1)
		action:executeAttack(attack)

		if attack:isHit() then
			enemy.ragdoll:ragdoll(60, true, dir * 10)
		end
		landed += 1
	end
end

local ORB_CFG = table.freeze({
	speed       = 800,
	-- capped: at 800 studs/s an uncapped lifetime is an 8000-stud shot.
	maxDistance = 900,
	lifetime    = 2,
	-- only the cross-section is ours: the depth is the substep, which the scheduler owns.
	size        = Vector3.new(6, 6, 6),
	dmgTbl      = PROXIMITY,
	pierce      = 1,
	stopOnWorld = true,
	fxId        = "inverseRedProj",
	onExpire    = detonate,

	-- !! PARRYING IT SENDS IT BACK: without this a parried touch spends the pierce and blasts the person who read it correctly. newOwner hands the ignore over.
	onHit = function(proj: any, attack: any)
		if attack:isParried() then
			local eroot = attack.enemyEntity.HRootPart
			if eroot == nil then return end
			fireVFX("rocketDeflect", proj.pos, eroot.CFrame.LookVector)
			-- blended heading with the head-on case handled. See parryDir.
			proj:deflect(proj:parryDir(eroot.CFrame.LookVector), nil, 0.15,
				attack.enemyEntity)
			-- a deflected orb belongs to whoever it reaches next
			proj.victimRoot = nil
			return
		end

		-- stamps EVERY body the sweep touches, hit or not, so a blocked or i-framed contact still puts the blast on the person. See detonate.
		local enemy = attack.enemyEntity
		proj.victimRoot = enemy and enemy.HRootPart or nil
	end,
})

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

	-- the charge whine: sound on the ability, visuals in the quiver.
	local chargeSnd = script.particle_style_charge:Clone()
	chargeSnd.Parent = humObj.HRootPart
	chargeSnd:Play()
	game.Debris:AddItem(chargeSnd, 4)

	-- the orb leaves along the root's facing, so without this an air cast fires along whatever heading the jump had. No-ops grounded.
	local releaseAir = aerialAim(humObj, WINDUP + 0.5)

	if this:feintWait(WINDUP) then
		if anim then anim:Stop(0.1) end
		releaseAir()
		-- or the orb hangs off the arm forever
		fireVFX("inverseRedCharge", 0, rightArm)
		-- and the whine outlasts the orb it belongs to
		game.Debris:AddItem(chargeSnd, 0)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 16, true)

	local originCF = hurtbox.CFrame * CFrame.new(0, 0, -3)
	-- consume the charge: the release pop, then the orb is the projectile's
	fireVFX("inverseRedCharge", 2, rightArm)
	fireVFX("camShake", hurtbox.Position, 300, 1, 0.2)

	this:projectile(ORB_CFG, originCF)

	-- after the shot, not before: the aim is read off the root and the client takes a frame to drop the gyro.
	releaseAir()

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
