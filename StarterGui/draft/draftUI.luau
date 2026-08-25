--!strict
-- The level-up draft. rowa1 CoreUI + MainUI/CardsLvlUI, rewritten onto plrObj.
-- Destroying a card frame severs its own connections, so that IS the cleanup:
-- rowa1's cardconnections table, its four clear loops and its `#loadedCards > 2` are gone.
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local clientData = require(game.ReplicatedFirst:WaitForChild("ClientData"))
local DraftTiers = require(game.ReplicatedStorage.Modules.DraftTiers)
local ShiftLock  = require(game.ReplicatedStorage.Modules.ShiftLock)
local plrObj = clientData.plrObj

local gui          = script.Parent :: any
local lvlButton    = gui:WaitForChild("LevelButton") :: any
local cardOut      = gui:WaitForChild("cardOut") :: any
local cardsPanel   = cardOut:WaitForChild("Cards") :: any
local shuffleFrame = cardsPanel:WaitForChild("zzShuffle") :: any
local shuffleBtn   = shuffleFrame:WaitForChild("ImageButton") :: any
local fxTemplate   = gui:WaitForChild("lvlFx") :: any

local DEAL_STAGGER = 0.3 -- rowa1 dealt at (i-1)/2; 0.15 was too quick to read
local SHUFFLE_CD   = 1   -- rowa1's client gate; the server gates again at 0.25
local GOLD = Color3.fromRGB(255, 183, 0)
--- rowa1's ability face. Its other id (7485051715) is the card face, for when cards join the pool.
local ABILITY_ICON = "rbxassetid://8575479406"

local FLIP   = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local UNFLIP = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PICK   = TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.In)
local FX     = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local slot: any = nil
local page = 0
local open = false
local nextShuffle = 0

-- one voice per call: :Play() on a shared Sound RESTARTS it, so staggered flips cut each other off.
local function play(sound: Sound, pitch: number)
	local voice = sound:Clone()
	voice.PlaybackSpeed = pitch
	voice.Parent = SoundService
	voice:Play()
	Debris:AddItem(voice, 4)
end

-- the expanding ring. Cloned because a level-up and a click can overlap.
local function burst(size: number)
	local fx = fxTemplate:Clone()
	fx.Visible = true
	fx.Frame.Visible = true
	fx.Parent = gui
	local stroke = fx.Frame.UIStroke
	stroke.Color = GOLD
	TweenService:Create(stroke, FX, { Transparency = 1 }):Play()
	local grow = TweenService:Create(fx.Frame, FX, { Size = UDim2.new(size, 0, size, 0) })
	grow:Play()
	grow.Completed:Once(function() fx:Destroy() end)
end

local function clearCards()
	for _, v in pairs(cardsPanel:GetChildren()) do
		if v:IsA("Frame") and v ~= shuffleFrame then v:Destroy() end
	end
end

local function pending(): number
	return if slot then slot:pendingProg() else 0
end

local function refreshBadge()
	lvlButton.Visible = pending() > 0
end

local function setOpen(on: boolean)
	if open == on then return end
	open = on
	cardOut.Visible = on
	shuffleFrame.Visible = on
	ShiftLock.block("draft", on)
	if not on then clearCards() end
end

-- rows come resolved from draftOffer.roll; the client owns no ability metadata.
local function makeCard(row: any, index: number)
	local card = script.Card:Clone()
	card.Name = row.name
	local inner = card:WaitForChild("Inner") :: any
	inner.Label.Text = row.name
	inner.Desc.Text  = row.desc
	inner.UIStroke.Color = DraftTiers.colorOf(row.tier)
	inner.ImageLabel.Image = ABILITY_ICON
	-- hidden until the flip lands, so the face is never readable edge-on
	inner.Label.Visible = false
	inner.Desc.Visible = false
	inner.ImageLabel.Visible = false
	card.Parent = cardsPanel

	local button = inner:WaitForChild("TextButton") :: any
	button.MouseEnter:Connect(function()
		play(SoundService.Tap :: any, 0.9 + index / 30)
		button.UIStroke.Thickness = 1
	end)
	button.MouseLeave:Connect(function()
		button.UIStroke.Thickness = 0
	end)
	button.MouseButton1Up:Connect(function()
		if not open then return end
		-- close WITHOUT clearCards: this card animates itself out below.
		open = false
		shuffleFrame.Visible = false
		lvlButton.Visible = false
		-- cardOut stays visible so the pick can animate out
		ShiftLock.block("draft", false)

		plrObj:claimDraft(row.id)

		for _, v in pairs(cardsPanel:GetChildren()) do
			if v:IsA("Frame") and v ~= shuffleFrame and v ~= card then v:Destroy() end
		end
		local collapse = TweenService:Create(inner, PICK, { Size = UDim2.new(1, 0, 0, 0) })
		collapse:Play()
		-- guarded in case a new draft opened during the collapse.
		collapse.Completed:Once(function()
			card:Destroy()
			if not open then cardOut.Visible = false end
		end)
	end)

	task.delay((index - 1) * DEAL_STAGGER, function()
		if inner.Parent == nil then return end
		play(SoundService.PageFlip :: any, math.random(80, 120) / 100)
		local flip = TweenService:Create(inner, FLIP, { Size = UDim2.new(0, 0, 1, 0) })
		flip:Play()
		flip.Completed:Once(function()
			if inner.Parent == nil then return end
			inner.Label.Visible = true
			inner.Desc.Visible = true
			inner.ImageLabel.Visible = true
			TweenService:Create(inner, UNFLIP, { Size = UDim2.new(1, 0, 1, 0) }):Play()
		end)
	end)
end

lvlButton.MouseButton1Up:Connect(function()
	if open then setOpen(false) return end
	if pending() <= 0 then return end
	page = 0
	setOpen(true)
	burst(2)
	plrObj:requestDraft(page)
end)

-- rowa1's shuffle is PAGING, not a reroll: it walks the eligible set 5 at a time.
shuffleBtn.MouseButton1Up:Connect(function()
	if not open then return end
	local now = os.clock()
	if now < nextShuffle then return end
	nextShuffle = now + SHUFFLE_CD
	play(SoundService.Tap :: any, 1)
	page += 1
	plrObj:requestDraft(page)
end)

plrObj.draftOfferRecieved:Connect(function(rows)
	if not open then return end
	clearCards()
	for i, row in ipairs(rows) do
		makeCard(row, i)
	end
end)

local function bind(slotData: any)
	slot = slotData
	setOpen(false)
	refreshBadge()

	slotData.onStatChange:Connect(function(patch)
		if patch.lvl then
			play(SoundService.lvlUp :: any, 1)
			burst(40)
		end
		-- pendingProg moves with all three, so all three refresh the badge.
		if patch.lvl or patch.allocPts or patch.prog then
			refreshBadge()
			if pending() <= 0 then setOpen(false) end
		end
	end)
end

plrObj.slotLoaded:Connect(bind)

lvlButton.Visible = false
shuffleFrame.Visible = false
cardOut.Visible = false
clearCards()

-- AFTER the resets above, or they would undo the badge. A respawn rebuilds this
-- GUI once slotLoaded has already fired, so pick the slot up directly too.
if plrObj:IsSlotLoaded() and plrObj.Data then
	local existing = plrObj.Data.slots[plrObj.loadedSlotId]
	if existing then bind(existing) end
end
