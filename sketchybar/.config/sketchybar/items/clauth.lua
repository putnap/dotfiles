local colors = require("colors")

local clauth = sbar.add("item", "clauth", { position = "right", update_freq = 30 })

clauth:subscribe({ "forced", "routine" }, function()
	sbar.exec(
		[[jq -j '.active_profile as $a | .profiles[] | select(.name == $a) | "\($a) \([.windows[].utilization_pct // 0] | max | round)%"' ~/.clauth/status.json]],
		function(out)
			clauth:set({
				drawing = out ~= "",
				label = { string = out, color = (tonumber(out:match("(%d+)%%")) or 0) >= 85 and colors.red or colors.fg },
			})
		end
	)
end)
