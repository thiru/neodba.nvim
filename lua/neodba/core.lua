local u = require('neodba.utils')
local render = require('neodba.render')
local Client = require('neodba.pg.client')

local state = {
  opts = {},
  conn = nil,
  connecting = false,
  output_bufnr = nil,
  output_winid = nil,
}

local M = {
  state = state,
}

------------------------------------------------------------------------------
-- Connection management
------------------------------------------------------------------------------

local function resolve_connection_opts()
  local opts = state.opts or {}
  local conn = opts.connection or {}

  if opts.connection_string then
    conn = u.parse_pg_url(opts.connection_string)
  end

  return {
    host = conn.host or 'localhost',
    port = conn.port or 5432,
    user = conn.user or vim.env.USER,
    password = conn.password,
    database = conn.database or conn.user or vim.env.USER,
  }
end

--- Connects to PostgreSQL using the configured connection settings.
--- callback(err, conn) is optional.
function M.connect(callback)
  if state.conn and state.conn.state == 'ready' then
    if callback then
      callback(nil, state.conn)
    end
    return
  end

  if state.connecting then
    vim.notify('neodba: connection already in progress', vim.log.levels.WARN)
    return
  end

  local copts = resolve_connection_opts()
  state.connecting = true

  vim.notify(
    ('neodba: connecting to %s@%s:%s/%s...'):format(copts.user, copts.host, copts.port, copts.database),
    vim.log.levels.INFO
  )

  local conn = Client.new(copts)
  conn:connect(function(err)
    state.connecting = false
    if err then
      state.conn = nil
      vim.notify('neodba: ' .. (err.message or tostring(err)), vim.log.levels.ERROR)
      if callback then
        callback(err)
      end
      return
    end
    state.conn = conn
    vim.notify(
      ('neodba: connected to %s@%s:%s/%s'):format(copts.user, copts.host, copts.port, copts.database),
      vim.log.levels.INFO
    )
    if callback then
      callback(nil, conn)
    end
  end)
end

function M.disconnect()
  if state.conn then
    state.conn:disconnect()
    state.conn = nil
    vim.notify('neodba: disconnected', vim.log.levels.INFO)
  end
end

------------------------------------------------------------------------------
-- Query execution
------------------------------------------------------------------------------

--- Executes SQL. When `sql` is nil or empty, the SQL to run is taken from
--- the visual selection or the paragraph under the cursor.
function M.exec_sql(sql)
  if not sql or #sql == 0 then
    sql = M.get_sql_to_exec()
  end

  sql = vim.trim(sql)

  if #sql == 0 then
    return
  end

  local function run(conn)
    conn:query(sql, function(err, results, elapsed_ms)
      M.show_output(render.render(sql, results, err, elapsed_ms, state.opts.output))
    end)
  end

  if state.conn and state.conn.state == 'ready' then
    run(state.conn)
  else
    M.connect(function(err, conn)
      if not err then
        run(conn)
      end
    end)
  end
end

------------------------------------------------------------------------------
-- Output window
------------------------------------------------------------------------------

function M.show_output(lines)
  if type(lines) == 'string' then
    lines = vim.split(lines, '\n', { plain = true })
  end

  if not state.output_bufnr or not vim.api.nvim_buf_is_valid(state.output_bufnr) then
    state.output_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(state.output_bufnr, 'neodba-output')
    vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = state.output_bufnr })
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

  vim.api.nvim_buf_set_lines(state.output_bufnr, 0, -1, false, lines)
end

------------------------------------------------------------------------------
-- SQL extraction helpers
------------------------------------------------------------------------------

function M.get_sql_to_exec()
  local mode = vim.fn.mode()

  if mode == 'V' or mode == 'v' then
    return u.selected_text()
  end

  -- Get the current paragraph without entering visual mode,
  -- which would break the <C-O> one-shot-normal-mode mechanism.
  local cursor_line = vim.fn.line('.')
  local total_lines = vim.fn.line('$')

  -- Find start of paragraph (line after a blank line, or line 1)
  local start_line = 1
  for line = cursor_line - 1, 1, -1 do
    if vim.fn.getline(line):match('^%s*$') then
      start_line = line + 1
      break
    end
  end

  -- Find end of paragraph (line before a blank line, or last line)
  local end_line = total_lines
  for line = cursor_line + 1, total_lines do
    if vim.fn.getline(line):match('^%s*$') then
      end_line = line - 1
      break
    end
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local sql = vim.trim(table.concat(lines, ' '))

  return sql
end

return M
