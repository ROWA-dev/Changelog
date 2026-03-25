--!strict
local baseClass = require(script.Parent.AbilityBase)
export type myself = baseClass.myself

type humObj = baseClass.humObj
local module = {
	manaUse = 6,
	Name = "FireStab"
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

local function useFunc(this:myself & any)
	local cooldownID = "fireStab"
	if this:canTriggerCD(cooldownID) ~= true then return end
	print("USE ABILITY!")
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)
	local root = this._humObj.HurtBox

	local vfx = game.ReplicatedStorage.RemoteEvents.VFX	
	vfx:FireAllClients("fsShine2",
		this._humObj:GetBlade()
			or (
				this._humObj.HRootPart
				and this._humObj.HRootPart.Parent
				and this._humObj.HRootPart.Parent:FindFirstChild("Right Arm")
			)
	) -- LAMBDA OF DOOM	

	local feinted = this:feintWait(0.5)
	local cd = 10

	if feinted then
		if anim then
			anim:Stop()
		end
		this._lastUsed = math.max(this._lastUsed or 0, tick() - cd*0.5)
		return
	end
	vfx:FireAllClients("fstabb", root)
	this:useMana()


	-- rem cd
	local now = tick()

	local elapsed = now - (this._lastUsed or 0)
	local remaining = math.max(0, cd - elapsed)

	print("REMAINING:",remaining, elapsed)
	this:triggerCD(cooldownID, remaining)
	this._lastUsed = now
	--

	local humObj   = this._humObj
	local hurtbox  = humObj.HurtBox

	local hitboxOffset = CFrame.new(0, 0, -4)
	local hitboxSize   = Vector3.new(6,6,8)
	local hits		   = this:hitbox(hitboxOffset, hitboxSize)

	local dmgTbl = {
		weight   = dmgUtils.weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.fire),
		dmg      = 12,
		stun     = 0.6,
		posMult  = 2,
		parryH   = -0.04,
		onHit = function(attack, source:any)
			local eroot = attack.enemyEntity.HRootPart
			local sound = script.HeavyCut:Clone()
			sound.TimePosition = 0.05
			sound.PlaybackSpeed = math.random(9,13)/10
			sound.Parent = eroot
			sound:Play()
			game.Debris:AddItem(sound, 4)
		end,
	}

	for _,enemhum in pairs(hits) do
		local attack = this:makeAtk(
			dmgTbl,
			enemhum,
			hurtbox.CFrame.LookVector
		)

		this:executeAttack(attack)
	end

	this:endLag(0.1)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end


return table.freeze(module)
