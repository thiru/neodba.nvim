local h = require('neodba.core.helpers')

local M = {
  helpers = h,
}

function M.define_user_commands()
  vim.api.nvim_create_user_command(
    'NeodbaExecSql',
    h.exec_sql,
    {bang = true,
     desc = 'Execute SQL under cursor or what is visually selected'})

  vim.api.nvim_create_user_command(
    'NeodbaGetDatabaseInfo',
    function() h.get_db_metadata(h.cmds.get_database_info) end,
    {bang = true,
     desc = 'Get metadata about the database and the current connection to it'})

  vim.api.nvim_create_user_command(
    'NeodbaGetCatalogs',
    function() h.get_db_metadata(h.cmds.get_catalogs) end,
    {bang = true,
     desc = 'Get all catalogs'})

  vim.api.nvim_create_user_command(
    'NeodbaGetSchemas',
    function() h.get_db_metadata(h.cmds.get_schemas) end,
    {bang = true,
     desc = 'Get all schemas'})

  vim.api.nvim_create_user_command(
    'NeodbaGetTables',
    function() h.get_db_metadata(h.cmds.get_tables) end,
    {bang = true,
     desc = 'Get all tables'})

  vim.api.nvim_create_user_command(
    'NeodbaFindTables',
    function() h.get_db_metadata(h.telescope_cmds.get_tables) end,
    {bang = true,
     desc = 'Find table to show all records'})

  vim.api.nvim_create_user_command(
    'NeodbaGetViews',
    function() h.get_db_metadata(h.cmds.get_views) end,
    {bang = true,
     desc = 'Get all views'})

  vim.api.nvim_create_user_command(
    'NeodbaFindViewDefinition',
    function() h.get_db_metadata(h.telescope_cmds.get_views) end,
    {bang = true,
     desc = 'Find definition of view'})

  vim.api.nvim_create_user_command(
    'NeodbaGetViewDefinition',
    h.view_defn,
    {bang = true,
     desc = 'Get definition of view under cursor or what is visually selected'})

  vim.api.nvim_create_user_command(
    'NeodbaGetColumnInfo',
    h.column_info,
    {bang = true,
     desc = 'Get column info for table under cursor or what is visually selected'})

  vim.api.nvim_create_user_command(
    'NeodbaGetFunctions',
    function() h.get_db_metadata(h.cmds.get_functions) end,
    {bang = true,
     desc = 'Get all functions'})

  vim.api.nvim_create_user_command(
    'NeodbaFindFunctions',
    function() h.get_db_metadata(h.telescope_cmds.get_functions) end,
    {bang = true,
     desc = 'Find definition of function'})

  vim.api.nvim_create_user_command(
    'NeodbaGetFunctionDefinition',
    h.function_defn,
    {bang = true,
     desc = 'Get definition of function under cursor or what is visually selected'})

  vim.api.nvim_create_user_command(
    'NeodbaGetProcedures',
    function() h.get_db_metadata(h.cmds.get_procedures) end,
    {bang = true,
     desc = 'Get all procedures'})

  vim.api.nvim_create_user_command(
    'NeodbaFindProcedures',
    function() h.get_db_metadata(h.telescope_cmds.get_procedures) end,
    {bang = true,
     desc = 'Find definition of procedure'})

  vim.api.nvim_create_user_command(
    'NeodbaGetProcedureDefinition',
    h.procedure_defn,
    {bang = true,
     desc = 'Get definition of procedure under cursor or what is visually selected'})

  vim.api.nvim_create_user_command(
    'NeodbaStartProcess',
    h.start,
    {bang = true,
     desc = 'Start the neodba process'})

  vim.api.nvim_create_user_command(
    'NeodbaStopProcess',
    h.stop,
    {bang = true,
     desc = 'Stop the neodba process'})

  vim.api.nvim_create_user_command(
    'NeodbaRestartProcess',
    h.restart,
    {bang = true,
     desc = 'Restart the neodba process'})
end

function M.set_default_keymaps()
  vim.keymap.set({'n', 'v'}, '<C-CR>', '<CMD>NeodbaExecSql<CR>', {desc = 'Neodba - Execute SQL'})
  vim.keymap.set('i', '<C-CR>', '<C-O><CMD>NeodbaExecSql<CR>', {desc = 'Neodba - Execute SQL'})
  vim.keymap.set('n', '<localleader>dm', '<CMD>NeodbaGetDatabaseInfo<CR>', {desc = 'Neodba - Get database info'})
  vim.keymap.set({'n', 'v'}, '<localleader>dc', '<CMD>NeodbaGetColumnInfo<CR>', {desc = 'Neodba - Get column info'})
  vim.keymap.set({'n', 'v'}, '<localleader>ds', '<CMD>NeodbaGetSchemas<CR>', {desc = 'Neodba - Get all schemas'})
  vim.keymap.set({'n', 'v'}, '<localleader>dtt', '<CMD>NeodbaFindTables<CR>', {desc = 'Neodba - Find table to show all records'})
  vim.keymap.set({'n', 'v'}, '<localleader>dtl', '<CMD>NeodbaGetTables<CR>', {desc = 'Neodba - Get all tables'})
  vim.keymap.set({'n', 'v'}, '<localleader>dvv', '<CMD>NeodbaFindViewDefinition<CR>', {desc = 'Neodba - Find definition of view'})
  vim.keymap.set({'n', 'v'}, '<localleader>dvl', '<CMD>NeodbaGetViews<CR>', {desc = 'Neodba - Get all views'})
  vim.keymap.set({'n', 'v'}, '<localleader>dvd', '<CMD>NeodbaGetViewDefinition<CR>', {desc = 'Neodba - Get current view definition'})
  vim.keymap.set({'n', 'v'}, '<localleader>dff', '<CMD>NeodbaFindFunctions<CR>', {desc = 'Neodba - Find definition of function'})
  vim.keymap.set({'n', 'v'}, '<localleader>dfl', '<CMD>NeodbaGetFunctions<CR>', {desc = 'Neodba - Get all functions'})
  vim.keymap.set({'n', 'v'}, '<localleader>dfd', '<CMD>NeodbaGetFunctionDefinition<CR>', {desc = 'Neodba - Get current function defintion'})
  vim.keymap.set({'n', 'v'}, '<localleader>dpp', '<CMD>NeodbaFindProcedures<CR>', {desc = 'Neodba - Get all procedures'})
  vim.keymap.set({'n', 'v'}, '<localleader>dpl', '<CMD>NeodbaGetProcedures<CR>', {desc = 'Neodba - Find definition of procedure'})
  vim.keymap.set({'n', 'v'}, '<localleader>dpd', '<CMD>NeodbaGetProcedureDefinition<CR>', {desc = 'Neodba - Get current procedure definition'})
end

return M
