-- pgmoon socket backend for Neovim, implemented over libuv (vim.uv).
-- Replaces the upstream pgmoon.socket module (LuaSocket / luaposix / cqueues /
-- ngx cosocket), none of which are available or desirable in Neovim.
--
-- pgmoon expects a synchronous, blocking socket API. We emulate it the same
-- way OpenResty's cosocket API does: every blocking method yields the current
-- coroutine, and a libuv callback resumes it when the operation completes.
-- All pgmoon operations must therefore run inside a coroutine that is driven
-- by the consumer via the `on_wake` callback (see neodba.pg.client).

local uv = vim.uv or vim.loop
local flatten = require('pgmoon.util').flatten

local Socket = {}
Socket.__index = Socket

------------------------------------------------------------------------------
-- Timer / wakeup helpers
------------------------------------------------------------------------------

function Socket:_start_timer()
  self:_stop_timer()
  if not self.timeout or self.timeout <= 0 then
    return
  end
  self.timer = uv.new_timer()
  self.timer:start(self.timeout, 0, vim.schedule_wrap(function()
    self.timed_out = true
    self:_wake()
  end))
end

function Socket:_stop_timer()
  if self.timer then
    pcall(function()
      self.timer:stop()
      if not self.timer:is_closing() then
        self.timer:close()
      end
    end)
    self.timer = nil
  end
end

function Socket:_wake()
  if self.waiting then
    self.waiting = false
    if self.on_wake then
      self.on_wake()
    end
  end
end

------------------------------------------------------------------------------
-- Blocking primitives (must be called from a coroutine)
------------------------------------------------------------------------------

--- connect(host, port) connects over TCP; connect(path) over a Unix socket.
function Socket:connect(host, port)
  assert(coroutine.running(), 'pgmoon uv socket: connect() must be called from a coroutine')
  self.timed_out = false
  self.conn_err = nil
  self:_start_timer()

  local function on_connect(err)
    self.conn_err = err
    self:_wake()
  end

  if port == nil then
    self.handle = uv.new_pipe()
    uv.pipe_connect(self.handle, host, vim.schedule_wrap(on_connect))
  else
    self.handle = uv.new_tcp()
    uv.getaddrinfo(host, nil, { socktype = 'stream' }, vim.schedule_wrap(function(err, addresses)
      if err or not addresses or #addresses == 0 then
        return on_connect('could not resolve host ' .. tostring(host) .. ': ' .. tostring(err))
      end
      uv.tcp_connect(self.handle, addresses[1].addr, port, vim.schedule_wrap(on_connect))
    end))
  end

  self.waiting = true
  coroutine.yield()
  self:_stop_timer()

  if self.timed_out then
    self:close()
    return nil, 'timeout'
  end
  if self.conn_err then
    local err = self.conn_err
    self.conn_err = nil
    self:close()
    return nil, err
  end

  self.handle:read_start(vim.schedule_wrap(function(err, chunk)
    if err then
      self.fatal_err = tostring(err)
    elseif not chunk then
      self.fatal_err = 'closed'
    else
      self.buf = self.buf .. chunk
    end
    self:_wake()
  end))

  return true
end

--- Reads exactly `n` bytes.
function Socket:receive(n)
  assert(coroutine.running(), 'pgmoon uv socket: receive() must be called from a coroutine')
  if n == 0 then
    return ''
  end
  while #self.buf < n do
    if self.fatal_err then
      return nil, self.fatal_err
    end
    self.timed_out = false
    self:_start_timer()
    self.waiting = true
    coroutine.yield()
    self:_stop_timer()
    if self.timed_out then
      return nil, 'timeout'
    end
  end
  local out = self.buf:sub(1, n)
  self.buf = self.buf:sub(n + 1)
  return out
end

function Socket:send(...)
  if self.fatal_err then
    return nil, self.fatal_err
  end
  local data = flatten({ ... })
  self.handle:write(data, function(err)
    if err then
      self.fatal_err = tostring(err)
    end
  end)
  return #data
end

------------------------------------------------------------------------------
-- Housekeeping
------------------------------------------------------------------------------

function Socket:settimeout(ms)
  self.timeout = ms
end

function Socket:getreusedtimes()
  return 0
end

function Socket:setkeepalive()
  return error('setkeepalive is only available on the ngx cosocket API')
end

function Socket:sslhandshake()
  return error('SSL is not supported by neodba (pure-Lua pgmoon socket)')
end

function Socket:close()
  self.fatal_err = self.fatal_err or 'closed'
  self:_stop_timer()
  if self.handle then
    pcall(function()
      self.handle:read_stop()
      if not self.handle:is_closing() then
        self.handle:close()
      end
    end)
    self.handle = nil
  end
  self:_wake()
  return true
end

return {
  new = function(_socket_type)
    local self = setmetatable({
      buf = '',
      timeout = nil,
      handle = nil,
      waiting = false,
      timed_out = false,
      fatal_err = nil,
      -- Called (from a scheduled, main-loop-safe context) when a blocked
      -- operation can make progress. Set by the consumer.
      on_wake = nil,
    }, Socket)
    return self, 'neodba_uv'
  end,
}
