-- Unit tests for neodba.nvim's pure-Lua PostgreSQL client.
-- Run from the repository root:
--   nvim --clean -l tests/run.lua

package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local crypto = require('neodba.pg.crypto')
local Client = require('neodba.pg.client')
local render = require('neodba.render')
local utils = require('neodba.utils')

local total = 0
local failures = 0

local function check(cond, name)
  total = total + 1
  if cond then
    print('ok   ' .. name)
  else
    failures = failures + 1
    print('FAIL ' .. name)
  end
end

local function eq(actual, expected, name)
  total = total + 1
  if actual == expected then
    print('ok   ' .. name)
  else
    failures = failures + 1
    print(('FAIL %s\n  expected: %s\n  actual:   %s'):format(name, tostring(expected), tostring(actual)))
  end
end

local function hex_eq(actual_bin, expected_hex, name)
  eq(crypto.to_hex(actual_bin), expected_hex, name)
end

------------------------------------------------------------------------------
-- SHA-256
------------------------------------------------------------------------------

hex_eq(crypto.sha256(''), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'sha256 empty')
hex_eq(crypto.sha256('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'sha256 abc')
hex_eq(
  crypto.sha256('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
  '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
  'sha256 56-byte (padding edge)'
)
hex_eq(
  crypto.sha256('\0\0'),
  '96a296d224f285c67bee93c30f8a309157f0daa35dc5b87e410b78630a09cfc7',
  'sha256 NUL bytes'
)
hex_eq(
  crypto.sha256(string.rep('a', 1000000)),
  'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
  'sha256 1M bytes'
)

------------------------------------------------------------------------------
-- MD5
------------------------------------------------------------------------------

hex_eq(crypto.md5(''), 'd41d8cd98f00b204e9800998ecf8427e', 'md5 empty')
hex_eq(crypto.md5('abc'), '900150983cd24fb0d6963f7d28e17f72', 'md5 abc')
hex_eq(crypto.md5('The quick brown fox jumps over the lazy dog'), '9e107d9d372bb6826bd81d3542a419d6', 'md5 fox')
hex_eq(
  crypto.md5('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
  '8215ef0796a20bcaaae116d3876c664a',
  'md5 56-byte (padding edge)'
)
hex_eq(crypto.md5('\0'), '93b885adfe0da089cdf634904fd59f71', 'md5 NUL byte')

------------------------------------------------------------------------------
-- HMAC-SHA-256 (RFC 4231)
------------------------------------------------------------------------------

hex_eq(
  crypto.hmac_sha256(string.rep('\x0b', 20), 'Hi There'),
  'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
  'hmac-sha256 rfc4231 case 1'
)
hex_eq(
  crypto.hmac_sha256('Jefe', 'what do ya want for nothing?'),
  '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
  'hmac-sha256 rfc4231 case 2'
)
hex_eq(
  crypto.hmac_sha256(string.rep('\xaa', 131), 'Test Using Larger Than Block-Size Key - Hash Keys First'),
  'c0997e3005b7fc62410da381de67491c02a059202ccac940aee16a1d74904623',
  'hmac-sha256 rfc4231 case 6 (long key)'
)

------------------------------------------------------------------------------
-- PBKDF2-HMAC-SHA-256
------------------------------------------------------------------------------

hex_eq(
  crypto.pbkdf2_hmac_sha256('password', 'salt', 1, 32),
  '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
  'pbkdf2 c=1'
)
hex_eq(
  crypto.pbkdf2_hmac_sha256('password', 'salt', 2, 32),
  'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
  'pbkdf2 c=2'
)
hex_eq(
  crypto.pbkdf2_hmac_sha256('password', 'salt', 4096, 32),
  'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
  'pbkdf2 c=4096'
)

------------------------------------------------------------------------------
-- Base64 (RFC 4648)
------------------------------------------------------------------------------

eq(crypto.b64encode(''), '', 'b64 encode empty')
eq(crypto.b64encode('f'), 'Zg==', 'b64 encode f')
eq(crypto.b64encode('fo'), 'Zm8=', 'b64 encode fo')
eq(crypto.b64encode('foo'), 'Zm9v', 'b64 encode foo')
eq(crypto.b64encode('foob'), 'Zm9vYg==', 'b64 encode foob')
eq(crypto.b64encode('fooba'), 'Zm9vYmE=', 'b64 encode fooba')
eq(crypto.b64encode('foobar'), 'Zm9vYmFy', 'b64 encode foobar')
eq(crypto.b64decode(''), '', 'b64 decode empty')
eq(crypto.b64decode('Zg=='), 'f', 'b64 decode f')
eq(crypto.b64decode('Zm8='), 'fo', 'b64 decode fo')
eq(crypto.b64decode('Zm9v'), 'foo', 'b64 decode foo')
eq(crypto.b64decode('Zm9vYg=='), 'foob', 'b64 decode foob')
eq(crypto.b64decode('Zm9vYmE='), 'fooba', 'b64 decode fooba')
eq(crypto.b64decode('Zm9vYmFy'), 'foobar', 'b64 decode foobar')

-- Round-trip binary data
local bin = {}
for i = 0, 255 do
  bin[#bin + 1] = string.char(i)
end
bin = table.concat(bin)
eq(crypto.b64decode(crypto.b64encode(bin)), bin, 'b64 round-trip all bytes')

------------------------------------------------------------------------------
-- URL parsing
------------------------------------------------------------------------------

do
  local c1 = utils.parse_pg_url('postgresql://alice:secret@db.example.com:5433/mydb')
  eq(c1.user, 'alice', 'url user')
  eq(c1.password, 'secret', 'url password')
  eq(c1.host, 'db.example.com', 'url host')
  eq(c1.port, 5433, 'url port')
  eq(c1.database, 'mydb', 'url database')

  local c2 = utils.parse_pg_url('postgres://bob@localhost/db2')
  eq(c2.user, 'bob', 'url user (no password)')
  eq(c2.password, nil, 'url no password')
  eq(c2.host, 'localhost', 'url host (no port)')
  eq(c2.port, nil, 'url no port')

  local c3 = utils.parse_pg_url('postgresql://u%40x:p%3Ass@h/d')
  eq(c3.user, 'u@x', 'url decoded user')
  eq(c3.password, 'p:ss', 'url decoded password')
end

------------------------------------------------------------------------------
-- Client result/error normalization
------------------------------------------------------------------------------

do
  local NULL = Client.NULL

  -- SELECT-like result (pgmoon array mode)
  local res = Client._normalize_results({
    { 1, 'Alice', NULL },
    { 2, 'Bob', 'hi' },
    fields = { 'id', 'name', 'note' },
  }, 1)
  eq(#res, 1, 'normalize single result count')
  eq(res[1].kind, 'rows', 'normalize rows kind')
  eq(#res[1].columns, 3, 'normalize columns')
  eq(res[1].rows[1][1], 1, 'normalize row value (number)')
  eq(res[1].rows[1][3], nil, 'normalize NULL -> nil')
  eq(res[1].rows[2][3], 'hi', 'normalize row value (string)')

  -- affected rows
  local res2 = Client._normalize_results({ affected_rows = 5 }, 1)
  eq(res2[1].kind, 'ok', 'normalize affected kind')
  eq(res2[1].command, '5 rows affected', 'normalize affected command')

  -- bare true
  local res3 = Client._normalize_results(true, 1)
  eq(res3[1].kind, 'ok', 'normalize true kind')
  eq(res3[1].command, 'OK', 'normalize true command')

  -- multi-statement
  local res4 = Client._normalize_results({
    { { 1 }, fields = { 'x' } },
    { affected_rows = 2 },
  }, 2)
  eq(#res4, 2, 'normalize multi count')
  eq(res4[1].kind, 'rows', 'normalize multi first')
  eq(res4[2].kind, 'ok', 'normalize multi second')

  -- error strings
  local e1 = Client._normalize_error('ERROR: relation "nope" does not exist (15)')
  eq(e1.severity, 'ERROR', 'error severity')
  eq(e1.message, 'relation "nope" does not exist', 'error message')
  eq(e1.position, '15', 'error position')

  local e2 = Client._normalize_error('FATAL: password authentication failed for user "x"')
  eq(e2.severity, 'FATAL', 'error severity FATAL')
  eq(e2.position, nil, 'error no position')

  local e3 = Client._normalize_error('ERROR: duplicate key\nKey (id)=(1) already exists.')
  eq(e3.message, 'duplicate key', 'error message before detail')
  eq(e3.detail, 'Key (id)=(1) already exists.', 'error detail')

  -- structured error passthrough
  local e4 = Client._normalize_error({ severity = 'FATAL', code = '28000', message = 'bad auth' })
  eq(e4.code, '28000', 'error table passthrough')
end

------------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------------

do
  local results = {
    {
      kind = 'rows',
      columns = { 'id', 'name', 'note' },
      rows = {
        { 1, 'Alice', 'hi' },
        { 2, 'Bob', nil },
      },
    },
  }
  local lines = render.render('select ...', results, nil, 3.4, {})
  local text = table.concat(lines, '\n')
  check(text:find('id', 1, true) ~= nil, 'render has header')
  check(text:find('Alice', 1, true) ~= nil, 'render has data')
  check(text:find('NULL', 1, true) ~= nil, 'render shows NULL')
  check(text:find('(2 rows)', 1, true) ~= nil, 'render row count')
  check(text:find('-- 3 ms', 1, true) ~= nil, 'render elapsed')

  -- Column alignment: header, separator and rows must be same width
  eq(vim.fn.strdisplaywidth(lines[1]), vim.fn.strdisplaywidth(lines[2]), 'render header/sep aligned')
  eq(vim.fn.strdisplaywidth(lines[1]), vim.fn.strdisplaywidth(lines[3]), 'render header/row aligned')

  -- JSON values render as JSON
  local jlines = render.render('q', { { kind = 'rows', columns = { 'j' }, rows = { { { a = 1 } } } } }, nil, 1, {})
  check(table.concat(jlines, '\n'):find('{"a":1}', 1, true) ~= nil, 'render json value')

  -- Error rendering with position caret
  local elines = render.render('select * from nope', {}, {
    severity = 'ERROR',
    code = '42P01',
    message = 'relation "nope" does not exist',
    position = '15',
  }, 1, {})
  local etext = table.concat(elines, '\n')
  check(etext:find('ERROR 42P01: relation "nope" does not exist', 1, true) ~= nil, 'render error line')
  check(etext:find('LINE 1: select * from nope', 1, true) ~= nil, 'render error context')
  check(etext:find('%^') ~= nil, 'render error caret')
end

------------------------------------------------------------------------------
-- pgmoon socket backend: echo test over a real libuv TCP server
------------------------------------------------------------------------------

do
  local uv = vim.uv or vim.loop
  local server = uv.new_tcp()
  server:bind('127.0.0.1', 0)
  local port = server:getsockname().port
  server:listen(128, vim.schedule_wrap(function(lerr)
    assert(not lerr, lerr)
    local client = uv.new_tcp()
    server:accept(client)
    client:read_start(vim.schedule_wrap(function(_, chunk)
      if chunk then
        client:write(chunk) -- echo
      end
    end))
  end))

  local sock = require('pgmoon.socket').new()
  local done, result, serr = false, nil, nil
  local co
  local function resume()
    local ok, out = coroutine.resume(co)
    if coroutine.status(co) == 'dead' then
      done = true
      if ok then
        result = out
      else
        serr = out
      end
    end
  end
  sock.on_wake = resume
  co = coroutine.create(function()
    local ok, err = sock:connect('127.0.0.1', port)
    assert(ok, err)
    assert(sock:send('ping'))
    local pong = assert(sock:receive(4))
    -- exercise partial reads: 2 + 2 bytes
    assert(sock:send('ab'))
    local a = assert(sock:receive(1))
    local b = assert(sock:receive(1))
    sock:close()
    return pong .. a .. b
  end)
  resume()

  check(vim.wait(5000, function()
    return done
  end), 'socket echo completed')
  eq(serr, nil, 'socket echo no error')
  eq(result, 'pingab', 'socket echo round-trip')
  server:close()
end

------------------------------------------------------------------------------
-- PBKDF2 benchmark (informational)
------------------------------------------------------------------------------

do
  local t0 = vim.uv.hrtime()
  crypto.pbkdf2_hmac_sha256('password', 'salt', 4096, 32)
  local ms = (vim.uv.hrtime() - t0) / 1e6
  print(('info pbkdf2(4096 iterations): %.0f ms'):format(ms))
end

------------------------------------------------------------------------------

print(('\n%d tests, %d failures'):format(total, failures))
os.exit(failures == 0 and 0 or 1)
