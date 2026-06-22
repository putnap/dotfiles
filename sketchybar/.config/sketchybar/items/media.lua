local icons = require("icons")
local colors = require("colors")

-- Now-playing source.
-- macOS 15.4+ gated the MediaRemote notification API, so sketchybar's built-in
-- `media_change` event no longer fires (SketchyBar issue #708, still open). The
-- ACTIVE path below streams events from `media-control` (mediaremote-adapter)
-- and forwards them as a custom `media_update` event; the widget shows whatever
-- is playing (filter on env.APP / bundleIdentifier to restrict it).
--
-- REVERT (if #708 is ever fixed natively): comment the "media-control path"
-- block, uncomment the "native media_change path" block, and set the cover
-- image scale back to 0.80. (Popup buttons call `media-control`; switch them to
-- `nowplaying-cli` only if you also drop media-control.)

local media_cover = sbar.add("item", {
	position = "right",
	background = {
		image = {
			-- media-control path: ~100px file from media_stream.sh, scale 0.30.
			-- native media_change path: built-in artwork, use scale = 0.80.
			string = "media.artwork",
			scale = 0.30,
		},
		color = colors.transparent,
	},
	label = { drawing = false },
	icon = { drawing = false },
	drawing = false,
	updates = true,
	popup = {
		align = "center",
		horizontal = true,
	},
})

local media_artist = sbar.add("item", {
	position = "right",
	drawing = false,
	padding_left = 3,
	padding_right = 0,
	width = 0,
	icon = { drawing = false },
	label = {
		width = 0,
		font = { size = 10 },
		color = colors.green,
		max_chars = 18,
		y_offset = 6,
	},
})

local media_title = sbar.add("item", {
	position = "right",
	drawing = false,
	padding_left = 3,
	padding_right = 0,
	icon = { drawing = false },
	label = {
		font = { size = 12 },
		width = 0,
		color = colors.green,
		max_chars = 16,
		y_offset = -5,
	},
})

sbar.add("item", {
	position = "popup." .. media_cover.name,
	icon = { string = icons.media.back },
	label = { drawing = false },
	click_script = "media-control previous-track",
})
sbar.add("item", {
	position = "popup." .. media_cover.name,
	icon = { string = icons.media.play_pause },
	label = { drawing = false },
	click_script = "media-control toggle-play-pause",
})
sbar.add("item", {
	position = "popup." .. media_cover.name,
	icon = { string = icons.media.forward },
	label = { drawing = false },
	click_script = "media-control next-track",
})

local interrupt = 0
local function animate_detail(detail)
	if not detail then
		interrupt = interrupt - 1
	end
	if interrupt > 0 and not detail then
		return
	end

	sbar.animate("tanh", 30, function()
		media_artist:set({ label = { width = detail and "dynamic" or 0 } })
		media_title:set({ label = { width = detail and "dynamic" or 0 } })
	end)
end

-- === media-control path (ACTIVE) ===========================================
-- Now-playing changes arrive as a custom `media_update` event, triggered by
-- helpers/media_stream.sh (media-control stream). Comment this whole block to
-- fall back to the native path below.
sbar.add("event", "media_update")

local art_path = nil
media_cover:subscribe("media_update", function(env)
	local drawing = (env.PLAYING == "true")
	if env.ART and env.ART ~= "" then
		art_path = env.ART
	end

	media_artist:set({ drawing = drawing, label = env.ARTIST or "" })
	media_title:set({ drawing = drawing, label = env.TITLE or "" })

	local cover = { drawing = drawing }
	if drawing and art_path then
		cover.background = { image = { string = art_path } }
	end
	media_cover:set(cover)

	if drawing then
		animate_detail(true)
		interrupt = interrupt + 1
		sbar.delay(5, animate_detail)
	else
		media_cover:set({ popup = { drawing = false } })
	end
end)

-- Launch the media-control stream provider that feeds the event above. The
-- helper self-replaces any prior instance via its pidfile (no broad pkill).
local home = os.getenv("HOME") or ("/Users/" .. os.getenv("USER"))
os.execute("(" .. home .. "/.config/sketchybar/helpers/media_stream.sh >/dev/null 2>&1 &)")
-- === end media-control path =================================================

-- === native media_change path (DISABLED — re-enable if SketchyBar #708 lands) ===
-- Uncomment this block AND comment the media-control path above; also set the
-- cover image scale back to 0.80. Needs no helper / media-control.
-- local whitelist = { ["Spotify"] = true, ["SoundCloud"] = true, ["Music"] = true }
-- media_cover:subscribe("media_change", function(env)
-- 	if whitelist[env.INFO.app] then
-- 		local drawing = (env.INFO.state == "playing")
-- 		media_artist:set({ drawing = drawing, label = env.INFO.artist })
-- 		media_title:set({ drawing = drawing, label = env.INFO.title })
-- 		media_cover:set({ drawing = drawing })
-- 		if drawing then
-- 			animate_detail(true)
-- 			interrupt = interrupt + 1
-- 			sbar.delay(5, animate_detail)
-- 		else
-- 			media_cover:set({ popup = { drawing = false } })
-- 		end
-- 	end
-- end)
-- === end native media_change path ===========================================

media_cover:subscribe("mouse.entered", function()
	interrupt = interrupt + 1
	animate_detail(true)
end)

media_cover:subscribe("mouse.exited", function()
	animate_detail(false)
end)

media_cover:subscribe("mouse.clicked", function()
	media_cover:set({ popup = { drawing = "toggle" } })
end)

media_title:subscribe("mouse.exited.global", function()
	media_cover:set({ popup = { drawing = false } })
end)
