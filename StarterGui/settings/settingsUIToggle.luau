-- Settings bootstrap. Topbar icon <-> window, and that's the whole job.
-- Tabs live in settings/Pages and register themselves, so this file has no
-- knowledge of which tabs exist or when any of them should appear.
local terminal = require(script.Parent:WaitForChild("terminalModule"))
local term = script.Parent:WaitForChild("Terminal")
local topbar = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TopbarIcons"))

local icon
icon = topbar.register({
	name  = "settings",
	order = 1,
	frame = script.Parent:WaitForChild("TopbarIcon"),
	onClick = function()
		term.Visible = not term.Visible
		icon:setActive(term.Visible)
		if term.Visible then
			terminal.openDefault()
		end
	end,
})
