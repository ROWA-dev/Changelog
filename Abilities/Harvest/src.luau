--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself
type humObj = baseClass.humObj

local module = {
	Name = "Harvest"
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

local BLEED_T, BLEED_DMG = 4, 1

local hitSfx  = require(game.ServerStorage.ROWA.Modules.hitSfx)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local HARVEST = {
	weight   = dmgUtils.weighEnum.Medium,
	type     = dmgFlag.blood,
	dmg      = 10,
	stun     = 0.6,
	posMult  = 1,
	onHit = function(attack)
		local eroot = attack.enemyEntity.HRootPart
		hitSfx(eroot, "HeavyCut", "HitChop")
		
		local fx = script.slice:Clone()
		fx.Parent = eroot
		fx.glow:Emit(1)
		fx.vertical:Emit(1)
		game.Debris:AddItem(fx, 4)
	end,
}

local HITBOX_CF = CFrame.new(0, 0, -4)
local HITBOX_SZ = Vector3.new(6,7,7)

-- active frames: the swing rides a lunge, so one snapshot lands before the body
-- arrives. `lead` is the other half if it still reads short.
local SWING = table.freeze({ window = 0.2 })

local function drawScythe(humObj:any): any
	local char = humObj.Model
	local arm = char and char:FindFirstChild("Right Arm")
	if arm == nil then return nil end

	local scythe:any = script.bscythe:Clone()
	scythe.Motor6D.Part0 = arm
	scythe.Motor6D.Part1 = scythe
	scythe.Parent = char
	scythe.swingslash:Play()
	scythe.blood_scythe_hit:Play()
	game.Debris:AddItem(scythe, 8)
	return scythe
end

local function useFunc(this:myself&any)
	local cooldownID = "harvest"
	if this:canTriggerCD(cooldownID) ~= true then return end

	local humObj  = this._humObj
	local hurtbox = humObj.HurtBox
	local char:any = hurtbox.Parent
	local anim    = this:PlayAnim(script.anim, 0, 1, 1)
	local scythe  = drawScythe(humObj)

	-- the scythe takes the hand for the duration.
	fireVFX("hideTool", char)

	-- showArms is the only restore, so every exit owes it, and the scythe with it.
	local function restore()
		fireVFX("showArms", char)
		if scythe then scythe.Transparency = 1; game.Debris:AddItem(scythe,4) end
	end

	humObj.walkSpeed:SetMod("stopMoving", -100)
	-- guarded: drawScythe returns nil on an armless rig, and a throw here abandons the restore inside use()'s pcall.
	local committed = this:windup(0.5, function(dt)
		if scythe then scythe.BD:Emit(1) end
	end)
	humObj.walkSpeed:RemoveMod("stopMoving")

	if not committed then
		if anim then anim:Stop() end
		restore()
		return
	end
	this:triggerCD(cooldownID, 6, true)
	local bmover = this:bodyForce(hurtbox.CFrame.LookVector*12, 0.2)

	local _, hits = this:sweep(HITBOX_CF, HITBOX_SZ, SWING)
	-- sweep bails on stun; this is the interrupt branch it bailed for.
	if humObj:inStun() then
		if anim then anim:Stop() end
		restore()
		if bmover then bmover:destroy() end
		return
	end
	
	local landed = false
	for _,enemy in pairs(hits) do
		local attack = this:makeAtk(HARVEST, enemy, hurtbox.CFrame.LookVector)
		attack.knockback = this:knockback(attack.atkDir*6, 0.1, false, -1)

		this:executeAttack(attack)
		if attack:isHit() then
			attack.enemyEntity.statusEffects:apply(
				humObj.statusEffects.Bleed,
				BLEED_T,
				BLEED_DMG
			)
			humObj:Heal(attack:CalculateDamage() * 0.5)
			landed = true
		else
			-- lowercase destroy: bmover is a KBObj, not an Instance. nil when the humObj went away.
			if bmover then bmover:destroy() end
		end
	end

	if landed == true then
		this:endLag(0.1)
	else
		this:endLag(0.3)
	end
	restore()
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end


return table.freeze(module)
