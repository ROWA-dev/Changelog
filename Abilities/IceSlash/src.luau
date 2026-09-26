--!strict
--- IceSlash - throw TWO ice crescents, one off each leg. Each travels 200
--- studs/s for up to 3s, cutting through targets, DEFLECTING off blocks, and
--- shattering on the first parry or wall.
--- First customer of Class/Projectile, which SUBSTEPS -- stepping 6.6 studs
--- through a 4-stud box at once is how crescents pass clean through people.
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
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local fireVFX    = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx     = require(game.ServerStorage.ROWA.Modules.hitSfx)

--[[ stun is 0.6, not the 1.0 a hit this size would take: the Freeze meter
	carries the control now, and two crescents at 1.0s each would stack into
	the lock the meter was built to replace. ]]
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
	--- the real limit is TIME, not distance: 3 seconds at 200 studs/s. In
	--- practice a wall ends it long before either.
	lifetime    = 3,
	maxDistance = 600,
	size        = Vector3.new(9, 9, 4),
	dmgTbl      = ICE2,
	--- it shatters on the FIRST body, so the shatter fx never plays on a
	--- crescent that is still visibly flying.
	--- a block deflects, which refunds the pierce, so a blocked crescent bends away with its hit intact.
	pierce      = 1,
	stopOnWorld = true,
	knockbackForce = 4.8,
	fxId        = "iceSlashProj",

	onHit = function(proj, attack)
		if attack:isHit() then
			attack.enemyEntity.statusEffects:apply(
				statusEffects.Freeze, 4, FREEZE_FILL)
			--- a 60s CAP that stopOnGround ends when they land.
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 8)
			--- NO iceShatter here: the death carries `hitBody` now, so iceSlashProj plays that same shatter itself, where the server stopped.

		elseif attack:isParried() then
			--- parried crescents go home
			local eroot = attack.enemyEntity.HRootPart
			if eroot then fireVFX("iceShatter", eroot) end
			proj:parryHome(attack.enemyEntity)

		elseif attack:isBlocked() then
			--- bends off the guard and flies on, hit intact; the grace outlasts the pass through the blocker, so the cleared `seen` can't re-hit them
			local eroot = attack.enemyEntity.HRootPart
			if eroot then proj:deflect(proj.dir + eroot.CFrame.LookVector / 3, nil, 0.15) end
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

	--- hshock takes a BASEPART, not a Humanoid -- it reads .Position off it.
	local leftLeg = char:FindFirstChild("Left Leg")
	fireVFX("hshock", humObj.HRootPart)
	fireVFX("icepop", leftLeg, 0.55)

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
