--!strict
--- Spear - rowa2 id 9. Family Medium/Spear.
--- THE HEAVY IS A THROW: it leaves your hand, flies, sticks in what it reaches,
--- and while it is gone you fight with your FISTS. It returns on its own after
--- at most 4.6s, sooner if you walk to it.
--- rowa1's Spear/Main throw joined to rowa2's stance switch -- rowa1 had the
--- throw but no fist mode, rowa2 had the fist mode but merely DROPPED the spear.
--- Full notes: rowa1OldPlanToPort/README.md/PORTW_SpearThrow.md
--- spearState 1 = in hand, 2 = thrown. Every exit goes through :resetSpear,
--- the only thing allowed to touch the weld/anchor pair -- see its header.
local baseWep = require(script.Parent)

export type myself = baseWep.myself & {
	spearState: number
}

--[[ Resolved ONCE, at load, BEFORE any instance can park its own clone
	beside it. :unwield parks `_model` at `script` (the house pattern --
	Executer, Slayer, Oblitar all do it), so a later `script.Model` would
	resolve by CHILD ORDER between the template and somebody's used clone.
	That is S11 Q5's landmine, and a used clone can now be carrying throw
	state. ]]
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
	--[[ ONE model per weapon instance, like Katana/Claymore/Slayer. This
		used to clone inside :wield and never destroy, so every re-equip
		leaked a model into `script` -- harmless while the model was
		stateless, and not harmless now that it carries a throw. ]]
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

--methods

--- The streak behind a thrown spear. THE TRAIL ONLY: the blade's wind /
--- windlines / sharp emitters are PULSED from the flight loop, never switched
--- on -- they ship Enabled = false with junk Rates (`wind` is inf) because they
--- have only ever been :Emit assets. A Trail is the exception: Enabled is its
--- only control, and WepBase drives `_trail` this way for every weapon.
function module.setFlightFx(self:myself&any, on:boolean)
	local model = self._model
	local spear = model and model:FindFirstChild("Model")
	local trail = spear and spear:FindFirstChild("throwTrail")
	if trail and trail:IsA("Trail") then trail.Enabled = on end
end

--- Put the spear back in the hand and the weapon back in spear stance.
--- Idempotent, safe to call when nothing was thrown.
--- !! THE ORDER OF THE LAST TWO WRITES IS LOAD-BEARING. A thrown spear is
--- ANCHORED and modelWeld joins it to Hold, which is Motor6D'd to the Right
--- Arm -- re-enable the weld while it is still anchored and the anchor
--- propagates into the CHARACTER'S OWN ASSEMBLY: the player freezes with no
--- error anywhere. Unanchor FIRST, then weld. rowa1 has the same order.
--- spearState is cleared BEFORE the projectile is killed on purpose: the
--- flight's onExpire will not touch the model unless still in state 2.
function module.resetSpear(self:myself&any)
	self.spearState = 1

	local proj = self._spearProj
	self._spearProj = nil
	--- :kill directly rather than through the Projectile registry, so this
	--- file needs no require of the projectile side at all.
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
	--- the old DROP left this collidable so the assembly would rest on the
	--- floor. Nothing drops any more.
	hold.CanCollide = false

	handle.Anchored = false          -- 1) free it
	hold.modelWeld.Enabled = true    -- 2) THEN put it back in the hand
end

--- resetSpear plus the pickup tells. The recall timer and the throw's own
--- bail branches both come through here.
function module.recallSpear(self:myself&any)
	if self.spearState ~= 2 then return end
	self:resetSpear()

	local model = self._model
	local spear = model and model:FindFirstChild("Model")
	local handle = spear and spear:FindFirstChild("Handle")
	local equip = handle and handle:FindFirstChild("equip")
	if equip then (equip :: Sound):Play() end

	--- rowa1 stops the idle when the spear leaves and replays it here.
	if self.idleTrack and self._humObj then
		self.idleTrack:Play()
	end
end

--- wield
function module.wield(self:myself&any)
	local humobj = self._humObj
	local char:any = humobj.Hum.Parent
	local model = self._model

	--[[ back to spear stance on EVERY wield. spearState used to be written
		only in .new(), so unequipping while thrown and re-equipping handed
		you the fist moveset with a spear visibly in your hand. ]]
	self:resetSpear()

	model.mtr.Enabled = true
	model.mtr.Part0 = char["Right Arm"]
	model.mtr.Part1 = model.Hold
	model.Parent = char

	--[[ THE THROW HAS ITS OWN ID. While the spear is gone this weapon falls
		through to WepBase's default fist heavy, which gates on "heavy" --
		sharing one id would let a throw eat the punch's cooldown and vice
		versa. 6s matches rowa1's `lastHeavy + 6`, measured from the START of
		the throw, so the spear is back (<=4.6s) with a little to spare.
		"heavy" is Fist's own 6. ]]
	humobj.cooldowns:setCooldown("spearThrow", 6)
	humobj.cooldowns:setCooldown("heavy", 6)
	baseWep.wield(self)
end

--- unwield
function module.unwield(self:myself&any)
	if self.lastAnim then
		self.lastAnim:Stop()
	end

	--- a spear in flight must not be parked into ServerStorage mid-throw
	self:resetSpear()

	local model = self._model
	if model then
		model.Parent = script
	end

	baseWep.unwield(self)
end

--- unequip
--- the family parks the model; reset before it, not after.
function module.unequip(self:myself&any)
	self:resetSpear()
	baseWep.unequip(self)
end

--- attack
module.attack = require(script.attack)

return table.freeze(module)
