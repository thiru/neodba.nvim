-- pgmoon JSON backend for Neovim.
-- Replaces the upstream pgmoon.json module (which requires the cjson C
-- module) with vim.json, which is built into Neovim.

local function encode_json(tbl, escape_literal)
  local enc = vim.json.encode(tbl)
  if escape_literal then
    return escape_literal(enc)
  end
  local Postgres = require('pgmoon').Postgres
  return Postgres.escape_literal(nil, enc)
end

local function decode_json(str)
  return vim.json.decode(str)
end

return {
  encode_json = encode_json,
  decode_json = decode_json,
}
