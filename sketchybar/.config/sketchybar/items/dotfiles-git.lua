local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

local git_repo = "~/dotfiles"
local git_base_cmd = "git -C " .. git_repo

local git_diff_cmd = git_base_cmd .. " diff-index --quiet HEAD --"
local git_sync_cmd = git_base_cmd
	.. ' fetch --quiet && [ "$('
	.. git_base_cmd
	.. ' rev-parse HEAD)" = "$('
	.. git_base_cmd
	.. ' rev-parse @{u})" ]'
local git_cmd = git_diff_cmd .. " && " .. git_sync_cmd
local git_status = "( "
	.. git_base_cmd
	.. " diff --name-status HEAD; "
	.. git_base_cmd
	.. ' diff --cached --name-status HEAD ) | \
awk \'{counts[$1]++} END { printf "{\\"A\\": %d, \\"M\\": %d, \\"D\\": %d}\\n", counts["A"]+0, counts["M"]+0, counts["D"]+0 }\''

local dotfiles_outofsync = sbar.add("item", "widgets.dotfiles_sync_icon", {
	drawing = false,
	position = "right",
	padding_right = 9,
	icon = {
		string = icons.git.git,
		width = 0,
		align = "left",
		color = colors.fg,
		font = {
			style = settings.font.style_map["Bold"],
			size = 18.0,
		},
	},
	label = {
		width = 18,
		align = "left",
		font = {
			style = settings.font.style_map["Regular"],
			size = 14.0,
		},
	},
	update_freq = 120,
	updates = true,
	popup = { align = "center", horizontal = true },
})

local git_add = sbar.add("item", {
	position = "popup." .. dotfiles_outofsync.name,
	drawing = false,
	icon = {
		string = icons.git.added,
		align = "left",
		color = colors.green,
		font = {
			style = settings.font.style_map["Regular"],
			size = 14.0,
		},
	},
	label = {
		padding_left = 5,
		string = "?",
		align = "right",
	},
	padding_left = 10,
	padding_right = 10,
})

local git_mod = sbar.add("item", {
	position = "popup." .. dotfiles_outofsync.name,
	drawing = false,
	icon = {
		string = icons.git.modified,
		align = "left",
		color = colors.orange,
		font = {
			style = settings.font.style_map["Regular"],
			size = 14.0,
		},
	},
	label = {
		padding_left = 5,
		string = "?",
		align = "right",
	},
	padding_left = 10,
	padding_right = 10,
})

local git_rem = sbar.add("item", {
	position = "popup." .. dotfiles_outofsync.name,
	drawing = false,
	icon = {
		string = icons.git.removed,
		align = "left",
		color = colors.red,
		font = {
			style = settings.font.style_map["Regular"],
			size = 14.0,
		},
	},
	label = {
		padding_left = 5,
		string = "?",
		align = "right",
	},
	padding_left = 10,
	padding_right = 10,
})

local sync_status = sbar.add("item", {
	position = "popup." .. dotfiles_outofsync.name,
	drawing = false,
	icon = {
		string = icons.git.fetch,
		align = "left",
		color = colors.blue,
		font = {
			style = settings.font.style_map["Regular"],
			size = 14.0,
		},
	},
	padding_left = 10,
	padding_right = 10,
})

local function updateGitStatus()
	sbar.exec(git_cmd, function(_, exit_code)
		local result = exit_code ~= 0
		dotfiles_outofsync:set({ drawing = result })
	end)
end

local function git_status_popup()
	local drawing = dotfiles_outofsync:query().popup.drawing
	dotfiles_outofsync:set({ popup = { drawing = "toggle" } })
	if drawing == "off" then
		sbar.exec(git_status, function(modifications)
			git_add:set({ label = modifications.A, drawing = modifications.A ~= 0 })
			git_mod:set({ label = modifications.M, drawing = modifications.M ~= 0 })
			git_rem:set({ label = modifications.D, drawing = modifications.D ~= 0 })
		end)
		sbar.exec(git_sync_cmd, function(_, exit_code)
			sync_status:set({ drawing = exit_code == 1 })
		end)
	end
end

local function git_collapse_details()
	local drawing = dotfiles_outofsync:query().popup.drawing == "on"
	if not drawing then
		return
	end
	dotfiles_outofsync:set({ popup = { drawing = false } })
end
dotfiles_outofsync:subscribe("mouse.clicked", git_status_popup)
dotfiles_outofsync:subscribe("mouse.exited.global", git_collapse_details)
dotfiles_outofsync:subscribe("mouse.entered", function()
	dotfiles_outofsync:set({ icon = { highlight = true } })
end)
dotfiles_outofsync:subscribe("mouse.exited", function()
	dotfiles_outofsync:set({ icon = { highlight = false } })
end)
dotfiles_outofsync:subscribe("routine", function()
	updateGitStatus()
end)

updateGitStatus()
