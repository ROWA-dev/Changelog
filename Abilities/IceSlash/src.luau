--!strict
--- IceSlash - throw TWO ice crescents, one off each leg. Each travels 200
--- studs/s for up to 3s, cutting through targets, DEFLECTING off blocks, and
--- shattering on the first parry or wall. rowa1 port: README.md/PORT_IceSlash
--- (which says "up to 5"; the source calls sendIceSlash twice).
--- First customer of Class/Projectile: rowa1 compared accumulated SECONDS
--- against a stud count while stepping 6.6 studs through a 4-stud box, so
--- crescents passed clean through people. The class substeps.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "IceSlash"
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
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local fireVFX    = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx     = require(game.ServerStorage.ROWA.Modules.hitSfx)

--[[ rowa1 "ice2": Medium, ice+slash, 18 dmg, truestun 0.4 / stun 1.0.
	stun cut to 0.6 because the Freeze meter now carries the control -- two
	crescents at 1.0s each would stack into a lock the meter was built to
	replace. See PORT_Freeze section 1. ]]
local ICE2 = {
	weight   = dmgUtils.weighEnum.Medium,
	type     = bit32.bor(dmgFlag.ice, dmgFlag.slash),
	dmg      = 10,
	stun     = 0.6,
	posMult  = 1,
	--parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "IceSplash2")
	end,
}

--- fill per crescent. Two clean crescents is not a freeze on its own.
local FREEZE_FILL = 2

local CRESCENT = table.freeze({
	speed       = 200,
	--- rowa1's real limit is TIME, not distance: 3 seconds at 200 studs/s.
	--- In practice a wall ends it long before either.
	lifetime    = 3,
	maxDistance = 600,
	size        = Vector3.new(9, 9, 4),
	dmgTbl      = ICE2,
	--- it shatters on the FIRST body: rowa1 carried on through four, so the
	--- shatter fx played on a crescent that was still visibly flying.
	--- A BLOCK does not consume this -- resolveHits skips the pierce decrement
	--- on a deflection, so a blocked crescent bends away with its hit intact.
	pierce      = 1,
	stopOnWorld = true,
	--- rowa1 dir*8, at the x0.6 knockback ratio (README S7)
	knockbackForce = 4.8,
	fxId        = "iceSlashProj",

	onHit = function(proj, attack)
		if attack:isHit() then
			attack.enemyEntity.statusEffects:apply(
				statusEffects.Freeze, 4, FREEZE_FILL)
			--- rowa1's "ice2" row carries onHit = ragdtillground: a 60s CAP
			--- that stopOnGround ends when they land.
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 8)
			--[[ the crescent's own Hit/Shatter sounds live on the client fx,
				and the client only sees WALLS -- so a crescent that connected
				with a PLAYER broke silently. Fired at the victim instead. ]]
			fireVFX("iceShatter", attack.enemyEntity.HRootPart)

		elseif attack:isParried() then
			--- PARRIED CRESCENTS GO HOME. rowa1 killed it silently, which is a
			--- fine reward and a boring one. parryDir is the rocket's heading
			--- blend; `newOwner` is what lets it reach the caster at all.
			--- No target: a crescent does not home.
			local eroot = attack.enemyEntity.HRootPart
			if eroot then
				fireVFX("iceShatter", eroot)
				--- rowa1's rocket blend, degeneracy handled. See parryDir.
				proj:deflect(proj:parryDir(eroot.CFrame.LookVector), nil, 0.15,
					attack.enemyEntity)
			else
				Projectile.kill(proj)
			end

		elseif attack:isBlocked() then
			--- DEFLECTION: a blocked crescent bends away along the blocker's
			--- facing rather than dying. The only mechanic of its kind here.
			--- !! :setDir, not `proj.dir =` -- velocity is the storage and `dir` a
			--- derived read, so a raw assignment is overwritten next step.
			--- NOT :deflect() -- that clears `seen`, and a crescent that forgets
			--- who it hit can re-hit the same blocker for the rest of its flight.
			local eroot = attack.enemyEntity.HRootPart
			if eroot then
				proj:setDir(proj.dir + eroot.CFrame.LookVector / 3)
			end
		end
	end,
})

local function useFunc(this:myself)
	local cooldownID = "iceSlash"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)

	--[[ hshock takes a BASEPART, not a Humanoid -- it reads .Position off it.
		rowa1's version took the Humanoid, so porting the call literally threw
		"Position is not a valid member of Humanoid". Check the rowa2 module's
		signature, not the rowa1 call site. ]]
	local leftLeg = char:FindFirstChild("Left Leg")
	fireVFX("hshock", humObj.HRootPart)
	fireVFX("icepop", leftLeg, 0.55)

	-- rowa1: 0.05 + 5 * 0.1
	if this:feintWait(0.47) then
		if anim then anim:Stop() end
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 10, true)

	--[[ the two crescents are thrown at fixed yaw offsets, -30 and +10, so
		they fan rather than overlap. The angle is purely visual -- the hit
		volume travels along the throw direction either way -- so it is
		handed to the fx and the projectile flies straight. ]]
	this:projectile(CRESCENT, hurtbox.CFrame * CFrame.new(0, 0, -4))
	fireVFX("hshock", humObj.HRootPart)

	local rightLeg = char:FindFirstChild("Right Leg")
	fireVFX("icepop", rightLeg, 0.5)

	if this:feintWait(0.5) then
		if anim then anim:Stop() end
		return
	end

	this:projectile(CRESCENT, hurtbox.CFrame * CFrame.new(0, 0, -4))

	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
