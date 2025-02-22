local settings = require("settings")
local colors = require("colors")

-- Equivalent to the --default domain
sbar.default({
	updates = "when_shown",
	icon = {
		font = {
			family = settings.font.text,
			style = settings.font.style_map["Bold"],
			size = 14.0,
		},
		color = colors.fg,
		padding_left = settings.paddings,
		padding_right = settings.paddings,
		background = { image = { corner_radius = settings.corner_radius } },
		highlight_color = colors.green,
	},
	label = {
		font = {
			family = settings.font.text,
			style = settings.font.style_map["Semibold"],
			size = 13.0,
		},
		color = colors.fg,
		padding_left = settings.paddings,
		padding_right = settings.paddings,
		highlight_color = colors.green,
	},
	background = {
		height = 28,
		corner_radius = settings.corner_radius,
		border_width = 2,
		border_color = colors.bg2,
		image = {
			corner_radius = settings.corner_radius,
			border_color = colors.grey,
			border_width = 1,
		},
	},
	popup = {
		background = {
			border_width = 2,
			corner_radius = settings.corner_radius,
			border_color = colors.popup.border,
			color = colors.bar.bg,
			shadow = { drawing = true },
		},
		blur_radius = 50,
	},
	padding_left = settings.group_paddings,
	padding_right = settings.group_paddings,
	scroll_texts = true,
})
