--!strict
-- SumiyaNeedle heavy: a lunge that carries you THROUGH them and hooks the line on a hit or block; a heavy while hooked reels them in.
local wepType = require(game.ServerStorage.ROWA.Weps.WepBase.types)
type wepTyp = wepType.myself

local dmgConfig = require(script.Parent.Parent.dmgConfig)
local fireVFX = require(game.ServerStorage.ROWA.Modules.fireVFX)
local pinTo = require(game.ServerStorage.ROWA.Modules.pinTo)
local kb = require(game.ServerScriptService.Knockback)

local LINE = "sumiyaLine" -- stages: 1 hook, 2 reel, 3 let go (snapped?)
local MISS_CD = 6 -- a whiff or parry. A hook pays the registered 10 (SumiyaNeedle:wield) and lives as long as it; a reel restarts it
local SNAP = 80 -- studs apart and the line breaks
local RIP_DMG, RIP_STUN = 5, 0.4 -- what a snap tears out of them
local HOOKED = game.ServerStorage.ROWA.Class.StatusEffects.Hooked

local LUNGE_T = 0.5 -- the thrust's hit frame, so the anim runs at 1
local DASH = Vector3.new(0, 0, -18) -- ~13 studs on a whiff
local BOX_CF, BOX_SIZE = CFrame.new(0, 0, -5), Vector3.new(5, 6, 8)
local ACTIVE = table.freeze({ window = 0.15, lead = 0.07 })
local BEHIND = 8 -- a hook carries you this far past them
local PASS = table.freeze({ axes = Vector3.new(1, 0, 1), maxSpeed = 60, stopWithin = 1.5, maxTime = 0.35 })

local YANK, REELED = 0.33, 0.73 -- the reel anim's two whips, both pulls
local STOP = 4 -- they land this far in front of you
local HELD = 0.8 -- still stunned this long after they land
local PULL_T = 0.8 -- they arrive this long after the yank, at any range
local HOP = Vector3.new(0, workspace.Gravity * PULL_T / 12, 0) -- one kick whose arc lands on arrival (kb x5; /12 not /10 pays for the 0.05s hold and falling flat)

local function bail(this: any, humObj: any)
	this:stopLastAnim(true)
	humObj.walkSpeed:RemoveMod("stopMoving")
end

-- the line lets go; a snap rips the hook out of them
local function release(this: any, enemy: any, snapped: boolean)
	fireVFX(LINE, 3, this._model.Blade.Top, snapped)
	if enemy.isActive ~= true then return end
	enemy.statusEffects:remove(HOOKED)
	if not snapped then return end
	-- raw, not an attack: a parried snap would stun you from SNAP studs away
	enemy:Damage(RIP_DMG, this._humObj)
	enemy:Stun(RIP_STUN)
	fireVFX("slash", enemy.HRootPart)
end

-- the hook's life: a lapse, a snap or losing either end let it go; the cd has run since the hook, so none costs extra
local function watch(this: any, enemy: any, armed: number)
	local humObj = this._humObj
	local root, eroot = humObj.HRootPart, enemy.HRootPart
	while this._hookUntil == armed do
		local far = (eroot.Position - root.Position).Magnitude > SNAP
		if far or tick() > armed or humObj.wielding_weapon ~= this or enemy.isActive ~= true or eroot.Parent == nil then
			this._hooked, this._hookUntil = nil, nil
			release(this, enemy, far)
			return
		end
		task.wait(0.1)
	end
end

local function lunge(this: any): boolean?
	if this:canTriggerCD("heavy") == false then return end
	local humObj = this._humObj
	local hurtbox, root = humObj.HurtBox, humObj.HRootPart
	local model = this._model

	this:PlayAnim(script.sumiyahvylunge, 0.08, 1, 1)
	this:indicateAtk()
	model.Hold.hvystart:Play()
	fireVFX("hshock", root)
	humObj.walkSpeed:SetMod("stopMoving", -100)
	if this:feintWait(LUNGE_T) then bail(this, humObj) return end
	-- cds only go up, so the whiff price now and a hook pays the full one
	this:triggerCD("heavy", MISS_CD)
	model.Hold.arrowwoosh:Play()
	model.Hold.dash:Play()
	fireVFX("sumiyaWind", root)
	local dash = this:bodyForce(DASH, 0.3, true, 0.3)

	local hitbox, hits = this:sweep(BOX_CF, BOX_SIZE, ACTIVE)
	if humObj:inStun() then
		dash:destroy()
		bail(this, humObj)
		return
	end

	local look = hurtbox.CFrame.LookVector
	local hitLanded, hooked = false, nil
	for _, enemy in hits do
		local attack = this:makeAtk(dmgConfig.lunge, enemy, look)
		attack.hitbox = hitbox
		this:executeAttack(attack)
		if attack:isHit() then hitLanded = true end
		if attack:isParried() then dash:destroy() end
		-- a block hooks like a hit; Reflect swaps enemyEntity, so a reflected lunge hooks nobody
		if hooked == nil and attack.enemyEntity == enemy and (attack:isHit() or attack:isBlocked()) then hooked = enemy end
	end

	if hooked then
		model.Hold.chainsawpull:Play()
		model.Hold.lassowhip:Play()
		dash:destroy()
		this:triggerCD("heavy")
		local eroot = hooked.HRootPart
		local window = humObj.cooldowns:remaining("heavy") -- the hook IS the cd: its bar is the hook timer
		fireVFX(LINE, 1, model.Blade.Top, eroot, window)
		hooked.statusEffects:apply(HOOKED, window)
		local armed = tick() + window
		this._hooked, this._hookUntil = hooked, armed
		task.spawn(watch, this, hooked, armed)
		-- only the two roots collide (limbs are charLimb), so one pair is the whole pass
		local nc = Instance.new("NoCollisionConstraint")
		nc.Part0, nc.Part1 = root, eroot
		nc.Parent = root
		game.Debris:AddItem(nc, PASS.maxTime + 0.2)
		local behind = eroot.Position + Vector3.new(look.X, 0, look.Z).Unit * BEHIND
		behind = Vector3.new(behind.X, root.Position.Y, behind.Z)
		pinTo(root, function() return behind end, PASS)
	end

	this:endLag(if hooked then 0.1 else 0.3)
	humObj.walkSpeed:RemoveMod("stopMoving")
	return hitLanded
end

local function reel(this: any): boolean?
	local humObj = this._humObj
	local root = humObj.HRootPart
	local model = this._model
	-- claimed, so a lapse mid-windup cannot eat an in-time press. A feint lets it go
	local enemy = this._hooked
	this._hooked, this._hookUntil = nil, nil
	if enemy.isActive ~= true then release(this, enemy, false) return end

	this:PlayAnim(script.sumiyahvyreelin, 0.08, 1, 1)
	model.Hold.lassopickup:Play()
	model.Hold.fishingrodcast:Play()
	model.Hold.fishingrodcast.TimePosition = 0.1
	fireVFX(LINE, 2, model.Blade.Top, YANK, PULL_T) -- at the press, so the spool sparks through the windup; every exit below sends a 3
	humObj.walkSpeed:SetMod("stopMoving", -100)
	if this:feintWait(YANK) then
		bail(this, humObj)
		release(this, enemy, false)
		return
	end
	local eroot = enemy.HRootPart
	if enemy.isActive ~= true or eroot.Parent == nil or (eroot.Position - root.Position).Magnitude > SNAP then
		bail(this, humObj)
		release(this, enemy, true)
		return
	end
	enemy.statusEffects:remove(HOOKED)
	enemy:Stun(PULL_T + HELD) -- from the yank, so the windup is their tell
	this:triggerCD("heavy")

	local unpin = nil
	if not enemy.unlaunchable then -- a Boss's brain owns its body
		enemy.ragdoll:ragdoll(60, true) -- limp on the line; ends on the ground, 0.5s min
		local hurtbox = humObj.HurtBox
		-- STOP in front of you, live so turning steers it; from behind, the arc carries them over you
		local function spot(): Vector3?
			if root.Parent == nil then return nil end
			local look = hurtbox.CFrame.LookVector
			return root.Position + Vector3.new(look.X, 0, look.Z).Unit * STOP
		end
		local gap = ((eroot.Position - (spot() :: Vector3)) * Vector3.new(1, 0, 1)).Magnitude
		unpin = pinTo(eroot, spot, { axes = Vector3.new(1, 0, 1), maxSpeed = math.max(gap, 1) / PULL_T, maxTime = PULL_T + 0.1 })
		kb(HOP, eroot, 0.05)
	end
	-- the pin outlives the swing and lets go on arrival; only a cancel drops them early
	if this:feintWait(REELED - YANK) then
		if unpin then unpin() end
		bail(this, humObj)
		release(this, enemy, false)
		return
	end

	model.Hold.Swing1:Play()
	humObj.walkSpeed:RemoveMod("stopMoving")
end

return function(this: wepTyp & any): wepType.atkResult
	if this._hooked then return reel(this) end
	return lunge(this)
end
