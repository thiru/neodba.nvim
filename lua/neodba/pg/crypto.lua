-- Pure-Lua cryptographic primitives required by the PostgreSQL wire protocol
-- (SCRAM-SHA-256 and MD5 password authentication).
--
-- Implements SHA-256, MD5, HMAC-SHA-256, PBKDF2-HMAC-SHA256 and base64 using
-- only 32-bit bit operations (LuaJIT `bit` / `vim.bit`). No external binaries,
-- no C modules.

local ok, bit = pcall(require, 'bit')
if not ok then
  bit = vim.bit
end

local band = bit.band
local bor = bit.bor
local bxor = bit.bxor
local bnot = bit.bnot
local lshift = bit.lshift
local rshift = bit.rshift
local rol = bit.rol
local ror = bit.ror

local char = string.char
local concat = table.concat
local rep = string.rep

local MOD = 4294967296 -- 2^32

local M = {}

local function u32be(n)
  return char(band(rshift(n, 24), 0xff), band(rshift(n, 16), 0xff), band(rshift(n, 8), 0xff), band(n, 0xff))
end

local function u32le(n)
  return char(band(n, 0xff), band(rshift(n, 8), 0xff), band(rshift(n, 16), 0xff), band(rshift(n, 24), 0xff))
end

------------------------------------------------------------------------------
-- SHA-256 (FIPS 180-4)
------------------------------------------------------------------------------

local sha256_K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local sha256_H0 = {
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
}

local function sha256_compress(H, block, off)
  local w = {}
  for i = 0, 15 do
    local p = off + i * 4
    local b1, b2, b3, b4 = block:byte(p + 1, p + 4)
    w[i] = bor(lshift(b1, 24), lshift(b2, 16), lshift(b3, 8), b4)
  end
  for i = 16, 63 do
    local x = w[i - 15]
    local s0 = bxor(ror(x, 7), ror(x, 18), rshift(x, 3))
    local y = w[i - 2]
    local s1 = bxor(ror(y, 17), ror(y, 19), rshift(y, 10))
    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % MOD
  end

  local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]

  for i = 0, 63 do
    local S1 = bxor(ror(e, 6), ror(e, 11), ror(e, 25))
    local ch = bxor(band(e, f), band(bnot(e), g))
    local t1 = (h + S1 + ch + sha256_K[i + 1] + w[i]) % MOD
    local S0 = bxor(ror(a, 2), ror(a, 13), ror(a, 22))
    local maj = bxor(band(a, b), band(a, c), band(b, c))
    local t2 = (S0 + maj) % MOD
    h = g
    g = f
    f = e
    e = (d + t1) % MOD
    d = c
    c = b
    b = a
    a = (t1 + t2) % MOD
  end

  H[1] = (H[1] + a) % MOD
  H[2] = (H[2] + b) % MOD
  H[3] = (H[3] + c) % MOD
  H[4] = (H[4] + d) % MOD
  H[5] = (H[5] + e) % MOD
  H[6] = (H[6] + f) % MOD
  H[7] = (H[7] + g) % MOD
  H[8] = (H[8] + h) % MOD
end

--- SHA-256 digest of `data` as a 32-byte binary string.
function M.sha256(data)
  local H = { sha256_H0[1], sha256_H0[2], sha256_H0[3], sha256_H0[4],
              sha256_H0[5], sha256_H0[6], sha256_H0[7], sha256_H0[8] }
  local ml = #data
  local padded = data
    .. '\128'
    .. rep('\0', (64 - (ml + 9) % 64) % 64)
    .. u32be(math.floor(ml / 0x20000000))
    .. u32be((ml * 8) % MOD)
  for off = 0, #padded - 1, 64 do
    sha256_compress(H, padded, off)
  end
  local out = {}
  for i = 1, 8 do
    out[i] = u32be(H[i])
  end
  return concat(out)
end

------------------------------------------------------------------------------
-- MD5 (RFC 1321)
------------------------------------------------------------------------------

local md5_K = {
  0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
  0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
  0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
  0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
  0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
  0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
}

local md5_S = {
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
}

local function md5_compress(a0, b0, c0, d0, block, off)
  local w = {}
  for i = 0, 15 do
    local p = off + i * 4
    local b1, b2, b3, b4 = block:byte(p + 1, p + 4)
    w[i] = bor(b1, lshift(b2, 8), lshift(b3, 16), lshift(b4, 24))
  end

  local A, B, C, D = a0, b0, c0, d0
  for i = 0, 63 do
    local F, g
    if i < 16 then
      F = bor(band(B, C), band(bnot(B), D))
      g = i
    elseif i < 32 then
      F = bor(band(D, B), band(bnot(D), C))
      g = (5 * i + 1) % 16
    elseif i < 48 then
      F = bxor(B, C, D)
      g = (3 * i + 5) % 16
    else
      F = bxor(C, bor(B, bnot(D)))
      g = (7 * i) % 16
    end
    F = (F + A + md5_K[i + 1] + w[g]) % MOD
    A = D
    D = C
    C = B
    B = (B + rol(F, md5_S[i + 1])) % MOD
  end
  return (a0 + A) % MOD, (b0 + B) % MOD, (c0 + C) % MOD, (d0 + D) % MOD
end

--- MD5 digest of `data` as a 16-byte binary string.
function M.md5(data)
  local a, b, c, d = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476
  local ml = #data
  local padded = data
    .. '\128'
    .. rep('\0', (64 - (ml + 9) % 64) % 64)
    .. u32le((ml * 8) % MOD)
    .. u32le(math.floor(ml / 0x20000000))
  for off = 0, #padded - 1, 64 do
    a, b, c, d = md5_compress(a, b, c, d, padded, off)
  end
  return u32le(a) .. u32le(b) .. u32le(c) .. u32le(d)
end

------------------------------------------------------------------------------
-- HMAC / PBKDF2
------------------------------------------------------------------------------

--- Byte-wise XOR of two equal-length strings.
function M.xor_bytes(a, b)
  local out = {}
  for i = 1, #a do
    out[i] = char(bxor(a:byte(i), b:byte(i)))
  end
  return concat(out)
end

--- HMAC-SHA-256 (RFC 2104). Key and message are binary strings.
function M.hmac_sha256(key, message)
  if #key > 64 then
    key = M.sha256(key)
  end
  key = key .. rep('\0', 64 - #key)
  local ipad = {}
  local opad = {}
  for i = 1, 64 do
    local b = key:byte(i)
    ipad[i] = char(bxor(b, 0x36))
    opad[i] = char(bxor(b, 0x5c))
  end
  return M.sha256(concat(opad) .. M.sha256(concat(ipad) .. message))
end

--- PBKDF2-HMAC-SHA-256 (RFC 2898). Returns `dklen` bytes (default 32).
function M.pbkdf2_hmac_sha256(password, salt, iterations, dklen)
  dklen = dklen or 32
  local out = {}
  for i = 1, math.ceil(dklen / 32) do
    local u = M.hmac_sha256(password, salt .. u32be(i))
    local t = u
    for _ = 2, iterations do
      u = M.hmac_sha256(password, u)
      t = M.xor_bytes(t, u)
    end
    out[#out + 1] = t
  end
  return concat(out):sub(1, dklen)
end

------------------------------------------------------------------------------
-- Base64 (RFC 4648)
------------------------------------------------------------------------------

local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64lookup = {}
for i = 1, 64 do
  b64lookup[b64chars:sub(i, i)] = i - 1
end

function M.b64encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    b = b or 0
    c = c or 0
    local n = a * 65536 + b * 256 + c
    out[#out + 1] = b64chars:sub(band(rshift(n, 18), 63) + 1, band(rshift(n, 18), 63) + 1)
    out[#out + 1] = b64chars:sub(band(rshift(n, 12), 63) + 1, band(rshift(n, 12), 63) + 1)
    out[#out + 1] = b64chars:sub(band(rshift(n, 6), 63) + 1, band(rshift(n, 6), 63) + 1)
    out[#out + 1] = b64chars:sub(band(n, 63) + 1, band(n, 63) + 1)
  end
  local rem = #data % 3
  if rem == 1 then
    out[#out - 1] = '='
    out[#out] = '='
  elseif rem == 2 then
    out[#out] = '='
  end
  return concat(out)
end

function M.b64decode(data)
  data = data:gsub('%s', '')
  local out = {}
  for i = 1, #data, 4 do
    local c1, c2, c3, c4 = data:sub(i, i), data:sub(i + 1, i + 1), data:sub(i + 2, i + 2), data:sub(i + 3, i + 3)
    local n = b64lookup[c1] * 262144 + b64lookup[c2] * 4096 + (b64lookup[c3] or 0) * 64 + (b64lookup[c4] or 0)
    local b1 = band(rshift(n, 16), 255)
    local b2 = band(rshift(n, 8), 255)
    local b3 = band(n, 255)
    if c3 == '=' then
      out[#out + 1] = char(b1)
    elseif c4 == '=' then
      out[#out + 1] = char(b1, b2)
    else
      out[#out + 1] = char(b1, b2, b3)
    end
  end
  return concat(out)
end

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

function M.to_hex(s)
  return (s:gsub('.', function(c)
    return string.format('%02x', c:byte())
  end))
end

function M.from_hex(h)
  return (h:gsub('..', function(cc)
    return char(tonumber(cc, 16))
  end))
end

local uv = vim.uv or vim.loop

--- Returns `n` random bytes, using libuv's CSPRNG when available.
function M.random_bytes(n)
  local ok2, data = pcall(uv.random, n, 0)
  if ok2 and type(data) == 'string' and #data == n then
    return data
  end
  -- Fallback: non-cryptographic PRNG seeded from time and pid.
  math.randomseed((uv.hrtime() + uv.os_getpid() * 7919) % 2147483647)
  local t = {}
  for i = 1, n do
    t[i] = char(math.random(0, 255))
  end
  return concat(t)
end

return M
