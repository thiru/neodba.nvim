-- Renders query results as psql-style aligned plain-text tables.
--
-- Expects normalized results (see neodba.pg.client):
--   { kind = 'rows', columns = { 'id', 'name', ... }, rows = { {...}, ... } }
--   { kind = 'ok', command = '...' }
-- NULL values are nil; numbers/booleans are Lua values; JSON is a Lua table.

local M = {}

local defaults = {
  max_col_width = 60,
  null_text = 'NULL',
}

local function cell_text(v, null_text)
  if v == nil then
    return null_text
  end
  if type(v) == 'table' then
    local ok, enc = pcall(vim.json.encode, v)
    v = ok and enc or tostring(v)
  else
    v = tostring(v)
  end
  return (v:gsub('\n', '\\n'))
end

--- Pads or truncates `s` to display width `w`.
local function fit(s, w)
  local sw = vim.fn.strdisplaywidth(s)
  if sw > w then
    s = vim.fn.strcharpart(s, 0, w - 1)
    while vim.fn.strdisplaywidth(s) > w - 1 do
      s = vim.fn.strcharpart(s, 0, vim.fn.strchars(s) - 1)
    end
    return s .. '…' .. string.rep(' ', w - vim.fn.strdisplaywidth(s) - 1)
  end
  return s .. string.rep(' ', w - sw)
end

local function render_rows(set, opts, lines)
  local n = #set.columns
  local widths = {}
  for i, c in ipairs(set.columns) do
    widths[i] = math.min(vim.fn.strdisplaywidth(c), opts.max_col_width)
  end

  local cells = {}
  for r, row in ipairs(set.rows) do
    cells[r] = {}
    for i = 1, n do
      local v = cell_text(row[i], opts.null_text)
      cells[r][i] = v
      widths[i] = math.min(math.max(widths[i], vim.fn.strdisplaywidth(v)), opts.max_col_width)
    end
  end

  local header = {}
  local sep = {}
  for i, c in ipairs(set.columns) do
    header[i] = fit(c, widths[i])
    sep[i] = string.rep('-', widths[i])
  end
  lines[#lines + 1] = table.concat(header, ' | ')
  lines[#lines + 1] = table.concat(sep, '-+-')

  for _, row in ipairs(cells) do
    local parts = {}
    for i = 1, n do
      parts[i] = fit(row[i], widths[i])
    end
    lines[#lines + 1] = table.concat(parts, ' | ')
  end

  local nrows = #set.rows
  lines[#lines + 1] = ('(%d row%s)%s'):format(
    nrows,
    nrows == 1 and '' or 's',
    set.command and ('  ' .. set.command) or ''
  )
end

local function render_error(sql, err, lines)
  lines[#lines + 1] = ('%s%s: %s'):format(
    err.severity or 'ERROR',
    err.code and (' ' .. err.code) or '',
    err.message or 'unknown error'
  )

  -- Show the offending line with a caret, like psql does.
  local pos = tonumber(err.position or '')
  if pos and sql then
    local sql_lines = vim.split(sql, '\n', { plain = true })
    local acc = 0
    for i, l in ipairs(sql_lines) do
      if pos <= acc + #l + 1 then
        local prefix = ('LINE %d: '):format(i)
        lines[#lines + 1] = prefix .. l
        lines[#lines + 1] = string.rep(' ', #prefix + math.max(pos - acc - 1, 0)) .. '^'
        break
      end
      acc = acc + #l + 1
    end
  end

  if err.detail then
    lines[#lines + 1] = 'DETAIL: ' .. err.detail
  end
  if err.hint then
    lines[#lines + 1] = 'HINT: ' .. err.hint
  end
end

--- Renders a full query outcome into a list of lines.
--- err may be nil; results may be nil on connection-level failures.
function M.render(sql, results, err, elapsed_ms, opts)
  opts = vim.tbl_extend('force', defaults, opts or {})
  local lines = {}

  for _, res in ipairs(results or {}) do
    if res.kind == 'rows' then
      render_rows(res, opts, lines)
    else
      lines[#lines + 1] = res.command
    end
    lines[#lines + 1] = ''
  end

  if err then
    render_error(sql, err, lines)
    lines[#lines + 1] = ''
  end

  if elapsed_ms then
    if elapsed_ms < 1 then
      lines[#lines + 1] = ('-- %.1f ms'):format(elapsed_ms)
    else
      lines[#lines + 1] = ('-- %d ms'):format(math.floor(elapsed_ms + 0.5))
    end
  end

  -- Trim trailing blank lines.
  while #lines > 0 and lines[#lines] == '' do
    lines[#lines] = nil
  end

  return lines
end

return M
