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
	--- THE WIELDED SET: weapons you have committed to, capped by maxWeapons.
	--  Members live holstered on the back and swap into the hand for free.
	equippedWeapons: {weaponBase.myself},
	--- how many may be in that set at once. AdditiveValue so a card can raise
	--  it (`maxWeapons:SetMod("multiHanded", 1)`); NOT dual wielding, only one
	--  is ever `wielding_weapon`.
	maxWeapons: AdditiveValue.myself,
	--- drawn but NOT committed: in the right hand, roblox-Tool style, unusable.
	heldWeapon: weaponBase.myself?,

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

--- detach, never destroy: wepItem and the NPC Tool script own their weapons
--- and outlive the character.
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

--- One regen loop, three call sites; the nested while/Changed:Wait is deliberate throttling.
--- stepTime nil = wait() ~30Hz, n = wait(n), "frame" = task.wait() -- steps integrate dt, so
--- swapping a call site's timer changes its regen RATE, not just its resolution.
--- `step` returning false kills the coroutine, not just the inner loop (health needs that on death).
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
	self.cooldowns:setCooldown("wieldMsg", 2) -- anti chat-spam on refused wields

	self.canAtkThreshold = 0
	self.dodgeThreshold  = 0
	self.dodgeWindow     = 0.3

	self.attackAt        = 0

	self.equippedWeapons = {}
	self.maxWeapons      = AdditiveValue.new(2)
	self.heldWeapon      = nil
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
			--- HYPER ARMOUR: a SECOND interrupt path that never consults stun, so it gates itself; true stun still cancels via :Stun -> onStunned.
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
	end, "frame") -- floating alone used task.wait(); posture used wait()

	--- Posture is stepped here AND in CharController, so a client hitch loses regen the
	--- server granted -- linear, so the mana anchor shape would fix it. Own playtest.
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
	if self._emoteInstance then
		self._emoteInstance:destroy()
		self._emoteInstance = nil
	end
	-- already released by _clearWieldedWeapon at the top; same ownership rule.
	releaseWep(self.wielding_weapon)	self.wielding_weapon = nil
	if self.plrObj then
		self.plrObj.HumObj = nil
	end
	self.onAttackWindup:Destroy()
	self.onStunned:Destroy()
	self.cooldowns:Destroy()

	self.hurtboxSize:destroy()
	self.maxWeapons:destroy()
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

	--[[ PASS THE ATTACK. The parry branch above and the block branch below
		both do; this one did not, and that single omission made every
		`dmgTbl.dodgeH` in the game a no-op -- including HollowPurple's -10,
		which is its entire i-frame-piercing design (README S10.6). ]]
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


local Requirements = require(game.ReplicatedStorage.Modules.Requirements)

--- bind a weapon to me if it isn't already; :holdOut and :wield both need it.
local function bindWep(self:myself, w:any)
	if w._humObj ~= self then w:equip(self) end
end

--- re-park committed-but-inactive weapons so two holsters stop clashing.
function module.reholster(self:myself&any)
	for i, w in ipairs(self.equippedWeapons) do
		if w ~= self.wielding_weapon and w.holsterAt then
			pcall(w.holsterAt, w, i)
		end
	end
end

--- may this entity COMMIT to `wep`? NPCs have no slot and are never gated.
function module.canWield(self:myself, wep:any): (boolean, string?)
	if wep == nil then return false, "no weapon" end
	if self.plrObj == nil then return true end

	local slot = self.plrObj.loadedSlot
	if slot == nil then return false, "no slot loaded" end
	if Requirements.check(slot, wep.req) then return true end
	return false, Requirements.missing(slot, wep.req)
end

--[[ SELECT, and it never fails. In the wielded set -> straight to hand, the
	free swap the set exists for. Not in it -> HELD OUT, inert, until
	:WieldWeapon commits it. Boolean return is read by Weps/Utils/Template. ]]
function module.EquipWeapon(self:myself&any, newWeapon: weaponBase.myself): boolean
	if newWeapon == nil then
		error("attempted to :EquipWeapon(nil). u forgot to put a weapon stupid!")
	end

	--[[ An NPC has no click to commit with, so selecting IS committing.
		Every bot / summon / Tool script reaches a weapon through here and has
		no other route into the wielded set, so hold-out is a dead state for
		them. canWield already passes plrObj == nil, this just skips the pose. ]]
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
		-- holdOut reuses the weapon's own wield weld, so the model lands in the
		-- hand but wielding_weapon stays nil and every swing path dead-ends.
		ok = newWeapon:holdOut()
	end
	self:reholster()
	return ok
end

--- COMMIT: `req`-gated. Defaults to the held weapon, which is how M1 promotes it.
function module.WieldWeapon(self:myself&any, wep: weaponBase.myself?): (boolean, string?)
	local target = wep or self.heldWeapon
	if target == nil then return false, "nothing held" end
	if self.wielding_weapon == target then return true end

	local allowed, reason = self:canWield(target)
	if not allowed then return false, reason end

	bindWep(self, target)

	local already = table.find(self.equippedWeapons, target)
	if already then
		table.remove(self.equippedWeapons, already) -- re-queue as newest
	else
		-- evict oldest first; maxWeapons is an AdditiveValue so a card raises
		-- the cap without touching this line.
		local cap = math.max(1, math.floor(self.maxWeapons.Value))
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

--[[ Combatant contract. What killing me is worth in xp, TOTAL, before
	onDeath/processXp splits it by damage share.

	A kill is KILL_LEVELS levels AT MY OWN LEVEL, so an even 1v1 pays the
	winner exactly one level at any level -- both sides ride the same curve.
	The curve is NOT copied: slot.nextLevelXp is the single source, and
	`lvlStub` reuses one table so this allocates nothing.

	THIS is the only place that asks "is this thing player-backed?". Keep it
	that way -- the moment the payout has to ask, we are back to rowa1, where
	the rule lived in seven files. Anything not player-backed answers with
	`.xpLevel`, one plain number a summon or boss script sets in one line,
	exactly like it sets cards. Unset == 0 == worth nothing. ]]
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

--- how much a MOVING defender shifts their own dodge window, and the speed
--- it takes to earn it. One place, so it is one number to tune or to zero.
local VELOCITY_NUDGE   = 0.1
local NUDGE_MIN_SPEED  = 8

--[[ isDodge -- BUILT LIKE isParry, DELIBERATELY, AND IT DID NOT USED TO BE.
	The three defence questions are siblings: each answers "did the defender
	beat THIS attack", each reads a per-attack knob off the dmgTbl, and each
	is a PREDICATE. isParry accumulates a local `window` and never touches
	self.parryWindow. This now does the same against self.dodgeThreshold.

	!! IT USED TO WRITE TO dodgeThreshold, AND THAT FIELD IS THE DODGE.
	Dash sets it (tick() + dodgeWindow), DashCancel clamps it, Clap and
	HollowPurple push it forward. So ASKING THE QUESTION CHANGED THE ANSWER,
	permanently and cumulatively -- there was no per-attack scope to undo it.
	Worst caller: Cards/PingCompensation polls `humObj:isDodge(atk)` every
	Heartbeat for up to 0.9x the attacker's ping, so a defender moving faster
	than NUDGE_MIN_SPEED drifted their own window by 0.1 PER FRAME POLLED --
	tenths of a second of dodge appearing or vanishing based on nothing but
	how long someone's ping was. Nick_Amplifier and HeavensEqualizer poll it
	too. The nudge is a local term now and expires with the question, which
	is what it always read as.
]]
function module.isDodge(self:myself, atk:atkTyp?, offset:number?)
	local window:number = offset or 0

	if atk then
		--[[ THE PRESSURE VALVE (README S10.6). Positive widens the out;
			a large negative is rowa1's global `bypassiframes` SET expressed
			as a number on the ATTACKER's own table instead of an exemption
			list inside the resolver -- HollowPurple's -10 means "i-frames do
			not answer this".
			IT WAS DEAD UNTIL NOW. HandleAttack called :isDodge() with no
			attack, so for the one caller that actually decides whether a hit
			lands, this branch never ran and every dodgeH in the game was
			cosmetic. ]]
		if atk.dmgTbl.dodgeH then
			window += atk.dmgTbl.dodgeH
		end

		local root = self.HRootPart
		local velo = if root then root.AssemblyLinearVelocity else Vector3.zero
		local atkDir = atk.atkDir
		--[[ atkDir is WORLD-SPACE and NOT guaranteed unit -- call sites pass
			everything from a bare LookVector to `dir * 20`. Normalise it, or
			the nudge silently scales with whatever the caller multiplied by.
			Both guards also keep :Unit away from a zero vector, which is NaN
			(the old code computed the dot BEFORE checking the speed). ]]
		if velo.Magnitude > NUDGE_MIN_SPEED and atkDir.Magnitude > 0 then
			--[[ -1 moving against the blow, +1 moving with it. Moving INTO
				an attack widens the window, running with it narrows it.
				SIGN PRESERVED from the original -- this is a design call, not
				a bug, and it is now decided in exactly one place if it turns
				out to read backwards. ]]
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

	--[[ TRUE STUN IS NOT DERIVABLE FROM ID 1.

		:TrueStun routes through :Stun, so all the client ever saw was an
		ordinary stun packet -- a guard break and a jab look identical on the
		wire. Client-side `trueStun` therefore sat at 0 for a player's entire
		session, which quietly killed BOTH readers of it:
		  * CharController's hard `JP = 0 / WS = 0` branch never ran
		  * shiftlock kept steering you through a guard break (ClientClass)

		Duration on the wire, not the timestamp, matching id 1. 0 = clear, so
		the grab cancels that write `trueStun.Value = 0` release it too.
	]]
	self:AddConnection(self.trueStun.Changed:Connect(function(number: number) 
		local duration = number - tick()
		if number == 0 or duration <= 0 then
			duration = 0
		end
		remoteEvent:FireClient(plr, 14, duration)
	end), "repl_14_trueStun")
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

	--[[ id 24 -- WHO am I fighting, and how long is left on them.
		(enemyModel, joined, remaining?). Membership only changes on an edge, so
		this is two packets per enemy per fight plus one correction per TTL --
		never a stream. The enemy's Model is already replicated, so health,
		posture and name must NOT go on this wire; the client reads those off
		the Model it is handed.

		Being inside initReplicateServer IS the player gate -- only loadChar
		calls it -- so an NPC's dmgRecord keeps onEdge nil and arms no timers.

		Not AddConnection'd because it is a field, not a connection:
		dmgRecord:destroy() (in this class's destroy) clears it, which is also
		what kills any expiry timer still in flight. ]]
	self.dmgRecord.onEdge = function(enemyModel: Instance, joined: boolean, remaining: number?)
		remoteEvent:FireClient(plr, 24, enemyModel, joined, remaining)
	end


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
