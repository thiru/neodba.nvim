local u = require('neodba.utils')

local helpers = {}
local state = {
  output_bufnr = nil,
  output_winid = nil,
  sessions = {},
}

local M = {
  helpers = helpers,
  process = {
    cmd = 'neodba',
    cmd_args = {'repl'},
  },
  state = state,
}

function M.setup()
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

function M.start()
  local session = helpers.new_session()

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
            helpers.show_output(data)
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
            helpers.show_output(data)
          end
        end
      end))

  return session
end

function M.stop()
  local session = helpers.get_or_start_new_session()

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

function helpers.new_session()
  return {
    dir = vim.fn.getcwd(),
    process = {
      alive = true,
      handle = nil,
      pid = 0,
      stderr = vim.uv.new_pipe(),
      stdin = vim.uv.new_pipe(),
      stdout = vim.uv.new_pipe(),
    },
  }
end

function helpers.get_or_start_new_session()
  local session = state.sessions[vim.fn.getcwd()]
  if session and session.process.alive then
    return session
  end
  return M.start()
end

function helpers.show_output(data)
  if not state.output_bufnr then
    state.output_bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(state.output_bufnr, 'SQL Output')
    vim.api.nvim_set_option_value('buftype', 'nofile', {buf = state.output_bufnr})
    vim.api.nvim_set_option_value('bufhidden', 'hide', {buf = state.output_bufnr})
  end

  local output_win_open = state.output_winid and vim.tbl_contains(vim.api.nvim_list_wins(), state.output_winid)

  if not output_win_open then
    local curr_winid = vim.fn.win_getid()
    vim.cmd('rightbelow sb' .. state.output_bufnr) -- Any visual selection would get lost here
    vim.cmd('set nowrap')
    state.output_winid = vim.fn.win_getid()
    vim.fn.win_gotoid(curr_winid)
  end

  local lines = vim.split(data, '\n')
  u.ltrim_blank_lines(lines)
  u.append_to_buffer(state.output_bufnr, lines)
end

function helpers.get_sql_to_exec()
  local mode = vim.fn.mode()

  if mode == 'V' or mode == 'v' then
    return u.selected_text()
  end

  local orig_cur_pos = vim.fn.getpos('.')

  vim.cmd('normal vip')
  return u.selected_text(orig_cur_pos)
end

function helpers.get_table_name()
  local mode = vim.fn.mode()

  if mode == 'V' or mode == 'v' then
    return u.selected_text()
  end

  local orig_cur_pos = vim.fn.getpos('.')

  vim.cmd('normal viw')
  return u.selected_text(orig_cur_pos)
end

function M.exec_sql(sql)
  local session = helpers.get_or_start_new_session()

  if not sql or #sql == 0 then
    sql = helpers.get_sql_to_exec()
  end

  sql = vim.trim(sql)

  if sql and #sql > 0 then
    sql = sql .. '\n'

    u.clear_buffer(state.output_bufnr)

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
  local session = helpers.get_or_start_new_session()

  local sql = query .. '\n'

  u.clear_buffer(state.output_bufnr)

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
    table_name = helpers.get_table_name()
  end

  table_name = vim.trim(table_name)

  if table_name and #table_name > 0 then
    local query = '(get-columns ' .. table_name .. ')\n'
    M.get_db_metadata(query)
  end
end

return M
