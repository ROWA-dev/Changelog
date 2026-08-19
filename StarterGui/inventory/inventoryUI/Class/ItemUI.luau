--!strict
-- by air ofc <3
export type myself = {
	Frame: Frame & {TextButton: TextButton, Img: ImageLabel},
	select: (self:myself, setTo:boolean)->(),
	cooldown: (self:myself, seconds:number)->(),

	new: ()->myself,
	destroy: (self:myself)->(),
}

local module = {}
module.__index = module


function module.new():myself
	local self = setmetatable({
		empty = true,
		Frame = script.item:Clone()
	}, module) :: any&myself
	return self
end

function module.destroy(self:myself)
	local tween = (self::any)._cdTween
	if tween then tween:Cancel() end
	self.Frame:Destroy()
	table.clear(self)
	setmetatable(self, nil)
end


--- methods


function module.select(self:myself, setTo:boolean)
	local frame = self.Frame
	if setTo == true then
		local border = frame:FindFirstChild("border") or script.border:Clone()
		border.Enabled = true
		border.Parent = frame
		frame.Img.ImageColor3 = Color3.new(0.141176, 0.180392, 0.262745)
	else
		local border = frame:FindFirstChild("border") or script.border:Clone()
		border.Enabled = false
		border.Parent = frame
		frame.Img.ImageColor3 = script.item.Img.ImageColor3
	end
end


-- The minecraft-style cooldown wipe. Drop a Frame named `cd` (the wipe) or a
-- TextLabel named `cdText` (the readout) under this script to restyle either in
-- studio; this builds plain ones if they aren't there, so the feature doesn't
-- depend on an instance existing.
--
-- The two are SIBLINGS on purpose. The readout used to be a child of the wipe,
-- pinned to its top edge, so it slid down the slot as the wipe drained and was
-- unreadable. It now sits still on the slot and only the wipe moves.
local _cdTemplate: Frame? = nil
local function cdTemplate(): Frame
	if _cdTemplate then return _cdTemplate end

	local found = script:FindFirstChild("cd")
	if found then
		_cdTemplate = found::Frame
		return found::Frame
	end

	local f = Instance.new("Frame")
	f.Name = "cd"
	f.AnchorPoint = Vector2.new(0, 1)
	f.Position = UDim2.fromScale(0, 1)
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 0.5
	f.BorderSizePixel = 0
	f.ZIndex = 5

	_cdTemplate = f -- built once, cloned per slot
	return f
end

local _cdTextTemplate: TextLabel? = nil
local function cdTextTemplate(): TextLabel
	if _cdTextTemplate then return _cdTextTemplate end

	local found = script:FindFirstChild("cdText")
	if found then
		_cdTextTemplate = found::TextLabel
		return found::TextLabel
	end

	-- top-centre: `num` (the hotbar key) owns the top-left corner and the item
	-- name is centred, so this is the one corner nothing else is drawn in. It is
	-- also the part the wipe covers LONGEST, i.e. dark background the whole time.
	local t = Instance.new("TextLabel")
	t.Name = "cdText"
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.new(0.5, 0, 0, -2)
	t.Size = UDim2.new(1, 0, 0, 16)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.SourceSans
	t.TextSize = 14
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.RichText = true -- for SUFFIX below
	t.ZIndex = 6 -- above the wipe (5), sibling ZIndexBehaviour

	_cdTextTemplate = t
	return t
end

-- the number is what you read; the unit is small and dim so it stops competing
-- with it. Needs RichText on the label.
local SUFFIX = '<font size="9" color="rgb(165,165,165)">s</font>'

local ts = game:GetService("TweenService")
function module.cooldown(self:myself, seconds:number)
	local frame = self.Frame
	local overlay:any = frame:FindFirstChild("cd")
	if overlay == nil then
		overlay = cdTemplate():Clone()
		overlay.Parent = frame
	end
	local label:any = frame:FindFirstChild("cdText")
	if label == nil then
		label = cdTextTemplate():Clone()
		label.Parent = frame
	end

	local prev = (self::any)._cdTween
	if prev then prev:Cancel() end -- a retrigger replaces, never stacks

	if seconds <= 0 then
		overlay.Visible = false
		label.Visible = false
		return
	end

	overlay.Visible = true
	overlay.Size = UDim2.fromScale(1, 1)
	label.Visible = true
	label.Text = tostring(math.floor(seconds * 10) / 10) .. SUFFIX

	-- one linear tween, nothing ticks. the text is the TOTAL, same as the
	-- cooldowns list does it; the wipe is what shows progress.
	local tween = ts:Create(overlay, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromScale(1, 0)
	});
	(self::any)._cdTween = tween
	tween:Play()
	tween.Completed:Connect(function(state)
		-- Cancel() fires this too, and deferred signals mean it lands AFTER the
		-- retrigger above already re-showed both. Only a real finish hides them.
		if state == Enum.PlaybackState.Completed then
			overlay.Visible = false
			label.Visible = false
		end
		if (self::any)._cdTween == tween then
			(self::any)._cdTween = nil
		end
		tween:Destroy()
	end)
end


return table.freeze(module)
