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
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)

local function useFunc(this:myself & any)
	local cooldownID = "fireStab"
	if this:canTriggerCD(cooldownID) ~= true then return end
	print("USE ABILITY!")
	local anim = this:PlayAnim(script.Anim, 0, 1, 1)
	local root = this._humObj.HurtBox

	fireVFX("fsShine2",
		-- "Right Arm" is an R6-rig assumption, but it is already a FALLBACK to
		-- GetBlade() and the whole chain nil-degrades, so an odd-shaped entity
		-- using this ability just gets no shine rather than an error. Left as
		-- an ability-local quirk on purpose: don't grow the entity contract.
		this._humObj:GetBlade()
			or (this._humObj.Model and this._humObj.Model:FindFirstChild("Right Arm"))
	) -- LAMBDA OF DOOM	

	local feinted = this:feintWait(0.42)
	local cd = 10

	if feinted then
		if anim then
			anim:Stop()
		end
		this._lastUsed = math.max(this._lastUsed or 0, tick() - cd*0.5)
		return
	end
	fireVFX("fstabb", root)
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
	local _, hits	   = this:hitbox(hitboxOffset, hitboxSize)

	local dmgTbl = {
		weight   = dmgUtils.weighEnum.Heavy,
		type     = bit32.bor(dmgFlag.fire),
		dmg      = 8,
		stun     = 0.6,
		posMult  = 1,
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

	for _,enemy in pairs(hits) do
		local attack = this:makeAtk(
			dmgTbl,
			enemy,
			hurtbox.CFrame.LookVector
		)
		
		this:executeAttack(attack)
		if attack:isHit() then
			attack.enemyEntity.statusEffects:apply(
				humObj.statusEffects.Burn,
				10, -- duration
				3 -- dmg
			)
		end
	end

	this:endLag(0.1)
end

function module.use(self:myself)
	return baseClass.use(self, useFunc)
end


return table.freeze(module)
