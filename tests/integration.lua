-- Integration tests against a live PostgreSQL server.
-- Run from the repository root, e.g.:
--   docker run -d --name neodba-pg -e POSTGRES_PASSWORD=scrampw \
--     -p 55432:5432 -v /tmp/neodba-sock:/var/run/postgresql postgres:latest
--   docker exec neodba-pg psql -U postgres \
--     -c "SET password_encryption='md5'; CREATE USER md5user PASSWORD 'md5pw';"
--   PGHOST=127.0.0.1 PGPORT=55432 PGUSER=postgres PGPASSWORD=scrampw \
--     PGSOCKDIR=/tmp/neodba-sock nvim --clean -l tests/integration.lua

package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

local Client = require('neodba.pg.client')

local HOST = vim.env.PGHOST or '127.0.0.1'
local PORT = tonumber(vim.env.PGPORT or '55432')
local USER = vim.env.PGUSER or 'postgres'
local PASSWORD = vim.env.PGPASSWORD or 'scrampw'
local DATABASE = vim.env.PGDATABASE or 'postgres'
local SOCKDIR = vim.env.PGSOCKDIR

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
  local same
  if type(actual) == 'table' and type(expected) == 'table' then
    same = vim.deep_equal(actual, expected)
  else
    same = actual == expected
  end
  if same then
    print('ok   ' .. name)
  else
    failures = failures + 1
    print(('FAIL %s\n  expected: %s\n  actual:   %s'):format(name, vim.inspect(expected), vim.inspect(actual)))
  end
end

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

local function connect_sync(opts)
  local done, err = false, nil
  local conn = Client.new(opts)
  conn:connect(function(e)
    done = true
    err = e
  end)
  check(vim.wait(10000, function()
    return done
  end), 'connect completed (' .. (opts.user or '?') .. '@' .. (opts.host or '?') .. ')')
  return conn, err
end

local function query_sync(conn, sql)
  local done, err, results, elapsed = false, nil, nil, nil
  conn:query(sql, function(e, r, ms)
    done = true
    err = e
    results = r
    elapsed = ms
  end)
  check(vim.wait(15000, function()
    return done
  end), 'query completed: ' .. sql:sub(1, 60))
  return err, results, elapsed
end

------------------------------------------------------------------------------
-- 1. SCRAM-SHA-256 authentication (default in modern PostgreSQL)
------------------------------------------------------------------------------

local conn, cerr = connect_sync({ host = HOST, port = PORT, user = USER, password = PASSWORD, database = DATABASE })
eq(cerr, nil, 'scram-sha-256 auth')
check(conn.state == 'ready', 'connection ready')

------------------------------------------------------------------------------
-- 2. Wrong password is rejected
------------------------------------------------------------------------------

do
  local bad, berr = connect_sync({ host = HOST, port = PORT, user = USER, password = 'wrongpw', database = DATABASE })
  check(berr ~= nil, 'wrong password rejected')
  check(tostring(berr and berr.message):find('password authentication failed', 1, true) ~= nil, 'wrong password error message')
  eq(bad.state, 'closed', 'failed connection closed')
end

------------------------------------------------------------------------------
-- 3. MD5 password authentication
------------------------------------------------------------------------------

do
  local mconn, merr = connect_sync({ host = HOST, port = PORT, user = 'md5user', password = 'md5pw', database = DATABASE })
  eq(merr, nil, 'md5 auth')
  if mconn then
    mconn:disconnect()
  end
end

------------------------------------------------------------------------------
-- 4. Queries: types, NULLs, unicode
------------------------------------------------------------------------------

do
  local err, results = query_sync(
    conn,
    [[SELECT 1 AS one, 'two' AS two, NULL AS nul, true AS b, 1.5 AS f, 'héllo ✓' AS uni]]
  )
  eq(err, nil, 'select no error')
  eq(results and #results, 1, 'select one result set')
  local set = results and results[1]
  eq(set and set.kind, 'rows', 'select kind rows')
  eq(set and set.columns, { 'one', 'two', 'nul', 'b', 'f', 'uni' }, 'select columns')
  local row = set and set.rows[1]
  eq(row and row[1], 1, 'int4 converted to number')
  eq(row and row[2], 'two', 'text value')
  eq(row and row[3], nil, 'NULL is nil')
  eq(row and row[4], true, 'bool converted')
  eq(row and row[5], 1.5, 'float converted')
  eq(row and row[6], 'héllo ✓', 'unicode value')
end

------------------------------------------------------------------------------
-- 5. Multi-statement query
------------------------------------------------------------------------------

do
  local err, results = query_sync(conn, 'SELECT 1 AS a; SELECT 2 AS b; UPDATE pg_class SET relname = relname WHERE false')
  eq(err, nil, 'multi no error')
  eq(results and #results, 3, 'multi result count')
  eq(results and results[1].kind, 'rows', 'multi first rows')
  eq(results and results[2].rows[1][1], 2, 'multi second value')
  eq(results and results[3].kind, 'ok', 'multi third ok')
end

------------------------------------------------------------------------------
-- 6. Query error surfaces structured info
------------------------------------------------------------------------------

do
  local err = query_sync(conn, 'SELECT * FROM definitely_not_a_table')
  check(err ~= nil, 'error returned')
  eq(err and err.severity, 'ERROR', 'error severity')
  check(err and err.message:find('definitely_not_a_table', 1, true) ~= nil, 'error message')
  check(err and err.position ~= nil, 'error position present')
  -- connection still usable after error
  local err2, results2 = query_sync(conn, 'SELECT 1 AS ok')
  eq(err2, nil, 'connection usable after error')
  eq(results2 and results2[1].rows[1][1], 1, 'post-error query works')
end

------------------------------------------------------------------------------
-- 7. Empty query
------------------------------------------------------------------------------

do
  local err = query_sync(conn, '')
  eq(err, nil, 'empty query no error')
end

------------------------------------------------------------------------------
-- 8. Concurrent queries are serialized in order
------------------------------------------------------------------------------

do
  local completed = {}
  for i = 1, 3 do
    conn:query(('SELECT %d AS n'):format(i), function(e, r)
      completed[#completed + 1] = r[1].rows[1][1]
    end)
  end
  check(vim.wait(15000, function()
    return #completed == 3
  end), 'queued queries all completed')
  eq(completed, { 1, 2, 3 }, 'queued queries ran in order')
end

------------------------------------------------------------------------------
-- 9. JSON and array columns
------------------------------------------------------------------------------

do
  local err, results = query_sync(conn, [[SELECT '{"a": 1, "b": [2, 3]}'::jsonb AS j, ARRAY[1,2,3] AS arr]])
  eq(err, nil, 'json/array no error')
  local row = results and results[1].rows[1]
  eq(row and row[1], { a = 1, b = { 2, 3 } }, 'jsonb decoded')
  eq(row and row[2], { 1, 2, 3 }, 'array decoded')
end

------------------------------------------------------------------------------
-- 10. Larger result set
------------------------------------------------------------------------------

do
  local err, results, elapsed = query_sync(conn, 'SELECT i, i::text AS t FROM generate_series(1, 10000) AS i')
  eq(err, nil, 'generate_series no error')
  eq(results and #results[1].rows, 10000, 'generate_series row count')
  eq(results and results[1].rows[10000][1], 10000, 'generate_series last value')
  print(('info 10k rows in %.0f ms'):format(elapsed or 0))
end

------------------------------------------------------------------------------
-- 11. Unix domain socket (trust auth)
------------------------------------------------------------------------------

if SOCKDIR then
  local sconn, serr = connect_sync({ host = SOCKDIR, port = 5432, user = USER, database = DATABASE })
  eq(serr, nil, 'unix socket connect (trust)')
  if sconn and sconn.state == 'ready' then
    local err, results = query_sync(sconn, 'SELECT 42 AS answer')
    eq(err, nil, 'unix socket query')
    eq(results and results[1].rows[1][1], 42, 'unix socket result')
    sconn:disconnect()
  end
else
  print('skip unix socket test (PGSOCKDIR not set)')
end

------------------------------------------------------------------------------
-- 12. Disconnect
------------------------------------------------------------------------------

conn:disconnect()
eq(conn.state, 'closed', 'disconnect closes connection')

------------------------------------------------------------------------------

print(('\n%d tests, %d failures'):format(total, failures))
os.exit(failures == 0 and 0 or 1)
