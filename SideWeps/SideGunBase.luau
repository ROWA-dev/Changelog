--!strict
local baseClass = require(script.Parent:WaitForChild("SideWepBase"))
local Debris = game:GetService("Debris")

export type myself = baseClass.myself & {
	shots: number,
}

local module = {
	Name = "SideGunBase",

	-- subclass statics. Every one of these differed between the rowa1 copies.
	MAX_SHOTS   = 3,
	WINDUP      = 0.48,   -- rowa1 counted 4 x 0.12 with a stun check each step
	RELOAD_TIME = 0.9,
	END_LAG     = 0,
	HITBOX_SIZE = Vector3.new(3, 3, 5),
	HITBOX_OFFSET = CFrame.new(0,0,-4),
	MAX_TARGETS = 3,
	PELLETS     = 1,
	SPREAD      = 0,   -- radians of scatter per pellet
	MELEE_KB    = 0,   -- studs of shove on the close-range hit only; 0 = none
	MELEE_KB_T  = 0.2,
	DMG = nil :: any,  -- close-range dmgTbl
	PROJ = nil :: any, -- the bullet's whole config, dmgTbl included
}
module.__tostring = baseClass.__tostring
module.__index = module
setmetatable(module, { __index = baseClass })

local function flashMuzzle(self: any): Attachment?
	local model = self._model
	local top = model and model:FindFirstChild("Model")
	top = top and top:FindFirstChild("Blade2")
	top = top and top:FindFirstChild("Top")
	if top == nil or not top:IsA("Attachment") then return nil end
	for _, v in ipairs(top:GetChildren()) do
		local count = tonumber(v.Name)
		if count and v:IsA("ParticleEmitter") then v:Emit(count) end
	end
	return top
end

local function sound(self: any, name: string, pitch: number?)
	local model = self._model
	local hold = model and model:FindFirstChild("Hold")
	local src = hold and hold:FindFirstChild(name)
	if src == nil or not src:IsA("Sound") then return end
	local voice = src:Clone()
	voice.PlaybackSpeed = pitch or src.PlaybackSpeed
	voice.Parent = hold
	voice:Play()
	Debris:AddItem(voice, 4)
end

local function randVec(s)
	return Vector3.new(
		(math.random() * 2 - 1) * s,
		(math.random() * 2 - 1) * s,
		(math.random() * 2 - 1) * s
	)
end
-- PARRIED BULLETS GO BACK, shared by every gun.
-- !! newOwner is what makes it arrive: HitboxQuery ignores the owner, so without it the bullet passes through the shooter.
function module.onBulletHit(proj: any, attack: any)
	if not attack:isParried() then return end

	local eroot = attack.enemyEntity.HRootPart
	if eroot == nil then return end

	proj:deflect(
		proj:parryDir(
			(eroot.CFrame.LookVector + randVec(0.2)).Unit
		),
		nil,
		0,
		attack.enemyEntity
	)
end

--- subclasses call this, then clone their OWN model, exactly like a WepBase subclass.
function module.new(humObj): myself
	local abstract = baseClass.new(humObj) :: baseClass.myself
	local self: myself = setmetatable(abstract, module) :: any
	self.shots = self.MAX_SHOTS
	return self
end

function module.reload(self: any)
	self:PlayAnim(self.Reload, 0.8)
	sound(self, "reload")
	task.wait(self.RELOAD_TIME)
	self.shots = self.MAX_SHOTS
end

--- everything the shot does once the windup survives.
function module.fire(self: any)
	local humObj = self._humObj
	local root = humObj.HRootPart
	if root == nil then return end

	local muzzle = flashMuzzle(self)
	self.shots -= 1

	local hurtbox = humObj.HurtBox
	local origin = hurtbox.Position
	local look = hurtbox.CFrame.LookVector
	local _, hits = self:hitbox(
		self.HITBOX_OFFSET,
		self.HITBOX_SIZE
	)

	local landed = 0
	for _, enemy in ipairs(hits) do
		if landed >= self.MAX_TARGETS then break end
		local atk = self:makeAtk(self.DMG, enemy, look)
		-- point blank only. The bullet never gets this; its kb would be PROJ's job.
		if self.MELEE_KB > 0 then
			atk.knockback = self:knockback(look * self.MELEE_KB, self.MELEE_KB_T)
		end
		self:executeAttack(atk)
		-- !! landings, not bodies in the box: an i-framed body is a whiff, and counting it cost the shot its bullets too.
		if not atk:isDodged() then landed += 1 end
	end

	if landed == 0 then
		local from = origin + look * 2
		for _ = 1, self.PELLETS do
			local dir = look
			if self.SPREAD > 0 then
				dir = (
					CFrame.new(Vector3.zero, look)
					* CFrame.Angles(
						math.random() * self.SPREAD * 2 - self.SPREAD,
						math.random() * self.SPREAD * 2 - self.SPREAD,
						0
					)
				).LookVector
			end
			self:projectile(self.PROJ, CFrame.new(from, from + dir))
		end
	end

	sound(self, "shot", math.random(90, 120) / 100)
end

local function indicateAtk(self)
	local model = self._model
	local top = model and model:FindFirstChild("Model")
	top = top and top:FindFirstChild("Blade2")
	top = top and top:FindFirstChild("Top")
	if top == nil or not top:IsA("Attachment") then return nil end
	top:FindFirstChild("sharp"):Emit(1)
	return nil
end
--- THE bind entry. use() owns the attacking lock; this owns what happens inside it.
function module.use(self: any): boolean
	return baseClass.use(self, function()
		if self.shots <= 0 then
			self:reload()
			return
		end

		sound(self, "load")
		-- rowa1 alternated the draw pose off the shot count
		self:PlayAnim(if self.shots == 2 then self.Draw2 else self.Draw, 0.8)
		indicateAtk(self)

		-- a stun during the draw cancels the whole thing, and the shot is NOT spent
		if not self:windup(self.WINDUP) then
			self:StopAnim()
			return
		end
		if self._track then self._track:AdjustSpeed(1.2) end

		self:fire()
		if self.END_LAG > 0 then self:endLag(self.END_LAG) end
		return nil
	end)
end

return module
