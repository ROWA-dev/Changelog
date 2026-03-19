--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "ToshiCounter"
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
local dmgFlag = dmgUtils.dmgFlags
local function useFunc(this:myself)
	local cooldownID = "ToshiCounter"
	if this:canTriggerCD(cooldownID) ~= true then return end
		
	local humObj = this._humObj
	local now = tick()
	
	local sinceLastStunned = (now - humObj.stun.Value)
	if sinceLastStunned < 0.4 then -- cant counter 0.4s after stun
		return
	end
	
	if now < humObj._lastBlocked + 0.4 then -- 0.4s
		return
	end
	
	local anim = this:PlayAnim(script.Init, 0, 1, 1)

	humObj.walkSpeed:SetMod("stopMoving", -100)
	this:useMana()
	this:triggerCD(cooldownID, 20, true)
	
	local triggered = false
	local triggeredBy = nil
	local atkHook = humObj.beforeAttacked:Connect(function(atk) 
		triggeredBy = atk.myEntity
		atk.status = dmgUtils.returnEnum.aborted
		triggered = true
	end)
	
	local endt = tick() + 0.5
	while tick() < endt and triggered == false do
		task.wait()
	end
	
	atkHook:Destroy()
	
	if anim then
		anim:Stop(0.1)
	end
	
	if triggeredBy == nil then
		this:atkWait(0.5) -- 0.5s time to punish this guy lol
		humObj.walkSpeed:RemoveMod("stopMoving")
		return
	end

	if triggeredBy.TrueStun then
		triggeredBy:TrueStun(0.7)
	end
	if triggeredBy.walkSpeed then
		triggeredBy.walkSpeed:SetMod("stopMoving", -100)
	end
	
	print("trigger", triggeredBy)
	local char = humObj.Hum.Parent
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("phantom", char)

	local victimAnim = if triggeredBy.PlayAnim then triggeredBy:PlayAnim(script.Victim) else nil
	anim = this:PlayAnim(script.Land)
	
	local sound = script.counter:Clone()
	sound.Parent = humObj.HRootPart
	sound:Play()
	
	this:atkWait(0.6)
	
	local hitboxOffset = CFrame.new(0, 0, -3)
	local hitboxSize   = Vector3.new(8,8,8)
	local hits		   = this:hitbox(hitboxOffset, hitboxSize)
	local hurtbox  = humObj.HurtBox
	
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("bostaffShock", hurtbox.CFrame * CFrame.new(0,0,-6))


	local dmgTbl = {
		weight   = dmgUtils.weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.blunt),
		dmg      = 8,
		stun     = 1,
		posMult  = 4,
		parryH   = 0.1,
		onHit    = function(attack, source)
			local eroot = attack.enemyEntity.HRootPart
			game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("punch", eroot)
		end,
	}

	local victimWasHit = false
	for _,enemhum in pairs(hits) do
		local attack = this:makeAtk(
			dmgTbl,
			enemhum,
			hurtbox.CFrame.LookVector
		)
		
		--[[local newkb = this:knockback(
			attack.atkDir*14,
			0.1,
			false,
			-1
		)
		
		attack.knockback = newkb]]

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
			if enemhum == triggeredBy.Hum then
				victimWasHit = true
			end
			
			local attackActualVictimNow = attack.enemyEntity
			if attackActualVictimNow.TrueStun then
				attackActualVictimNow:TrueStun(0.2)
				attackActualVictimNow:Stun(0.4)
			end
			
			local grabClass = attackActualVictimNow.grab
			local grab = grabClass:grab(humObj)
			grab.C1 = CFrame.Angles(0, math.rad(180),0) * CFrame.new(0,0,3.5)
			
			task.wait(0.2)
			grabClass:release()
			local dmgTbl2 = {
				weight   = dmgUtils.weighEnum.Heavy,
				type     = bit32.bor(dmgFlag.blunt),
				dmg      = 10,
				stun     = 0.4,
				posMult  = 4,
				parryH   = -0.08,
				onHit    = function(attack, source)
					local eroot = attack.enemyEntity.HRootPart
					game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("strpunch", eroot)
				end,
			}
			
			local attack2 = this:makeAtk(
				dmgTbl2,
				enemhum,
				hurtbox.CFrame.LookVector
			)

			local newkb = this:knockback(
				attack.atkDir*18,
				0.1,
				false
			)
		
			attack2.knockback = newkb

			this:executeAttack(attack2)
			--[[if attack2:isHit() then
				attack2.enemyEntity.ragdoll:ragdoll(60, true, attack2.atkDir*10)
			end]]
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
		triggeredBy.walkSpeed:RemoveMod("stopMoving")
	end
	humObj.walkSpeed:RemoveMod("stopMoving")
	humObj.canAtkThreshold = tick() + 0.24
	this:endLag(0.1)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end


return table.freeze(module)
