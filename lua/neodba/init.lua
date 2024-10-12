local c = require('neodba.core')

local M = c

function M.setup()
  c.define_user_commands()
end

return M
