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

-- TODO: remove this or support via user-defined option
function M.show_output_from_data(state, data)
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

function M.show_output_from_file(state)
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
    end)
  else
    vim.notify('Neodba: Failed to show SQL result (buffer is invalid: ' .. state.output_bufnr .. ')', vim.log.levels.ERROR)
  end
end

function M.show_output(state, data)
  local load_from_file = true

  if load_from_file then
    M.show_output_from_file(state)
  else
    M.show_output_from_data(state, data)
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
