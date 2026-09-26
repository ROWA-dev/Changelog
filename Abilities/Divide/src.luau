--!strict
-- Divide - uppercut, drag them in, punch/grab (freeze frame kinda) -> punch continue away
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Divide"
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
local fireVFX  = require(game.ServerStorage.ROWA.Modules.fireVFX)
local hitSfx   = require(game.ServerStorage.ROWA.Modules.hitSfx)
local pinTo    = require(game.ServerStorage.ROWA.Modules.pinTo)
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

local UCUT = {
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.blunt,
	dmg      = 8,
	stun     = 1,
	posMult  = 3.5, -- 3 + the lift's old posture share, now that it isn't on the attack up front
	parryH   = -0.04,
	-- the lift lives here so a block doesn't launch them. NO DECAY: a decaying vertical mover barely lifts. 0.8s FLAT ragdoll: a ground check would release them mid-air.
	onHit    = function(attack, this)
		hitSfx(attack.enemyEntity.HRootPart, "kick1")
		attack.knockback = this:knockback(Vector3.new(0, 6, 0), 0.2, false, -1)
		attack:ApplyKnockback()
		attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * 8)
	end,
}

local BFLASH = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 26,
	stun     = 1.5,
	posMult  = 3,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "BigPunch", "bflash2")
	end,
}

local BFLASH2 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 14,
	stun     = 0.6,
	posMult  = 4,
	parryH   = -0.04,
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "bflash2", "HitSoundLow")
	end,
}

-- HORIZONTAL ONLY, so the drag never fights gravity or the launch.
local DRAG_OPTS = table.freeze({
	axes = Vector3.new(1, 0, 1),
	maxTime = 2,
})

-- active frames: the pin is still dragging them in, so one snapshot can land before they arrive.
local CATCH = table.freeze({ window = 0.15 })

-- the launcher. The first gate-passing body is the only candidate, hit or not.
local function launch(this:myself, hurtbox:BasePart, myRoot:BasePart?): any?
	local mySpeed = myRoot and myRoot.AssemblyLinearVelocity.Magnitude or 0
	local forward = hurtbox.CFrame.LookVector
	local _, hits = this:hitbox(CFrame.new(0, 0, -2), Vector3.new(5.5, 5.5, 5.5))

	for _, enemy in pairs(hits) do
		local eroot = enemy.HRootPart
		if eroot == nil then continue end

		-- THE SPEED GATE: stops this being a free launcher into someone mid-commitment.
		local canLaunch = mySpeed + 6 > eroot.AssemblyLinearVelocity.Magnitude
			or not (enemy.attacking and enemy.attacking.Value == true)
		if not canLaunch then continue end

		local attack = this:makeAtk(UCUT, enemy, forward)
		this:executeAttack(attack)

		if not attack:isHit() then return nil end
		enemy:TrueStun(1)
		return enemy
	end
	return nil
end

local function grabPunch(this:myself, hurtbox:BasePart): boolean
	local forward = hurtbox.CFrame.LookVector
	-- wider than the uppercut on purpose: this beat catches someone falling, and a box sized for a standing target misses them on the way down.
	local _, hits = this:sweep(CFrame.new(0, 0, -4), Vector3.new(9, 10, 9), CATCH)

	-- sweep bails on stun, so an interrupt mid-window arrives as an empty list.
	local target = hits[1]
	if target == nil then return false end

	local attack = this:makeAtk(BFLASH, target, forward)
	this:executeAttack(attack)
	-- a block, parry or dodge is not a catch.
	if not attack:isHit() then return false end

	-- !! UNRAGDOLL HERE, do not add one: a ragdolled character has its Motor6Ds disabled, so the grab's Victim animation would drive nothing.
	if attack.enemyEntity.ragdoll:inRagdoll() then
		attack.enemyEntity.ragdoll:unragdoll()
	end
	return true
end

-- the caller owns the release timing, hence the boolean.
local function holdVictim(this:myself, char:any, caught:any): boolean
	if caught.isActive ~= true or caught.grab == nil then return false end

	-- maxTime is a dead-man switch: a grab that never releases is a player who can never move again, silently.
	-- welded to the RIGHT ARM with a PURE ROTATION; the arm is already extended, so adding a translation pushes them off the end of it.
	caught.grab:grab(this._humObj,
		CFrame.Angles(math.rad(90), 0, math.rad(230)), 1.5,
		char:FindFirstChild("Right Arm"))

	-- TRUE stun for the hold: an ordinary :Stun is refused under hyper armour, letting an armoured victim act through the payoff beat. Guarded, not in Combatant.
	if caught.TrueStun then
		caught:TrueStun(0.7)
	end

	-- the VICTIM's own reaction: PlayAnim only drives self.
	local victimTrack = caught.LoadAnimation and caught:LoadAnimation(script.Victim)
	if victimTrack then
		victimTrack:Play()
		game.Debris:AddItem(victimTrack, 3)
	end
	return true
end

-- the cut, then the knockback that carries everyone still in front of it.
local function finish(this:myself, hurtbox:BasePart)
	-- r8 is the inscribed sphere of the 16^3 cut
	Destruction.Sphere(nil,
		hurtbox.Position + hurtbox.CFrame.LookVector * 8 + Vector3.new(0, 4, 0),
		-- studs/SECOND, not a heading
		8, 4.8, hurtbox.CFrame.LookVector * 55)
	fireVFX("divideFlash", this._humObj.HRootPart, nil)

	local forward = hurtbox.CFrame.LookVector
	local _, hits = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(6, 7, 6))
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(BFLASH2, enemy, forward)
		attack.knockback = this:knockback(
			attack.atkDir * 18 + Vector3.new(0, 4.8, 0), 0.2, false, -1)
		this:executeAttack(attack)
		if attack:isHit() then
			-- a long CAP ended by the ground, not a fixed duration
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
		end
	end
end

local function useFunc(this:myself)
	local cooldownID = "divide"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	-- reassigned at each beat, so bail() always stops whatever is playing.
	local track = this:PlayAnim(script.Uppercut, 0, 1, 0.7)
	-- declared above bail() because bail has to see it.
	local release:(()->())? = nil

	local function unpin()
		if release then
			release()
			release = nil
		end
	end

	-- EVERY exit owes this: a feint, an outside attacker's stun and sweep's own interrupt all land here.
	local function bail()
		unpin()
		if track then track:Stop(0.1) end
		fireVFX("bFlashTrail", nil, 0)
	end

	fireVFX("hshock", humObj.HRootPart)
	fireVFX("bFlashTrail", char:FindFirstChild("Left Arm"), 0.5)

	if this:feintWait(0.47) then
		bail()
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	local myRoot = humObj.HRootPart
	local caught = launch(this, hurtbox, myRoot)

	if caught == nil or caught.HRootPart == nil or myRoot == nil then
		this:endLag(0.1)
		return
	end

	-- the pin's own maxTime is the hard stop, so a stranded AlignPosition can never drag someone forever even if this errors.
	release = pinTo(caught.HRootPart, function()
		if myRoot == nil or myRoot.Parent == nil then return nil end
		return (myRoot.CFrame * CFrame.new(0, 0, -4)).Position
	end, DRAG_OPTS)

	-- to wait for them to fall down alittlebit...
	if this:feintWait(0.22) then
		bail()
		return
	end

	if track then track:Stop(0.1) end
	track = this:PlayAnim(script.Part2, 0, 1, 1)
	fireVFX("divergant", char:FindFirstChild("Right Arm"), 0.8)

	if this:feintWait(0.6) then
		bail()
		return
	end

	if not grabPunch(this, hurtbox) then
		bail()
		this:endLag(0.25)
		return
	end

	if track then track:Stop() end
	this:PlayAnim(script.Final, 0, 1, 1)

	fireVFX("divideFlash", humObj.HRootPart, char:FindFirstChild("Right Arm"))
	fireVFX("bflashScreen", char, caught.HRootPart and caught.HRootPart.Parent)

	-- !! the drag comes off FIRST, or two things own the victim's position and fight.
	unpin()

	local held = holdVictim(this, char, caught)

	this:atkWait(0.7)

	if held and caught.grab then
		caught.grab:release()
	end

	fireVFX("pauseF", char, caught.HRootPart and caught.HRootPart.Parent)
	finish(this, hurtbox)

	-- !! THE BLACK FLASH, the payoff: the only place LightningClash + bflash2 + bflash play.
	fireVFX("blackFlash", humObj.HRootPart)
	-- there is no Lighting effect for the second pulse, so the participants' screen flash carries it.
	fireVFX("bflashScreen", char, caught.HRootPart and caught.HRootPart.Parent)
	fireVFX("camShake", hurtbox.Position, 400, 1, 0.3)
	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
