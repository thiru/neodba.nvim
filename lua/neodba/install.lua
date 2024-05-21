local u = require('neodba.utils')

local M = {}

function M.is_installed(cmd)
  return not u.is_empty(vim.fn.exepath(cmd))
end

function M.install()
  
end

return M
