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

function M.clear_buffer(bufnr)
  if bufnr then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  end
end

function M.append_to_buffer(bufnr, lines)
  if bufnr then
    vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, lines)
  end
end

function M.selected_text_in_visual_char_mode(cur_pos_to_restore)
  local orig_cur_pos = cur_pos_to_restore or vim.fn.getpos('.')

  -- We need to escape visual mode as the '< and '> marks apply to the *last* visual mode selection
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), 'x', true)

  vim.fn.setpos('.', orig_cur_pos)

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = start_pos[2] - 1
  local end_line = end_pos[2] - 1
  local start_col = start_pos[3] - 1
  local end_col = end_pos[3]

  local sel_lines = vim.api.nvim_buf_get_text(0, start_line, start_col, end_line, end_col, {})

  local sel_text_joined = vim.trim(table.concat(sel_lines, ' '))

  return sel_text_joined
end

function M.selected_text_in_visual_line_mode(cur_pos_to_restore)
  local orig_cur_pos = cur_pos_to_restore or vim.fn.getpos('.')

  -- We need to escape visual mode as the '< and '> marks apply to the *last* visual mode selection
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), 'x', true)

  vim.fn.setpos('.', orig_cur_pos)

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = math.max(0, start_pos[2] - 1)
  local end_line = end_pos[2]
  local sel_lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)

  local sel_text_joined = vim.trim(table.concat(sel_lines, ' '))

  return sel_text_joined
end

function M.selected_text(cur_pos_to_restore)
  local mode = vim.fn.mode()

  if mode == 'V' then
    return M.selected_text_in_visual_line_mode(cur_pos_to_restore)
  else
    return M.selected_text_in_visual_char_mode(cur_pos_to_restore)
  end
end

local function urldecode(s)
  return s and (s:gsub('%%(%x%x)', function(h)
    return string.char(tonumber(h, 16))
  end))
end

--- Parses a postgresql:// connection URL into a connection table.
--- postgresql://[user[:password]@][host][:port][/dbname]
function M.parse_pg_url(url)
  local rest = url:gsub('^postgres://', ''):gsub('^postgresql://', '')
  local conn = {}

  local userinfo, hostpart = rest:match('^([^@]+)@(.+)$')
  if not hostpart then
    hostpart = rest
  else
    conn.user, conn.password = userinfo:match('^([^:]+):?(.*)$')
    if conn.password == '' then
      conn.password = nil
    end
    conn.user = urldecode(conn.user)
    conn.password = urldecode(conn.password)
  end

  local hp, db = hostpart:match('^([^/]*)/?(.*)$')
  if db and db ~= '' then
    conn.database = urldecode(db:gsub('%?.*$', ''))
  end

  -- host, optional [ipv6] and optional :port
  local host, port = hp:match('^(%[[%x:]+%]):?(%d*)$')
  if host then
    conn.host = host:gsub('^%[', ''):gsub('%]$', '')
  else
    host, port = hp:match('^([^:]*):?(%d*)$')
    if host and host ~= '' then
      conn.host = host
    end
  end
  conn.port = tonumber(port)

  return conn
end

function M.resize_height(percentage)
  local total_height = vim.api.nvim_get_option_value("lines", {}) -
                       vim.api.nvim_get_option_value("cmdheight", {})
  local new_height = math.floor(total_height * (percentage / 100))
  vim.api.nvim_win_set_height(0, new_height)
end

return M
