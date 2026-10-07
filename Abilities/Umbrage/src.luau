--!strict
--- Umbrage - lock on within 100 studs, sink into shadow and ride a homing projectile onto them as a wraith, burst out where it lands.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Umbrage"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local dmgUtils  = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag   = dmgUtils.dmgFlags
local Targeting = require(game.ServerStorage.ROWA.Modules.Targeting)
local fireVFX   = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx    = require(game.ServerStorage.ROWA.Modules.hitSfx)
local pinTo     = require(game.ServerStorage.ROWA.Modules.pinTo)

local DIVE = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.shadow,
	dmg      = 8,
	stun     = 1,
	posMult  = 2,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "SuffocationHit")
	end,
}

--- a shadow cut on the held target; 8 + 6 x 2 keeps the old 20 dmg and 40 posture, so a held block gets chewed. A parry ends the flurry instead of punishing per cut.
local CUT = {
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.shadow,
	dmg      = 2,
	stun     = 0.6,
	posMult  = 2,
	stunMeOnParried = 0,
}

--- SOFT weighting, so any direction inside RANGE (facing preferred), but never through a wall.
local LOCK     = table.freeze({ distWeight = 10, requireLOS = true }) :: Targeting.opts
local RANGE    = 100
local WINDUP   = 0.4 -- the anim's lean lands at 0.43
local SPEED    = 140
local TRAVEL   = RANGE / SPEED + 0.6 -- slack for the homing curve, a runner, and a loop-back after a dodge
local CD       = 12
local WHIFF_CD = 2
--- the pin outlives the hit this long, so the dive's momentum dies where it landed
local BRAKE    = 0.15
local CUTS     = 6
local CUT_GAP  = 0.1
--- how far the shadow lifts them while it cuts
local LIFT     = 1.5

--- the dive IS a projectile: it owns the hit (first body it touches, dodges pass through), the caster just rides it
local PROJ = table.freeze({
	speed          = SPEED,
	steer          = 8,
	lifetime       = TRAVEL,
	maxDistance    = SPEED * TRAVEL,
	--- thin on Z: hurtboxes are 4 deep, so it lands ~2.5 studs out, body on body
	size           = Vector3.new(3, 4, 1),
	dmgTbl         = DIVE,
	--- the one it locked is seized for the cuts; anyone else in the way is bowled over
	onHit = function(proj, attack)
		local enemy = attack.enemyEntity
		--- a dodge only buys its i-frames: once they're spent the dive can loop back and take them
		if attack:isDodged() then
			task.delay(enemy.dodgeWindow, function() proj.seen[enemy.entityId] = nil end)
		elseif enemy == proj.target then
			proj.seized = attack:isHit() or attack:isBlocked()
		elseif attack:isHit() then
			enemy:bodyForce(proj.dir * 12, 0.2)
			enemy.ragdoll:ragdoll(60, true, proj.dir * 10)
		end
	end,
})

--- turn `char`, standing at `at`, to face `them` on the flat
local function face(char: any, at: Vector3, them: Vector3)
	local flat = (them - at) * Vector3.new(1, 0, 1)
	if flat.Magnitude > 0 then char:PivotTo(CFrame.lookAt(at, at + flat)) end
end

local function useFunc(this:myself)
	local cooldownID = "umbrage"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent

	local target = Targeting.nearestInDirection(
		hurtbox.Position, hurtbox.CFrame.LookVector, humObj, RANGE, LOCK)
	local myRoot = humObj.HRootPart
	if target == nil or myRoot == nil then
		this:triggerCD(cooldownID, WHIFF_CD, true)
		return
	end
	local eroot = target.HRootPart

	--- the lean reads toward who it locked, even someone behind you
	face(char, myRoot.Position, eroot.Position)
	local anim = this:PlayAnim(script.Anim, 0.05, 1, 1)
	local function stop()
		if anim then anim:Stop(0.15) end
		fireVFX("umbrage", 2, char, 0)
	end

	fireVFX("umbrage", 1, char, eroot, this:scaledTime(WINDUP))

	if this:feintWait(WINDUP) then
		stop()
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, CD)

	local p = this:projectile(PROJ, CFrame.lookAt(myRoot.Position, eroot.Position))
	if p == nil then stop() return end
	p.target = target

	--- the anim ends at 1s; slowed, its held dive covers the whole flight
	if anim then anim:AdjustSpeed(0.5) end
	fireVFX("phantom", char)
	fireVFX("umbrage", 2, char, TRAVEL)

	--- the speed cap lets the owner's physics fly the gaps between replicated positions
	local unpin = pinTo(myRoot, function() return p.pos end,
		{ maxTime = TRAVEL + CUTS * CUT_GAP + 0.3, responsiveness = 200, maxSpeed = SPEED * 1.25 })

	while not p.dead do
		task.wait()
		if this:channelBreak() then
			p:drop()
			unpin()
			stop()
			return
		end
	end
	face(char, p.pos, eroot.Position)
	if anim then anim:Stop(0.1) end
	fireVFX("umbrage", 3, char, p.pos)

	if p.seized ~= true then
		task.delay(BRAKE, unpin)
		this:endLag(0.3)
		return
	end

	--- seized: the shadow holds them up in front of you and cuts; you stay planted until it lets go
	local hold = eroot.Position + Vector3.new(0, LIFT, 0)
	local grab = this:PlayAnim(script.Grab, 0.05, 1, 1)
	local release = pinTo(eroot, function() return hold end, { maxTime = CUTS * CUT_GAP + 0.3 })
	local letGo = false
	for i = 1, CUTS do
		task.wait(CUT_GAP)
		--- a clean hold lets the anim play out; a broken one cuts it
		if letGo or this:channelBreak() or target.isActive ~= true then
			if grab then grab:Stop(0.15) end
			break
		end
		fireVFX("umbrage", 4, target.Model, i == CUTS)
		--- spawned: ping compensation can hold an execute, and that must not stretch the cadence
		task.spawn(function()
			local attack = this:makeAtk(CUT, target, (eroot.Position - myRoot.Position).Unit)
			this:executeAttack(attack)
			if attack:isParried() or attack:isDodged() then letGo = true end
		end)
	end
	release()
	unpin()

	this:endLag(0.15)
end

--- a parried cut only ends the flurry, so it skips AbilityBase's attack lockout
function module.onParried(self:myself, attack:any)
	if attack.dmgTbl ~= CUT then baseClass.onParried(self, attack) end
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
