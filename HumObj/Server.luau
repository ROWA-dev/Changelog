--!strict

debug.setmemorycategory("HumObjClass")
local packages = game.ReplicatedStorage:WaitForChild("Packages")
local classes  = game.ReplicatedStorage:WaitForChild("Class")

local Signal        = require(packages.Signal)
local AdditiveValue = require(packages.AdditiveValue)
local numVal        = require(packages.valueBase.numberValue)

local weaponBase = require(game.ServerStorage.ROWA.Weps.WepBase.types)
local baseClass  = require(classes.HumObjClient)

local DmgUtils        = require(game.ServerScriptService.Utils.DmgUtils)
local dmgRecord       = require(script.damageRecord)
local cardLoader      = require(script.cardLoader)
local rowaRagdoll     = require(script.RowaRagdoll)
local grabClass       = require(script.Grab)

local knockForce = require(game.ServerScriptService.Knockback)
local emoteBase = require(game.ServerStorage.ROWA.Emotes.EmoteBase)
type atkTyp = DmgUtils.atkTyp
type abilityTyp = any


export type myself = baseClass.myself & {
	plrObj: any?,
	wielding_weapon: weaponBase.myself?,
	using_ability:  abilityTyp?,

	dmgRecord:      dmgRecord.myself,
	cards:          cardLoader.myself,
	ragdoll:        rowaRagdoll.myself,
	grab:           grabClass.myself,

	hurtboxSize: AdditiveValue.myself,
	HurtBox:     BasePart,

	--stopW: boolean?, -- set to true to cancel windup
	isDead: boolean?,
	canAtkThreshold: number,
	dodgeThreshold: number,

	dodgeWindow: number,

	attackAt: number,

	-- Methods
	HandleAttack: (self:myself, attack:atkTyp, atkSource:any?) -> number,

	canAttack: (self: myself) -> boolean,
	canBlock:  (self: myself) -> boolean,
	isParry: (self: myself, atk:atkTyp?) -> boolean,
	isBlock: (self: myself, atk:atkTyp?) -> boolean,
	isDodge: (self: myself, atk:atkTyp?, offset:number?) -> boolean,

	GuardBreak: (self:myself)->(),
	GetBlade: (self:myself)->Instance?,
	feint: (self:myself)->boolean,
	Heal: (self:myself, amt:number) -> number,
	setTransparency: (self:myself, transparency:number?) -> (),
	Die: (self:myself)->(),

	parryAnim: AnimationTrack?,
	blockAnim: AnimationTrack?,
	lastAbilityAnim: AnimationTrack?,

	inCombat: (self:myself) -> boolean,

	-- returns true on sucess
	equippedWeapons: {weaponBase.myself},
	EquipWeapon:   (self: myself, newWeapon: weaponBase.myself) -> boolean,
	UseAbility:    (self: myself, newAbility: abilityTyp) -> boolean,
	UnwieldWeapon: (self: myself) -> boolean,

	stopAbilityAnims: (self:myself)->(),
	ChangeBlocking:   (self:myself, setTo:boolean) -> boolean,
	ChangeState:      (self:myself, state:Enum.HumanoidStateType)->(),

	bodyForce: (self:myself, forceVector:Vector3, t: number, isRootRelative:boolean?, decayT:number?, decayBias: number?) -> knockForce.myself,
	FireVFXClient: (self:myself, any) -> (),

	initReplicateServer: (self: myself, remoteEvent:RemoteEvent, plr:Player) -> (),

	onAttackWindup: Signal.Signal<number>,
	onStunned: Signal.Signal<number>,

	SubscribedEventCB: ((id:number, value: any)->())?,

	_emoteInstance: emoteBase.myself?,
	destroy: (self: myself) -> (),
	--new:     (hum: Humanoid) -> myself,
}

local module = {
	Name = "HumObj_Server",
	__mode = "k"
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

local function landSpeed(humObj:any)
	while humObj and humObj.walkSpeed do
		local remaining = humObj._landHitExpire - time()
		if remaining <= 0 then
			humObj.walkSpeed:RemoveMod("landhit")
			humObj._landHitTask = nil
			break
		end
		task.wait(remaining)
	end
end

local function landHitSpeedBuff(humObj:any)
	humObj.walkSpeed:SetMod("landhit", 4)
	humObj._landHitExpire = time() + 2
	if not humObj._landHitTask then
		humObj._landHitTask = task.spawn(landSpeed, humObj)
	end
end

local onDied = require(script.onDeath)
function module.new(hum: Humanoid): myself
	local abstract = baseClass.new(hum) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	self.isActive 		= true
	self.hurtboxSize    = AdditiveValue.new(1)
	self.dmgRecord      = dmgRecord.new()
	self.cards          = cardLoader.new(self)
	self.ragdoll        = rowaRagdoll.new(hum)
	self.grab           = grabClass.new(hum)

	-- defaults
	self.cooldowns:setCooldown("feint", 2)
	self.cooldowns:setCooldown("feint2", 2)
	self.cooldowns:setCooldown("parry", 1.2)

	self.canAtkThreshold = 0
	self.dodgeThreshold  = 0
	self.dodgeWindow     = 0.3

	self.attackAt        = 0

	self.equippedWeapons = {}
	self.wielding_weapon = nil
	self.using_ability  = nil

	self.onAttackWindup = Signal.new()
	self.onStunned      = Signal.new()

	local function blockedOrHit(attack:atkTyp)		
		local myEntity = self--attack.enemyEntity
		landHitSpeedBuff(myEntity)

		-- TODO turn this into blade Dancer card (resets dash after landing a hit)
		myEntity.cooldowns:Reset("dash")
		myEntity.cooldowns:Reset("dashCancel")

		local enemyEntity = attack.enemyEntity
		local enemyhum = enemyEntity.Hum

		-- continue air combo
		if enemyEntity.floating and enemyhum.FloorMaterial == Enum.Material.Air and myEntity.Hum.FloorMaterial == Enum.Material.Air and myEntity:isSwimming() == false and enemyEntity:isSwimming() == false then
			local keepfloating = 0.2 + attack.dmgTbl.stun

			-- maybe seperate this int oa module or uppercut class? cuz im using this in here and uppercut attack too...
			enemyEntity.floating.Value = keepfloating
			myEntity.floating.Value = keepfloating

			enemyEntity.targetFloatY.Value = myEntity.HurtBox or myEntity.HRootPart
			myEntity.targetFloatY.Value = enemyEntity.HurtBox or enemyEntity.HRootPart
		end
	end

	self.onAttacked:Connect(function(attack: DmgUtils.atkTyp, returnValue: number, atkSource: any?) 
		if attack:isBlocked() then
			game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("block",
				self.HRootPart,
				attack.dmgTbl.dmg,
				attack.dmgTbl.weight,
				attack.atkDir
			)
		elseif attack:isParried() then
			self.cooldowns:Reset("parry")
			self.stun.Value = 0    -- reset stun so they can attack back
			self.canAtkThreshold = 0

			self.ragdoll:unragdoll()
		elseif attack:isHit() then
			local now = tick()
			if now < self.attackAt - 0.1 and self.wielding_weapon then
				local equippedWep:any = self.wielding_weapon
				equippedWep:stopLastAnim(true)
			end

			-- YOUR FEINT WAS READ!! HAHAH
			local lastUsedFeint = self.cooldowns:lastUsedAt("feint")
			if now > lastUsedFeint + 0.2 -- 0.2 is too fast for a read..
				and now < lastUsedFeint + 0.8 -- window for heuristic feint read??
				and self.attacking.Value == true
			then
				--==warn("FEINT READ")
				local mambo = script.Mambo:Clone()
				mambo.Parent = self.HRootPart
				mambo:Play()
				mambo.TimePosition = 0.1
				game.Debris:AddItem(mambo, 4)
			end

			--
			local totalBleed = math.ceil(attack.dmgTbl.dmg/2)

			local attackIsSlash = attack:hasDmgFlag(DmgUtils.dmgFlags.slash)
			local extraVelo = attack.atkDir
			local emitcount = if attackIsSlash then totalBleed else math.floor(totalBleed/2)
			if attack.knockback then
				extraVelo = attack.knockback.force*2
				emitcount += math.floor(attack.knockback.force.Magnitude^0.5)
			end

			if self.Hum and self.Hum.Parent and self.Hum.Parent:FindFirstChild("Torso") then
				local newDmg = attack:CalculateDamage()
				if attackIsSlash == false then
					newDmg = newDmg/2
				end
				local myTorso:BasePart = self.Hum.Parent:FindFirstChild("Torso")::any
				local bfx:ParticleEmitter = myTorso:FindFirstChild("BD")::any
				local bfx2:ParticleEmitter = myTorso:FindFirstChild("BD2")::any
				if bfx == nil then
					bfx = script.BD:Clone()
					bfx.Archivable = false
					bfx.Parent = myTorso
				end
				if bfx2 == nil then
					bfx2 = script.BD2:Clone()
					bfx2.Archivable = false
					bfx2.Parent = myTorso
				end
				local totalBleed1 = math.clamp(newDmg/5,2,200)
				local totalBleed2 = math.clamp(newDmg/4,2,300)
				bfx:Emit(totalBleed1)
				bfx2:Emit(totalBleed2)

				local relativeAtkDir = myTorso.CFrame:VectorToObjectSpace(attack.atkDir)
				local allHitAnims = script.HitAnims:GetChildren()
				local hitAnim = allHitAnims[math.random(1,#allHitAnims)]
				local hitTrack = self:LoadAnimation(hitAnim)
				hitTrack.Priority = Enum.AnimationPriority.Action4
				hitTrack:Play(0,0.5,2)
				if self.lastAbilityAnim then
					self.lastAbilityAnim:Stop()
				end
				self.lastAbilityAnim = hitTrack
			end

			local charSize = self.charSize.Value
			game.ReplicatedStorage.FastRemotes.blood:FireAllClients(
				emitcount,
				self.HRootPart,
				{180,180}, -- spread
				{10*charSize,30*charSize}, -- speed
				{1*charSize,3*charSize}, -- size/10
				extraVelo
			)
		end

		if hum.Health > 0 then return end -- still alive return
		onDied(self, atkSource)
	end)

	self.onAttack:Connect(function(attack, returnValue: number, atkSource: any?) 
		if attack:isHit() then
			if attack:isWep() then
				local maxMana = self.maxMana.Value
				local mana = self.mana
				mana.Value = math.min(mana.Value + attack:CalculateDamage() / 4, maxMana) -- increase mana
			end

			blockedOrHit(attack)
		elseif attack:isBlocked() then
			blockedOrHit(attack)
		end	
	end)
	--

	hum.Died:Connect(function() 
		self:Die()
	end)

	local character:Model = self.HRootPart.Parent::any
	local hurtbox = character:FindFirstChild("hurtbox") or script.hurtbox:Clone()
	hurtbox:WaitForChild("Weld").Part0 = self.HRootPart
	hurtbox.Weld.Part1 = hurtbox
	hurtbox.Parent = character
	self.HurtBox = hurtbox

	do
		local ogHBSize = self.HurtBox.Size
		local function hurtboxSzChange()
			local sz = self.hurtboxSize.Value--*self.charSize.Value
			--print("HURTBOX CHANGE!", sz)
			self.HurtBox.Size = ogHBSize*sz
		end
		self.hurtboxSize.onSet:Connect(hurtboxSzChange)
		self.hurtboxSize.onRemove:Connect(hurtboxSzChange)
	end

	do
		local charSizeChanged = function(key: string) 
			local hroot:any = self.HRootPart
			hroot.Parent:ScaleTo(self.charSize.Value)
		end
		self.charSize.onSet:Connect(charSizeChanged)
		self.charSize.onRemove:Connect(charSizeChanged)
	end

	do
		self.floating.Changed:Connect(function(v)
			if v > 0 and self.isDead ~= true then
				self.ragdoll:unragdoll()
				--[[if self.ragdoll:inRagdoll() then
					print("STOP floatin!")
					self.ragdoll:unragdoll()
					self.targetFloatY.Value = nil
					self.floating.Value = 0
				end]]
			end
		end)
	end

	do
		local function stopEmote()
			if self._emoteInstance then
				if self._emoteInstance.destroy then self._emoteInstance:destroy() end
				self._emoteInstance = nil
			end
		end

		self.onStunned:Connect(function(a0: number) 
			if a0 <= 0 then return end
			stopEmote()
		end)

		self.attacking.Changed:Connect(function(attacking: boolean) 
			if attacking == false then return end
			stopEmote()
		end)

		self.blocking.Changed:Connect(stopEmote)
		--self.onDash:Connect(stopEmote)
	end
	-- passive healing
	task.spawn(function()
		local REGEN_PER_SEC = 0.5
		local REGEN_STEP = 1

		local Humanoid = hum

		while self.isActive do
			while self.isActive and Humanoid.Health < Humanoid.MaxHealth do
				local dt = wait(REGEN_STEP)
				if self.isActive ~= true or self.isDead then return end
				local dh = dt*REGEN_PER_SEC
				Humanoid.Health = math.min(Humanoid.Health + dh, Humanoid.MaxHealth)
			end
			Humanoid.HealthChanged:Wait()
		end
	end)

	-- TODO move this out -- and yes the nested while throttled by a changed:Wait is optimal
	task.spawn(function()
		while  self.isActive do
			while self.isActive and self.floating.Value > 0 do
				local dt = task.wait()
				if self.floating then
					self.floating.Value = math.clamp(self.floating.Value-dt, 0, 2)
				end
			end
			if self.isActive then self.floating.Changed:Wait() end
		end
	end)
	task.spawn(function()
		while self.isActive do
			self.posture.Changed:Wait()
			local posture:any = self.posture
			local maxPosture:any = self.maxPosture
			while self.isActive and posture.Value < maxPosture.Value do
				local dt = wait()
				if self and self.isActive then
					local postureHeal = self.postureHeal.Value
					local newPostureValue =  math.min(posture.v + dt*postureHeal, maxPosture.Value)
					rawset(posture, "v", newPostureValue)
				end
			end
			if self.isActive then self.posture.Changed:Wait() end
		end
	end)
	task.spawn(function()
		while self.isActive do
			self.mana.Changed:Wait()
			local mana:any = self.mana
			local maxMana:any = self.maxMana
			while self.isActive and mana.Value < maxMana.Value do
				local dt = wait()
				if self.isActive then
					local baseGain = 4
					local ration = mana.v / maxMana.Value
					local manaGain = baseGain * (1 - ration)^3
					local newManaValue =  math.min(mana.v + dt*manaGain, maxMana.Value)
					rawset(mana, "v", newManaValue)
				end
			end
			if self.isActive then self.mana.Changed:Wait() end
		end
	end)

	return self
end

function module.destroy(self:myself&any)
	--print("DESTROYED ME!", self.Hum, debug.traceback())
	_clearWieldedWeapon(self)
	if self.isActive ~= true then
		return
	end
	self.isActive = false
	if self.equippedWeapons then
		--warn("DESTROY WEPS RAH", self.equippedWeapons)
		for i, w in ipairs(self.equippedWeapons) do
			local ok,err = pcall(function()
				w:destroy()
			end)
			if not ok then
				warn(err, debug.traceback())
			end
		end
		table.clear(self.equippedWeapons)
	end
	if self.HurtBox then
		self.HurtBox:Destroy()
	end
	if self.HRootPart then
		self.HRootPart:AddTag("norepli")
	end
	if self.blockAnim then
		self.blockAnim:Destroy()
	end
	if self.parryAnim then
		self.parryAnim:Destroy()
	end
	if self._emoteInstance then
		self._emoteInstance:destroy()
		self._emoteInstance = nil
	end
	if self.wielding_weapon then
		self.wielding_weapon:destroy()
	end
	if self.plrObj then
		self.plrObj.HumObj = nil
	end
	self.onAttackWindup:Destroy()
	self.onStunned:Destroy()
	self.cooldowns:Destroy()

	self.hurtboxSize:destroy()
	self.dmgRecord:destroy()
	self.cards:destroy()
	self.ragdoll:destroy()
	self.grab:destroy()

	baseClass.destroy(self)
end

--

function module.Die(self:myself)
	if self.isActive ~= true then return end
	self.Hum.Health = 0
	onDied(self, nil)
end

local returnEnums = DmgUtils.returnEnum
function module.HandleAttack(self:myself, attack:atkTyp, atkSource:any?):number
	local myEntity    = attack.myEntity
	local enemyEntity = attack.enemyEntity

	local myhum    = myEntity.Hum
	local enemyhum = enemyEntity.Hum
	local dmgtbl   = attack.dmgTbl

	if self.isDead then
		return nil
	end

	local atkPostureDMG = attack:CalculatePostureDmg()
	if enemyEntity.isParry and enemyEntity:isParry(attack) then
		game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("parry",
			enemyEntity.HRootPart,
			myEntity.HRootPart,
			dmgtbl.dmg,
			attack.atkDir
		)

		-- stun attacker
		local stunMeOnParried = dmgtbl.stunMeOnParried
		if stunMeOnParried then
			if stunMeOnParried ~= 0 then
				myEntity:Stun(stunMeOnParried)
			end
		else
			if attack.dmgTbl.weight == DmgUtils.weighEnum.Heavy then
				myEntity.canAtkThreshold = tick() + 0.4
				myEntity:Stun(0.3)
			else
				myEntity.canAtkThreshold = tick() + 0.5
				myEntity:Stun(0.4)
			end
		end

		local postureGain = 0
		if atkSource and atkSource.onParried then
			atkSource:onParried(attack)
		end
		if myEntity.wielding_weapon and DmgUtils.isWeaponAtk(dmgtbl.type) then
			postureGain = myEntity.wielding_weapon.postureGain
		end

		-- posture trade
		local humPosture   = myEntity.posture
		local enemyPosture = enemyEntity.posture
		local maxposture   = enemyEntity.maxPosture.Value

		print("posturegain: ", postureGain)
		local postureTransfer = atkPostureDMG - postureGain
		enemyPosture.Value = math.clamp(enemyPosture.Value + postureTransfer/2, 0, maxposture) -- decrease posture
		humPosture.Value = math.clamp(humPosture.Value - postureTransfer/1.5, 0, maxposture) -- increase posture

		return attack:onAttackReturn(returnEnums.parried, atkSource)
	end

	if enemyEntity.isDodge and enemyEntity:isDodge() then
		return attack:onAttackReturn(returnEnums.dodged, atkSource)
	end

	--enemyEntity.HRootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
	-- TODO make block motors like move when hit on client side
	if enemyEntity.isBlock and enemyEntity:isBlock(attack) then
		enemyEntity.posture.Value -= atkPostureDMG
		if enemyEntity.posture.Value > 0 then

			-- todo prob move the to client fx
			local blocksound = nil
			if dmgtbl.weight == DmgUtils.weighEnum.Heavy then
				if DmgUtils.hasDmgFlag(dmgtbl.type, DmgUtils.dmgFlags.slash) then
					blocksound = script.BlockSounds.blockheavy
				else
					blocksound = script.BlockSounds.blunt
				end
			elseif dmgtbl.weight == DmgUtils.weighEnum.Medium then
				if DmgUtils.hasDmgFlag(dmgtbl.type, DmgUtils.dmgFlags.slash) then
					blocksound = script.BlockSounds.blocklight
				else
					blocksound = script.BlockSounds.blunt
				end
			else
				if DmgUtils.hasDmgFlag(dmgtbl.type, DmgUtils.dmgFlags.slash) then
					blocksound = script.BlockSounds.blocklight
				else
					blocksound = script.BlockSounds.blunt
				end
			end

			blocksound = blocksound:Clone()
			blocksound.Parent = enemyEntity.HRootPart
			blocksound:Play()
			game.Debris:AddItem(blocksound, 4)

			attack:ApplyKnockback()
			if atkSource and atkSource.onBlocked then
				atkSource:onBlocked(attack)
			end
			return attack:onAttackReturn(returnEnums.blocked, atkSource)
		end

		--- POSTURE BREAK
		if enemyEntity.GuardBreak then enemyEntity:GuardBreak() end
	end

	--[[if dmgtbl["onHit"] then
		dmgtbl.onHit(attack, atkSource)
	end]]

	attack:ApplyKnockback()

	local finalDamage = attack:CalculateDamage()
	enemyhum.Health -= finalDamage

	if dmgtbl["onHit"] then
		dmgtbl.onHit(attack, atkSource)
	end

	enemyEntity.dmgRecord:addEntry(myEntity, finalDamage)
	enemyEntity:Stun(dmgtbl.stun)

	-- if both hit eachother then reset stun so they can both hit again
	-- prevents awkward look at eachother while stunned...
	if enemyEntity:inStun() and myEntity:inStun() then
		enemyEntity.stun.Value = tick() + 0.1
		myEntity.stun.Value    = tick() + 0.1
	end
	return attack:onAttackReturn(returnEnums.hit, atkSource)
end


function _clearWieldedWeapon(self:myself)
	local wielding = self.wielding_weapon
	if wielding then
		if wielding.unwield then
			--wielding:unequip()
			pcall(wielding.unequip, wielding)
		end
		self.wielding_weapon = nil
		return true
	end
	return false
end


--- false is failed to equip
function module.EquipWeapon(self:myself, newWeapon: weaponBase.myself): boolean
	if newWeapon == nil then
		error("attempted to :EquipWeapon(nil). u forgot to put a weapon stupid!")
	end
	_clearWieldedWeapon(self)

	local alreadyIndex = nil
	for i, w in ipairs(self.equippedWeapons) do
		if w == newWeapon then
			alreadyIndex = i
			break
		end
	end
	if alreadyIndex then
		table.remove(self.equippedWeapons, alreadyIndex) -- remove old spot
	end

	local maxEquippedSlots = 2

	--print(self.equippedWeapons)
	while #self.equippedWeapons >= maxEquippedSlots do
		local oldest = table.remove(self.equippedWeapons, 1) -- queue pop oldest
		if oldest and oldest.unequip then
			--print("UNEUIP", oldest._humObj)
			oldest:unequip()
		end
	end

	table.insert(self.equippedWeapons, newWeapon)
	newWeapon:equip(self)
	newWeapon:wield()

	return true
end

function module:UnwieldWeapon(): boolean
	return _clearWieldedWeapon(self)
end

--

function module.UseAbility(self:myself, newAbility: abilityTyp)
	if self.isActive ~= true then return end
	if newAbility._humObj ~= self then
		error("tried to use another humObj("..tostring(newAbility._humObj)..") ability")
	end

	local nearAbtToHit = (self.attackAt - tick())
	if nearAbtToHit > 0.06 then
		task.spawn(self.feint, self)
	end

	local atking = self.attacking
	if atking.Value == true then
		atking.Changed:Wait()
		task.wait()
	end
	-- moved this inside abilitybase self.using_ability = newAbility
	local endt = tick() + 0.2
	while tick() < endt and self.isActive and self.attacking.Value == false do
		if newAbility.use then
			newAbility:use()
		end
		task.wait()
	end

end

function module.inCombat(self:myself): boolean
	return self.dmgRecord:inCombat()
end

--

function module.isParry(self:myself, atk:atkTyp?)
	local ogWindow = self.parryWindow.Value/self.timeScale.Value
	local window = ogWindow

	local inStun = self:inStun()
	if inStun then
		-- harder to parry in stun
		window -= 0.08 
	end
	if atk and atk.myEntity then
		if atk.dmgTbl.parryH then
			window += atk.dmgTbl.parryH
		end

		local enemyEntity = atk.myEntity
		local enemyRoot:BasePart = enemyEntity.HurtBox or enemyEntity.HRootPart
		local humRoot:BasePart   = self.HurtBox or self.HRootPart
		local dot = humRoot.CFrame.LookVector:Dot(enemyRoot.CFrame.LookVector)

		if dot > 0.1 then -- is behind via angle
			--harder to parry if attacked from behind

			local toEnemy = (enemyRoot.Position - humRoot.Position).Unit
			local facingDot = humRoot.CFrame.LookVector:Dot(toEnemy)
			--print(facingDot)
			if facingDot < 0 then -- is behind via position
				window -= 0.06
			end
		end
	end
	-- TODO maybe clamp parrywindow...
	return tick() <= self.cooldowns:lastUsedAt("parry") + window
end

function module.isDodge(self:myself, atk:atkTyp?, offset:number?)
	local offset:number = offset or 0
	if atk then
		local velo = self.HRootPart.AssemblyLinearVelocity
		local dif = velo.Unit:Dot(atk.atkDir)
		-- dif is -1 if moving opposite of atk dir
		-- dif is 1 if moving same dir as atk

		if velo.Magnitude > 8 then
			self.dodgeThreshold -= dif*0.1
		end
		if atk.dmgTbl.dodgeH then
			offset += atk.dmgTbl.dodgeH
		end
	end
	return tick() <= self.dodgeThreshold + (offset or 0)
end

function module.isBlock(self:myself, atk:atkTyp?)
	local isBlockingValue = self.blocking.Value
	if atk and atk.myEntity and isBlockingValue then
		local enemyEntity = atk.myEntity
		local enemyRoot:BasePart = enemyEntity.HurtBox or enemyEntity.HRootPart
		local humRoot:BasePart   = self.HurtBox or self.HRootPart
		local dot = humRoot.CFrame.LookVector:Dot(enemyRoot.CFrame.LookVector)

		if dot > 0.1 then -- is behind via angle
			local toEnemy = (enemyRoot.Position - humRoot.Position).Unit
			local facingDot = humRoot.CFrame.LookVector:Dot(toEnemy)
			--print(facingDot)
			return facingDot > 0 -- is in front via position
		end
	end
	if self.ragdoll:inRagdoll() then -- cannot block in ragdoll
		return false
	end

	return 
		isBlockingValue
		or tick() <= self.cooldowns:lastUsedAt("parry") + self.parryWindow.Value + 0.2 -- 0.2s of ending block frames...
end

function module.canAttack(self:myself)
	local now = tick()
	local lastDashed = math.min(self.cooldowns:lastUsedAt("dash")+0.2, self._lastDashed + 0.3/self.timeScale.Value)

	return (
		not self:inStun() -- cant attack in stun
			--and self:isDodge() == false
			and now > lastDashed
			and now > self.canAtkThreshold
		--and now > self.cooldowns:lastUsedAt("parry")+0.4 -- cant attack right after missing a parry for 0.4s
	)
end

function module.Stun(self:myself, stunTime:number)
	if self.isActive ~= true then return end
	self.onStunned:Fire(stunTime)
	if tick() < self.attackAt - 0.1 and self.wielding_weapon then
		self.wielding_weapon:stopLastAnim()
	end
	baseClass.Stun(self, stunTime)
end

function module.GuardBreak(self:myself)
	self.posture.Value = self.maxPosture.Value
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("postureBreak", self.HRootPart)

	print(self, "POSTURE BROKEN!")

	self:TrueStun(1.6) -- 1.6 second of posturebreak true stun
	self:Stun(1.9)     -- 1.9 second of posturebreak stun
	if self.blocking.Value == true then
		self:ChangeBlocking(false)
	end

	task.spawn(function()
		local gbreakTrack = self:PlayAnim(script.blockBroke, 0, 1, 1)

		local bleed = 0
		while self.isActive and self:inTrueStun() and gbreakTrack do
			local now = tick()
			if tick() > bleed then bleed = now + 0.1
				local char = self.Hum.Parent::any
				local myTorso:BasePart = char:FindFirstChild("Torso")::any
				local bfx:ParticleEmitter = myTorso:FindFirstChild("BD")::any
				local bfx2:ParticleEmitter = myTorso:FindFirstChild("BD2")::any
				if bfx and bfx2 then
					bfx:Emit(2)
					bfx2:Emit(1)
				end

				game.ReplicatedStorage.FastRemotes.blood:FireAllClients(
					1,
					self.HRootPart,
					{180,180}, -- spread
					{10,30}, -- speed
					{1,3} -- size/10
				)
			end

			task.wait()
		end
		if gbreakTrack then
			gbreakTrack:Stop()
			gbreakTrack:Destroy()
		end
	end)
end

function module.GetBlade(self:myself): Instance?
	local wep = self.wielding_weapon
	if wep and wep._model then
		return wep._model:FindFirstChild("Blade", true)
	end
	return nil-- self.HRootPart.Parent:FindFirstChild("Blade", true)
end

function module.feint(self:myself): boolean
	local wepFeint = (self.wielding_weapon and self.wielding_weapon:feint())
	local ablFeint = (self.using_ability and self.using_ability:feint())
	return wepFeint or ablFeint
end

function module.Heal(self:myself, amt:number): number
	self.Hum.Health += amt
	return amt
end

type ogTransparency = {
	[Instance]: number | NumberSequence
}

function module.setTransparency(self: myself & { _ogTransparency: ogTransparency }, transparency: number?)
	if self._ogTransparency == nil then
		self._ogTransparency = {}
	end

	local ogTransparency = self._ogTransparency
	local char = self.HRootPart and self.HRootPart.Parent
	if not char then return end

	print("set transparency", transparency)

	if transparency == nil or transparency == 0 then
		for inst:any, value in pairs(ogTransparency) do
			if inst and inst.Parent then
				if inst:IsA("BasePart") or inst:IsA("Decal") then
					inst.Transparency = value :: number
				elseif inst:IsA("ParticleEmitter") then
					inst.Transparency = value :: NumberSequence
				end
			end
		end
		table.clear(ogTransparency)
		return
	end

	-- clamp
	transparency = math.clamp(transparency, 0, 1)

	for _, inst:any in pairs(char:GetDescendants()) do
		if inst:IsA("BasePart") or inst:IsA("Decal") then
			if ogTransparency[inst] == nil then
				ogTransparency[inst] = inst.Transparency
			end
			inst.Transparency = math.max(inst.Transparency, transparency)
		elseif inst:IsA("ParticleEmitter") then
			if ogTransparency[inst] == nil then
				ogTransparency[inst] = inst.Transparency
			end
			inst.Transparency = NumberSequence.new(transparency)
		end
	end
end


function module.Dash(self:myself, dir:Vector3, fromSS:boolean?): boolean
	if self:canDash() == false then return false end
	self.dodgeThreshold = tick() + self.dodgeWindow
	self.ragdoll:unragdoll()
	if self:isBlock() == true then
		warn("RAH punish dash while blocking")
		self.cooldowns:trigger("dashCancel")
		self:ChangeBlocking(false)
	end
	--print("ssDASH", dir)
	return baseClass.Dash(self, dir, fromSS)
end

function module.DashCancel(self:myself, dir:Vector3, fromSS:boolean?): boolean
	if self.cooldowns:canTrigger("dashCancel") == false then return false end
	self.dodgeThreshold = math.min(self.dodgeThreshold, tick() + 0.16)
	return baseClass.DashCancel(self, dir, fromSS)
end

function module.stopAbilityAnims(self:myself)
	if self and self.lastAbilityAnim then
		self.lastAbilityAnim:Stop()
		self.lastAbilityAnim = nil

		if self.wielding_weapon then
			self.wielding_weapon:stopLastAnim()
		end
	end
end

local function isProperParry(self:myself)
	return tick() + self.timeStunned > self.stun.Value + 0.2
end

function module.canBlock(self:myself&any)
	local now = tick()
	return (
		self.attacking.Value == false -- cant block while attacking
			and now > self._lastDashed + 0.3/self.timeScale.Value
			--and now > self.cooldowns:lastUsedAt("dash") + 0.3
			and baseClass.inTrueStun(self) == false
	)
end

--- returns true if it was a parry
function module.ChangeBlocking(self:myself&any, setTo:boolean): boolean																																															-- A I R Z Y was here and made every script
	self._wantblock = setTo
	if setTo == true and not self:canBlock()  then
		while not self:canBlock() and self._wantblock == true do
			task.wait()
		end
		if self._wantblock == false then
			warn("CANCEL", self:canAttack())
			return self.blocking.Value
		end
		if self:canBlock() == false then
			return false
		end
		print("atkend", setTo)
	end
	--setTo = self._wantblock
	if self.blocking.Value ~= setTo then
		self._lastBlocked = tick()

	end
	self.blocking.Value = setTo
	if setTo == true then
		self.canAtkThreshold = math.max(self.canAtkThreshold, tick()+0.4/self.timeScale.Value)
	end

	local wep:weaponBase.myself = self.wielding_weapon
	if setTo == true and isProperParry(self) and self.cooldowns:canTrigger("parry") then self.cooldowns:trigger("parry")
		if wep and self.blockAnim and self.parryAnim then
			self.blockAnim:Stop()
			self:PlayTrack(self.parryAnim)
			self:AddConnection(self.parryAnim.Stopped:Once(function()  -- field upvalue from table field 'parryAnim'
				if self.blocking.Value == true then
					self:PlayTrack(self.blockAnim)
					self:RemConnection("onParryStop")
				end
			end), "onParryStop")
		end
		return true
	end

	if wep and self.blockAnim --[[and self.parryAnim]] then
		if setTo == true then
			self:PlayTrack(self.blockAnim)
		else
			self.blockAnim:Stop()
		end
	end
	return false
end

function module.FireVFXClient(self:myself, ...)
	if self.plrObj == nil then
		return
	end
	local plr = self.plrObj.Plr
	if plr then
		game.ReplicatedStorage.RemoteEvents.VFX:FireClient(plr, ...)
	end
end

function module.ChangeState(self:myself, state:Enum.HumanoidStateType)
	if self.plrObj then
		local plr = self.plrObj.Plr
		if plr then
			game.ReplicatedStorage.RemoteEvents.VFX:FireClient(plr, "cstate", state)
		end
	else
		self.Hum:ChangeState(state)
	end
end

function module.bodyForce(self:myself, forceVector:Vector3, t: number, isRootRelative:boolean?, decayT:number?, decayBias: number?): knockForce.myself
	local timeScale = self.timeScale.Value
	local iTimeScale = 1/timeScale


	forceVector *= self.charSize.Value * timeScale
	t*=iTimeScale
	if decayT then
		decayT *= iTimeScale
	end

	return knockForce(forceVector, self.HRootPart, t, isRootRelative, decayT, decayBias)
end

---

function module.initReplicateServer(self:myself, remoteEvent:RemoteEvent, plr:Player)
	self.maxPosture:initReplicateServer(5, remoteEvent, plr)
	self.walkSpeed:initReplicateServer(6, remoteEvent, plr)
	self.sprintSpeed:initReplicateServer(15, remoteEvent, plr)
	self.dashPower:initReplicateServer(16, remoteEvent, plr)
	self.postureHeal:initReplicateServer(17, remoteEvent, plr)
	self.slideSpeed:initReplicateServer(18, remoteEvent, plr)
	self.charSize:initReplicateServer(19, remoteEvent, plr)

	self.stun.Changed:Connect(function(number: number) 
		local duration = self.timeStunned--number-tick()
		if number == 0 then
			duration = 0
		end
		--print("STUN duration:",duration, number)
		remoteEvent:FireClient(plr, 1, duration)
	end)
	self.attacking.Changed:Connect(function(boolean: boolean)
		--print("RAH", boolean)
		remoteEvent:FireClient(plr, 2, boolean)
	end)
	self.blocking.Changed:Connect(function(boolean: boolean) 
		remoteEvent:FireClient(plr, 3, boolean)
	end)
	self.posture.Changed:Connect(function(number: number) 
		remoteEvent:FireClient(plr, 4, number)
	end)
	self.parryWindow.Changed:Connect(function(number: number) 
		remoteEvent:FireClient(plr, 7, number)
	end)
	self.onDash:Connect(function(dir: Vector3) 
		remoteEvent:FireClient(plr, 8)
	end)
	self.onDashCancel:Connect(function(dir: Vector3) 
		remoteEvent:FireClient(plr, 9)
	end)

	self.cooldowns.CooldownChanged:Connect(function(id: string, value: number) 
		remoteEvent:FireClient(plr, 10, id, value)
	end)
	self.cooldowns.CooldownTriggered:Connect(function(id: string, value: number) 
		remoteEvent:FireClient(plr, 11, id, value)
	end)
	self.floating.Changed:Connect(function(number: number)
		remoteEvent:FireClient(plr, 12, number)
	end)
	self.targetFloatY.Changed:Connect(function(value: any?) 
		remoteEvent:FireClient(plr, 20, value)
	end)
	self.timeScale:initReplicateServer(21, remoteEvent, plr)
	self.maxMana:initReplicateServer(22, remoteEvent, plr)
	self.mana.Changed:Connect(function(number: number) 
		remoteEvent:FireClient(plr, 23, number)
	end)


	--[[local rcon = remoteEvent.OnServerEvent:Connect(function(plr: Player, id:number, value: any)
		if plr.Character and self.Hum and plr.Character:FindFirstChild("Humanoid") ~= self.Hum then
			return
		end]]
	self.SubscribedEventCB = function(id:number, value: any)
		--print("im working!", id, value)
		if id == 1 then
			self.sprinting.Value = value
		elseif id == 13 then
			self._lastJumped = tick()
		elseif id == 14 then
			self.sliding.Value = value
		end
	end
	--self:AddConnection(rcon, "repliServer")
end

return table.freeze(module)