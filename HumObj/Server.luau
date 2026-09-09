--!strict
-- TODO asses redundancy in this entire class... how bad does this scale with alot of humobjs??
debug.setmemorycategory("HumObjClass")
local packages = game.ReplicatedStorage:WaitForChild("Packages")
local classes  = game.ReplicatedStorage:WaitForChild("Class")

local Signal        = require(packages.Signal)
local AdditiveValue = require(packages.AdditiveValue)
local numVal        = require(packages.valueBase.numberValue)

local weaponBase = require(game.ServerStorage.ROWA.Weps.WepBase.types)
local baseClass  = require(classes.HumObjClient)
local replIds    = require(classes.HumObjClient.replIds) -- THE wire ids. SINGLE SOURCE, shared with the client, same deal as KNOCK_HP.
local S2C, C2S   = replIds.S2C, replIds.C2S
local locomotionProfiles = require(game.ReplicatedStorage.Modules.LocomotionProfiles)

local DmgUtils      = require(game.ServerScriptService.Utils.DmgUtils)
local dmgRecord     = require(script.damageRecord)
local cardLoader    = require(script.cardLoader)
local rowaRagdoll   = require(script.RowaRagdoll)
local statusEffects = require(game.ServerStorage.ROWA.Class.StatusEffects)
local grabClass     = require(script.Grab)
local dragBody      = require(script.dragBody)

local knockForce = require(game.ServerScriptService.Knockback)
--local emoteBase = require(game.ServerStorage.ROWA.Emotes.EmoteBase)

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
	-- the KNOCKED-DOWN pool. nil until you are first knocked, nil again once you get up, so an entity that never goes down holds nothing.
	knockedHp: number?,
	-- scales the parrier's half of the posture trade in resolveParry. nil unless a card (Counterweight) sets it.
	parryPostureMult: number?,
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

	isKnocked: (self:myself)->boolean,
	-- DRAG. Every field of it is LAZY, these two and dragBody's own constraints alike: nil unless a drag is actually live, so an entity that never drags or gets dragged holds nothing. See HumObj/dragBody.
	dragging:  myself?,   -- the victim I am hauling
	draggedBy: myself?,   -- who is hauling me
	startDrag: (self:myself, victim:myself, limb:BasePart)->boolean,
	stopDrag:  (self:myself)->(),
	GuardBreak: (self:myself)->(),
	GetBlade: (self:myself)->Instance?,
	feint: (self:myself)->boolean,
	Heal: (self:myself, amt:number) -> number,
	setTransparency: (self:myself, transparency:number?) -> (),
	Die: (self:myself)->(),

	parryAnim: AnimationTrack?,
	blockAnim: AnimationTrack?,
	blockAnimOverride: AnimationTrack?,
	getBlockAnim: (self:myself) -> AnimationTrack?,
	setBlockAnimOverride: (self:myself, track:AnimationTrack?) -> (),
	lastAbilityAnim: AnimationTrack?,

	inCombat: (self:myself) -> boolean,

	-- returns true on sucess
	-- THE WIELDED SET: weapons you have committed to, capped by maxWeapons; members live holstered on the back and swap into the hand for free.
	equippedWeapons: {weaponBase.myself},
	-- how many may be in that set at once; AdditiveValue so a card can raise it. NOT dual wielding, only one is ever `wielding_weapon`.
	maxWeapons: AdditiveValue.myself,
	weaponCap: (self: myself) -> number,
	-- outgoing BASIC-attack damage multiplier. AdditiveValue so a card stacks without touching AttackClass.
	wepDmgMult: AdditiveValue.myself,
	-- UPRIGHT health regen multiplier. Server-only (health regen is), so unlike postureHeal it never replicates.
	healthHeal: AdditiveValue.myself,
	-- drawn but NOT committed: in the right hand, roblox-Tool style, unusable.
	heldWeapon: weaponBase.myself?,
	-- THE OFF HAND. One left arm, so one side weapon; not part of the wielded set.
	sideWep: any?,
	EquipSideWep: (self: myself, sideWep: any?) -> (),
	useSideWep:   (self: myself) -> boolean,

	EquipWeapon:   (self: myself, newWeapon: weaponBase.myself) -> boolean,
	WieldWeapon:   (self: myself, wep: weaponBase.myself?) -> (boolean, string?),
	canWield:      (self: myself, wep: weaponBase.myself) -> (boolean, string?),
	reholster:     (self: myself) -> (),
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
	wieldChanged: (self:myself) -> Signal.Signal<any?>,
	setWieldingWeapon: (self:myself, weapon:weaponBase.myself?) -> (),

	SubscribedEventCB: ((id:number, value: any)->())?,

	_emoteInstance: any?,--emoteBase.myself?,
	StopEmote: (self: myself) -> (),
	destroy: (self: myself) -> (),
	--new:     (hum: Humanoid) -> myself,
}

local module = {
	Name = "HumObj_Server",
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

local KNOCK_HP   = baseClass.KNOCK_HP -- shared with the client so both sides derive knocked from replicated Health. SINGLE SOURCE: HumObjClient.
local KNOCKED_HP = 20 -- damage needed to finish someone while they are down.
local HEALTH_REGEN  = 0.5 -- hp/sec, upright.
local KNOCKED_REGEN = 0.5 -- hp/sec, down. THE GETUP CLOCK, and the only thing setting how long you lie there: 1 -> past KNOCK_HP.


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

-- detach, never destroy: wepItem and the NPC Tool script own their weapons and outlive the character.
local function releaseWep(w:any)
	if w == nil then return end
	local ok, err = pcall(function()
		if w.putAway then w:putAway() end
		if w.unequip then w:unequip() end
	end)
	if not ok then
		warn(err, debug.traceback())
	end
end

local onDied = require(script.onDeath)

-- HandleAttack's branches. Pure moves; see the dispatcher for the order.
local resolveParry = require(script.resolution.resolveParry)
local resolveBlock = require(script.resolution.resolveBlock)
local resolveHit   = require(script.resolution.resolveHit)

-- one regen loop, three call sites; the nested while/Changed:Wait is deliberate throttling.
-- !! steps integrate dt, so changing a call site's timer changes its regen RATE, not just its resolution. `step` returning false kills the coroutine, not just the inner loop.
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

-- !! HumObj GENUINELY REQUIRES a Humanoid, unlike EntityBase: ragdoll, grab, CharController and the animation stack all take one directly, so it refuses up front.
-- an odd-shaped entity should NOT be a HumObj -- subclass EntityBase and take Combatant's inert defaults instead.
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
	-- destroy() stamps "norepli" on the root, so a live HumObj on that same root must clear it or CharController reads the stale tag as "apply air friction forever". Symmetric with destroy.
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
	self.cooldowns:setCooldown("feint", 2) -- basic feint (wep)
	self.cooldowns:setCooldown("feint2", 3) -- ability feint
	self.cooldowns:setCooldown("parry", 1.2)
	self.cooldowns:setCooldown("wieldMsg", 2) -- anti chat-spam on refused wields -- TODO this is redundant and is a waste?

	self.canAtkThreshold = 0
	self.dodgeThreshold  = 0
	self.dodgeWindow     = 0.3

	self.attackAt        = 0

	self.equippedWeapons = {}
	self.maxWeapons      = AdditiveValue.new(1) -- ONE committed weapon by default; Many-Handed is the card that raises it
	self.wepDmgMult      = AdditiveValue.new(1) -- TODO might be redundant?
	self.healthHeal      = AdditiveValue.new(1)
	self.heldWeapon      = nil
	self.sideWep         = nil
	self.wielding_weapon = nil
	self.using_ability  = nil
	self.blockAnimOverride = nil

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
		if enemyEntity.floating and enemyhum.FloorMaterial == Enum.Material.Air and myEntity.Hum and myEntity.Hum.FloorMaterial == Enum.Material.Air and myEntity:isSwimming() == false and enemyEntity:isSwimming() == false then
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
			-- _lastBlocked means "my guard last DID something", not "blocking.Value last flipped", since ChangeBlocking only stamps the EDGES. Sole reader is ToshiCounter.
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
			-- HYPER ARMOUR: a SECOND interrupt path that never consults stun, so it gates itself; true stun still cancels via :Stun -> onStunned.
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
				-- this flinch is what cancels abilities: it takes over lastAbilityAnim, one slot, so both cannot play. Armoured skips the anim entirely.
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
				-- increase mana. :setMana clamps and re-anchors; never write .Value
				self:setMana(self:manaNow() + attack:CalculateDamage() / 4)
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

	-- self.Model, not HRootPart.Parent: the rootpart need not sit directly under the model on a non-standard rig.
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
			if v > 0 and self.isDead ~= true and not self:isKnocked() then
				self.ragdoll:unragdoll()
			end
		end), "floating_unragdoll")
	end

	do
		local function stopEmote()
			self:StopEmote()
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
	regenLoop(self, hum.HealthChanged, function()
		return hum.Health < hum.MaxHealth
	end, function(dt)
		if self.isActive ~= true or self.isDead then return false end
		-- rate is picked from the PRE-write state, the getup from the POST-write one, or the tick you cross KNOCK_HP re-pins you and getting up costs an extra second.
		local knocked = self:isKnocked()
		-- BEING DRAGGED PAUSES THE CLOCK. Getting up IS health crossing KNOCK_HP, so freezing regen freezes the getup; no separate "cannot stand" flag exists or is needed.
		if not (knocked and self.draggedBy) then
			-- healthHeal scales the UPRIGHT rate only: KNOCKED_REGEN is the getup clock, and a heal card must not shorten a knockdown.
			hum.Health = math.min(hum.Health + dt * (if knocked then KNOCKED_REGEN else HEALTH_REGEN * self.healthHeal.Value), hum.MaxHealth)
		end
		-- upright entities pay one nil check a second and stop here.
		if self.knockedHp then
			if self:isKnocked() then
				-- re-arm the pin so a long knockdown cannot outlive the ragdoll's own lifetime cap.
				self.ragdoll:ragdoll(60, false)
			else
				-- crossed back over KNOCK_HP: get up, and drop the pool so we hold nothing again.
				self.knockedHp = nil
				self.ragdoll:unragdoll(true) -- the one caller that wants the getup animation
			end
		end
		return true
	end, 1) -- REGEN_STEP: health ticks once a second, unlike the others

	regenLoop(self, self.floating.Changed, function()
		return self.floating.Value > 0
	end, function(dt)
		if self.floating then
			self.floating.Value = math.clamp(self.floating.Value - dt, 0, 2)
		end
		return true
	end, "frame") -- floating alone used task.wait(); posture used wait()

	-- posture is stepped here AND in CharController, so a client hitch loses regen the server granted; the mana anchor shape would fix it.
	regenLoop(self, self.posture.Changed, function()
		return self.posture.Value < self.maxPosture.Value
	end, function(dt)
		local posture:any, maxPosture:any = self.posture, self.maxPosture
		-- rawset: regen must not fire Changed (i.e. replicate) every tick
		rawset(posture, "v", math.min(posture.v + dt * self.postureHeal.Value, maxPosture.Value))
		return true
	end)

	return self
end

-- the ONE emote teardown. EmoteBase.destroy nils _emoteInstance itself, so the
-- .destroy guard is only for a table.clear'd leftover (truthy, no metatable).
function module.StopEmote(self:myself&any)
	local emote = self._emoteInstance
	if emote and emote.destroy then emote:destroy() end
	self._emoteInstance = nil
end

function module.destroy(self:myself&any)
	--print("DESTROYED ME!", self.Hum, debug.traceback())
	_clearWieldedWeapon(self)
	if self.isActive ~= true then
		return
	end
	self.isActive = false
	releaseWep(self.heldWeapon)
	self.heldWeapon = nil

	if self.equippedWeapons then
		for _, w in ipairs(self.equippedWeapons) do
			releaseWep(w)
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
	self:StopEmote()
	-- already released by _clearWieldedWeapon at the top; same ownership rule.
	releaseWep(self.wielding_weapon)
	self:setWieldingWeapon(nil)
	if self.plrObj then
		self.plrObj.HumObj = nil
	end
	self.onAttackWindup:Destroy()
	self.onStunned:Destroy()
	local wieldChanged = rawget(self, "_wieldChanged")
	if wieldChanged then wieldChanged:Destroy() end
	self.cooldowns:Destroy()

	-- !! CARDS FIRST. Their destroy RemoveMods the AdditiveValues below and releases
	-- the side weapon; a destroyed AdditiveValue has no metatable, so :RemoveMod on
	-- one is a nil call that would abort the rest of this teardown.
	self.cards:destroy()
	self.hurtboxSize:destroy()
	self.maxWeapons:destroy()
	self.wepDmgMult:destroy()
	self.healthHeal:destroy()
	self.dmgRecord:destroy()
	self.ragdoll:destroy()
	self.statusEffects:destroy()
	self.grab:destroy()
	if self.sideWep then self.sideWep:destroy() self.sideWep = nil end
	-- BOTH directions: drop whoever I am hauling, and make whoever is hauling ME let go. Otherwise the survivor keeps a dangling AlignPosition and the victim's parts stay owned by a player who no longer exists.
	self:stopDrag()
	if self.draggedBy then
		self.draggedBy:stopDrag()
	end

	baseClass.destroy(self)
end

--

function module.Die(self)
	if self.isActive ~= true then return end
	self.Hum.Health = 0
	onDied(self, nil)
end

local returnEnums = DmgUtils.returnEnum
-- !! HandleAttack - the dispatcher. Resolution ORDER is the contract: dead -> parry -> dodge -> block -> hit, and the combat test harness pins it.
-- !! THE BLOCK BRANCH CAN RETURN nil ON PURPOSE -- a broken guard falls through to the hit branch, which is how guard-breaking works. Do not collapse it into `return blocked`.
function module.HandleAttack(self:myself, attack:atkTyp, atkSource:any?):number
	local enemyEntity = attack.enemyEntity

	-- !! NEVER `return nil` here: a caller cannot tell "already dead" from "forgot to return". Routed through onAttackReturn so attack.status is really set.
	if self.isDead then
		return attack:onAttackReturn(returnEnums.aborted, atkSource)
	end

	local atkPostureDMG = attack:CalculatePostureDmg()

	if enemyEntity.isParry and enemyEntity:isParry(attack) then
		return resolveParry(self, attack, atkSource, atkPostureDMG)
	end

	-- !! PASS THE ATTACK, as the parry and block branches do: without it every `dmgTbl.dodgeH` is a no-op, including HollowPurple's i-frame-piercing -10.
	if enemyEntity.isDodge and enemyEntity:isDodge(attack) then
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


--- ONE off-hand: equipping replaces whatever was there. nil just clears it.
function module.EquipSideWep(self:myself&any, sideWep: any?)
	local old = self.sideWep
	if old == sideWep then return end
	self.sideWep = sideWep
	if old then old:destroy() end
	if sideWep then sideWep:attach() end
end

--- the `sideWep` bind lands here. Inert without one, so the bind is always safe to press.
function module.useSideWep(self:myself&any): boolean
	local sideWep = self.sideWep
	if sideWep == nil or sideWep.use == nil then return false end
	return sideWep:use()
end

function module.wieldChanged(self:myself&any): Signal.Signal<any?>
	local signal = rawget(self, "_wieldChanged")
	if signal then return signal end
	signal = Signal.new()
	rawset(self, "_wieldChanged", signal)
	return signal
end

function module.setWieldingWeapon(self:myself&any, weapon:weaponBase.myself?)
	if self.wielding_weapon == weapon then return end
	self.wielding_weapon = weapon
	-- forwarded, not subscribed: the hook dies with the side weapon for free.
	if self.sideWep then self.sideWep:onWieldChanged(weapon) end
	local signal = rawget(self, "_wieldChanged")
	if signal then signal:Fire(weapon) end
end

function _clearWieldedWeapon(self:myself)
	local wielding = self.wielding_weapon
	if wielding then
		if wielding.unwield then
			--wielding:unequip()
			pcall(wielding.unequip, wielding)
		end
		self:setWieldingWeapon(nil)
		return true
	end
	return false
end


local Requirements = require(game.ReplicatedStorage.Modules.Requirements)

-- bind a weapon to me if it isn't already; :holdOut and :wield both need it.
local function bindWep(self:myself, w:any)
	if w._humObj ~= self then w:equip(self) end
end

-- re-park committed-but-inactive weapons so two holsters stop clashing.
function module.reholster(self:myself&any)
	for i, w in ipairs(self.equippedWeapons) do
		if w ~= self.wielding_weapon and w.holsterAt then
			pcall(w.holsterAt, w, i)
		end
	end
end

--- THE wielded-set cap, floored at 1. Read it, never re-derive it: WieldWeapon evicts
--- down to this and loadChar's commitFrom stops at it, and those two disagreeing is
--- how a shrunk cap quietly deletes a saved weapon.
function module.weaponCap(self:myself&any): number
	return math.max(1, math.floor(self.maxWeapons.Value))
end

-- may this entity COMMIT to `wep`? NPCs have no slot and are never gated.
function module.canWield(self:myself, wep:any): (boolean, string?)
	if wep == nil then return false, "no weapon" end
	if self.plrObj == nil then return true end

	local slot = self.plrObj.loadedSlot
	if slot == nil then return false, "no slot loaded" end
	-- missing is nil exactly when check passes; one walk answers both.
	local why = Requirements.missing(slot, wep.req)
	return why == nil, why
end

-- SELECT, and it never fails: in the wielded set -> straight to hand, not in it -> HELD OUT and inert until :WieldWeapon commits it.
function module.EquipWeapon(self:myself&any, newWeapon: weaponBase.myself): boolean
	if newWeapon == nil then
		error("attempted to :EquipWeapon(nil). u forgot to put a weapon stupid!")
	end

	-- an NPC has no click to commit with, so selecting IS committing; canWield already passes plrObj == nil, this just skips the pose.
	if self.plrObj == nil then
		return (self:WieldWeapon(newWeapon))
	end

	bindWep(self, newWeapon)

	local ok
	if table.find(self.equippedWeapons, newWeapon) then
		if self.wielding_weapon == newWeapon then return true end
		newWeapon:wield()
		ok = true
	else
		-- holdOut reuses the weapon's own wield weld, so the model lands in the hand but wielding_weapon stays nil and every swing path dead-ends.
		ok = newWeapon:holdOut()
	end
	self:reholster()
	return ok
end

-- COMMIT: `req`-gated; defaults to the held weapon, which is how M1 promotes it.
function module.WieldWeapon(self:myself&any, wep: weaponBase.myself?): (boolean, string?)
	local target:weaponBase.myself = wep or self.heldWeapon
	if target == nil then return false, "nothing held" end
	if self.wielding_weapon == target then return true end

	local allowed, reason = self:canWield(target)
	if not allowed then return false, reason end

	bindWep(self, target)

	local already = table.find(self.equippedWeapons, target)
	if already then
		table.remove(self.equippedWeapons, already) -- re-queue as newest
	else
		-- evict oldest first; maxWeapons is an AdditiveValue, so a card raises the cap without touching this line.
		local cap = self:weaponCap()
		while #self.equippedWeapons >= cap do
			local evicted = table.remove(self.equippedWeapons, 1)
			if evicted then evicted.committed = nil end
			releaseWep(evicted)
		end
	end

	table.insert(self.equippedWeapons, target)
	target.committed = true -- wepItem persists this; survives respawn + rejoin
	if self.heldWeapon == target then
		self.heldWeapon = nil
	end
	target:wield()
	self:reholster()
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

-- Combatant contract: what killing me is worth in xp, TOTAL, before onDeath/processXp splits it by damage share. A kill is KILL_LEVELS levels AT MY OWN LEVEL.
-- !! THIS is the only place that asks "is this thing player-backed?". Anything not player-backed answers with `.xpLevel`; unset == 0 == worth nothing.
local slotCurve = require(game.ReplicatedStorage.Class.plrObjClient.slot)
local KILL_LEVELS = 2
local lvlStub = { lvl = 0 }

function module.xpWorth(self:myself): number
	local plrObj = self.plrObj
	local slot = plrObj and plrObj.loadedSlot
	lvlStub.lvl = (slot and slot.lvl) or (self :: any).xpLevel or 0
	return slotCurve.nextLevelXp(lvlStub :: any) * KILL_LEVELS
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

-- how much a MOVING defender shifts their own dodge window, and the speed it takes to earn it. One place, so it is one number to tune or to zero.
local VELOCITY_NUDGE   = 0.1
local NUDGE_MIN_SPEED  = 8

-- !! isDodge is a PREDICATE and must NEVER write to dodgeThreshold: Dash sets that field, DashCancel clamps it, Clap and HollowPurple push it forward, so asking the question would change the answer permanently and cumulatively.
-- PingCompensation polls this every Heartbeat for up to 0.9x the attacker's ping, so the nudge is a LOCAL term that expires with the question. Built like isParry, deliberately.
function module.isDodge(self:myself, atk:atkTyp?, offset:number?)
	local window:number = offset or 0

	if atk then
		-- THE PRESSURE VALVE: positive widens the out, a large negative means "i-frames do not answer this" (HollowPurple's -10). A knob on the ATTACKER's own table, not an exemption list in the resolver.
		if atk.dmgTbl.dodgeH then
			window += atk.dmgTbl.dodgeH
		end

		local root = self.HRootPart
		local velo = if root then root.AssemblyLinearVelocity else Vector3.zero
		local atkDir = atk.atkDir
		-- !! atkDir is WORLD-SPACE and NOT guaranteed unit, so normalise it or the nudge scales with whatever the caller multiplied by. The guards also keep :Unit off a zero vector.
		if velo.Magnitude > NUDGE_MIN_SPEED and atkDir.Magnitude > 0 then
			-- -1 moving against the blow, +1 moving with it: moving INTO an attack widens the window, running with it narrows it. Design call, decided in one place.
			window -= velo.Unit:Dot(atkDir.Unit) * VELOCITY_NUDGE
		end
	end

	return tick() <= self.dodgeThreshold + window
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
			and not self:isKnocked() -- cant attack on the floor. rowa1 gated its whole input handler on this.
			and now > lastDashed
			and now > self.canAtkThreshold
	)
end

-- gate is duplicated from baseClass.Stun so it sits ABOVE the side effects: otherwise an armoured player still eats onStunned and loses their swing.
function module.Stun(self:myself, stunTime:number, bypassArmour:boolean?)
	if self.isActive ~= true then return end
	-- hooked here, not in baseClass, because statusEffects is server-only; via activeEffects because a raw _hyperUntil write has no effect object.
	if not bypassArmour and tick() < self._hyperUntil then
		local armour:statusEffects.anyEffect = self.statusEffects.activeEffects
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
				local char = self.Model::any
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
	if self.Hum then self.Hum.Health += amt end
	return amt
end

-- am I on the floor right now? DERIVED, never stored, so any route down here counts and getting up is just health crossing back.
-- adds the SERVER-ONLY isDead term to the shared predicate; the client half is HumObjClient.isKnocked.
function module.isKnocked(self:myself): boolean
	return self.isDead ~= true and baseClass.isKnocked(self)
end

-- see HumObj/dragBody. Assigned rather than wrapped: there is nothing to add here.
module.startDrag = dragBody.start
module.stopDrag  = dragBody.stop

--[[ THE DEATH STALL, rowa1 AttackModule:685. Overridden here rather than in
	resolveHit so SimpleEntity keeps the plain EntityBase version and the
	Combatant contract needs nothing.
	Setting Health = 0 rather than calling :Die() keeps the kill flowing
	through onAttacked -> onDied, so the killer still gets credit. ]]
function module.Damage(self:myself&any, amt:number)
	if amt <= 0 or self.isDead then
		return baseClass.Damage(self, amt)
	end

	local hum = self.Hum
	if self:isKnocked() then
		-- already down: chip the pool, health stays pinned at 1.
		local pool = (self.knockedHp or KNOCKED_HP) - amt
		self.knockedHp = pool
		if pool <= 0 then
			hum.Health = 0
		end
		return
	end

	-- canBeKnocked, not isKnocked: health has not dropped yet, so this asks whether the entity is knockable AT ALL. One that cannot regen past KNOCK_HP would lie there forever, so it dies normally instead.
	if hum.Health - amt > KNOCK_HP or not self:canBeKnocked() then
		return baseClass.Damage(self, amt)
	end

	-- knocked down: pinned at 1, flat ragdoll (stopOnGround false, or the ground check releases them at once).
	hum.Health = 1
	self.knockedHp = KNOCKED_HP
	-- and stopOnGround false is not enough on its own: the next hit to land re-arms it. This outranks it, and self-expires when health crosses back. RowaRagdoll.doUnragdoll.
	self.ragdoll.pinned = KNOCK_HP
	self.ragdoll:ragdoll(60, false)
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
	self.cooldowns:clearLastUsed("parry") -- parry is cancelled on dash
	
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
			and self:isKnocked() == false
	)
end

function module.getBlockAnim(self:myself): AnimationTrack?
	return self.blockAnimOverride or self.blockAnim
end

-- One central pose override: weapons still own the default; Shield owns only its replacement track.
function module.setBlockAnimOverride(self:myself&any, track:AnimationTrack?)
	local old = self:getBlockAnim()
	if old == track then return end
	if old and old.IsPlaying then old:Stop(0.1) end
	self.blockAnimOverride = track
	if self.isActive ~= true then return end
	local parry = self.parryAnim
	if self.blocking.Value and self.wielding_weapon and not (parry and parry.IsPlaying) then
		local resolved = self:getBlockAnim()
		if resolved then self:PlayTrack(resolved) end
	end
end

-- returns true if it was a parry
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
	local blockAnim = self:getBlockAnim()
	if setTo == true and isProperParry(self) and self.cooldowns:canTrigger("parry") then self.cooldowns:trigger("parry")
		if wep and blockAnim and self.parryAnim then
			blockAnim:Stop()
			self:PlayTrack(self.parryAnim)
			self:AddConnection(self.parryAnim.Stopped:Once(function()
				if self.blocking.Value == true then
					local resolved = self:getBlockAnim()
					if resolved then self:PlayTrack(resolved) end
					self:RemConnection("onParryStop")
				end
			end), "onParryStop")
		end
		return true
	end

	if wep and blockAnim then
		if setTo == true then
			self:PlayTrack(blockAnim)
		else
			blockAnim:Stop()
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
	elseif self.Hum then
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

function module.initReplicateServer(self:myself, remoteEvent:RemoteEvent, plr:Player)
	self.maxPosture:initReplicateServer(S2C.maxPosture, remoteEvent, plr)
	self.walkSpeed:initReplicateServer(S2C.walkSpeed, remoteEvent, plr)
	self.sprintSpeed:initReplicateServer(S2C.sprintSpeed, remoteEvent, plr)
	self.dashPower:initReplicateServer(S2C.dashPower, remoteEvent, plr)
	self.postureHeal:initReplicateServer(S2C.postureHeal, remoteEvent, plr)
	self.slideSpeed:initReplicateServer(S2C.slideSpeed, remoteEvent, plr)
	self.charSize:initReplicateServer(S2C.charSize, remoteEvent, plr)
	self.timeScale:initReplicateServer(S2C.timeScale, remoteEvent, plr)
	self.maxMana:initReplicateServer(S2C.maxMana, remoteEvent, plr)

	self:AddConnection(self.stun.Changed:Connect(function(number: number) 
		local duration = self.timeStunned--number-tick()
		if number == 0 then
			duration = 0
		end
		--print("STUN duration:",duration, number)
		remoteEvent:FireClient(plr, S2C.stun, duration)
	end), "repl_stun")

	-- !! TRUE STUN IS NOT DERIVABLE FROM S2C.stun: :TrueStun routes through :Stun, so a guard break and a jab look identical on the wire, leaving client-side `trueStun` at 0 forever and killing both its readers.
	-- duration on the wire, not the timestamp, matching S2C.stun. 0 = clear.
	self:AddConnection(self.trueStun.Changed:Connect(function(number: number) 
		local duration = number - tick()
		if number == 0 or duration <= 0 then
			duration = 0
		end
		remoteEvent:FireClient(plr, S2C.trueStun, duration)
	end), "repl_trueStun")
-- the plain "signal fired -> forward its value under an id" cases, tabled so the id/field pairing is readable in one place. onDash/onDashCancel deliberately forward NO payload.
-- !! the two lists are NOT interchangeable: valueRepl holds VALUE OBJECTS whose signal is `x.Changed`, pingRepl holds RAW Signals that forward no payload.
-- do not merge them with `entry.signal.Changed or entry.signal` -- Signal's __index THROWS on an unknown member rather than returning nil, so it would take out initReplicateServer for every player.
	local valueRepl:{{ value: numVal.NumberValue|any, id: number}} = {
		{ value = self.attacking,    id = S2C.attacking },
		{ value = self.blocking,     id = S2C.blocking },
		{ value = self.posture,      id = S2C.posture },
		{ value = self.parryWindow,  id = S2C.parryWindow },
		{ value = self.floating,     id = S2C.floating },
		{ value = self.targetFloatY, id = S2C.targetFloatY },
		{ value = self.mana,         id = S2C.mana },
	}
	for _, entry in valueRepl do
		local id = entry.id
		self:AddConnection(entry.value.Changed:Connect(function(value: any)
			remoteEvent:FireClient(plr, id, value)
		end), "repl_" .. id)
	end

	local pingRepl = {
		{ signal = self.onDash,       id = S2C.onDash },
		{ signal = self.onDashCancel, id = S2C.onDashCancel },
	}
	for _, entry in pingRepl do
		local id = entry.id
		self:AddConnection(entry.signal:Connect(function()
			remoteEvent:FireClient(plr, id)
		end), "repl_" .. id)
	end

	-- Wield switches can emit nil -> weapon in one thread. Defer once and send
	-- only the final inherited profile, so heavy -> heavy costs no packet.
	local lastLocomotionProfile = locomotionProfiles.DEFAULT
	local locomotionQueued = false
	self:AddConnection(self:wieldChanged():Connect(function()
		if locomotionQueued then return end
		locomotionQueued = true
		task.defer(function()
			locomotionQueued = false
			if self.isActive ~= true then return end
			local weapon = self.wielding_weapon
			local wanted = if weapon then weapon.locomotionProfile else locomotionProfiles.DEFAULT
			local profile = locomotionProfiles.resolveId(wanted)
			if profile == lastLocomotionProfile then return end
			lastLocomotionProfile = profile
			remoteEvent:FireClient(plr, S2C.locomotionProfile, profile)
		end)
	end), "repl_locomotionProfile")

	-- bespoke: these two send an id AND a value, so they are not rows in valueRepl above.
	self:AddConnection(self.cooldowns.CooldownChanged:Connect(function(id: string, value: number) 
		remoteEvent:FireClient(plr, S2C.cdChanged, id, value)
	end), "repl_cdChanged")
	self:AddConnection(self.cooldowns.CooldownTriggered:Connect(function(id: string, value: number) 
		remoteEvent:FireClient(plr, S2C.cdTriggered, id, value)
	end), "repl_cdTriggered")

	-- combatEdge -- WHO am I fighting and how long is left: (enemyModel, joined, remaining?). Membership only changes on an edge, so this is never a stream.
	-- !! the enemy's Model is already replicated, so health, posture and name must NOT go on this wire. Being inside initReplicateServer IS the player gate, so an NPC keeps onEdge nil.
	-- not AddConnection'd because it is a field, not a connection: destroy() clears it for a LIVE entity, onDeath does it for a dead one.
	self.dmgRecord.onEdge = function(enemyModel: Instance, joined: boolean, remaining: number?)
		remoteEvent:FireClient(plr, S2C.combatEdge, enemyModel, joined, remaining)
	end


	-- C2S: its OWN id space, see replIds.
	self.SubscribedEventCB = function(id:number, value: any)
		if id == C2S.sprinting then
			self.sprinting.Value = value
		elseif id == C2S.jumped then
			self._lastJumped = tick()
		elseif id == C2S.sliding then
			self.sliding.Value = value
		end
	end
	--self:AddConnection(rcon, "repliServer")
end

return table.freeze(module)
