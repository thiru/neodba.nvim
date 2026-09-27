-- pgmoon utilities, Neovim edition.
-- `flatten` is verbatim from upstream; base64 uses neodba's pure-Lua
-- implementation instead of LuaSocket's `mime` C module.

local crypto = require('neodba.pg.crypto')

local flatten
do
  local function __flatten(t, buffer)
    local t_type = type(t)
    if t_type == 'string' then
      buffer[#buffer + 1] = t
    elseif t_type == 'number' then
      buffer[#buffer + 1] = tostring(t)
    elseif t_type == 'table' then
      for _, thing in ipairs(t) do
        __flatten(thing, buffer)
      end
    end
  end
  flatten = function(t)
    local buffer = {}
    __flatten(t, buffer)
    return table.concat(buffer)
  end
end

return {
  flatten = flatten,
  encode_base64 = crypto.b64encode,
  decode_base64 = crypto.b64decode,
}
