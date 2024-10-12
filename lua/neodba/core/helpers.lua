local u = require('neodba.utils')

local M = {}

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

function M.get_existing_session(state)
  local session = state.sessions[vim.fn.getcwd()]
  if session and session.process.alive then
    return session
  end
  return nil
end

function M.show_output(state, data)
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
    u.resize_height(40)
    state.output_winid = vim.fn.win_getid()
    vim.fn.win_gotoid(curr_winid)
  end

  local lines = vim.split(data, '\n')
  u.ltrim_blank_lines(lines)
  u.append_to_buffer(state.output_bufnr, lines)
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

function M.get_table_name()
  local mode = vim.fn.mode()

  if mode == 'V' or mode == 'v' then
    return u.selected_text()
  end

  local orig_cur_pos = vim.fn.getpos('.')

  vim.cmd('normal viw')
  return u.selected_text(orig_cur_pos)
end

return M
