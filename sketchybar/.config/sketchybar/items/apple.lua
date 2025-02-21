local colors = require("colors")
local icons = require("icons")

-- Padding item required because of bracket
sbar.add("item", { width = 5 })

local apple = sbar.add("item", {
	icon = {
		font = { size = 16.0 },
		string = icons.apple,
		padding_right = 8,
		padding_left = 8,
		highlight_color = colors.green,
	},
	label = { drawing = false },
	background = {
		color = colors.bg,
		border_color = colors.black,
		border_width = 1,
	},
	padding_left = 1,
	padding_right = 8,
	click_script = "$CONFIG_DIR/helpers/menus/bin/menus -s 0",
})

apple:subscribe("mouse.entered", function()
	sbar.animate("tanh", 10, function()
		apple:set({
			icon = { highlight = true },
			label = { highlight = true },
			background = { border_width = 2 },
		})
	end)
end)

apple:subscribe("mouse.exited", function()
	-- Maintain highlight if this is the focused workspace
	sbar.animate("tanh", 10, function()
		apple:set({
			icon = { highlight = false },
			label = { highlight = false },
			background = { border_width = 0 },
		})
	end)
end)
