local c = require('neodba.core')

local M = {
  core = c,
}

function M.setup(opts)
  c.state.opts = opts or {}
  M.define_autocmds()
  M.define_user_commands()
  M.set_default_keymaps()
end

function M.define_autocmds()
  local group = vim.api.nvim_create_augroup('neodba_keybinds', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'sql',
    callback = function()
      vim.keymap.set({ 'n', 'v' }, '<CR>', c.exec_sql, { buffer = true, desc = 'Neodba - Execute SQL' })
    end,
  })
end

function M.define_user_commands()
  vim.api.nvim_create_user_command('NeodbaConnect', function()
    c.connect()
  end, { desc = 'Connect to PostgreSQL' })

  vim.api.nvim_create_user_command('NeodbaDisconnect', function()
    c.disconnect()
  end, { desc = 'Disconnect from PostgreSQL' })

  vim.api.nvim_create_user_command('NeodbaExecSql', function(cmd)
    if cmd.range > 0 then
      local lines = vim.api.nvim_buf_get_lines(0, cmd.line1 - 1, cmd.line2, false)
      c.exec_sql(table.concat(lines, '\n'))
    else
      c.exec_sql(cmd.args)
    end
  end, {
    range = true,
    nargs = '?',
    desc = 'Execute SQL: argument, range, visual selection, or paragraph under cursor',
  })

  vim.api.nvim_create_user_command('NeodbaExecBuffer', function()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    c.exec_sql(table.concat(lines, '\n'))
  end, { desc = 'Execute the entire buffer as SQL' })
end

function M.set_default_keymaps()
  vim.keymap.set('i', '<C-CR>', '<C-O><CMD>NeodbaExecSql<CR>', { desc = 'Neodba - Execute SQL' })
end

return M
