--!strict
local wepBase = require(game.ServerStorage.ROWA.Weps.WepBase)
local dmgConfig = require(script.Parent.Parent.dmgConfig)

local FORK = 0.08 -- pause before the 3rd swing that takes the branch
local UP = Vector3.yAxis
local HB_OFF, HB_SZ = CFrame.new(0,0,-3), Vector3.new(5.5,5.5,5.5)
local UPPER = table.freeze({swing3 = script.upperSlash})
local GROUND = table.freeze({
	anims  = script,
	swings = 4,
	dmg    = dmgConfig.m1,
	speed  = 0.8,
})
local AIR = table.freeze({
	anims  = script.air,
	swings = 3,
	dmg    = dmgConfig.airM1,
	speed  = 0.8,
})

-- ground swings 1-2 strike sheathed
local function indicator(this:any)
	return function()
		this:indicateAtk()
		this:sheathed(not this._air and (this.m1cycle == 1 or this.m1cycle == 2))
	end
end

local function upperSlash(this:any): wepBase.atkResult
	this.lastAttacked = tick() -- stops the helper resetting the string
	local hit = this.basicAtks.m1(
		this,
		UPPER,
		4, -- swings
		dmgConfig.upperSlash,
		0.56, -- windup
		HB_OFF,
		HB_SZ,
		indicator(this),
		0.1,   -- fadetime
		1,     -- weight
		0.8,   -- speed
		0.2,   -- endlag
		function(atk)
			atk.knockback = this:knockback(this._humObj.HurtBox.CFrame.LookVector*14.4 + UP*6.4, 0.3)
		end
	)
	if this.m1cycle == 3 then this.m1cycle = 0 end
	return hit
end

local function spin(this:any): wepBase.atkResult
	local hurtbox = this._humObj.HurtBox
	this.m1cycle = 0
	this:PlayAnim(script.spin, 0.08, 1, 1)
	this:indicateAtk()
	this:sheathed(false)
	local hitLanded = false
	for i = 1, 5 do
		if not this:windup(0.2) then
			this:stopLastAnim()
			return hitLanded
		end
		local look = hurtbox.CFrame.LookVector
		local hitbox, hits = this:hitbox(HB_OFF, HB_SZ)
		for _, enemy in hits do
			local atk = this:makeAtk(if i < 5 then dmgConfig.spin else dmgConfig.slam, enemy, look)
			atk.hitbox = hitbox
			if i == 5 then atk.knockback = this:knockback(look*5.3 - UP*16, 0.1, false, -1) end
			this:executeAttack(atk)
			if atk:isHit() then hitLanded = true end
		end
	end
	this:endLag(0.2)
	return hitLanded
end

return function(this:wepBase.myself&any): wepBase.atkResult
	local humObj = this._humObj
	local air = humObj.floating.Value > 0
	if air ~= this._air then
		this._air = air
		this.m1cycle = 0
	end

	local gap = tick() - humObj.attackAt
	if this.m1cycle == 2 and gap > FORK and gap < 1 then
		return if air then spin(this) else upperSlash(this)
	end

	local combo = if air then AIR else GROUND
	return this.basicAtks.m1(
		this,
		combo.anims,
		combo.swings,
		combo.dmg,
		0.4, -- windup
		HB_OFF,
		HB_SZ,
		indicator(this),
		0.1, -- fadetime
		1,   -- weight
		combo.speed
	)
end
