if vim.g.loaded_kappa then
	return
end
vim.g.loaded_kappa = true

vim.api.nvim_create_user_command("Kappa", function(opts)
	require("kappa").toggle(opts.args ~= "" and opts.args or nil)
end, { nargs = "?", desc = "Toggle Twitch chat sidebar (:Kappa <channel>)" })
