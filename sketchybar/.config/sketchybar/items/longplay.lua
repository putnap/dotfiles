local colors = require("colors")

-- The installed app's daemon CLI: the same answer the window and Raycast read.
local LONGPLAYD = "/Applications/Longplay.app/Contents/MacOS/longplayd"

local longplay = sbar.add("item", "longplay", {
	position = "right",
	update_freq = 20,
	drawing = false,
	-- Hidden is its usual state, and a hidden item only updates when asked to.
	updates = true,
	icon = { string = "󰝚" },
	click_script = "open -a Longplay",
})

-- `2 · 5↓`: two wait on you, five are on their way.
local function said(waiting, working)
	if waiting > 0 and working > 0 then
		return waiting .. " · " .. working .. "↓"
	end
	return waiting > 0 and tostring(waiting) or working .. "↓"
end

-- Drawn only while something is open: what waits on you in red, then what is
-- still on its way. Click for the Longplay window.
longplay:subscribe({ "forced", "routine" }, function()
	sbar.exec(LONGPLAYD .. [[ status --json | jq -j '.counts | "\(.questions + .errors) \(.working)"']], function(out)
		local waiting, working = out:match("(%d+) (%d+)")
		waiting, working = tonumber(waiting) or 0, tonumber(working) or 0
		longplay:set({
			drawing = waiting + working > 0,
			label = { string = said(waiting, working), color = waiting > 0 and colors.red or colors.fg },
		})
	end)
end)
