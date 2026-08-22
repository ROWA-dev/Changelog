--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Fulminate"
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
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local function useFunc(this:myself)
	local cooldownID = "fulminate"
	if this:canTriggerCD(cooldownID) ~= true then return end
	print("USE ABILITY!")
	local anim = this:PlayAnim(script.Anim)
	
	local humObj = this._humObj
	local hurtbox = humObj.HurtBox
	
	local vfx = script.vfx:Clone()
	vfx.Parent = humObj.HRootPart
	vfx.charge:Play()
	
	local blade = humObj:GetBlade() or hurtbox.Parent:FindFirstChild("Right Arm")
	local vfx2 = script.ELECTRIC:Clone()
	vfx2.Parent = blade
	
	local vfx3 = script.lighting4:Clone()
	vfx3.Parent = blade

	local initForce = this:bodyForce(Vector3.new(0,0,2), 0.6, true, 0.6, 0.5)
	humObj.walkSpeed:SetMod("stopMoving", -100)
	
	local st = tick()
	local feinted = this:feintWait(0.62, function()
		vfx2:Emit(1)
		vfx3:Emit(1)
	end)
	
	game.Debris:AddItem(vfx3, 4)
	game.Debris:AddItem(vfx2, 4)
	
	if feinted then
		humObj.walkSpeed:RemoveMod("stopMoving")
		if anim then
			anim:Stop()
		end
		initForce:destroy()
		vfx:Destroy()
		return
	end
	
	vfx.dash:Play()
	vfx.idash:Emit(4)
	fireVFX("speedBeams", vfx)
	
	this:useMana()
	this:triggerCD(cooldownID, 14, true)
	local moveForce = this:bodyForce(Vector3.new(0,0,-35), 0.4, true, 0.4)
	
	local hitboxOffset = CFrame.new(0, 0, -2)
	local hitboxSize   = Vector3.new(6,6,6)
	
	local strongDmg = {
		weight   = dmgUtils.weighEnum.Medium,
		type     = dmgFlag.lightning,
		dmg      = 16,
		stun     = 1,
		posMult  = 2,
		dodgeH   = -0.2,
		--parryH   = 0.04,
		--[[onHit    = function(attack, source)
			local eroot = attack.enemyEntity.HRootPart
			game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("strpunch", eroot)
		end,]]
	}
	
	local weakDmg = {
		weight   = dmgUtils.weighEnum.Light,
		type     = bit32.bor(dmgFlag.lightning),
		dmg      = 4,
		stun     = 1,
		posMult  = 1,
		--parryH   = 0.04,
		--[[onHit    = function(attack, source)
			local eroot = attack.enemyEntity.HRootPart
			game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("strpunch", eroot)
		end,]]
	}
	
	local endt = tick() + 0.4
	local strongt = tick() + 0.1
	local alreadyHit = {}
	local hcount = 0
	while tick() < endt do
		if humObj:inStun() then
			hcount = 0
			break
		end
		local isStrong = strongt > tick()
		local dmg = isStrong and strongDmg or weakDmg
		
		local _, hits = this:hitbox(hitboxOffset, hitboxSize)
		for _,enemy in pairs(hits) do
			if alreadyHit[enemy] then continue end
			alreadyHit[enemy] = true
			
			local attack = this:makeAtk(
				dmg,
				enemy,
				hurtbox.CFrame.LookVector
			)
			
			local knockPower = if isStrong then 30 else 12
			local newkb = this:knockback(
				attack.atkDir * knockPower,
				0.1,
				false
			)
			
			attack.knockback = newkb

			task.spawn(function()
				this:executeAttack(attack)
				if attack:isParried() then
					moveForce:destroy()
					--humObj.walkSpeed:RemoveMod("stopMoving")
					endt = 0
					hcount = 0
				elseif attack:isHit() or attack:isBlocked() or attack:isDodged() then
					local hitEnemy = attack.enemyEntity
					if hitEnemy and hitEnemy.statusEffects then
						hitEnemy.statusEffects:apply(
							hitEnemy.statusEffects.Shock,
							1.5 -- duration
						)
					end
					hcount += 1
				end
			end)
		end
		task.wait()
	end
	
	--local worldCF = vfx.WorldCFrame
	--vfx.Parent = workspace.Terrain
	--vfx.WorldCFrame = worldCF
	vfx.Name = "a"
	game.Debris:AddItem(vfx, 4)
	
	if hcount == 0 then
		this:endLag(0.4)
	else
		this:endLag(0.2)
	end
	
	humObj.walkSpeed:RemoveMod("stopMoving")
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end


return table.freeze(module)
