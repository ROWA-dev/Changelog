--!strict
--[[ Smash - rowa1 Items/Ability/Smash. Notes: README.md/PORT_Smash.

	Uppercut someone into the air, flash-step up after them, and drive them
	back into the ground.

	KEPT SIMPLE, same call as Divide. rowa1 holds the victim mid-air with a
	BodyPosition; that is Modules/pinTo here, not the `floating` air-combo
	system the port doc proposed. Divide and Smash therefore make the SAME
	choice, which was the doc's actual worry -- if they diverged the game
	would have two air-combo models.

	rowa1's file is 359 lines. Most of that is the four-value guard repeated
	seven times and a commented-out block of TweenService the author had
	already decided belonged on the client. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Smash"
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

--- rowa1 "ucut": Light, blunt, 10 dmg, stun 1.0, posMult 3. Shared with Divide.
local UCUT = {
	weight   = dmgUtils.weighEnum.Light,
	type     = dmgFlag.blunt,
	dmg      = 10,
	stun     = 1,
	posMult  = 3,
	parryH   = -0.04,
	--[[ rowa1's "ucut" row carries its own OnHitFunc: a 0.8s FLAT ragdoll,
		no ground check, so the victim flops through the launch instead of
		riding it upright. Flat rather than stopOnGround on purpose -- a
		ground check releases them the instant they land, which reads as
		standing up mid-air.
		SAME rowa1 row as Divide's; keep the two in step. ]]
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "kick1")
		attack.enemyEntity.ragdoll:ragdoll(0.8, false, attack.atkDir * 8)
	end,
}

--[[ rowa1 "ssmash": Heavy, magic, 60 dmg -- the highest single hit in the
	whole table outside Cero, off ONE confirmed uppercut. Cut hard. ]]
local SSMASH = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = bit32.bor(dmgFlag.magic, dmgFlag.blunt),
	dmg      = 34,
	stun     = 0.6,
	posMult  = 3,
	parryH   = -0.04,
	--- rowa1 ssmash sounds: HeavyHit, wet_punch2
	onHit    = function(attack)
		hitSfx(attack.enemyEntity.HRootPart, "HeavyHit", "wet_punch2")
	end,
}

local SLOW_KEY = "smash"

local function useFunc(this:myself)
	local cooldownID = "smash"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent
	local anim = this:PlayAnim(script.Uppercut, 0, 1, 1)

	--- rowa1 set WalkSpeed 8 for the windup
	humObj.walkSpeed:SetMod(SLOW_KEY, -8)
	fireVFX("hideTool", char)
	fireVFX("smashCharge", char:FindFirstChild("Right Arm"), 1.2)

	--- rowa1 plays this on the root for the whole gather
	local chargeSnd = script["magic attack sound"]:Clone()
	chargeSnd.Parent = humObj.HRootPart
	chargeSnd:Play()
	game.Debris:AddItem(chargeSnd, 6)

	--[[ THE CANCEL PATH MUST RESTORE THE ARMS AND THE TOOL. rowa1 forgot it
		on several of its seven bail branches, which is how players ended up
		armless. ]]
	local function bail()
		if anim then anim:Stop(0.1) end
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		fireVFX("smashCharge", nil, 0)
		fireVFX("showArms", char)
		game.Debris:AddItem(chargeSnd, 0)
	end

	--[[ !! 1.0, NOT 0.6. rowa1 DECLARES `Attacking.Time = 0.6` but its real
		windup is `local endt = tick() + 1` -- a full second of the arm
		gathering before anything happens. The declared value only feeds the
		trade logic; the wait is the truth (README S7 note 7g), and porting
		the claim made the uppercut come out early. ]]
	if this:feintWait(1) then
		bail()
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, 14, true)

	local forward = hurtbox.CFrame.LookVector
	local _, hits = this:hitbox(CFrame.new(0, 0, -2), Vector3.new(7, 7, 7))

	local caught = nil
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(UCUT, enemy, forward)
		--[[ rowa1 lookVec*30 + (0,40,0) with `true, 3` -- the 3 meant "no
			knockback damage". rowa2's KnockbackClass builds its own wall
			impact, so the way to opt out is simply a gentler vector rather
			than a magic third argument. x0.6 (README S7). ]]
		--[[ NO DECAY, like rowa1. A decaying vertical mover fights 196
			studs/s^2 the whole way down its own ramp, so it barely lifts --
			an earlier pass swapped to decay and the uppercut stopped
			launching at all.
			rowa1 is lookVec*30 + (0,40,0), which converts to 18 + 24 at the
			x0.6 ratio. Pulled a little under that: the apex only has to be
			high enough for the pin to hold them there. ]]
		attack.knockback = this:knockback(forward * 15 + Vector3.new(0, 21, 0), 0.25, false, -1)
		this:executeAttack(attack)
		if attack:isHit() or attack:isBlocked() then caught = enemy end
		if attack:isHit() then
			if enemy.TrueStun then
				enemy:TrueStun(1)
			end
		end
		break
	end

	if caught == nil or caught.HRootPart == nil then
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		fireVFX("showArms", char)
		this:endLag(0.25)
		return
	end

	fireVFX("camShake", hurtbox.Position, 200, 2, 0.1)
	fireVFX("smashUppercut", hurtbox.Position + Vector3.new(0, 6, 0))

	--[[ +0.08 on every feintWait after the first: it subtracts 0.08 per call,
		which is deliberate for the windup and wrong for the beats after it.
		Chained, the three lost 0.24s and the slam landed early.
		README S7 note 7f. ]]
	if this:feintWait(0.46) then
		bail()
		return
	end

	--[[ hold them at the apex while you close. rowa1 used a BodyPosition at
		`smashPos + lookVec*4`; the pin is the same idea with a guaranteed
		destructor. ]]
	local apex = caught.HRootPart.Position + forward * 4
	local release = pinTo(caught.HRootPart, function() return apex end,
		{ maxTime = 1.2 })

	--[[ TRUE stun for the pin, same call as ToshiCounter. THIS IS THE ONE
		GRAB THAT HAD A REAL GAP: UCUT's stun is 1.0 and the uppercut lands
		0.46 before the pin even starts, so the last ~0.1s of the 0.66 hold
		was already unstunned even without armour -- they could act while
		frozen at the apex. Under hyper armour the whole pin was free, since
		:Stun refuses to write and only :TrueStun passes bypassArmour.
		0.66 is the hold below, not a new number.
		GUARDED: TrueStun is not in the Combatant contract (SimpleEntity
		has :Stun only). ]]
	if caught.TrueStun then
		caught:TrueStun(0.66)
	end

	fireVFX("phantom", char, char.PrimaryPart and char.PrimaryPart.CFrame or hurtbox.CFrame)
	fireVFX("fstep", char, 0.4)
	fireVFX("smashDown", humObj.HRootPart, apex)

	if anim then anim:Stop(0.1) end
	local smashAnim = this:PlayAnim(script.Smash, 0, 1, 1)

	if this:feintWait(0.66) then
		release()
		if smashAnim then smashAnim:Stop(0.1) end
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		fireVFX("smashCharge", nil, 0)
		fireVFX("showArms", char)
		return
	end

	release()

	if caught.isActive == true and caught.HRootPart then
		local eroot = caught.HRootPart
		fireVFX("camShake", eroot.Position, 400, 4, 0.2)

		forward = hurtbox.CFrame.LookVector
		local attack = this:makeAtk(SSMASH, caught, forward)
		-- rowa1 lookVec*10 + (0,-60,0), at the x0.6 ratio (README S7)
		attack.knockback = this:knockback(
			forward * 6 + Vector3.new(0, -36, 0), 0.25, false, -1)
		this:executeAttack(attack)

		if attack:isHit() then
			--[[ rowa1's onHit is ragdollWait: 0.8s FLAT, not a long cap.
				`true` here would be wrong -- they are being driven INTO the
				ground, so stopOnGround would end it on the first frame. ]]
			attack.enemyEntity.ragdoll:ragdoll(0.8, false, Vector3.new(0, -10, 0))
			fireVFX("smashLand", eroot.Position)
			fireVFX("pauseF", char, eroot.Parent)
		end
	end

	humObj.walkSpeed:RemoveMod(SLOW_KEY)
	fireVFX("smashCharge", nil, 0)
	fireVFX("showArms", char)
	this:endLag(0.3)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
