local u = require('neodba.utils')

local state = {
  output_bufnr = nil,
  output_winid = nil,
  sessions = {},
}

local M = {
  cmds = {
    get_database_info = '(get-database-info)',
    get_catalogs = '(get-catalogs)',
    get_schemas = '(get-schemas)',
    get_tables = '(get-tables)',
    get_views = '(get-views)',
    get_functions = '(get-functions)',
    get_procedures = '(get-procedures)'
  },
  telescope_cmds = {
    get_functions = '(get-functions plain)',
    get_procedures = '(get-procedures plain)',
    get_tables = '(get-tables plain)',
    get_views = '(get-views plain)',
  },
  process = {
    cmd = 'neodba',
    cmd_args = {'repl'},
  },
  state = state,
}

function M.load_telescope()
  M.telescope = {
    loaded = true,
    action_state = require('telescope.actions.state'),
    actions = require('telescope.actions'),
    conf = require('telescope.config').values,
    finders = require('telescope.finders'),
    pickers = require('telescope.pickers')
  }
end

function M.new_session()
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

function M.get_existing_session()
  local session = state.sessions[vim.fn.getcwd()]
  if session and session.process.alive then
    return session
  end
  return nil
end

function M.start()
  local session = M.new_session()

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
            M.show_output(data)
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
            M.show_output(data)
          end
        end
      end))

  return session
end

function M.stop()
  local session = M.get_existing_session() or M.start()

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
  local session = M.get_existing_session() or M.start()

  if not sql or #sql == 0 then
    sql = M.get_sql_to_exec()
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
  local session = M.get_existing_session() or M.start()

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
    table_name = M.get_word_under_cursor()
  end

  table_name = vim.trim(table_name)

  if table_name and #table_name > 0 then
    local query = '(get-columns ' .. table_name .. ')\n'
    M.get_db_metadata(query)
  end
end

function M.view_defn(view_name)
  if not view_name or #view_name == 0 then
    view_name = M.get_word_under_cursor()
  end

  view_name = vim.trim(view_name)

  if view_name and #view_name > 0 then
    local query = '(get-view-defn ' .. view_name .. ')\n'
    M.get_db_metadata(query)
  end
end

function M.function_defn(func_name)
  if not func_name or #func_name == 0 then
    func_name = M.get_word_under_cursor()
  end

  func_name = vim.trim(func_name)

  if func_name and #func_name > 0 then
    local query = '(get-function-defn ' .. func_name .. ')\n'
    M.get_db_metadata(query)
  end
end

function M.procedure_defn(proc_name)
  if not proc_name or #proc_name == 0 then
    proc_name = M.get_word_under_cursor()
  end

  proc_name = vim.trim(proc_name)

  if proc_name and #proc_name > 0 then
    local query = '(get-procedure-defn ' .. proc_name .. ')\n'
    M.get_db_metadata(query)
  end
end

-- TODO: remove this or support via user-defined option
function M.show_output_from_data(data)
  if not state.output_bufnr then
    state.output_bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(state.output_bufnr, 'sql-output.md')
    vim.api.nvim_set_option_value('bufhidden', 'hide', {buf = state.output_bufnr})
  end

  local output_win_open = state.output_winid and vim.tbl_contains(vim.api.nvim_list_wins(), state.output_winid)

  if not output_win_open then
    local curr_winid = vim.fn.win_getid()
    vim.cmd('rightbelow sb' .. state.output_bufnr) -- Any visual selection would get lost here
    vim.cmd('set nowrap')
    u.resize_height(40)
    state.output_winid = vim.fn.win_getid()
    vim.fn.win_gotoid(curr_winid)
  end

  local lines = vim.split(data, '\n')
  u.ltrim_blank_lines(lines)
  u.clear_buffer(state.output_bufnr)
  u.append_to_buffer(state.output_bufnr, lines)
  vim.api.nvim_buf_call(state.output_bufnr, function()
    vim.cmd('silent! write!')
    vim.cmd('edit!') -- NOTE: reloading to trigger Markdown plugin render
  end)
end

function M.show_ouput_in_split()
  if not state.output_bufnr then
    state.output_bufnr = vim.fn.bufadd('sql-output.md')
  end

  local output_win_open = state.output_winid and vim.tbl_contains(vim.api.nvim_list_wins(), state.output_winid)

  if not output_win_open then
    state.output_winid = vim.api.nvim_open_win(state.output_bufnr, false, {split='below'})
    vim.api.nvim_set_option_value('wrap', false, {win=state.output_winid})
  end

  if vim.api.nvim_buf_is_valid(state.output_bufnr) then
    vim.api.nvim_buf_call(state.output_bufnr, function()
      vim.cmd('edit!')
      vim.api.nvim_set_option_value('buflisted', false, {buf = state.output_bufnr})
    end)
  else
    vim.notify('Neodba: Failed to show SQL result (buffer is invalid: ' .. state.output_bufnr .. ')', vim.log.levels.ERROR)
  end
end

function M.show_output_in_telescope(opts)
  opts = opts or {}

  if M.telescope == nil and (not pcall(M.load_telescope)) then
    error("Telescope is required for Neodba's picker")
  end

  M.telescope.pickers.new(opts, {
    prompt_title = 'Neodba Picker',
    finder = M.telescope.finders.new_table({
      results = opts.results
    }),
    sorter = M.telescope.conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, _)
      -- Open in the current buffer
      M.telescope.actions.select_default:replace(function()
        M.telescope.actions.close(prompt_bufnr)
        opts.handle_action()
      end)
      return true
    end,
  }):find()
end

function M.show_output_from_file(data)
  local lines = vim.split(vim.trim(data), '\n')

  if #lines == 0 then
    return
  end

  local last_line = lines[#lines]

  -- Skipping last 2 lines since they are essentially metadata
  local telescope_data = vim.list_slice(lines, 1, (#lines - 2))
  local telescope_action = nil

  if last_line == M.telescope_cmds.get_functions then
    telescope_action = M.function_defn
  elseif last_line == M.telescope_cmds.get_procedures then
    telescope_action = M.procedure_defn
  elseif last_line == M.telescope_cmds.get_tables then
    telescope_action = function(table_name)
      M.exec_sql('SELECT * FROM ' .. table_name)
    end
  elseif last_line == M.telescope_cmds.get_views then
    telescope_action = function(view_name)
      M.exec_sql('SELECT * FROM ' .. view_name)
    end
  else
    M.show_ouput_in_split()
  end

  if telescope_action ~= nil then
    M.show_output_in_telescope({
      results = telescope_data,
      handle_action = function()
        local selection = M.telescope.action_state.get_selected_entry()
        if selection ~= nil then
          telescope_action(selection[1])
        end
      end
    })
  end
end

function M.show_output(data)
  local load_from_file = true

  if load_from_file then
    M.show_output_from_file(data)
  else
    M.show_output_from_data(data)
  end
end

function M.get_sql_to_exec()
  local mode = vim.fn.mode()

  if mode == 'V' or mode == 'v' then
    return u.selected_text()
  end

  local orig_cur_pos = vim.fn.getpos('.')

  vim.cmd('normal vip')
  return u.selected_text(orig_cur_pos)
end

function M.get_word_under_cursor()
  local mode = vim.fn.mode()

  if mode == 'V' or mode == 'v' then
    return u.selected_text()
  end

  local orig_cur_pos = vim.fn.getpos('.')

  vim.cmd('normal viw')
  return u.selected_text(orig_cur_pos)
end

return M
