--!strict
-- The settings window. Owns the tab strip, page visibility, and which page is up.
--
-- Pages are DISCOVERED: any Frame parented to Terminal with a `module` child that
-- returns the contract below becomes a tab. Adding one touches no file here and
-- none in the bootstrap. Pages sit directly in Terminal so they're authored in the
-- size/position context they actually render in.
--
-- Pages that CAN'T be authored there register with module.addTab() instead --
-- mobileUI injects its touch-button editor at runtime, only on touch devices.
--
-- PAGE CONTRACT (what the `module` child returns)
--   open      ()->()     render your content. the terminal owns .Visible, not you
--   close     ()->()     drop your content. also fires when availability is lost
--   order     number?    tab strip slot, low = left            (default 100)
--   default   boolean?   focus me when the window opens with nothing up
--   available boolean?   start with a tab button?              (default true)
--   init      (ctx)->()  once, at discovery. ctx.setAvailable(bool) is how a page
--                        comes and goes at runtime -- Slot follows the loaded slot
--                        with it, so no other file needs to know that rule.

local term  = script.Parent:WaitForChild("Terminal")
local strip = term:WaitForChild("tabs")
local tabTemplate = script:WaitForChild("tab")

export type ctx = { setAvailable: (value: boolean) -> () }
export type page = {
	open: () -> (),
	close: () -> (),
	order: number?,
	default: boolean?,
	available: boolean?,
	init: ((ctx: ctx) -> ())?,
}

type entry = {
	id: string,
	page: page,
	frame: Frame,
	tab: any?,   -- the strip button, nil while the page is unavailable
	order: number,
}

local module = {}
local entries: {[string]: entry} = {}
local openId: string? = nil

local function setOpenVisual(tab: any)
	tab.Back.Text = "X"
	tab.Frame.BackgroundColor3 = Color3.new(0.611765, 0.611765, 0.611765)
	tab.Back.TextColor3 = Color3.new(0, 0, 0)
	tab.TextButton.TextColor3 = tab.Back.TextColor3
	tab.BackgroundColor3 = tab.Frame.BackgroundColor3
end

local function setClosedVisual(tab: any)
	tab.Back.Text = "|"
	tab.Frame.BackgroundColor3 = Color3.new(0.313725, 0.301961, 0.298039)
	tab.Back.TextColor3 = Color3.new(0.701961, 0.701961, 0.701961)
	tab.TextButton.TextColor3 = tab.Back.TextColor3
	tab.BackgroundColor3 = tab.Frame.BackgroundColor3
end

local function closeAll()
	for _, e in pairs(entries) do
		if e.tab then setClosedVisual(e.tab) end
		e.frame.Visible = false
		e.page.close()
	end
	openId = nil
end

function module.open(id: string)
	local e = entries[id]
	if e == nil or e.tab == nil then return end -- unknown, or currently unavailable
	closeAll()
	setOpenVisual(e.tab)
	openId = id
	e.frame.Visible = true
	e.page.open()
end

function module.closeAll()
	closeAll()
end

function module.getOpenId(): string?
	return openId
end

-- Opens the lowest-order available page that asked to be the default. No-ops when
-- something is already up, so reopening the window mid-edit doesn't yank the
-- player off the tab they picked.
function module.openDefault()
	if openId ~= nil then return end
	local best: entry? = nil
	for _, e in pairs(entries) do
		if e.page.default and e.tab and (best == nil or e.order < best.order) then
			best = e
		end
	end
	if best then module.open(best.id) end
end

local function makeTab(e: entry)
	if e.tab then return end
	local tab = tabTemplate:Clone()
	tab.TextButton.Text = e.id
	tab.LayoutOrder = e.order -- strip is SortOrder.LayoutOrder; every tab used to be 0
	setClosedVisual(tab)
	tab.Visible = true
	tab.TextButton.MouseButton1Down:Connect(function() module.open(e.id) end)
	tab.Back.MouseButton1Down:Connect(closeAll)
	tab.Parent = strip
	e.tab = tab
end

local function dropTab(e: entry)
	if e.tab == nil then return end
	if openId == e.id then closeAll() end
	e.tab:Destroy()
	e.tab = nil
	e.frame.Visible = false
	e.page.close()
end

-- Returning the contract IS the discriminator. Terminal's chrome (Back, bg, line,
-- tabs, topframe) has no `module` child, and anything that does but returns the
-- wrong shape is skipped loudly rather than half-registered.
local function asPage(mod: ModuleScript): page?
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[settings] page '" .. mod.Parent.Name .. "' failed to load: " .. tostring(result))
		return nil
	end
	if type(result) ~= "table" or type(result.open) ~= "function" or type(result.close) ~= "function" then
		warn("[settings] '" .. mod.Parent.Name .. "'.module is not a page (needs open + close)")
		return nil
	end
	return result :: page
end

local function registerPage(id: string, frame: Frame, mod: ModuleScript, orderOverride: number?)
	if entries[id] then return end

	local pg = asPage(mod)
	if pg == nil then return end

	local e: entry = {
		id = id,
		page = pg,
		frame = frame,
		tab = nil,
		order = orderOverride or pg.order or 100,
	}
	entries[id] = e
	frame.Visible = false
	frame.Parent = term

	if pg.available ~= false then makeTab(e) end
	if pg.init then
		pg.init({
			setAvailable = function(value: boolean)
				if value then makeTab(e) else dropTab(e) end
			end,
		})
	end
end

-- Registers a page that does NOT live under Terminal, so discovery can't see it.
-- mobileUI uses this: its touch-button editor is injected at runtime and only on
-- touch devices, so it can't be authored into Terminal like the others. The frame
-- still needs a `module` child returning the contract; it gets reparented in.
function module.addTab(id: string, frame: Frame, layoutOrder: number?)
	local mod = frame:FindFirstChild("module")
	if mod == nil or not mod:IsA("ModuleScript") then
		warn("[settings] addTab('" .. id .. "') needs a `module` child returning {open, close}")
		return
	end
	registerPage(id, frame, mod, layoutOrder)
end

local function discover()
	-- the strip is authored empty and every button is built here; clear anything
	-- left over so discovery can't ever double up
	for _, c in ipairs(strip:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end

	for _, frame in ipairs(term:GetChildren()) do
		if not frame:IsA("Frame") then continue end
		local mod = frame:FindFirstChild("module")
		if mod == nil or not mod:IsA("ModuleScript") then continue end
		registerPage(frame.Name, frame, mod)
	end
end

discover()

return module
