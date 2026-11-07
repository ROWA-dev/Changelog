--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "ToshiCounter",
	counter = 0.5, -- its stance secs (past the startup): flags a counter for HumanAI
	--manaUse = 10,
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

function module.new(humObj:humObj):myself
	return setmetatable(baseClass.new(humObj), module) :: any
end

local dmgUtils = require(game.ServerScriptService.Utils.DmgUtils)
local dmgFlag = dmgUtils.dmgFlags
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local REACH, MAX_STEP = 5, 6 -- studs: past REACH the counterer steps in, at most MAX_STEP
local function useFunc(this:myself)
	local cooldownID = "ToshiCounter"
	if this:canTriggerCD(cooldownID) ~= true then return end
		
	local humObj = this._humObj

	if this:counterStartup() then return end

	local anim = this:PlayAnim(script.Init, 0, 1, 1)

	local indicator = script.Highlight:Clone()
	indicator.Enabled = true
	indicator.Parent = humObj.Hum.Parent
	
	local triggeredBy = nil
	local atkHook = humObj.beforeAttacked:Connect(function(atk) 
		triggeredBy = atk.myEntity
		atk.status = dmgUtils.returnEnum.aborted
	end)
	
	local endt = tick() + 0.5
	while tick() < endt and triggeredBy == nil do
		task.wait()
	end
	
	atkHook:Destroy()
	indicator:Destroy()
	
	if anim then
		anim:Stop(0.1)
	end
	
	if triggeredBy == nil then
		this:counterMissed()
		this:atkWait(0.7) -- 0.7s time to punish this guy lol
		humObj.walkSpeed:RemoveMod(cooldownID)
		return
	end

	if triggeredBy.TrueStun then
		triggeredBy:TrueStun(0.7)
	end
	if triggeredBy.walkSpeed then
		triggeredBy.walkSpeed:SetMod(cooldownID, -100)
	end
	
	local char = humObj.Hum.Parent
	fireVFX("phantom", char)

	local victimAnim = if triggeredBy.PlayAnim then triggeredBy:PlayAnim(script.Victim) else nil
	anim = this:PlayAnim(script.Land)
	
	local sound = script.counter:Clone()
	sound.Parent = humObj.HRootPart
	sound:Play()
	game.Debris:AddItem(sound, 4)
	
	local gap = (triggeredBy.HRootPart.Position - humObj.HRootPart.Position) * Vector3.new(1, 0, 1)
	if gap.Magnitude > REACH then
		this:bodyForce(gap.Unit * math.min(gap.Magnitude - REACH, MAX_STEP), 0.2)
	end

	this:atkWait(0.6)
	
	local hitboxOffset = CFrame.new(0, 0, -3)
	local hitboxSize   = Vector3.new(8,8,8)
	local _, hits	   = this:hitbox(hitboxOffset, hitboxSize)
	local hurtbox  = humObj.HurtBox
	
	fireVFX("bostaffShock", hurtbox.CFrame * CFrame.new(0,0,-6))


	local dmgTbl = {
		weight   = dmgUtils.weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.blunt),
		dmg      = 8,
		stun     = 1,
		posMult  = 4,
		parryH   = 0.1,
		onHit    = function(attack, source)
			local eroot = attack.enemyEntity.HRootPart
			fireVFX("punch", eroot)
		end,
	}

	local victimWasHit = false
	for _,enemy in pairs(hits) do
		local attack = this:makeAtk(
			dmgTbl,
			enemy,
			hurtbox.CFrame.LookVector
		)

		if anim and victimAnim then
			anim:AdjustSpeed(0)
			victimAnim:AdjustSpeed(0)
		end
		this:executeAttack(attack)
		if anim and victimAnim then
			anim:AdjustSpeed(1)
			victimAnim:AdjustSpeed(1)
		end
		
		if attack:isHit() then
			if enemy.Hum == triggeredBy.Hum then
				victimWasHit = true
			end
			
			local attackActualVictimNow = attack.enemyEntity
			if attackActualVictimNow.TrueStun then
				attackActualVictimNow:TrueStun(0.2)
				attackActualVictimNow:Stun(0.4)
			end
			
			-- not in the Combatant contract: a non-HumObj victim just isn't held
			local grabClass = attackActualVictimNow.grab
			if grabClass then
				grabClass:grab(humObj).C1 = CFrame.Angles(0, math.rad(180),0) * CFrame.new(0,0,3.5)
			end
			
			task.wait(0.2)
			if grabClass then grabClass:release() end
			local dmgTbl2 = {
				weight   = dmgUtils.weighEnum.Heavy,
				type     = bit32.bor(dmgFlag.blunt),
				dmg      = 10,
				stun     = 0.4,
				posMult  = 4,
				parryH   = -0.08,
				onHit    = function(attack, source)
					local eroot = attack.enemyEntity.HRootPart
					fireVFX("strpunch", eroot)
				end,
			}
			
			local attack2 = this:makeAtk(
				dmgTbl2,
				enemy,
				hurtbox.CFrame.LookVector
			)

			local newkb = this:knockback(
				attack.atkDir*18,
				0.1,
				false
			)
		
			attack2.knockback = newkb

			this:executeAttack(attack2)
		elseif anim then
			anim:Stop(0.2)
			if victimAnim then victimAnim:Stop(0.1) end
		end
	end
	
	if victimWasHit == false then
		if anim then anim:Stop() end
		if victimAnim then victimAnim:Stop(0.1) end
	end
	if triggeredBy.walkSpeed then
		triggeredBy.walkSpeed:RemoveMod(cooldownID)
	end
	humObj.walkSpeed:RemoveMod(cooldownID)
	humObj.canAtkThreshold = tick() + 0.24
	this:endLag(0.1)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end


return table.freeze(module)
