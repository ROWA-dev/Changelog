--!strict
-- Divide - uppercut, drag them in, then two committed strikes; three beats, each gated on the last connecting.
-- !! the uppercut has a SPEED GATE: it only lands if you are moving faster than the target OR they are not attacking. Not a free launcher.
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

-- the launcher.
local UCUT = {
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.blunt,
	dmg      = 10,
	stun     = 1,
	posMult  = 3,
	parryH   = -0.04,
	-- 0.8s FLAT ragdoll: they must ragdoll IN THE AIR, and a ground check would release them the moment they came down. Smash shares this row.
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "kick1")
		attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * 8)
	end,
}

-- the second beat.
local BFLASH = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 26,
	stun     = 1.5,
	posMult  = 3,
	parryH   = -0.04,
	-- sounds: BigPunch, bflash2
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "BigPunch", "bflash2")
	end,
}

-- posMult 4, not 6: the posture pool maxes at 80 and the launcher already spent 3.
local BFLASH2 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 13,
	stun     = 0.6,
	posMult  = 4,
	parryH   = -0.04,
	-- sounds: bflash2, HitSoundLow
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "bflash2", "HitSoundLow")
	end,
}

-- hold the victim a few studs in front of the caster, HORIZONTAL ONLY (axes 1,0,1), so it drags without fighting gravity or the launch.
local DRAG_OPTS = table.freeze({
	axes = Vector3.new(1, 0, 1),
	maxTime = 2,
})

local function useFunc(this:myself)
	local cooldownID = "divide"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Uppercut, 0, 1, 0.7)

	fireVFX("hshock", humObj.HRootPart)
	fireVFX("bFlashTrail", char:FindFirstChild("Left Arm"), 0.5)

	if this:feintWait(0.47) then
		if anim then anim:Stop(0.1) end
		fireVFX("bFlashTrail", nil, 0)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 12, true)

	local myRoot = humObj.HRootPart
	local forward = hurtbox.CFrame.LookVector

	local _, hits = this:hitbox(CFrame.new(0, 0, -2), Vector3.new(5.5, 5.5, 5.5))

	local caught = nil
	for _, enemy in pairs(hits) do
		-- THE SPEED GATE: stops this being a free launcher into someone mid-commitment.
		local mySpeed = myRoot and myRoot.AssemblyLinearVelocity.Magnitude or 0
		local eroot = enemy.HRootPart
		if eroot == nil then continue end
		local theirSpeed = eroot.AssemblyLinearVelocity.Magnitude
		local theyAreAttacking = enemy.attacking and enemy.attacking.Value == true
		if not (mySpeed + 6 > theirSpeed or not theyAreAttacking) then continue end

		local attack = this:makeAtk(UCUT, enemy, forward)
		-- NO DECAY: a decaying vertical mover fights gravity down its ramp and barely lifts. They are SUPPOSED to land before the follow-up.
		attack.knockback = this:knockback(Vector3.new(0, 6, 0), 0.2, false, -1)
		this:executeAttack(attack)

		if attack:isHit() then
			enemy:TrueStun(1)
			caught = enemy
		end
		break
	end

	if caught == nil or caught.HRootPart == nil or myRoot == nil then
		this:endLag(0.2)
		return
	end

	-- the pin's own maxTime is the hard stop, so a stranded AlignPosition can never drag someone forever even if this errors.
	local release = pinTo(caught.HRootPart, function()
		if myRoot == nil or myRoot.Parent == nil then return nil end
		return (myRoot.CFrame * CFrame.new(0, 0, -4)).Position
	end, DRAG_OPTS)
	
	-- to wait for them to fall down alittlebit...
	if this:feintWait(0.12) then
		if anim then anim:Stop(0.1) end
		release()
		return
	end

	if anim then anim:Stop(0.1) end
	
	local part2 = this:PlayAnim(script.Part2, 0, 1, 1)
	fireVFX("divergant", char:FindFirstChild("Right Arm"), 0.8)

	if this:feintWait(0.6) then
		if part2 then part2:Stop(0.1) end
		release()
		return
	end

	forward = hurtbox.CFrame.LookVector
	-- wider than the uppercut on purpose: this beat catches someone falling, and a box sized for a standing target misses them on the way down.
	local _, hits2 = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(9, 10, 9))

	local landed = false
	for _, enemy in pairs(hits2) do
		local attack = this:makeAtk(BFLASH, enemy, forward)
		this:executeAttack(attack)
		if attack:isHit() then
			landed = true
			-- !! UNRAGDOLL HERE, do not add one: a ragdolled character has its Motor6Ds disabled, so the grab's Victim animation would drive nothing.
			if attack.enemyEntity.ragdoll:inRagdoll() then
				attack.enemyEntity.ragdoll:unragdoll()
			end
		end
		break
	end

	if not landed then
		release()
		this:endLag(0.25)
		return
	end

	if part2 then part2:Stop() end
	this:PlayAnim(script.Final, 0, 1, 1)

	fireVFX("divideFlash", humObj.HRootPart, char:FindFirstChild("Right Arm"))
	fireVFX("bflashScreen", char, caught.HRootPart and caught.HRootPart.Parent)

	-- !! THE THIRD BEAT: grab, hold, then release into the finisher. The drag comes off FIRST, or two things own the victim's position and fight.
	release()

	local held = false
	if caught.isActive == true and caught.grab then
		-- maxTime is a dead-man switch: a grab that never releases is a player who can never move again, silently.
		-- welded to the RIGHT ARM with a PURE ROTATION; the arm is already extended, so adding a translation pushes them off the end of it.
		caught.grab:grab(humObj,
			CFrame.Angles(math.rad(90), 0, math.rad(230)), 1.5,
			char:FindFirstChild("Right Arm"))
		held = true

		-- TRUE stun for the hold: an ordinary :Stun is refused under hyper armour, letting an armoured victim act through the payoff beat. Guarded, not in Combatant.
		if caught.TrueStun then
			caught:TrueStun(0.7)
		end

		-- the VICTIM's own reaction animation: PlayAnim only drives self, so this goes through their Animator directly, guarded against a rig mid-teardown.
		local victimAnim = script:FindFirstChild("Victim")
		local animator = caught.Hum and caught.Hum:FindFirstChildOfClass("Animator")
		if victimAnim and animator then
			local ok, track = pcall(function()
				return (animator :: Animator):LoadAnimation(victimAnim :: Animation)
			end)
			if ok and track then
				track:Play()
				game.Debris:AddItem(track, 3)
			end
		end
	end

	this:atkWait(0.7)

	if held and caught.grab then
		caught.grab:release()
	end

	fireVFX("pauseF", char, caught.HRootPart and caught.HRootPart.Parent)
	-- r8 is the inscribed sphere of the 16^3 cut
	Destruction.Sphere(nil,
		hurtbox.Position + hurtbox.CFrame.LookVector * 8 + Vector3.new(0, 4, 0),
		-- studs/SECOND, not a heading
		8, 4.8, hurtbox.CFrame.LookVector * 55)
	fireVFX("divideFlash", humObj.HRootPart, nil)

	forward = hurtbox.CFrame.LookVector
	local _, hits3 = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(6, 7, 6))
	for _, enemy in pairs(hits3) do
		local attack = this:makeAtk(BFLASH2, enemy, forward)
		attack.knockback = this:knockback(
			attack.atkDir * 18 + Vector3.new(0, 4.8, 0), 0.2, false, -1)
		this:executeAttack(attack)
		if attack:isHit() then
			-- a long CAP ended by the ground, not a fixed duration
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
		end
	end

	-- !! THE BLACK FLASH, the payoff: fires after the finisher resolves, just before the shake, and is the only place LightningClash + bflash2 + bflash play.
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
