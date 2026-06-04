local scratchpad = require("nvim-scratchpad")

scratchpad.setup()

vim.api.nvim_create_user_command("ScratchpadOpen", function()
  scratchpad.open()
end, {})

vim.api.nvim_create_user_command("ScratchpadClose", function()
  scratchpad.close()
end, {})

vim.api.nvim_create_user_command("ScratchpadWrite", function()
  scratchpad.write()
end, {})
