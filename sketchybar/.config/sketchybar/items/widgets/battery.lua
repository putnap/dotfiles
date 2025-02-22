local icons = require("icons")
local colors = require("colors")
local settings = require("settings")

local battery = sbar.add("item", "widgets.battery", {
	position = "right",
	icon = {
		font = {
			style = settings.font.style_map["Regular"],
			size = 17.0,
		},
	},
	label = { font = { family = settings.font.numbers } },
	update_freq = 180,
	popup = { align = "center" },
})

local percentage = sbar.add("item", {
	position = "popup." .. battery.name,
	icon = {
		string = "Battery",
		align = "left",
		width = 150,
	},
	label = {
		string = "??%",
		align = "right",
	},
	padding_left = 10,
	padding_right = 10,
})

local remaining_time = sbar.add("item", {
	position = "popup." .. battery.name,
	icon = {
		string = "Time remaining:",
		align = "left",
		width = 150,
	},
	label = {
		string = "??:??h",
		align = "right",
	},
	padding_left = 10,
	padding_right = 10,
	drawing = false,
})

battery:subscribe({ "routine", "power_source_change", "system_woke" }, function()
	sbar.exec("pmset -g batt", function(batt_info)
		local icon = "!"
		local label = "??%"

		local found, _, charge = batt_info:find("(%d+)%%")
		if found then
			charge = tonumber(charge)
			label = charge .. "%"
		end

		local color = colors.fg
		local charging, _, _ = batt_info:find("AC Power")

		if charging then
			icon = icons.battery.charging
		else
			if found and charge > 80 then
				icon = icons.battery._100
			elseif found and charge > 60 then
				icon = icons.battery._75
			elseif found and charge > 40 then
				icon = icons.battery._50
			elseif found and charge > 20 then
				icon = icons.battery._25
				color = colors.orange
			else
				icon = icons.battery._0
				color = colors.red
			end
		end

		local lead = ""
		if found and charge < 10 then
			lead = "0"
		end

		battery:set({
			icon = {
				string = icon,
				color = color,
			},
			-- label = { string = lead .. label },
		})
		percentage:set({
			label = { string = lead .. label },
		})
	end)
end)

local function battery_collapse_details()
	local drawing = battery:query().popup.drawing == "on"
	if not drawing then
		return
	end
	battery:set({ popup = { drawing = false } })
end

battery:subscribe("mouse.clicked", function()
	local drawing = battery:query().popup.drawing
	battery:set({ popup = { drawing = "toggle" } })

	if drawing == "off" then
		sbar.exec("pmset -g batt", function(batt_info)
			local charging, _, _ = batt_info:find("AC Power")
			local found, _, remaining = batt_info:find(" (%d+:%d+) remaining")
			local label = found and remaining .. "h" or "No estimate"
			remaining_time:set({ drawing = not charging, label = label })
		end)
	end
end)
battery:subscribe("mouse.exited.global", battery_collapse_details)
battery:subscribe("mouse.entered", function()
	battery:set({ icon = { highlight = true } })
end)
battery:subscribe("mouse.exited", function()
	battery:set({ icon = { highlight = false } })
end)
