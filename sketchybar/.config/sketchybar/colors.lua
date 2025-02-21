return {
	black = 0xff444a73,
	white = 0xffe2e2e3,
	red = 0xffff757f,
	green = 0xffc3e88d,
	green1 = 0xff4fd6be,
	green2 = 0xff41a6b5,
	blue = 0xff82aaff,
	blue0 = 0xff3e68d7,
	blue1 = 0xff65bcff,
	blue2 = 0xff0db9d7,
	blue5 = 0xff89ddff,
	blue6 = 0xffb4f9f8,
	blue7 = 0xff394b70,
	yellow = 0xffffc777,
	orange = 0xffff966c,
	magenta = 0xffc099ff,
	grey = 0xff7f8490,
	transparent = 0x00000000,

	bar = {
		bg = 0xf0222436,
		border = 0xff1e2030,
	},
	popup = {
		bg = 0x7e222436,
		border = 0xff1e2030,
	},
	bg1 = 0x7e222436,
	bg2 = 0xff1e2030,

	fg = 0xffc8d3f5,
	fg_dark = 0xff828bb8,
	fg_gutter = 0xff3b4261,
	with_alpha = function(color, alpha)
		if alpha > 1.0 or alpha < 0.0 then
			return color
		end
		return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
	end,
}
