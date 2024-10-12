local c = require('neodba.core')

local M = c

function M.setup()
  c.define_user_commands()
  c.set_default_keymaps()
end

return M
