-- pgmoon crypto backend for Neovim.
-- Replaces the upstream pgmoon.crypto module (which requires luaossl,
-- LuaCrypto or OpenResty) with pure-Lua implementations from neodba.pg.crypto,
-- so no C modules are needed for MD5 / SCRAM-SHA-256 authentication.

local crypto = require('neodba.pg.crypto')
local util = require('pgmoon.util')

return {
  -- pgmoon expects the hex-encoded digest (matching the luaossl backend).
  md5 = function(str)
    return crypto.to_hex(crypto.md5(str))
  end,
  hmac_sha256 = function(key, str)
    return crypto.hmac_sha256(key, str)
  end,
  digest_sha256 = function(str)
    return crypto.sha256(str)
  end,
  kdf_derive_sha256 = function(str, salt, i)
    return crypto.pbkdf2_hmac_sha256(str, util.decode_base64(salt), i, 32)
  end,
  random_bytes = function(n)
    return crypto.random_bytes(n)
  end,
  x509_digest = function()
    return error('x509 digest is not supported (SSL is not supported by neodba)')
  end,
}
