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
    'NeodbaShowDatabaseInfo',
    function() h.get_db_metadata(h.cmds.get_database_info) end,
    {bang = true,
     desc = 'Show metadata about the database and the current connection to it'})

  vim.api.nvim_create_user_command(
    'NeodbaShowCatalogs',
    function() h.get_db_metadata(h.cmds.get_catalogs) end,
    {bang = true,
     desc = 'Show all catalogs'})

  vim.api.nvim_create_user_command(
    'NeodbaShowSchemas',
    function() h.get_db_metadata(h.cmds.get_schemas) end,
    {bang = true,
     desc = 'Show all schemas'})

  vim.api.nvim_create_user_command(
    'NeodbaShowTables',
    function() h.get_db_metadata(h.cmds.get_tables) end,
    {bang = true,
     desc = 'Show all tables'})

  vim.api.nvim_create_user_command(
    'NeodbaSearchTables',
    function() h.get_db_metadata(h.telescope_cmds.get_tables) end,
    {bang = true,
     desc = 'Search tables in Telescope'})

  vim.api.nvim_create_user_command(
    'NeodbaShowViews',
    function() h.get_db_metadata(h.cmds.get_views) end,
    {bang = true,
     desc = 'Show all views'})

  vim.api.nvim_create_user_command(
    'NeodbaSearchViewDefinition',
    function() h.get_db_metadata(h.telescope_cmds.get_views) end,
    {bang = true,
     desc = 'Search views in Telescope'})

  vim.api.nvim_create_user_command(
    'NeodbaShowViewDefinition',
    h.view_defn,
    {bang = true,
     desc = 'Show definition of view under cursor or what is visually selected'})

  vim.api.nvim_create_user_command(
    'NeodbaShowColumnInfo',
    h.column_info,
    {bang = true,
     desc = 'Show column info for table under cursor or what is visually selected'})

  vim.api.nvim_create_user_command(
    'NeodbaShowFunctions',
    function() h.get_db_metadata(h.cmds.get_functions) end,
    {bang = true,
     desc = 'Show all functions'})

  vim.api.nvim_create_user_command(
    'NeodbaSearchFunctions',
    function() h.get_db_metadata(h.telescope_cmds.get_functions) end,
    {bang = true,
     desc = 'Search functions in Telescope'})

  vim.api.nvim_create_user_command(
    'NeodbaShowFunctionDefinition',
    h.function_defn,
    {bang = true,
     desc = 'Show definition of function under cursor or what is visually selected'})

  vim.api.nvim_create_user_command(
    'NeodbaShowProcedures',
    function() h.get_db_metadata(h.cmds.get_procedures) end,
    {bang = true,
     desc = 'Show all procedures'})

  vim.api.nvim_create_user_command(
    'NeodbaSearchProcedures',
    function() h.get_db_metadata(h.telescope_cmds.get_procedures) end,
    {bang = true,
     desc = 'Search stored procedures in Telescope'})

  vim.api.nvim_create_user_command(
    'NeodbaShowProcedureDefinition',
    h.procedure_defn,
    {bang = true,
     desc = 'Show definition of procedure under cursor or what is visually selected'})

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
  vim.keymap.set('n', '<localleader>dm', '<CMD>NeodbaShowDatabaseInfo<CR>', {desc = 'Neodba - Show database info'})
  vim.keymap.set({'n', 'v'}, '<localleader>dc', '<CMD>NeodbaShowColumnInfo<CR>', {desc = 'Neodba - Show column info'})
  vim.keymap.set({'n', 'v'}, '<localleader>ds', '<CMD>NeodbaShowSchemas<CR>', {desc = 'Neodba - Show all schemas'})
  vim.keymap.set({'n', 'v'}, '<localleader>dt', '<CMD>NeodbaSearchTables<CR>', {desc = 'Neodba - Search tables in Telescope'})
  vim.keymap.set({'n', 'v'}, '<localleader>dT', '<CMD>NeodbaShowTables<CR>', {desc = 'Neodba - Show all tables'})
  vim.keymap.set({'n', 'v'}, '<localleader>dv', '<CMD>NeodbaSearchViewDefinition<CR>', {desc = 'Neodba - Search views in Telescope'})
  vim.keymap.set({'n', 'v'}, '<localleader>dV', '<CMD>NeodbaShowViews<CR>', {desc = 'Neodba - Show all views'})
  vim.keymap.set({'n', 'v'}, '<localleader>ddv', '<CMD>NeodbaShowViewDefinition<CR>', {desc = 'Neodba - Show current view definition'})
  vim.keymap.set({'n', 'v'}, '<localleader>df', '<CMD>NeodbaSearchFunctions<CR>', {desc = 'Neodba - Search functions in Telescope'})
  vim.keymap.set({'n', 'v'}, '<localleader>dF', '<CMD>NeodbaShowFunctions<CR>', {desc = 'Neodba - Show all functions'})
  vim.keymap.set({'n', 'v'}, '<localleader>ddf', '<CMD>NeodbaShowFunctionDefinition<CR>', {desc = 'Neodba - Show current function defintion'})
  vim.keymap.set({'n', 'v'}, '<localleader>dp', '<CMD>NeodbaSearchProcedures<CR>', {desc = 'Neodba - Search stored procedures in Telescope'})
  vim.keymap.set({'n', 'v'}, '<localleader>dP', '<CMD>NeodbaShowProcedures<CR>', {desc = 'Neodba - Show definition of procedure'})
  vim.keymap.set({'n', 'v'}, '<localleader>ddp', '<CMD>NeodbaShowProcedureDefinition<CR>', {desc = 'Neodba - Show current procedure definition'})
end

return M
