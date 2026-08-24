--!strict
--- Divide - uppercut, drag them in, then two committed strikes. Three beats,
--- each gated on the last connecting. rowa1 port: README.md/PORT_Divide.
--- No CharAtkWeld cinematic and no `floating` air-combo: the AlignPosition drag
--- does the same job in one object. Adding the hold later is additive.
--- !! the uppercut has a SPEED GATE -- it only lands if you are moving faster
--- than the target OR they are not attacking. Not a free launcher.
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

--- rowa1 "ucut": Light, blunt, 10 dmg, stun 1.0, posMult 3. The launcher.
local UCUT = {
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.blunt,
	dmg      = 10,
	stun     = 1,
	posMult  = 3,
	parryH   = -0.04,
	--- 0.8s FLAT ragdoll: the uppercut is supposed to ragdoll them IN THE AIR,
	--- and a ground check would release them the moment they came down.
	--- Smash shares this rowa1 row; keep the two in step.
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "kick1")
		attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * 8)
	end,
}

--- rowa1 "bflash": Heavy, magic, 40 dmg, truestun 0.5 / stun 1.5.
local BFLASH = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 26,
	stun     = 1.5,
	posMult  = 3,
	parryH   = -0.04,
	--- rowa1 bflash sounds: BigPunch, bflash2
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "BigPunch", "bflash2")
	end,
}

--[[ rowa1 "bflash2": Heavy, magic, 20 dmg, stun 0.6, posMult 6.
	posMult 6 was tuned against a 100 posture pool; rowa2's max is 80, and
	the launcher already spent 3. Pulled to 4. ]]
local BFLASH2 = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.magic,
	dmg      = 13,
	stun     = 0.6,
	posMult  = 4,
	parryH   = -0.04,
	--- rowa1 bflash2 sounds: bflash2, HitSoundLow
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "bflash2", "HitSoundLow")
	end,
}

--[[ hold the victim a few studs in front of the caster.
	HORIZONTAL ONLY (axes 1,0,1), which is rowa1's MaxAxesForce: it drags
	them in without fighting gravity or the launch, and that is what makes it
	read as a pull rather than a float. ]]
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
		--[[ THE SPEED GATE. rowa1 only lands the uppercut if you are moving
			faster than them, or they are not attacking. It is what stops
			this being a free launcher into someone mid-commitment. ]]
		local mySpeed = myRoot and myRoot.AssemblyLinearVelocity.Magnitude or 0
		local eroot = enemy.HRootPart
		if eroot == nil then continue end
		local theirSpeed = eroot.AssemblyLinearVelocity.Magnitude
		local theyAreAttacking = enemy.attacking and enemy.attacking.Value == true
		if not (mySpeed + 6 > theirSpeed or not theyAreAttacking) then continue end

		local attack = this:makeAtk(UCUT, enemy, forward)
		--[[ NO DECAY, and the reason is gravity: a decaying vertical mover
			fights 196 studs/s^2 the whole way down its ramp and barely lifts.
			rowa1 holds (0,12,0) flat = 7.2 at the x0.6 ratio; slightly under.
			They are SUPPOSED to land before the follow-up -- the 0.6s gap
			below is what catches them, not a short launch. ]]
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

	--- the pin's own maxTime is the hard stop, so a stranded AlignPosition
	--- can never drag someone forever even if this errors.
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
	--[[ wider than the uppercut on purpose. This beat has to catch someone
		who has been launched, dragged and is now falling, so a box sized for
		a standing target misses them on the way down. ]]
	local _, hits2 = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(9, 10, 9))

	local landed = false
	for _, enemy in pairs(hits2) do
		local attack = this:makeAtk(BFLASH, enemy, forward)
		this:executeAttack(attack)
		if attack:isHit() then
			landed = true
			--[[ !! UNRAGDOLL HERE, do not add one. The grab plays a `Victim`
				animation on them and a ragdolled character has its Motor6Ds
				disabled, so the animation would drive nothing. The uppercut's
				0.8s ragdoll is usually still running, so end it explicitly. ]]
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

	--- !! THE THIRD BEAT: grab, hold, then release into the finisher. Skipping
	--- it is what made the move read as two hits instead of three -- the hold is
	--- the moment the camera reads. The drag comes off first: two things owning
	--- the victim's position at once fight each other.
	release()

	local held = false
	if caught.isActive == true and caught.grab then
		--- maxTime is a dead-man switch: a grab that never releases is a
		--- player who can never move again, and it is silent.
		--[[ welded to the RIGHT ARM with a PURE ROTATION -- rowa1's
			C0 = CFrame.Angles(90, 0, 230), parented to that arm. The arm is
			already extended, so it is the position; the translation an
			earlier pass added on top pushed them off the end of it. ]]
		caught.grab:grab(humObj,
			CFrame.Angles(math.rad(90), 0, math.rad(230)), 1.5,
			char:FindFirstChild("Right Arm"))
		held = true

		--[[ TRUE stun for the hold, same call as ToshiCounter. The hold is
			the payoff of the move and an ordinary :Stun is refused under
			hyper armour, which let an armoured victim act through the one
			beat the camera is reading. 0.7 is the atkWait below.
			GUARDED: TrueStun is not part of the Combatant contract
			(SimpleEntity has :Stun only). ]]
		if caught.TrueStun then
			caught:TrueStun(0.7)
		end

		--[[ the VICTIM's own reaction animation. PlayAnim only drives self,
			so this goes through their Animator directly -- guarded, because
			a rig mid-teardown can be missing one and a throw here would eat
			the rest of the move (AbilityBase.use pcalls the useFunc). ]]
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
	--- rowa1 BigBreak cut with a 16^3 cube; r8 is its inscribed sphere
	Destruction.Sphere(nil,
		hurtbox.Position + hurtbox.CFrame.LookVector * 8 + Vector3.new(0, 4, 0),
		--- studs/SECOND, not a heading
		8, 4.8, hurtbox.CFrame.LookVector * 55)
	fireVFX("divideFlash", humObj.HRootPart, nil)

	forward = hurtbox.CFrame.LookVector
	local _, hits3 = this:hitbox(CFrame.new(0, 0, -4), Vector3.new(6, 7, 6))
	for _, enemy in pairs(hits3) do
		local attack = this:makeAtk(BFLASH2, enemy, forward)
		-- rowa1 look*30 + (0,8,0), at the x0.6 knockback ratio (README S7)
		attack.knockback = this:knockback(
			attack.atkDir * 18 + Vector3.new(0, 4.8, 0), 0.2, false, -1)
		this:executeAttack(attack)
		if attack:isHit() then
			--- rowa1's onHit was ragdtillground: a long CAP ended by ground
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
		end
	end

	--- !! THE BLACK FLASH -- the payoff, and it was missing entirely. Fired in
	--- rowa1's order: after the finisher resolves, immediately before the shake.
	--- It is also the only place LightningClash + bflash2 + bflash play, which is
	--- why the move's audio read thin without it. The `landed` gate is rowa1's
	--- `therehit2`: never on a whiffed finisher.
	fireVFX("blackFlash", humObj.HRootPart)
	--- rowa1's second RedFlash pulse. rowa2 has no such Lighting effect, so
	--- the participants' screen flash is what carries it (see bflashScreen).
	fireVFX("bflashScreen", char, caught.HRootPart and caught.HRootPart.Parent)
	fireVFX("camShake", hurtbox.Position, 400, 1, 0.3)
	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
