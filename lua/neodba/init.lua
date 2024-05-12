local u = require('neodba.utils')
local uv = vim.loop

local M = {
  output_bufnr = nil, -- TODO: remove?
  output_winid = nil,
  output_file_path = 'db-result',
  process = {
    cmd = 'neodba',
    handle = nil,
    pid = 0,
    stderr = nil,
    stdin = nil,
    stdout = nil,
  }
}

function M.setup(config)
  u.pp('neodba setup', config)
  vim.keymap.set({'n', 'v'}, '<leader><leader>', function() M.exec_sql() end, {desc = 'Exec SQL'})
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
  vim.notify('neodba started (pid '.. pid .. ')')

  M.process.handle = handle
  M.process.pid = pid

  -- Read from stdout
  uv.read_start(M.process.stdout, function(err, data)
    assert(not err, err)
    if data then
      local trimmed_data = vim.trim(data)
      if #trimmed_data > 0 then
        u.write_file(M.output_file_path, data)
      end
    else
      print("stdout end")
    end
  end)

  -- Read from stderr
  uv.read_start(M.process.stderr, function(err, data)
    assert(not err, err)
    if data then
      vim.notify('SQL error', vim.log.levels.ERROR)
      local trimmed_data = vim.trim(data)
      if #trimmed_data > 0 then
        u.write_file(M.output_file_path, data)
      end
    else
      print("stderr end")
    end
  end)
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

local function get_selected_text_in_visual_char_mode()
  local start_pos = vim.fn.getpos('v') -- get visual mode position
  local end_pos = vim.fn.getpos('.') -- cursor position

  local start_line = start_pos[2] - 1
  local end_line = end_pos[2] - 1
  local start_col = start_pos[3] - 1
  local end_col = end_pos[3]

  local sel_lines = vim.api.nvim_buf_get_text(0, start_line, start_col, end_line, end_col, {})

  local sel_text_joined = vim.trim(table.concat(sel_lines, ' '))
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

  local sel_text_joined = vim.trim(table.concat(sel_lines, ' '))
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

local function show_output()
  if not M.output_bufnr then
    M.output_bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(M.output_bufnr, 'SQL Output')
    vim.api.nvim_buf_set_option(M.output_bufnr, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(M.output_bufnr, 'bufhidden', 'hide')
  end

  local output_win_open = M.output_winid and vim.tbl_contains(vim.api.nvim_list_wins(), M.output_winid)

  if not output_win_open then
    local curr_winid = vim.fn.win_getid()
    vim.cmd('rightbelow sb' .. M.output_bufnr)
    M.output_winid = vim.fn.win_getid()
    vim.fn.win_gotoid(curr_winid)
  end

  local lines = {}
  if (u.file_exists(M.output_file_path)) then
    lines = vim.fn.readfile(M.output_file_path)
    u.ltrim_blank_lines(lines)
  end

  vim.api.nvim_buf_set_lines(M.output_bufnr, 0, -1, false, lines)
end

function M.exec_sql(sql)
  if M.process.pid == 0 then
    M.start()
  end

  if not sql or #sql == 0 then
    sql = selected_text()
  end

  sql = vim.trim(sql)

  if sql and #sql > 0 then
    sql = sql .. '\n'

    vim.fn.delete(M.output_file_path)

    uv.write(
      M.process.stdin,
      sql,
      function(err)
        if err then
          print('stdin error:', err)
        end
      end)

    vim.cmd('sleep 250m')

    show_output()
  end
end

return M
