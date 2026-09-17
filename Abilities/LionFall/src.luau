--!strict
--- LionFall - a COUNTER, not the leaping slam the doc describes. Stand for
--- 0.6s; if someone attacks you in that window their damage is CANCELLED and
--- you answer with one enormous punch. The 2.5s is the STANCE, not a windup.
--- Built on ToshiCounter's shape (subscribe to beforeAttacked, abort, remember
--- who threw it). Half the cooldown is charged on a whiff.
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "LionFall",
	manaUse = 20,
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

local LION_FALL = {
	weight   = dmgUtils.weighEnum.Heavy,
	type     = dmgFlag.blunt,
	dmg      = 18,
	stun     = 1,
	posMult  = 3,
	parryH   = -0.1,
	onHit    = function(attack)
		local eroot = attack.enemyEntity.HRootPart
		hitSfx(eroot, "LionFall", "DawnHeavyPunch", "Sugarcoat")
		fireVFX("lFall", eroot)
	end,
}

local STANCE     = 0.4
local CD         = 22
local WHIFF_CD   = CD / 2
local SLOW_KEY   = "lionFall"

local function useFunc(this:myself)
	local cooldownID = "lionFall"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char: any = hurtbox.Parent

	--- no reversal out of pressure. See HumObj:canCounter.
	if not humObj:canCounter() then return end

	local windup = this:PlayAnim(script.Windup, 0, 1, 1.5)
	humObj.walkSpeed:SetMod(SLOW_KEY, -100)
	this:useMana()
	--- the whiff tier, paid UP FRONT. The full price lands below only if the
	--- stance actually catches something -- charging it here and refunding after
	--- is the no-op trigger() quietly eats. See triggerCD.
	this:triggerCD(cooldownID, WHIFF_CD, true)
	this:atkWait(0.1)

	--- the red tell.
	local indicator = script.Highlight:Clone()
	indicator.Enabled = true
	indicator.Parent = char

	local triggeredBy = nil
	local hook = humObj.beforeAttacked:Connect(function(atk)
		triggeredBy = atk.myEntity
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
		--- whiffed: already paid the half tier, plus a window to be punished in
		humObj.walkSpeed:RemoveMod(SLOW_KEY)
		this:atkWait(0.6) -- on miss
		return
	end

	--- it caught one, so it costs the full price. No dontOverwrite: that is
	--- exactly what stops this landing.
	this:triggerCD(cooldownID, CD)

	local punch = this:PlayAnim(script.Punch, 0, 1, 1)

	local startSnd = script.start:Clone()
	startSnd.Parent = humObj.HRootPart
	startSnd:Play()
	game.Debris:AddItem(startSnd, 4)

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

	--- the 4 x 0.05s charge. atkWait, not feintWait: the counter has already
	--- committed, so this stretch is deliberately not cancellable.
	for i = 1, 4 do
		if humObj:inStun() then
			if punch then punch:Stop() end
			--[[ bin BOTH emitters here. Getting stunned out of the charge left
				the hand sparking and the charge sound ringing for another four
				seconds -- an interrupt that does not look like one. ]]
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
	--- studs/SECOND, not a heading -- see Destruction's visualizeDestroyed
	Destruction.Sphere(nil, hurtbox.Position + forward * 7, 8, 4.8, forward * 55)

	local _, hits = this:hitbox(CFrame.new(0, 0, -5), Vector3.new(8, 8, 8))
	for _, enemy in pairs(hits) do
		local attack = this:makeAtk(LION_FALL, enemy, forward)
		attack.knockback = this:knockback(
			attack.atkDir * 12 + Vector3.new(0, 4.8, 0), 0.15, false, -1)
		this:executeAttack(attack)

		if attack:isHit() then
			--- a long CAP ended by the ground check, not a 60s ragdoll
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
