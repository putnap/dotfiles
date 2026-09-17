local colors = require("colors")

local clauth = sbar.add("item", "clauth", { position = "right", update_freq = 30 })

-- 5h / 7d / Fable week: a spent per-model week idles the account for that
-- model while both aggregate windows still read low.
clauth:subscribe({ "forced", "routine" }, function()
	sbar.exec(
		[[jq -j '.active_profile as $a | .profiles[] | select(.name == $a) | (.windows | map({(.label | ascii_downcase | sub("^7d ";"")): (.utilization_pct // 0 | round)}) | add) as $w | "\($a) \($w["5h"] // 0)/\($w["7d"] // 0)/\($w.fable // 0)%"' ~/.clauth/status.json]],
		function(out)
			local worst = 0
			for pct in out:gmatch("(%d+)[/%%]") do
				worst = math.max(worst, tonumber(pct))
			end
			clauth:set({
				drawing = out ~= "",
				label = { string = out, color = worst >= 85 and colors.red or colors.fg },
			})
		end
	)
end)
