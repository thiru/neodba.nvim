local h = require('neodba.core.helpers')

local state = {
  output_bufnr = nil,
  output_winid = nil,
  sessions = {},
}

local M = {
  helpers = h,
  process = {
    cmd = 'neodba',
    cmd_args = {'repl'},
  },
  state = state,
}

function M.define_user_commands()
  vim.api.nvim_create_user_command(
    'NeodbaExecSql',
    M.exec_sql,
    {bang = true,
     desc = 'Execute SQL under cursor or what is visually selected'})

  vim.api.nvim_create_user_command(
    'NeodbaGetDatabaseInfo',
    function() M.get_db_metadata('(get-database-info)') end,
    {bang = true,
     desc = 'Get metadata about the database and the current connection to it'})

  vim.api.nvim_create_user_command(
    'NeodbaGetCatalogs',
    function() M.get_db_metadata('(get-catalogs)') end,
    {bang = true,
     desc = 'Get all catalogs'})

  vim.api.nvim_create_user_command(
    'NeodbaGetSchemas',
    function() M.get_db_metadata('(get-schemas)') end,
    {bang = true,
     desc = 'Get all schemas'})

  vim.api.nvim_create_user_command(
    'NeodbaGetTables',
    function() M.get_db_metadata('(get-tables)') end,
    {bang = true,
     desc = 'Get all tables'})

  vim.api.nvim_create_user_command(
    'NeodbaGetViews',
    function() M.get_db_metadata('(get-views)') end,
    {bang = true,
     desc = 'Get all views'})

  vim.api.nvim_create_user_command(
    'NeodbaGetColumnInfo',
    M.column_info,
    {bang = true,
     desc = 'Get column info for table under cursor or what is visually selected'})

  vim.api.nvim_create_user_command(
    'NeodbaGetFunctions',
    function() M.get_db_metadata('(get-functions)') end,
    {bang = true,
     desc = 'Get all functions'})

  vim.api.nvim_create_user_command(
    'NeodbaGetProcedures',
    function() M.get_db_metadata('(get-procedures)') end,
    {bang = true,
     desc = 'Get all procedures'})

  vim.api.nvim_create_user_command(
    'NeodbaStartProcess',
    M.start,
    {bang = true,
     desc = 'Start the neodba process'})

  vim.api.nvim_create_user_command(
    'NeodbaStopProcess',
    M.stop,
    {bang = true,
     desc = 'Stop the neodba process'})

  vim.api.nvim_create_user_command(
    'NeodbaRestartProcess',
    M.restart,
    {bang = true,
     desc = 'Restart the neodba process'})
end

function M.set_default_keymaps()
  vim.keymap.set({'n', 'v'}, '<C-CR>', '<CMD>NeodbaExecSql<CR>', {desc = 'Neodba - Execute SQL'})
  vim.keymap.set('i', '<C-CR>', '<C-O><CMD>NeodbaExecSql<CR>', {desc = 'Neodba - Execute SQL'})
  vim.keymap.set('n', '<localleader>dm', '<CMD>NeodbaGetDatabaseInfo<CR>', {desc = 'Neodba - Get database info'})
  vim.keymap.set({'n', 'v'}, '<localleader>dc', '<CMD>NeodbaGetColumnInfo<CR>', {desc = 'Neodba - Get column info'})
  vim.keymap.set({'n', 'v'}, '<localleader>ds', '<CMD>NeodbaGetSchemas<CR>', {desc = 'Neodba - Get all schemas'})
  vim.keymap.set({'n', 'v'}, '<localleader>dt', '<CMD>NeodbaGetTables<CR>', {desc = 'Neodba - Get all tables'})
  vim.keymap.set({'n', 'v'}, '<localleader>dv', '<CMD>NeodbaGetViews<CR>', {desc = 'Neodba - Get all views'})
  vim.keymap.set({'n', 'v'}, '<localleader>df', '<CMD>NeodbaGetFunctions<CR>', {desc = 'Neodba - Get all functions'})
end

function M.start()
  local session = h.new_session()

  vim.notify('Starting neodba...', vim.log.levels.DEBUG)

  -- Start process
  local handle, pid = vim.uv.spawn(
    M.process.cmd,
    { args = M.process.cmd_args,
      cwd = vim.fn.getcwd(),
      stdio = {session.process.stdin, session.process.stdout, session.process.stderr}},
    function (code, _)
      vim.notify('Neodba exited with error code: ' .. code, vim.log.levels.ERROR)
      session.process.alive = false
    end)

  vim.notify('Neodba started (pid '.. pid .. ')', vim.log.levels.DEBUG)

  session.process.handle = handle
  session.process.pid = pid

  state.sessions[session.dir] = session

  -- Read from stdout
  vim.uv.read_start(
    session.process.stdout,
    vim.schedule_wrap(
      function(err, data)
        assert(not err, err)
        if data then
          local trimmed_data = vim.trim(data)
          if #trimmed_data > 0 then
            h.show_output(state, data)
          end
        end
      end))

  -- Read from stderr
  vim.uv.read_start(
    session.process.stderr,
    vim.schedule_wrap(
      function(err, data)
        assert(not err, err)
        if data then
          vim.notify('SQL error', vim.log.levels.ERROR)
          local trimmed_data = vim.trim(data)
          if #trimmed_data > 0 then
            h.show_output(state, data)
          end
        end
      end))

  return session
end

function M.stop()
  local session = h.get_existing_session(state) or M.start()

  if not session.process.alive then
    return
  end

  vim.uv.shutdown(
    session.process.stdin,
    function()
      vim.uv.close(
        session.process.handle,
        function()
          session.process.alive = false
          vim.notify('Neodba process closed: (pid = ' .. session.process.pid .. ')', vim.log.levels.DEBUG)
        end)
    end)
end

function M.restart()
  M.stop()
  M.start()
end

function M.exec_sql(sql)
  local session = h.get_existing_session(state) or M.start()

  if not sql or #sql == 0 then
    sql = h.get_sql_to_exec()
  end

  sql = vim.trim(sql)

  if sql and #sql > 0 then
    sql = sql .. '\n'

    vim.uv.write(
      session.process.stdin,
      sql,
      function(err)
        if err then
          vim.notify('Neodba stdin error: ' .. err, vim.log.levels.ERROR)
        end
      end)
  end
end

function M.get_db_metadata(query)
  local session = h.get_existing_session(state) or M.start()

  local sql = query .. '\n'

  vim.uv.write(
    session.process.stdin,
    sql,
    function(err)
      if err then
        vim.notify('Neodba stdin error: ' .. err, vim.log.levels.ERROR)
      end
    end)
end

function M.column_info(table_name)
  if not table_name or #table_name == 0 then
    table_name = h.get_table_name()
  end

  table_name = vim.trim(table_name)

  if table_name and #table_name > 0 then
    local query = '(get-columns ' .. table_name .. ')\n'
    M.get_db_metadata(query)
  end
end

return M
