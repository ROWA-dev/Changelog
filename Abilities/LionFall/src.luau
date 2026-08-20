--!strict
--[[ LionFall - rowa1 Items/Ability/LionFall. Notes: README.md/PORT_LionFall.

	!! THE PORT DOC HAD THIS MOVE WRONG. It described "a long-telegraph
	leaping slam with a cinematic freeze on connect", built around a 2.5s
	uncancellable windup.

	IT IS A COUNTER. rowa1 hooks `HumObj.beforeDamage` and sets
	`extras["nodmg"] = true` -- it stands there for 0.6s, and if someone
	attacks you in that window the incoming damage is CANCELLED and you
	answer with one enormous punch. The 2.5s `Attacking.Time` is the stance,
	not a windup.

	Built on ToshiCounter's shape, which is rowa2's established counter:
	subscribe to `beforeAttacked`, abort the attack, remember who threw it.
	Same hook, one field instead of an `extras` table.

	rowa1 REFUNDED HALF the cooldown on a whiff, which is what makes a
	counter worth attempting. Kept. ]]
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "LionFall"
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
local Destruction = require(game.ServerStorage.ROWA.Destruction_Stable.Destruction)

--[[ rowa1 "lionFall": Heavy, blunt, 30 dmg ("nerfed from 40"), truestun 0.4
	/ stun 1. Its onHit was an INLINE function -- ragdtillground plus two
	emitters parented to the victim -- so the emitters became the `lFall`
	quiver id and the ragdoll moved into the isHit branch. ]]
local LION_FALL = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 20,
	stun     = 1,
	posMult  = 3,
	parryH   = -0.04,
	onHit    = function(attack)
		local eroot = attack.enemyEntity.HRootPart
		hitSfx(eroot, "LionFall", "DawnHeavyPunch", "Sugarcoat")
		fireVFX("lFall", eroot)
	end,
}

local STANCE     = 0.6
local CD         = 22
--- rowa1 gave back half on a whiff: `cd = tick() - cd/2`
local WHIFF_CD   = CD / 2
local SLOW_KEY   = "lionFall"

local function useFunc(this:myself)
	local cooldownID = "lionFall"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent

	--- ToshiCounter's guards: a counter thrown out of stun is free defence
	local now = tick()
	if now < humObj.stun.Value + 0.4 then return end
	if now < humObj._lastBlocked + 0.4 then return end

	local windup = this:PlayAnim(script.Windup, 0, 1, 1.5)
	humObj.walkSpeed:SetMod(SLOW_KEY, -100)

	--- the red tell. rowa1 parented a Highlight straight onto the character.
	local indicator = script.Highlight:Clone()
	indicator.Enabled = true
	indicator.Parent = char

	local triggeredBy = nil
	local hook = humObj.beforeAttacked:Connect(function(atk)
		triggeredBy = atk.myEntity
		--- rowa1's `extras["nodmg"] = true`, expressed as the one field
		--- rowa2 has for it
		atk.status = dmgUtils.returnEnum.aborted
	end)

	local endt = tick() + STANCE
	while tick() < endt and triggeredBy == nil do
		task.wait()
	end
	hook:Destroy()
	indicator:Destroy()

	if windup then windup:Stop(0.1) end

	if triggeredBy == nil then
		--- whiffed: half cooldown, and a window to be punished in
		this:triggerCD(cooldownID, WHIFF_CD, true)
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		this:atkWait(0.5)
		return
	end

	this:useMana()
	this:triggerCD(cooldownID, CD, true)

	local punch = this:PlayAnim(script.Punch, 0, 1, 1)

	local startSnd = script.start:Clone()
	startSnd.Parent = humObj.HRootPart
	startSnd:Play()
	game.Debris:AddItem(startSnd, 4)

	--- rowa1 hung the charge emitters off the RIGHT arm's grip attachment
	local rArm = char:FindFirstChild("Right Arm")
	local grip = rArm and rArm:FindFirstChild("RightGripAttachment")
	local sparks, circle
	if grip then
		sparks = script.handsparks:Clone()
		sparks.Parent = grip
		game.Debris:AddItem(sparks, 4)
		circle = script.circle:Clone()
		circle.Parent = grip
		game.Debris:AddItem(circle, 4)
	end

	--[[ the 4 x 0.05s charge. atkWait, not feintWait: the counter has
		already committed and rowa1 tagged it `noFeint` for exactly this
		stretch. See PORT_LionFall step 2. ]]
	for i = 1, 4 do
		if humObj:inStun() then
			if punch then punch:Stop() end
			--[[ rowa1 bins Chargup AND HandSparks on this exact path
				(Debris 0 on both). Getting stunned out of the charge left
				the hand sparking and the charge sound ringing for another
				four seconds -- the same interrupt-does-not-look-like-an-
				interrupt bug as the beam and the flamethrower. ]]
			game.Debris:AddItem(startSnd, 0)
			if sparks then game.Debris:AddItem(sparks, 0) end
			if circle then game.Debris:AddItem(circle, 0) end
			humObj.walkSpeed:RemoveMod(SLOW_KEY)
			return
		end
		if sparks then sparks:Emit(8) end
		if circle and i % 2 == 0 then circle:Emit(1) end
		this:atkWait(0.05)
	end

	local forward = hurtbox.CFrame.LookVector
	fireVFX("phantom", char, char.PrimaryPart and char.PrimaryPart.CFrame or hurtbox.CFrame)
	--- rowa1 BigBreak cut with a 16^3 cube; r8 is its inscribed sphere
	--- studs/SECOND, not a heading -- see Destruction's visualizeDestroyed
	Destruction.Sphere(nil, hurtbox.Position + forward * 7, 8, 4.8, forward * 55)

	local _, hits = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(8, 8, 8))
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(LION_FALL, enemy, forward)
		-- rowa1 look*20 + (0,8,0), at the x0.6 knockback ratio (README S7)
		attack.knockback = this:knockback(
			attack.atkDir * 12 + Vector3.new(0, 4.8, 0), 0.15, false, -1)
		this:executeAttack(attack)

		if attack:isHit() then
			--- rowa1's onHit ran ragdtillground: a long CAP ended by ground
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir * 10)
			local eroot = enemy.HRootPart
			if eroot then
				fireVFX("pauseF", char, eroot.Parent)
			end
		end
	end

	--- the trailing hand smoke, after the move ends
	if grip then
		local smoke = script.smoke:Clone()
		smoke.Parent = grip
		game.Debris:AddItem(smoke, 4)
		task.spawn(function()
			for _ = 1, 16 do
				if smoke.Parent == nil then return end
				smoke:Emit(1)
				task.wait(0.05)
			end
		end)
	end

	humObj.walkSpeed:RemoveMod(SLOW_KEY)
	humObj.canAtkThreshold = tick() + 0.24
	this:endLag(0.2)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end

return table.freeze(module)
