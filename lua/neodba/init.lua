local u = require('neodba.utils')
local uv = vim.loop

local M = {
  output_bufnr = nil,
  output_winid = nil,
  process = {
    cmd = 'neodba',
    handle = nil,
    pid = 0,
    stderr = nil,
    stdin = nil,
    stdout = nil,
  }
}

function M.setup()
  vim.api.nvim_create_user_command(
    'NeodbaExecSql',
    M.exec_sql,
    {bang = true,
     desc = 'Execute SQL under cursor or what is visually selected'})

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
  M.process.stdin = uv.new_pipe()
  M.process.stdout = uv.new_pipe()
  M.process.stderr = uv.new_pipe()

  vim.notify('Starting neodba...' .. M.process.cmd, vim.log.levels.INFO)

  -- Start process
  local handle, pid = uv.spawn(
    M.process.cmd,
    {stdio = {M.process.stdin, M.process.stdout, M.process.stderr}},
    function(code, signal) -- on exit (doesn't seem to be getting called)
      print("exit code", code)
      print("exit signal", signal)
    end)
  print('neodba started (pid '.. pid .. ')')

  M.process.handle = handle
  M.process.pid = pid

  -- Read from stdout
  uv.read_start(
    M.process.stdout,
    vim.schedule_wrap(
      function(err, data)
        assert(not err, err)
        if data then
          local trimmed_data = vim.trim(data)
          if #trimmed_data > 0 then
            M.show_output(data)
          end
        else
          print("stdout end")
        end
      end))

  -- Read from stderr
  uv.read_start(
    M.process.stderr,
    vim.schedule_wrap(
      function(err, data)
        assert(not err, err)
        if data then
          vim.notify('SQL error', vim.log.levels.ERROR)
          local trimmed_data = vim.trim(data)
          if #trimmed_data > 0 then
            M.show_output(data)
          end
        else
          print("stderr end")
        end
      end))
end

function M.stop()
  if M.process.pid == 0 then
    return
  end

  uv.shutdown(
    M.process.stdin,
    function()
      print("stdin shutdown")
      uv.close(
        M.process.handle,
        function()
          M.process.pid = 0
          print("process closed: " .. M.process.pid)
        end)
    end)
end

function M.restart()
  M.stop()
  M.start()
end

function M.show_output(data)
  if not M.output_bufnr then
    M.output_bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(M.output_bufnr, 'SQL Output')
    vim.api.nvim_buf_set_option(M.output_bufnr, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(M.output_bufnr, 'bufhidden', 'hide')
  end

  local output_win_open = M.output_winid and vim.tbl_contains(vim.api.nvim_list_wins(), M.output_winid)

  if not output_win_open then
    local curr_winid = vim.fn.win_getid()
    vim.cmd('rightbelow sb' .. M.output_bufnr) -- Any visual selection would get lost here
    vim.cmd('set nowrap')
    M.output_winid = vim.fn.win_getid()
    vim.fn.win_gotoid(curr_winid)
  end

  local lines = vim.split(data, '\n')
  u.ltrim_blank_lines(lines)
  u.append_to_buffer(M.output_bufnr, lines)
end

function M.get_sql_to_exec()
  local mode = vim.fn.mode()

  if mode == 'V' or mode == 'v' then
    return u.selected_text()
  end

  vim.cmd('normal vip')
  return u.selected_text()
end

function M.exec_sql(sql)
  if M.process.pid == 0 then
    M.start()
  end

  if not sql or #sql == 0 then
    sql = M.get_sql_to_exec()
  end

  sql = vim.trim(sql)

  if sql and #sql > 0 then
    sql = sql .. '\n'

    u.clear_buffer(M.output_bufnr)

    uv.write(
      M.process.stdin,
      sql,
      function(err)
        if err then
          print('stdin error:', err)
        end
      end)
  end
end

return M
