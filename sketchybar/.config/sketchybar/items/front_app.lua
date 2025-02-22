local colors = require("colors")
local app_icons = require("app_icons")
local settings = require("settings")

local front_app = sbar.add("item", "front_app", {
	display = "active",
	icon = {
		drawing = false,
		color = colors.white,
		font = "sketchybar-app-font:Regular:16.0",
		y_offset = -1,
	},
	label = {
		font = {
			style = settings.font.style_map["Black"],
			size = 12.0,
		},
	},
	updates = true,
	padding_left = 10,
})

front_app:subscribe("mouse.entered", function()
	sbar.animate("tanh", 10, function()
		front_app:set({
			icon = { highlight = true },
			label = { highlight = true },
			background = { border_width = 2 },
		})
	end)
end)

front_app:subscribe("mouse.exited", function()
	-- Maintain highlight if this is the focused workspace
	sbar.animate("tanh", 10, function()
		front_app:set({
			icon = { highlight = false },
			label = { highlight = false },
			background = { border_width = 0 },
		})
	end)
end)

front_app:subscribe("front_app_switched", function(env)
	local lookup = app_icons[env.INFO]
	local icon = ((lookup == nil) and app_icons["Default"] or lookup)
	front_app:set({
		icon = {
			drawing = true,
			string = icon,
		},
		label = { string = env.INFO },
	})
end)

front_app:subscribe("mouse.clicked", function()
	sbar.trigger("swap_menus_and_spaces")
end)
