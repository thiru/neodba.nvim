local M = {
  process = {
    cmd = 'neodba',
    handle = nil,
    pid = 0,
    stderr = nil,
    stdin = nil,
    stdout = nil,
  }
}

function M.pp(...)
  local objects = vim.tbl_map(vim.inspect, { ... })
  print(unpack(objects))
end

function M.setup(config)
  M.pp('neodba setup', config)
  vim.keymap.set({'n', 'v'}, '<leader><leader>', function() M.exec_sql() end, {desc = 'Exec SQL'})
end

function M.start()
  local uv = vim.loop

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
  vim.notify('neodba started (pid '.. pid .. ')')

  M.process.handle = handle
  M.process.pid = pid

  -- Read from stdout
  uv.read_start(M.process.stdout, function(err, data)
    assert(not err, err)
    if data then
      print(data)
    else
      print("stdout end")
    end
  end)

  -- Read from stderr
  uv.read_start(M.process.stderr, function(err, data)
    assert(not err, err)
    if data then
      vim.notify('SQL error', vim.log.levels.ERROR)
      print(data)
    else
      print("stderr end")
    end
  end)
end

function M.stop()
  if M.process.pid == 0 then
    return
  end

  vim.loop.shutdown(
    M.process.stdin,
    function()
      print("stdin shutdown")
      vim.loop.close(
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

local function get_selected_text_in_visual_char_mode()
  local start_pos = vim.fn.getpos('v') -- get visual mode position
  local end_pos = vim.fn.getpos('.') -- cursor position

  local start_line = start_pos[2] - 1
  local end_line = end_pos[2] - 1
  local start_col = start_pos[3] - 1
  local end_col = end_pos[3]

  local sel_lines = vim.api.nvim_buf_get_text(0, start_line, start_col, end_line, end_col, {})

  local sel_text_joined = table.concat(sel_lines, ' ')
  print(sel_text_joined .. '\n')
  vim.notify(sel_text_joined, vim.log.levels.INFO)

  return sel_text_joined
end

local function get_selected_text_in_visual_line_mode()
  -- NOTE: we need to escape visual mode as the '< and '> marks apply to the *last* visual mode selection
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), 'x', true)

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = math.max(0, start_pos[2] - 1)
  local end_line = end_pos[2]
  local sel_lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)

  local sel_text_joined = table.concat(sel_lines, ' ')
  print(sel_text_joined .. '\n')
  vim.notify(sel_text_joined, vim.log.levels.INFO)

  return sel_text_joined
end

local function selected_text()
  local mode = vim.fn.mode() -- used to distinguish visual block/line mode

  if mode == 'V' then
    return get_selected_text_in_visual_line_mode()
  else
    return get_selected_text_in_visual_char_mode()
  end
end

function M.exec_sql(sql)
  if M.process.pid == 0 then
    M.start()
  end

  if not sql or #sql == 0 then
    sql = selected_text() .. '\n'
  end

  vim.loop.write(
    M.process.stdin,
    sql,
    function(err)
      if err then
        print('stdin error:', err)
      end
    end)
end

return M
