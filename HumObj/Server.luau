--!strict

debug.setmemorycategory("HumObjClass")
local packages = game.ReplicatedStorage:WaitForChild("Packages")
local classes  = game.ReplicatedStorage:WaitForChild("Class")

local Signal        = require(packages.Signal)
local AdditiveValue = require(packages.AdditiveValue)
local numVal        = require(packages.valueBase.numberValue)

local weaponBase = require(game.ServerStorage.ROWA.Weps.WepBase.types)
local baseClass  = require(classes.HumObjClient)
local Debug      = require(game.ReplicatedStorage.Modules.Debug)

local DmgUtils        = require(game.ServerScriptService.Utils.DmgUtils)
local dmgRecord       = require(script.damageRecord)
local cardLoader      = require(script.cardLoader)
local rowaRagdoll     = require(script.RowaRagdoll)
local statusEffects   = require(game.ServerStorage.ROWA.Class.StatusEffects)
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
	statusEffects:  statusEffects.myself,
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

local function landHitSpeedBuff(humObj:any, extraTime:number)
	humObj.walkSpeed:SetMod("landhit", 5+extraTime)
	
	local speedboostTime = 0.8+extraTime
	--print(speedboostTime)
	humObj._landHitExpire = time() + speedboostTime
	if not humObj._landHitTask then
		humObj._landHitTask = task.spawn(landSpeed, humObj)
	end
end

local onDied = require(script.onDeath)

-- HandleAttack's branches. Pure moves; see the dispatcher for the order.
local resolveParry = require(script.resolution.resolveParry)
local resolveBlock = require(script.resolution.resolveBlock)
local resolveHit   = require(script.resolution.resolveHit)

--[[ One regen loop, four call sites.

	Preserves the exact `while active do while active and belowMax do step end
	Changed:Wait() end` shape the four hand-written loops used -- that nested
	idiom is deliberate throttling and is an explicit non-goal to change.

	  changedSignal  what to wait on when the value is already full
	  isBelowMax()   should we keep stepping?
	  step(dt)       do one tick. Return FALSE to kill the loop entirely.
	  stepTime       nil     = wait()      -- legacy ~30Hz, returns elapsed
	                 number  = wait(n)
	                 "frame" = task.wait() -- true per-frame

	wait() vs task.wait() IS A BALANCE DIFFERENCE, NOT A STYLE ONE.
	posture and mana used BARE wait(), which yields ~30Hz. floating used
	task.wait(), which is per-frame (~60Hz+). Since every one of these
	loops integrates `dt * rate`, swapping the two changes how much regen
	lands per second on a fast client. An earlier draft of this helper used
	task.wait() for all of them and would have silently doubled posture and
	mana regen. Each call site keeps the timer it actually had.

	The `step` return value exists for health, which alone did
	`if not active or isDead then RETURN end` -- exiting the whole loop rather
	than just the inner one. Flattening that to a `break` would leave a dead
	player's regen coroutine alive and waiting on HealthChanged forever.
]]
local function regenLoop(self: any, changedSignal: any, isBelowMax: () -> boolean, step: (number) -> boolean, stepTime: (number | string)?)
	task.spawn(function()
		while self.isActive do
			while self.isActive and isBelowMax() do
				local dt
				if stepTime == "frame" then
					dt = task.wait()
				elseif stepTime then
					dt = wait(stepTime :: number)
				else
					dt = wait()
				end
				if self.isActive ~= true then return end
				if step(dt) == false then return end
			end
			if self.isActive then changedSignal:Wait() end
		end
	end)
end

--- HumObj GENUINELY REQUIRES a Humanoid, unlike EntityBase.
--  It is the full player-character surface: ragdoll, grab, CharController and
--  the animation stack all take a Humanoid directly. So it refuses up front
--  with a clear message instead of failing five subsystems deep.
--  An odd-shaped entity should NOT be a HumObj -- subclass EntityBase and take
--  Combatant's inert defaults instead.
function module.new(hum: Humanoid): myself
	if typeof(hum) ~= "Instance" or not hum:IsA("Humanoid") then
		error(
			"HumObj requires a Humanoid, got " .. tostring(hum) .. ". "
				.. "For an entity without a Humanoid, subclass EntityBase instead "
				.. "and let Combatant's inert defaults cover parry/posture/dodge.",
			2
		)
	end
	local abstract = baseClass.new(hum) :: baseClass.myself
	local self:myself = setmetatable(abstract, module) :: any

	self.isActive 		= true
	-- destroy() stamps "norepli" on the root to mark it dead. a live HumObj on
	-- that same root must clear it, or the marker outlives the corpse: loadChar
	-- does Unregister(hum) -> Get(hum), which destroys and rebuilds on a char
	-- that never died, and CharController reads the stale tag as "apply air
	-- friction forever". Symmetric with destroy, keep it that way.
	if self.HRootPart then
		self.HRootPart:RemoveTag("norepli")
	end
	self.hurtboxSize    = AdditiveValue.new(1)
	self.dmgRecord      = dmgRecord.new()
	self.cards          = cardLoader.new(self)
	self.ragdoll        = rowaRagdoll.new(hum)
	self.statusEffects  = statusEffects.new(self)
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
		landHitSpeedBuff(myEntity, attack.dmgTbl.stun*2)

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

	self:AddConnection(self.onAttacked:Connect(function(attack: DmgUtils.atkTyp, returnValue: number, atkSource: any?) 
		if attack:isBlocked() then
			-- _lastBlocked means "my guard last DID something", not "blocking.Value
			-- last flipped". ChangeBlocking only stamps the EDGES, so holding guard
			-- through a string let it expire mid-combo. Sole reader is ToshiCounter.
			self._lastBlocked = tick()
			game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("block",
				self.HRootPart,
				attack.dmgTbl.dmg,
				attack.dmgTbl.weight,
				attack.atkDir
			)
		elseif attack:isParried() then
			self._lastBlocked = tick() -- see isBlocked branch above
			self.cooldowns:Reset("parry")
			self.stun.Value = 0    -- reset stun so they can attack back
			self.canAtkThreshold = 0

			self.ragdoll:unragdoll()
		elseif attack:isHit() then
			local now = tick()
		--[[ HYPER ARMOUR. This cancel is a SECOND, INDEPENDENT interrupt --
				it hangs off onAttacked and never consults stun, so gating
				:Stun alone left an armoured player still losing their swing to
				every chip hit. "Cannot be stunned" has to mean "cannot be
				interrupted" or the effect does nothing that a player can feel.
				True stun still cancels: it goes through :Stun, which fires
				onStunned -> the stopLastAnim at the top of module.Stun. ]]
			if now < self.attackAt - 0.1 and self.wielding_weapon and not self:inHyperArmour() then
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
				-- this flinch is what cancels abilities: it takes over
				-- lastAbilityAnim. one slot, so both cannot play -- armoured
				-- skips the anim entirely. blood/vfx are outside this branch.
				if not self:inHyperArmour() then
					local hitTrack = self:LoadAnimation(hitAnim)
					hitTrack.Priority = Enum.AnimationPriority.Action4
					hitTrack:Play(0,0.5,2)
					if self.lastAbilityAnim then
						self.lastAbilityAnim:Stop()
					end
					self.lastAbilityAnim = hitTrack
				end
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
	end), "onAttacked_juice")

	self:AddConnection(self.onAttack:Connect(function(attack, returnValue: number, atkSource: any?) 
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
	end), "onAttack_mana")
	--

	self:AddConnection(hum.Died:Connect(function() 
		self:Die()
	end), "humDied")

	-- self.Model, not HRootPart.Parent: the rootpart is not guaranteed to sit
	-- directly under the model on a non-standard rig.
	local character:Model = self.Model or self.HRootPart.Parent::any
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
		self:AddConnection(self.hurtboxSize.onSet:Connect(hurtboxSzChange), "hurtboxSz_set")
		self:AddConnection(self.hurtboxSize.onRemove:Connect(hurtboxSzChange), "hurtboxSz_rem")
	end

	do
		local charSizeChanged = function(key: string) 
			-- self.Model, not HRootPart.Parent
			local model:any = self.Model or (self.HRootPart::any).Parent
			model:ScaleTo(self.charSize.Value)
		end
		self:AddConnection(self.charSize.onSet:Connect(charSizeChanged), "charSz_set")
		self:AddConnection(self.charSize.onRemove:Connect(charSizeChanged), "charSz_rem")
	end

	do
		self:AddConnection(self.floating.Changed:Connect(function(v)
			if v > 0 and self.isDead ~= true then
				self.ragdoll:unragdoll()
			--[[if self.ragdoll:inRagdoll() then
					Debug.dprint("STOP floatin!")
					self.ragdoll:unragdoll()
					self.targetFloatY.Value = nil
					self.floating.Value = 0
				end]]
			end
		end), "floating_unragdoll")
	end

	do
		local function stopEmote()
			if self._emoteInstance then
				if self._emoteInstance.destroy then self._emoteInstance:destroy() end
				self._emoteInstance = nil
			end
		end

		self:AddConnection(self.onStunned:Connect(function(a0: number) 
			if a0 <= 0 then return end
			stopEmote()
		end), "emote_stun")

		self:AddConnection(self.attacking.Changed:Connect(function(attacking: boolean) 
			if attacking == false then return end
			stopEmote()
		end), "emote_attacking")

		self:AddConnection(self.blocking.Changed:Connect(stopEmote), "emote_blocking")
		--self.onDash:Connect(stopEmote)
	end
--[[ Four near-identical regen loops -> one helper + four call sites.

		The nested `while ... Changed:Wait()` throttling idiom is CORRECT and
		DELIBERATE -- this DEDUPES it, it does not replace it. A flat Heartbeat
		loop would be strictly worse.

		The helper takes a STEP FUNCTION, not a rate, because the four are not
		interchangeable: health uses constants and a real Humanoid, floating
		counts DOWN and clamps to (0,2), and mana uses a nonlinear curve
		`baseGain * (1 - ratio)^3`. A rate-only helper would silently flatten
		mana's curve into a linear one.

		`rawset(v, "v", ...)` dodges firing Changed on every tick -- it was
		repeated as folklore in the posture and mana loops. It now lives in
		exactly one place: the caller's step function still does it, but the
		reason is documented here once.
	]]
	regenLoop(self, hum.HealthChanged, function()
		return hum.Health < hum.MaxHealth
	end, function(dt)
		if self.isActive ~= true or self.isDead then return false end
		hum.Health = math.min(hum.Health + dt * 0.5, hum.MaxHealth)
		return true
	end, 1) -- REGEN_STEP: health ticks once a second, unlike the others

	regenLoop(self, self.floating.Changed, function()
		return self.floating.Value > 0
	end, function(dt)
		if self.floating then
			self.floating.Value = math.clamp(self.floating.Value - dt, 0, 2)
		end
		return true
	end, "frame") -- floating alone used task.wait(); posture/mana used wait()

	regenLoop(self, self.posture.Changed, function()
		return self.posture.Value < self.maxPosture.Value
	end, function(dt)
		local posture:any, maxPosture:any = self.posture, self.maxPosture
		rawset(posture, "v", math.min(posture.v + dt * self.postureHeal.Value, maxPosture.Value))
		return true
	end)

	regenLoop(self, self.mana.Changed, function()
		return self.mana.Value < self.maxMana.Value
	end, function(dt)
		local mana:any, maxMana:any = self.mana, self.maxMana
		local ratio = mana.v / maxMana.Value
		local manaGain = 4 * (1 - ratio)^3 -- nonlinear ON PURPOSE, do not flatten
		rawset(mana, "v", math.min(mana.v + dt * manaGain, maxMana.Value))
		return true
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
	self.statusEffects:destroy()
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
--[==[ HandleAttack — the dispatcher.

	Resolution ORDER is the contract, and it is the one thing this function
	still owns:  dead -> parry -> dodge -> block -> hit.
	The combat test harness pins that order; if you reorder these, that suite
	fails, which is the point.

	Each branch lives in HumObj/resolution/. They are PURE MOVES -- the balance
	numbers inside them (the parry stun fallback, the asymmetric posture trade,
	the mutual-stun reset) were carried across verbatim.

	dodge is still inline BECAUSE IT IS ONE LINE. Extracting a one-line branch
	to match its siblings would be symmetry for its own sake and would add a
	file to read for no information gained.

	THE BLOCK BRANCH CAN RETURN nil ON PURPOSE. A broken guard falls
	through to the hit branch, which is how guard-breaking works. Do not
	collapse `if blocked ~= nil then return blocked end` into
	`return blocked`.
]==]
function module.HandleAttack(self:myself, attack:atkTyp, atkSource:any?):number
	local enemyEntity = attack.enemyEntity

	-- NEVER `return nil` here. A caller receiving nil cannot tell "target was
	-- already dead" from "this function forgot to return", and that ambiguity
	-- IS the bug. Routed through onAttackReturn so attack.status is really set.
	if self.isDead then
		return attack:onAttackReturn(returnEnums.aborted, atkSource)
	end

	local atkPostureDMG = attack:CalculatePostureDmg()

	if enemyEntity.isParry and enemyEntity:isParry(attack) then
		return resolveParry(self, attack, atkSource, atkPostureDMG)
	end

	if enemyEntity.isDodge and enemyEntity:isDodge() then
		return attack:onAttackReturn(returnEnums.dodged, atkSource)
	end

	--enemyEntity.HRootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
	-- TODO make block motors like move when hit on client side
	if enemyEntity.isBlock and enemyEntity:isBlock(attack) then
		local blocked = resolveBlock(self, attack, atkSource, atkPostureDMG)
		if blocked ~= nil then
			return blocked
		end
		-- guard broke: fall through
	end

	return resolveHit(self, attack, atkSource)
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
	)
end

-- gate is duplicated from baseClass.Stun so it sits ABOVE the side effects:
-- otherwise an armoured player still eats onStunned + loses their swing.
function module.Stun(self:myself, stunTime:number, bypassArmour:boolean?)
	if self.isActive ~= true then return end
	-- hooked here not in baseClass: statusEffects is server-only. via
	-- activeEffects because a raw _hyperUntil write has no effect object.
	if not bypassArmour and tick() < self._hyperUntil then
		local armour = self.statusEffects.activeEffects
			and self.statusEffects.activeEffects.HyperArmour
		if armour then
			armour:onTrigger()
		end
		return
	end

	self.onStunned:Fire(stunTime)
	if tick() < self.attackAt - 0.1 and self.wielding_weapon then
		self.wielding_weapon:stopLastAnim()
	end
	baseClass.Stun(self, stunTime, bypassArmour)
end

function module.GuardBreak(self:myself)
	self.posture.Value = self.maxPosture.Value
	game.ReplicatedStorage.RemoteEvents.VFX:FireAllClients("postureBreak", self.HRootPart)

	Debug.dprint(self, "POSTURE BROKEN!")

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
	local char = self.Model or (self.HRootPart and self.HRootPart.Parent)
	if not char then return end

	Debug.dprint("set transparency", transparency)

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
	local canDash = self:canDash()
	
	if fromSS == true and canDash == false and self.attacking.Value == true then
		warn(self,"dashing while attack... punish?")
		self.cooldowns:trigger("dashCancel")
	end
	--print("SS DASH", fromSS, canDash)
	if canDash == false then return false end
	
	self.dodgeThreshold = tick() + self.dodgeWindow
	self.cooldowns:get("parry").lastUsed = 0 -- parry is cancelled on dash
	
	self.ragdoll:unragdoll()
	if self:isBlock() == true then
		--warn("RAH punish dash while blocking")
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
		Debug.dprint("atkend", setTo)
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

	self:AddConnection(self.stun.Changed:Connect(function(number: number) 
		local duration = self.timeStunned--number-tick()
		if number == 0 then
			duration = 0
		end
		--print("STUN duration:",duration, number)
		remoteEvent:FireClient(plr, 1, duration)
	end), "repl_1_stun")
--[[ The plain "signal fired -> forward its value under an id" cases.

		These six were six separate raw :Connect blocks that differed only by
		which signal and which integer. Collapsed into a table so the id/field
		pairing is READABLE IN ONE PLACE, without touching the wire format or
		the client side. Every connection is janitored.

		onDash/onDashCancel deliberately forward NO payload, matching the
		original `FireClient(plr, 8)` with no third argument.
	]]
--[[ NOTE the two lists. They are NOT interchangeable and must not be
		merged with a `x.Changed or x` fallback:

		  * attacking/blocking/posture/parryWindow are VALUE OBJECTS. The
		    signal is `x.Changed` and it carries the new value.
		  * onDash/onDashCancel are RAW Signals (HumObjClient:138-139). They
		    are the signal, and they forward no payload.

		Signal's __index ERRORS on an unknown member rather than returning nil
	-- "Attempt to get Signal::Changed (not a valid member)" -- so
		`entry.signal.Changed or entry.signal` does not degrade, it throws, and
		it would have taken out initReplicateServer for every player.
	]]
	local valueRepl = {
		{ value = self.attacking,   id = 2 },
		{ value = self.blocking,    id = 3 },
		{ value = self.posture,     id = 4 },
		{ value = self.parryWindow, id = 7 },
	}
	for _, entry in valueRepl do
		local id = entry.id
		self:AddConnection(entry.value.Changed:Connect(function(value: any)
			remoteEvent:FireClient(plr, id, value)
		end), "repl_" .. id)
	end

	local pingRepl = {
		{ signal = self.onDash,       id = 8 },
		{ signal = self.onDashCancel, id = 9 },
	}
	for _, entry in pingRepl do
		local id = entry.id
		self:AddConnection(entry.signal:Connect(function()
			remoteEvent:FireClient(plr, id)
		end), "repl_" .. id)
	end

	-- bespoke: these two send an id AND a value, so they are not part of the
	-- simpleRepl table above.
	self:AddConnection(self.cooldowns.CooldownChanged:Connect(function(id: string, value: number) 
		remoteEvent:FireClient(plr, 10, id, value)
	end), "repl_10_cdChanged")
	self:AddConnection(self.cooldowns.CooldownTriggered:Connect(function(id: string, value: number) 
		remoteEvent:FireClient(plr, 11, id, value)
	end), "repl_11_cdTriggered")
	self:AddConnection(self.floating.Changed:Connect(function(number: number)
		remoteEvent:FireClient(plr, 12, number)
	end), "repl_12_floating")
	self:AddConnection(self.targetFloatY.Changed:Connect(function(value: any?) 
		remoteEvent:FireClient(plr, 20, value)
	end), "repl_20_targetFloatY")
	self.timeScale:initReplicateServer(21, remoteEvent, plr)
	self.maxMana:initReplicateServer(22, remoteEvent, plr)
	self:AddConnection(self.mana.Changed:Connect(function(number: number) 
		remoteEvent:FireClient(plr, 23, number)
	end), "repl_23_mana")


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
