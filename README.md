# neodba.nvim

Run SQL queries against PostgreSQL from Neovim. **Pure Lua — no external
binaries, no C modules, no `psql`.**

The plugin speaks the PostgreSQL wire protocol directly using
[pgmoon](https://github.com/leafo/pgmoon) (a pure-Lua PostgreSQL client,
vendored in `lua/pgmoon/`) running on Neovim's built-in libuv (`vim.uv`).

## Features

- Connect over TCP or Unix domain sockets
- SCRAM-SHA-256, MD5 and cleartext password authentication (crypto implemented
  in pure Lua), plus trust auth; password prompt via `inputsecret()` when needed
- Execute SQL: paragraph under cursor, visual selection, range, or whole buffer
- Results in a split window, rendered as aligned plain-text tables
- psql-style error display with a caret pointing at the offending position
- Fully asynchronous: queries never block the editor
- Type conversion: numbers, booleans, NULL, JSON/JSONB (to Lua tables), arrays
- Multi-statement queries, with partial results shown when a statement fails

## Requirements

- Neovim 0.9+ (developed against 0.12)
- A reachable PostgreSQL server. Note: **TLS/SSL is not supported**, so use
  localhost, a Unix socket, or a trusted network.

## Installation

Use your favorite plugin manager, e.g. lazy.nvim:

```lua
{
  'you/neodba.nvim',
  config = function()
    require('neodba').setup({
      connection = {
        host = '127.0.0.1',     -- or '/run/postgresql' for a Unix socket
        port = 5432,
        user = 'postgres',
        password = 'secret',    -- optional; prompted when required
        database = 'postgres',
      },
      -- or a single string:
      -- connection_string = 'postgresql://postgres:secret@127.0.0.1:5432/postgres',
    })
  end,
}
```

### Options

```lua
require('neodba').setup({
  connection = { ... },        -- see above
  connection_string = nil,     -- postgresql:// URL, overrides `connection`
  output = {
    max_col_width = 60,        -- truncate wide values
    null_text = 'NULL',        -- how SQL NULL is displayed
  },
})
```

## Usage

In a `sql` buffer, press `<CR>` (normal or visual mode) to execute the
paragraph under the cursor or the current selection. `<C-CR>` works in insert
mode.

| Command | Description |
| --- | --- |
| `:NeodbaConnect` | Connect to PostgreSQL |
| `:NeodbaDisconnect` | Disconnect |
| `:NeodbaExecSql [sql]` | Execute argument, range, selection, or paragraph |
| `:NeodbaExecBuffer` | Execute the entire buffer |

Example output:

```
 id | name  | note
----+-------+-------
 1  | Alice | hi
 2  | Bob   | NULL
(2 rows)
-- 3 ms
```

Errors look like psql's:

```
ERROR 42P01: relation "nope" does not exist
LINE 1: select * from nope
                      ^
-- 0.4 ms
```

## How it works

```
lua/
  neodba/
    init.lua          setup, user commands, keymaps
    core.lua          connection management, query execution, output window
    render.lua        result table rendering
    utils.lua         helpers (selection, pg URL parsing)
    pg/
      client.lua      async, coroutine-based driver around pgmoon
      crypto.lua      pure-Lua SHA-256/MD5/HMAC/PBKDF2/base64 (for auth)
  pgmoon/             vendored pgmoon 1.18.0 (MIT, (C) Leaf Corcoran)
                      with Neovim-specific socket/crypto/json/util backends
```

pgmoon is written in a synchronous style against a blocking socket API (like
LuaSocket or OpenResty's cosocket). `lua/pgmoon/socket.lua` emulates that API
on top of `vim.uv` the same way OpenResty does: blocking calls yield the
current coroutine and libuv callbacks resume it. `neodba.pg.client` runs every
operation inside a coroutine and exposes a plain callback API, so the editor
never blocks.

Upstream pgmoon modules that required C libraries were replaced:

| Upstream dependency | Replacement |
| --- | --- |
| LuaSocket / luaposix / cqueues / ngx socket | `vim.uv` coroutine socket |
| luaossl / LuaCrypto (md5, sha256, hmac, pbkdf2) | `neodba.pg.crypto` (pure Lua) |
| `cjson` | `vim.json` |
| LuaSocket `mime` (base64) | `neodba.pg.crypto` (pure Lua) |

Two tiny behavioral patches were applied to vendored `pgmoon/init.lua`
(marked with `neodba patch` comments): surface the server's error message on
SCRAM failure, and handle `EmptyQueryResponse`.

## Limitations

- No TLS/SSL (would require a TLS implementation; not planned)
- Simple query protocol only (no prepared statements / parameters yet)
- Metadata browsing (tables/schemas/views) from the old binary-based version
  is not yet reimplemented

## Testing

Unit tests (crypto vectors, rendering, normalization, socket echo):

```sh
nvim --clean -l tests/run.lua
```

Integration tests against a live server in Docker:

```sh
docker run -d --name neodba-pg -e POSTGRES_PASSWORD=scrampw \
  -p 55432:5432 -v /tmp/neodba-sock:/var/run/postgresql postgres:latest
docker exec neodba-pg psql -U postgres \
  -c "SET password_encryption='md5'; CREATE USER md5user PASSWORD 'md5pw';"
# PG18+: allow md5 for that user explicitly
docker exec neodba-pg bash -c "sed -i '/^host all all all scram-sha-256/i host all md5user all md5' /var/lib/postgresql/*/docker/pg_hba.conf"
docker exec neodba-pg psql -U postgres -c "SELECT pg_reload_conf();"

PGHOST=127.0.0.1 PGPORT=55432 PGUSER=postgres PGPASSWORD=scrampw \
  PGSOCKDIR=/tmp/neodba-sock nvim --clean -l tests/integration.lua
```

## License

MIT (see `LICENSE`). Bundles pgmoon (MIT, Copyright (C) 2018 Leaf Corcoran,
see `lua/pgmoon/LICENSE`).
