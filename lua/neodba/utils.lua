local M = {}

function M.pp(...)
  local objects = vim.tbl_map(vim.inspect, { ... })
  print(unpack(objects))
end

function M.ltrim_blank_lines(lines)
  if lines and #lines > 0 then
    local idx = 1
    local line = lines[1]
    while vim.trim(line) == '' do
      table.remove(lines, idx)
      line = lines[idx]
    end
  end
end

function M.file_exists(path)
  return vim.loop.fs_stat(path)
end

function M.ensure_exists(path)
  if not M.file_exists(path) then
    vim.fn.mkdir(path)
  end
end

function M.write_file(path, data)
  local fd = vim.loop.fs_open(path, 'a', 438) -- TODO: what is 438
  if fd then
    vim.loop.fs_write(fd, data, 0)
    vim.loop.fs_close(fd)
  else
    vim.notify('Failed to write to: ' .. path, vim.log.levels.ERROR)
  end
end

function M.selected_text_in_visual_char_mode()
  local start_pos = vim.fn.getpos('v') -- get visual mode position
  local end_pos = vim.fn.getpos('.') -- cursor position

  local start_line = start_pos[2] - 1
  local end_line = end_pos[2] - 1
  local start_col = start_pos[3] - 1
  local end_col = end_pos[3]

  local sel_lines = vim.api.nvim_buf_get_text(0, start_line, start_col, end_line, end_col, {})

  local sel_text_joined = vim.trim(table.concat(sel_lines, ' '))
  print(sel_text_joined .. '\n')

  return sel_text_joined
end

function M.selected_text_in_visual_line_mode()
  -- NOTE: we need to escape visual mode as the '< and '> marks apply to the *last* visual mode selection
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), 'x', true)
  vim.cmd('normal gv')

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = math.max(0, start_pos[2] - 1)
  local end_line = end_pos[2]
  local sel_lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)

  local sel_text_joined = vim.trim(table.concat(sel_lines, ' '))
  print(sel_text_joined .. '\n')

  return sel_text_joined
end

function M.selected_text()
  local mode = vim.fn.mode()

  if mode == 'V' then
    return M.selected_text_in_visual_line_mode()
  else
    return M.selected_text_in_visual_char_mode()
  end
end

return M
