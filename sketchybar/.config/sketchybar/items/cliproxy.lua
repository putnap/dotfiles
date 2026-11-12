local colors = require("colors")

-- Anthropic throttles its usage endpoint, so not every 30s as clauth's item was.
local cliproxy = sbar.add("item", "cliproxy", { position = "right", update_freq = 180 })

-- 5h / 7d / Fable week of the account new sessions go to: a spent per-model week idles the
-- account for that model while both aggregate windows still read low.
cliproxy:subscribe({ "forced", "routine" }, function()
	sbar.exec("$CONFIG_DIR/helpers/cliproxy_usage.sh", function(out)
		local worst = 0
		for pct in out:gmatch("(%d+)[/%%]") do
			worst = math.max(worst, tonumber(pct))
		end
		cliproxy:set({
			drawing = out ~= "",
			label = { string = out:gsub("%s+$", ""), color = worst >= 85 and colors.red or colors.fg },
		})
	end)
end)
