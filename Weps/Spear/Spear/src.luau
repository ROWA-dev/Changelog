--!strict
-- Spear - the heavy is a THROW: it leaves your hand, you fight with fists, it returns within 4.6s.
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
	spearState: number -- 1 = in hand, 2 = thrown; every exit goes through :resetSpear
}

-- !! resolved ONCE at load: :unwield parks _model at `script`, so a later script.Model could resolve to a used clone by child order.
local TEMPLATE = script:WaitForChild("Model")

local module = {
	Name = "spear",
	idleAnim = script:WaitForChild("idle"),
}
module.__tostring = baseWep.__tostring
module.__index = module
setmetatable(module, { __index = baseWep })

function module.new(): myself&any
	local abstract = baseWep.new() :: baseWep.myself
	local self = setmetatable(abstract, module) :: myself&any
	-- ONE model per weapon instance; cloning in :wield instead leaks a model on every re-equip.
	local model = TEMPLATE:Clone()
	self._model = model
	self._trail = model:WaitForChild("Trail1")
	self.spearState = 1
	return self
end

function module.destroy(self:myself&any)
	self:unequip()
	if self._model then
		self._model:Destroy()
	end
	baseWep.destroy(self)
end

-- methods

-- the streak behind a thrown spear, THE TRAIL ONLY: the blade emitters are pulsed from the flight loop, never switched on.
function module.setFlightFx(self:myself&any, on:boolean)
	local model = self._model
	local spear = model and model:FindFirstChild("Model")
	local trail = spear and spear:FindFirstChild("throwTrail")
	if trail and trail:IsA("Trail") then trail.Enabled = on end
end

-- !! puts the spear back, idempotent; UNANCHOR FIRST THEN WELD, or the anchor propagates into the character's assembly and freezes the player.
function module.resetSpear(self:myself&any)
	self.spearState = 1 -- cleared before the kill: onExpire skips the model unless still in state 2

	local proj = self._spearProj
	self._spearProj = nil
	-- :kill directly, so this file needs no require of the projectile side.
	if proj ~= nil and proj.dead ~= true and proj.kill then
		proj:kill(false)
	end

	local model = self._model
	if model == nil then return end
	local spear = model:FindFirstChild("Model")
	local hold  = model:FindFirstChild("Hold")
	if spear == nil or hold == nil then return end

	local handle:any = spear:FindFirstChild("Handle")
	if handle == nil then return end

	self:setFlightFx(false)
	handle.humweld.Part0 = nil
	-- nothing drops any more, so this stays off.
	hold.CanCollide = false

	handle.Anchored = false          -- 1) free it
	hold.modelWeld.Enabled = true    -- 2) THEN put it back in the hand
end

-- resetSpear plus the pickup tells; the recall timer and the throw's bail branches both come here.
function module.recallSpear(self:myself&any)
	if self.spearState ~= 2 then return end
	self:resetSpear()

	local model = self._model
	local spear = model and model:FindFirstChild("Model")
	local handle = spear and spear:FindFirstChild("Handle")
	local equip = handle and handle:FindFirstChild("equip")
	if equip then (equip :: Sound):Play() end

	-- the idle stops when the spear leaves and replays here.
	if self.idleTrack and self._humObj then
		self.idleTrack:Play()
	end
end

-- wield
function module.wield(self:myself&any)
	local humobj = self._humObj
	local char:any = humobj.Hum.Parent
	local model = self._model

	-- back to spear stance on EVERY wield, or re-equipping while thrown hands you the fist moveset with a spear in hand.
	self:resetSpear()

	model.mtr.Enabled = true
	model.mtr.Part0 = char["Right Arm"]
	model.mtr.Part1 = model.Hold
	model.Parent = char

	-- separate ids: the fist heavy gates on "heavy", so one shared id would cross-eat cooldowns. 6s runs from the START of the throw.
	humobj.cooldowns:setCooldown("spearThrow", 6)
	humobj.cooldowns:setCooldown("heavy", 6)
	baseWep.wield(self)
end

-- unwield
function module.unwield(self:myself&any)
	if self.lastAnim then
		self.lastAnim:Stop()
	end

	-- a spear in flight must not be parked into ServerStorage mid-throw
	self:resetSpear()

	local model = self._model
	if model then
		model.Parent = script
	end

	baseWep.unwield(self)
end

-- unequip: the family parks the model, so reset before it, not after.
function module.unequip(self:myself&any)
	self:resetSpear()
	baseWep.unequip(self)
end

-- attack
module.attack = require(script.attack)

return table.freeze(module)
