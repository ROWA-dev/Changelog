--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Hitself"
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
	-- cooldownID = "strongLeft"
	--if this:canTriggerCD(cooldownID) ~= true then return end
	print("USE ABILITY!")
	local anim = this:PlayAnim(script.Punch, 0, 1, 1.4)
	local root = this._humObj.HurtBox
	
	local startSnd = script.start:Clone()
	startSnd.Parent = root
	startSnd:Play()
	game.Debris:AddItem(startSnd,4)

	local char:any = root.Parent
	local LeftGripAttachment = char:FindFirstChild("Left Arm"):FindFirstChild("LeftGripAttachment")
	local Idle = script.idle:Clone()
	Idle.Parent = LeftGripAttachment
	game.Debris:AddItem(Idle,4)
	
	local feinted = this:feintWait(0.6, function(dt: number)
		Idle:Emit(1)
	end)
	if feinted then
		if anim then
			anim:Stop()
		end
		game.Debris:AddItem(startSnd, 0)
		game.Debris:AddItem(Idle, 0)
		return
	end
	
	--this:triggerCD(cooldownID, 8, true)
	this:bodyForce(root.CFrame.LookVector*14, 0.2)
	
	if anim then
		anim:AdjustSpeed(1.2)
	end
	
	local PunchS = script.crack:Clone()
	PunchS.Parent = root
	PunchS:Play()
	game.Debris:AddItem(PunchS,4)
	
	for _,v in pairs(script.Folder:GetChildren()) do
		local emit = v:Clone()
		emit.Parent = LeftGripAttachment
		emit:Emit(tonumber(v.Name))
		game.Debris:AddItem(emit,4)
	end
	
	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox
	
	local hitboxOffset = CFrame.new(0, 0, -4)
	local hitboxSize   = Vector3.new(9,9,9)
	local hits		   = this:hitbox(hitboxOffset, hitboxSize)
	table.insert(hits, humObj.Hum)
	
	local dmgTbl = {
		weight   = dmgUtils.weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.blunt),
		dmg      = 1,
		stun     = 1,
		posMult  = 1,
		--parryH   = -0.1,
		onHit    = function(attack, source)
			local eroot = attack.enemyEntity.HRootPart
			game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("strpunch", eroot)
		end,
	}
	
	for _,enemhum in pairs(hits) do
		local attack = this:makeAtk(
			dmgTbl,
			enemhum,
			hurtbox.CFrame.LookVector
		)
		local newkb = this:knockback(hurtbox.CFrame.LookVector*60 + Vector3.new(0,20,0), 0.1, false, -1)
		attack.knockback = newkb

		this:executeAttack(attack)
		if attack:isHit() then
			attack.enemyEntity.ragdoll:ragdoll(60, true, attack.atkDir*100)
		end
	end
	
	humObj.canAtkThreshold = tick() + 0.24
	this:endLag(0.1)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end


return table.freeze(module)
