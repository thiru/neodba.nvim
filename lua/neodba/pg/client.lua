-- Asynchronous PostgreSQL client for Neovim, built on pgmoon (pure Lua).
--
-- pgmoon is written in a synchronous style; we run it inside coroutines while
-- our pgmoon socket backend (lua/pgmoon/socket.lua) suspends the coroutine on
-- every blocking socket operation and resumes it from libuv callbacks. The
-- result is a fully asynchronous, callback-based API that never blocks
-- Neovim's main loop.

local uv = vim.uv or vim.loop
local pgmoon = require('pgmoon')

local unpack = table.unpack or unpack

--- table.pack equivalent (Lua 5.1 / LuaJIT has no table.pack).
local function pack(...)
  return { n = select('#', ...), ... }
end

local NULL = pgmoon.Postgres.NULL

local Client = {}
Client.__index = Client

Client.NULL = NULL

------------------------------------------------------------------------------
-- Result / error normalization (pure functions, unit-tested)
------------------------------------------------------------------------------

--- pgmoon reports query errors as a string: "SEVERITY: message (position)"
--- optionally followed by "\ndetail". Structured error tables (from auth
--- failures) are passed through.
local function normalize_error(err)
  if type(err) == 'table' then
    return {
      severity = err.severity or 'ERROR',
      code = err.code,
      message = err.message or '?',
      position = err.position,
      detail = err.detail,
    }
  end
  local msg = tostring(err)
  local severity, rest = msg:match('^(%u+): (.*)$')
  if not severity then
    return { severity = 'ERROR', message = msg }
  end
  local first_line, detail = rest:match('^([^\n]*)\n?(.*)$')
  local message, position = first_line:match('^(.-) %((%d+)%)$')
  return {
    severity = severity,
    message = message or first_line,
    position = position,
    detail = detail ~= '' and detail or nil,
  }
end

--- Normalizes one pgmoon (array-mode) result into:
---   { kind = 'rows', columns = {...}, rows = {...} }  (NULLs become nil)
---   { kind = 'ok', command = '...' }
local function normalize_one(res)
  if res == true then
    return { kind = 'ok', command = 'OK' }
  end
  if type(res) ~= 'table' then
    return { kind = 'ok', command = tostring(res) }
  end
  if res.fields then
    local ncols = #res.fields
    local rows = {}
    for i, row in ipairs(res) do
      local r = {}
      for j = 1, ncols do
        local v = row[j]
        if v ~= NULL then
          -- pgmoon wraps arrays in a PostgresArray class; unwrap to a
          -- plain table for easier consumption.
          if type(v) == 'table' and getmetatable(v) ~= nil then
            v = setmetatable(v, nil)
          end
          r[j] = v
        end
      end
      rows[i] = r
    end
    return { kind = 'rows', columns = res.fields, rows = rows }
  end
  if res.affected_rows then
    return { kind = 'ok', command = ('%d rows affected'):format(res.affected_rows) }
  end
  return { kind = 'ok', command = 'OK' }
end

local function normalize_results(result, num_queries)
  if num_queries == 1 then
    return { normalize_one(result) }
  end
  local out = {}
  for i, res in ipairs(result) do
    out[i] = normalize_one(res)
  end
  return out
end

Client._normalize_error = normalize_error
Client._normalize_one = normalize_one
Client._normalize_results = normalize_results

------------------------------------------------------------------------------
-- Client
------------------------------------------------------------------------------

--- opts: host, port, user, password, database, timeout
--- A `host` starting with '/' is treated as a Unix socket directory.
function Client.new(opts)
  assert(opts and opts.user, 'connection requires a user')
  local self = setmetatable({}, Client)
  self.opts = {
    host = opts.host or '127.0.0.1',
    port = opts.port or 5432,
    user = opts.user,
    password = opts.password,
    database = opts.database or opts.user,
    timeout = opts.timeout,
  }
  if self.opts.host:sub(1, 1) == '/' then
    self.opts.socket_path = ('%s/.s.PGSQL.%d'):format(self.opts.host, self.opts.port)
  end
  -- disconnected | connecting | ready | closed
  self.state = 'disconnected'
  self.queue = {}
  self.running = false
  return self
end

function Client:is_ready()
  return self.state == 'ready'
end

------------------------------------------------------------------------------
-- Coroutine task runner (serializes all operations on the connection)
------------------------------------------------------------------------------

function Client:_run(fn, callback)
  self.queue[#self.queue + 1] = { fn = fn, callback = callback }
  self:_pump()
end

function Client:_pump()
  if self.running then
    return
  end
  local task = table.remove(self.queue, 1)
  if not task then
    return
  end
  self.running = true
  self.active_task = task
  self.active_co = coroutine.create(task.fn)
  self:_resume()
end

--- Resumes the active coroutine. Called when a task is started and whenever
--- the socket backend signals that a blocked operation can proceed.
function Client:_resume(...)
  local co = self.active_co
  if not co then
    return
  end
  local out = pack(coroutine.resume(co, ...))
  if coroutine.status(co) ~= 'dead' then
    return -- suspended on a socket operation; the socket's on_wake resumes us
  end
  local ok = out[1]
  local task = self.active_task
  self.active_co = nil
  self.active_task = nil
  self.running = false
  if ok then
    task.callback(true, unpack(out, 2, out.n))
  else
    task.callback(false, out[2])
  end
  self:_pump()
end

------------------------------------------------------------------------------
-- Connection lifecycle
------------------------------------------------------------------------------

function Client:_connect_once(password)
  local pg = pgmoon.new({
    host = self.opts.host,
    port = tostring(self.opts.port),
    user = self.opts.user,
    password = password,
    database = self.opts.database,
    socket_path = self.opts.socket_path,
    application_name = 'neodba.nvim',
  })
  pg.sock.on_wake = function()
    self:_resume()
  end
  if self.opts.timeout then
    pg:settimeout(self.opts.timeout)
  end
  local ok, err = pg:connect()
  if not ok then
    pcall(function()
      pg.sock:close()
    end)
    return nil, err
  end
  self.pg = pg
  return true
end

--- Connects and authenticates. callback(err, client)
--- Prompts for a password (via inputsecret) if the server requires one and
--- none was configured.
function Client:connect(callback)
  if self.state == 'ready' then
    if callback then
      callback(nil, self)
    end
    return
  end
  self.state = 'connecting'
  self:_run(function()
    local ok, err = self:_connect_once(self.opts.password)
    if
      not ok
      and not self.opts.password
      and type(err) == 'string'
      and err:find('did not provide a password', 1, true)
    then
      local pw = vim.fn.inputsecret(('Password for %s@%s: '):format(self.opts.user, self.opts.host))
      if pw and #pw > 0 then
        self.opts.password = pw
        ok, err = self:_connect_once(pw)
      end
    end
    if not ok then
      return nil, err
    end
    return true
  end, function(ok, res, err)
    if ok and res then
      self.state = 'ready'
      if callback then
        callback(nil, self)
      end
    else
      self.state = 'closed'
      if callback then
        callback(normalize_error(ok and err or res))
      end
    end
  end)
end

function Client:disconnect()
  if self.pg then
    pcall(function()
      self.pg:disconnect()
    end)
    self.pg = nil
  end
  self.state = 'closed'
end

------------------------------------------------------------------------------
-- Queries
------------------------------------------------------------------------------

--- Runs SQL via the simple query protocol.
--- callback(err, results, elapsed_ms)
---   err: nil, or { severity, code?, message, position?, detail? }
---   results: list of { kind = 'rows', columns, rows } | { kind = 'ok', command }
function Client:query(sql, callback)
  self:_run(function()
    if not self.pg then
      return nil, 'not connected'
    end
    local started = uv.hrtime()
    local out = { self.pg:query_array(sql) }
    local elapsed = (uv.hrtime() - started) / 1e6
    if out[1] == nil then
      -- nil, errmsg, partial_result, num_queries, notifications, notices
      self:_report_notices(out[6])
      local results
      if out[3] and out[4] then
        results = normalize_results(out[3], out[4])
      end
      return results, out[2], elapsed
    end
    -- result, num_queries, notifications, notices
    self:_report_notices(out[4])
    return normalize_results(out[1], out[2]), nil, elapsed
  end, function(ok, results, err, elapsed)
    if not ok then
      self:_mark_dead_if_socket_error(results)
      callback(normalize_error(results), nil, 0)
      return
    end
    if err then
      self:_mark_dead_if_socket_error(err)
      callback(normalize_error(err), results, elapsed)
      return
    end
    callback(nil, results, elapsed)
  end)
end

function Client:_report_notices(notices)
  if type(notices) == 'table' then
    for _, n in ipairs(notices) do
      vim.notify('PostgreSQL: ' .. tostring(n), vim.log.levels.INFO)
    end
  end
end

--- A socket-level failure ('closed' / 'timeout') leaves the protocol stream
--- desynchronized; the connection is unusable and must be re-established.
function Client:_mark_dead_if_socket_error(err)
  local msg = type(err) == 'table' and err.message or tostring(err)
  if msg:find('closed', 1, true) or msg:find('timeout', 1, true) then
    self.state = 'closed'
    self.pg = nil
  end
end

return Client
