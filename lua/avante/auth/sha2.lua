--------------------------------------------------------------------------------------------------------------------------
-- sha2.lua
--------------------------------------------------------------------------------------------------------------------------
-- VERSION: 12 (2022-02-23)
-- AUTHOR:  Egor Skriptunoff
-- LICENSE: MIT (the same license as Lua itself)
-- URL:     https://github.com/Egor-Skriptunoff/pure_lua_SHA
--
-- DESCRIPTION:
--    This module contains functions to calculate SHA digest:
--       MD5, SHA-1,
--       SHA-224, SHA-256, SHA-512/224, SHA-512/256, SHA-384, SHA-512,
--       SHA3-224, SHA3-256, SHA3-384, SHA3-512, SHAKE128, SHAKE256,
--       HMAC,
--       BLAKE2b, BLAKE2s, BLAKE2bp, BLAKE2sp, BLAKE2Xb, BLAKE2Xs,
--       BLAKE3, BLAKE3_KDF
--    Written in pure Lua.
--    Compatible with:
--       Lua 5.1, Lua 5.2, Lua 5.3, Lua 5.4, Fengari, LuaJIT 2.0/2.1 (any CPU endianness).
--    Main feature of this module: it was heavily optimized for speed.
--    For every Lua version the module contains particular implementation branch to get benefits from version-specific features.
--       - branch for Lua 5.1 (emulating bitwise operators using look-up table)
--       - branch for Lua 5.2 (using bit32/bit library), suitable for both Lua 5.2 with native "bit32" and Lua 5.1 with external library "bit"
--       - branch for Lua 5.3/5.4 (using native 64-bit bitwise operators)
--       - branch for Lua 5.3/5.4 (using native 32-bit bitwise operators) for Lua built with LUA_INT_TYPE=LUA_INT_INT
--       - branch for LuaJIT without FFI library (useful in a sandboxed environment)
--       - branch for LuaJIT x86 without FFI library (LuaJIT x86 has oddity because of lack of CPU registers)
--       - branch for LuaJIT 2.0 with FFI library (bit.* functions work only with Lua numbers)
--       - branch for LuaJIT 2.1 with FFI library (bit.* functions can work with "int64_t" arguments)
--
--
-- USAGE:
--    Input data should be provided as a binary string: either as a whole string or as a sequence of substrings (chunk-by-chunk loading, total length < 9*10^15 bytes).
--    Result (SHA digest) is returned in hexadecimal representation as a string of lowercase hex digits.
--    Simplest usage example:
--       local sha = require("sha2")
--       local your_hash = sha.sha256("your string")
--    See file "sha2_test.lua" for more examples.
--
--
-- CHANGELOG:
--  version     date      description
--  -------  ----------   -----------
--    12     2022-02-23   Now works in Luau (but NOT optimized for speed)
--    11     2022-01-09   BLAKE3 added
--    10     2022-01-02   BLAKE2 functions added
--     9     2020-05-10   Now works in OpenWrt's Lua (dialect of Lua 5.1 with "double" + "invisible int32")
--     8     2019-09-03   SHA-3 functions added
--     7     2019-03-17   Added functions to convert to/from base64
--     6     2018-11-12   HMAC added
--     5     2018-11-10   SHA-1 added
--     4     2018-11-03   MD5 added
--     3     2018-11-02   Bug fixed: incorrect hashing of long (2 GByte) data streams on Lua 5.3/5.4 built with "int32" integers
--     2     2018-10-07   Decreased module loading time in Lua 5.1 implementation branch (thanks to Peter Melnichenko for giving a hint)
--     1     2018-10-06   First release (only SHA-2 functions)
-----------------------------------------------------------------------------

local print_debug_messages = false -- set to true to view some messages about your system's abilities and implementation branch chosen for your system

local unpack, table_concat, byte, char, string_rep, sub, gsub, gmatch, string_format, floor, ceil, math_min, math_max, tonumber, type, math_huge =
  table.unpack or unpack,
  table.concat,
  string.byte,
  string.char,
  string.rep,
  string.sub,
  string.gsub,
  string.gmatch,
  string.format,
  math.floor,
  math.ceil,
  math.min,
  math.max,
  tonumber,
  type,
  math.huge

--------------------------------------------------------------------------------
-- EXAMINING YOUR SYSTEM
--------------------------------------------------------------------------------

local function get_precision(one)
  -- "one" must be either float 1.0 or integer 1
  -- returns bits_precision, is_integer
  -- This function works correctly with all floating point datatypes (including non-IEEE-754)
  local k, n, m, prev_n = 0, one, one
  while true do
    k, prev_n, n, m = k + 1, n, n + n + 1, m + m + k % 2
    if k > 256 or n - (n - 1) ~= 1 or m - (m - 1) ~= 1 or n == m then
      return k, false -- floating point datatype
    elseif n == prev_n then
      return k, true -- integer datatype
    end
  end
end

-- Make sure Lua has "double" numbers
local x = 2 / 3
local Lua_has_double = x * 5 > 3 and x * 4 < 3 and get_precision(1.0) >= 53
assert(Lua_has_double, "at least 53-bit floating point numbers are required")

-- Q:
--    SHA2 was designed for FPU-less machines.
--    So, why floating point numbers are needed for this module?
-- A:
--    53-bit "double" numbers are useful to calculate "magic numbers" used in SHA.
--    I prefer to write 50 LOC "magic numbers calculator" instead of storing more than 200 constants explicitly in this source file.

local int_prec, Lua_has_integers = get_precision(1)
local Lua_has_int64 = Lua_has_integers and int_prec == 64
local Lua_has_int32 = Lua_has_integers and int_prec == 32
assert(Lua_has_int64 or Lua_has_int32 or not Lua_has_integers, "Lua integers must be either 32-bit or 64-bit")

-- Q:
--    Does it mean that almost all non-standard configurations are not supported?
-- A:
--    Yes.  Sorry, too many problems to support all possible Lua numbers configurations.
--       Lua 5.1/5.2    with "int32"               will not work.
--       Lua 5.1/5.2    with "int64"               will not work.
--       Lua 5.1/5.2    with "int128"              will not work.
--       Lua 5.1/5.2    with "float"               will not work.
--       Lua 5.1/5.2    with "double"              is OK.          (default config for Lua 5.1, Lua 5.2, LuaJIT)
--       Lua 5.3/5.4    with "int32"  + "float"    will not work.
--       Lua 5.3/5.4    with "int64"  + "float"    will not work.
--       Lua 5.3/5.4    with "int128" + "float"    will not work.
--       Lua 5.3/5.4    with "int32"  + "double"   is OK.          (config used by Fengari)
--       Lua 5.3/5.4    with "int64"  + "double"   is OK.          (default config for Lua 5.3, Lua 5.4)
--       Lua 5.3/5.4    with "int128" + "double"   will not work.
--   Using floating point numbers better than "double" instead of "double" is OK (non-IEEE-754 floating point implementation are allowed).
--   Using "int128" instead of "int64" is not OK: "int128" would require different branch of implementation for optimized SHA512.

-- Check for LuaJIT and 32-bit bitwise libraries
local is_LuaJIT = ({ false, [1] = true })[1]
  and _VERSION ~= "Luau"
  and (type(jit) ~= "table" or jit.version_num >= 20000) -- LuaJIT 1.x.x and Luau are treated as vanilla Lua 5.1/5.2
local is_LuaJIT_21 -- LuaJIT 2.1+
local LuaJIT_arch
local ffi -- LuaJIT FFI library (as a table)
local b -- 32-bit bitwise library (as a table)
local library_name

if is_LuaJIT then
  -- Assuming "bit" library is always available on LuaJIT
  b = require("bit")
  library_name = "bit"
  -- "ffi" is intentionally disabled on some systems for safety reason
  local LuaJIT_has_FFI, result = pcall(require, "ffi")
  if LuaJIT_has_FFI then ffi = result end
  is_LuaJIT_21 = not not loadstring("b=0b0")
  LuaJIT_arch = type(jit) == "table" and jit.arch or ffi and ffi.arch or nil
else
  -- For vanilla Lua, "bit"/"bit32" libraries are searched in global namespace only.  No attempt is made to load a library if it's not loaded yet.
  for _, libname in ipairs(_VERSION == "Lua 5.2" and { "bit32", "bit" } or { "bit", "bit32" }) do
    if type(_G[libname]) == "table" and _G[libname].bxor then
      b = _G[libname]
      library_name = libname
      break
    end
  end
end

--------------------------------------------------------------------------------
-- You can disable here some of your system's abilities (for testing purposes)
--------------------------------------------------------------------------------
-- is_LuaJIT = nil
-- is_LuaJIT_21 = nil
-- ffi = nil
-- Lua_has_int32 = nil
-- Lua_has_int64 = nil
-- b, library_name = nil
--------------------------------------------------------------------------------

if print_debug_messages then
  -- Printing list of abilities of your system
  print("Abilities:")
  print(
    "   Lua version:               "
      .. (
        is_LuaJIT
          and "LuaJIT " .. (is_LuaJIT_21 and "2.1 " or "2.0 ") .. (LuaJIT_arch or "") .. (ffi and " with FFI" or " without FFI")
        or _VERSION
      )
  )
  print("   Integer bitwise operators: " .. (Lua_has_int64 and "int64" or Lua_has_int32 and "int32" or "no"))
  print("   32-bit bitwise library:    " .. (library_name or "not found"))
end

-- Selecting the most suitable implementation for given set of abilities
local method, branch
if is_LuaJIT and ffi then
  method = "Using 'ffi' library of LuaJIT"
  branch = "FFI"
elseif is_LuaJIT then
  method = "Using special code for sandboxed LuaJIT (no FFI)"
  branch = "LJ"
elseif Lua_has_int64 then
  method = "Using native int64 bitwise operators"
  branch = "INT64"
elseif Lua_has_int32 then
  method = "Using native int32 bitwise operators"
  branch = "INT32"
elseif library_name then -- when bitwise library is available (Lua 5.2 with native library "bit32" or Lua 5.1 with external library "bit")
  method = "Using '" .. library_name .. "' library"
  branch = "LIB32"
else
  method = "Emulating bitwise operators using look-up table"
  branch = "EMUL"
end

if print_debug_messages then
  -- Printing the implementation selected to be used on your system
  print("Implementation selected:")
  print("   " .. method)
end

--------------------------------------------------------------------------------
-- BASIC 32-BIT BITWISE FUNCTIONS
--------------------------------------------------------------------------------

local AND, OR, XOR, SHL, SHR, ROL, ROR, NOT, NORM, HEX, XOR_BYTE
-- Only low 32 bits of function arguments matter, high bits are ignored
-- The result of all functions (except HEX) is an integer inside "correct range":
--    for "bit" library:    (-2^31)..(2^31-1)
--    for "bit32" library:        0..(2^32-1)

if branch == "FFI" or branch == "LJ" or branch == "LIB32" then
  -- Your system has 32-bit bitwise library (either "bit" or "bit32")

  AND = b.band -- 2 arguments
  OR = b.bor -- 2 arguments
  XOR = b.bxor -- 2..5 arguments
  SHL = b.lshift -- second argument is integer 0..31
  SHR = b.rshift -- second argument is integer 0..31
  ROL = b.rol or b.lrotate -- second argument is integer 0..31
  ROR = b.ror or b.rrotate -- second argument is integer 0..31
  NOT = b.bnot -- only for LuaJIT
  NORM = b.tobit -- only for LuaJIT
  HEX = b.tohex -- returns string of 8 lowercase hexadecimal digits
  assert(AND and OR and XOR and SHL and SHR and ROL and ROR and NOT, "Library '" .. library_name .. "' is incomplete")
  XOR_BYTE = XOR -- XOR of two bytes (0..255)
elseif branch == "EMUL" then
  -- Emulating 32-bit bitwise operations using 53-bit floating point arithmetic

  function SHL(x, n) return (x * 2 ^ n) % 2 ^ 32 end

  function SHR(x, n)
    x = x % 2 ^ 32 / 2 ^ n
    return x - x % 1
  end

  function ROL(x, n)
    x = x % 2 ^ 32 * 2 ^ n
    local r = x % 2 ^ 32
    return r + (x - r) / 2 ^ 32
  end

  function ROR(x, n)
    x = x % 2 ^ 32 / 2 ^ n
    local r = x % 1
    return r * 2 ^ 32 + (x - r)
  end

  local AND_of_two_bytes = { [0] = 0 } -- look-up table (256*256 entries)
  local idx = 0
  for y = 0, 127 * 256, 256 do
    for x = y, y + 127 do
      x = AND_of_two_bytes[x] * 2
      AND_of_two_bytes[idx] = x
      AND_of_two_bytes[idx + 1] = x
      AND_of_two_bytes[idx + 256] = x
      AND_of_two_bytes[idx + 257] = x + 1
      idx = idx + 2
    end
    idx = idx + 256
  end

  local function and_or_xor(x, y, operation)
    -- operation: nil = AND, 1 = OR, 2 = XOR
    local x0 = x % 2 ^ 32
    local y0 = y % 2 ^ 32
    local rx = x0 % 256
    local ry = y0 % 256
    local res = AND_of_two_bytes[rx + ry * 256]
    x = x0 - rx
    y = (y0 - ry) / 256
    rx = x % 65536
    ry = y % 256
    res = res + AND_of_two_bytes[rx + ry] * 256
    x = (x - rx) / 256
    y = (y - ry) / 256
    rx = x % 65536 + y % 256
    res = res + AND_of_two_bytes[rx] * 65536
    res = res + AND_of_two_bytes[(x + y - rx) / 256] * 16777216
    if operation then res = x0 + y0 - operation * res end
    return res
  end

  function AND(x, y) return and_or_xor(x, y) end

  function OR(x, y) return and_or_xor(x, y, 1) end

  function XOR(x, y, z, t, u) -- 2..5 arguments
    if z then
      if t then
        if u then t = and_or_xor(t, u, 2) end
        z = and_or_xor(z, t, 2)
      end
      y = and_or_xor(y, z, 2)
    end
    return and_or_xor(x, y, 2)
  end

  function XOR_BYTE(x, y) return x + y - 2 * AND_of_two_bytes[x + y * 256] end
end

HEX = HEX
  or pcall(string_format, "%x", 2 ^ 31)
    and function(x) -- returns string of 8 lowercase hexadecimal digits
      return string_format("%08x", x % 4294967296)
    end
  or function(x) -- for OpenWrt's dialect of Lua
    return string_format("%08x", (x + 2 ^ 31) % 2 ^ 32 - 2 ^ 31)
  end

local function XORA5(x, y) return XOR(x, y or 0xA5A5A5A5) % 4294967296 end

local function create_array_of_lanes()
  return { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
end

--------------------------------------------------------------------------------
-- CREATING OPTIMIZED INNER LOOP
--------------------------------------------------------------------------------

-- Inner loop functions
local sha256_feed_64, sha512_feed_128, md5_feed_64, sha1_feed_64, keccak_feed, blake2s_feed_64, blake2b_feed_128, blake3_feed_64

-- Arrays of SHA-2 "magic numbers" (in "INT64" and "FFI" branches "*_lo" arrays contain 64-bit values)
local sha2_K_lo, sha2_K_hi, sha2_H_lo, sha2_H_hi, sha3_RC_lo, sha3_RC_hi = {}, {}, {}, {}, {}, {}
local sha2_H_ext256 = { [224] = {}, [256] = sha2_H_hi }
local sha2_H_ext512_lo, sha2_H_ext512_hi = { [384] = {}, [512] = sha2_H_lo }, { [384] = {}, [512] = sha2_H_hi }
local md5_K, md5_sha1_H = {}, { 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0 }
local md5_next_shift =
  { 0, 0, 0, 0, 0, 0, 0, 0, 28, 25, 26, 27, 0, 0, 10, 9, 11, 12, 0, 15, 16, 17, 18, 0, 20, 22, 23, 21 }
local HEX64, lanes_index_base -- defined only for branches that internally use 64-bit integers: "INT64" and "FFI"
local common_W = {} -- temporary table shared between all calculations (to avoid creating new temporary table every time)
local common_W_blake2b, common_W_blake2s, v_for_blake2s_feed_64 = common_W, common_W, {}
local K_lo_modulo, hi_factor, hi_factor_keccak = 4294967296, 0, 0
local sigma = {
  { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
  { 15, 11, 5, 9, 10, 16, 14, 7, 2, 13, 1, 3, 12, 8, 6, 4 },
  { 12, 9, 13, 1, 6, 3, 16, 14, 11, 15, 4, 7, 8, 2, 10, 5 },
  { 8, 10, 4, 2, 14, 13, 12, 15, 3, 7, 6, 11, 5, 1, 16, 9 },
  { 10, 1, 6, 8, 3, 5, 11, 16, 15, 2, 12, 13, 7, 9, 4, 14 },
  { 3, 13, 7, 11, 1, 12, 9, 4, 5, 14, 8, 6, 16, 15, 2, 10 },
  { 13, 6, 2, 16, 15, 14, 5, 11, 1, 8, 7, 4, 10, 3, 9, 12 },
  { 14, 12, 8, 15, 13, 2, 4, 10, 6, 1, 16, 5, 9, 7, 3, 11 },
  { 7, 16, 15, 10, 12, 4, 1, 9, 13, 3, 14, 8, 2, 5, 11, 6 },
  { 11, 3, 9, 5, 8, 7, 2, 6, 16, 12, 10, 15, 4, 13, 14, 1 },
}
sigma[11], sigma[12] = sigma[1], sigma[2]
local perm_blake3 = {
  1,
  3,
  4,
  11,
  13,
  10,
  12,
  6,
  1,
  3,
  4,
  11,
  13,
  10,
  2,
  7,
  5,
  8,
  14,
  15,
  16,
  9,
  2,
  7,
  5,
  8,
  14,
  15,
}

local function build_keccak_format(elem)
  local keccak_format = {}
  for _, size in ipairs({ 1, 9, 13, 17, 18, 21 }) do
    keccak_format[size] = "<" .. string_rep(elem, size)
  end
  return keccak_format
end

if branch == "FFI" then
  local common_W_FFI_int32 = ffi.new("int32_t[?]", 80) -- 64 is enough for SHA256, but 80 is needed for SHA-1
  common_W_blake2s = common_W_FFI_int32
  v_for_blake2s_feed_64 = ffi.new("int32_t[?]", 16)
  perm_blake3 = ffi.new("uint8_t[?]", #perm_blake3 + 1, 0, unpack(perm_blake3))
  for j = 1, 10 do
    sigma[j] = ffi.new("uint8_t[?]", #sigma[j] + 1, 0, unpack(sigma[j]))
  end
  sigma[11], sigma[12] = sigma[1], sigma[2]

  -- SHA256 implementation for "LuaJIT with FFI" branch

  function sha256_feed_64(H, str, offs, size)
    -- offs >= 0, size >= 0, size is multiple of 64
    local W, K = common_W_FFI_int32, sha2_K_hi
    for pos = offs, offs + size - 1, 64 do
      for j = 0, 15 do
        pos = pos + 4
        local a, b, c, d = byte(str, pos - 3, pos) -- slow, but doesn't depend on endianness
        W[j] = OR(SHL(a, 24), SHL(b, 16), SHL(c, 8), d)
      end
      for j = 16, 63 do
        local a, b = W[j - 15], W[j - 2]
        W[j] =
          NORM(XOR(ROR(a, 7), ROL(a, 14), SHR(a, 3)) + XOR(ROL(b, 15), ROL(b, 13), SHR(b, 10)) + W[j - 7] + W[j - 16])
      end
      local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
      for j = 0, 63, 8 do -- Thanks to Peter Cawley for this workaround (unroll the loop to avoid "PHI shuffling too complex" due to PHIs overlap)
        local z = NORM(XOR(g, AND(e, XOR(f, g))) + XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + (W[j] + K[j + 1] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(g, AND(e, XOR(f, g))) + XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + (W[j + 1] + K[j + 2] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(g, AND(e, XOR(f, g))) + XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + (W[j + 2] + K[j + 3] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(g, AND(e, XOR(f, g))) + XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + (W[j + 3] + K[j + 4] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(g, AND(e, XOR(f, g))) + XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + (W[j + 4] + K[j + 5] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(g, AND(e, XOR(f, g))) + XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + (W[j + 5] + K[j + 6] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(g, AND(e, XOR(f, g))) + XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + (W[j + 6] + K[j + 7] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(g, AND(e, XOR(f, g))) + XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + (W[j + 7] + K[j + 8] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
      end
      H[1], H[2], H[3], H[4] = NORM(a + H[1]), NORM(b + H[2]), NORM(c + H[3]), NORM(d + H[4])
      H[5], H[6], H[7], H[8] = NORM(e + H[5]), NORM(f + H[6]), NORM(g + H[7]), NORM(h + H[8])
    end
  end

  local common_W_FFI_int64 = ffi.new("int64_t[?]", 80)
  common_W_blake2b = common_W_FFI_int64
  local int64 = ffi.typeof("int64_t")
  local int32 = ffi.typeof("int32_t")
  local uint32 = ffi.typeof("uint32_t")
  hi_factor = int64(2 ^ 32)

  if is_LuaJIT_21 then -- LuaJIT 2.1 supports bitwise 64-bit operations
    local AND64, OR64, XOR64, NOT64, SHL64, SHR64, ROL64, ROR64 -- introducing synonyms for better code readability
      =
        AND, OR, XOR, NOT, SHL, SHR, ROL, ROR
    HEX64 = HEX

    -- BLAKE2b implementation for "LuaJIT 2.1 + FFI" branch

    do
      local v = ffi.new("int64_t[?]", 16)
      local W = common_W_blake2b

      local function G(a, b, c, d, k1, k2)
        local va, vb, vc, vd = v[a], v[b], v[c], v[d]
        va = W[k1] + (va + vb)
        vd = ROR64(XOR64(vd, va), 32)
        vc = vc + vd
        vb = ROR64(XOR64(vb, vc), 24)
        va = W[k2] + (va + vb)
        vd = ROR64(XOR64(vd, va), 16)
        vc = vc + vd
        vb = ROL64(XOR64(vb, vc), 1)
        v[a], v[b], v[c], v[d] = va, vb, vc, vd
      end

      function blake2b_feed_128(H, _, str, offs, size, bytes_compressed, last_block_size, is_last_node)
        -- offs >= 0, size >= 0, size is multiple of 128
        local h1, h2, h3, h4, h5, h6, h7, h8 = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
        for pos = offs, offs + size - 1, 128 do
          if str then
            for j = 1, 16 do
              pos = pos + 8
              local a, b, c, d, e, f, g, h = byte(str, pos - 7, pos)
              W[j] = XOR64(
                OR(SHL(h, 24), SHL(g, 16), SHL(f, 8), e) * int64(2 ^ 32),
                uint32(int32(OR(SHL(d, 24), SHL(c, 16), SHL(b, 8), a)))
              )
            end
          end
          v[0x0], v[0x1], v[0x2], v[0x3], v[0x4], v[0x5], v[0x6], v[0x7] = h1, h2, h3, h4, h5, h6, h7, h8
          v[0x8], v[0x9], v[0xA], v[0xB], v[0xD], v[0xE], v[0xF] =
            sha2_H_lo[1], sha2_H_lo[2], sha2_H_lo[3], sha2_H_lo[4], sha2_H_lo[6], sha2_H_lo[7], sha2_H_lo[8]
          bytes_compressed = bytes_compressed + (last_block_size or 128)
          v[0xC] = XOR64(sha2_H_lo[5], bytes_compressed) -- t0 = low_8_bytes(bytes_compressed)
          -- t1 = high_8_bytes(bytes_compressed) = 0,  message length is always below 2^53 bytes
          if last_block_size then -- flag f0
            v[0xE] = NOT64(v[0xE])
          end
          if is_last_node then -- flag f1
            v[0xF] = NOT64(v[0xF])
          end
          for j = 1, 12 do
            local row = sigma[j]
            G(0, 4, 8, 12, row[1], row[2])
            G(1, 5, 9, 13, row[3], row[4])
            G(2, 6, 10, 14, row[5], row[6])
            G(3, 7, 11, 15, row[7], row[8])
            G(0, 5, 10, 15, row[9], row[10])
            G(1, 6, 11, 12, row[11], row[12])
            G(2, 7, 8, 13, row[13], row[14])
            G(3, 4, 9, 14, row[15], row[16])
          end
          h1 = XOR64(h1, v[0x0], v[0x8])
          h2 = XOR64(h2, v[0x1], v[0x9])
          h3 = XOR64(h3, v[0x2], v[0xA])
          h4 = XOR64(h4, v[0x3], v[0xB])
          h5 = XOR64(h5, v[0x4], v[0xC])
          h6 = XOR64(h6, v[0x5], v[0xD])
          h7 = XOR64(h7, v[0x6], v[0xE])
          h8 = XOR64(h8, v[0x7], v[0xF])
        end
        H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
        return bytes_compressed
      end
    end

    -- SHA-3 implementation for "LuaJIT 2.1 + FFI" branch

    local arr64_t = ffi.typeof("int64_t[?]")
    -- lanes array is indexed from 0
    lanes_index_base = 0
    hi_factor_keccak = int64(2 ^ 32)

    function create_array_of_lanes()
      return arr64_t(30) -- 25 + 5 for temporary usage
    end

    function keccak_feed(lanes, _, str, offs, size, block_size_in_bytes)
      -- offs >= 0, size >= 0, size is multiple of block_size_in_bytes, block_size_in_bytes is positive multiple of 8
      local RC = sha3_RC_lo
      local qwords_qty = SHR(block_size_in_bytes, 3)
      for pos = offs, offs + size - 1, block_size_in_bytes do
        for j = 0, qwords_qty - 1 do
          pos = pos + 8
          local h, g, f, e, d, c, b, a = byte(str, pos - 7, pos) -- slow, but doesn't depend on endianness
          lanes[j] = XOR64(
            lanes[j],
            OR64(
              OR(SHL(a, 24), SHL(b, 16), SHL(c, 8), d) * int64(2 ^ 32),
              uint32(int32(OR(SHL(e, 24), SHL(f, 16), SHL(g, 8), h)))
            )
          )
        end
        for round_idx = 1, 24 do
          for j = 0, 4 do
            lanes[25 + j] = XOR64(lanes[j], lanes[j + 5], lanes[j + 10], lanes[j + 15], lanes[j + 20])
          end
          local D = XOR64(lanes[25], ROL64(lanes[27], 1))
          lanes[1], lanes[6], lanes[11], lanes[16] =
            ROL64(XOR64(D, lanes[6]), 44),
            ROL64(XOR64(D, lanes[16]), 45),
            ROL64(XOR64(D, lanes[1]), 1),
            ROL64(XOR64(D, lanes[11]), 10)
          lanes[21] = ROL64(XOR64(D, lanes[21]), 2)
          D = XOR64(lanes[26], ROL64(lanes[28], 1))
          lanes[2], lanes[7], lanes[12], lanes[22] =
            ROL64(XOR64(D, lanes[12]), 43),
            ROL64(XOR64(D, lanes[22]), 61),
            ROL64(XOR64(D, lanes[7]), 6),
            ROL64(XOR64(D, lanes[2]), 62)
          lanes[17] = ROL64(XOR64(D, lanes[17]), 15)
          D = XOR64(lanes[27], ROL64(lanes[29], 1))
          lanes[3], lanes[8], lanes[18], lanes[23] =
            ROL64(XOR64(D, lanes[18]), 21),
            ROL64(XOR64(D, lanes[3]), 28),
            ROL64(XOR64(D, lanes[23]), 56),
            ROL64(XOR64(D, lanes[8]), 55)
          lanes[13] = ROL64(XOR64(D, lanes[13]), 25)
          D = XOR64(lanes[28], ROL64(lanes[25], 1))
          lanes[4], lanes[14], lanes[19], lanes[24] =
            ROL64(XOR64(D, lanes[24]), 14),
            ROL64(XOR64(D, lanes[19]), 8),
            ROL64(XOR64(D, lanes[4]), 27),
            ROL64(XOR64(D, lanes[14]), 39)
          lanes[9] = ROL64(XOR64(D, lanes[9]), 20)
          D = XOR64(lanes[29], ROL64(lanes[26], 1))
          lanes[5], lanes[10], lanes[15], lanes[20] =
            ROL64(XOR64(D, lanes[10]), 3),
            ROL64(XOR64(D, lanes[20]), 18),
            ROL64(XOR64(D, lanes[5]), 36),
            ROL64(XOR64(D, lanes[15]), 41)
          lanes[0] = XOR64(D, lanes[0])
          lanes[0], lanes[1], lanes[2], lanes[3], lanes[4] =
            XOR64(lanes[0], AND64(NOT64(lanes[1]), lanes[2]), RC[round_idx]),
            XOR64(lanes[1], AND64(NOT64(lanes[2]), lanes[3])),
            XOR64(lanes[2], AND64(NOT64(lanes[3]), lanes[4])),
            XOR64(lanes[3], AND64(NOT64(lanes[4]), lanes[0])),
            XOR64(lanes[4], AND64(NOT64(lanes[0]), lanes[1]))
          lanes[5], lanes[6], lanes[7], lanes[8], lanes[9] =
            XOR64(lanes[8], AND64(NOT64(lanes[9]), lanes[5])),
            XOR64(lanes[9], AND64(NOT64(lanes[5]), lanes[6])),
            XOR64(lanes[5], AND64(NOT64(lanes[6]), lanes[7])),
            XOR64(lanes[6], AND64(NOT64(lanes[7]), lanes[8])),
            XOR64(lanes[7], AND64(NOT64(lanes[8]), lanes[9]))
          lanes[10], lanes[11], lanes[12], lanes[13], lanes[14] =
            XOR64(lanes[11], AND64(NOT64(lanes[12]), lanes[13])),
            XOR64(lanes[12], AND64(NOT64(lanes[13]), lanes[14])),
            XOR64(lanes[13], AND64(NOT64(lanes[14]), lanes[10])),
            XOR64(lanes[14], AND64(NOT64(lanes[10]), lanes[11])),
            XOR64(lanes[10], AND64(NOT64(lanes[11]), lanes[12]))
          lanes[15], lanes[16], lanes[17], lanes[18], lanes[19] =
            XOR64(lanes[19], AND64(NOT64(lanes[15]), lanes[16])),
            XOR64(lanes[15], AND64(NOT64(lanes[16]), lanes[17])),
            XOR64(lanes[16], AND64(NOT64(lanes[17]), lanes[18])),
            XOR64(lanes[17], AND64(NOT64(lanes[18]), lanes[19])),
            XOR64(lanes[18], AND64(NOT64(lanes[19]), lanes[15]))
          lanes[20], lanes[21], lanes[22], lanes[23], lanes[24] =
            XOR64(lanes[22], AND64(NOT64(lanes[23]), lanes[24])),
            XOR64(lanes[23], AND64(NOT64(lanes[24]), lanes[20])),
            XOR64(lanes[24], AND64(NOT64(lanes[20]), lanes[21])),
            XOR64(lanes[20], AND64(NOT64(lanes[21]), lanes[22])),
            XOR64(lanes[21], AND64(NOT64(lanes[22]), lanes[23]))
        end
      end
    end

    local A5_long = 0xA5A5A5A5 * int64(2 ^ 32 + 1) -- It's impossible to use constant 0xA5A5A5A5A5A5A5A5LL because it will raise syntax error on other Lua versions

    function XORA5(long, long2) return XOR64(long, long2 or A5_long) end

    -- SHA512 implementation for "LuaJIT 2.1 + FFI" branch

    function sha512_feed_128(H, _, str, offs, size)
      -- offs >= 0, size >= 0, size is multiple of 128
      local W, K = common_W_FFI_int64, sha2_K_lo
      for pos = offs, offs + size - 1, 128 do
        for j = 0, 15 do
          pos = pos + 8
          local a, b, c, d, e, f, g, h = byte(str, pos - 7, pos) -- slow, but doesn't depend on endianness
          W[j] = OR64(
            OR(SHL(a, 24), SHL(b, 16), SHL(c, 8), d) * int64(2 ^ 32),
            uint32(int32(OR(SHL(e, 24), SHL(f, 16), SHL(g, 8), h)))
          )
        end
        for j = 16, 79 do
          local a, b = W[j - 15], W[j - 2]
          W[j] = XOR64(ROR64(a, 1), ROR64(a, 8), SHR64(a, 7))
            + XOR64(ROR64(b, 19), ROL64(b, 3), SHR64(b, 6))
            + W[j - 7]
            + W[j - 16]
        end
        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
        for j = 0, 79, 8 do
          local z = XOR64(ROR64(e, 14), ROR64(e, 18), ROL64(e, 23))
            + XOR64(g, AND64(e, XOR64(f, g)))
            + h
            + K[j + 1]
            + W[j]
          h, g, f, e = g, f, e, z + d
          d, c, b, a =
            c, b, a, XOR64(AND64(XOR64(a, b), c), AND64(a, b)) + XOR64(ROR64(a, 28), ROL64(a, 25), ROL64(a, 30)) + z
          z = XOR64(ROR64(e, 14), ROR64(e, 18), ROL64(e, 23))
            + XOR64(g, AND64(e, XOR64(f, g)))
            + h
            + K[j + 2]
            + W[j + 1]
          h, g, f, e = g, f, e, z + d
          d, c, b, a =
            c, b, a, XOR64(AND64(XOR64(a, b), c), AND64(a, b)) + XOR64(ROR64(a, 28), ROL64(a, 25), ROL64(a, 30)) + z
          z = XOR64(ROR64(e, 14), ROR64(e, 18), ROL64(e, 23))
            + XOR64(g, AND64(e, XOR64(f, g)))
            + h
            + K[j + 3]
            + W[j + 2]
          h, g, f, e = g, f, e, z + d
          d, c, b, a =
            c, b, a, XOR64(AND64(XOR64(a, b), c), AND64(a, b)) + XOR64(ROR64(a, 28), ROL64(a, 25), ROL64(a, 30)) + z
          z = XOR64(ROR64(e, 14), ROR64(e, 18), ROL64(e, 23))
            + XOR64(g, AND64(e, XOR64(f, g)))
            + h
            + K[j + 4]
            + W[j + 3]
          h, g, f, e = g, f, e, z + d
          d, c, b, a =
            c, b, a, XOR64(AND64(XOR64(a, b), c), AND64(a, b)) + XOR64(ROR64(a, 28), ROL64(a, 25), ROL64(a, 30)) + z
          z = XOR64(ROR64(e, 14), ROR64(e, 18), ROL64(e, 23))
            + XOR64(g, AND64(e, XOR64(f, g)))
            + h
            + K[j + 5]
            + W[j + 4]
          h, g, f, e = g, f, e, z + d
          d, c, b, a =
            c, b, a, XOR64(AND64(XOR64(a, b), c), AND64(a, b)) + XOR64(ROR64(a, 28), ROL64(a, 25), ROL64(a, 30)) + z
          z = XOR64(ROR64(e, 14), ROR64(e, 18), ROL64(e, 23))
            + XOR64(g, AND64(e, XOR64(f, g)))
            + h
            + K[j + 6]
            + W[j + 5]
          h, g, f, e = g, f, e, z + d
          d, c, b, a =
            c, b, a, XOR64(AND64(XOR64(a, b), c), AND64(a, b)) + XOR64(ROR64(a, 28), ROL64(a, 25), ROL64(a, 30)) + z
          z = XOR64(ROR64(e, 14), ROR64(e, 18), ROL64(e, 23))
            + XOR64(g, AND64(e, XOR64(f, g)))
            + h
            + K[j + 7]
            + W[j + 6]
          h, g, f, e = g, f, e, z + d
          d, c, b, a =
            c, b, a, XOR64(AND64(XOR64(a, b), c), AND64(a, b)) + XOR64(ROR64(a, 28), ROL64(a, 25), ROL64(a, 30)) + z
          z = XOR64(ROR64(e, 14), ROR64(e, 18), ROL64(e, 23))
            + XOR64(g, AND64(e, XOR64(f, g)))
            + h
            + K[j + 8]
            + W[j + 7]
          h, g, f, e = g, f, e, z + d
          d, c, b, a =
            c, b, a, XOR64(AND64(XOR64(a, b), c), AND64(a, b)) + XOR64(ROR64(a, 28), ROL64(a, 25), ROL64(a, 30)) + z
        end
        H[1] = a + H[1]
        H[2] = b + H[2]
        H[3] = c + H[3]
        H[4] = d + H[4]
        H[5] = e + H[5]
        H[6] = f + H[6]
        H[7] = g + H[7]
        H[8] = h + H[8]
      end
    end
  else -- LuaJIT 2.0 doesn't support 64-bit bitwise operations
    local U =
      ffi.new("union{int64_t i64; struct{int32_t " .. (ffi.abi("le") and "lo, hi" or "hi, lo") .. ";} i32;}[3]")
    -- this array of unions is used for fast splitting int64 into int32_high and int32_low

    -- "xorrific" 64-bit functions :-)
    -- int64 input is splitted into two int32 parts, some bitwise 32-bit operations are performed, finally the result is converted to int64
    -- these functions are needed because bit.* functions in LuaJIT 2.0 don't work with int64_t

    local function XORROR64_1(a)
      -- return XOR64(ROR64(a, 1), ROR64(a, 8), SHR64(a, 7))
      U[0].i64 = a
      local a_lo, a_hi = U[0].i32.lo, U[0].i32.hi
      local t_lo = XOR(SHR(a_lo, 1), SHL(a_hi, 31), SHR(a_lo, 8), SHL(a_hi, 24), SHR(a_lo, 7), SHL(a_hi, 25))
      local t_hi = XOR(SHR(a_hi, 1), SHL(a_lo, 31), SHR(a_hi, 8), SHL(a_lo, 24), SHR(a_hi, 7))
      return t_hi * int64(2 ^ 32) + uint32(int32(t_lo))
    end

    local function XORROR64_2(b)
      -- return XOR64(ROR64(b, 19), ROL64(b, 3), SHR64(b, 6))
      U[0].i64 = b
      local b_lo, b_hi = U[0].i32.lo, U[0].i32.hi
      local u_lo = XOR(SHR(b_lo, 19), SHL(b_hi, 13), SHL(b_lo, 3), SHR(b_hi, 29), SHR(b_lo, 6), SHL(b_hi, 26))
      local u_hi = XOR(SHR(b_hi, 19), SHL(b_lo, 13), SHL(b_hi, 3), SHR(b_lo, 29), SHR(b_hi, 6))
      return u_hi * int64(2 ^ 32) + uint32(int32(u_lo))
    end

    local function XORROR64_3(e)
      -- return XOR64(ROR64(e, 14), ROR64(e, 18), ROL64(e, 23))
      U[0].i64 = e
      local e_lo, e_hi = U[0].i32.lo, U[0].i32.hi
      local u_lo = XOR(SHR(e_lo, 14), SHL(e_hi, 18), SHR(e_lo, 18), SHL(e_hi, 14), SHL(e_lo, 23), SHR(e_hi, 9))
      local u_hi = XOR(SHR(e_hi, 14), SHL(e_lo, 18), SHR(e_hi, 18), SHL(e_lo, 14), SHL(e_hi, 23), SHR(e_lo, 9))
      return u_hi * int64(2 ^ 32) + uint32(int32(u_lo))
    end

    local function XORROR64_6(a)
      -- return XOR64(ROR64(a, 28), ROL64(a, 25), ROL64(a, 30))
      U[0].i64 = a
      local b_lo, b_hi = U[0].i32.lo, U[0].i32.hi
      local u_lo = XOR(SHR(b_lo, 28), SHL(b_hi, 4), SHL(b_lo, 30), SHR(b_hi, 2), SHL(b_lo, 25), SHR(b_hi, 7))
      local u_hi = XOR(SHR(b_hi, 28), SHL(b_lo, 4), SHL(b_hi, 30), SHR(b_lo, 2), SHL(b_hi, 25), SHR(b_lo, 7))
      return u_hi * int64(2 ^ 32) + uint32(int32(u_lo))
    end

    local function XORROR64_4(e, f, g)
      -- return XOR64(g, AND64(e, XOR64(f, g)))
      U[0].i64 = f
      U[1].i64 = g
      U[2].i64 = e
      local f_lo, f_hi = U[0].i32.lo, U[0].i32.hi
      local g_lo, g_hi = U[1].i32.lo, U[1].i32.hi
      local e_lo, e_hi = U[2].i32.lo, U[2].i32.hi
      local result_lo = XOR(g_lo, AND(e_lo, XOR(f_lo, g_lo)))
      local result_hi = XOR(g_hi, AND(e_hi, XOR(f_hi, g_hi)))
      return result_hi * int64(2 ^ 32) + uint32(int32(result_lo))
    end

    local function XORROR64_5(a, b, c)
      -- return XOR64(AND64(XOR64(a, b), c), AND64(a, b))
      U[0].i64 = a
      U[1].i64 = b
      U[2].i64 = c
      local a_lo, a_hi = U[0].i32.lo, U[0].i32.hi
      local b_lo, b_hi = U[1].i32.lo, U[1].i32.hi
      local c_lo, c_hi = U[2].i32.lo, U[2].i32.hi
      local result_lo = XOR(AND(XOR(a_lo, b_lo), c_lo), AND(a_lo, b_lo))
      local result_hi = XOR(AND(XOR(a_hi, b_hi), c_hi), AND(a_hi, b_hi))
      return result_hi * int64(2 ^ 32) + uint32(int32(result_lo))
    end

    local function XORROR64_7(a, b, m)
      -- return ROR64(XOR64(a, b), m), m = 1..31
      U[0].i64 = a
      U[1].i64 = b
      local a_lo, a_hi = U[0].i32.lo, U[0].i32.hi
      local b_lo, b_hi = U[1].i32.lo, U[1].i32.hi
      local c_lo, c_hi = XOR(a_lo, b_lo), XOR(a_hi, b_hi)
      local t_lo = XOR(SHR(c_lo, m), SHL(c_hi, -m))
      local t_hi = XOR(SHR(c_hi, m), SHL(c_lo, -m))
      return t_hi * int64(2 ^ 32) + uint32(int32(t_lo))
    end

    local function XORROR64_8(a, b)
      -- return ROL64(XOR64(a, b), 1)
      U[0].i64 = a
      U[1].i64 = b
      local a_lo, a_hi = U[0].i32.lo, U[0].i32.hi
      local b_lo, b_hi = U[1].i32.lo, U[1].i32.hi
      local c_lo, c_hi = XOR(a_lo, b_lo), XOR(a_hi, b_hi)
      local t_lo = XOR(SHL(c_lo, 1), SHR(c_hi, 31))
      local t_hi = XOR(SHL(c_hi, 1), SHR(c_lo, 31))
      return t_hi * int64(2 ^ 32) + uint32(int32(t_lo))
    end

    local function XORROR64_9(a, b)
      -- return ROR64(XOR64(a, b), 32)
      U[0].i64 = a
      U[1].i64 = b
      local a_lo, a_hi = U[0].i32.lo, U[0].i32.hi
      local b_lo, b_hi = U[1].i32.lo, U[1].i32.hi
      local t_hi, t_lo = XOR(a_lo, b_lo), XOR(a_hi, b_hi)
      return t_hi * int64(2 ^ 32) + uint32(int32(t_lo))
    end

    local function XOR64(a, b)
      -- return XOR64(a, b)
      U[0].i64 = a
      U[1].i64 = b
      local a_lo, a_hi = U[0].i32.lo, U[0].i32.hi
      local b_lo, b_hi = U[1].i32.lo, U[1].i32.hi
      local t_lo, t_hi = XOR(a_lo, b_lo), XOR(a_hi, b_hi)
      return t_hi * int64(2 ^ 32) + uint32(int32(t_lo))
    end

    local function XORROR64_11(a, b, c)
      -- return XOR64(a, b, c)
      U[0].i64 = a
      U[1].i64 = b
      U[2].i64 = c
      local a_lo, a_hi = U[0].i32.lo, U[0].i32.hi
      local b_lo, b_hi = U[1].i32.lo, U[1].i32.hi
      local c_lo, c_hi = U[2].i32.lo, U[2].i32.hi
      local t_lo, t_hi = XOR(a_lo, b_lo, c_lo), XOR(a_hi, b_hi, c_hi)
      return t_hi * int64(2 ^ 32) + uint32(int32(t_lo))
    end

    function XORA5(long, long2)
      -- return XOR64(long, long2 or 0xA5A5A5A5A5A5A5A5)
      U[0].i64 = long
      local lo32, hi32 = U[0].i32.lo, U[0].i32.hi
      local long2_lo, long2_hi = 0xA5A5A5A5, 0xA5A5A5A5
      if long2 then
        U[1].i64 = long2
        long2_lo, long2_hi = U[1].i32.lo, U[1].i32.hi
      end
      lo32 = XOR(lo32, long2_lo)
      hi32 = XOR(hi32, long2_hi)
      return hi32 * int64(2 ^ 32) + uint32(int32(lo32))
    end

    function HEX64(long)
      U[0].i64 = long
      return HEX(U[0].i32.hi) .. HEX(U[0].i32.lo)
    end

    -- SHA512 implementation for "LuaJIT 2.0 + FFI" branch

    function sha512_feed_128(H, _, str, offs, size)
      -- offs >= 0, size >= 0, size is multiple of 128
      local W, K = common_W_FFI_int64, sha2_K_lo
      for pos = offs, offs + size - 1, 128 do
        for j = 0, 15 do
          pos = pos + 8
          local a, b, c, d, e, f, g, h = byte(str, pos - 7, pos) -- slow, but doesn't depend on endianness
          W[j] = OR(SHL(a, 24), SHL(b, 16), SHL(c, 8), d) * int64(2 ^ 32)
            + uint32(int32(OR(SHL(e, 24), SHL(f, 16), SHL(g, 8), h)))
        end
        for j = 16, 79 do
          W[j] = XORROR64_1(W[j - 15]) + XORROR64_2(W[j - 2]) + W[j - 7] + W[j - 16]
        end
        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
        for j = 0, 79, 8 do
          local z = XORROR64_3(e) + XORROR64_4(e, f, g) + h + K[j + 1] + W[j]
          h, g, f, e = g, f, e, z + d
          d, c, b, a = c, b, a, XORROR64_5(a, b, c) + XORROR64_6(a) + z
          z = XORROR64_3(e) + XORROR64_4(e, f, g) + h + K[j + 2] + W[j + 1]
          h, g, f, e = g, f, e, z + d
          d, c, b, a = c, b, a, XORROR64_5(a, b, c) + XORROR64_6(a) + z
          z = XORROR64_3(e) + XORROR64_4(e, f, g) + h + K[j + 3] + W[j + 2]
          h, g, f, e = g, f, e, z + d
          d, c, b, a = c, b, a, XORROR64_5(a, b, c) + XORROR64_6(a) + z
          z = XORROR64_3(e) + XORROR64_4(e, f, g) + h + K[j + 4] + W[j + 3]
          h, g, f, e = g, f, e, z + d
          d, c, b, a = c, b, a, XORROR64_5(a, b, c) + XORROR64_6(a) + z
          z = XORROR64_3(e) + XORROR64_4(e, f, g) + h + K[j + 5] + W[j + 4]
          h, g, f, e = g, f, e, z + d
          d, c, b, a = c, b, a, XORROR64_5(a, b, c) + XORROR64_6(a) + z
          z = XORROR64_3(e) + XORROR64_4(e, f, g) + h + K[j + 6] + W[j + 5]
          h, g, f, e = g, f, e, z + d
          d, c, b, a = c, b, a, XORROR64_5(a, b, c) + XORROR64_6(a) + z
          z = XORROR64_3(e) + XORROR64_4(e, f, g) + h + K[j + 7] + W[j + 6]
          h, g, f, e = g, f, e, z + d
          d, c, b, a = c, b, a, XORROR64_5(a, b, c) + XORROR64_6(a) + z
          z = XORROR64_3(e) + XORROR64_4(e, f, g) + h + K[j + 8] + W[j + 7]
          h, g, f, e = g, f, e, z + d
          d, c, b, a = c, b, a, XORROR64_5(a, b, c) + XORROR64_6(a) + z
        end
        H[1] = a + H[1]
        H[2] = b + H[2]
        H[3] = c + H[3]
        H[4] = d + H[4]
        H[5] = e + H[5]
        H[6] = f + H[6]
        H[7] = g + H[7]
        H[8] = h + H[8]
      end
    end

    -- BLAKE2b implementation for "LuaJIT 2.0 + FFI" branch

    do
      local v = ffi.new("int64_t[?]", 16)
      local W = common_W_blake2b

      local function G(a, b, c, d, k1, k2)
        local va, vb, vc, vd = v[a], v[b], v[c], v[d]
        va = W[k1] + (va + vb)
        vd = XORROR64_9(vd, va)
        vc = vc + vd
        vb = XORROR64_7(vb, vc, 24)
        va = W[k2] + (va + vb)
        vd = XORROR64_7(vd, va, 16)
        vc = vc + vd
        vb = XORROR64_8(vb, vc)
        v[a], v[b], v[c], v[d] = va, vb, vc, vd
      end

      function blake2b_feed_128(H, _, str, offs, size, bytes_compressed, last_block_size, is_last_node)
        -- offs >= 0, size >= 0, size is multiple of 128
        local h1, h2, h3, h4, h5, h6, h7, h8 = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
        for pos = offs, offs + size - 1, 128 do
          if str then
            for j = 1, 16 do
              pos = pos + 8
              local a, b, c, d, e, f, g, h = byte(str, pos - 7, pos)
              W[j] = XOR64(
                OR(SHL(h, 24), SHL(g, 16), SHL(f, 8), e) * int64(2 ^ 32),
                uint32(int32(OR(SHL(d, 24), SHL(c, 16), SHL(b, 8), a)))
              )
            end
          end
          v[0x0], v[0x1], v[0x2], v[0x3], v[0x4], v[0x5], v[0x6], v[0x7] = h1, h2, h3, h4, h5, h6, h7, h8
          v[0x8], v[0x9], v[0xA], v[0xB], v[0xD], v[0xE], v[0xF] =
            sha2_H_lo[1], sha2_H_lo[2], sha2_H_lo[3], sha2_H_lo[4], sha2_H_lo[6], sha2_H_lo[7], sha2_H_lo[8]
          bytes_compressed = bytes_compressed + (last_block_size or 128)
          v[0xC] = XOR64(sha2_H_lo[5], bytes_compressed) -- t0 = low_8_bytes(bytes_compressed)
          -- t1 = high_8_bytes(bytes_compressed) = 0,  message length is always below 2^53 bytes
          if last_block_size then -- flag f0
            v[0xE] = -1 - v[0xE]
          end
          if is_last_node then -- flag f1
            v[0xF] = -1 - v[0xF]
          end
          for j = 1, 12 do
            local row = sigma[j]
            G(0, 4, 8, 12, row[1], row[2])
            G(1, 5, 9, 13, row[3], row[4])
            G(2, 6, 10, 14, row[5], row[6])
            G(3, 7, 11, 15, row[7], row[8])
            G(0, 5, 10, 15, row[9], row[10])
            G(1, 6, 11, 12, row[11], row[12])
            G(2, 7, 8, 13, row[13], row[14])
            G(3, 4, 9, 14, row[15], row[16])
          end
          h1 = XORROR64_11(h1, v[0x0], v[0x8])
          h2 = XORROR64_11(h2, v[0x1], v[0x9])
          h3 = XORROR64_11(h3, v[0x2], v[0xA])
          h4 = XORROR64_11(h4, v[0x3], v[0xB])
          h5 = XORROR64_11(h5, v[0x4], v[0xC])
          h6 = XORROR64_11(h6, v[0x5], v[0xD])
          h7 = XORROR64_11(h7, v[0x6], v[0xE])
          h8 = XORROR64_11(h8, v[0x7], v[0xF])
        end
        H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
        return bytes_compressed
      end
    end
  end

  -- MD5 implementation for "LuaJIT with FFI" branch

  function md5_feed_64(H, str, offs, size)
    -- offs >= 0, size >= 0, size is multiple of 64
    local W, K = common_W_FFI_int32, md5_K
    for pos = offs, offs + size - 1, 64 do
      for j = 0, 15 do
        pos = pos + 4
        local a, b, c, d = byte(str, pos - 3, pos) -- slow, but doesn't depend on endianness
        W[j] = OR(SHL(d, 24), SHL(c, 16), SHL(b, 8), a)
      end
      local a, b, c, d = H[1], H[2], H[3], H[4]
      for j = 0, 15, 4 do
        a, d, c, b = d, c, b, NORM(ROL(XOR(d, AND(b, XOR(c, d))) + (K[j + 1] + W[j] + a), 7) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(d, AND(b, XOR(c, d))) + (K[j + 2] + W[j + 1] + a), 12) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(d, AND(b, XOR(c, d))) + (K[j + 3] + W[j + 2] + a), 17) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(d, AND(b, XOR(c, d))) + (K[j + 4] + W[j + 3] + a), 22) + b)
      end
      for j = 16, 31, 4 do
        local g = 5 * j
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, AND(d, XOR(b, c))) + (K[j + 1] + W[AND(g + 1, 15)] + a), 5) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, AND(d, XOR(b, c))) + (K[j + 2] + W[AND(g + 6, 15)] + a), 9) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, AND(d, XOR(b, c))) + (K[j + 3] + W[AND(g - 5, 15)] + a), 14) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, AND(d, XOR(b, c))) + (K[j + 4] + W[AND(g, 15)] + a), 20) + b)
      end
      for j = 32, 47, 4 do
        local g = 3 * j
        a, d, c, b = d, c, b, NORM(ROL(XOR(b, c, d) + (K[j + 1] + W[AND(g + 5, 15)] + a), 4) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(b, c, d) + (K[j + 2] + W[AND(g + 8, 15)] + a), 11) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(b, c, d) + (K[j + 3] + W[AND(g - 5, 15)] + a), 16) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(b, c, d) + (K[j + 4] + W[AND(g - 2, 15)] + a), 23) + b)
      end
      for j = 48, 63, 4 do
        local g = 7 * j
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, OR(b, NOT(d))) + (K[j + 1] + W[AND(g, 15)] + a), 6) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, OR(b, NOT(d))) + (K[j + 2] + W[AND(g + 7, 15)] + a), 10) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, OR(b, NOT(d))) + (K[j + 3] + W[AND(g - 2, 15)] + a), 15) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, OR(b, NOT(d))) + (K[j + 4] + W[AND(g + 5, 15)] + a), 21) + b)
      end
      H[1], H[2], H[3], H[4] = NORM(a + H[1]), NORM(b + H[2]), NORM(c + H[3]), NORM(d + H[4])
    end
  end

  -- SHA-1 implementation for "LuaJIT with FFI" branch

  function sha1_feed_64(H, str, offs, size)
    -- offs >= 0, size >= 0, size is multiple of 64
    local W = common_W_FFI_int32
    for pos = offs, offs + size - 1, 64 do
      for j = 0, 15 do
        pos = pos + 4
        local a, b, c, d = byte(str, pos - 3, pos) -- slow, but doesn't depend on endianness
        W[j] = OR(SHL(a, 24), SHL(b, 16), SHL(c, 8), d)
      end
      for j = 16, 79 do
        W[j] = ROL(XOR(W[j - 3], W[j - 8], W[j - 14], W[j - 16]), 1)
      end
      local a, b, c, d, e = H[1], H[2], H[3], H[4], H[5]
      for j = 0, 19, 5 do
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(d, AND(b, XOR(d, c))) + (W[j] + 0x5A827999 + e)) -- constant = floor(2^30 * sqrt(2))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(d, AND(b, XOR(d, c))) + (W[j + 1] + 0x5A827999 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(d, AND(b, XOR(d, c))) + (W[j + 2] + 0x5A827999 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(d, AND(b, XOR(d, c))) + (W[j + 3] + 0x5A827999 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(d, AND(b, XOR(d, c))) + (W[j + 4] + 0x5A827999 + e))
      end
      for j = 20, 39, 5 do
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j] + 0x6ED9EBA1 + e)) -- 2^30 * sqrt(3)
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 1] + 0x6ED9EBA1 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 2] + 0x6ED9EBA1 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 3] + 0x6ED9EBA1 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 4] + 0x6ED9EBA1 + e))
      end
      for j = 40, 59, 5 do
        e, d, c, b, a =
          d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(AND(d, XOR(b, c)), AND(b, c)) + (W[j] + 0x8F1BBCDC + e)) -- 2^30 * sqrt(5)
        e, d, c, b, a =
          d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(AND(d, XOR(b, c)), AND(b, c)) + (W[j + 1] + 0x8F1BBCDC + e))
        e, d, c, b, a =
          d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(AND(d, XOR(b, c)), AND(b, c)) + (W[j + 2] + 0x8F1BBCDC + e))
        e, d, c, b, a =
          d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(AND(d, XOR(b, c)), AND(b, c)) + (W[j + 3] + 0x8F1BBCDC + e))
        e, d, c, b, a =
          d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(AND(d, XOR(b, c)), AND(b, c)) + (W[j + 4] + 0x8F1BBCDC + e))
      end
      for j = 60, 79, 5 do
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j] + 0xCA62C1D6 + e)) -- 2^30 * sqrt(10)
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 1] + 0xCA62C1D6 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 2] + 0xCA62C1D6 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 3] + 0xCA62C1D6 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 4] + 0xCA62C1D6 + e))
      end
      H[1], H[2], H[3], H[4], H[5] = NORM(a + H[1]), NORM(b + H[2]), NORM(c + H[3]), NORM(d + H[4]), NORM(e + H[5])
    end
  end
end

if branch == "FFI" and not is_LuaJIT_21 or branch == "LJ" then
  if branch == "FFI" then
    local arr32_t = ffi.typeof("int32_t[?]")

    function create_array_of_lanes()
      return arr32_t(31) -- 25 + 5 + 1 (due to 1-based indexing)
    end
  end

  -- SHA-3 implementation for "LuaJIT 2.0 + FFI" and "LuaJIT without FFI" branches

  function keccak_feed(lanes_lo, lanes_hi, str, offs, size, block_size_in_bytes)
    -- offs >= 0, size >= 0, size is multiple of block_size_in_bytes, block_size_in_bytes is positive multiple of 8
    local RC_lo, RC_hi = sha3_RC_lo, sha3_RC_hi
    local qwords_qty = SHR(block_size_in_bytes, 3)
    for pos = offs, offs + size - 1, block_size_in_bytes do
      for j = 1, qwords_qty do
        local a, b, c, d = byte(str, pos + 1, pos + 4)
        lanes_lo[j] = XOR(lanes_lo[j], OR(SHL(d, 24), SHL(c, 16), SHL(b, 8), a))
        pos = pos + 8
        a, b, c, d = byte(str, pos - 3, pos)
        lanes_hi[j] = XOR(lanes_hi[j], OR(SHL(d, 24), SHL(c, 16), SHL(b, 8), a))
      end
      for round_idx = 1, 24 do
        for j = 1, 5 do
          lanes_lo[25 + j] = XOR(lanes_lo[j], lanes_lo[j + 5], lanes_lo[j + 10], lanes_lo[j + 15], lanes_lo[j + 20])
        end
        for j = 1, 5 do
          lanes_hi[25 + j] = XOR(lanes_hi[j], lanes_hi[j + 5], lanes_hi[j + 10], lanes_hi[j + 15], lanes_hi[j + 20])
        end
        local D_lo = XOR(lanes_lo[26], SHL(lanes_lo[28], 1), SHR(lanes_hi[28], 31))
        local D_hi = XOR(lanes_hi[26], SHL(lanes_hi[28], 1), SHR(lanes_lo[28], 31))
        lanes_lo[2], lanes_hi[2], lanes_lo[7], lanes_hi[7], lanes_lo[12], lanes_hi[12], lanes_lo[17], lanes_hi[17] =
          XOR(SHR(XOR(D_lo, lanes_lo[7]), 20), SHL(XOR(D_hi, lanes_hi[7]), 12)),
          XOR(SHR(XOR(D_hi, lanes_hi[7]), 20), SHL(XOR(D_lo, lanes_lo[7]), 12)),
          XOR(SHR(XOR(D_lo, lanes_lo[17]), 19), SHL(XOR(D_hi, lanes_hi[17]), 13)),
          XOR(SHR(XOR(D_hi, lanes_hi[17]), 19), SHL(XOR(D_lo, lanes_lo[17]), 13)),
          XOR(SHL(XOR(D_lo, lanes_lo[2]), 1), SHR(XOR(D_hi, lanes_hi[2]), 31)),
          XOR(SHL(XOR(D_hi, lanes_hi[2]), 1), SHR(XOR(D_lo, lanes_lo[2]), 31)),
          XOR(SHL(XOR(D_lo, lanes_lo[12]), 10), SHR(XOR(D_hi, lanes_hi[12]), 22)),
          XOR(SHL(XOR(D_hi, lanes_hi[12]), 10), SHR(XOR(D_lo, lanes_lo[12]), 22))
        local L, H = XOR(D_lo, lanes_lo[22]), XOR(D_hi, lanes_hi[22])
        lanes_lo[22], lanes_hi[22] = XOR(SHL(L, 2), SHR(H, 30)), XOR(SHL(H, 2), SHR(L, 30))
        D_lo = XOR(lanes_lo[27], SHL(lanes_lo[29], 1), SHR(lanes_hi[29], 31))
        D_hi = XOR(lanes_hi[27], SHL(lanes_hi[29], 1), SHR(lanes_lo[29], 31))
        lanes_lo[3], lanes_hi[3], lanes_lo[8], lanes_hi[8], lanes_lo[13], lanes_hi[13], lanes_lo[23], lanes_hi[23] =
          XOR(SHR(XOR(D_lo, lanes_lo[13]), 21), SHL(XOR(D_hi, lanes_hi[13]), 11)),
          XOR(SHR(XOR(D_hi, lanes_hi[13]), 21), SHL(XOR(D_lo, lanes_lo[13]), 11)),
          XOR(SHR(XOR(D_lo, lanes_lo[23]), 3), SHL(XOR(D_hi, lanes_hi[23]), 29)),
          XOR(SHR(XOR(D_hi, lanes_hi[23]), 3), SHL(XOR(D_lo, lanes_lo[23]), 29)),
          XOR(SHL(XOR(D_lo, lanes_lo[8]), 6), SHR(XOR(D_hi, lanes_hi[8]), 26)),
          XOR(SHL(XOR(D_hi, lanes_hi[8]), 6), SHR(XOR(D_lo, lanes_lo[8]), 26)),
          XOR(SHR(XOR(D_lo, lanes_lo[3]), 2), SHL(XOR(D_hi, lanes_hi[3]), 30)),
          XOR(SHR(XOR(D_hi, lanes_hi[3]), 2), SHL(XOR(D_lo, lanes_lo[3]), 30))
        L, H = XOR(D_lo, lanes_lo[18]), XOR(D_hi, lanes_hi[18])
        lanes_lo[18], lanes_hi[18] = XOR(SHL(L, 15), SHR(H, 17)), XOR(SHL(H, 15), SHR(L, 17))
        D_lo = XOR(lanes_lo[28], SHL(lanes_lo[30], 1), SHR(lanes_hi[30], 31))
        D_hi = XOR(lanes_hi[28], SHL(lanes_hi[30], 1), SHR(lanes_lo[30], 31))
        lanes_lo[4], lanes_hi[4], lanes_lo[9], lanes_hi[9], lanes_lo[19], lanes_hi[19], lanes_lo[24], lanes_hi[24] =
          XOR(SHL(XOR(D_lo, lanes_lo[19]), 21), SHR(XOR(D_hi, lanes_hi[19]), 11)),
          XOR(SHL(XOR(D_hi, lanes_hi[19]), 21), SHR(XOR(D_lo, lanes_lo[19]), 11)),
          XOR(SHL(XOR(D_lo, lanes_lo[4]), 28), SHR(XOR(D_hi, lanes_hi[4]), 4)),
          XOR(SHL(XOR(D_hi, lanes_hi[4]), 28), SHR(XOR(D_lo, lanes_lo[4]), 4)),
          XOR(SHR(XOR(D_lo, lanes_lo[24]), 8), SHL(XOR(D_hi, lanes_hi[24]), 24)),
          XOR(SHR(XOR(D_hi, lanes_hi[24]), 8), SHL(XOR(D_lo, lanes_lo[24]), 24)),
          XOR(SHR(XOR(D_lo, lanes_lo[9]), 9), SHL(XOR(D_hi, lanes_hi[9]), 23)),
          XOR(SHR(XOR(D_hi, lanes_hi[9]), 9), SHL(XOR(D_lo, lanes_lo[9]), 23))
        L, H = XOR(D_lo, lanes_lo[14]), XOR(D_hi, lanes_hi[14])
        lanes_lo[14], lanes_hi[14] = XOR(SHL(L, 25), SHR(H, 7)), XOR(SHL(H, 25), SHR(L, 7))
        D_lo = XOR(lanes_lo[29], SHL(lanes_lo[26], 1), SHR(lanes_hi[26], 31))
        D_hi = XOR(lanes_hi[29], SHL(lanes_hi[26], 1), SHR(lanes_lo[26], 31))
        lanes_lo[5], lanes_hi[5], lanes_lo[15], lanes_hi[15], lanes_lo[20], lanes_hi[20], lanes_lo[25], lanes_hi[25] =
          XOR(SHL(XOR(D_lo, lanes_lo[25]), 14), SHR(XOR(D_hi, lanes_hi[25]), 18)),
          XOR(SHL(XOR(D_hi, lanes_hi[25]), 14), SHR(XOR(D_lo, lanes_lo[25]), 18)),
          XOR(SHL(XOR(D_lo, lanes_lo[20]), 8), SHR(XOR(D_hi, lanes_hi[20]), 24)),
          XOR(SHL(XOR(D_hi, lanes_hi[20]), 8), SHR(XOR(D_lo, lanes_lo[20]), 24)),
          XOR(SHL(XOR(D_lo, lanes_lo[5]), 27), SHR(XOR(D_hi, lanes_hi[5]), 5)),
          XOR(SHL(XOR(D_hi, lanes_hi[5]), 27), SHR(XOR(D_lo, lanes_lo[5]), 5)),
          XOR(SHR(XOR(D_lo, lanes_lo[15]), 25), SHL(XOR(D_hi, lanes_hi[15]), 7)),
          XOR(SHR(XOR(D_hi, lanes_hi[15]), 25), SHL(XOR(D_lo, lanes_lo[15]), 7))
        L, H = XOR(D_lo, lanes_lo[10]), XOR(D_hi, lanes_hi[10])
        lanes_lo[10], lanes_hi[10] = XOR(SHL(L, 20), SHR(H, 12)), XOR(SHL(H, 20), SHR(L, 12))
        D_lo = XOR(lanes_lo[30], SHL(lanes_lo[27], 1), SHR(lanes_hi[27], 31))
        D_hi = XOR(lanes_hi[30], SHL(lanes_hi[27], 1), SHR(lanes_lo[27], 31))
        lanes_lo[6], lanes_hi[6], lanes_lo[11], lanes_hi[11], lanes_lo[16], lanes_hi[16], lanes_lo[21], lanes_hi[21] =
          XOR(SHL(XOR(D_lo, lanes_lo[11]), 3), SHR(XOR(D_hi, lanes_hi[11]), 29)),
          XOR(SHL(XOR(D_hi, lanes_hi[11]), 3), SHR(XOR(D_lo, lanes_lo[11]), 29)),
          XOR(SHL(XOR(D_lo, lanes_lo[21]), 18), SHR(XOR(D_hi, lanes_hi[21]), 14)),
          XOR(SHL(XOR(D_hi, lanes_hi[21]), 18), SHR(XOR(D_lo, lanes_lo[21]), 14)),
          XOR(SHR(XOR(D_lo, lanes_lo[6]), 28), SHL(XOR(D_hi, lanes_hi[6]), 4)),
          XOR(SHR(XOR(D_hi, lanes_hi[6]), 28), SHL(XOR(D_lo, lanes_lo[6]), 4)),
          XOR(SHR(XOR(D_lo, lanes_lo[16]), 23), SHL(XOR(D_hi, lanes_hi[16]), 9)),
          XOR(SHR(XOR(D_hi, lanes_hi[16]), 23), SHL(XOR(D_lo, lanes_lo[16]), 9))
        lanes_lo[1], lanes_hi[1] = XOR(D_lo, lanes_lo[1]), XOR(D_hi, lanes_hi[1])
        lanes_lo[1], lanes_lo[2], lanes_lo[3], lanes_lo[4], lanes_lo[5] =
          XOR(lanes_lo[1], AND(NOT(lanes_lo[2]), lanes_lo[3]), RC_lo[round_idx]),
          XOR(lanes_lo[2], AND(NOT(lanes_lo[3]), lanes_lo[4])),
          XOR(lanes_lo[3], AND(NOT(lanes_lo[4]), lanes_lo[5])),
          XOR(lanes_lo[4], AND(NOT(lanes_lo[5]), lanes_lo[1])),
          XOR(lanes_lo[5], AND(NOT(lanes_lo[1]), lanes_lo[2]))
        lanes_lo[6], lanes_lo[7], lanes_lo[8], lanes_lo[9], lanes_lo[10] =
          XOR(lanes_lo[9], AND(NOT(lanes_lo[10]), lanes_lo[6])),
          XOR(lanes_lo[10], AND(NOT(lanes_lo[6]), lanes_lo[7])),
          XOR(lanes_lo[6], AND(NOT(lanes_lo[7]), lanes_lo[8])),
          XOR(lanes_lo[7], AND(NOT(lanes_lo[8]), lanes_lo[9])),
          XOR(lanes_lo[8], AND(NOT(lanes_lo[9]), lanes_lo[10]))
        lanes_lo[11], lanes_lo[12], lanes_lo[13], lanes_lo[14], lanes_lo[15] =
          XOR(lanes_lo[12], AND(NOT(lanes_lo[13]), lanes_lo[14])),
          XOR(lanes_lo[13], AND(NOT(lanes_lo[14]), lanes_lo[15])),
          XOR(lanes_lo[14], AND(NOT(lanes_lo[15]), lanes_lo[11])),
          XOR(lanes_lo[15], AND(NOT(lanes_lo[11]), lanes_lo[12])),
          XOR(lanes_lo[11], AND(NOT(lanes_lo[12]), lanes_lo[13]))
        lanes_lo[16], lanes_lo[17], lanes_lo[18], lanes_lo[19], lanes_lo[20] =
          XOR(lanes_lo[20], AND(NOT(lanes_lo[16]), lanes_lo[17])),
          XOR(lanes_lo[16], AND(NOT(lanes_lo[17]), lanes_lo[18])),
          XOR(lanes_lo[17], AND(NOT(lanes_lo[18]), lanes_lo[19])),
          XOR(lanes_lo[18], AND(NOT(lanes_lo[19]), lanes_lo[20])),
          XOR(lanes_lo[19], AND(NOT(lanes_lo[20]), lanes_lo[16]))
        lanes_lo[21], lanes_lo[22], lanes_lo[23], lanes_lo[24], lanes_lo[25] =
          XOR(lanes_lo[23], AND(NOT(lanes_lo[24]), lanes_lo[25])),
          XOR(lanes_lo[24], AND(NOT(lanes_lo[25]), lanes_lo[21])),
          XOR(lanes_lo[25], AND(NOT(lanes_lo[21]), lanes_lo[22])),
          XOR(lanes_lo[21], AND(NOT(lanes_lo[22]), lanes_lo[23])),
          XOR(lanes_lo[22], AND(NOT(lanes_lo[23]), lanes_lo[24]))
        lanes_hi[1], lanes_hi[2], lanes_hi[3], lanes_hi[4], lanes_hi[5] =
          XOR(lanes_hi[1], AND(NOT(lanes_hi[2]), lanes_hi[3]), RC_hi[round_idx]),
          XOR(lanes_hi[2], AND(NOT(lanes_hi[3]), lanes_hi[4])),
          XOR(lanes_hi[3], AND(NOT(lanes_hi[4]), lanes_hi[5])),
          XOR(lanes_hi[4], AND(NOT(lanes_hi[5]), lanes_hi[1])),
          XOR(lanes_hi[5], AND(NOT(lanes_hi[1]), lanes_hi[2]))
        lanes_hi[6], lanes_hi[7], lanes_hi[8], lanes_hi[9], lanes_hi[10] =
          XOR(lanes_hi[9], AND(NOT(lanes_hi[10]), lanes_hi[6])),
          XOR(lanes_hi[10], AND(NOT(lanes_hi[6]), lanes_hi[7])),
          XOR(lanes_hi[6], AND(NOT(lanes_hi[7]), lanes_hi[8])),
          XOR(lanes_hi[7], AND(NOT(lanes_hi[8]), lanes_hi[9])),
          XOR(lanes_hi[8], AND(NOT(lanes_hi[9]), lanes_hi[10]))
        lanes_hi[11], lanes_hi[12], lanes_hi[13], lanes_hi[14], lanes_hi[15] =
          XOR(lanes_hi[12], AND(NOT(lanes_hi[13]), lanes_hi[14])),
          XOR(lanes_hi[13], AND(NOT(lanes_hi[14]), lanes_hi[15])),
          XOR(lanes_hi[14], AND(NOT(lanes_hi[15]), lanes_hi[11])),
          XOR(lanes_hi[15], AND(NOT(lanes_hi[11]), lanes_hi[12])),
          XOR(lanes_hi[11], AND(NOT(lanes_hi[12]), lanes_hi[13]))
        lanes_hi[16], lanes_hi[17], lanes_hi[18], lanes_hi[19], lanes_hi[20] =
          XOR(lanes_hi[20], AND(NOT(lanes_hi[16]), lanes_hi[17])),
          XOR(lanes_hi[16], AND(NOT(lanes_hi[17]), lanes_hi[18])),
          XOR(lanes_hi[17], AND(NOT(lanes_hi[18]), lanes_hi[19])),
          XOR(lanes_hi[18], AND(NOT(lanes_hi[19]), lanes_hi[20])),
          XOR(lanes_hi[19], AND(NOT(lanes_hi[20]), lanes_hi[16]))
        lanes_hi[21], lanes_hi[22], lanes_hi[23], lanes_hi[24], lanes_hi[25] =
          XOR(lanes_hi[23], AND(NOT(lanes_hi[24]), lanes_hi[25])),
          XOR(lanes_hi[24], AND(NOT(lanes_hi[25]), lanes_hi[21])),
          XOR(lanes_hi[25], AND(NOT(lanes_hi[21]), lanes_hi[22])),
          XOR(lanes_hi[21], AND(NOT(lanes_hi[22]), lanes_hi[23])),
          XOR(lanes_hi[22], AND(NOT(lanes_hi[23]), lanes_hi[24]))
      end
    end
  end
end

if branch == "LJ" then
  -- SHA256 implementation for "LuaJIT without FFI" branch

  function sha256_feed_64(H, str, offs, size)
    -- offs >= 0, size >= 0, size is multiple of 64
    local W, K = common_W, sha2_K_hi
    for pos = offs, offs + size - 1, 64 do
      for j = 1, 16 do
        pos = pos + 4
        local a, b, c, d = byte(str, pos - 3, pos)
        W[j] = OR(SHL(a, 24), SHL(b, 16), SHL(c, 8), d)
      end
      for j = 17, 64 do
        local a, b = W[j - 15], W[j - 2]
        W[j] = NORM(
          NORM(XOR(ROR(a, 7), ROL(a, 14), SHR(a, 3)) + XOR(ROL(b, 15), ROL(b, 13), SHR(b, 10)))
            + NORM(W[j - 7] + W[j - 16])
        )
      end
      local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
      for j = 1, 64, 8 do -- Thanks to Peter Cawley for this workaround (unroll the loop to avoid "PHI shuffling too complex" due to PHIs overlap)
        local z = NORM(XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + XOR(g, AND(e, XOR(f, g))) + (K[j] + W[j] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + XOR(g, AND(e, XOR(f, g))) + (K[j + 1] + W[j + 1] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + XOR(g, AND(e, XOR(f, g))) + (K[j + 2] + W[j + 2] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + XOR(g, AND(e, XOR(f, g))) + (K[j + 3] + W[j + 3] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + XOR(g, AND(e, XOR(f, g))) + (K[j + 4] + W[j + 4] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + XOR(g, AND(e, XOR(f, g))) + (K[j + 5] + W[j + 5] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + XOR(g, AND(e, XOR(f, g))) + (K[j + 6] + W[j + 6] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
        z = NORM(XOR(ROR(e, 6), ROR(e, 11), ROL(e, 7)) + XOR(g, AND(e, XOR(f, g))) + (K[j + 7] + W[j + 7] + h))
        h, g, f, e = g, f, e, NORM(d + z)
        d, c, b, a = c, b, a, NORM(XOR(AND(a, XOR(b, c)), AND(b, c)) + XOR(ROR(a, 2), ROR(a, 13), ROL(a, 10)) + z)
      end
      H[1], H[2], H[3], H[4] = NORM(a + H[1]), NORM(b + H[2]), NORM(c + H[3]), NORM(d + H[4])
      H[5], H[6], H[7], H[8] = NORM(e + H[5]), NORM(f + H[6]), NORM(g + H[7]), NORM(h + H[8])
    end
  end

  local function ADD64_4(a_lo, a_hi, b_lo, b_hi, c_lo, c_hi, d_lo, d_hi)
    local sum_lo = a_lo % 2 ^ 32 + b_lo % 2 ^ 32 + c_lo % 2 ^ 32 + d_lo % 2 ^ 32
    local sum_hi = a_hi + b_hi + c_hi + d_hi
    local result_lo = NORM(sum_lo)
    local result_hi = NORM(sum_hi + floor(sum_lo / 2 ^ 32))
    return result_lo, result_hi
  end

  if LuaJIT_arch == "x86" then -- Special trick is required to avoid "PHI shuffling too complex" on x86 platform
    -- SHA512 implementation for "LuaJIT x86 without FFI" branch

    function sha512_feed_128(H_lo, H_hi, str, offs, size)
      -- offs >= 0, size >= 0, size is multiple of 128
      -- W1_hi, W1_lo, W2_hi, W2_lo, ...   Wk_hi = W[2*k-1], Wk_lo = W[2*k]
      local W, K_lo, K_hi = common_W, sha2_K_lo, sha2_K_hi
      for pos = offs, offs + size - 1, 128 do
        for j = 1, 16 * 2 do
          pos = pos + 4
          local a, b, c, d = byte(str, pos - 3, pos)
          W[j] = OR(SHL(a, 24), SHL(b, 16), SHL(c, 8), d)
        end
        for jj = 17 * 2, 80 * 2, 2 do
          local a_lo, a_hi = W[jj - 30], W[jj - 31]
          local t_lo =
            XOR(OR(SHR(a_lo, 1), SHL(a_hi, 31)), OR(SHR(a_lo, 8), SHL(a_hi, 24)), OR(SHR(a_lo, 7), SHL(a_hi, 25)))
          local t_hi = XOR(OR(SHR(a_hi, 1), SHL(a_lo, 31)), OR(SHR(a_hi, 8), SHL(a_lo, 24)), SHR(a_hi, 7))
          local b_lo, b_hi = W[jj - 4], W[jj - 5]
          local u_lo =
            XOR(OR(SHR(b_lo, 19), SHL(b_hi, 13)), OR(SHL(b_lo, 3), SHR(b_hi, 29)), OR(SHR(b_lo, 6), SHL(b_hi, 26)))
          local u_hi = XOR(OR(SHR(b_hi, 19), SHL(b_lo, 13)), OR(SHL(b_hi, 3), SHR(b_lo, 29)), SHR(b_hi, 6))
          W[jj], W[jj - 1] = ADD64_4(t_lo, t_hi, u_lo, u_hi, W[jj - 14], W[jj - 15], W[jj - 32], W[jj - 33])
        end
        local a_lo, b_lo, c_lo, d_lo, e_lo, f_lo, g_lo, h_lo =
          H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8]
        local a_hi, b_hi, c_hi, d_hi, e_hi, f_hi, g_hi, h_hi =
          H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8]
        local zero = 0
        for j = 1, 80 do
          local t_lo = XOR(g_lo, AND(e_lo, XOR(f_lo, g_lo)))
          local t_hi = XOR(g_hi, AND(e_hi, XOR(f_hi, g_hi)))
          local u_lo =
            XOR(OR(SHR(e_lo, 14), SHL(e_hi, 18)), OR(SHR(e_lo, 18), SHL(e_hi, 14)), OR(SHL(e_lo, 23), SHR(e_hi, 9)))
          local u_hi =
            XOR(OR(SHR(e_hi, 14), SHL(e_lo, 18)), OR(SHR(e_hi, 18), SHL(e_lo, 14)), OR(SHL(e_hi, 23), SHR(e_lo, 9)))
          local sum_lo = u_lo % 2 ^ 32 + t_lo % 2 ^ 32 + h_lo % 2 ^ 32 + K_lo[j] + W[2 * j] % 2 ^ 32
          local z_lo, z_hi = NORM(sum_lo), NORM(u_hi + t_hi + h_hi + K_hi[j] + W[2 * j - 1] + floor(sum_lo / 2 ^ 32))
          zero = zero + zero -- this thick is needed to avoid "PHI shuffling too complex" due to PHIs overlap
          h_lo, h_hi, g_lo, g_hi, f_lo, f_hi =
            OR(zero, g_lo), OR(zero, g_hi), OR(zero, f_lo), OR(zero, f_hi), OR(zero, e_lo), OR(zero, e_hi)
          local sum_lo = z_lo % 2 ^ 32 + d_lo % 2 ^ 32
          e_lo, e_hi = NORM(sum_lo), NORM(z_hi + d_hi + floor(sum_lo / 2 ^ 32))
          d_lo, d_hi, c_lo, c_hi, b_lo, b_hi =
            OR(zero, c_lo), OR(zero, c_hi), OR(zero, b_lo), OR(zero, b_hi), OR(zero, a_lo), OR(zero, a_hi)
          u_lo = XOR(OR(SHR(b_lo, 28), SHL(b_hi, 4)), OR(SHL(b_lo, 30), SHR(b_hi, 2)), OR(SHL(b_lo, 25), SHR(b_hi, 7)))
          u_hi = XOR(OR(SHR(b_hi, 28), SHL(b_lo, 4)), OR(SHL(b_hi, 30), SHR(b_lo, 2)), OR(SHL(b_hi, 25), SHR(b_lo, 7)))
          t_lo = OR(AND(d_lo, c_lo), AND(b_lo, XOR(d_lo, c_lo)))
          t_hi = OR(AND(d_hi, c_hi), AND(b_hi, XOR(d_hi, c_hi)))
          local sum_lo = z_lo % 2 ^ 32 + t_lo % 2 ^ 32 + u_lo % 2 ^ 32
          a_lo, a_hi = NORM(sum_lo), NORM(z_hi + t_hi + u_hi + floor(sum_lo / 2 ^ 32))
        end
        H_lo[1], H_hi[1] = ADD64_4(H_lo[1], H_hi[1], a_lo, a_hi, 0, 0, 0, 0)
        H_lo[2], H_hi[2] = ADD64_4(H_lo[2], H_hi[2], b_lo, b_hi, 0, 0, 0, 0)
        H_lo[3], H_hi[3] = ADD64_4(H_lo[3], H_hi[3], c_lo, c_hi, 0, 0, 0, 0)
        H_lo[4], H_hi[4] = ADD64_4(H_lo[4], H_hi[4], d_lo, d_hi, 0, 0, 0, 0)
        H_lo[5], H_hi[5] = ADD64_4(H_lo[5], H_hi[5], e_lo, e_hi, 0, 0, 0, 0)
        H_lo[6], H_hi[6] = ADD64_4(H_lo[6], H_hi[6], f_lo, f_hi, 0, 0, 0, 0)
        H_lo[7], H_hi[7] = ADD64_4(H_lo[7], H_hi[7], g_lo, g_hi, 0, 0, 0, 0)
        H_lo[8], H_hi[8] = ADD64_4(H_lo[8], H_hi[8], h_lo, h_hi, 0, 0, 0, 0)
      end
    end
  else -- all platforms except x86
    -- SHA512 implementation for "LuaJIT non-x86 without FFI" branch

    function sha512_feed_128(H_lo, H_hi, str, offs, size)
      -- offs >= 0, size >= 0, size is multiple of 128
      -- W1_hi, W1_lo, W2_hi, W2_lo, ...   Wk_hi = W[2*k-1], Wk_lo = W[2*k]
      local W, K_lo, K_hi = common_W, sha2_K_lo, sha2_K_hi
      for pos = offs, offs + size - 1, 128 do
        for j = 1, 16 * 2 do
          pos = pos + 4
          local a, b, c, d = byte(str, pos - 3, pos)
          W[j] = OR(SHL(a, 24), SHL(b, 16), SHL(c, 8), d)
        end
        for jj = 17 * 2, 80 * 2, 2 do
          local a_lo, a_hi = W[jj - 30], W[jj - 31]
          local t_lo =
            XOR(OR(SHR(a_lo, 1), SHL(a_hi, 31)), OR(SHR(a_lo, 8), SHL(a_hi, 24)), OR(SHR(a_lo, 7), SHL(a_hi, 25)))
          local t_hi = XOR(OR(SHR(a_hi, 1), SHL(a_lo, 31)), OR(SHR(a_hi, 8), SHL(a_lo, 24)), SHR(a_hi, 7))
          local b_lo, b_hi = W[jj - 4], W[jj - 5]
          local u_lo =
            XOR(OR(SHR(b_lo, 19), SHL(b_hi, 13)), OR(SHL(b_lo, 3), SHR(b_hi, 29)), OR(SHR(b_lo, 6), SHL(b_hi, 26)))
          local u_hi = XOR(OR(SHR(b_hi, 19), SHL(b_lo, 13)), OR(SHL(b_hi, 3), SHR(b_lo, 29)), SHR(b_hi, 6))
          W[jj], W[jj - 1] = ADD64_4(t_lo, t_hi, u_lo, u_hi, W[jj - 14], W[jj - 15], W[jj - 32], W[jj - 33])
        end
        local a_lo, b_lo, c_lo, d_lo, e_lo, f_lo, g_lo, h_lo =
          H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8]
        local a_hi, b_hi, c_hi, d_hi, e_hi, f_hi, g_hi, h_hi =
          H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8]
        for j = 1, 80 do
          local t_lo = XOR(g_lo, AND(e_lo, XOR(f_lo, g_lo)))
          local t_hi = XOR(g_hi, AND(e_hi, XOR(f_hi, g_hi)))
          local u_lo =
            XOR(OR(SHR(e_lo, 14), SHL(e_hi, 18)), OR(SHR(e_lo, 18), SHL(e_hi, 14)), OR(SHL(e_lo, 23), SHR(e_hi, 9)))
          local u_hi =
            XOR(OR(SHR(e_hi, 14), SHL(e_lo, 18)), OR(SHR(e_hi, 18), SHL(e_lo, 14)), OR(SHL(e_hi, 23), SHR(e_lo, 9)))
          local sum_lo = u_lo % 2 ^ 32 + t_lo % 2 ^ 32 + h_lo % 2 ^ 32 + K_lo[j] + W[2 * j] % 2 ^ 32
          local z_lo, z_hi = NORM(sum_lo), NORM(u_hi + t_hi + h_hi + K_hi[j] + W[2 * j - 1] + floor(sum_lo / 2 ^ 32))
          h_lo, h_hi, g_lo, g_hi, f_lo, f_hi = g_lo, g_hi, f_lo, f_hi, e_lo, e_hi
          local sum_lo = z_lo % 2 ^ 32 + d_lo % 2 ^ 32
          e_lo, e_hi = NORM(sum_lo), NORM(z_hi + d_hi + floor(sum_lo / 2 ^ 32))
          d_lo, d_hi, c_lo, c_hi, b_lo, b_hi = c_lo, c_hi, b_lo, b_hi, a_lo, a_hi
          u_lo = XOR(OR(SHR(b_lo, 28), SHL(b_hi, 4)), OR(SHL(b_lo, 30), SHR(b_hi, 2)), OR(SHL(b_lo, 25), SHR(b_hi, 7)))
          u_hi = XOR(OR(SHR(b_hi, 28), SHL(b_lo, 4)), OR(SHL(b_hi, 30), SHR(b_lo, 2)), OR(SHL(b_hi, 25), SHR(b_lo, 7)))
          t_lo = OR(AND(d_lo, c_lo), AND(b_lo, XOR(d_lo, c_lo)))
          t_hi = OR(AND(d_hi, c_hi), AND(b_hi, XOR(d_hi, c_hi)))
          local sum_lo = z_lo % 2 ^ 32 + u_lo % 2 ^ 32 + t_lo % 2 ^ 32
          a_lo, a_hi = NORM(sum_lo), NORM(z_hi + u_hi + t_hi + floor(sum_lo / 2 ^ 32))
        end
        H_lo[1], H_hi[1] = ADD64_4(H_lo[1], H_hi[1], a_lo, a_hi, 0, 0, 0, 0)
        H_lo[2], H_hi[2] = ADD64_4(H_lo[2], H_hi[2], b_lo, b_hi, 0, 0, 0, 0)
        H_lo[3], H_hi[3] = ADD64_4(H_lo[3], H_hi[3], c_lo, c_hi, 0, 0, 0, 0)
        H_lo[4], H_hi[4] = ADD64_4(H_lo[4], H_hi[4], d_lo, d_hi, 0, 0, 0, 0)
        H_lo[5], H_hi[5] = ADD64_4(H_lo[5], H_hi[5], e_lo, e_hi, 0, 0, 0, 0)
        H_lo[6], H_hi[6] = ADD64_4(H_lo[6], H_hi[6], f_lo, f_hi, 0, 0, 0, 0)
        H_lo[7], H_hi[7] = ADD64_4(H_lo[7], H_hi[7], g_lo, g_hi, 0, 0, 0, 0)
        H_lo[8], H_hi[8] = ADD64_4(H_lo[8], H_hi[8], h_lo, h_hi, 0, 0, 0, 0)
      end
    end
  end

  -- MD5 implementation for "LuaJIT without FFI" branch

  function md5_feed_64(H, str, offs, size)
    -- offs >= 0, size >= 0, size is multiple of 64
    local W, K = common_W, md5_K
    for pos = offs, offs + size - 1, 64 do
      for j = 1, 16 do
        pos = pos + 4
        local a, b, c, d = byte(str, pos - 3, pos)
        W[j] = OR(SHL(d, 24), SHL(c, 16), SHL(b, 8), a)
      end
      local a, b, c, d = H[1], H[2], H[3], H[4]
      for j = 1, 16, 4 do
        a, d, c, b = d, c, b, NORM(ROL(XOR(d, AND(b, XOR(c, d))) + (K[j] + W[j] + a), 7) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(d, AND(b, XOR(c, d))) + (K[j + 1] + W[j + 1] + a), 12) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(d, AND(b, XOR(c, d))) + (K[j + 2] + W[j + 2] + a), 17) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(d, AND(b, XOR(c, d))) + (K[j + 3] + W[j + 3] + a), 22) + b)
      end
      for j = 17, 32, 4 do
        local g = 5 * j - 4
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, AND(d, XOR(b, c))) + (K[j] + W[AND(g, 15) + 1] + a), 5) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, AND(d, XOR(b, c))) + (K[j + 1] + W[AND(g + 5, 15) + 1] + a), 9) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, AND(d, XOR(b, c))) + (K[j + 2] + W[AND(g + 10, 15) + 1] + a), 14) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, AND(d, XOR(b, c))) + (K[j + 3] + W[AND(g - 1, 15) + 1] + a), 20) + b)
      end
      for j = 33, 48, 4 do
        local g = 3 * j + 2
        a, d, c, b = d, c, b, NORM(ROL(XOR(b, c, d) + (K[j] + W[AND(g, 15) + 1] + a), 4) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(b, c, d) + (K[j + 1] + W[AND(g + 3, 15) + 1] + a), 11) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(b, c, d) + (K[j + 2] + W[AND(g + 6, 15) + 1] + a), 16) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(b, c, d) + (K[j + 3] + W[AND(g - 7, 15) + 1] + a), 23) + b)
      end
      for j = 49, 64, 4 do
        local g = j * 7
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, OR(b, NOT(d))) + (K[j] + W[AND(g - 7, 15) + 1] + a), 6) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, OR(b, NOT(d))) + (K[j + 1] + W[AND(g, 15) + 1] + a), 10) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, OR(b, NOT(d))) + (K[j + 2] + W[AND(g + 7, 15) + 1] + a), 15) + b)
        a, d, c, b = d, c, b, NORM(ROL(XOR(c, OR(b, NOT(d))) + (K[j + 3] + W[AND(g - 2, 15) + 1] + a), 21) + b)
      end
      H[1], H[2], H[3], H[4] = NORM(a + H[1]), NORM(b + H[2]), NORM(c + H[3]), NORM(d + H[4])
    end
  end

  -- SHA-1 implementation for "LuaJIT without FFI" branch

  function sha1_feed_64(H, str, offs, size)
    -- offs >= 0, size >= 0, size is multiple of 64
    local W = common_W
    for pos = offs, offs + size - 1, 64 do
      for j = 1, 16 do
        pos = pos + 4
        local a, b, c, d = byte(str, pos - 3, pos)
        W[j] = OR(SHL(a, 24), SHL(b, 16), SHL(c, 8), d)
      end
      for j = 17, 80 do
        W[j] = ROL(XOR(W[j - 3], W[j - 8], W[j - 14], W[j - 16]), 1)
      end
      local a, b, c, d, e = H[1], H[2], H[3], H[4], H[5]
      for j = 1, 20, 5 do
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(d, AND(b, XOR(d, c))) + (W[j] + 0x5A827999 + e)) -- constant = floor(2^30 * sqrt(2))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(d, AND(b, XOR(d, c))) + (W[j + 1] + 0x5A827999 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(d, AND(b, XOR(d, c))) + (W[j + 2] + 0x5A827999 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(d, AND(b, XOR(d, c))) + (W[j + 3] + 0x5A827999 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(d, AND(b, XOR(d, c))) + (W[j + 4] + 0x5A827999 + e))
      end
      for j = 21, 40, 5 do
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j] + 0x6ED9EBA1 + e)) -- 2^30 * sqrt(3)
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 1] + 0x6ED9EBA1 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 2] + 0x6ED9EBA1 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 3] + 0x6ED9EBA1 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 4] + 0x6ED9EBA1 + e))
      end
      for j = 41, 60, 5 do
        e, d, c, b, a =
          d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(AND(d, XOR(b, c)), AND(b, c)) + (W[j] + 0x8F1BBCDC + e)) -- 2^30 * sqrt(5)
        e, d, c, b, a =
          d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(AND(d, XOR(b, c)), AND(b, c)) + (W[j + 1] + 0x8F1BBCDC + e))
        e, d, c, b, a =
          d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(AND(d, XOR(b, c)), AND(b, c)) + (W[j + 2] + 0x8F1BBCDC + e))
        e, d, c, b, a =
          d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(AND(d, XOR(b, c)), AND(b, c)) + (W[j + 3] + 0x8F1BBCDC + e))
        e, d, c, b, a =
          d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(AND(d, XOR(b, c)), AND(b, c)) + (W[j + 4] + 0x8F1BBCDC + e))
      end
      for j = 61, 80, 5 do
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j] + 0xCA62C1D6 + e)) -- 2^30 * sqrt(10)
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 1] + 0xCA62C1D6 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 2] + 0xCA62C1D6 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 3] + 0xCA62C1D6 + e))
        e, d, c, b, a = d, c, ROR(b, 2), a, NORM(ROL(a, 5) + XOR(b, c, d) + (W[j + 4] + 0xCA62C1D6 + e))
      end
      H[1], H[2], H[3], H[4], H[5] = NORM(a + H[1]), NORM(b + H[2]), NORM(c + H[3]), NORM(d + H[4]), NORM(e + H[5])
    end
  end

  -- BLAKE2b implementation for "LuaJIT without FFI" branch

  do
    local v_lo, v_hi = {}, {}

    local function G(a, b, c, d, k1, k2)
      local W = common_W
      local va_lo, vb_lo, vc_lo, vd_lo = v_lo[a], v_lo[b], v_lo[c], v_lo[d]
      local va_hi, vb_hi, vc_hi, vd_hi = v_hi[a], v_hi[b], v_hi[c], v_hi[d]
      local z = W[2 * k1 - 1] + (va_lo % 2 ^ 32 + vb_lo % 2 ^ 32)
      va_lo = NORM(z)
      va_hi = NORM(W[2 * k1] + (va_hi + vb_hi + floor(z / 2 ^ 32)))
      vd_lo, vd_hi = XOR(vd_hi, va_hi), XOR(vd_lo, va_lo)
      z = vc_lo % 2 ^ 32 + vd_lo % 2 ^ 32
      vc_lo = NORM(z)
      vc_hi = NORM(vc_hi + vd_hi + floor(z / 2 ^ 32))
      vb_lo, vb_hi = XOR(vb_lo, vc_lo), XOR(vb_hi, vc_hi)
      vb_lo, vb_hi = XOR(SHR(vb_lo, 24), SHL(vb_hi, 8)), XOR(SHR(vb_hi, 24), SHL(vb_lo, 8))
      z = W[2 * k2 - 1] + (va_lo % 2 ^ 32 + vb_lo % 2 ^ 32)
      va_lo = NORM(z)
      va_hi = NORM(W[2 * k2] + (va_hi + vb_hi + floor(z / 2 ^ 32)))
      vd_lo, vd_hi = XOR(vd_lo, va_lo), XOR(vd_hi, va_hi)
      vd_lo, vd_hi = XOR(SHR(vd_lo, 16), SHL(vd_hi, 16)), XOR(SHR(vd_hi, 16), SHL(vd_lo, 16))
      z = vc_lo % 2 ^ 32 + vd_lo % 2 ^ 32
      vc_lo = NORM(z)
      vc_hi = NORM(vc_hi + vd_hi + floor(z / 2 ^ 32))
      vb_lo, vb_hi = XOR(vb_lo, vc_lo), XOR(vb_hi, vc_hi)
      vb_lo, vb_hi = XOR(SHL(vb_lo, 1), SHR(vb_hi, 31)), XOR(SHL(vb_hi, 1), SHR(vb_lo, 31))
      v_lo[a], v_lo[b], v_lo[c], v_lo[d] = va_lo, vb_lo, vc_lo, vd_lo
      v_hi[a], v_hi[b], v_hi[c], v_hi[d] = va_hi, vb_hi, vc_hi, vd_hi
    end

    function blake2b_feed_128(H_lo, H_hi, str, offs, size, bytes_compressed, last_block_size, is_last_node)
      -- offs >= 0, size >= 0, size is multiple of 128
      local W = common_W
      local h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo =
        H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8]
      local h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi =
        H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8]
      for pos = offs, offs + size - 1, 128 do
        if str then
          for j = 1, 32 do
            pos = pos + 4
            local a, b, c, d = byte(str, pos - 3, pos)
            W[j] = d * 2 ^ 24 + OR(SHL(c, 16), SHL(b, 8), a)
          end
        end
        v_lo[0x0], v_lo[0x1], v_lo[0x2], v_lo[0x3], v_lo[0x4], v_lo[0x5], v_lo[0x6], v_lo[0x7] =
          h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo
        v_lo[0x8], v_lo[0x9], v_lo[0xA], v_lo[0xB], v_lo[0xC], v_lo[0xD], v_lo[0xE], v_lo[0xF] =
          sha2_H_lo[1],
          sha2_H_lo[2],
          sha2_H_lo[3],
          sha2_H_lo[4],
          sha2_H_lo[5],
          sha2_H_lo[6],
          sha2_H_lo[7],
          sha2_H_lo[8]
        v_hi[0x0], v_hi[0x1], v_hi[0x2], v_hi[0x3], v_hi[0x4], v_hi[0x5], v_hi[0x6], v_hi[0x7] =
          h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi
        v_hi[0x8], v_hi[0x9], v_hi[0xA], v_hi[0xB], v_hi[0xC], v_hi[0xD], v_hi[0xE], v_hi[0xF] =
          sha2_H_hi[1],
          sha2_H_hi[2],
          sha2_H_hi[3],
          sha2_H_hi[4],
          sha2_H_hi[5],
          sha2_H_hi[6],
          sha2_H_hi[7],
          sha2_H_hi[8]
        bytes_compressed = bytes_compressed + (last_block_size or 128)
        local t0_lo = bytes_compressed % 2 ^ 32
        local t0_hi = floor(bytes_compressed / 2 ^ 32)
        v_lo[0xC] = XOR(v_lo[0xC], t0_lo) -- t0 = low_8_bytes(bytes_compressed)
        v_hi[0xC] = XOR(v_hi[0xC], t0_hi)
        -- t1 = high_8_bytes(bytes_compressed) = 0,  message length is always below 2^53 bytes
        if last_block_size then -- flag f0
          v_lo[0xE] = NOT(v_lo[0xE])
          v_hi[0xE] = NOT(v_hi[0xE])
        end
        if is_last_node then -- flag f1
          v_lo[0xF] = NOT(v_lo[0xF])
          v_hi[0xF] = NOT(v_hi[0xF])
        end
        for j = 1, 12 do
          local row = sigma[j]
          G(0, 4, 8, 12, row[1], row[2])
          G(1, 5, 9, 13, row[3], row[4])
          G(2, 6, 10, 14, row[5], row[6])
          G(3, 7, 11, 15, row[7], row[8])
          G(0, 5, 10, 15, row[9], row[10])
          G(1, 6, 11, 12, row[11], row[12])
          G(2, 7, 8, 13, row[13], row[14])
          G(3, 4, 9, 14, row[15], row[16])
        end
        h1_lo = XOR(h1_lo, v_lo[0x0], v_lo[0x8])
        h2_lo = XOR(h2_lo, v_lo[0x1], v_lo[0x9])
        h3_lo = XOR(h3_lo, v_lo[0x2], v_lo[0xA])
        h4_lo = XOR(h4_lo, v_lo[0x3], v_lo[0xB])
        h5_lo = XOR(h5_lo, v_lo[0x4], v_lo[0xC])
        h6_lo = XOR(h6_lo, v_lo[0x5], v_lo[0xD])
        h7_lo = XOR(h7_lo, v_lo[0x6], v_lo[0xE])
        h8_lo = XOR(h8_lo, v_lo[0x7], v_lo[0xF])
        h1_hi = XOR(h1_hi, v_hi[0x0], v_hi[0x8])
        h2_hi = XOR(h2_hi, v_hi[0x1], v_hi[0x9])
        h3_hi = XOR(h3_hi, v_hi[0x2], v_hi[0xA])
        h4_hi = XOR(h4_hi, v_hi[0x3], v_hi[0xB])
        h5_hi = XOR(h5_hi, v_hi[0x4], v_hi[0xC])
        h6_hi = XOR(h6_hi, v_hi[0x5], v_hi[0xD])
        h7_hi = XOR(h7_hi, v_hi[0x6], v_hi[0xE])
        h8_hi = XOR(h8_hi, v_hi[0x7], v_hi[0xF])
      end
      H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8] =
        h1_lo % 2 ^ 32,
        h2_lo % 2 ^ 32,
        h3_lo % 2 ^ 32,
        h4_lo % 2 ^ 32,
        h5_lo % 2 ^ 32,
        h6_lo % 2 ^ 32,
        h7_lo % 2 ^ 32,
        h8_lo % 2 ^ 32
      H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8] =
        h1_hi % 2 ^ 32,
        h2_hi % 2 ^ 32,
        h3_hi % 2 ^ 32,
        h4_hi % 2 ^ 32,
        h5_hi % 2 ^ 32,
        h6_hi % 2 ^ 32,
        h7_hi % 2 ^ 32,
        h8_hi % 2 ^ 32
      return bytes_compressed
    end
  end
end

if branch == "FFI" or branch == "LJ" then
  -- BLAKE2s and BLAKE3 implementations for "LuaJIT with FFI" and "LuaJIT without FFI" branches

  do
    local W = common_W_blake2s
    local v = v_for_blake2s_feed_64

    local function G(a, b, c, d, k1, k2)
      local va, vb, vc, vd = v[a], v[b], v[c], v[d]
      va = NORM(W[k1] + (va + vb))
      vd = ROR(XOR(vd, va), 16)
      vc = NORM(vc + vd)
      vb = ROR(XOR(vb, vc), 12)
      va = NORM(W[k2] + (va + vb))
      vd = ROR(XOR(vd, va), 8)
      vc = NORM(vc + vd)
      vb = ROR(XOR(vb, vc), 7)
      v[a], v[b], v[c], v[d] = va, vb, vc, vd
    end

    function blake2s_feed_64(H, str, offs, size, bytes_compressed, last_block_size, is_last_node)
      -- offs >= 0, size >= 0, size is multiple of 64
      local h1, h2, h3, h4, h5, h6, h7, h8 =
        NORM(H[1]), NORM(H[2]), NORM(H[3]), NORM(H[4]), NORM(H[5]), NORM(H[6]), NORM(H[7]), NORM(H[8])
      for pos = offs, offs + size - 1, 64 do
        if str then
          for j = 1, 16 do
            pos = pos + 4
            local a, b, c, d = byte(str, pos - 3, pos)
            W[j] = OR(SHL(d, 24), SHL(c, 16), SHL(b, 8), a)
          end
        end
        v[0x0], v[0x1], v[0x2], v[0x3], v[0x4], v[0x5], v[0x6], v[0x7] = h1, h2, h3, h4, h5, h6, h7, h8
        v[0x8], v[0x9], v[0xA], v[0xB], v[0xE], v[0xF] =
          NORM(sha2_H_hi[1]),
          NORM(sha2_H_hi[2]),
          NORM(sha2_H_hi[3]),
          NORM(sha2_H_hi[4]),
          NORM(sha2_H_hi[7]),
          NORM(sha2_H_hi[8])
        bytes_compressed = bytes_compressed + (last_block_size or 64)
        local t0 = bytes_compressed % 2 ^ 32
        local t1 = floor(bytes_compressed / 2 ^ 32)
        v[0xC] = XOR(sha2_H_hi[5], t0) -- t0 = low_4_bytes(bytes_compressed)
        v[0xD] = XOR(sha2_H_hi[6], t1) -- t1 = high_4_bytes(bytes_compressed
        if last_block_size then -- flag f0
          v[0xE] = NOT(v[0xE])
        end
        if is_last_node then -- flag f1
          v[0xF] = NOT(v[0xF])
        end
        for j = 1, 10 do
          local row = sigma[j]
          G(0, 4, 8, 12, row[1], row[2])
          G(1, 5, 9, 13, row[3], row[4])
          G(2, 6, 10, 14, row[5], row[6])
          G(3, 7, 11, 15, row[7], row[8])
          G(0, 5, 10, 15, row[9], row[10])
          G(1, 6, 11, 12, row[11], row[12])
          G(2, 7, 8, 13, row[13], row[14])
          G(3, 4, 9, 14, row[15], row[16])
        end
        h1 = XOR(h1, v[0x0], v[0x8])
        h2 = XOR(h2, v[0x1], v[0x9])
        h3 = XOR(h3, v[0x2], v[0xA])
        h4 = XOR(h4, v[0x3], v[0xB])
        h5 = XOR(h5, v[0x4], v[0xC])
        h6 = XOR(h6, v[0x5], v[0xD])
        h7 = XOR(h7, v[0x6], v[0xE])
        h8 = XOR(h8, v[0x7], v[0xF])
      end
      H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
      return bytes_compressed
    end

    function blake3_feed_64(str, offs, size, flags, chunk_index, H_in, H_out, wide_output, block_length)
      -- offs >= 0, size >= 0, size is multiple of 64
      block_length = block_length or 64
      local h1, h2, h3, h4, h5, h6, h7, h8 =
        NORM(H_in[1]),
        NORM(H_in[2]),
        NORM(H_in[3]),
        NORM(H_in[4]),
        NORM(H_in[5]),
        NORM(H_in[6]),
        NORM(H_in[7]),
        NORM(H_in[8])
      H_out = H_out or H_in
      for pos = offs, offs + size - 1, 64 do
        if str then
          for j = 1, 16 do
            pos = pos + 4
            local a, b, c, d = byte(str, pos - 3, pos)
            W[j] = OR(SHL(d, 24), SHL(c, 16), SHL(b, 8), a)
          end
        end
        v[0x0], v[0x1], v[0x2], v[0x3], v[0x4], v[0x5], v[0x6], v[0x7] = h1, h2, h3, h4, h5, h6, h7, h8
        v[0x8], v[0x9], v[0xA], v[0xB] = NORM(sha2_H_hi[1]), NORM(sha2_H_hi[2]), NORM(sha2_H_hi[3]), NORM(sha2_H_hi[4])
        v[0xC] = NORM(chunk_index % 2 ^ 32) -- t0 = low_4_bytes(chunk_index)
        v[0xD] = floor(chunk_index / 2 ^ 32) -- t1 = high_4_bytes(chunk_index)
        v[0xE], v[0xF] = block_length, flags
        for j = 1, 7 do
          G(0, 4, 8, 12, perm_blake3[j], perm_blake3[j + 14])
          G(1, 5, 9, 13, perm_blake3[j + 1], perm_blake3[j + 2])
          G(2, 6, 10, 14, perm_blake3[j + 16], perm_blake3[j + 7])
          G(3, 7, 11, 15, perm_blake3[j + 15], perm_blake3[j + 17])
          G(0, 5, 10, 15, perm_blake3[j + 21], perm_blake3[j + 5])
          G(1, 6, 11, 12, perm_blake3[j + 3], perm_blake3[j + 6])
          G(2, 7, 8, 13, perm_blake3[j + 4], perm_blake3[j + 18])
          G(3, 4, 9, 14, perm_blake3[j + 19], perm_blake3[j + 20])
        end
        if wide_output then
          H_out[9] = XOR(h1, v[0x8])
          H_out[10] = XOR(h2, v[0x9])
          H_out[11] = XOR(h3, v[0xA])
          H_out[12] = XOR(h4, v[0xB])
          H_out[13] = XOR(h5, v[0xC])
          H_out[14] = XOR(h6, v[0xD])
          H_out[15] = XOR(h7, v[0xE])
          H_out[16] = XOR(h8, v[0xF])
        end
        h1 = XOR(v[0x0], v[0x8])
        h2 = XOR(v[0x1], v[0x9])
        h3 = XOR(v[0x2], v[0xA])
        h4 = XOR(v[0x3], v[0xB])
        h5 = XOR(v[0x4], v[0xC])
        h6 = XOR(v[0x5], v[0xD])
        h7 = XOR(v[0x6], v[0xE])
        h8 = XOR(v[0x7], v[0xF])
      end
      H_out[1], H_out[2], H_out[3], H_out[4], H_out[5], H_out[6], H_out[7], H_out[8] = h1, h2, h3, h4, h5, h6, h7, h8
    end
  end
end

if branch == "INT64" then
  -- implementation for Lua 5.3/5.4

  hi_factor = 4294967296
  hi_factor_keccak = 4294967296
  lanes_index_base = 1

  HEX64, XORA5, XOR_BYTE, sha256_feed_64, sha512_feed_128, md5_feed_64, sha1_feed_64, keccak_feed, blake2s_feed_64, blake2b_feed_128, blake3_feed_64 =
    load([=[-- branch "INT64"
      local md5_next_shift, md5_K, sha2_K_lo, sha2_K_hi, build_keccak_format, sha3_RC_lo, sigma, common_W, sha2_H_lo, sha2_H_hi, perm_blake3 = ...
      local string_format, string_unpack = string.format, string.unpack

      local function HEX64(x)
         return string_format("%016x", x)
      end

      local function XORA5(x, y)
         return x ~ (y or 0xa5a5a5a5a5a5a5a5)
      end

      local function XOR_BYTE(x, y)
         return x ~ y
      end

      local function sha256_feed_64(H, str, offs, size)
         -- offs >= 0, size >= 0, size is multiple of 64
         local W, K = common_W, sha2_K_hi
         local h1, h2, h3, h4, h5, h6, h7, h8 = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
         for pos = offs + 1, offs + size, 64 do
            W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
               string_unpack(">I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4", str, pos)
            for j = 17, 64 do
               local a = W[j-15]
               a = a<<32 | a
               local b = W[j-2]
               b = b<<32 | b
               W[j] = (a>>7 ~ a>>18 ~ a>>35) + (b>>17 ~ b>>19 ~ b>>42) + W[j-7] + W[j-16] & (1<<32)-1
            end
            local a, b, c, d, e, f, g, h = h1, h2, h3, h4, h5, h6, h7, h8
            for j = 1, 64 do
               e = e<<32 | e & (1<<32)-1
               local z = (e>>6 ~ e>>11 ~ e>>25) + (g ~ e & (f ~ g)) + h + K[j] + W[j]
               h = g
               g = f
               f = e
               e = z + d
               d = c
               c = b
               b = a
               a = a<<32 | a & (1<<32)-1
               a = z + ((a ~ c) & d ~ a & c) + (a>>2 ~ a>>13 ~ a>>22)
            end
            h1 = a + h1
            h2 = b + h2
            h3 = c + h3
            h4 = d + h4
            h5 = e + h5
            h6 = f + h6
            h7 = g + h7
            h8 = h + h8
         end
         H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
      end

      local function sha512_feed_128(H, _, str, offs, size)
         -- offs >= 0, size >= 0, size is multiple of 128
         local W, K = common_W, sha2_K_lo
         local h1, h2, h3, h4, h5, h6, h7, h8 = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
         for pos = offs + 1, offs + size, 128 do
            W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
               string_unpack(">i8i8i8i8i8i8i8i8i8i8i8i8i8i8i8i8", str, pos)
            for j = 17, 80 do
               local a = W[j-15]
               local b = W[j-2]
               W[j] = (a >> 1 ~ a >> 7 ~ a >> 8 ~ a << 56 ~ a << 63) + (b >> 6 ~ b >> 19 ~ b >> 61 ~ b << 3 ~ b << 45) + W[j-7] + W[j-16]
            end
            local a, b, c, d, e, f, g, h = h1, h2, h3, h4, h5, h6, h7, h8
            for j = 1, 80 do
               local z = (e >> 14 ~ e >> 18 ~ e >> 41 ~ e << 23 ~ e << 46 ~ e << 50) + (g ~ e & (f ~ g)) + h + K[j] + W[j]
               h = g
               g = f
               f = e
               e = z + d
               d = c
               c = b
               b = a
               a = z + ((a ~ c) & d ~ a & c) + (a >> 28 ~ a >> 34 ~ a >> 39 ~ a << 25 ~ a << 30 ~ a << 36)
            end
            h1 = a + h1
            h2 = b + h2
            h3 = c + h3
            h4 = d + h4
            h5 = e + h5
            h6 = f + h6
            h7 = g + h7
            h8 = h + h8
         end
         H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
      end

      local function md5_feed_64(H, str, offs, size)
         -- offs >= 0, size >= 0, size is multiple of 64
         local W, K, md5_next_shift = common_W, md5_K, md5_next_shift
         local h1, h2, h3, h4 = H[1], H[2], H[3], H[4]
         for pos = offs + 1, offs + size, 64 do
            W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
               string_unpack("<I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4", str, pos)
            local a, b, c, d = h1, h2, h3, h4
            local s = 32-7
            for j = 1, 16 do
               local F = (d ~ b & (c ~ d)) + a + K[j] + W[j]
               a = d
               d = c
               c = b
               b = ((F<<32 | F & (1<<32)-1) >> s) + b
               s = md5_next_shift[s]
            end
            s = 32-5
            for j = 17, 32 do
               local F = (c ~ d & (b ~ c)) + a + K[j] + W[(5*j-4 & 15) + 1]
               a = d
               d = c
               c = b
               b = ((F<<32 | F & (1<<32)-1) >> s) + b
               s = md5_next_shift[s]
            end
            s = 32-4
            for j = 33, 48 do
               local F = (b ~ c ~ d) + a + K[j] + W[(3*j+2 & 15) + 1]
               a = d
               d = c
               c = b
               b = ((F<<32 | F & (1<<32)-1) >> s) + b
               s = md5_next_shift[s]
            end
            s = 32-6
            for j = 49, 64 do
               local F = (c ~ (b | ~d)) + a + K[j] + W[(j*7-7 & 15) + 1]
               a = d
               d = c
               c = b
               b = ((F<<32 | F & (1<<32)-1) >> s) + b
               s = md5_next_shift[s]
            end
            h1 = a + h1
            h2 = b + h2
            h3 = c + h3
            h4 = d + h4
         end
         H[1], H[2], H[3], H[4] = h1, h2, h3, h4
      end

      local function sha1_feed_64(H, str, offs, size)
         -- offs >= 0, size >= 0, size is multiple of 64
         local W = common_W
         local h1, h2, h3, h4, h5 = H[1], H[2], H[3], H[4], H[5]
         for pos = offs + 1, offs + size, 64 do
            W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
               string_unpack(">I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4", str, pos)
            for j = 17, 80 do
               local a = W[j-3] ~ W[j-8] ~ W[j-14] ~ W[j-16]
               W[j] = (a<<32 | a) << 1 >> 32
            end
            local a, b, c, d, e = h1, h2, h3, h4, h5
            for j = 1, 20 do
               local z = ((a<<32 | a & (1<<32)-1) >> 27) + (d ~ b & (c ~ d)) + 0x5A827999 + W[j] + e      -- constant = floor(2^30 * sqrt(2))
               e = d
               d = c
               c = (b<<32 | b & (1<<32)-1) >> 2
               b = a
               a = z
            end
            for j = 21, 40 do
               local z = ((a<<32 | a & (1<<32)-1) >> 27) + (b ~ c ~ d) + 0x6ED9EBA1 + W[j] + e            -- 2^30 * sqrt(3)
               e = d
               d = c
               c = (b<<32 | b & (1<<32)-1) >> 2
               b = a
               a = z
            end
            for j = 41, 60 do
               local z = ((a<<32 | a & (1<<32)-1) >> 27) + ((b ~ c) & d ~ b & c) + 0x8F1BBCDC + W[j] + e  -- 2^30 * sqrt(5)
               e = d
               d = c
               c = (b<<32 | b & (1<<32)-1) >> 2
               b = a
               a = z
            end
            for j = 61, 80 do
               local z = ((a<<32 | a & (1<<32)-1) >> 27) + (b ~ c ~ d) + 0xCA62C1D6 + W[j] + e            -- 2^30 * sqrt(10)
               e = d
               d = c
               c = (b<<32 | b & (1<<32)-1) >> 2
               b = a
               a = z
            end
            h1 = a + h1
            h2 = b + h2
            h3 = c + h3
            h4 = d + h4
            h5 = e + h5
         end
         H[1], H[2], H[3], H[4], H[5] = h1, h2, h3, h4, h5
      end

      local keccak_format_i8 = build_keccak_format("i8")

      local function keccak_feed(lanes, _, str, offs, size, block_size_in_bytes)
         -- offs >= 0, size >= 0, size is multiple of block_size_in_bytes, block_size_in_bytes is positive multiple of 8
         local RC = sha3_RC_lo
         local qwords_qty = block_size_in_bytes / 8
         local keccak_format = keccak_format_i8[qwords_qty]
         for pos = offs + 1, offs + size, block_size_in_bytes do
            local qwords_from_message = {string_unpack(keccak_format, str, pos)}
            for j = 1, qwords_qty do
               lanes[j] = lanes[j] ~ qwords_from_message[j]
            end
            local L01, L02, L03, L04, L05, L06, L07, L08, L09, L10, L11, L12, L13, L14, L15, L16, L17, L18, L19, L20, L21, L22, L23, L24, L25 =
               lanes[1], lanes[2], lanes[3], lanes[4], lanes[5], lanes[6], lanes[7], lanes[8], lanes[9], lanes[10], lanes[11], lanes[12], lanes[13],
               lanes[14], lanes[15], lanes[16], lanes[17], lanes[18], lanes[19], lanes[20], lanes[21], lanes[22], lanes[23], lanes[24], lanes[25]
            for round_idx = 1, 24 do
               local C1 = L01 ~ L06 ~ L11 ~ L16 ~ L21
               local C2 = L02 ~ L07 ~ L12 ~ L17 ~ L22
               local C3 = L03 ~ L08 ~ L13 ~ L18 ~ L23
               local C4 = L04 ~ L09 ~ L14 ~ L19 ~ L24
               local C5 = L05 ~ L10 ~ L15 ~ L20 ~ L25
               local D = C1 ~ C3<<1 ~ C3>>63
               local T0 = D ~ L02
               local T1 = D ~ L07
               local T2 = D ~ L12
               local T3 = D ~ L17
               local T4 = D ~ L22
               L02 = T1<<44 ~ T1>>20
               L07 = T3<<45 ~ T3>>19
               L12 = T0<<1 ~ T0>>63
               L17 = T2<<10 ~ T2>>54
               L22 = T4<<2 ~ T4>>62
               D = C2 ~ C4<<1 ~ C4>>63
               T0 = D ~ L03
               T1 = D ~ L08
               T2 = D ~ L13
               T3 = D ~ L18
               T4 = D ~ L23
               L03 = T2<<43 ~ T2>>21
               L08 = T4<<61 ~ T4>>3
               L13 = T1<<6 ~ T1>>58
               L18 = T3<<15 ~ T3>>49
               L23 = T0<<62 ~ T0>>2
               D = C3 ~ C5<<1 ~ C5>>63
               T0 = D ~ L04
               T1 = D ~ L09
               T2 = D ~ L14
               T3 = D ~ L19
               T4 = D ~ L24
               L04 = T3<<21 ~ T3>>43
               L09 = T0<<28 ~ T0>>36
               L14 = T2<<25 ~ T2>>39
               L19 = T4<<56 ~ T4>>8
               L24 = T1<<55 ~ T1>>9
               D = C4 ~ C1<<1 ~ C1>>63
               T0 = D ~ L05
               T1 = D ~ L10
               T2 = D ~ L15
               T3 = D ~ L20
               T4 = D ~ L25
               L05 = T4<<14 ~ T4>>50
               L10 = T1<<20 ~ T1>>44
               L15 = T3<<8 ~ T3>>56
               L20 = T0<<27 ~ T0>>37
               L25 = T2<<39 ~ T2>>25
               D = C5 ~ C2<<1 ~ C2>>63
               T1 = D ~ L06
               T2 = D ~ L11
               T3 = D ~ L16
               T4 = D ~ L21
               L06 = T2<<3 ~ T2>>61
               L11 = T4<<18 ~ T4>>46
               L16 = T1<<36 ~ T1>>28
               L21 = T3<<41 ~ T3>>23
               L01 = D ~ L01
               L01, L02, L03, L04, L05 = L01 ~ ~L02 & L03, L02 ~ ~L03 & L04, L03 ~ ~L04 & L05, L04 ~ ~L05 & L01, L05 ~ ~L01 & L02
               L06, L07, L08, L09, L10 = L09 ~ ~L10 & L06, L10 ~ ~L06 & L07, L06 ~ ~L07 & L08, L07 ~ ~L08 & L09, L08 ~ ~L09 & L10
               L11, L12, L13, L14, L15 = L12 ~ ~L13 & L14, L13 ~ ~L14 & L15, L14 ~ ~L15 & L11, L15 ~ ~L11 & L12, L11 ~ ~L12 & L13
               L16, L17, L18, L19, L20 = L20 ~ ~L16 & L17, L16 ~ ~L17 & L18, L17 ~ ~L18 & L19, L18 ~ ~L19 & L20, L19 ~ ~L20 & L16
               L21, L22, L23, L24, L25 = L23 ~ ~L24 & L25, L24 ~ ~L25 & L21, L25 ~ ~L21 & L22, L21 ~ ~L22 & L23, L22 ~ ~L23 & L24
               L01 = L01 ~ RC[round_idx]
            end
            lanes[1]  = L01
            lanes[2]  = L02
            lanes[3]  = L03
            lanes[4]  = L04
            lanes[5]  = L05
            lanes[6]  = L06
            lanes[7]  = L07
            lanes[8]  = L08
            lanes[9]  = L09
            lanes[10] = L10
            lanes[11] = L11
            lanes[12] = L12
            lanes[13] = L13
            lanes[14] = L14
            lanes[15] = L15
            lanes[16] = L16
            lanes[17] = L17
            lanes[18] = L18
            lanes[19] = L19
            lanes[20] = L20
            lanes[21] = L21
            lanes[22] = L22
            lanes[23] = L23
            lanes[24] = L24
            lanes[25] = L25
         end
      end

      local function blake2s_feed_64(H, str, offs, size, bytes_compressed, last_block_size, is_last_node)
         -- offs >= 0, size >= 0, size is multiple of 64
         local W = common_W
         local h1, h2, h3, h4, h5, h6, h7, h8 = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
         for pos = offs + 1, offs + size, 64 do
            if str then
               W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
                  string_unpack("<I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4", str, pos)
            end
            local v0, v1, v2, v3, v4, v5, v6, v7 = h1, h2, h3, h4, h5, h6, h7, h8
            local v8, v9, vA, vB, vC, vD, vE, vF = sha2_H_hi[1], sha2_H_hi[2], sha2_H_hi[3], sha2_H_hi[4], sha2_H_hi[5], sha2_H_hi[6], sha2_H_hi[7], sha2_H_hi[8]
            bytes_compressed = bytes_compressed + (last_block_size or 64)
            vC = vC ~ bytes_compressed        -- t0 = low_4_bytes(bytes_compressed)
            vD = vD ~ bytes_compressed >> 32  -- t1 = high_4_bytes(bytes_compressed)
            if last_block_size then  -- flag f0
               vE = ~vE
            end
            if is_last_node then  -- flag f1
               vF = ~vF
            end
            for j = 1, 10 do
               local row = sigma[j]
               v0 = v0 + v4 + W[row[1]]
               vC = vC ~ v0
               vC = (vC & (1<<32)-1) >> 16 | vC << 16
               v8 = v8 + vC
               v4 = v4 ~ v8
               v4 = (v4 & (1<<32)-1) >> 12 | v4 << 20
               v0 = v0 + v4 + W[row[2]]
               vC = vC ~ v0
               vC = (vC & (1<<32)-1) >> 8 | vC << 24
               v8 = v8 + vC
               v4 = v4 ~ v8
               v4 = (v4 & (1<<32)-1) >> 7 | v4 << 25
               v1 = v1 + v5 + W[row[3]]
               vD = vD ~ v1
               vD = (vD & (1<<32)-1) >> 16 | vD << 16
               v9 = v9 + vD
               v5 = v5 ~ v9
               v5 = (v5 & (1<<32)-1) >> 12 | v5 << 20
               v1 = v1 + v5 + W[row[4]]
               vD = vD ~ v1
               vD = (vD & (1<<32)-1) >> 8 | vD << 24
               v9 = v9 + vD
               v5 = v5 ~ v9
               v5 = (v5 & (1<<32)-1) >> 7 | v5 << 25
               v2 = v2 + v6 + W[row[5]]
               vE = vE ~ v2
               vE = (vE & (1<<32)-1) >> 16 | vE << 16
               vA = vA + vE
               v6 = v6 ~ vA
               v6 = (v6 & (1<<32)-1) >> 12 | v6 << 20
               v2 = v2 + v6 + W[row[6]]
               vE = vE ~ v2
               vE = (vE & (1<<32)-1) >> 8 | vE << 24
               vA = vA + vE
               v6 = v6 ~ vA
               v6 = (v6 & (1<<32)-1) >> 7 | v6 << 25
               v3 = v3 + v7 + W[row[7]]
               vF = vF ~ v3
               vF = (vF & (1<<32)-1) >> 16 | vF << 16
               vB = vB + vF
               v7 = v7 ~ vB
               v7 = (v7 & (1<<32)-1) >> 12 | v7 << 20
               v3 = v3 + v7 + W[row[8]]
               vF = vF ~ v3
               vF = (vF & (1<<32)-1) >> 8 | vF << 24
               vB = vB + vF
               v7 = v7 ~ vB
               v7 = (v7 & (1<<32)-1) >> 7 | v7 << 25
               v0 = v0 + v5 + W[row[9]]
               vF = vF ~ v0
               vF = (vF & (1<<32)-1) >> 16 | vF << 16
               vA = vA + vF
               v5 = v5 ~ vA
               v5 = (v5 & (1<<32)-1) >> 12 | v5 << 20
               v0 = v0 + v5 + W[row[10]]
               vF = vF ~ v0
               vF = (vF & (1<<32)-1) >> 8 | vF << 24
               vA = vA + vF
               v5 = v5 ~ vA
               v5 = (v5 & (1<<32)-1) >> 7 | v5 << 25
               v1 = v1 + v6 + W[row[11]]
               vC = vC ~ v1
               vC = (vC & (1<<32)-1) >> 16 | vC << 16
               vB = vB + vC
               v6 = v6 ~ vB
               v6 = (v6 & (1<<32)-1) >> 12 | v6 << 20
               v1 = v1 + v6 + W[row[12]]
               vC = vC ~ v1
               vC = (vC & (1<<32)-1) >> 8 | vC << 24
               vB = vB + vC
               v6 = v6 ~ vB
               v6 = (v6 & (1<<32)-1) >> 7 | v6 << 25
               v2 = v2 + v7 + W[row[13]]
               vD = vD ~ v2
               vD = (vD & (1<<32)-1) >> 16 | vD << 16
               v8 = v8 + vD
               v7 = v7 ~ v8
               v7 = (v7 & (1<<32)-1) >> 12 | v7 << 20
               v2 = v2 + v7 + W[row[14]]
               vD = vD ~ v2
               vD = (vD & (1<<32)-1) >> 8 | vD << 24
               v8 = v8 + vD
               v7 = v7 ~ v8
               v7 = (v7 & (1<<32)-1) >> 7 | v7 << 25
               v3 = v3 + v4 + W[row[15]]
               vE = vE ~ v3
               vE = (vE & (1<<32)-1) >> 16 | vE << 16
               v9 = v9 + vE
               v4 = v4 ~ v9
               v4 = (v4 & (1<<32)-1) >> 12 | v4 << 20
               v3 = v3 + v4 + W[row[16]]
               vE = vE ~ v3
               vE = (vE & (1<<32)-1) >> 8 | vE << 24
               v9 = v9 + vE
               v4 = v4 ~ v9
               v4 = (v4 & (1<<32)-1) >> 7 | v4 << 25
            end
            h1 = h1 ~ v0 ~ v8
            h2 = h2 ~ v1 ~ v9
            h3 = h3 ~ v2 ~ vA
            h4 = h4 ~ v3 ~ vB
            h5 = h5 ~ v4 ~ vC
            h6 = h6 ~ v5 ~ vD
            h7 = h7 ~ v6 ~ vE
            h8 = h8 ~ v7 ~ vF
         end
         H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
         return bytes_compressed
      end

      local function blake2b_feed_128(H, _, str, offs, size, bytes_compressed, last_block_size, is_last_node)
         -- offs >= 0, size >= 0, size is multiple of 128
         local W = common_W
         local h1, h2, h3, h4, h5, h6, h7, h8 = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
         for pos = offs + 1, offs + size, 128 do
            if str then
               W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
                  string_unpack("<i8i8i8i8i8i8i8i8i8i8i8i8i8i8i8i8", str, pos)
            end
            local v0, v1, v2, v3, v4, v5, v6, v7 = h1, h2, h3, h4, h5, h6, h7, h8
            local v8, v9, vA, vB, vC, vD, vE, vF = sha2_H_lo[1], sha2_H_lo[2], sha2_H_lo[3], sha2_H_lo[4], sha2_H_lo[5], sha2_H_lo[6], sha2_H_lo[7], sha2_H_lo[8]
            bytes_compressed = bytes_compressed + (last_block_size or 128)
            vC = vC ~ bytes_compressed  -- t0 = low_8_bytes(bytes_compressed)
            -- t1 = high_8_bytes(bytes_compressed) = 0,  message length is always below 2^53 bytes
            if last_block_size then  -- flag f0
               vE = ~vE
            end
            if is_last_node then  -- flag f1
               vF = ~vF
            end
            for j = 1, 12 do
               local row = sigma[j]
               v0 = v0 + v4 + W[row[1]]
               vC = vC ~ v0
               vC = vC >> 32 | vC << 32
               v8 = v8 + vC
               v4 = v4 ~ v8
               v4 = v4 >> 24 | v4 << 40
               v0 = v0 + v4 + W[row[2]]
               vC = vC ~ v0
               vC = vC >> 16 | vC << 48
               v8 = v8 + vC
               v4 = v4 ~ v8
               v4 = v4 >> 63 | v4 << 1
               v1 = v1 + v5 + W[row[3]]
               vD = vD ~ v1
               vD = vD >> 32 | vD << 32
               v9 = v9 + vD
               v5 = v5 ~ v9
               v5 = v5 >> 24 | v5 << 40
               v1 = v1 + v5 + W[row[4]]
               vD = vD ~ v1
               vD = vD >> 16 | vD << 48
               v9 = v9 + vD
               v5 = v5 ~ v9
               v5 = v5 >> 63 | v5 << 1
               v2 = v2 + v6 + W[row[5]]
               vE = vE ~ v2
               vE = vE >> 32 | vE << 32
               vA = vA + vE
               v6 = v6 ~ vA
               v6 = v6 >> 24 | v6 << 40
               v2 = v2 + v6 + W[row[6]]
               vE = vE ~ v2
               vE = vE >> 16 | vE << 48
               vA = vA + vE
               v6 = v6 ~ vA
               v6 = v6 >> 63 | v6 << 1
               v3 = v3 + v7 + W[row[7]]
               vF = vF ~ v3
               vF = vF >> 32 | vF << 32
               vB = vB + vF
               v7 = v7 ~ vB
               v7 = v7 >> 24 | v7 << 40
               v3 = v3 + v7 + W[row[8]]
               vF = vF ~ v3
               vF = vF >> 16 | vF << 48
               vB = vB + vF
               v7 = v7 ~ vB
               v7 = v7 >> 63 | v7 << 1
               v0 = v0 + v5 + W[row[9]]
               vF = vF ~ v0
               vF = vF >> 32 | vF << 32
               vA = vA + vF
               v5 = v5 ~ vA
               v5 = v5 >> 24 | v5 << 40
               v0 = v0 + v5 + W[row[10]]
               vF = vF ~ v0
               vF = vF >> 16 | vF << 48
               vA = vA + vF
               v5 = v5 ~ vA
               v5 = v5 >> 63 | v5 << 1
               v1 = v1 + v6 + W[row[11]]
               vC = vC ~ v1
               vC = vC >> 32 | vC << 32
               vB = vB + vC
               v6 = v6 ~ vB
               v6 = v6 >> 24 | v6 << 40
               v1 = v1 + v6 + W[row[12]]
               vC = vC ~ v1
               vC = vC >> 16 | vC << 48
               vB = vB + vC
               v6 = v6 ~ vB
               v6 = v6 >> 63 | v6 << 1
               v2 = v2 + v7 + W[row[13]]
               vD = vD ~ v2
               vD = vD >> 32 | vD << 32
               v8 = v8 + vD
               v7 = v7 ~ v8
               v7 = v7 >> 24 | v7 << 40
               v2 = v2 + v7 + W[row[14]]
               vD = vD ~ v2
               vD = vD >> 16 | vD << 48
               v8 = v8 + vD
               v7 = v7 ~ v8
               v7 = v7 >> 63 | v7 << 1
               v3 = v3 + v4 + W[row[15]]
               vE = vE ~ v3
               vE = vE >> 32 | vE << 32
               v9 = v9 + vE
               v4 = v4 ~ v9
               v4 = v4 >> 24 | v4 << 40
               v3 = v3 + v4 + W[row[16]]
               vE = vE ~ v3
               vE = vE >> 16 | vE << 48
               v9 = v9 + vE
               v4 = v4 ~ v9
               v4 = v4 >> 63 | v4 << 1
            end
            h1 = h1 ~ v0 ~ v8
            h2 = h2 ~ v1 ~ v9
            h3 = h3 ~ v2 ~ vA
            h4 = h4 ~ v3 ~ vB
            h5 = h5 ~ v4 ~ vC
            h6 = h6 ~ v5 ~ vD
            h7 = h7 ~ v6 ~ vE
            h8 = h8 ~ v7 ~ vF
         end
         H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
         return bytes_compressed
      end

      local function blake3_feed_64(str, offs, size, flags, chunk_index, H_in, H_out, wide_output, block_length)
         -- offs >= 0, size >= 0, size is multiple of 64
         block_length = block_length or 64
         local W = common_W
         local h1, h2, h3, h4, h5, h6, h7, h8 = H_in[1], H_in[2], H_in[3], H_in[4], H_in[5], H_in[6], H_in[7], H_in[8]
         H_out = H_out or H_in
         for pos = offs + 1, offs + size, 64 do
            if str then
               W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
                  string_unpack("<I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4", str, pos)
            end
            local v0, v1, v2, v3, v4, v5, v6, v7 = h1, h2, h3, h4, h5, h6, h7, h8
            local v8, v9, vA, vB = sha2_H_hi[1], sha2_H_hi[2], sha2_H_hi[3], sha2_H_hi[4]
            local t0 = chunk_index % 2^32         -- t0 = low_4_bytes(chunk_index)
            local t1 = (chunk_index - t0) / 2^32  -- t1 = high_4_bytes(chunk_index)
            local vC, vD, vE, vF = 0|t0, 0|t1, block_length, flags
            for j = 1, 7 do
               v0 = v0 + v4 + W[perm_blake3[j]]
               vC = vC ~ v0
               vC = (vC & (1<<32)-1) >> 16 | vC << 16
               v8 = v8 + vC
               v4 = v4 ~ v8
               v4 = (v4 & (1<<32)-1) >> 12 | v4 << 20
               v0 = v0 + v4 + W[perm_blake3[j + 14]]
               vC = vC ~ v0
               vC = (vC & (1<<32)-1) >> 8 | vC << 24
               v8 = v8 + vC
               v4 = v4 ~ v8
               v4 = (v4 & (1<<32)-1) >> 7 | v4 << 25
               v1 = v1 + v5 + W[perm_blake3[j + 1]]
               vD = vD ~ v1
               vD = (vD & (1<<32)-1) >> 16 | vD << 16
               v9 = v9 + vD
               v5 = v5 ~ v9
               v5 = (v5 & (1<<32)-1) >> 12 | v5 << 20
               v1 = v1 + v5 + W[perm_blake3[j + 2]]
               vD = vD ~ v1
               vD = (vD & (1<<32)-1) >> 8 | vD << 24
               v9 = v9 + vD
               v5 = v5 ~ v9
               v5 = (v5 & (1<<32)-1) >> 7 | v5 << 25
               v2 = v2 + v6 + W[perm_blake3[j + 16]]
               vE = vE ~ v2
               vE = (vE & (1<<32)-1) >> 16 | vE << 16
               vA = vA + vE
               v6 = v6 ~ vA
               v6 = (v6 & (1<<32)-1) >> 12 | v6 << 20
               v2 = v2 + v6 + W[perm_blake3[j + 7]]
               vE = vE ~ v2
               vE = (vE & (1<<32)-1) >> 8 | vE << 24
               vA = vA + vE
               v6 = v6 ~ vA
               v6 = (v6 & (1<<32)-1) >> 7 | v6 << 25
               v3 = v3 + v7 + W[perm_blake3[j + 15]]
               vF = vF ~ v3
               vF = (vF & (1<<32)-1) >> 16 | vF << 16
               vB = vB + vF
               v7 = v7 ~ vB
               v7 = (v7 & (1<<32)-1) >> 12 | v7 << 20
               v3 = v3 + v7 + W[perm_blake3[j + 17]]
               vF = vF ~ v3
               vF = (vF & (1<<32)-1) >> 8 | vF << 24
               vB = vB + vF
               v7 = v7 ~ vB
               v7 = (v7 & (1<<32)-1) >> 7 | v7 << 25
               v0 = v0 + v5 + W[perm_blake3[j + 21]]
               vF = vF ~ v0
               vF = (vF & (1<<32)-1) >> 16 | vF << 16
               vA = vA + vF
               v5 = v5 ~ vA
               v5 = (v5 & (1<<32)-1) >> 12 | v5 << 20
               v0 = v0 + v5 + W[perm_blake3[j + 5]]
               vF = vF ~ v0
               vF = (vF & (1<<32)-1) >> 8 | vF << 24
               vA = vA + vF
               v5 = v5 ~ vA
               v5 = (v5 & (1<<32)-1) >> 7 | v5 << 25
               v1 = v1 + v6 + W[perm_blake3[j + 3]]
               vC = vC ~ v1
               vC = (vC & (1<<32)-1) >> 16 | vC << 16
               vB = vB + vC
               v6 = v6 ~ vB
               v6 = (v6 & (1<<32)-1) >> 12 | v6 << 20
               v1 = v1 + v6 + W[perm_blake3[j + 6]]
               vC = vC ~ v1
               vC = (vC & (1<<32)-1) >> 8 | vC << 24
               vB = vB + vC
               v6 = v6 ~ vB
               v6 = (v6 & (1<<32)-1) >> 7 | v6 << 25
               v2 = v2 + v7 + W[perm_blake3[j + 4]]
               vD = vD ~ v2
               vD = (vD & (1<<32)-1) >> 16 | vD << 16
               v8 = v8 + vD
               v7 = v7 ~ v8
               v7 = (v7 & (1<<32)-1) >> 12 | v7 << 20
               v2 = v2 + v7 + W[perm_blake3[j + 18]]
               vD = vD ~ v2
               vD = (vD & (1<<32)-1) >> 8 | vD << 24
               v8 = v8 + vD
               v7 = v7 ~ v8
               v7 = (v7 & (1<<32)-1) >> 7 | v7 << 25
               v3 = v3 + v4 + W[perm_blake3[j + 19]]
               vE = vE ~ v3
               vE = (vE & (1<<32)-1) >> 16 | vE << 16
               v9 = v9 + vE
               v4 = v4 ~ v9
               v4 = (v4 & (1<<32)-1) >> 12 | v4 << 20
               v3 = v3 + v4 + W[perm_blake3[j + 20]]
               vE = vE ~ v3
               vE = (vE & (1<<32)-1) >> 8 | vE << 24
               v9 = v9 + vE
               v4 = v4 ~ v9
               v4 = (v4 & (1<<32)-1) >> 7 | v4 << 25
            end
            if wide_output then
               H_out[ 9] = h1 ~ v8
               H_out[10] = h2 ~ v9
               H_out[11] = h3 ~ vA
               H_out[12] = h4 ~ vB
               H_out[13] = h5 ~ vC
               H_out[14] = h6 ~ vD
               H_out[15] = h7 ~ vE
               H_out[16] = h8 ~ vF
            end
            h1 = v0 ~ v8
            h2 = v1 ~ v9
            h3 = v2 ~ vA
            h4 = v3 ~ vB
            h5 = v4 ~ vC
            h6 = v5 ~ vD
            h7 = v6 ~ vE
            h8 = v7 ~ vF
         end
         H_out[1], H_out[2], H_out[3], H_out[4], H_out[5], H_out[6], H_out[7], H_out[8] = h1, h2, h3, h4, h5, h6, h7, h8
      end

      return HEX64, XORA5, XOR_BYTE, sha256_feed_64, sha512_feed_128, md5_feed_64, sha1_feed_64, keccak_feed, blake2s_feed_64, blake2b_feed_128, blake3_feed_64
   ]=])(
      md5_next_shift,
      md5_K,
      sha2_K_lo,
      sha2_K_hi,
      build_keccak_format,
      sha3_RC_lo,
      sigma,
      common_W,
      sha2_H_lo,
      sha2_H_hi,
      perm_blake3
    )
end

if branch == "INT32" then
  -- implementation for Lua 5.3/5.4 having non-standard numbers config "int32"+"double" (built with LUA_INT_TYPE=LUA_INT_INT)

  K_lo_modulo = 2 ^ 32

  function HEX(x) -- returns string of 8 lowercase hexadecimal digits
    return string_format("%08x", x)
  end

  XORA5, XOR_BYTE, sha256_feed_64, sha512_feed_128, md5_feed_64, sha1_feed_64, keccak_feed, blake2s_feed_64, blake2b_feed_128, blake3_feed_64 =
    load([=[-- branch "INT32"
      local md5_next_shift, md5_K, sha2_K_lo, sha2_K_hi, build_keccak_format, sha3_RC_lo, sha3_RC_hi, sigma, common_W, sha2_H_lo, sha2_H_hi, perm_blake3 = ...
      local string_unpack, floor = string.unpack, math.floor

      local function XORA5(x, y)
         return x ~ (y and (y + 2^31) % 2^32 - 2^31 or 0xA5A5A5A5)
      end

      local function XOR_BYTE(x, y)
         return x ~ y
      end

      local function sha256_feed_64(H, str, offs, size)
         -- offs >= 0, size >= 0, size is multiple of 64
         local W, K = common_W, sha2_K_hi
         local h1, h2, h3, h4, h5, h6, h7, h8 = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
         for pos = offs + 1, offs + size, 64 do
            W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
               string_unpack(">i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4", str, pos)
            for j = 17, 64 do
               local a, b = W[j-15], W[j-2]
               W[j] = (a>>7 ~ a<<25 ~ a<<14 ~ a>>18 ~ a>>3) + (b<<15 ~ b>>17 ~ b<<13 ~ b>>19 ~ b>>10) + W[j-7] + W[j-16]
            end
            local a, b, c, d, e, f, g, h = h1, h2, h3, h4, h5, h6, h7, h8
            for j = 1, 64 do
               local z = (e>>6 ~ e<<26 ~ e>>11 ~ e<<21 ~ e>>25 ~ e<<7) + (g ~ e & (f ~ g)) + h + K[j] + W[j]
               h = g
               g = f
               f = e
               e = z + d
               d = c
               c = b
               b = a
               a = z + ((a ~ c) & d ~ a & c) + (a>>2 ~ a<<30 ~ a>>13 ~ a<<19 ~ a<<10 ~ a>>22)
            end
            h1 = a + h1
            h2 = b + h2
            h3 = c + h3
            h4 = d + h4
            h5 = e + h5
            h6 = f + h6
            h7 = g + h7
            h8 = h + h8
         end
         H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
      end

      local function sha512_feed_128(H_lo, H_hi, str, offs, size)
         -- offs >= 0, size >= 0, size is multiple of 128
         -- W1_hi, W1_lo, W2_hi, W2_lo, ...   Wk_hi = W[2*k-1], Wk_lo = W[2*k]
         local floor, W, K_lo, K_hi = floor, common_W, sha2_K_lo, sha2_K_hi
         local h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo = H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8]
         local h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi = H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8]
         for pos = offs + 1, offs + size, 128 do
            W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16],
               W[17], W[18], W[19], W[20], W[21], W[22], W[23], W[24], W[25], W[26], W[27], W[28], W[29], W[30], W[31], W[32] =
               string_unpack(">i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4", str, pos)
            for jj = 17*2, 80*2, 2 do
               local a_lo, a_hi, b_lo, b_hi = W[jj-30], W[jj-31], W[jj-4], W[jj-5]
               local tmp =
                  (a_lo>>1 ~ a_hi<<31 ~ a_lo>>8 ~ a_hi<<24 ~ a_lo>>7 ~ a_hi<<25) % 2^32
                  + (b_lo>>19 ~ b_hi<<13 ~ b_lo<<3 ~ b_hi>>29 ~ b_lo>>6 ~ b_hi<<26) % 2^32
                  + W[jj-14] % 2^32 + W[jj-32] % 2^32
               W[jj-1] =
                  (a_hi>>1 ~ a_lo<<31 ~ a_hi>>8 ~ a_lo<<24 ~ a_hi>>7)
                  + (b_hi>>19 ~ b_lo<<13 ~ b_hi<<3 ~ b_lo>>29 ~ b_hi>>6)
                  + W[jj-15] + W[jj-33] + floor(tmp / 2^32)
               W[jj] = 0|((tmp + 2^31) % 2^32 - 2^31)
            end
            local a_lo, b_lo, c_lo, d_lo, e_lo, f_lo, g_lo, h_lo = h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo
            local a_hi, b_hi, c_hi, d_hi, e_hi, f_hi, g_hi, h_hi = h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi
            for j = 1, 80 do
               local jj = 2*j
               local z_lo = (e_lo>>14 ~ e_hi<<18 ~ e_lo>>18 ~ e_hi<<14 ~ e_lo<<23 ~ e_hi>>9) % 2^32 + (g_lo ~ e_lo & (f_lo ~ g_lo)) % 2^32 + h_lo % 2^32 + K_lo[j] + W[jj] % 2^32
               local z_hi = (e_hi>>14 ~ e_lo<<18 ~ e_hi>>18 ~ e_lo<<14 ~ e_hi<<23 ~ e_lo>>9) + (g_hi ~ e_hi & (f_hi ~ g_hi)) + h_hi + K_hi[j] + W[jj-1] + floor(z_lo / 2^32)
               z_lo = z_lo % 2^32
               h_lo = g_lo;  h_hi = g_hi
               g_lo = f_lo;  g_hi = f_hi
               f_lo = e_lo;  f_hi = e_hi
               e_lo = z_lo + d_lo % 2^32
               e_hi = z_hi + d_hi + floor(e_lo / 2^32)
               e_lo = 0|((e_lo + 2^31) % 2^32 - 2^31)
               d_lo = c_lo;  d_hi = c_hi
               c_lo = b_lo;  c_hi = b_hi
               b_lo = a_lo;  b_hi = a_hi
               z_lo = z_lo + (d_lo & c_lo ~ b_lo & (d_lo ~ c_lo)) % 2^32 + (b_lo>>28 ~ b_hi<<4 ~ b_lo<<30 ~ b_hi>>2 ~ b_lo<<25 ~ b_hi>>7) % 2^32
               a_hi = z_hi + (d_hi & c_hi ~ b_hi & (d_hi ~ c_hi)) + (b_hi>>28 ~ b_lo<<4 ~ b_hi<<30 ~ b_lo>>2 ~ b_hi<<25 ~ b_lo>>7) + floor(z_lo / 2^32)
               a_lo = 0|((z_lo + 2^31) % 2^32 - 2^31)
            end
            a_lo = h1_lo % 2^32 + a_lo % 2^32
            h1_hi = h1_hi + a_hi + floor(a_lo / 2^32)
            h1_lo = 0|((a_lo + 2^31) % 2^32 - 2^31)
            a_lo = h2_lo % 2^32 + b_lo % 2^32
            h2_hi = h2_hi + b_hi + floor(a_lo / 2^32)
            h2_lo = 0|((a_lo + 2^31) % 2^32 - 2^31)
            a_lo = h3_lo % 2^32 + c_lo % 2^32
            h3_hi = h3_hi + c_hi + floor(a_lo / 2^32)
            h3_lo = 0|((a_lo + 2^31) % 2^32 - 2^31)
            a_lo = h4_lo % 2^32 + d_lo % 2^32
            h4_hi = h4_hi + d_hi + floor(a_lo / 2^32)
            h4_lo = 0|((a_lo + 2^31) % 2^32 - 2^31)
            a_lo = h5_lo % 2^32 + e_lo % 2^32
            h5_hi = h5_hi + e_hi + floor(a_lo / 2^32)
            h5_lo = 0|((a_lo + 2^31) % 2^32 - 2^31)
            a_lo = h6_lo % 2^32 + f_lo % 2^32
            h6_hi = h6_hi + f_hi + floor(a_lo / 2^32)
            h6_lo = 0|((a_lo + 2^31) % 2^32 - 2^31)
            a_lo = h7_lo % 2^32 + g_lo % 2^32
            h7_hi = h7_hi + g_hi + floor(a_lo / 2^32)
            h7_lo = 0|((a_lo + 2^31) % 2^32 - 2^31)
            a_lo = h8_lo % 2^32 + h_lo % 2^32
            h8_hi = h8_hi + h_hi + floor(a_lo / 2^32)
            h8_lo = 0|((a_lo + 2^31) % 2^32 - 2^31)
         end
         H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8] = h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo
         H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8] = h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi
      end

      local function md5_feed_64(H, str, offs, size)
         -- offs >= 0, size >= 0, size is multiple of 64
         local W, K, md5_next_shift = common_W, md5_K, md5_next_shift
         local h1, h2, h3, h4 = H[1], H[2], H[3], H[4]
         for pos = offs + 1, offs + size, 64 do
            W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
               string_unpack("<i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4", str, pos)
            local a, b, c, d = h1, h2, h3, h4
            local s = 32-7
            for j = 1, 16 do
               local F = (d ~ b & (c ~ d)) + a + K[j] + W[j]
               a = d
               d = c
               c = b
               b = (F << 32-s | F>>s) + b
               s = md5_next_shift[s]
            end
            s = 32-5
            for j = 17, 32 do
               local F = (c ~ d & (b ~ c)) + a + K[j] + W[(5*j-4 & 15) + 1]
               a = d
               d = c
               c = b
               b = (F << 32-s | F>>s) + b
               s = md5_next_shift[s]
            end
            s = 32-4
            for j = 33, 48 do
               local F = (b ~ c ~ d) + a + K[j] + W[(3*j+2 & 15) + 1]
               a = d
               d = c
               c = b
               b = (F << 32-s | F>>s) + b
               s = md5_next_shift[s]
            end
            s = 32-6
            for j = 49, 64 do
               local F = (c ~ (b | ~d)) + a + K[j] + W[(j*7-7 & 15) + 1]
               a = d
               d = c
               c = b
               b = (F << 32-s | F>>s) + b
               s = md5_next_shift[s]
            end
            h1 = a + h1
            h2 = b + h2
            h3 = c + h3
            h4 = d + h4
         end
         H[1], H[2], H[3], H[4] = h1, h2, h3, h4
      end

      local function sha1_feed_64(H, str, offs, size)
         -- offs >= 0, size >= 0, size is multiple of 64
         local W = common_W
         local h1, h2, h3, h4, h5 = H[1], H[2], H[3], H[4], H[5]
         for pos = offs + 1, offs + size, 64 do
            W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
               string_unpack(">i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4", str, pos)
            for j = 17, 80 do
               local a = W[j-3] ~ W[j-8] ~ W[j-14] ~ W[j-16]
               W[j] = a << 1 ~ a >> 31
            end
            local a, b, c, d, e = h1, h2, h3, h4, h5
            for j = 1, 20 do
               local z = (a << 5 ~ a >> 27) + (d ~ b & (c ~ d)) + 0x5A827999 + W[j] + e      -- constant = floor(2^30 * sqrt(2))
               e = d
               d = c
               c = b << 30 ~ b >> 2
               b = a
               a = z
            end
            for j = 21, 40 do
               local z = (a << 5 ~ a >> 27) + (b ~ c ~ d) + 0x6ED9EBA1 + W[j] + e            -- 2^30 * sqrt(3)
               e = d
               d = c
               c = b << 30 ~ b >> 2
               b = a
               a = z
            end
            for j = 41, 60 do
               local z = (a << 5 ~ a >> 27) + ((b ~ c) & d ~ b & c) + 0x8F1BBCDC + W[j] + e  -- 2^30 * sqrt(5)
               e = d
               d = c
               c = b << 30 ~ b >> 2
               b = a
               a = z
            end
            for j = 61, 80 do
               local z = (a << 5 ~ a >> 27) + (b ~ c ~ d) + 0xCA62C1D6 + W[j] + e            -- 2^30 * sqrt(10)
               e = d
               d = c
               c = b << 30 ~ b >> 2
               b = a
               a = z
            end
            h1 = a + h1
            h2 = b + h2
            h3 = c + h3
            h4 = d + h4
            h5 = e + h5
         end
         H[1], H[2], H[3], H[4], H[5] = h1, h2, h3, h4, h5
      end

      local keccak_format_i4i4 = build_keccak_format("i4i4")

      local function keccak_feed(lanes_lo, lanes_hi, str, offs, size, block_size_in_bytes)
         -- offs >= 0, size >= 0, size is multiple of block_size_in_bytes, block_size_in_bytes is positive multiple of 8
         local RC_lo, RC_hi = sha3_RC_lo, sha3_RC_hi
         local qwords_qty = block_size_in_bytes / 8
         local keccak_format = keccak_format_i4i4[qwords_qty]
         for pos = offs + 1, offs + size, block_size_in_bytes do
            local dwords_from_message = {string_unpack(keccak_format, str, pos)}
            for j = 1, qwords_qty do
               lanes_lo[j] = lanes_lo[j] ~ dwords_from_message[2*j-1]
               lanes_hi[j] = lanes_hi[j] ~ dwords_from_message[2*j]
            end
            local L01_lo, L01_hi, L02_lo, L02_hi, L03_lo, L03_hi, L04_lo, L04_hi, L05_lo, L05_hi, L06_lo, L06_hi, L07_lo, L07_hi, L08_lo, L08_hi,
               L09_lo, L09_hi, L10_lo, L10_hi, L11_lo, L11_hi, L12_lo, L12_hi, L13_lo, L13_hi, L14_lo, L14_hi, L15_lo, L15_hi, L16_lo, L16_hi,
               L17_lo, L17_hi, L18_lo, L18_hi, L19_lo, L19_hi, L20_lo, L20_hi, L21_lo, L21_hi, L22_lo, L22_hi, L23_lo, L23_hi, L24_lo, L24_hi, L25_lo, L25_hi =
               lanes_lo[1], lanes_hi[1], lanes_lo[2], lanes_hi[2], lanes_lo[3], lanes_hi[3], lanes_lo[4], lanes_hi[4], lanes_lo[5], lanes_hi[5],
               lanes_lo[6], lanes_hi[6], lanes_lo[7], lanes_hi[7], lanes_lo[8], lanes_hi[8], lanes_lo[9], lanes_hi[9], lanes_lo[10], lanes_hi[10],
               lanes_lo[11], lanes_hi[11], lanes_lo[12], lanes_hi[12], lanes_lo[13], lanes_hi[13], lanes_lo[14], lanes_hi[14], lanes_lo[15], lanes_hi[15],
               lanes_lo[16], lanes_hi[16], lanes_lo[17], lanes_hi[17], lanes_lo[18], lanes_hi[18], lanes_lo[19], lanes_hi[19], lanes_lo[20], lanes_hi[20],
               lanes_lo[21], lanes_hi[21], lanes_lo[22], lanes_hi[22], lanes_lo[23], lanes_hi[23], lanes_lo[24], lanes_hi[24], lanes_lo[25], lanes_hi[25]
            for round_idx = 1, 24 do
               local C1_lo = L01_lo ~ L06_lo ~ L11_lo ~ L16_lo ~ L21_lo
               local C1_hi = L01_hi ~ L06_hi ~ L11_hi ~ L16_hi ~ L21_hi
               local C2_lo = L02_lo ~ L07_lo ~ L12_lo ~ L17_lo ~ L22_lo
               local C2_hi = L02_hi ~ L07_hi ~ L12_hi ~ L17_hi ~ L22_hi
               local C3_lo = L03_lo ~ L08_lo ~ L13_lo ~ L18_lo ~ L23_lo
               local C3_hi = L03_hi ~ L08_hi ~ L13_hi ~ L18_hi ~ L23_hi
               local C4_lo = L04_lo ~ L09_lo ~ L14_lo ~ L19_lo ~ L24_lo
               local C4_hi = L04_hi ~ L09_hi ~ L14_hi ~ L19_hi ~ L24_hi
               local C5_lo = L05_lo ~ L10_lo ~ L15_lo ~ L20_lo ~ L25_lo
               local C5_hi = L05_hi ~ L10_hi ~ L15_hi ~ L20_hi ~ L25_hi
               local D_lo = C1_lo ~ C3_lo<<1 ~ C3_hi>>31
               local D_hi = C1_hi ~ C3_hi<<1 ~ C3_lo>>31
               local T0_lo = D_lo ~ L02_lo
               local T0_hi = D_hi ~ L02_hi
               local T1_lo = D_lo ~ L07_lo
               local T1_hi = D_hi ~ L07_hi
               local T2_lo = D_lo ~ L12_lo
               local T2_hi = D_hi ~ L12_hi
               local T3_lo = D_lo ~ L17_lo
               local T3_hi = D_hi ~ L17_hi
               local T4_lo = D_lo ~ L22_lo
               local T4_hi = D_hi ~ L22_hi
               L02_lo = T1_lo>>20 ~ T1_hi<<12
               L02_hi = T1_hi>>20 ~ T1_lo<<12
               L07_lo = T3_lo>>19 ~ T3_hi<<13
               L07_hi = T3_hi>>19 ~ T3_lo<<13
               L12_lo = T0_lo<<1 ~ T0_hi>>31
               L12_hi = T0_hi<<1 ~ T0_lo>>31
               L17_lo = T2_lo<<10 ~ T2_hi>>22
               L17_hi = T2_hi<<10 ~ T2_lo>>22
               L22_lo = T4_lo<<2 ~ T4_hi>>30
               L22_hi = T4_hi<<2 ~ T4_lo>>30
               D_lo = C2_lo ~ C4_lo<<1 ~ C4_hi>>31
               D_hi = C2_hi ~ C4_hi<<1 ~ C4_lo>>31
               T0_lo = D_lo ~ L03_lo
               T0_hi = D_hi ~ L03_hi
               T1_lo = D_lo ~ L08_lo
               T1_hi = D_hi ~ L08_hi
               T2_lo = D_lo ~ L13_lo
               T2_hi = D_hi ~ L13_hi
               T3_lo = D_lo ~ L18_lo
               T3_hi = D_hi ~ L18_hi
               T4_lo = D_lo ~ L23_lo
               T4_hi = D_hi ~ L23_hi
               L03_lo = T2_lo>>21 ~ T2_hi<<11
               L03_hi = T2_hi>>21 ~ T2_lo<<11
               L08_lo = T4_lo>>3 ~ T4_hi<<29
               L08_hi = T4_hi>>3 ~ T4_lo<<29
               L13_lo = T1_lo<<6 ~ T1_hi>>26
               L13_hi = T1_hi<<6 ~ T1_lo>>26
               L18_lo = T3_lo<<15 ~ T3_hi>>17
               L18_hi = T3_hi<<15 ~ T3_lo>>17
               L23_lo = T0_lo>>2 ~ T0_hi<<30
               L23_hi = T0_hi>>2 ~ T0_lo<<30
               D_lo = C3_lo ~ C5_lo<<1 ~ C5_hi>>31
               D_hi = C3_hi ~ C5_hi<<1 ~ C5_lo>>31
               T0_lo = D_lo ~ L04_lo
               T0_hi = D_hi ~ L04_hi
               T1_lo = D_lo ~ L09_lo
               T1_hi = D_hi ~ L09_hi
               T2_lo = D_lo ~ L14_lo
               T2_hi = D_hi ~ L14_hi
               T3_lo = D_lo ~ L19_lo
               T3_hi = D_hi ~ L19_hi
               T4_lo = D_lo ~ L24_lo
               T4_hi = D_hi ~ L24_hi
               L04_lo = T3_lo<<21 ~ T3_hi>>11
               L04_hi = T3_hi<<21 ~ T3_lo>>11
               L09_lo = T0_lo<<28 ~ T0_hi>>4
               L09_hi = T0_hi<<28 ~ T0_lo>>4
               L14_lo = T2_lo<<25 ~ T2_hi>>7
               L14_hi = T2_hi<<25 ~ T2_lo>>7
               L19_lo = T4_lo>>8 ~ T4_hi<<24
               L19_hi = T4_hi>>8 ~ T4_lo<<24
               L24_lo = T1_lo>>9 ~ T1_hi<<23
               L24_hi = T1_hi>>9 ~ T1_lo<<23
               D_lo = C4_lo ~ C1_lo<<1 ~ C1_hi>>31
               D_hi = C4_hi ~ C1_hi<<1 ~ C1_lo>>31
               T0_lo = D_lo ~ L05_lo
               T0_hi = D_hi ~ L05_hi
               T1_lo = D_lo ~ L10_lo
               T1_hi = D_hi ~ L10_hi
               T2_lo = D_lo ~ L15_lo
               T2_hi = D_hi ~ L15_hi
               T3_lo = D_lo ~ L20_lo
               T3_hi = D_hi ~ L20_hi
               T4_lo = D_lo ~ L25_lo
               T4_hi = D_hi ~ L25_hi
               L05_lo = T4_lo<<14 ~ T4_hi>>18
               L05_hi = T4_hi<<14 ~ T4_lo>>18
               L10_lo = T1_lo<<20 ~ T1_hi>>12
               L10_hi = T1_hi<<20 ~ T1_lo>>12
               L15_lo = T3_lo<<8 ~ T3_hi>>24
               L15_hi = T3_hi<<8 ~ T3_lo>>24
               L20_lo = T0_lo<<27 ~ T0_hi>>5
               L20_hi = T0_hi<<27 ~ T0_lo>>5
               L25_lo = T2_lo>>25 ~ T2_hi<<7
               L25_hi = T2_hi>>25 ~ T2_lo<<7
               D_lo = C5_lo ~ C2_lo<<1 ~ C2_hi>>31
               D_hi = C5_hi ~ C2_hi<<1 ~ C2_lo>>31
               T1_lo = D_lo ~ L06_lo
               T1_hi = D_hi ~ L06_hi
               T2_lo = D_lo ~ L11_lo
               T2_hi = D_hi ~ L11_hi
               T3_lo = D_lo ~ L16_lo
               T3_hi = D_hi ~ L16_hi
               T4_lo = D_lo ~ L21_lo
               T4_hi = D_hi ~ L21_hi
               L06_lo = T2_lo<<3 ~ T2_hi>>29
               L06_hi = T2_hi<<3 ~ T2_lo>>29
               L11_lo = T4_lo<<18 ~ T4_hi>>14
               L11_hi = T4_hi<<18 ~ T4_lo>>14
               L16_lo = T1_lo>>28 ~ T1_hi<<4
               L16_hi = T1_hi>>28 ~ T1_lo<<4
               L21_lo = T3_lo>>23 ~ T3_hi<<9
               L21_hi = T3_hi>>23 ~ T3_lo<<9
               L01_lo = D_lo ~ L01_lo
               L01_hi = D_hi ~ L01_hi
               L01_lo, L02_lo, L03_lo, L04_lo, L05_lo = L01_lo ~ ~L02_lo & L03_lo, L02_lo ~ ~L03_lo & L04_lo, L03_lo ~ ~L04_lo & L05_lo, L04_lo ~ ~L05_lo & L01_lo, L05_lo ~ ~L01_lo & L02_lo
               L01_hi, L02_hi, L03_hi, L04_hi, L05_hi = L01_hi ~ ~L02_hi & L03_hi, L02_hi ~ ~L03_hi & L04_hi, L03_hi ~ ~L04_hi & L05_hi, L04_hi ~ ~L05_hi & L01_hi, L05_hi ~ ~L01_hi & L02_hi
               L06_lo, L07_lo, L08_lo, L09_lo, L10_lo = L09_lo ~ ~L10_lo & L06_lo, L10_lo ~ ~L06_lo & L07_lo, L06_lo ~ ~L07_lo & L08_lo, L07_lo ~ ~L08_lo & L09_lo, L08_lo ~ ~L09_lo & L10_lo
               L06_hi, L07_hi, L08_hi, L09_hi, L10_hi = L09_hi ~ ~L10_hi & L06_hi, L10_hi ~ ~L06_hi & L07_hi, L06_hi ~ ~L07_hi & L08_hi, L07_hi ~ ~L08_hi & L09_hi, L08_hi ~ ~L09_hi & L10_hi
               L11_lo, L12_lo, L13_lo, L14_lo, L15_lo = L12_lo ~ ~L13_lo & L14_lo, L13_lo ~ ~L14_lo & L15_lo, L14_lo ~ ~L15_lo & L11_lo, L15_lo ~ ~L11_lo & L12_lo, L11_lo ~ ~L12_lo & L13_lo
               L11_hi, L12_hi, L13_hi, L14_hi, L15_hi = L12_hi ~ ~L13_hi & L14_hi, L13_hi ~ ~L14_hi & L15_hi, L14_hi ~ ~L15_hi & L11_hi, L15_hi ~ ~L11_hi & L12_hi, L11_hi ~ ~L12_hi & L13_hi
               L16_lo, L17_lo, L18_lo, L19_lo, L20_lo = L20_lo ~ ~L16_lo & L17_lo, L16_lo ~ ~L17_lo & L18_lo, L17_lo ~ ~L18_lo & L19_lo, L18_lo ~ ~L19_lo & L20_lo, L19_lo ~ ~L20_lo & L16_lo
               L16_hi, L17_hi, L18_hi, L19_hi, L20_hi = L20_hi ~ ~L16_hi & L17_hi, L16_hi ~ ~L17_hi & L18_hi, L17_hi ~ ~L18_hi & L19_hi, L18_hi ~ ~L19_hi & L20_hi, L19_hi ~ ~L20_hi & L16_hi
               L21_lo, L22_lo, L23_lo, L24_lo, L25_lo = L23_lo ~ ~L24_lo & L25_lo, L24_lo ~ ~L25_lo & L21_lo, L25_lo ~ ~L21_lo & L22_lo, L21_lo ~ ~L22_lo & L23_lo, L22_lo ~ ~L23_lo & L24_lo
               L21_hi, L22_hi, L23_hi, L24_hi, L25_hi = L23_hi ~ ~L24_hi & L25_hi, L24_hi ~ ~L25_hi & L21_hi, L25_hi ~ ~L21_hi & L22_hi, L21_hi ~ ~L22_hi & L23_hi, L22_hi ~ ~L23_hi & L24_hi
               L01_lo = L01_lo ~ RC_lo[round_idx]
               L01_hi = L01_hi ~ RC_hi[round_idx]
            end
            lanes_lo[1]  = L01_lo;  lanes_hi[1]  = L01_hi
            lanes_lo[2]  = L02_lo;  lanes_hi[2]  = L02_hi
            lanes_lo[3]  = L03_lo;  lanes_hi[3]  = L03_hi
            lanes_lo[4]  = L04_lo;  lanes_hi[4]  = L04_hi
            lanes_lo[5]  = L05_lo;  lanes_hi[5]  = L05_hi
            lanes_lo[6]  = L06_lo;  lanes_hi[6]  = L06_hi
            lanes_lo[7]  = L07_lo;  lanes_hi[7]  = L07_hi
            lanes_lo[8]  = L08_lo;  lanes_hi[8]  = L08_hi
            lanes_lo[9]  = L09_lo;  lanes_hi[9]  = L09_hi
            lanes_lo[10] = L10_lo;  lanes_hi[10] = L10_hi
            lanes_lo[11] = L11_lo;  lanes_hi[11] = L11_hi
            lanes_lo[12] = L12_lo;  lanes_hi[12] = L12_hi
            lanes_lo[13] = L13_lo;  lanes_hi[13] = L13_hi
            lanes_lo[14] = L14_lo;  lanes_hi[14] = L14_hi
            lanes_lo[15] = L15_lo;  lanes_hi[15] = L15_hi
            lanes_lo[16] = L16_lo;  lanes_hi[16] = L16_hi
            lanes_lo[17] = L17_lo;  lanes_hi[17] = L17_hi
            lanes_lo[18] = L18_lo;  lanes_hi[18] = L18_hi
            lanes_lo[19] = L19_lo;  lanes_hi[19] = L19_hi
            lanes_lo[20] = L20_lo;  lanes_hi[20] = L20_hi
            lanes_lo[21] = L21_lo;  lanes_hi[21] = L21_hi
            lanes_lo[22] = L22_lo;  lanes_hi[22] = L22_hi
            lanes_lo[23] = L23_lo;  lanes_hi[23] = L23_hi
            lanes_lo[24] = L24_lo;  lanes_hi[24] = L24_hi
            lanes_lo[25] = L25_lo;  lanes_hi[25] = L25_hi
         end
      end

      local function blake2s_feed_64(H, str, offs, size, bytes_compressed, last_block_size, is_last_node)
         -- offs >= 0, size >= 0, size is multiple of 64
         local W = common_W
         local h1, h2, h3, h4, h5, h6, h7, h8 = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
         for pos = offs + 1, offs + size, 64 do
            if str then
               W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
                  string_unpack("<i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4", str, pos)
            end
            local v0, v1, v2, v3, v4, v5, v6, v7 = h1, h2, h3, h4, h5, h6, h7, h8
            local v8, v9, vA, vB, vC, vD, vE, vF = sha2_H_hi[1], sha2_H_hi[2], sha2_H_hi[3], sha2_H_hi[4], sha2_H_hi[5], sha2_H_hi[6], sha2_H_hi[7], sha2_H_hi[8]
            bytes_compressed = bytes_compressed + (last_block_size or 64)
            local t0 = bytes_compressed % 2^32
            local t1 = (bytes_compressed - t0) / 2^32
            t0 = (t0 + 2^31) % 2^32 - 2^31  -- convert to int32 range (-2^31)..(2^31-1) to avoid "number has no integer representation" error while XORing
            vC = vC ~ t0  -- t0 = low_4_bytes(bytes_compressed)
            vD = vD ~ t1  -- t1 = high_4_bytes(bytes_compressed)
            if last_block_size then  -- flag f0
               vE = ~vE
            end
            if is_last_node then  -- flag f1
               vF = ~vF
            end
            for j = 1, 10 do
               local row = sigma[j]
               v0 = v0 + v4 + W[row[1]]
               vC = vC ~ v0
               vC = vC >> 16 | vC << 16
               v8 = v8 + vC
               v4 = v4 ~ v8
               v4 = v4 >> 12 | v4 << 20
               v0 = v0 + v4 + W[row[2]]
               vC = vC ~ v0
               vC = vC >> 8 | vC << 24
               v8 = v8 + vC
               v4 = v4 ~ v8
               v4 = v4 >> 7 | v4 << 25
               v1 = v1 + v5 + W[row[3]]
               vD = vD ~ v1
               vD = vD >> 16 | vD << 16
               v9 = v9 + vD
               v5 = v5 ~ v9
               v5 = v5 >> 12 | v5 << 20
               v1 = v1 + v5 + W[row[4]]
               vD = vD ~ v1
               vD = vD >> 8 | vD << 24
               v9 = v9 + vD
               v5 = v5 ~ v9
               v5 = v5 >> 7 | v5 << 25
               v2 = v2 + v6 + W[row[5]]
               vE = vE ~ v2
               vE = vE >> 16 | vE << 16
               vA = vA + vE
               v6 = v6 ~ vA
               v6 = v6 >> 12 | v6 << 20
               v2 = v2 + v6 + W[row[6]]
               vE = vE ~ v2
               vE = vE >> 8 | vE << 24
               vA = vA + vE
               v6 = v6 ~ vA
               v6 = v6 >> 7 | v6 << 25
               v3 = v3 + v7 + W[row[7]]
               vF = vF ~ v3
               vF = vF >> 16 | vF << 16
               vB = vB + vF
               v7 = v7 ~ vB
               v7 = v7 >> 12 | v7 << 20
               v3 = v3 + v7 + W[row[8]]
               vF = vF ~ v3
               vF = vF >> 8 | vF << 24
               vB = vB + vF
               v7 = v7 ~ vB
               v7 = v7 >> 7 | v7 << 25
               v0 = v0 + v5 + W[row[9]]
               vF = vF ~ v0
               vF = vF >> 16 | vF << 16
               vA = vA + vF
               v5 = v5 ~ vA
               v5 = v5 >> 12 | v5 << 20
               v0 = v0 + v5 + W[row[10]]
               vF = vF ~ v0
               vF = vF >> 8 | vF << 24
               vA = vA + vF
               v5 = v5 ~ vA
               v5 = v5 >> 7 | v5 << 25
               v1 = v1 + v6 + W[row[11]]
               vC = vC ~ v1
               vC = vC >> 16 | vC << 16
               vB = vB + vC
               v6 = v6 ~ vB
               v6 = v6 >> 12 | v6 << 20
               v1 = v1 + v6 + W[row[12]]
               vC = vC ~ v1
               vC = vC >> 8 | vC << 24
               vB = vB + vC
               v6 = v6 ~ vB
               v6 = v6 >> 7 | v6 << 25
               v2 = v2 + v7 + W[row[13]]
               vD = vD ~ v2
               vD = vD >> 16 | vD << 16
               v8 = v8 + vD
               v7 = v7 ~ v8
               v7 = v7 >> 12 | v7 << 20
               v2 = v2 + v7 + W[row[14]]
               vD = vD ~ v2
               vD = vD >> 8 | vD << 24
               v8 = v8 + vD
               v7 = v7 ~ v8
               v7 = v7 >> 7 | v7 << 25
               v3 = v3 + v4 + W[row[15]]
               vE = vE ~ v3
               vE = vE >> 16 | vE << 16
               v9 = v9 + vE
               v4 = v4 ~ v9
               v4 = v4 >> 12 | v4 << 20
               v3 = v3 + v4 + W[row[16]]
               vE = vE ~ v3
               vE = vE >> 8 | vE << 24
               v9 = v9 + vE
               v4 = v4 ~ v9
               v4 = v4 >> 7 | v4 << 25
            end
            h1 = h1 ~ v0 ~ v8
            h2 = h2 ~ v1 ~ v9
            h3 = h3 ~ v2 ~ vA
            h4 = h4 ~ v3 ~ vB
            h5 = h5 ~ v4 ~ vC
            h6 = h6 ~ v5 ~ vD
            h7 = h7 ~ v6 ~ vE
            h8 = h8 ~ v7 ~ vF
         end
         H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
         return bytes_compressed
      end

      local function blake2b_feed_128(H_lo, H_hi, str, offs, size, bytes_compressed, last_block_size, is_last_node)
         -- offs >= 0, size >= 0, size is multiple of 128
         local W = common_W
         local h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo = H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8]
         local h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi = H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8]
         for pos = offs + 1, offs + size, 128 do
            if str then
               W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16],
               W[17], W[18], W[19], W[20], W[21], W[22], W[23], W[24], W[25], W[26], W[27], W[28], W[29], W[30], W[31], W[32] =
                  string_unpack("<i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4", str, pos)
            end
            local v0_lo, v1_lo, v2_lo, v3_lo, v4_lo, v5_lo, v6_lo, v7_lo = h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo
            local v0_hi, v1_hi, v2_hi, v3_hi, v4_hi, v5_hi, v6_hi, v7_hi = h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi
            local v8_lo, v9_lo, vA_lo, vB_lo, vC_lo, vD_lo, vE_lo, vF_lo = sha2_H_lo[1], sha2_H_lo[2], sha2_H_lo[3], sha2_H_lo[4], sha2_H_lo[5], sha2_H_lo[6], sha2_H_lo[7], sha2_H_lo[8]
            local v8_hi, v9_hi, vA_hi, vB_hi, vC_hi, vD_hi, vE_hi, vF_hi = sha2_H_hi[1], sha2_H_hi[2], sha2_H_hi[3], sha2_H_hi[4], sha2_H_hi[5], sha2_H_hi[6], sha2_H_hi[7], sha2_H_hi[8]
            bytes_compressed = bytes_compressed + (last_block_size or 128)
            local t0_lo = bytes_compressed % 2^32
            local t0_hi = (bytes_compressed - t0_lo) / 2^32
            t0_lo = (t0_lo + 2^31) % 2^32 - 2^31  -- convert to int32 range (-2^31)..(2^31-1) to avoid "number has no integer representation" error while XORing
            vC_lo = vC_lo ~ t0_lo  -- t0 = low_8_bytes(bytes_compressed)
            vC_hi = vC_hi ~ t0_hi
            -- t1 = high_8_bytes(bytes_compressed) = 0,  message length is always below 2^53 bytes
            if last_block_size then  -- flag f0
               vE_lo = ~vE_lo
               vE_hi = ~vE_hi
            end
            if is_last_node then  -- flag f1
               vF_lo = ~vF_lo
               vF_hi = ~vF_hi
            end
            for j = 1, 12 do
               local row = sigma[j]
               local k = row[1] * 2
               v0_lo = v0_lo % 2^32 + v4_lo % 2^32 + W[k-1] % 2^32
               v0_hi = v0_hi + v4_hi + floor(v0_lo / 2^32) + W[k]
               v0_lo = 0|((v0_lo + 2^31) % 2^32 - 2^31)
               vC_lo, vC_hi = vC_hi ~ v0_hi, vC_lo ~ v0_lo
               v8_lo = v8_lo % 2^32 + vC_lo % 2^32
               v8_hi = v8_hi + vC_hi + floor(v8_lo / 2^32)
               v8_lo = 0|((v8_lo + 2^31) % 2^32 - 2^31)
               v4_lo, v4_hi = v4_lo ~ v8_lo, v4_hi ~ v8_hi
               v4_lo, v4_hi = v4_lo >> 24 | v4_hi << 8, v4_hi >> 24 | v4_lo << 8
               k = row[2] * 2
               v0_lo = v0_lo % 2^32 + v4_lo % 2^32 + W[k-1] % 2^32
               v0_hi = v0_hi + v4_hi + floor(v0_lo / 2^32) + W[k]
               v0_lo = 0|((v0_lo + 2^31) % 2^32 - 2^31)
               vC_lo, vC_hi = vC_lo ~ v0_lo, vC_hi ~ v0_hi
               vC_lo, vC_hi = vC_lo >> 16 | vC_hi << 16, vC_hi >> 16 | vC_lo << 16
               v8_lo = v8_lo % 2^32 + vC_lo % 2^32
               v8_hi = v8_hi + vC_hi + floor(v8_lo / 2^32)
               v8_lo = 0|((v8_lo + 2^31) % 2^32 - 2^31)
               v4_lo, v4_hi = v4_lo ~ v8_lo, v4_hi ~ v8_hi
               v4_lo, v4_hi = v4_lo << 1 | v4_hi >> 31, v4_hi << 1 | v4_lo >> 31
               k = row[3] * 2
               v1_lo = v1_lo % 2^32 + v5_lo % 2^32 + W[k-1] % 2^32
               v1_hi = v1_hi + v5_hi + floor(v1_lo / 2^32) + W[k]
               v1_lo = 0|((v1_lo + 2^31) % 2^32 - 2^31)
               vD_lo, vD_hi = vD_hi ~ v1_hi, vD_lo ~ v1_lo
               v9_lo = v9_lo % 2^32 + vD_lo % 2^32
               v9_hi = v9_hi + vD_hi + floor(v9_lo / 2^32)
               v9_lo = 0|((v9_lo + 2^31) % 2^32 - 2^31)
               v5_lo, v5_hi = v5_lo ~ v9_lo, v5_hi ~ v9_hi
               v5_lo, v5_hi = v5_lo >> 24 | v5_hi << 8, v5_hi >> 24 | v5_lo << 8
               k = row[4] * 2
               v1_lo = v1_lo % 2^32 + v5_lo % 2^32 + W[k-1] % 2^32
               v1_hi = v1_hi + v5_hi + floor(v1_lo / 2^32) + W[k]
               v1_lo = 0|((v1_lo + 2^31) % 2^32 - 2^31)
               vD_lo, vD_hi = vD_lo ~ v1_lo, vD_hi ~ v1_hi
               vD_lo, vD_hi = vD_lo >> 16 | vD_hi << 16, vD_hi >> 16 | vD_lo << 16
               v9_lo = v9_lo % 2^32 + vD_lo % 2^32
               v9_hi = v9_hi + vD_hi + floor(v9_lo / 2^32)
               v9_lo = 0|((v9_lo + 2^31) % 2^32 - 2^31)
               v5_lo, v5_hi = v5_lo ~ v9_lo, v5_hi ~ v9_hi
               v5_lo, v5_hi = v5_lo << 1 | v5_hi >> 31, v5_hi << 1 | v5_lo >> 31
               k = row[5] * 2
               v2_lo = v2_lo % 2^32 + v6_lo % 2^32 + W[k-1] % 2^32
               v2_hi = v2_hi + v6_hi + floor(v2_lo / 2^32) + W[k]
               v2_lo = 0|((v2_lo + 2^31) % 2^32 - 2^31)
               vE_lo, vE_hi = vE_hi ~ v2_hi, vE_lo ~ v2_lo
               vA_lo = vA_lo % 2^32 + vE_lo % 2^32
               vA_hi = vA_hi + vE_hi + floor(vA_lo / 2^32)
               vA_lo = 0|((vA_lo + 2^31) % 2^32 - 2^31)
               v6_lo, v6_hi = v6_lo ~ vA_lo, v6_hi ~ vA_hi
               v6_lo, v6_hi = v6_lo >> 24 | v6_hi << 8, v6_hi >> 24 | v6_lo << 8
               k = row[6] * 2
               v2_lo = v2_lo % 2^32 + v6_lo % 2^32 + W[k-1] % 2^32
               v2_hi = v2_hi + v6_hi + floor(v2_lo / 2^32) + W[k]
               v2_lo = 0|((v2_lo + 2^31) % 2^32 - 2^31)
               vE_lo, vE_hi = vE_lo ~ v2_lo, vE_hi ~ v2_hi
               vE_lo, vE_hi = vE_lo >> 16 | vE_hi << 16, vE_hi >> 16 | vE_lo << 16
               vA_lo = vA_lo % 2^32 + vE_lo % 2^32
               vA_hi = vA_hi + vE_hi + floor(vA_lo / 2^32)
               vA_lo = 0|((vA_lo + 2^31) % 2^32 - 2^31)
               v6_lo, v6_hi = v6_lo ~ vA_lo, v6_hi ~ vA_hi
               v6_lo, v6_hi = v6_lo << 1 | v6_hi >> 31, v6_hi << 1 | v6_lo >> 31
               k = row[7] * 2
               v3_lo = v3_lo % 2^32 + v7_lo % 2^32 + W[k-1] % 2^32
               v3_hi = v3_hi + v7_hi + floor(v3_lo / 2^32) + W[k]
               v3_lo = 0|((v3_lo + 2^31) % 2^32 - 2^31)
               vF_lo, vF_hi = vF_hi ~ v3_hi, vF_lo ~ v3_lo
               vB_lo = vB_lo % 2^32 + vF_lo % 2^32
               vB_hi = vB_hi + vF_hi + floor(vB_lo / 2^32)
               vB_lo = 0|((vB_lo + 2^31) % 2^32 - 2^31)
               v7_lo, v7_hi = v7_lo ~ vB_lo, v7_hi ~ vB_hi
               v7_lo, v7_hi = v7_lo >> 24 | v7_hi << 8, v7_hi >> 24 | v7_lo << 8
               k = row[8] * 2
               v3_lo = v3_lo % 2^32 + v7_lo % 2^32 + W[k-1] % 2^32
               v3_hi = v3_hi + v7_hi + floor(v3_lo / 2^32) + W[k]
               v3_lo = 0|((v3_lo + 2^31) % 2^32 - 2^31)
               vF_lo, vF_hi = vF_lo ~ v3_lo, vF_hi ~ v3_hi
               vF_lo, vF_hi = vF_lo >> 16 | vF_hi << 16, vF_hi >> 16 | vF_lo << 16
               vB_lo = vB_lo % 2^32 + vF_lo % 2^32
               vB_hi = vB_hi + vF_hi + floor(vB_lo / 2^32)
               vB_lo = 0|((vB_lo + 2^31) % 2^32 - 2^31)
               v7_lo, v7_hi = v7_lo ~ vB_lo, v7_hi ~ vB_hi
               v7_lo, v7_hi = v7_lo << 1 | v7_hi >> 31, v7_hi << 1 | v7_lo >> 31
               k = row[9] * 2
               v0_lo = v0_lo % 2^32 + v5_lo % 2^32 + W[k-1] % 2^32
               v0_hi = v0_hi + v5_hi + floor(v0_lo / 2^32) + W[k]
               v0_lo = 0|((v0_lo + 2^31) % 2^32 - 2^31)
               vF_lo, vF_hi = vF_hi ~ v0_hi, vF_lo ~ v0_lo
               vA_lo = vA_lo % 2^32 + vF_lo % 2^32
               vA_hi = vA_hi + vF_hi + floor(vA_lo / 2^32)
               vA_lo = 0|((vA_lo + 2^31) % 2^32 - 2^31)
               v5_lo, v5_hi = v5_lo ~ vA_lo, v5_hi ~ vA_hi
               v5_lo, v5_hi = v5_lo >> 24 | v5_hi << 8, v5_hi >> 24 | v5_lo << 8
               k = row[10] * 2
               v0_lo = v0_lo % 2^32 + v5_lo % 2^32 + W[k-1] % 2^32
               v0_hi = v0_hi + v5_hi + floor(v0_lo / 2^32) + W[k]
               v0_lo = 0|((v0_lo + 2^31) % 2^32 - 2^31)
               vF_lo, vF_hi = vF_lo ~ v0_lo, vF_hi ~ v0_hi
               vF_lo, vF_hi = vF_lo >> 16 | vF_hi << 16, vF_hi >> 16 | vF_lo << 16
               vA_lo = vA_lo % 2^32 + vF_lo % 2^32
               vA_hi = vA_hi + vF_hi + floor(vA_lo / 2^32)
               vA_lo = 0|((vA_lo + 2^31) % 2^32 - 2^31)
               v5_lo, v5_hi = v5_lo ~ vA_lo, v5_hi ~ vA_hi
               v5_lo, v5_hi = v5_lo << 1 | v5_hi >> 31, v5_hi << 1 | v5_lo >> 31
               k = row[11] * 2
               v1_lo = v1_lo % 2^32 + v6_lo % 2^32 + W[k-1] % 2^32
               v1_hi = v1_hi + v6_hi + floor(v1_lo / 2^32) + W[k]
               v1_lo = 0|((v1_lo + 2^31) % 2^32 - 2^31)
               vC_lo, vC_hi = vC_hi ~ v1_hi, vC_lo ~ v1_lo
               vB_lo = vB_lo % 2^32 + vC_lo % 2^32
               vB_hi = vB_hi + vC_hi + floor(vB_lo / 2^32)
               vB_lo = 0|((vB_lo + 2^31) % 2^32 - 2^31)
               v6_lo, v6_hi = v6_lo ~ vB_lo, v6_hi ~ vB_hi
               v6_lo, v6_hi = v6_lo >> 24 | v6_hi << 8, v6_hi >> 24 | v6_lo << 8
               k = row[12] * 2
               v1_lo = v1_lo % 2^32 + v6_lo % 2^32 + W[k-1] % 2^32
               v1_hi = v1_hi + v6_hi + floor(v1_lo / 2^32) + W[k]
               v1_lo = 0|((v1_lo + 2^31) % 2^32 - 2^31)
               vC_lo, vC_hi = vC_lo ~ v1_lo, vC_hi ~ v1_hi
               vC_lo, vC_hi = vC_lo >> 16 | vC_hi << 16, vC_hi >> 16 | vC_lo << 16
               vB_lo = vB_lo % 2^32 + vC_lo % 2^32
               vB_hi = vB_hi + vC_hi + floor(vB_lo / 2^32)
               vB_lo = 0|((vB_lo + 2^31) % 2^32 - 2^31)
               v6_lo, v6_hi = v6_lo ~ vB_lo, v6_hi ~ vB_hi
               v6_lo, v6_hi = v6_lo << 1 | v6_hi >> 31, v6_hi << 1 | v6_lo >> 31
               k = row[13] * 2
               v2_lo = v2_lo % 2^32 + v7_lo % 2^32 + W[k-1] % 2^32
               v2_hi = v2_hi + v7_hi + floor(v2_lo / 2^32) + W[k]
               v2_lo = 0|((v2_lo + 2^31) % 2^32 - 2^31)
               vD_lo, vD_hi = vD_hi ~ v2_hi, vD_lo ~ v2_lo
               v8_lo = v8_lo % 2^32 + vD_lo % 2^32
               v8_hi = v8_hi + vD_hi + floor(v8_lo / 2^32)
               v8_lo = 0|((v8_lo + 2^31) % 2^32 - 2^31)
               v7_lo, v7_hi = v7_lo ~ v8_lo, v7_hi ~ v8_hi
               v7_lo, v7_hi = v7_lo >> 24 | v7_hi << 8, v7_hi >> 24 | v7_lo << 8
               k = row[14] * 2
               v2_lo = v2_lo % 2^32 + v7_lo % 2^32 + W[k-1] % 2^32
               v2_hi = v2_hi + v7_hi + floor(v2_lo / 2^32) + W[k]
               v2_lo = 0|((v2_lo + 2^31) % 2^32 - 2^31)
               vD_lo, vD_hi = vD_lo ~ v2_lo, vD_hi ~ v2_hi
               vD_lo, vD_hi = vD_lo >> 16 | vD_hi << 16, vD_hi >> 16 | vD_lo << 16
               v8_lo = v8_lo % 2^32 + vD_lo % 2^32
               v8_hi = v8_hi + vD_hi + floor(v8_lo / 2^32)
               v8_lo = 0|((v8_lo + 2^31) % 2^32 - 2^31)
               v7_lo, v7_hi = v7_lo ~ v8_lo, v7_hi ~ v8_hi
               v7_lo, v7_hi = v7_lo << 1 | v7_hi >> 31, v7_hi << 1 | v7_lo >> 31
               k = row[15] * 2
               v3_lo = v3_lo % 2^32 + v4_lo % 2^32 + W[k-1] % 2^32
               v3_hi = v3_hi + v4_hi + floor(v3_lo / 2^32) + W[k]
               v3_lo = 0|((v3_lo + 2^31) % 2^32 - 2^31)
               vE_lo, vE_hi = vE_hi ~ v3_hi, vE_lo ~ v3_lo
               v9_lo = v9_lo % 2^32 + vE_lo % 2^32
               v9_hi = v9_hi + vE_hi + floor(v9_lo / 2^32)
               v9_lo = 0|((v9_lo + 2^31) % 2^32 - 2^31)
               v4_lo, v4_hi = v4_lo ~ v9_lo, v4_hi ~ v9_hi
               v4_lo, v4_hi = v4_lo >> 24 | v4_hi << 8, v4_hi >> 24 | v4_lo << 8
               k = row[16] * 2
               v3_lo = v3_lo % 2^32 + v4_lo % 2^32 + W[k-1] % 2^32
               v3_hi = v3_hi + v4_hi + floor(v3_lo / 2^32) + W[k]
               v3_lo = 0|((v3_lo + 2^31) % 2^32 - 2^31)
               vE_lo, vE_hi = vE_lo ~ v3_lo, vE_hi ~ v3_hi
               vE_lo, vE_hi = vE_lo >> 16 | vE_hi << 16, vE_hi >> 16 | vE_lo << 16
               v9_lo = v9_lo % 2^32 + vE_lo % 2^32
               v9_hi = v9_hi + vE_hi + floor(v9_lo / 2^32)
               v9_lo = 0|((v9_lo + 2^31) % 2^32 - 2^31)
               v4_lo, v4_hi = v4_lo ~ v9_lo, v4_hi ~ v9_hi
               v4_lo, v4_hi = v4_lo << 1 | v4_hi >> 31, v4_hi << 1 | v4_lo >> 31
            end
            h1_lo = h1_lo ~ v0_lo ~ v8_lo
            h2_lo = h2_lo ~ v1_lo ~ v9_lo
            h3_lo = h3_lo ~ v2_lo ~ vA_lo
            h4_lo = h4_lo ~ v3_lo ~ vB_lo
            h5_lo = h5_lo ~ v4_lo ~ vC_lo
            h6_lo = h6_lo ~ v5_lo ~ vD_lo
            h7_lo = h7_lo ~ v6_lo ~ vE_lo
            h8_lo = h8_lo ~ v7_lo ~ vF_lo
            h1_hi = h1_hi ~ v0_hi ~ v8_hi
            h2_hi = h2_hi ~ v1_hi ~ v9_hi
            h3_hi = h3_hi ~ v2_hi ~ vA_hi
            h4_hi = h4_hi ~ v3_hi ~ vB_hi
            h5_hi = h5_hi ~ v4_hi ~ vC_hi
            h6_hi = h6_hi ~ v5_hi ~ vD_hi
            h7_hi = h7_hi ~ v6_hi ~ vE_hi
            h8_hi = h8_hi ~ v7_hi ~ vF_hi
         end
         H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8] = h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo
         H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8] = h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi
         return bytes_compressed
      end

      local function blake3_feed_64(str, offs, size, flags, chunk_index, H_in, H_out, wide_output, block_length)
         -- offs >= 0, size >= 0, size is multiple of 64
         block_length = block_length or 64
         local W = common_W
         local h1, h2, h3, h4, h5, h6, h7, h8 = H_in[1], H_in[2], H_in[3], H_in[4], H_in[5], H_in[6], H_in[7], H_in[8]
         H_out = H_out or H_in
         for pos = offs + 1, offs + size, 64 do
            if str then
               W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
                  string_unpack("<i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4i4", str, pos)
            end
            local v0, v1, v2, v3, v4, v5, v6, v7 = h1, h2, h3, h4, h5, h6, h7, h8
            local v8, v9, vA, vB = sha2_H_hi[1], sha2_H_hi[2], sha2_H_hi[3], sha2_H_hi[4]
            local t0 = chunk_index % 2^32         -- t0 = low_4_bytes(chunk_index)
            local t1 = (chunk_index - t0) / 2^32  -- t1 = high_4_bytes(chunk_index)
            t0 = (t0 + 2^31) % 2^32 - 2^31  -- convert to int32 range (-2^31)..(2^31-1) to avoid "number has no integer representation" error while ORing
            local vC, vD, vE, vF = 0|t0, 0|t1, block_length, flags
            for j = 1, 7 do
               v0 = v0 + v4 + W[perm_blake3[j]]
               vC = vC ~ v0
               vC = vC >> 16 | vC << 16
               v8 = v8 + vC
               v4 = v4 ~ v8
               v4 = v4 >> 12 | v4 << 20
               v0 = v0 + v4 + W[perm_blake3[j + 14]]
               vC = vC ~ v0
               vC = vC >> 8 | vC << 24
               v8 = v8 + vC
               v4 = v4 ~ v8
               v4 = v4 >> 7 | v4 << 25
               v1 = v1 + v5 + W[perm_blake3[j + 1]]
               vD = vD ~ v1
               vD = vD >> 16 | vD << 16
               v9 = v9 + vD
               v5 = v5 ~ v9
               v5 = v5 >> 12 | v5 << 20
               v1 = v1 + v5 + W[perm_blake3[j + 2]]
               vD = vD ~ v1
               vD = vD >> 8 | vD << 24
               v9 = v9 + vD
               v5 = v5 ~ v9
               v5 = v5 >> 7 | v5 << 25
               v2 = v2 + v6 + W[perm_blake3[j + 16]]
               vE = vE ~ v2
               vE = vE >> 16 | vE << 16
               vA = vA + vE
               v6 = v6 ~ vA
               v6 = v6 >> 12 | v6 << 20
               v2 = v2 + v6 + W[perm_blake3[j + 7]]
               vE = vE ~ v2
               vE = vE >> 8 | vE << 24
               vA = vA + vE
               v6 = v6 ~ vA
               v6 = v6 >> 7 | v6 << 25
               v3 = v3 + v7 + W[perm_blake3[j + 15]]
               vF = vF ~ v3
               vF = vF >> 16 | vF << 16
               vB = vB + vF
               v7 = v7 ~ vB
               v7 = v7 >> 12 | v7 << 20
               v3 = v3 + v7 + W[perm_blake3[j + 17]]
               vF = vF ~ v3
               vF = vF >> 8 | vF << 24
               vB = vB + vF
               v7 = v7 ~ vB
               v7 = v7 >> 7 | v7 << 25
               v0 = v0 + v5 + W[perm_blake3[j + 21]]
               vF = vF ~ v0
               vF = vF >> 16 | vF << 16
               vA = vA + vF
               v5 = v5 ~ vA
               v5 = v5 >> 12 | v5 << 20
               v0 = v0 + v5 + W[perm_blake3[j + 5]]
               vF = vF ~ v0
               vF = vF >> 8 | vF << 24
               vA = vA + vF
               v5 = v5 ~ vA
               v5 = v5 >> 7 | v5 << 25
               v1 = v1 + v6 + W[perm_blake3[j + 3]]
               vC = vC ~ v1
               vC = vC >> 16 | vC << 16
               vB = vB + vC
               v6 = v6 ~ vB
               v6 = v6 >> 12 | v6 << 20
               v1 = v1 + v6 + W[perm_blake3[j + 6]]
               vC = vC ~ v1
               vC = vC >> 8 | vC << 24
               vB = vB + vC
               v6 = v6 ~ vB
               v6 = v6 >> 7 | v6 << 25
               v2 = v2 + v7 + W[perm_blake3[j + 4]]
               vD = vD ~ v2
               vD = vD >> 16 | vD << 16
               v8 = v8 + vD
               v7 = v7 ~ v8
               v7 = v7 >> 12 | v7 << 20
               v2 = v2 + v7 + W[perm_blake3[j + 18]]
               vD = vD ~ v2
               vD = vD >> 8 | vD << 24
               v8 = v8 + vD
               v7 = v7 ~ v8
               v7 = v7 >> 7 | v7 << 25
               v3 = v3 + v4 + W[perm_blake3[j + 19]]
               vE = vE ~ v3
               vE = vE >> 16 | vE << 16
               v9 = v9 + vE
               v4 = v4 ~ v9
               v4 = v4 >> 12 | v4 << 20
               v3 = v3 + v4 + W[perm_blake3[j + 20]]
               vE = vE ~ v3
               vE = vE >> 8 | vE << 24
               v9 = v9 + vE
               v4 = v4 ~ v9
               v4 = v4 >> 7 | v4 << 25
            end
            if wide_output then
               H_out[ 9] = h1 ~ v8
               H_out[10] = h2 ~ v9
               H_out[11] = h3 ~ vA
               H_out[12] = h4 ~ vB
               H_out[13] = h5 ~ vC
               H_out[14] = h6 ~ vD
               H_out[15] = h7 ~ vE
               H_out[16] = h8 ~ vF
            end
            h1 = v0 ~ v8
            h2 = v1 ~ v9
            h3 = v2 ~ vA
            h4 = v3 ~ vB
            h5 = v4 ~ vC
            h6 = v5 ~ vD
            h7 = v6 ~ vE
            h8 = v7 ~ vF
         end
         H_out[1], H_out[2], H_out[3], H_out[4], H_out[5], H_out[6], H_out[7], H_out[8] = h1, h2, h3, h4, h5, h6, h7, h8
      end

      return XORA5, XOR_BYTE, sha256_feed_64, sha512_feed_128, md5_feed_64, sha1_feed_64, keccak_feed, blake2s_feed_64, blake2b_feed_128, blake3_feed_64
   ]=])(
      md5_next_shift,
      md5_K,
      sha2_K_lo,
      sha2_K_hi,
      build_keccak_format,
      sha3_RC_lo,
      sha3_RC_hi,
      sigma,
      common_W,
      sha2_H_lo,
      sha2_H_hi,
      perm_blake3
    )
end

XOR = XOR or XORA5

if branch == "LIB32" or branch == "EMUL" then
  -- implementation for Lua 5.1/5.2 (with or without bitwise library available)

  function sha256_feed_64(H, str, offs, size)
    -- offs >= 0, size >= 0, size is multiple of 64
    local W, K = common_W, sha2_K_hi
    local h1, h2, h3, h4, h5, h6, h7, h8 = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for pos = offs, offs + size - 1, 64 do
      for j = 1, 16 do
        pos = pos + 4
        local a, b, c, d = byte(str, pos - 3, pos)
        W[j] = ((a * 256 + b) * 256 + c) * 256 + d
      end
      for j = 17, 64 do
        local a, b = W[j - 15], W[j - 2]
        local a7, a18, b17, b19 = a / 2 ^ 7, a / 2 ^ 18, b / 2 ^ 17, b / 2 ^ 19
        W[j] = (
          XOR(a7 % 1 * (2 ^ 32 - 1) + a7, a18 % 1 * (2 ^ 32 - 1) + a18, (a - a % 2 ^ 3) / 2 ^ 3)
          + W[j - 16]
          + W[j - 7]
          + XOR(b17 % 1 * (2 ^ 32 - 1) + b17, b19 % 1 * (2 ^ 32 - 1) + b19, (b - b % 2 ^ 10) / 2 ^ 10)
        ) % 2 ^ 32
      end
      local a, b, c, d, e, f, g, h = h1, h2, h3, h4, h5, h6, h7, h8
      for j = 1, 64 do
        e = e % 2 ^ 32
        local e6, e11, e7 = e / 2 ^ 6, e / 2 ^ 11, e * 2 ^ 7
        local e7_lo = e7 % 2 ^ 32
        local z = AND(e, f)
          + AND(-1 - e, g)
          + h
          + K[j]
          + W[j]
          + XOR(e6 % 1 * (2 ^ 32 - 1) + e6, e11 % 1 * (2 ^ 32 - 1) + e11, e7_lo + (e7 - e7_lo) / 2 ^ 32)
        h = g
        g = f
        f = e
        e = z + d
        d = c
        c = b
        b = a % 2 ^ 32
        local b2, b13, b10 = b / 2 ^ 2, b / 2 ^ 13, b * 2 ^ 10
        local b10_lo = b10 % 2 ^ 32
        a = z
          + AND(d, c)
          + AND(b, XOR(d, c))
          + XOR(b2 % 1 * (2 ^ 32 - 1) + b2, b13 % 1 * (2 ^ 32 - 1) + b13, b10_lo + (b10 - b10_lo) / 2 ^ 32)
      end
      h1, h2, h3, h4 = (a + h1) % 2 ^ 32, (b + h2) % 2 ^ 32, (c + h3) % 2 ^ 32, (d + h4) % 2 ^ 32
      h5, h6, h7, h8 = (e + h5) % 2 ^ 32, (f + h6) % 2 ^ 32, (g + h7) % 2 ^ 32, (h + h8) % 2 ^ 32
    end
    H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
  end

  function sha512_feed_128(H_lo, H_hi, str, offs, size)
    -- offs >= 0, size >= 0, size is multiple of 128
    -- W1_hi, W1_lo, W2_hi, W2_lo, ...   Wk_hi = W[2*k-1], Wk_lo = W[2*k]
    local W, K_lo, K_hi = common_W, sha2_K_lo, sha2_K_hi
    local h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo =
      H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8]
    local h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi =
      H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8]
    for pos = offs, offs + size - 1, 128 do
      for j = 1, 16 * 2 do
        pos = pos + 4
        local a, b, c, d = byte(str, pos - 3, pos)
        W[j] = ((a * 256 + b) * 256 + c) * 256 + d
      end
      for jj = 17 * 2, 80 * 2, 2 do
        local a_hi, a_lo, b_hi, b_lo = W[jj - 31], W[jj - 30], W[jj - 5], W[jj - 4]
        local b_hi_6, b_hi_19, b_hi_29, b_lo_19, b_lo_29, a_hi_1, a_hi_7, a_hi_8, a_lo_1, a_lo_8 =
          b_hi % 2 ^ 6,
          b_hi % 2 ^ 19,
          b_hi % 2 ^ 29,
          b_lo % 2 ^ 19,
          b_lo % 2 ^ 29,
          a_hi % 2 ^ 1,
          a_hi % 2 ^ 7,
          a_hi % 2 ^ 8,
          a_lo % 2 ^ 1,
          a_lo % 2 ^ 8
        local tmp1 = XOR(
          (a_lo - a_lo_1) / 2 ^ 1 + a_hi_1 * 2 ^ 31,
          (a_lo - a_lo_8) / 2 ^ 8 + a_hi_8 * 2 ^ 24,
          (a_lo - a_lo % 2 ^ 7) / 2 ^ 7 + a_hi_7 * 2 ^ 25
        ) % 2 ^ 32 + XOR(
          (b_lo - b_lo_19) / 2 ^ 19 + b_hi_19 * 2 ^ 13,
          b_lo_29 * 2 ^ 3 + (b_hi - b_hi_29) / 2 ^ 29,
          (b_lo - b_lo % 2 ^ 6) / 2 ^ 6 + b_hi_6 * 2 ^ 26
        ) % 2 ^ 32 + W[jj - 14] + W[jj - 32]
        local tmp2 = tmp1 % 2 ^ 32
        W[jj - 1] = (
          XOR(
            (a_hi - a_hi_1) / 2 ^ 1 + a_lo_1 * 2 ^ 31,
            (a_hi - a_hi_8) / 2 ^ 8 + a_lo_8 * 2 ^ 24,
            (a_hi - a_hi_7) / 2 ^ 7
          )
          + XOR(
            (b_hi - b_hi_19) / 2 ^ 19 + b_lo_19 * 2 ^ 13,
            b_hi_29 * 2 ^ 3 + (b_lo - b_lo_29) / 2 ^ 29,
            (b_hi - b_hi_6) / 2 ^ 6
          )
          + W[jj - 15]
          + W[jj - 33]
          + (tmp1 - tmp2) / 2 ^ 32
        ) % 2 ^ 32
        W[jj] = tmp2
      end
      local a_lo, b_lo, c_lo, d_lo, e_lo, f_lo, g_lo, h_lo = h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo
      local a_hi, b_hi, c_hi, d_hi, e_hi, f_hi, g_hi, h_hi = h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi
      for j = 1, 80 do
        local jj = 2 * j
        local e_lo_9, e_lo_14, e_lo_18, e_hi_9, e_hi_14, e_hi_18 =
          e_lo % 2 ^ 9, e_lo % 2 ^ 14, e_lo % 2 ^ 18, e_hi % 2 ^ 9, e_hi % 2 ^ 14, e_hi % 2 ^ 18
        local tmp1 = (AND(e_lo, f_lo) + AND(-1 - e_lo, g_lo)) % 2 ^ 32
          + h_lo
          + K_lo[j]
          + W[jj]
          + XOR(
              (e_lo - e_lo_14) / 2 ^ 14 + e_hi_14 * 2 ^ 18,
              (e_lo - e_lo_18) / 2 ^ 18 + e_hi_18 * 2 ^ 14,
              e_lo_9 * 2 ^ 23 + (e_hi - e_hi_9) / 2 ^ 9
            )
            % 2 ^ 32
        local z_lo = tmp1 % 2 ^ 32
        local z_hi = AND(e_hi, f_hi)
          + AND(-1 - e_hi, g_hi)
          + h_hi
          + K_hi[j]
          + W[jj - 1]
          + (tmp1 - z_lo) / 2 ^ 32
          + XOR(
            (e_hi - e_hi_14) / 2 ^ 14 + e_lo_14 * 2 ^ 18,
            (e_hi - e_hi_18) / 2 ^ 18 + e_lo_18 * 2 ^ 14,
            e_hi_9 * 2 ^ 23 + (e_lo - e_lo_9) / 2 ^ 9
          )
        h_lo = g_lo
        h_hi = g_hi
        g_lo = f_lo
        g_hi = f_hi
        f_lo = e_lo
        f_hi = e_hi
        tmp1 = z_lo + d_lo
        e_lo = tmp1 % 2 ^ 32
        e_hi = (z_hi + d_hi + (tmp1 - e_lo) / 2 ^ 32) % 2 ^ 32
        d_lo = c_lo
        d_hi = c_hi
        c_lo = b_lo
        c_hi = b_hi
        b_lo = a_lo
        b_hi = a_hi
        local b_lo_2, b_lo_7, b_lo_28, b_hi_2, b_hi_7, b_hi_28 =
          b_lo % 2 ^ 2, b_lo % 2 ^ 7, b_lo % 2 ^ 28, b_hi % 2 ^ 2, b_hi % 2 ^ 7, b_hi % 2 ^ 28
        tmp1 = z_lo
          + (AND(d_lo, c_lo) + AND(b_lo, XOR(d_lo, c_lo))) % 2 ^ 32
          + XOR(
              (b_lo - b_lo_28) / 2 ^ 28 + b_hi_28 * 2 ^ 4,
              b_lo_2 * 2 ^ 30 + (b_hi - b_hi_2) / 2 ^ 2,
              b_lo_7 * 2 ^ 25 + (b_hi - b_hi_7) / 2 ^ 7
            )
            % 2 ^ 32
        a_lo = tmp1 % 2 ^ 32
        a_hi = (
          z_hi
          + AND(d_hi, c_hi)
          + AND(b_hi, XOR(d_hi, c_hi))
          + (tmp1 - a_lo) / 2 ^ 32
          + XOR(
            (b_hi - b_hi_28) / 2 ^ 28 + b_lo_28 * 2 ^ 4,
            b_hi_2 * 2 ^ 30 + (b_lo - b_lo_2) / 2 ^ 2,
            b_hi_7 * 2 ^ 25 + (b_lo - b_lo_7) / 2 ^ 7
          )
        ) % 2 ^ 32
      end
      a_lo = h1_lo + a_lo
      h1_lo = a_lo % 2 ^ 32
      h1_hi = (h1_hi + a_hi + (a_lo - h1_lo) / 2 ^ 32) % 2 ^ 32
      a_lo = h2_lo + b_lo
      h2_lo = a_lo % 2 ^ 32
      h2_hi = (h2_hi + b_hi + (a_lo - h2_lo) / 2 ^ 32) % 2 ^ 32
      a_lo = h3_lo + c_lo
      h3_lo = a_lo % 2 ^ 32
      h3_hi = (h3_hi + c_hi + (a_lo - h3_lo) / 2 ^ 32) % 2 ^ 32
      a_lo = h4_lo + d_lo
      h4_lo = a_lo % 2 ^ 32
      h4_hi = (h4_hi + d_hi + (a_lo - h4_lo) / 2 ^ 32) % 2 ^ 32
      a_lo = h5_lo + e_lo
      h5_lo = a_lo % 2 ^ 32
      h5_hi = (h5_hi + e_hi + (a_lo - h5_lo) / 2 ^ 32) % 2 ^ 32
      a_lo = h6_lo + f_lo
      h6_lo = a_lo % 2 ^ 32
      h6_hi = (h6_hi + f_hi + (a_lo - h6_lo) / 2 ^ 32) % 2 ^ 32
      a_lo = h7_lo + g_lo
      h7_lo = a_lo % 2 ^ 32
      h7_hi = (h7_hi + g_hi + (a_lo - h7_lo) / 2 ^ 32) % 2 ^ 32
      a_lo = h8_lo + h_lo
      h8_lo = a_lo % 2 ^ 32
      h8_hi = (h8_hi + h_hi + (a_lo - h8_lo) / 2 ^ 32) % 2 ^ 32
    end
    H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8] =
      h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo
    H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8] =
      h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi
  end

  if branch == "LIB32" then
    function md5_feed_64(H, str, offs, size)
      -- offs >= 0, size >= 0, size is multiple of 64
      local W, K, md5_next_shift = common_W, md5_K, md5_next_shift
      local h1, h2, h3, h4 = H[1], H[2], H[3], H[4]
      for pos = offs, offs + size - 1, 64 do
        for j = 1, 16 do
          pos = pos + 4
          local a, b, c, d = byte(str, pos - 3, pos)
          W[j] = ((d * 256 + c) * 256 + b) * 256 + a
        end
        local a, b, c, d = h1, h2, h3, h4
        local s = 25
        for j = 1, 16 do
          local F = ROR(AND(b, c) + AND(-1 - b, d) + a + K[j] + W[j], s) + b
          s = md5_next_shift[s]
          a = d
          d = c
          c = b
          b = F
        end
        s = 27
        for j = 17, 32 do
          local F = ROR(AND(d, b) + AND(-1 - d, c) + a + K[j] + W[(5 * j - 4) % 16 + 1], s) + b
          s = md5_next_shift[s]
          a = d
          d = c
          c = b
          b = F
        end
        s = 28
        for j = 33, 48 do
          local F = ROR(XOR(XOR(b, c), d) + a + K[j] + W[(3 * j + 2) % 16 + 1], s) + b
          s = md5_next_shift[s]
          a = d
          d = c
          c = b
          b = F
        end
        s = 26
        for j = 49, 64 do
          local F = ROR(XOR(c, OR(b, -1 - d)) + a + K[j] + W[(j * 7 - 7) % 16 + 1], s) + b
          s = md5_next_shift[s]
          a = d
          d = c
          c = b
          b = F
        end
        h1 = (a + h1) % 2 ^ 32
        h2 = (b + h2) % 2 ^ 32
        h3 = (c + h3) % 2 ^ 32
        h4 = (d + h4) % 2 ^ 32
      end
      H[1], H[2], H[3], H[4] = h1, h2, h3, h4
    end
  elseif branch == "EMUL" then
    function md5_feed_64(H, str, offs, size)
      -- offs >= 0, size >= 0, size is multiple of 64
      local W, K, md5_next_shift = common_W, md5_K, md5_next_shift
      local h1, h2, h3, h4 = H[1], H[2], H[3], H[4]
      for pos = offs, offs + size - 1, 64 do
        for j = 1, 16 do
          pos = pos + 4
          local a, b, c, d = byte(str, pos - 3, pos)
          W[j] = ((d * 256 + c) * 256 + b) * 256 + a
        end
        local a, b, c, d = h1, h2, h3, h4
        local s = 25
        for j = 1, 16 do
          local z = (AND(b, c) + AND(-1 - b, d) + a + K[j] + W[j]) % 2 ^ 32 / 2 ^ s
          local y = z % 1
          s = md5_next_shift[s]
          a = d
          d = c
          c = b
          b = y * 2 ^ 32 + (z - y) + b
        end
        s = 27
        for j = 17, 32 do
          local z = (AND(d, b) + AND(-1 - d, c) + a + K[j] + W[(5 * j - 4) % 16 + 1]) % 2 ^ 32 / 2 ^ s
          local y = z % 1
          s = md5_next_shift[s]
          a = d
          d = c
          c = b
          b = y * 2 ^ 32 + (z - y) + b
        end
        s = 28
        for j = 33, 48 do
          local z = (XOR(XOR(b, c), d) + a + K[j] + W[(3 * j + 2) % 16 + 1]) % 2 ^ 32 / 2 ^ s
          local y = z % 1
          s = md5_next_shift[s]
          a = d
          d = c
          c = b
          b = y * 2 ^ 32 + (z - y) + b
        end
        s = 26
        for j = 49, 64 do
          local z = (XOR(c, OR(b, -1 - d)) + a + K[j] + W[(j * 7 - 7) % 16 + 1]) % 2 ^ 32 / 2 ^ s
          local y = z % 1
          s = md5_next_shift[s]
          a = d
          d = c
          c = b
          b = y * 2 ^ 32 + (z - y) + b
        end
        h1 = (a + h1) % 2 ^ 32
        h2 = (b + h2) % 2 ^ 32
        h3 = (c + h3) % 2 ^ 32
        h4 = (d + h4) % 2 ^ 32
      end
      H[1], H[2], H[3], H[4] = h1, h2, h3, h4
    end
  end

  function sha1_feed_64(H, str, offs, size)
    -- offs >= 0, size >= 0, size is multiple of 64
    local W = common_W
    local h1, h2, h3, h4, h5 = H[1], H[2], H[3], H[4], H[5]
    for pos = offs, offs + size - 1, 64 do
      for j = 1, 16 do
        pos = pos + 4
        local a, b, c, d = byte(str, pos - 3, pos)
        W[j] = ((a * 256 + b) * 256 + c) * 256 + d
      end
      for j = 17, 80 do
        local a = XOR(W[j - 3], W[j - 8], W[j - 14], W[j - 16]) % 2 ^ 32 * 2
        local b = a % 2 ^ 32
        W[j] = b + (a - b) / 2 ^ 32
      end
      local a, b, c, d, e = h1, h2, h3, h4, h5
      for j = 1, 20 do
        local a5 = a * 2 ^ 5
        local z = a5 % 2 ^ 32
        z = z + (a5 - z) / 2 ^ 32 + AND(b, c) + AND(-1 - b, d) + 0x5A827999 + W[j] + e -- constant = floor(2^30 * sqrt(2))
        e = d
        d = c
        c = b / 2 ^ 2
        c = c % 1 * (2 ^ 32 - 1) + c
        b = a
        a = z % 2 ^ 32
      end
      for j = 21, 40 do
        local a5 = a * 2 ^ 5
        local z = a5 % 2 ^ 32
        z = z + (a5 - z) / 2 ^ 32 + XOR(b, c, d) + 0x6ED9EBA1 + W[j] + e -- 2^30 * sqrt(3)
        e = d
        d = c
        c = b / 2 ^ 2
        c = c % 1 * (2 ^ 32 - 1) + c
        b = a
        a = z % 2 ^ 32
      end
      for j = 41, 60 do
        local a5 = a * 2 ^ 5
        local z = a5 % 2 ^ 32
        z = z + (a5 - z) / 2 ^ 32 + AND(d, c) + AND(b, XOR(d, c)) + 0x8F1BBCDC + W[j] + e -- 2^30 * sqrt(5)
        e = d
        d = c
        c = b / 2 ^ 2
        c = c % 1 * (2 ^ 32 - 1) + c
        b = a
        a = z % 2 ^ 32
      end
      for j = 61, 80 do
        local a5 = a * 2 ^ 5
        local z = a5 % 2 ^ 32
        z = z + (a5 - z) / 2 ^ 32 + XOR(b, c, d) + 0xCA62C1D6 + W[j] + e -- 2^30 * sqrt(10)
        e = d
        d = c
        c = b / 2 ^ 2
        c = c % 1 * (2 ^ 32 - 1) + c
        b = a
        a = z % 2 ^ 32
      end
      h1 = (a + h1) % 2 ^ 32
      h2 = (b + h2) % 2 ^ 32
      h3 = (c + h3) % 2 ^ 32
      h4 = (d + h4) % 2 ^ 32
      h5 = (e + h5) % 2 ^ 32
    end
    H[1], H[2], H[3], H[4], H[5] = h1, h2, h3, h4, h5
  end

  function keccak_feed(lanes_lo, lanes_hi, str, offs, size, block_size_in_bytes)
    -- This is an example of a Lua function having 79 local variables :-)
    -- offs >= 0, size >= 0, size is multiple of block_size_in_bytes, block_size_in_bytes is positive multiple of 8
    local RC_lo, RC_hi = sha3_RC_lo, sha3_RC_hi
    local qwords_qty = block_size_in_bytes / 8
    for pos = offs, offs + size - 1, block_size_in_bytes do
      for j = 1, qwords_qty do
        local a, b, c, d = byte(str, pos + 1, pos + 4)
        lanes_lo[j] = XOR(lanes_lo[j], ((d * 256 + c) * 256 + b) * 256 + a)
        pos = pos + 8
        a, b, c, d = byte(str, pos - 3, pos)
        lanes_hi[j] = XOR(lanes_hi[j], ((d * 256 + c) * 256 + b) * 256 + a)
      end
      local L01_lo, L01_hi, L02_lo, L02_hi, L03_lo, L03_hi, L04_lo, L04_hi, L05_lo, L05_hi, L06_lo, L06_hi, L07_lo, L07_hi, L08_lo, L08_hi, L09_lo, L09_hi, L10_lo, L10_hi, L11_lo, L11_hi, L12_lo, L12_hi, L13_lo, L13_hi, L14_lo, L14_hi, L15_lo, L15_hi, L16_lo, L16_hi, L17_lo, L17_hi, L18_lo, L18_hi, L19_lo, L19_hi, L20_lo, L20_hi, L21_lo, L21_hi, L22_lo, L22_hi, L23_lo, L23_hi, L24_lo, L24_hi, L25_lo, L25_hi =
        lanes_lo[1],
        lanes_hi[1],
        lanes_lo[2],
        lanes_hi[2],
        lanes_lo[3],
        lanes_hi[3],
        lanes_lo[4],
        lanes_hi[4],
        lanes_lo[5],
        lanes_hi[5],
        lanes_lo[6],
        lanes_hi[6],
        lanes_lo[7],
        lanes_hi[7],
        lanes_lo[8],
        lanes_hi[8],
        lanes_lo[9],
        lanes_hi[9],
        lanes_lo[10],
        lanes_hi[10],
        lanes_lo[11],
        lanes_hi[11],
        lanes_lo[12],
        lanes_hi[12],
        lanes_lo[13],
        lanes_hi[13],
        lanes_lo[14],
        lanes_hi[14],
        lanes_lo[15],
        lanes_hi[15],
        lanes_lo[16],
        lanes_hi[16],
        lanes_lo[17],
        lanes_hi[17],
        lanes_lo[18],
        lanes_hi[18],
        lanes_lo[19],
        lanes_hi[19],
        lanes_lo[20],
        lanes_hi[20],
        lanes_lo[21],
        lanes_hi[21],
        lanes_lo[22],
        lanes_hi[22],
        lanes_lo[23],
        lanes_hi[23],
        lanes_lo[24],
        lanes_hi[24],
        lanes_lo[25],
        lanes_hi[25]
      for round_idx = 1, 24 do
        local C1_lo = XOR(L01_lo, L06_lo, L11_lo, L16_lo, L21_lo)
        local C1_hi = XOR(L01_hi, L06_hi, L11_hi, L16_hi, L21_hi)
        local C2_lo = XOR(L02_lo, L07_lo, L12_lo, L17_lo, L22_lo)
        local C2_hi = XOR(L02_hi, L07_hi, L12_hi, L17_hi, L22_hi)
        local C3_lo = XOR(L03_lo, L08_lo, L13_lo, L18_lo, L23_lo)
        local C3_hi = XOR(L03_hi, L08_hi, L13_hi, L18_hi, L23_hi)
        local C4_lo = XOR(L04_lo, L09_lo, L14_lo, L19_lo, L24_lo)
        local C4_hi = XOR(L04_hi, L09_hi, L14_hi, L19_hi, L24_hi)
        local C5_lo = XOR(L05_lo, L10_lo, L15_lo, L20_lo, L25_lo)
        local C5_hi = XOR(L05_hi, L10_hi, L15_hi, L20_hi, L25_hi)
        local D_lo = XOR(C1_lo, C3_lo * 2 + (C3_hi % 2 ^ 32 - C3_hi % 2 ^ 31) / 2 ^ 31)
        local D_hi = XOR(C1_hi, C3_hi * 2 + (C3_lo % 2 ^ 32 - C3_lo % 2 ^ 31) / 2 ^ 31)
        local T0_lo = XOR(D_lo, L02_lo)
        local T0_hi = XOR(D_hi, L02_hi)
        local T1_lo = XOR(D_lo, L07_lo)
        local T1_hi = XOR(D_hi, L07_hi)
        local T2_lo = XOR(D_lo, L12_lo)
        local T2_hi = XOR(D_hi, L12_hi)
        local T3_lo = XOR(D_lo, L17_lo)
        local T3_hi = XOR(D_hi, L17_hi)
        local T4_lo = XOR(D_lo, L22_lo)
        local T4_hi = XOR(D_hi, L22_hi)
        L02_lo = (T1_lo % 2 ^ 32 - T1_lo % 2 ^ 20) / 2 ^ 20 + T1_hi * 2 ^ 12
        L02_hi = (T1_hi % 2 ^ 32 - T1_hi % 2 ^ 20) / 2 ^ 20 + T1_lo * 2 ^ 12
        L07_lo = (T3_lo % 2 ^ 32 - T3_lo % 2 ^ 19) / 2 ^ 19 + T3_hi * 2 ^ 13
        L07_hi = (T3_hi % 2 ^ 32 - T3_hi % 2 ^ 19) / 2 ^ 19 + T3_lo * 2 ^ 13
        L12_lo = T0_lo * 2 + (T0_hi % 2 ^ 32 - T0_hi % 2 ^ 31) / 2 ^ 31
        L12_hi = T0_hi * 2 + (T0_lo % 2 ^ 32 - T0_lo % 2 ^ 31) / 2 ^ 31
        L17_lo = T2_lo * 2 ^ 10 + (T2_hi % 2 ^ 32 - T2_hi % 2 ^ 22) / 2 ^ 22
        L17_hi = T2_hi * 2 ^ 10 + (T2_lo % 2 ^ 32 - T2_lo % 2 ^ 22) / 2 ^ 22
        L22_lo = T4_lo * 2 ^ 2 + (T4_hi % 2 ^ 32 - T4_hi % 2 ^ 30) / 2 ^ 30
        L22_hi = T4_hi * 2 ^ 2 + (T4_lo % 2 ^ 32 - T4_lo % 2 ^ 30) / 2 ^ 30
        D_lo = XOR(C2_lo, C4_lo * 2 + (C4_hi % 2 ^ 32 - C4_hi % 2 ^ 31) / 2 ^ 31)
        D_hi = XOR(C2_hi, C4_hi * 2 + (C4_lo % 2 ^ 32 - C4_lo % 2 ^ 31) / 2 ^ 31)
        T0_lo = XOR(D_lo, L03_lo)
        T0_hi = XOR(D_hi, L03_hi)
        T1_lo = XOR(D_lo, L08_lo)
        T1_hi = XOR(D_hi, L08_hi)
        T2_lo = XOR(D_lo, L13_lo)
        T2_hi = XOR(D_hi, L13_hi)
        T3_lo = XOR(D_lo, L18_lo)
        T3_hi = XOR(D_hi, L18_hi)
        T4_lo = XOR(D_lo, L23_lo)
        T4_hi = XOR(D_hi, L23_hi)
        L03_lo = (T2_lo % 2 ^ 32 - T2_lo % 2 ^ 21) / 2 ^ 21 + T2_hi * 2 ^ 11
        L03_hi = (T2_hi % 2 ^ 32 - T2_hi % 2 ^ 21) / 2 ^ 21 + T2_lo * 2 ^ 11
        L08_lo = (T4_lo % 2 ^ 32 - T4_lo % 2 ^ 3) / 2 ^ 3 + T4_hi * 2 ^ 29 % 2 ^ 32
        L08_hi = (T4_hi % 2 ^ 32 - T4_hi % 2 ^ 3) / 2 ^ 3 + T4_lo * 2 ^ 29 % 2 ^ 32
        L13_lo = T1_lo * 2 ^ 6 + (T1_hi % 2 ^ 32 - T1_hi % 2 ^ 26) / 2 ^ 26
        L13_hi = T1_hi * 2 ^ 6 + (T1_lo % 2 ^ 32 - T1_lo % 2 ^ 26) / 2 ^ 26
        L18_lo = T3_lo * 2 ^ 15 + (T3_hi % 2 ^ 32 - T3_hi % 2 ^ 17) / 2 ^ 17
        L18_hi = T3_hi * 2 ^ 15 + (T3_lo % 2 ^ 32 - T3_lo % 2 ^ 17) / 2 ^ 17
        L23_lo = (T0_lo % 2 ^ 32 - T0_lo % 2 ^ 2) / 2 ^ 2 + T0_hi * 2 ^ 30 % 2 ^ 32
        L23_hi = (T0_hi % 2 ^ 32 - T0_hi % 2 ^ 2) / 2 ^ 2 + T0_lo * 2 ^ 30 % 2 ^ 32
        D_lo = XOR(C3_lo, C5_lo * 2 + (C5_hi % 2 ^ 32 - C5_hi % 2 ^ 31) / 2 ^ 31)
        D_hi = XOR(C3_hi, C5_hi * 2 + (C5_lo % 2 ^ 32 - C5_lo % 2 ^ 31) / 2 ^ 31)
        T0_lo = XOR(D_lo, L04_lo)
        T0_hi = XOR(D_hi, L04_hi)
        T1_lo = XOR(D_lo, L09_lo)
        T1_hi = XOR(D_hi, L09_hi)
        T2_lo = XOR(D_lo, L14_lo)
        T2_hi = XOR(D_hi, L14_hi)
        T3_lo = XOR(D_lo, L19_lo)
        T3_hi = XOR(D_hi, L19_hi)
        T4_lo = XOR(D_lo, L24_lo)
        T4_hi = XOR(D_hi, L24_hi)
        L04_lo = T3_lo * 2 ^ 21 % 2 ^ 32 + (T3_hi % 2 ^ 32 - T3_hi % 2 ^ 11) / 2 ^ 11
        L04_hi = T3_hi * 2 ^ 21 % 2 ^ 32 + (T3_lo % 2 ^ 32 - T3_lo % 2 ^ 11) / 2 ^ 11
        L09_lo = T0_lo * 2 ^ 28 % 2 ^ 32 + (T0_hi % 2 ^ 32 - T0_hi % 2 ^ 4) / 2 ^ 4
        L09_hi = T0_hi * 2 ^ 28 % 2 ^ 32 + (T0_lo % 2 ^ 32 - T0_lo % 2 ^ 4) / 2 ^ 4
        L14_lo = T2_lo * 2 ^ 25 % 2 ^ 32 + (T2_hi % 2 ^ 32 - T2_hi % 2 ^ 7) / 2 ^ 7
        L14_hi = T2_hi * 2 ^ 25 % 2 ^ 32 + (T2_lo % 2 ^ 32 - T2_lo % 2 ^ 7) / 2 ^ 7
        L19_lo = (T4_lo % 2 ^ 32 - T4_lo % 2 ^ 8) / 2 ^ 8 + T4_hi * 2 ^ 24 % 2 ^ 32
        L19_hi = (T4_hi % 2 ^ 32 - T4_hi % 2 ^ 8) / 2 ^ 8 + T4_lo * 2 ^ 24 % 2 ^ 32
        L24_lo = (T1_lo % 2 ^ 32 - T1_lo % 2 ^ 9) / 2 ^ 9 + T1_hi * 2 ^ 23 % 2 ^ 32
        L24_hi = (T1_hi % 2 ^ 32 - T1_hi % 2 ^ 9) / 2 ^ 9 + T1_lo * 2 ^ 23 % 2 ^ 32
        D_lo = XOR(C4_lo, C1_lo * 2 + (C1_hi % 2 ^ 32 - C1_hi % 2 ^ 31) / 2 ^ 31)
        D_hi = XOR(C4_hi, C1_hi * 2 + (C1_lo % 2 ^ 32 - C1_lo % 2 ^ 31) / 2 ^ 31)
        T0_lo = XOR(D_lo, L05_lo)
        T0_hi = XOR(D_hi, L05_hi)
        T1_lo = XOR(D_lo, L10_lo)
        T1_hi = XOR(D_hi, L10_hi)
        T2_lo = XOR(D_lo, L15_lo)
        T2_hi = XOR(D_hi, L15_hi)
        T3_lo = XOR(D_lo, L20_lo)
        T3_hi = XOR(D_hi, L20_hi)
        T4_lo = XOR(D_lo, L25_lo)
        T4_hi = XOR(D_hi, L25_hi)
        L05_lo = T4_lo * 2 ^ 14 + (T4_hi % 2 ^ 32 - T4_hi % 2 ^ 18) / 2 ^ 18
        L05_hi = T4_hi * 2 ^ 14 + (T4_lo % 2 ^ 32 - T4_lo % 2 ^ 18) / 2 ^ 18
        L10_lo = T1_lo * 2 ^ 20 % 2 ^ 32 + (T1_hi % 2 ^ 32 - T1_hi % 2 ^ 12) / 2 ^ 12
        L10_hi = T1_hi * 2 ^ 20 % 2 ^ 32 + (T1_lo % 2 ^ 32 - T1_lo % 2 ^ 12) / 2 ^ 12
        L15_lo = T3_lo * 2 ^ 8 + (T3_hi % 2 ^ 32 - T3_hi % 2 ^ 24) / 2 ^ 24
        L15_hi = T3_hi * 2 ^ 8 + (T3_lo % 2 ^ 32 - T3_lo % 2 ^ 24) / 2 ^ 24
        L20_lo = T0_lo * 2 ^ 27 % 2 ^ 32 + (T0_hi % 2 ^ 32 - T0_hi % 2 ^ 5) / 2 ^ 5
        L20_hi = T0_hi * 2 ^ 27 % 2 ^ 32 + (T0_lo % 2 ^ 32 - T0_lo % 2 ^ 5) / 2 ^ 5
        L25_lo = (T2_lo % 2 ^ 32 - T2_lo % 2 ^ 25) / 2 ^ 25 + T2_hi * 2 ^ 7
        L25_hi = (T2_hi % 2 ^ 32 - T2_hi % 2 ^ 25) / 2 ^ 25 + T2_lo * 2 ^ 7
        D_lo = XOR(C5_lo, C2_lo * 2 + (C2_hi % 2 ^ 32 - C2_hi % 2 ^ 31) / 2 ^ 31)
        D_hi = XOR(C5_hi, C2_hi * 2 + (C2_lo % 2 ^ 32 - C2_lo % 2 ^ 31) / 2 ^ 31)
        T1_lo = XOR(D_lo, L06_lo)
        T1_hi = XOR(D_hi, L06_hi)
        T2_lo = XOR(D_lo, L11_lo)
        T2_hi = XOR(D_hi, L11_hi)
        T3_lo = XOR(D_lo, L16_lo)
        T3_hi = XOR(D_hi, L16_hi)
        T4_lo = XOR(D_lo, L21_lo)
        T4_hi = XOR(D_hi, L21_hi)
        L06_lo = T2_lo * 2 ^ 3 + (T2_hi % 2 ^ 32 - T2_hi % 2 ^ 29) / 2 ^ 29
        L06_hi = T2_hi * 2 ^ 3 + (T2_lo % 2 ^ 32 - T2_lo % 2 ^ 29) / 2 ^ 29
        L11_lo = T4_lo * 2 ^ 18 + (T4_hi % 2 ^ 32 - T4_hi % 2 ^ 14) / 2 ^ 14
        L11_hi = T4_hi * 2 ^ 18 + (T4_lo % 2 ^ 32 - T4_lo % 2 ^ 14) / 2 ^ 14
        L16_lo = (T1_lo % 2 ^ 32 - T1_lo % 2 ^ 28) / 2 ^ 28 + T1_hi * 2 ^ 4
        L16_hi = (T1_hi % 2 ^ 32 - T1_hi % 2 ^ 28) / 2 ^ 28 + T1_lo * 2 ^ 4
        L21_lo = (T3_lo % 2 ^ 32 - T3_lo % 2 ^ 23) / 2 ^ 23 + T3_hi * 2 ^ 9
        L21_hi = (T3_hi % 2 ^ 32 - T3_hi % 2 ^ 23) / 2 ^ 23 + T3_lo * 2 ^ 9
        L01_lo = XOR(D_lo, L01_lo)
        L01_hi = XOR(D_hi, L01_hi)
        L01_lo, L02_lo, L03_lo, L04_lo, L05_lo =
          XOR(L01_lo, AND(-1 - L02_lo, L03_lo)),
          XOR(L02_lo, AND(-1 - L03_lo, L04_lo)),
          XOR(L03_lo, AND(-1 - L04_lo, L05_lo)),
          XOR(L04_lo, AND(-1 - L05_lo, L01_lo)),
          XOR(L05_lo, AND(-1 - L01_lo, L02_lo))
        L01_hi, L02_hi, L03_hi, L04_hi, L05_hi =
          XOR(L01_hi, AND(-1 - L02_hi, L03_hi)),
          XOR(L02_hi, AND(-1 - L03_hi, L04_hi)),
          XOR(L03_hi, AND(-1 - L04_hi, L05_hi)),
          XOR(L04_hi, AND(-1 - L05_hi, L01_hi)),
          XOR(L05_hi, AND(-1 - L01_hi, L02_hi))
        L06_lo, L07_lo, L08_lo, L09_lo, L10_lo =
          XOR(L09_lo, AND(-1 - L10_lo, L06_lo)),
          XOR(L10_lo, AND(-1 - L06_lo, L07_lo)),
          XOR(L06_lo, AND(-1 - L07_lo, L08_lo)),
          XOR(L07_lo, AND(-1 - L08_lo, L09_lo)),
          XOR(L08_lo, AND(-1 - L09_lo, L10_lo))
        L06_hi, L07_hi, L08_hi, L09_hi, L10_hi =
          XOR(L09_hi, AND(-1 - L10_hi, L06_hi)),
          XOR(L10_hi, AND(-1 - L06_hi, L07_hi)),
          XOR(L06_hi, AND(-1 - L07_hi, L08_hi)),
          XOR(L07_hi, AND(-1 - L08_hi, L09_hi)),
          XOR(L08_hi, AND(-1 - L09_hi, L10_hi))
        L11_lo, L12_lo, L13_lo, L14_lo, L15_lo =
          XOR(L12_lo, AND(-1 - L13_lo, L14_lo)),
          XOR(L13_lo, AND(-1 - L14_lo, L15_lo)),
          XOR(L14_lo, AND(-1 - L15_lo, L11_lo)),
          XOR(L15_lo, AND(-1 - L11_lo, L12_lo)),
          XOR(L11_lo, AND(-1 - L12_lo, L13_lo))
        L11_hi, L12_hi, L13_hi, L14_hi, L15_hi =
          XOR(L12_hi, AND(-1 - L13_hi, L14_hi)),
          XOR(L13_hi, AND(-1 - L14_hi, L15_hi)),
          XOR(L14_hi, AND(-1 - L15_hi, L11_hi)),
          XOR(L15_hi, AND(-1 - L11_hi, L12_hi)),
          XOR(L11_hi, AND(-1 - L12_hi, L13_hi))
        L16_lo, L17_lo, L18_lo, L19_lo, L20_lo =
          XOR(L20_lo, AND(-1 - L16_lo, L17_lo)),
          XOR(L16_lo, AND(-1 - L17_lo, L18_lo)),
          XOR(L17_lo, AND(-1 - L18_lo, L19_lo)),
          XOR(L18_lo, AND(-1 - L19_lo, L20_lo)),
          XOR(L19_lo, AND(-1 - L20_lo, L16_lo))
        L16_hi, L17_hi, L18_hi, L19_hi, L20_hi =
          XOR(L20_hi, AND(-1 - L16_hi, L17_hi)),
          XOR(L16_hi, AND(-1 - L17_hi, L18_hi)),
          XOR(L17_hi, AND(-1 - L18_hi, L19_hi)),
          XOR(L18_hi, AND(-1 - L19_hi, L20_hi)),
          XOR(L19_hi, AND(-1 - L20_hi, L16_hi))
        L21_lo, L22_lo, L23_lo, L24_lo, L25_lo =
          XOR(L23_lo, AND(-1 - L24_lo, L25_lo)),
          XOR(L24_lo, AND(-1 - L25_lo, L21_lo)),
          XOR(L25_lo, AND(-1 - L21_lo, L22_lo)),
          XOR(L21_lo, AND(-1 - L22_lo, L23_lo)),
          XOR(L22_lo, AND(-1 - L23_lo, L24_lo))
        L21_hi, L22_hi, L23_hi, L24_hi, L25_hi =
          XOR(L23_hi, AND(-1 - L24_hi, L25_hi)),
          XOR(L24_hi, AND(-1 - L25_hi, L21_hi)),
          XOR(L25_hi, AND(-1 - L21_hi, L22_hi)),
          XOR(L21_hi, AND(-1 - L22_hi, L23_hi)),
          XOR(L22_hi, AND(-1 - L23_hi, L24_hi))
        L01_lo = XOR(L01_lo, RC_lo[round_idx])
        L01_hi = L01_hi + RC_hi[round_idx] -- RC_hi[] is either 0 or 0x80000000, so we could use fast addition instead of slow XOR
      end
      lanes_lo[1] = L01_lo
      lanes_hi[1] = L01_hi
      lanes_lo[2] = L02_lo
      lanes_hi[2] = L02_hi
      lanes_lo[3] = L03_lo
      lanes_hi[3] = L03_hi
      lanes_lo[4] = L04_lo
      lanes_hi[4] = L04_hi
      lanes_lo[5] = L05_lo
      lanes_hi[5] = L05_hi
      lanes_lo[6] = L06_lo
      lanes_hi[6] = L06_hi
      lanes_lo[7] = L07_lo
      lanes_hi[7] = L07_hi
      lanes_lo[8] = L08_lo
      lanes_hi[8] = L08_hi
      lanes_lo[9] = L09_lo
      lanes_hi[9] = L09_hi
      lanes_lo[10] = L10_lo
      lanes_hi[10] = L10_hi
      lanes_lo[11] = L11_lo
      lanes_hi[11] = L11_hi
      lanes_lo[12] = L12_lo
      lanes_hi[12] = L12_hi
      lanes_lo[13] = L13_lo
      lanes_hi[13] = L13_hi
      lanes_lo[14] = L14_lo
      lanes_hi[14] = L14_hi
      lanes_lo[15] = L15_lo
      lanes_hi[15] = L15_hi
      lanes_lo[16] = L16_lo
      lanes_hi[16] = L16_hi
      lanes_lo[17] = L17_lo
      lanes_hi[17] = L17_hi
      lanes_lo[18] = L18_lo
      lanes_hi[18] = L18_hi
      lanes_lo[19] = L19_lo
      lanes_hi[19] = L19_hi
      lanes_lo[20] = L20_lo
      lanes_hi[20] = L20_hi
      lanes_lo[21] = L21_lo
      lanes_hi[21] = L21_hi
      lanes_lo[22] = L22_lo
      lanes_hi[22] = L22_hi
      lanes_lo[23] = L23_lo
      lanes_hi[23] = L23_hi
      lanes_lo[24] = L24_lo
      lanes_hi[24] = L24_hi
      lanes_lo[25] = L25_lo
      lanes_hi[25] = L25_hi
    end
  end

  function blake2s_feed_64(H, str, offs, size, bytes_compressed, last_block_size, is_last_node)
    -- offs >= 0, size >= 0, size is multiple of 64
    local W = common_W
    local h1, h2, h3, h4, h5, h6, h7, h8 = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for pos = offs, offs + size - 1, 64 do
      if str then
        for j = 1, 16 do
          pos = pos + 4
          local a, b, c, d = byte(str, pos - 3, pos)
          W[j] = ((d * 256 + c) * 256 + b) * 256 + a
        end
      end
      local v0, v1, v2, v3, v4, v5, v6, v7 = h1, h2, h3, h4, h5, h6, h7, h8
      local v8, v9, vA, vB, vC, vD, vE, vF =
        sha2_H_hi[1], sha2_H_hi[2], sha2_H_hi[3], sha2_H_hi[4], sha2_H_hi[5], sha2_H_hi[6], sha2_H_hi[7], sha2_H_hi[8]
      bytes_compressed = bytes_compressed + (last_block_size or 64)
      local t0 = bytes_compressed % 2 ^ 32
      local t1 = (bytes_compressed - t0) / 2 ^ 32
      vC = XOR(vC, t0) -- t0 = low_4_bytes(bytes_compressed)
      vD = XOR(vD, t1) -- t1 = high_4_bytes(bytes_compressed)
      if last_block_size then -- flag f0
        vE = -1 - vE
      end
      if is_last_node then -- flag f1
        vF = -1 - vF
      end
      for j = 1, 10 do
        local row = sigma[j]
        v0 = v0 + v4 + W[row[1]]
        vC = XOR(vC, v0) % 2 ^ 32 / 2 ^ 16
        vC = vC % 1 * (2 ^ 32 - 1) + vC
        v8 = v8 + vC
        v4 = XOR(v4, v8) % 2 ^ 32 / 2 ^ 12
        v4 = v4 % 1 * (2 ^ 32 - 1) + v4
        v0 = v0 + v4 + W[row[2]]
        vC = XOR(vC, v0) % 2 ^ 32 / 2 ^ 8
        vC = vC % 1 * (2 ^ 32 - 1) + vC
        v8 = v8 + vC
        v4 = XOR(v4, v8) % 2 ^ 32 / 2 ^ 7
        v4 = v4 % 1 * (2 ^ 32 - 1) + v4
        v1 = v1 + v5 + W[row[3]]
        vD = XOR(vD, v1) % 2 ^ 32 / 2 ^ 16
        vD = vD % 1 * (2 ^ 32 - 1) + vD
        v9 = v9 + vD
        v5 = XOR(v5, v9) % 2 ^ 32 / 2 ^ 12
        v5 = v5 % 1 * (2 ^ 32 - 1) + v5
        v1 = v1 + v5 + W[row[4]]
        vD = XOR(vD, v1) % 2 ^ 32 / 2 ^ 8
        vD = vD % 1 * (2 ^ 32 - 1) + vD
        v9 = v9 + vD
        v5 = XOR(v5, v9) % 2 ^ 32 / 2 ^ 7
        v5 = v5 % 1 * (2 ^ 32 - 1) + v5
        v2 = v2 + v6 + W[row[5]]
        vE = XOR(vE, v2) % 2 ^ 32 / 2 ^ 16
        vE = vE % 1 * (2 ^ 32 - 1) + vE
        vA = vA + vE
        v6 = XOR(v6, vA) % 2 ^ 32 / 2 ^ 12
        v6 = v6 % 1 * (2 ^ 32 - 1) + v6
        v2 = v2 + v6 + W[row[6]]
        vE = XOR(vE, v2) % 2 ^ 32 / 2 ^ 8
        vE = vE % 1 * (2 ^ 32 - 1) + vE
        vA = vA + vE
        v6 = XOR(v6, vA) % 2 ^ 32 / 2 ^ 7
        v6 = v6 % 1 * (2 ^ 32 - 1) + v6
        v3 = v3 + v7 + W[row[7]]
        vF = XOR(vF, v3) % 2 ^ 32 / 2 ^ 16
        vF = vF % 1 * (2 ^ 32 - 1) + vF
        vB = vB + vF
        v7 = XOR(v7, vB) % 2 ^ 32 / 2 ^ 12
        v7 = v7 % 1 * (2 ^ 32 - 1) + v7
        v3 = v3 + v7 + W[row[8]]
        vF = XOR(vF, v3) % 2 ^ 32 / 2 ^ 8
        vF = vF % 1 * (2 ^ 32 - 1) + vF
        vB = vB + vF
        v7 = XOR(v7, vB) % 2 ^ 32 / 2 ^ 7
        v7 = v7 % 1 * (2 ^ 32 - 1) + v7
        v0 = v0 + v5 + W[row[9]]
        vF = XOR(vF, v0) % 2 ^ 32 / 2 ^ 16
        vF = vF % 1 * (2 ^ 32 - 1) + vF
        vA = vA + vF
        v5 = XOR(v5, vA) % 2 ^ 32 / 2 ^ 12
        v5 = v5 % 1 * (2 ^ 32 - 1) + v5
        v0 = v0 + v5 + W[row[10]]
        vF = XOR(vF, v0) % 2 ^ 32 / 2 ^ 8
        vF = vF % 1 * (2 ^ 32 - 1) + vF
        vA = vA + vF
        v5 = XOR(v5, vA) % 2 ^ 32 / 2 ^ 7
        v5 = v5 % 1 * (2 ^ 32 - 1) + v5
        v1 = v1 + v6 + W[row[11]]
        vC = XOR(vC, v1) % 2 ^ 32 / 2 ^ 16
        vC = vC % 1 * (2 ^ 32 - 1) + vC
        vB = vB + vC
        v6 = XOR(v6, vB) % 2 ^ 32 / 2 ^ 12
        v6 = v6 % 1 * (2 ^ 32 - 1) + v6
        v1 = v1 + v6 + W[row[12]]
        vC = XOR(vC, v1) % 2 ^ 32 / 2 ^ 8
        vC = vC % 1 * (2 ^ 32 - 1) + vC
        vB = vB + vC
        v6 = XOR(v6, vB) % 2 ^ 32 / 2 ^ 7
        v6 = v6 % 1 * (2 ^ 32 - 1) + v6
        v2 = v2 + v7 + W[row[13]]
        vD = XOR(vD, v2) % 2 ^ 32 / 2 ^ 16
        vD = vD % 1 * (2 ^ 32 - 1) + vD
        v8 = v8 + vD
        v7 = XOR(v7, v8) % 2 ^ 32 / 2 ^ 12
        v7 = v7 % 1 * (2 ^ 32 - 1) + v7
        v2 = v2 + v7 + W[row[14]]
        vD = XOR(vD, v2) % 2 ^ 32 / 2 ^ 8
        vD = vD % 1 * (2 ^ 32 - 1) + vD
        v8 = v8 + vD
        v7 = XOR(v7, v8) % 2 ^ 32 / 2 ^ 7
        v7 = v7 % 1 * (2 ^ 32 - 1) + v7
        v3 = v3 + v4 + W[row[15]]
        vE = XOR(vE, v3) % 2 ^ 32 / 2 ^ 16
        vE = vE % 1 * (2 ^ 32 - 1) + vE
        v9 = v9 + vE
        v4 = XOR(v4, v9) % 2 ^ 32 / 2 ^ 12
        v4 = v4 % 1 * (2 ^ 32 - 1) + v4
        v3 = v3 + v4 + W[row[16]]
        vE = XOR(vE, v3) % 2 ^ 32 / 2 ^ 8
        vE = vE % 1 * (2 ^ 32 - 1) + vE
        v9 = v9 + vE
        v4 = XOR(v4, v9) % 2 ^ 32 / 2 ^ 7
        v4 = v4 % 1 * (2 ^ 32 - 1) + v4
      end
      h1 = XOR(h1, v0, v8)
      h2 = XOR(h2, v1, v9)
      h3 = XOR(h3, v2, vA)
      h4 = XOR(h4, v3, vB)
      h5 = XOR(h5, v4, vC)
      h6 = XOR(h6, v5, vD)
      h7 = XOR(h7, v6, vE)
      h8 = XOR(h8, v7, vF)
    end
    H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] = h1, h2, h3, h4, h5, h6, h7, h8
    return bytes_compressed
  end

  function blake2b_feed_128(H_lo, H_hi, str, offs, size, bytes_compressed, last_block_size, is_last_node)
    -- offs >= 0, size >= 0, size is multiple of 128
    local W = common_W
    local h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo =
      H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8]
    local h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi =
      H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8]
    for pos = offs, offs + size - 1, 128 do
      if str then
        for j = 1, 32 do
          pos = pos + 4
          local a, b, c, d = byte(str, pos - 3, pos)
          W[j] = ((d * 256 + c) * 256 + b) * 256 + a
        end
      end
      local v0_lo, v1_lo, v2_lo, v3_lo, v4_lo, v5_lo, v6_lo, v7_lo =
        h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo
      local v0_hi, v1_hi, v2_hi, v3_hi, v4_hi, v5_hi, v6_hi, v7_hi =
        h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi
      local v8_lo, v9_lo, vA_lo, vB_lo, vC_lo, vD_lo, vE_lo, vF_lo =
        sha2_H_lo[1], sha2_H_lo[2], sha2_H_lo[3], sha2_H_lo[4], sha2_H_lo[5], sha2_H_lo[6], sha2_H_lo[7], sha2_H_lo[8]
      local v8_hi, v9_hi, vA_hi, vB_hi, vC_hi, vD_hi, vE_hi, vF_hi =
        sha2_H_hi[1], sha2_H_hi[2], sha2_H_hi[3], sha2_H_hi[4], sha2_H_hi[5], sha2_H_hi[6], sha2_H_hi[7], sha2_H_hi[8]
      bytes_compressed = bytes_compressed + (last_block_size or 128)
      local t0_lo = bytes_compressed % 2 ^ 32
      local t0_hi = (bytes_compressed - t0_lo) / 2 ^ 32
      vC_lo = XOR(vC_lo, t0_lo) -- t0 = low_8_bytes(bytes_compressed)
      vC_hi = XOR(vC_hi, t0_hi)
      -- t1 = high_8_bytes(bytes_compressed) = 0,  message length is always below 2^53 bytes
      if last_block_size then -- flag f0
        vE_lo = -1 - vE_lo
        vE_hi = -1 - vE_hi
      end
      if is_last_node then -- flag f1
        vF_lo = -1 - vF_lo
        vF_hi = -1 - vF_hi
      end
      for j = 1, 12 do
        local row = sigma[j]
        local k = row[1] * 2
        local z = v0_lo % 2 ^ 32 + v4_lo % 2 ^ 32 + W[k - 1]
        v0_lo = z % 2 ^ 32
        v0_hi = v0_hi + v4_hi + (z - v0_lo) / 2 ^ 32 + W[k]
        vC_lo, vC_hi = XOR(vC_hi, v0_hi), XOR(vC_lo, v0_lo)
        z = v8_lo % 2 ^ 32 + vC_lo % 2 ^ 32
        v8_lo = z % 2 ^ 32
        v8_hi = v8_hi + vC_hi + (z - v8_lo) / 2 ^ 32
        v4_lo, v4_hi = XOR(v4_lo, v8_lo), XOR(v4_hi, v8_hi)
        local z_lo, z_hi = v4_lo % 2 ^ 24, v4_hi % 2 ^ 24
        v4_lo, v4_hi = (v4_lo - z_lo) / 2 ^ 24 % 2 ^ 8 + z_hi * 2 ^ 8, (v4_hi - z_hi) / 2 ^ 24 % 2 ^ 8 + z_lo * 2 ^ 8
        k = row[2] * 2
        z = v0_lo % 2 ^ 32 + v4_lo % 2 ^ 32 + W[k - 1]
        v0_lo = z % 2 ^ 32
        v0_hi = v0_hi + v4_hi + (z - v0_lo) / 2 ^ 32 + W[k]
        vC_lo, vC_hi = XOR(vC_lo, v0_lo), XOR(vC_hi, v0_hi)
        z_lo, z_hi = vC_lo % 2 ^ 16, vC_hi % 2 ^ 16
        vC_lo, vC_hi =
          (vC_lo - z_lo) / 2 ^ 16 % 2 ^ 16 + z_hi * 2 ^ 16, (vC_hi - z_hi) / 2 ^ 16 % 2 ^ 16 + z_lo * 2 ^ 16
        z = v8_lo % 2 ^ 32 + vC_lo % 2 ^ 32
        v8_lo = z % 2 ^ 32
        v8_hi = v8_hi + vC_hi + (z - v8_lo) / 2 ^ 32
        v4_lo, v4_hi = XOR(v4_lo, v8_lo), XOR(v4_hi, v8_hi)
        z_lo, z_hi = v4_lo % 2 ^ 31, v4_hi % 2 ^ 31
        v4_lo, v4_hi = z_lo * 2 ^ 1 + (v4_hi - z_hi) / 2 ^ 31 % 2 ^ 1, z_hi * 2 ^ 1 + (v4_lo - z_lo) / 2 ^ 31 % 2 ^ 1
        k = row[3] * 2
        z = v1_lo % 2 ^ 32 + v5_lo % 2 ^ 32 + W[k - 1]
        v1_lo = z % 2 ^ 32
        v1_hi = v1_hi + v5_hi + (z - v1_lo) / 2 ^ 32 + W[k]
        vD_lo, vD_hi = XOR(vD_hi, v1_hi), XOR(vD_lo, v1_lo)
        z = v9_lo % 2 ^ 32 + vD_lo % 2 ^ 32
        v9_lo = z % 2 ^ 32
        v9_hi = v9_hi + vD_hi + (z - v9_lo) / 2 ^ 32
        v5_lo, v5_hi = XOR(v5_lo, v9_lo), XOR(v5_hi, v9_hi)
        z_lo, z_hi = v5_lo % 2 ^ 24, v5_hi % 2 ^ 24
        v5_lo, v5_hi = (v5_lo - z_lo) / 2 ^ 24 % 2 ^ 8 + z_hi * 2 ^ 8, (v5_hi - z_hi) / 2 ^ 24 % 2 ^ 8 + z_lo * 2 ^ 8
        k = row[4] * 2
        z = v1_lo % 2 ^ 32 + v5_lo % 2 ^ 32 + W[k - 1]
        v1_lo = z % 2 ^ 32
        v1_hi = v1_hi + v5_hi + (z - v1_lo) / 2 ^ 32 + W[k]
        vD_lo, vD_hi = XOR(vD_lo, v1_lo), XOR(vD_hi, v1_hi)
        z_lo, z_hi = vD_lo % 2 ^ 16, vD_hi % 2 ^ 16
        vD_lo, vD_hi =
          (vD_lo - z_lo) / 2 ^ 16 % 2 ^ 16 + z_hi * 2 ^ 16, (vD_hi - z_hi) / 2 ^ 16 % 2 ^ 16 + z_lo * 2 ^ 16
        z = v9_lo % 2 ^ 32 + vD_lo % 2 ^ 32
        v9_lo = z % 2 ^ 32
        v9_hi = v9_hi + vD_hi + (z - v9_lo) / 2 ^ 32
        v5_lo, v5_hi = XOR(v5_lo, v9_lo), XOR(v5_hi, v9_hi)
        z_lo, z_hi = v5_lo % 2 ^ 31, v5_hi % 2 ^ 31
        v5_lo, v5_hi = z_lo * 2 ^ 1 + (v5_hi - z_hi) / 2 ^ 31 % 2 ^ 1, z_hi * 2 ^ 1 + (v5_lo - z_lo) / 2 ^ 31 % 2 ^ 1
        k = row[5] * 2
        z = v2_lo % 2 ^ 32 + v6_lo % 2 ^ 32 + W[k - 1]
        v2_lo = z % 2 ^ 32
        v2_hi = v2_hi + v6_hi + (z - v2_lo) / 2 ^ 32 + W[k]
        vE_lo, vE_hi = XOR(vE_hi, v2_hi), XOR(vE_lo, v2_lo)
        z = vA_lo % 2 ^ 32 + vE_lo % 2 ^ 32
        vA_lo = z % 2 ^ 32
        vA_hi = vA_hi + vE_hi + (z - vA_lo) / 2 ^ 32
        v6_lo, v6_hi = XOR(v6_lo, vA_lo), XOR(v6_hi, vA_hi)
        z_lo, z_hi = v6_lo % 2 ^ 24, v6_hi % 2 ^ 24
        v6_lo, v6_hi = (v6_lo - z_lo) / 2 ^ 24 % 2 ^ 8 + z_hi * 2 ^ 8, (v6_hi - z_hi) / 2 ^ 24 % 2 ^ 8 + z_lo * 2 ^ 8
        k = row[6] * 2
        z = v2_lo % 2 ^ 32 + v6_lo % 2 ^ 32 + W[k - 1]
        v2_lo = z % 2 ^ 32
        v2_hi = v2_hi + v6_hi + (z - v2_lo) / 2 ^ 32 + W[k]
        vE_lo, vE_hi = XOR(vE_lo, v2_lo), XOR(vE_hi, v2_hi)
        z_lo, z_hi = vE_lo % 2 ^ 16, vE_hi % 2 ^ 16
        vE_lo, vE_hi =
          (vE_lo - z_lo) / 2 ^ 16 % 2 ^ 16 + z_hi * 2 ^ 16, (vE_hi - z_hi) / 2 ^ 16 % 2 ^ 16 + z_lo * 2 ^ 16
        z = vA_lo % 2 ^ 32 + vE_lo % 2 ^ 32
        vA_lo = z % 2 ^ 32
        vA_hi = vA_hi + vE_hi + (z - vA_lo) / 2 ^ 32
        v6_lo, v6_hi = XOR(v6_lo, vA_lo), XOR(v6_hi, vA_hi)
        z_lo, z_hi = v6_lo % 2 ^ 31, v6_hi % 2 ^ 31
        v6_lo, v6_hi = z_lo * 2 ^ 1 + (v6_hi - z_hi) / 2 ^ 31 % 2 ^ 1, z_hi * 2 ^ 1 + (v6_lo - z_lo) / 2 ^ 31 % 2 ^ 1
        k = row[7] * 2
        z = v3_lo % 2 ^ 32 + v7_lo % 2 ^ 32 + W[k - 1]
        v3_lo = z % 2 ^ 32
        v3_hi = v3_hi + v7_hi + (z - v3_lo) / 2 ^ 32 + W[k]
        vF_lo, vF_hi = XOR(vF_hi, v3_hi), XOR(vF_lo, v3_lo)
        z = vB_lo % 2 ^ 32 + vF_lo % 2 ^ 32
        vB_lo = z % 2 ^ 32
        vB_hi = vB_hi + vF_hi + (z - vB_lo) / 2 ^ 32
        v7_lo, v7_hi = XOR(v7_lo, vB_lo), XOR(v7_hi, vB_hi)
        z_lo, z_hi = v7_lo % 2 ^ 24, v7_hi % 2 ^ 24
        v7_lo, v7_hi = (v7_lo - z_lo) / 2 ^ 24 % 2 ^ 8 + z_hi * 2 ^ 8, (v7_hi - z_hi) / 2 ^ 24 % 2 ^ 8 + z_lo * 2 ^ 8
        k = row[8] * 2
        z = v3_lo % 2 ^ 32 + v7_lo % 2 ^ 32 + W[k - 1]
        v3_lo = z % 2 ^ 32
        v3_hi = v3_hi + v7_hi + (z - v3_lo) / 2 ^ 32 + W[k]
        vF_lo, vF_hi = XOR(vF_lo, v3_lo), XOR(vF_hi, v3_hi)
        z_lo, z_hi = vF_lo % 2 ^ 16, vF_hi % 2 ^ 16
        vF_lo, vF_hi =
          (vF_lo - z_lo) / 2 ^ 16 % 2 ^ 16 + z_hi * 2 ^ 16, (vF_hi - z_hi) / 2 ^ 16 % 2 ^ 16 + z_lo * 2 ^ 16
        z = vB_lo % 2 ^ 32 + vF_lo % 2 ^ 32
        vB_lo = z % 2 ^ 32
        vB_hi = vB_hi + vF_hi + (z - vB_lo) / 2 ^ 32
        v7_lo, v7_hi = XOR(v7_lo, vB_lo), XOR(v7_hi, vB_hi)
        z_lo, z_hi = v7_lo % 2 ^ 31, v7_hi % 2 ^ 31
        v7_lo, v7_hi = z_lo * 2 ^ 1 + (v7_hi - z_hi) / 2 ^ 31 % 2 ^ 1, z_hi * 2 ^ 1 + (v7_lo - z_lo) / 2 ^ 31 % 2 ^ 1
        k = row[9] * 2
        z = v0_lo % 2 ^ 32 + v5_lo % 2 ^ 32 + W[k - 1]
        v0_lo = z % 2 ^ 32
        v0_hi = v0_hi + v5_hi + (z - v0_lo) / 2 ^ 32 + W[k]
        vF_lo, vF_hi = XOR(vF_hi, v0_hi), XOR(vF_lo, v0_lo)
        z = vA_lo % 2 ^ 32 + vF_lo % 2 ^ 32
        vA_lo = z % 2 ^ 32
        vA_hi = vA_hi + vF_hi + (z - vA_lo) / 2 ^ 32
        v5_lo, v5_hi = XOR(v5_lo, vA_lo), XOR(v5_hi, vA_hi)
        z_lo, z_hi = v5_lo % 2 ^ 24, v5_hi % 2 ^ 24
        v5_lo, v5_hi = (v5_lo - z_lo) / 2 ^ 24 % 2 ^ 8 + z_hi * 2 ^ 8, (v5_hi - z_hi) / 2 ^ 24 % 2 ^ 8 + z_lo * 2 ^ 8
        k = row[10] * 2
        z = v0_lo % 2 ^ 32 + v5_lo % 2 ^ 32 + W[k - 1]
        v0_lo = z % 2 ^ 32
        v0_hi = v0_hi + v5_hi + (z - v0_lo) / 2 ^ 32 + W[k]
        vF_lo, vF_hi = XOR(vF_lo, v0_lo), XOR(vF_hi, v0_hi)
        z_lo, z_hi = vF_lo % 2 ^ 16, vF_hi % 2 ^ 16
        vF_lo, vF_hi =
          (vF_lo - z_lo) / 2 ^ 16 % 2 ^ 16 + z_hi * 2 ^ 16, (vF_hi - z_hi) / 2 ^ 16 % 2 ^ 16 + z_lo * 2 ^ 16
        z = vA_lo % 2 ^ 32 + vF_lo % 2 ^ 32
        vA_lo = z % 2 ^ 32
        vA_hi = vA_hi + vF_hi + (z - vA_lo) / 2 ^ 32
        v5_lo, v5_hi = XOR(v5_lo, vA_lo), XOR(v5_hi, vA_hi)
        z_lo, z_hi = v5_lo % 2 ^ 31, v5_hi % 2 ^ 31
        v5_lo, v5_hi = z_lo * 2 ^ 1 + (v5_hi - z_hi) / 2 ^ 31 % 2 ^ 1, z_hi * 2 ^ 1 + (v5_lo - z_lo) / 2 ^ 31 % 2 ^ 1
        k = row[11] * 2
        z = v1_lo % 2 ^ 32 + v6_lo % 2 ^ 32 + W[k - 1]
        v1_lo = z % 2 ^ 32
        v1_hi = v1_hi + v6_hi + (z - v1_lo) / 2 ^ 32 + W[k]
        vC_lo, vC_hi = XOR(vC_hi, v1_hi), XOR(vC_lo, v1_lo)
        z = vB_lo % 2 ^ 32 + vC_lo % 2 ^ 32
        vB_lo = z % 2 ^ 32
        vB_hi = vB_hi + vC_hi + (z - vB_lo) / 2 ^ 32
        v6_lo, v6_hi = XOR(v6_lo, vB_lo), XOR(v6_hi, vB_hi)
        z_lo, z_hi = v6_lo % 2 ^ 24, v6_hi % 2 ^ 24
        v6_lo, v6_hi = (v6_lo - z_lo) / 2 ^ 24 % 2 ^ 8 + z_hi * 2 ^ 8, (v6_hi - z_hi) / 2 ^ 24 % 2 ^ 8 + z_lo * 2 ^ 8
        k = row[12] * 2
        z = v1_lo % 2 ^ 32 + v6_lo % 2 ^ 32 + W[k - 1]
        v1_lo = z % 2 ^ 32
        v1_hi = v1_hi + v6_hi + (z - v1_lo) / 2 ^ 32 + W[k]
        vC_lo, vC_hi = XOR(vC_lo, v1_lo), XOR(vC_hi, v1_hi)
        z_lo, z_hi = vC_lo % 2 ^ 16, vC_hi % 2 ^ 16
        vC_lo, vC_hi =
          (vC_lo - z_lo) / 2 ^ 16 % 2 ^ 16 + z_hi * 2 ^ 16, (vC_hi - z_hi) / 2 ^ 16 % 2 ^ 16 + z_lo * 2 ^ 16
        z = vB_lo % 2 ^ 32 + vC_lo % 2 ^ 32
        vB_lo = z % 2 ^ 32
        vB_hi = vB_hi + vC_hi + (z - vB_lo) / 2 ^ 32
        v6_lo, v6_hi = XOR(v6_lo, vB_lo), XOR(v6_hi, vB_hi)
        z_lo, z_hi = v6_lo % 2 ^ 31, v6_hi % 2 ^ 31
        v6_lo, v6_hi = z_lo * 2 ^ 1 + (v6_hi - z_hi) / 2 ^ 31 % 2 ^ 1, z_hi * 2 ^ 1 + (v6_lo - z_lo) / 2 ^ 31 % 2 ^ 1
        k = row[13] * 2
        z = v2_lo % 2 ^ 32 + v7_lo % 2 ^ 32 + W[k - 1]
        v2_lo = z % 2 ^ 32
        v2_hi = v2_hi + v7_hi + (z - v2_lo) / 2 ^ 32 + W[k]
        vD_lo, vD_hi = XOR(vD_hi, v2_hi), XOR(vD_lo, v2_lo)
        z = v8_lo % 2 ^ 32 + vD_lo % 2 ^ 32
        v8_lo = z % 2 ^ 32
        v8_hi = v8_hi + vD_hi + (z - v8_lo) / 2 ^ 32
        v7_lo, v7_hi = XOR(v7_lo, v8_lo), XOR(v7_hi, v8_hi)
        z_lo, z_hi = v7_lo % 2 ^ 24, v7_hi % 2 ^ 24
        v7_lo, v7_hi = (v7_lo - z_lo) / 2 ^ 24 % 2 ^ 8 + z_hi * 2 ^ 8, (v7_hi - z_hi) / 2 ^ 24 % 2 ^ 8 + z_lo * 2 ^ 8
        k = row[14] * 2
        z = v2_lo % 2 ^ 32 + v7_lo % 2 ^ 32 + W[k - 1]
        v2_lo = z % 2 ^ 32
        v2_hi = v2_hi + v7_hi + (z - v2_lo) / 2 ^ 32 + W[k]
        vD_lo, vD_hi = XOR(vD_lo, v2_lo), XOR(vD_hi, v2_hi)
        z_lo, z_hi = vD_lo % 2 ^ 16, vD_hi % 2 ^ 16
        vD_lo, vD_hi =
          (vD_lo - z_lo) / 2 ^ 16 % 2 ^ 16 + z_hi * 2 ^ 16, (vD_hi - z_hi) / 2 ^ 16 % 2 ^ 16 + z_lo * 2 ^ 16
        z = v8_lo % 2 ^ 32 + vD_lo % 2 ^ 32
        v8_lo = z % 2 ^ 32
        v8_hi = v8_hi + vD_hi + (z - v8_lo) / 2 ^ 32
        v7_lo, v7_hi = XOR(v7_lo, v8_lo), XOR(v7_hi, v8_hi)
        z_lo, z_hi = v7_lo % 2 ^ 31, v7_hi % 2 ^ 31
        v7_lo, v7_hi = z_lo * 2 ^ 1 + (v7_hi - z_hi) / 2 ^ 31 % 2 ^ 1, z_hi * 2 ^ 1 + (v7_lo - z_lo) / 2 ^ 31 % 2 ^ 1
        k = row[15] * 2
        z = v3_lo % 2 ^ 32 + v4_lo % 2 ^ 32 + W[k - 1]
        v3_lo = z % 2 ^ 32
        v3_hi = v3_hi + v4_hi + (z - v3_lo) / 2 ^ 32 + W[k]
        vE_lo, vE_hi = XOR(vE_hi, v3_hi), XOR(vE_lo, v3_lo)
        z = v9_lo % 2 ^ 32 + vE_lo % 2 ^ 32
        v9_lo = z % 2 ^ 32
        v9_hi = v9_hi + vE_hi + (z - v9_lo) / 2 ^ 32
        v4_lo, v4_hi = XOR(v4_lo, v9_lo), XOR(v4_hi, v9_hi)
        z_lo, z_hi = v4_lo % 2 ^ 24, v4_hi % 2 ^ 24
        v4_lo, v4_hi = (v4_lo - z_lo) / 2 ^ 24 % 2 ^ 8 + z_hi * 2 ^ 8, (v4_hi - z_hi) / 2 ^ 24 % 2 ^ 8 + z_lo * 2 ^ 8
        k = row[16] * 2
        z = v3_lo % 2 ^ 32 + v4_lo % 2 ^ 32 + W[k - 1]
        v3_lo = z % 2 ^ 32
        v3_hi = v3_hi + v4_hi + (z - v3_lo) / 2 ^ 32 + W[k]
        vE_lo, vE_hi = XOR(vE_lo, v3_lo), XOR(vE_hi, v3_hi)
        z_lo, z_hi = vE_lo % 2 ^ 16, vE_hi % 2 ^ 16
        vE_lo, vE_hi =
          (vE_lo - z_lo) / 2 ^ 16 % 2 ^ 16 + z_hi * 2 ^ 16, (vE_hi - z_hi) / 2 ^ 16 % 2 ^ 16 + z_lo * 2 ^ 16
        z = v9_lo % 2 ^ 32 + vE_lo % 2 ^ 32
        v9_lo = z % 2 ^ 32
        v9_hi = v9_hi + vE_hi + (z - v9_lo) / 2 ^ 32
        v4_lo, v4_hi = XOR(v4_lo, v9_lo), XOR(v4_hi, v9_hi)
        z_lo, z_hi = v4_lo % 2 ^ 31, v4_hi % 2 ^ 31
        v4_lo, v4_hi = z_lo * 2 ^ 1 + (v4_hi - z_hi) / 2 ^ 31 % 2 ^ 1, z_hi * 2 ^ 1 + (v4_lo - z_lo) / 2 ^ 31 % 2 ^ 1
      end
      h1_lo = XOR(h1_lo, v0_lo, v8_lo) % 2 ^ 32
      h2_lo = XOR(h2_lo, v1_lo, v9_lo) % 2 ^ 32
      h3_lo = XOR(h3_lo, v2_lo, vA_lo) % 2 ^ 32
      h4_lo = XOR(h4_lo, v3_lo, vB_lo) % 2 ^ 32
      h5_lo = XOR(h5_lo, v4_lo, vC_lo) % 2 ^ 32
      h6_lo = XOR(h6_lo, v5_lo, vD_lo) % 2 ^ 32
      h7_lo = XOR(h7_lo, v6_lo, vE_lo) % 2 ^ 32
      h8_lo = XOR(h8_lo, v7_lo, vF_lo) % 2 ^ 32
      h1_hi = XOR(h1_hi, v0_hi, v8_hi) % 2 ^ 32
      h2_hi = XOR(h2_hi, v1_hi, v9_hi) % 2 ^ 32
      h3_hi = XOR(h3_hi, v2_hi, vA_hi) % 2 ^ 32
      h4_hi = XOR(h4_hi, v3_hi, vB_hi) % 2 ^ 32
      h5_hi = XOR(h5_hi, v4_hi, vC_hi) % 2 ^ 32
      h6_hi = XOR(h6_hi, v5_hi, vD_hi) % 2 ^ 32
      h7_hi = XOR(h7_hi, v6_hi, vE_hi) % 2 ^ 32
      h8_hi = XOR(h8_hi, v7_hi, vF_hi) % 2 ^ 32
    end
    H_lo[1], H_lo[2], H_lo[3], H_lo[4], H_lo[5], H_lo[6], H_lo[7], H_lo[8] =
      h1_lo, h2_lo, h3_lo, h4_lo, h5_lo, h6_lo, h7_lo, h8_lo
    H_hi[1], H_hi[2], H_hi[3], H_hi[4], H_hi[5], H_hi[6], H_hi[7], H_hi[8] =
      h1_hi, h2_hi, h3_hi, h4_hi, h5_hi, h6_hi, h7_hi, h8_hi
    return bytes_compressed
  end

  function blake3_feed_64(str, offs, size, flags, chunk_index, H_in, H_out, wide_output, block_length)
    -- offs >= 0, size >= 0, size is multiple of 64
    block_length = block_length or 64
    local W = common_W
    local h1, h2, h3, h4, h5, h6, h7, h8 = H_in[1], H_in[2], H_in[3], H_in[4], H_in[5], H_in[6], H_in[7], H_in[8]
    H_out = H_out or H_in
    for pos = offs, offs + size - 1, 64 do
      if str then
        for j = 1, 16 do
          pos = pos + 4
          local a, b, c, d = byte(str, pos - 3, pos)
          W[j] = ((d * 256 + c) * 256 + b) * 256 + a
        end
      end
      local v0, v1, v2, v3, v4, v5, v6, v7 = h1, h2, h3, h4, h5, h6, h7, h8
      local v8, v9, vA, vB = sha2_H_hi[1], sha2_H_hi[2], sha2_H_hi[3], sha2_H_hi[4]
      local vC = chunk_index % 2 ^ 32 -- t0 = low_4_bytes(chunk_index)
      local vD = (chunk_index - vC) / 2 ^ 32 -- t1 = high_4_bytes(chunk_index)
      local vE, vF = block_length, flags
      for j = 1, 7 do
        v0 = v0 + v4 + W[perm_blake3[j]]
        vC = XOR(vC, v0) % 2 ^ 32 / 2 ^ 16
        vC = vC % 1 * (2 ^ 32 - 1) + vC
        v8 = v8 + vC
        v4 = XOR(v4, v8) % 2 ^ 32 / 2 ^ 12
        v4 = v4 % 1 * (2 ^ 32 - 1) + v4
        v0 = v0 + v4 + W[perm_blake3[j + 14]]
        vC = XOR(vC, v0) % 2 ^ 32 / 2 ^ 8
        vC = vC % 1 * (2 ^ 32 - 1) + vC
        v8 = v8 + vC
        v4 = XOR(v4, v8) % 2 ^ 32 / 2 ^ 7
        v4 = v4 % 1 * (2 ^ 32 - 1) + v4
        v1 = v1 + v5 + W[perm_blake3[j + 1]]
        vD = XOR(vD, v1) % 2 ^ 32 / 2 ^ 16
        vD = vD % 1 * (2 ^ 32 - 1) + vD
        v9 = v9 + vD
        v5 = XOR(v5, v9) % 2 ^ 32 / 2 ^ 12
        v5 = v5 % 1 * (2 ^ 32 - 1) + v5
        v1 = v1 + v5 + W[perm_blake3[j + 2]]
        vD = XOR(vD, v1) % 2 ^ 32 / 2 ^ 8
        vD = vD % 1 * (2 ^ 32 - 1) + vD
        v9 = v9 + vD
        v5 = XOR(v5, v9) % 2 ^ 32 / 2 ^ 7
        v5 = v5 % 1 * (2 ^ 32 - 1) + v5
        v2 = v2 + v6 + W[perm_blake3[j + 16]]
        vE = XOR(vE, v2) % 2 ^ 32 / 2 ^ 16
        vE = vE % 1 * (2 ^ 32 - 1) + vE
        vA = vA + vE
        v6 = XOR(v6, vA) % 2 ^ 32 / 2 ^ 12
        v6 = v6 % 1 * (2 ^ 32 - 1) + v6
        v2 = v2 + v6 + W[perm_blake3[j + 7]]
        vE = XOR(vE, v2) % 2 ^ 32 / 2 ^ 8
        vE = vE % 1 * (2 ^ 32 - 1) + vE
        vA = vA + vE
        v6 = XOR(v6, vA) % 2 ^ 32 / 2 ^ 7
        v6 = v6 % 1 * (2 ^ 32 - 1) + v6
        v3 = v3 + v7 + W[perm_blake3[j + 15]]
        vF = XOR(vF, v3) % 2 ^ 32 / 2 ^ 16
        vF = vF % 1 * (2 ^ 32 - 1) + vF
        vB = vB + vF
        v7 = XOR(v7, vB) % 2 ^ 32 / 2 ^ 12
        v7 = v7 % 1 * (2 ^ 32 - 1) + v7
        v3 = v3 + v7 + W[perm_blake3[j + 17]]
        vF = XOR(vF, v3) % 2 ^ 32 / 2 ^ 8
        vF = vF % 1 * (2 ^ 32 - 1) + vF
        vB = vB + vF
        v7 = XOR(v7, vB) % 2 ^ 32 / 2 ^ 7
        v7 = v7 % 1 * (2 ^ 32 - 1) + v7
        v0 = v0 + v5 + W[perm_blake3[j + 21]]
        vF = XOR(vF, v0) % 2 ^ 32 / 2 ^ 16
        vF = vF % 1 * (2 ^ 32 - 1) + vF
        vA = vA + vF
        v5 = XOR(v5, vA) % 2 ^ 32 / 2 ^ 12
        v5 = v5 % 1 * (2 ^ 32 - 1) + v5
        v0 = v0 + v5 + W[perm_blake3[j + 5]]
        vF = XOR(vF, v0) % 2 ^ 32 / 2 ^ 8
        vF = vF % 1 * (2 ^ 32 - 1) + vF
        vA = vA + vF
        v5 = XOR(v5, vA) % 2 ^ 32 / 2 ^ 7
        v5 = v5 % 1 * (2 ^ 32 - 1) + v5
        v1 = v1 + v6 + W[perm_blake3[j + 3]]
        vC = XOR(vC, v1) % 2 ^ 32 / 2 ^ 16
        vC = vC % 1 * (2 ^ 32 - 1) + vC
        vB = vB + vC
        v6 = XOR(v6, vB) % 2 ^ 32 / 2 ^ 12
        v6 = v6 % 1 * (2 ^ 32 - 1) + v6
        v1 = v1 + v6 + W[perm_blake3[j + 6]]
        vC = XOR(vC, v1) % 2 ^ 32 / 2 ^ 8
        vC = vC % 1 * (2 ^ 32 - 1) + vC
        vB = vB + vC
        v6 = XOR(v6, vB) % 2 ^ 32 / 2 ^ 7
        v6 = v6 % 1 * (2 ^ 32 - 1) + v6
        v2 = v2 + v7 + W[perm_blake3[j + 4]]
        vD = XOR(vD, v2) % 2 ^ 32 / 2 ^ 16
        vD = vD % 1 * (2 ^ 32 - 1) + vD
        v8 = v8 + vD
        v7 = XOR(v7, v8) % 2 ^ 32 / 2 ^ 12
        v7 = v7 % 1 * (2 ^ 32 - 1) + v7
        v2 = v2 + v7 + W[perm_blake3[j + 18]]
        vD = XOR(vD, v2) % 2 ^ 32 / 2 ^ 8
        vD = vD % 1 * (2 ^ 32 - 1) + vD
        v8 = v8 + vD
        v7 = XOR(v7, v8) % 2 ^ 32 / 2 ^ 7
        v7 = v7 % 1 * (2 ^ 32 - 1) + v7
        v3 = v3 + v4 + W[perm_blake3[j + 19]]
        vE = XOR(vE, v3) % 2 ^ 32 / 2 ^ 16
        vE = vE % 1 * (2 ^ 32 - 1) + vE
        v9 = v9 + vE
        v4 = XOR(v4, v9) % 2 ^ 32 / 2 ^ 12
        v4 = v4 % 1 * (2 ^ 32 - 1) + v4
        v3 = v3 + v4 + W[perm_blake3[j + 20]]
        vE = XOR(vE, v3) % 2 ^ 32 / 2 ^ 8
        vE = vE % 1 * (2 ^ 32 - 1) + vE
        v9 = v9 + vE
        v4 = XOR(v4, v9) % 2 ^ 32 / 2 ^ 7
        v4 = v4 % 1 * (2 ^ 32 - 1) + v4
      end
      if wide_output then
        H_out[9] = XOR(h1, v8)
        H_out[10] = XOR(h2, v9)
        H_out[11] = XOR(h3, vA)
        H_out[12] = XOR(h4, vB)
        H_out[13] = XOR(h5, vC)
        H_out[14] = XOR(h6, vD)
        H_out[15] = XOR(h7, vE)
        H_out[16] = XOR(h8, vF)
      end
      h1 = XOR(v0, v8)
      h2 = XOR(v1, v9)
      h3 = XOR(v2, vA)
      h4 = XOR(v3, vB)
      h5 = XOR(v4, vC)
      h6 = XOR(v5, vD)
      h7 = XOR(v6, vE)
      h8 = XOR(v7, vF)
    end
    H_out[1], H_out[2], H_out[3], H_out[4], H_out[5], H_out[6], H_out[7], H_out[8] = h1, h2, h3, h4, h5, h6, h7, h8
  end
end

--------------------------------------------------------------------------------
-- MAGIC NUMBERS CALCULATOR
--------------------------------------------------------------------------------
-- Q:
--    Is 53-bit "double" math enough to calculate square roots and cube roots of primes with 64 correct bits after decimal point?
-- A:
--    Yes, 53-bit "double" arithmetic is enough.
--    We could obtain first 40 bits by direct calculation of p^(1/3) and next 40 bits by one step of Newton's method.

do
  local function mul(src1, src2, factor, result_length)
    -- src1, src2 - long integers (arrays of digits in base 2^24)
    -- factor - small integer
    -- returns long integer result (src1 * src2 * factor) and its floating point approximation
    local result, carry, value, weight = {}, 0.0, 0.0, 1.0
    for j = 1, result_length do
      for k = math_max(1, j + 1 - #src2), math_min(j, #src1) do
        carry = carry + factor * src1[k] * src2[j + 1 - k] -- "int32" is not enough for multiplication result, that's why "factor" must be of type "double"
      end
      local digit = carry % 2 ^ 24
      result[j] = floor(digit)
      carry = (carry - digit) / 2 ^ 24
      value = value + digit * weight
      weight = weight * 2 ^ 24
    end
    return result, value
  end

  local idx, step, p, one, sqrt_hi, sqrt_lo = 0, { 4, 1, 2, -2, 2 }, 4, { 1 }, sha2_H_hi, sha2_H_lo
  repeat
    p = p + step[p % 6]
    local d = 1
    repeat
      d = d + step[d % 6]
      if d * d > p then -- next prime number is found
        local root = p ^ (1 / 3)
        local R = root * 2 ^ 40
        R = mul({ R - R % 1 }, one, 1.0, 2)
        local _, delta = mul(R, mul(R, R, 1.0, 4), -1.0, 4)
        local hi = R[2] % 65536 * 65536 + floor(R[1] / 256)
        local lo = R[1] % 256 * 16777216 + floor(delta * (2 ^ -56 / 3) * root / p)
        if idx < 16 then
          root = p ^ (1 / 2)
          R = root * 2 ^ 40
          R = mul({ R - R % 1 }, one, 1.0, 2)
          _, delta = mul(R, R, -1.0, 2)
          local hi = R[2] % 65536 * 65536 + floor(R[1] / 256)
          local lo = R[1] % 256 * 16777216 + floor(delta * 2 ^ -17 / root)
          local idx = idx % 8 + 1
          sha2_H_ext256[224][idx] = lo
          sqrt_hi[idx], sqrt_lo[idx] = hi, lo + hi * hi_factor
          if idx > 7 then
            sqrt_hi, sqrt_lo = sha2_H_ext512_hi[384], sha2_H_ext512_lo[384]
          end
        end
        idx = idx + 1
        sha2_K_hi[idx], sha2_K_lo[idx] = hi, lo % K_lo_modulo + hi * hi_factor
        break
      end
    until p % d == 0
  until idx > 79
end

-- Calculating IVs for SHA512/224 and SHA512/256
for width = 224, 256, 32 do
  local H_lo, H_hi = {}
  if HEX64 then
    for j = 1, 8 do
      H_lo[j] = XORA5(sha2_H_lo[j])
    end
  else
    H_hi = {}
    for j = 1, 8 do
      H_lo[j] = XORA5(sha2_H_lo[j])
      H_hi[j] = XORA5(sha2_H_hi[j])
    end
  end
  sha512_feed_128(H_lo, H_hi, "SHA-512/" .. tostring(width) .. "\128" .. string_rep("\0", 115) .. "\88", 0, 128)
  sha2_H_ext512_lo[width] = H_lo
  sha2_H_ext512_hi[width] = H_hi
end

-- Constants for MD5
do
  local sin, abs, modf = math.sin, math.abs, math.modf
  for idx = 1, 64 do
    -- we can't use formula floor(abs(sin(idx))*2^32) because its result may be beyond integer range on Lua built with 32-bit integers
    local hi, lo = modf(abs(sin(idx)) * 2 ^ 16)
    md5_K[idx] = hi * 65536 + floor(lo * 2 ^ 16)
  end
end

-- Constants for SHA-3
do
  local sh_reg = 29

  local function next_bit()
    local r = sh_reg % 2
    sh_reg = XOR_BYTE((sh_reg - r) / 2, 142 * r)
    return r
  end

  for idx = 1, 24 do
    local lo, m = 0
    for _ = 1, 6 do
      m = m and m * m * 2 or 1
      lo = lo + next_bit() * m
    end
    local hi = next_bit() * m
    sha3_RC_hi[idx], sha3_RC_lo[idx] = hi, lo + hi * hi_factor_keccak
  end
end

if branch == "FFI" then
  sha2_K_hi = ffi.new("uint32_t[?]", #sha2_K_hi + 1, 0, unpack(sha2_K_hi))
  sha2_K_lo = ffi.new("int64_t[?]", #sha2_K_lo + 1, 0, unpack(sha2_K_lo))
  --md5_K = ffi.new("uint32_t[?]", #md5_K + 1, 0, unpack(md5_K))
  if hi_factor_keccak == 0 then
    sha3_RC_lo = ffi.new("uint32_t[?]", #sha3_RC_lo + 1, 0, unpack(sha3_RC_lo))
    sha3_RC_hi = ffi.new("uint32_t[?]", #sha3_RC_hi + 1, 0, unpack(sha3_RC_hi))
  else
    sha3_RC_lo = ffi.new("int64_t[?]", #sha3_RC_lo + 1, 0, unpack(sha3_RC_lo))
  end
end

--------------------------------------------------------------------------------
-- MAIN FUNCTIONS
--------------------------------------------------------------------------------

local function sha256ext(width, message)
  -- Create an instance (private objects for current calculation)
  local H, length, tail = { unpack(sha2_H_ext256[width]) }, 0.0, ""

  local function partial(message_part)
    if message_part then
      if tail then
        length = length + #message_part
        local offs = 0
        if tail ~= "" and #tail + #message_part >= 64 then
          offs = 64 - #tail
          sha256_feed_64(H, tail .. sub(message_part, 1, offs), 0, 64)
          tail = ""
        end
        local size = #message_part - offs
        local size_tail = size % 64
        sha256_feed_64(H, message_part, offs, size - size_tail)
        tail = tail .. sub(message_part, #message_part + 1 - size_tail)
        return partial
      else
        error("Adding more chunks is not allowed after receiving the result", 2)
      end
    else
      if tail then
        local final_blocks = { tail, "\128", string_rep("\0", (-9 - length) % 64 + 1) }
        tail = nil
        -- Assuming user data length is shorter than (2^53)-9 bytes
        -- Anyway, it looks very unrealistic that someone would spend more than a year of calculations to process 2^53 bytes of data by using this Lua script :-)
        -- 2^53 bytes = 2^56 bits, so "bit-counter" fits in 7 bytes
        length = length * (8 / 256 ^ 7) -- convert "byte-counter" to "bit-counter" and move decimal point to the left
        for j = 4, 10 do
          length = length % 1 * 256
          final_blocks[j] = char(floor(length))
        end
        final_blocks = table_concat(final_blocks)
        sha256_feed_64(H, final_blocks, 0, #final_blocks)
        local max_reg = width / 32
        for j = 1, max_reg do
          H[j] = HEX(H[j])
        end
        H = table_concat(H, "", 1, max_reg)
      end
      return H
    end
  end

  if message then
    -- Actually perform calculations and return the SHA256 digest of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading
    -- User should feed every chunk of input data as single argument to this function and finally get SHA256 digest by invoking this function without an argument
    return partial
  end
end

local function sha512ext(width, message)
  -- Create an instance (private objects for current calculation)
  local length, tail, H_lo, H_hi =
    0.0, "", { unpack(sha2_H_ext512_lo[width]) }, not HEX64 and { unpack(sha2_H_ext512_hi[width]) }

  local function partial(message_part)
    if message_part then
      if tail then
        length = length + #message_part
        local offs = 0
        if tail ~= "" and #tail + #message_part >= 128 then
          offs = 128 - #tail
          sha512_feed_128(H_lo, H_hi, tail .. sub(message_part, 1, offs), 0, 128)
          tail = ""
        end
        local size = #message_part - offs
        local size_tail = size % 128
        sha512_feed_128(H_lo, H_hi, message_part, offs, size - size_tail)
        tail = tail .. sub(message_part, #message_part + 1 - size_tail)
        return partial
      else
        error("Adding more chunks is not allowed after receiving the result", 2)
      end
    else
      if tail then
        local final_blocks = { tail, "\128", string_rep("\0", (-17 - length) % 128 + 9) }
        tail = nil
        -- Assuming user data length is shorter than (2^53)-17 bytes
        -- 2^53 bytes = 2^56 bits, so "bit-counter" fits in 7 bytes
        length = length * (8 / 256 ^ 7) -- convert "byte-counter" to "bit-counter" and move floating point to the left
        for j = 4, 10 do
          length = length % 1 * 256
          final_blocks[j] = char(floor(length))
        end
        final_blocks = table_concat(final_blocks)
        sha512_feed_128(H_lo, H_hi, final_blocks, 0, #final_blocks)
        local max_reg = ceil(width / 64)
        if HEX64 then
          for j = 1, max_reg do
            H_lo[j] = HEX64(H_lo[j])
          end
        else
          for j = 1, max_reg do
            H_lo[j] = HEX(H_hi[j]) .. HEX(H_lo[j])
          end
          H_hi = nil
        end
        H_lo = sub(table_concat(H_lo, "", 1, max_reg), 1, width / 4)
      end
      return H_lo
    end
  end

  if message then
    -- Actually perform calculations and return the SHA512 digest of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading
    -- User should feed every chunk of input data as single argument to this function and finally get SHA512 digest by invoking this function without an argument
    return partial
  end
end

local function md5(message)
  -- Create an instance (private objects for current calculation)
  local H, length, tail = { unpack(md5_sha1_H, 1, 4) }, 0.0, ""

  local function partial(message_part)
    if message_part then
      if tail then
        length = length + #message_part
        local offs = 0
        if tail ~= "" and #tail + #message_part >= 64 then
          offs = 64 - #tail
          md5_feed_64(H, tail .. sub(message_part, 1, offs), 0, 64)
          tail = ""
        end
        local size = #message_part - offs
        local size_tail = size % 64
        md5_feed_64(H, message_part, offs, size - size_tail)
        tail = tail .. sub(message_part, #message_part + 1 - size_tail)
        return partial
      else
        error("Adding more chunks is not allowed after receiving the result", 2)
      end
    else
      if tail then
        local final_blocks = { tail, "\128", string_rep("\0", (-9 - length) % 64) }
        tail = nil
        length = length * 8 -- convert "byte-counter" to "bit-counter"
        for j = 4, 11 do
          local low_byte = length % 256
          final_blocks[j] = char(low_byte)
          length = (length - low_byte) / 256
        end
        final_blocks = table_concat(final_blocks)
        md5_feed_64(H, final_blocks, 0, #final_blocks)
        for j = 1, 4 do
          H[j] = HEX(H[j])
        end
        H = gsub(table_concat(H), "(..)(..)(..)(..)", "%4%3%2%1")
      end
      return H
    end
  end

  if message then
    -- Actually perform calculations and return the MD5 digest of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading
    -- User should feed every chunk of input data as single argument to this function and finally get MD5 digest by invoking this function without an argument
    return partial
  end
end

local function sha1(message)
  -- Create an instance (private objects for current calculation)
  local H, length, tail = { unpack(md5_sha1_H) }, 0.0, ""

  local function partial(message_part)
    if message_part then
      if tail then
        length = length + #message_part
        local offs = 0
        if tail ~= "" and #tail + #message_part >= 64 then
          offs = 64 - #tail
          sha1_feed_64(H, tail .. sub(message_part, 1, offs), 0, 64)
          tail = ""
        end
        local size = #message_part - offs
        local size_tail = size % 64
        sha1_feed_64(H, message_part, offs, size - size_tail)
        tail = tail .. sub(message_part, #message_part + 1 - size_tail)
        return partial
      else
        error("Adding more chunks is not allowed after receiving the result", 2)
      end
    else
      if tail then
        local final_blocks = { tail, "\128", string_rep("\0", (-9 - length) % 64 + 1) }
        tail = nil
        -- Assuming user data length is shorter than (2^53)-9 bytes
        -- 2^53 bytes = 2^56 bits, so "bit-counter" fits in 7 bytes
        length = length * (8 / 256 ^ 7) -- convert "byte-counter" to "bit-counter" and move decimal point to the left
        for j = 4, 10 do
          length = length % 1 * 256
          final_blocks[j] = char(floor(length))
        end
        final_blocks = table_concat(final_blocks)
        sha1_feed_64(H, final_blocks, 0, #final_blocks)
        for j = 1, 5 do
          H[j] = HEX(H[j])
        end
        H = table_concat(H)
      end
      return H
    end
  end

  if message then
    -- Actually perform calculations and return the SHA-1 digest of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading
    -- User should feed every chunk of input data as single argument to this function and finally get SHA-1 digest by invoking this function without an argument
    return partial
  end
end

local function keccak(block_size_in_bytes, digest_size_in_bytes, is_SHAKE, message)
  -- "block_size_in_bytes" is multiple of 8
  if type(digest_size_in_bytes) ~= "number" then
    -- arguments in SHAKE are swapped:
    --    NIST FIPS 202 defines SHAKE(message,num_bits)
    --    this module   defines SHAKE(num_bytes,message)
    -- it's easy to forget about this swap, hence the check
    error("Argument 'digest_size_in_bytes' must be a number", 2)
  end
  -- Create an instance (private objects for current calculation)
  local tail, lanes_lo, lanes_hi = "", create_array_of_lanes(), hi_factor_keccak == 0 and create_array_of_lanes()
  local result

  local function partial(message_part)
    if message_part then
      if tail then
        local offs = 0
        if tail ~= "" and #tail + #message_part >= block_size_in_bytes then
          offs = block_size_in_bytes - #tail
          keccak_feed(
            lanes_lo,
            lanes_hi,
            tail .. sub(message_part, 1, offs),
            0,
            block_size_in_bytes,
            block_size_in_bytes
          )
          tail = ""
        end
        local size = #message_part - offs
        local size_tail = size % block_size_in_bytes
        keccak_feed(lanes_lo, lanes_hi, message_part, offs, size - size_tail, block_size_in_bytes)
        tail = tail .. sub(message_part, #message_part + 1 - size_tail)
        return partial
      else
        error("Adding more chunks is not allowed after receiving the result", 2)
      end
    else
      if tail then
        -- append the following bits to the message: for usual SHA-3: 011(0*)1, for SHAKE: 11111(0*)1
        local gap_start = is_SHAKE and 31 or 6
        tail = tail
          .. (
            #tail + 1 == block_size_in_bytes and char(gap_start + 128)
            or char(gap_start) .. string_rep("\0", (-2 - #tail) % block_size_in_bytes) .. "\128"
          )
        keccak_feed(lanes_lo, lanes_hi, tail, 0, #tail, block_size_in_bytes)
        tail = nil
        local lanes_used = 0
        local total_lanes = floor(block_size_in_bytes / 8)
        local qwords = {}

        local function get_next_qwords_of_digest(qwords_qty)
          -- returns not more than 'qwords_qty' qwords ('qwords_qty' might be non-integer)
          -- doesn't go across keccak-buffer boundary
          -- block_size_in_bytes is a multiple of 8, so, keccak-buffer contains integer number of qwords
          if lanes_used >= total_lanes then
            keccak_feed(lanes_lo, lanes_hi, "\0\0\0\0\0\0\0\0", 0, 8, 8)
            lanes_used = 0
          end
          qwords_qty = floor(math_min(qwords_qty, total_lanes - lanes_used))
          if hi_factor_keccak ~= 0 then
            for j = 1, qwords_qty do
              qwords[j] = HEX64(lanes_lo[lanes_used + j - 1 + lanes_index_base])
            end
          else
            for j = 1, qwords_qty do
              qwords[j] = HEX(lanes_hi[lanes_used + j]) .. HEX(lanes_lo[lanes_used + j])
            end
          end
          lanes_used = lanes_used + qwords_qty
          return gsub(table_concat(qwords, "", 1, qwords_qty), "(..)(..)(..)(..)(..)(..)(..)(..)", "%8%7%6%5%4%3%2%1"),
            qwords_qty * 8
        end

        local parts = {} -- digest parts
        local last_part, last_part_size = "", 0

        local function get_next_part_of_digest(bytes_needed)
          -- returns 'bytes_needed' bytes, for arbitrary integer 'bytes_needed'
          bytes_needed = bytes_needed or 1
          if bytes_needed <= last_part_size then
            last_part_size = last_part_size - bytes_needed
            local part_size_in_nibbles = bytes_needed * 2
            local result = sub(last_part, 1, part_size_in_nibbles)
            last_part = sub(last_part, part_size_in_nibbles + 1)
            return result
          end
          local parts_qty = 0
          if last_part_size > 0 then
            parts_qty = 1
            parts[parts_qty] = last_part
            bytes_needed = bytes_needed - last_part_size
          end
          -- repeats until the length is enough
          while bytes_needed >= 8 do
            local next_part, next_part_size = get_next_qwords_of_digest(bytes_needed / 8)
            parts_qty = parts_qty + 1
            parts[parts_qty] = next_part
            bytes_needed = bytes_needed - next_part_size
          end
          if bytes_needed > 0 then
            last_part, last_part_size = get_next_qwords_of_digest(1)
            parts_qty = parts_qty + 1
            parts[parts_qty] = get_next_part_of_digest(bytes_needed)
          else
            last_part, last_part_size = "", 0
          end
          return table_concat(parts, "", 1, parts_qty)
        end

        if digest_size_in_bytes < 0 then
          result = get_next_part_of_digest
        else
          result = get_next_part_of_digest(digest_size_in_bytes)
        end
      end
      return result
    end
  end

  if message then
    -- Actually perform calculations and return the SHA-3 digest of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading
    -- User should feed every chunk of input data as single argument to this function and finally get SHA-3 digest by invoking this function without an argument
    return partial
  end
end

local hex_to_bin, bin_to_hex, bin_to_base64, base64_to_bin
do
  function hex_to_bin(hex_string)
    return (gsub(hex_string, "%x%x", function(hh) return char(tonumber(hh, 16)) end))
  end

  function bin_to_hex(binary_string)
    return (gsub(binary_string, ".", function(c) return string_format("%02x", byte(c)) end))
  end

  local base64_symbols = {
    ["+"] = 62,
    ["-"] = 62,
    [62] = "+",
    ["/"] = 63,
    ["_"] = 63,
    [63] = "/",
    ["="] = -1,
    ["."] = -1,
    [-1] = "=",
  }
  local symbol_index = 0
  for j, pair in ipairs({ "AZ", "az", "09" }) do
    for ascii = byte(pair), byte(pair, 2) do
      local ch = char(ascii)
      base64_symbols[ch] = symbol_index
      base64_symbols[symbol_index] = ch
      symbol_index = symbol_index + 1
    end
  end

  function bin_to_base64(binary_string)
    local result = {}
    for pos = 1, #binary_string, 3 do
      local c1, c2, c3, c4 = byte(sub(binary_string, pos, pos + 2) .. "\0", 1, -1)
      result[#result + 1] = base64_symbols[floor(c1 / 4)]
        .. base64_symbols[c1 % 4 * 16 + floor(c2 / 16)]
        .. base64_symbols[c3 and c2 % 16 * 4 + floor(c3 / 64) or -1]
        .. base64_symbols[c4 and c3 % 64 or -1]
    end
    return table_concat(result)
  end

  function base64_to_bin(base64_string)
    local result, chars_qty = {}, 3
    for pos, ch in gmatch(gsub(base64_string, "%s+", ""), "()(.)") do
      local code = base64_symbols[ch]
      if code < 0 then
        chars_qty = chars_qty - 1
        code = 0
      end
      local idx = pos % 4
      if idx > 0 then
        result[-idx] = code
      else
        local c1 = result[-1] * 4 + floor(result[-2] / 16)
        local c2 = (result[-2] % 16) * 16 + floor(result[-3] / 4)
        local c3 = (result[-3] % 4) * 64 + code
        result[#result + 1] = sub(char(c1, c2, c3), 1, chars_qty)
      end
    end
    return table_concat(result)
  end
end

local block_size_for_HMAC -- this table will be initialized at the end of the module

local function pad_and_xor(str, result_length, byte_for_xor)
  return gsub(str, ".", function(c) return char(XOR_BYTE(byte(c), byte_for_xor)) end)
    .. string_rep(char(byte_for_xor), result_length - #str)
end

local function hmac(hash_func, key, message)
  -- Create an instance (private objects for current calculation)
  local block_size = block_size_for_HMAC[hash_func]
  if not block_size then error("Unknown hash function", 2) end
  if #key > block_size then key = hex_to_bin(hash_func(key)) end
  local append = hash_func()(pad_and_xor(key, block_size, 0x36))
  local result

  local function partial(message_part)
    if not message_part then
      result = result or hash_func(pad_and_xor(key, block_size, 0x5C) .. hex_to_bin(append()))
      return result
    elseif result then
      error("Adding more chunks is not allowed after receiving the result", 2)
    else
      append(message_part)
      return partial
    end
  end

  if message then
    -- Actually perform calculations and return the HMAC of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading of a message
    -- User should feed every chunk of the message as single argument to this function and finally get HMAC by invoking this function without an argument
    return partial
  end
end

local function xor_blake2_salt(salt, letter, H_lo, H_hi)
  -- salt: concatenation of "Salt"+"Personalization" fields
  local max_size = letter == "s" and 16 or 32
  local salt_size = #salt
  if salt_size > max_size then
    error(
      string_format(
        "For BLAKE2%s/BLAKE2%sp/BLAKE2X%s the 'salt' parameter length must not exceed %d bytes",
        letter,
        letter,
        letter,
        max_size
      ),
      2
    )
  end
  if H_lo then
    local offset, blake2_word_size, xor = 0, letter == "s" and 4 or 8, letter == "s" and XOR or XORA5
    for j = 5, 4 + ceil(salt_size / blake2_word_size) do
      local prev, last
      for _ = 1, blake2_word_size, 4 do
        offset = offset + 4
        local a, b, c, d = byte(salt, offset - 3, offset)
        local four_bytes = (((d or 0) * 256 + (c or 0)) * 256 + (b or 0)) * 256 + (a or 0)
        prev, last = last, four_bytes
      end
      H_lo[j] = xor(H_lo[j], prev and last * hi_factor + prev or last)
      if H_hi then H_hi[j] = xor(H_hi[j], last) end
    end
  end
end

local function blake2s(message, key, salt, digest_size_in_bytes, XOF_length, B2_offset)
  -- message:  binary string to be hashed (or nil for "chunk-by-chunk" input mode)
  -- key:      (optional) binary string up to 32 bytes, by default empty string
  -- salt:     (optional) binary string up to 16 bytes, by default empty string
  -- digest_size_in_bytes: (optional) integer from 1 to 32, by default 32
  -- The last two parameters "XOF_length" and "B2_offset" are for internal use only, user must omit them (or pass nil)
  digest_size_in_bytes = digest_size_in_bytes or 32
  if digest_size_in_bytes < 1 or digest_size_in_bytes > 32 then
    error("BLAKE2s digest length must be from 1 to 32 bytes", 2)
  end
  key = key or ""
  local key_length = #key
  if key_length > 32 then error("BLAKE2s key length must not exceed 32 bytes", 2) end
  salt = salt or ""
  local bytes_compressed, tail, H = 0.0, "", { unpack(sha2_H_hi) }
  if B2_offset then
    H[1] = XOR(H[1], digest_size_in_bytes)
    H[2] = XOR(H[2], 0x20)
    H[3] = XOR(H[3], B2_offset)
    H[4] = XOR(H[4], 0x20000000 + XOF_length)
  else
    H[1] = XOR(H[1], 0x01010000 + key_length * 256 + digest_size_in_bytes)
    if XOF_length then H[4] = XOR(H[4], XOF_length) end
  end
  if salt ~= "" then xor_blake2_salt(salt, "s", H) end

  local function partial(message_part)
    if message_part then
      if tail then
        local offs = 0
        if tail ~= "" and #tail + #message_part > 64 then
          offs = 64 - #tail
          bytes_compressed = blake2s_feed_64(H, tail .. sub(message_part, 1, offs), 0, 64, bytes_compressed)
          tail = ""
        end
        local size = #message_part - offs
        local size_tail = size > 0 and (size - 1) % 64 + 1 or 0
        bytes_compressed = blake2s_feed_64(H, message_part, offs, size - size_tail, bytes_compressed)
        tail = tail .. sub(message_part, #message_part + 1 - size_tail)
        return partial
      else
        error("Adding more chunks is not allowed after receiving the result", 2)
      end
    else
      if tail then
        if B2_offset then
          blake2s_feed_64(H, nil, 0, 64, 0, 32)
        else
          blake2s_feed_64(H, tail .. string_rep("\0", 64 - #tail), 0, 64, bytes_compressed, #tail)
        end
        tail = nil
        if not XOF_length or B2_offset then
          local max_reg = ceil(digest_size_in_bytes / 4)
          for j = 1, max_reg do
            H[j] = HEX(H[j])
          end
          H = sub(gsub(table_concat(H, "", 1, max_reg), "(..)(..)(..)(..)", "%4%3%2%1"), 1, digest_size_in_bytes * 2)
        end
      end
      return H
    end
  end

  if key_length > 0 then partial(key .. string_rep("\0", 64 - key_length)) end
  if B2_offset then
    return partial()
  elseif message then
    -- Actually perform calculations and return the BLAKE2s digest of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading
    -- User should feed every chunk of input data as single argument to this function and finally get BLAKE2s digest by invoking this function without an argument
    return partial
  end
end

local function blake2b(message, key, salt, digest_size_in_bytes, XOF_length, B2_offset)
  -- message:  binary string to be hashed (or nil for "chunk-by-chunk" input mode)
  -- key:      (optional) binary string up to 64 bytes, by default empty string
  -- salt:     (optional) binary string up to 32 bytes, by default empty string
  -- digest_size_in_bytes: (optional) integer from 1 to 64, by default 64
  -- The last two parameters "XOF_length" and "B2_offset" are for internal use only, user must omit them (or pass nil)
  digest_size_in_bytes = floor(digest_size_in_bytes or 64)
  if digest_size_in_bytes < 1 or digest_size_in_bytes > 64 then
    error("BLAKE2b digest length must be from 1 to 64 bytes", 2)
  end
  key = key or ""
  local key_length = #key
  if key_length > 64 then error("BLAKE2b key length must not exceed 64 bytes", 2) end
  salt = salt or ""
  local bytes_compressed, tail, H_lo, H_hi = 0.0, "", { unpack(sha2_H_lo) }, not HEX64 and { unpack(sha2_H_hi) }
  if B2_offset then
    if H_hi then
      H_lo[1] = XORA5(H_lo[1], digest_size_in_bytes)
      H_hi[1] = XORA5(H_hi[1], 0x40)
      H_lo[2] = XORA5(H_lo[2], B2_offset)
      H_hi[2] = XORA5(H_hi[2], XOF_length)
    else
      H_lo[1] = XORA5(H_lo[1], 0x40 * hi_factor + digest_size_in_bytes)
      H_lo[2] = XORA5(H_lo[2], XOF_length * hi_factor + B2_offset)
    end
    H_lo[3] = XORA5(H_lo[3], 0x4000)
  else
    H_lo[1] = XORA5(H_lo[1], 0x01010000 + key_length * 256 + digest_size_in_bytes)
    if XOF_length then
      if H_hi then
        H_hi[2] = XORA5(H_hi[2], XOF_length)
      else
        H_lo[2] = XORA5(H_lo[2], XOF_length * hi_factor)
      end
    end
  end
  if salt ~= "" then xor_blake2_salt(salt, "b", H_lo, H_hi) end

  local function partial(message_part)
    if message_part then
      if tail then
        local offs = 0
        if tail ~= "" and #tail + #message_part > 128 then
          offs = 128 - #tail
          bytes_compressed = blake2b_feed_128(H_lo, H_hi, tail .. sub(message_part, 1, offs), 0, 128, bytes_compressed)
          tail = ""
        end
        local size = #message_part - offs
        local size_tail = size > 0 and (size - 1) % 128 + 1 or 0
        bytes_compressed = blake2b_feed_128(H_lo, H_hi, message_part, offs, size - size_tail, bytes_compressed)
        tail = tail .. sub(message_part, #message_part + 1 - size_tail)
        return partial
      else
        error("Adding more chunks is not allowed after receiving the result", 2)
      end
    else
      if tail then
        if B2_offset then
          blake2b_feed_128(H_lo, H_hi, nil, 0, 128, 0, 64)
        else
          blake2b_feed_128(H_lo, H_hi, tail .. string_rep("\0", 128 - #tail), 0, 128, bytes_compressed, #tail)
        end
        tail = nil
        if XOF_length and not B2_offset then
          if H_hi then
            for j = 8, 1, -1 do
              H_lo[j * 2] = H_hi[j]
              H_lo[j * 2 - 1] = H_lo[j]
            end
            return H_lo, 16
          end
        else
          local max_reg = ceil(digest_size_in_bytes / 8)
          if H_hi then
            for j = 1, max_reg do
              H_lo[j] = HEX(H_hi[j]) .. HEX(H_lo[j])
            end
          else
            for j = 1, max_reg do
              H_lo[j] = HEX64(H_lo[j])
            end
          end
          H_lo = sub(
            gsub(table_concat(H_lo, "", 1, max_reg), "(..)(..)(..)(..)(..)(..)(..)(..)", "%8%7%6%5%4%3%2%1"),
            1,
            digest_size_in_bytes * 2
          )
        end
        H_hi = nil
      end
      return H_lo
    end
  end

  if key_length > 0 then partial(key .. string_rep("\0", 128 - key_length)) end
  if B2_offset then
    return partial()
  elseif message then
    -- Actually perform calculations and return the BLAKE2b digest of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading
    -- User should feed every chunk of input data as single argument to this function and finally get BLAKE2b digest by invoking this function without an argument
    return partial
  end
end

local function blake2sp(message, key, salt, digest_size_in_bytes)
  -- message:  binary string to be hashed (or nil for "chunk-by-chunk" input mode)
  -- key:      (optional) binary string up to 32 bytes, by default empty string
  -- salt:     (optional) binary string up to 16 bytes, by default empty string
  -- digest_size_in_bytes: (optional) integer from 1 to 32, by default 32
  digest_size_in_bytes = digest_size_in_bytes or 32
  if digest_size_in_bytes < 1 or digest_size_in_bytes > 32 then
    error("BLAKE2sp digest length must be from 1 to 32 bytes", 2)
  end
  key = key or ""
  local key_length = #key
  if key_length > 32 then error("BLAKE2sp key length must not exceed 32 bytes", 2) end
  salt = salt or ""
  local instances, length, first_dword_of_parameter_block, result =
    {}, 0.0, 0x02080000 + key_length * 256 + digest_size_in_bytes
  for j = 1, 8 do
    local bytes_compressed, tail, H = 0.0, "", { unpack(sha2_H_hi) }
    instances[j] = { bytes_compressed, tail, H }
    H[1] = XOR(H[1], first_dword_of_parameter_block)
    H[3] = XOR(H[3], j - 1)
    H[4] = XOR(H[4], 0x20000000)
    if salt ~= "" then xor_blake2_salt(salt, "s", H) end
  end

  local function partial(message_part)
    if message_part then
      if instances then
        local from = 0
        while true do
          local to = math_min(from + 64 - length % 64, #message_part)
          if to > from then
            local inst = instances[floor(length / 64) % 8 + 1]
            local part = sub(message_part, from + 1, to)
            length, from = length + to - from, to
            local bytes_compressed, tail = inst[1], inst[2]
            if #tail < 64 then
              tail = tail .. part
            else
              local H = inst[3]
              bytes_compressed = blake2s_feed_64(H, tail, 0, 64, bytes_compressed)
              tail = part
            end
            inst[1], inst[2] = bytes_compressed, tail
          else
            break
          end
        end
        return partial
      else
        error("Adding more chunks is not allowed after receiving the result", 2)
      end
    else
      if instances then
        local root_H = { unpack(sha2_H_hi) }
        root_H[1] = XOR(root_H[1], first_dword_of_parameter_block)
        root_H[4] = XOR(root_H[4], 0x20010000)
        if salt ~= "" then xor_blake2_salt(salt, "s", root_H) end
        for j = 1, 8 do
          local inst = instances[j]
          local bytes_compressed, tail, H = inst[1], inst[2], inst[3]
          blake2s_feed_64(H, tail .. string_rep("\0", 64 - #tail), 0, 64, bytes_compressed, #tail, j == 8)
          if j % 2 == 0 then
            local index = 0
            for k = j - 1, j do
              local inst = instances[k]
              local H = inst[3]
              for i = 1, 8 do
                index = index + 1
                common_W_blake2s[index] = H[i]
              end
            end
            blake2s_feed_64(root_H, nil, 0, 64, 64 * (j / 2 - 1), j == 8 and 64, j == 8)
          end
        end
        instances = nil
        local max_reg = ceil(digest_size_in_bytes / 4)
        for j = 1, max_reg do
          root_H[j] = HEX(root_H[j])
        end
        result =
          sub(gsub(table_concat(root_H, "", 1, max_reg), "(..)(..)(..)(..)", "%4%3%2%1"), 1, digest_size_in_bytes * 2)
      end
      return result
    end
  end

  if key_length > 0 then
    key = key .. string_rep("\0", 64 - key_length)
    for j = 1, 8 do
      partial(key)
    end
  end
  if message then
    -- Actually perform calculations and return the BLAKE2sp digest of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading
    -- User should feed every chunk of input data as single argument to this function and finally get BLAKE2sp digest by invoking this function without an argument
    return partial
  end
end

local function blake2bp(message, key, salt, digest_size_in_bytes)
  -- message:  binary string to be hashed (or nil for "chunk-by-chunk" input mode)
  -- key:      (optional) binary string up to 64 bytes, by default empty string
  -- salt:     (optional) binary string up to 32 bytes, by default empty string
  -- digest_size_in_bytes: (optional) integer from 1 to 64, by default 64
  digest_size_in_bytes = digest_size_in_bytes or 64
  if digest_size_in_bytes < 1 or digest_size_in_bytes > 64 then
    error("BLAKE2bp digest length must be from 1 to 64 bytes", 2)
  end
  key = key or ""
  local key_length = #key
  if key_length > 64 then error("BLAKE2bp key length must not exceed 64 bytes", 2) end
  salt = salt or ""
  local instances, length, first_dword_of_parameter_block, result =
    {}, 0.0, 0x02040000 + key_length * 256 + digest_size_in_bytes
  for j = 1, 4 do
    local bytes_compressed, tail, H_lo, H_hi = 0.0, "", { unpack(sha2_H_lo) }, not HEX64 and { unpack(sha2_H_hi) }
    instances[j] = { bytes_compressed, tail, H_lo, H_hi }
    H_lo[1] = XORA5(H_lo[1], first_dword_of_parameter_block)
    H_lo[2] = XORA5(H_lo[2], j - 1)
    H_lo[3] = XORA5(H_lo[3], 0x4000)
    if salt ~= "" then xor_blake2_salt(salt, "b", H_lo, H_hi) end
  end

  local function partial(message_part)
    if message_part then
      if instances then
        local from = 0
        while true do
          local to = math_min(from + 128 - length % 128, #message_part)
          if to > from then
            local inst = instances[floor(length / 128) % 4 + 1]
            local part = sub(message_part, from + 1, to)
            length, from = length + to - from, to
            local bytes_compressed, tail = inst[1], inst[2]
            if #tail < 128 then
              tail = tail .. part
            else
              local H_lo, H_hi = inst[3], inst[4]
              bytes_compressed = blake2b_feed_128(H_lo, H_hi, tail, 0, 128, bytes_compressed)
              tail = part
            end
            inst[1], inst[2] = bytes_compressed, tail
          else
            break
          end
        end
        return partial
      else
        error("Adding more chunks is not allowed after receiving the result", 2)
      end
    else
      if instances then
        local root_H_lo, root_H_hi = { unpack(sha2_H_lo) }, not HEX64 and { unpack(sha2_H_hi) }
        root_H_lo[1] = XORA5(root_H_lo[1], first_dword_of_parameter_block)
        root_H_lo[3] = XORA5(root_H_lo[3], 0x4001)
        if salt ~= "" then xor_blake2_salt(salt, "b", root_H_lo, root_H_hi) end
        for j = 1, 4 do
          local inst = instances[j]
          local bytes_compressed, tail, H_lo, H_hi = inst[1], inst[2], inst[3], inst[4]
          blake2b_feed_128(H_lo, H_hi, tail .. string_rep("\0", 128 - #tail), 0, 128, bytes_compressed, #tail, j == 4)
          if j % 2 == 0 then
            local index = 0
            for k = j - 1, j do
              local inst = instances[k]
              local H_lo, H_hi = inst[3], inst[4]
              for i = 1, 8 do
                index = index + 1
                common_W_blake2b[index] = H_lo[i]
                if H_hi then
                  index = index + 1
                  common_W_blake2b[index] = H_hi[i]
                end
              end
            end
            blake2b_feed_128(root_H_lo, root_H_hi, nil, 0, 128, 128 * (j / 2 - 1), j == 4 and 128, j == 4)
          end
        end
        instances = nil
        local max_reg = ceil(digest_size_in_bytes / 8)
        if HEX64 then
          for j = 1, max_reg do
            root_H_lo[j] = HEX64(root_H_lo[j])
          end
        else
          for j = 1, max_reg do
            root_H_lo[j] = HEX(root_H_hi[j]) .. HEX(root_H_lo[j])
          end
        end
        result = sub(
          gsub(table_concat(root_H_lo, "", 1, max_reg), "(..)(..)(..)(..)(..)(..)(..)(..)", "%8%7%6%5%4%3%2%1"),
          1,
          digest_size_in_bytes * 2
        )
      end
      return result
    end
  end

  if key_length > 0 then
    key = key .. string_rep("\0", 128 - key_length)
    for j = 1, 4 do
      partial(key)
    end
  end
  if message then
    -- Actually perform calculations and return the BLAKE2bp digest of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading
    -- User should feed every chunk of input data as single argument to this function and finally get BLAKE2bp digest by invoking this function without an argument
    return partial
  end
end

local function blake2x(
  inner_func,
  inner_func_letter,
  common_W_blake2,
  block_size,
  digest_size_in_bytes,
  message,
  key,
  salt
)
  local XOF_digest_length_limit, XOF_digest_length, chunk_by_chunk_output = 2 ^ (block_size / 2) - 1
  if digest_size_in_bytes == -1 then -- infinite digest
    digest_size_in_bytes = math_huge
    XOF_digest_length = floor(XOF_digest_length_limit)
    chunk_by_chunk_output = true
  else
    if digest_size_in_bytes < 0 then
      digest_size_in_bytes = -1.0 * digest_size_in_bytes
      chunk_by_chunk_output = true
    end
    XOF_digest_length = floor(digest_size_in_bytes)
    if XOF_digest_length >= XOF_digest_length_limit then
      error(
        "Requested digest is too long.  BLAKE2X"
          .. inner_func_letter
          .. " finite digest is limited by (2^"
          .. floor(block_size / 2)
          .. ")-2 bytes.  Hint: you can generate infinite digest.",
        2
      )
    end
  end
  salt = salt or ""
  if salt ~= "" then
    xor_blake2_salt(salt, inner_func_letter) -- don't xor, only check the size of salt
  end
  local inner_partial = inner_func(nil, key, salt, nil, XOF_digest_length)
  local result

  local function partial(message_part)
    if message_part then
      if inner_partial then
        inner_partial(message_part)
        return partial
      else
        error("Adding more chunks is not allowed after receiving the result", 2)
      end
    else
      if inner_partial then
        local half_W, half_W_size = inner_partial()
        half_W_size, inner_partial = half_W_size or 8

        local function get_hash_block(block_no)
          -- block_no = 0...(2^32-1)
          local size = math_min(block_size, digest_size_in_bytes - block_no * block_size)
          if size <= 0 then return "" end
          for j = 1, half_W_size do
            common_W_blake2[j] = half_W[j]
          end
          for j = half_W_size + 1, 2 * half_W_size do
            common_W_blake2[j] = 0
          end
          return inner_func(nil, nil, salt, size, XOF_digest_length, floor(block_no))
        end

        local hash = {}
        if chunk_by_chunk_output then
          local pos, period, cached_block_no, cached_block = 0, block_size * 2 ^ 32

          local function get_next_part_of_digest(arg1, arg2)
            if arg1 == "seek" then
              -- Usage #1:  get_next_part_of_digest("seek", new_pos)
              pos = arg2 % period
            else
              -- Usage #2:  hex_string = get_next_part_of_digest(size)
              local size, index = arg1 or 1, 0
              while size > 0 do
                local block_offset = pos % block_size
                local block_no = (pos - block_offset) / block_size
                local part_size = math_min(size, block_size - block_offset)
                if cached_block_no ~= block_no then
                  cached_block_no = block_no
                  cached_block = get_hash_block(block_no)
                end
                index = index + 1
                hash[index] = sub(cached_block, block_offset * 2 + 1, (block_offset + part_size) * 2)
                size = size - part_size
                pos = (pos + part_size) % period
              end
              return table_concat(hash, "", 1, index)
            end
          end

          result = get_next_part_of_digest
        else
          for j = 1.0, ceil(digest_size_in_bytes / block_size) do
            hash[j] = get_hash_block(j - 1.0)
          end
          result = table_concat(hash)
        end
      end
      return result
    end
  end

  if message then
    -- Actually perform calculations and return the BLAKE2X digest of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading
    -- User should feed every chunk of input data as single argument to this function and finally get BLAKE2X digest by invoking this function without an argument
    return partial
  end
end

local function blake2xs(digest_size_in_bytes, message, key, salt)
  -- digest_size_in_bytes:
  --    0..65534       = get finite digest as single Lua string
  --    (-1)           = get infinite digest in "chunk-by-chunk" output mode
  --    (-2)..(-65534) = get finite digest in "chunk-by-chunk" output mode
  -- message:  binary string to be hashed (or nil for "chunk-by-chunk" input mode)
  -- key:      (optional) binary string up to 32 bytes, by default empty string
  -- salt:     (optional) binary string up to 16 bytes, by default empty string
  return blake2x(blake2s, "s", common_W_blake2s, 32, digest_size_in_bytes, message, key, salt)
end

local function blake2xb(digest_size_in_bytes, message, key, salt)
  -- digest_size_in_bytes:
  --    0..4294967294       = get finite digest as single Lua string
  --    (-1)                = get infinite digest in "chunk-by-chunk" output mode
  --    (-2)..(-4294967294) = get finite digest in "chunk-by-chunk" output mode
  -- message:  binary string to be hashed (or nil for "chunk-by-chunk" input mode)
  -- key:      (optional) binary string up to 64 bytes, by default empty string
  -- salt:     (optional) binary string up to 32 bytes, by default empty string
  return blake2x(blake2b, "b", common_W_blake2b, 64, digest_size_in_bytes, message, key, salt)
end

local function blake3(message, key, digest_size_in_bytes, message_flags, K, return_array)
  -- message:  binary string to be hashed (or nil for "chunk-by-chunk" input mode)
  -- key:      (optional) binary string up to 32 bytes, by default empty string
  -- digest_size_in_bytes: (optional) by default 32
  --    0,1,2,3,4,...  = get finite digest as single Lua string
  --    (-1)           = get infinite digest in "chunk-by-chunk" output mode
  --    -2,-3,-4,...   = get finite digest in "chunk-by-chunk" output mode
  -- The last three parameters "message_flags", "K" and "return_array" are for internal use only, user must omit them (or pass nil)
  key = key or ""
  digest_size_in_bytes = digest_size_in_bytes or 32
  message_flags = message_flags or 0
  if key == "" then
    K = K or sha2_H_hi
  else
    local key_length = #key
    if key_length > 32 then error("BLAKE3 key length must not exceed 32 bytes", 2) end
    key = key .. string_rep("\0", 32 - key_length)
    K = {}
    for j = 1, 8 do
      local a, b, c, d = byte(key, 4 * j - 3, 4 * j)
      K[j] = ((d * 256 + c) * 256 + b) * 256 + a
    end
    message_flags = message_flags + 16 -- flag:KEYED_HASH
  end
  local tail, H, chunk_index, blocks_in_chunk, stack_size, stack = "", {}, 0, 0, 0, {}
  local final_H_in, final_block_length, chunk_by_chunk_output, result, wide_output = K
  local final_compression_flags = 3 -- flags:CHUNK_START,CHUNK_END

  local function feed_blocks(str, offs, size)
    -- size >= 0, size is multiple of 64
    while size > 0 do
      local part_size_in_blocks, block_flags, H_in = 1, 0, H
      if blocks_in_chunk == 0 then
        block_flags = 1 -- flag:CHUNK_START
        H_in, final_H_in = K, H
        final_compression_flags = 2 -- flag:CHUNK_END
      elseif blocks_in_chunk == 15 then
        block_flags = 2 -- flag:CHUNK_END
        final_compression_flags = 3 -- flags:CHUNK_START,CHUNK_END
        final_H_in = K
      else
        part_size_in_blocks = math_min(size / 64, 15 - blocks_in_chunk)
      end
      local part_size = part_size_in_blocks * 64
      blake3_feed_64(str, offs, part_size, message_flags + block_flags, chunk_index, H_in, H)
      offs, size = offs + part_size, size - part_size
      blocks_in_chunk = (blocks_in_chunk + part_size_in_blocks) % 16
      if blocks_in_chunk == 0 then
        -- completing the currect chunk
        chunk_index = chunk_index + 1.0
        local divider = 2.0
        while chunk_index % divider == 0 do
          divider = divider * 2.0
          stack_size = stack_size - 8
          for j = 1, 8 do
            common_W_blake2s[j] = stack[stack_size + j]
          end
          for j = 1, 8 do
            common_W_blake2s[j + 8] = H[j]
          end
          blake3_feed_64(nil, 0, 64, message_flags + 4, 0, K, H) -- flag:PARENT
        end
        for j = 1, 8 do
          stack[stack_size + j] = H[j]
        end
        stack_size = stack_size + 8
      end
    end
  end

  local function get_hash_block(block_no)
    local size = math_min(64, digest_size_in_bytes - block_no * 64)
    if block_no < 0 or size <= 0 then return "" end
    if chunk_by_chunk_output then
      for j = 1, 16 do
        common_W_blake2s[j] = stack[j + 16]
      end
    end
    blake3_feed_64(nil, 0, 64, final_compression_flags, block_no, final_H_in, stack, wide_output, final_block_length)
    if return_array then return stack end
    local max_reg = ceil(size / 4)
    for j = 1, max_reg do
      stack[j] = HEX(stack[j])
    end
    return sub(gsub(table_concat(stack, "", 1, max_reg), "(..)(..)(..)(..)", "%4%3%2%1"), 1, size * 2)
  end

  local function partial(message_part)
    if message_part then
      if tail then
        local offs = 0
        if tail ~= "" and #tail + #message_part > 64 then
          offs = 64 - #tail
          feed_blocks(tail .. sub(message_part, 1, offs), 0, 64)
          tail = ""
        end
        local size = #message_part - offs
        local size_tail = size > 0 and (size - 1) % 64 + 1 or 0
        feed_blocks(message_part, offs, size - size_tail)
        tail = tail .. sub(message_part, #message_part + 1 - size_tail)
        return partial
      else
        error("Adding more chunks is not allowed after receiving the result", 2)
      end
    else
      if tail then
        final_block_length = #tail
        tail = tail .. string_rep("\0", 64 - #tail)
        if common_W_blake2s[0] then
          for j = 1, 16 do
            local a, b, c, d = byte(tail, 4 * j - 3, 4 * j)
            common_W_blake2s[j] = OR(SHL(d, 24), SHL(c, 16), SHL(b, 8), a)
          end
        else
          for j = 1, 16 do
            local a, b, c, d = byte(tail, 4 * j - 3, 4 * j)
            common_W_blake2s[j] = ((d * 256 + c) * 256 + b) * 256 + a
          end
        end
        tail = nil
        for stack_size = stack_size - 8, 0, -8 do
          blake3_feed_64(
            nil,
            0,
            64,
            message_flags + final_compression_flags,
            chunk_index,
            final_H_in,
            H,
            nil,
            final_block_length
          )
          chunk_index, final_block_length, final_H_in, final_compression_flags = 0, 64, K, 4 -- flag:PARENT
          for j = 1, 8 do
            common_W_blake2s[j] = stack[stack_size + j]
          end
          for j = 1, 8 do
            common_W_blake2s[j + 8] = H[j]
          end
        end
        final_compression_flags = message_flags + final_compression_flags + 8 -- flag:ROOT
        if digest_size_in_bytes < 0 then
          if digest_size_in_bytes == -1 then -- infinite digest
            digest_size_in_bytes = math_huge
          else
            digest_size_in_bytes = -1.0 * digest_size_in_bytes
          end
          chunk_by_chunk_output = true
          for j = 1, 16 do
            stack[j + 16] = common_W_blake2s[j]
          end
        end
        digest_size_in_bytes = math_min(2 ^ 53, digest_size_in_bytes)
        wide_output = digest_size_in_bytes > 32
        if chunk_by_chunk_output then
          local pos, cached_block_no, cached_block = 0.0

          local function get_next_part_of_digest(arg1, arg2)
            if arg1 == "seek" then
              -- Usage #1:  get_next_part_of_digest("seek", new_pos)
              pos = arg2 * 1.0
            else
              -- Usage #2:  hex_string = get_next_part_of_digest(size)
              local size, index = arg1 or 1, 32
              while size > 0 do
                local block_offset = pos % 64
                local block_no = (pos - block_offset) / 64
                local part_size = math_min(size, 64 - block_offset)
                if cached_block_no ~= block_no then
                  cached_block_no = block_no
                  cached_block = get_hash_block(block_no)
                end
                index = index + 1
                stack[index] = sub(cached_block, block_offset * 2 + 1, (block_offset + part_size) * 2)
                size = size - part_size
                pos = pos + part_size
              end
              return table_concat(stack, "", 33, index)
            end
          end

          result = get_next_part_of_digest
        elseif digest_size_in_bytes <= 64 then
          result = get_hash_block(0)
        else
          local last_block_no = ceil(digest_size_in_bytes / 64) - 1
          for block_no = 0.0, last_block_no do
            stack[33 + block_no] = get_hash_block(block_no)
          end
          result = table_concat(stack, "", 33, 33 + last_block_no)
        end
      end
      return result
    end
  end

  if message then
    -- Actually perform calculations and return the BLAKE3 digest of a message
    return partial(message)()
  else
    -- Return function for chunk-by-chunk loading
    -- User should feed every chunk of input data as single argument to this function and finally get BLAKE3 digest by invoking this function without an argument
    return partial
  end
end

local function blake3_derive_key(key_material, context_string, derived_key_size_in_bytes)
  -- key_material: (string) your source of entropy to derive a key from (for example, it can be a master password)
  --               set to nil for feeding the key material in "chunk-by-chunk" input mode
  -- context_string: (string) unique description of the derived key
  -- digest_size_in_bytes: (optional) by default 32
  --    0,1,2,3,4,...  = get finite derived key as single Lua string
  --    (-1)           = get infinite derived key in "chunk-by-chunk" output mode
  --    -2,-3,-4,...   = get finite derived key in "chunk-by-chunk" output mode
  if type(context_string) ~= "string" then error("'context_string' parameter must be a Lua string", 2) end
  local K = blake3(context_string, nil, nil, 32, nil, true) -- flag:DERIVE_KEY_CONTEXT
  return blake3(key_material, nil, derived_key_size_in_bytes, 64, K) -- flag:DERIVE_KEY_MATERIAL
end

local sha = {
  md5 = md5, -- MD5
  sha1 = sha1, -- SHA-1
  -- SHA-2 hash functions:
  sha224 = function(message) return sha256ext(224, message) end, -- SHA-224
  sha256 = function(message) return sha256ext(256, message) end, -- SHA-256
  sha512_224 = function(message) return sha512ext(224, message) end, -- SHA-512/224
  sha512_256 = function(message) return sha512ext(256, message) end, -- SHA-512/256
  sha384 = function(message) return sha512ext(384, message) end, -- SHA-384
  sha512 = function(message) return sha512ext(512, message) end, -- SHA-512
  -- SHA-3 hash functions:
  sha3_224 = function(message) return keccak((1600 - 2 * 224) / 8, 224 / 8, false, message) end, -- SHA3-224
  sha3_256 = function(message) return keccak((1600 - 2 * 256) / 8, 256 / 8, false, message) end, -- SHA3-256
  sha3_384 = function(message) return keccak((1600 - 2 * 384) / 8, 384 / 8, false, message) end, -- SHA3-384
  sha3_512 = function(message) return keccak((1600 - 2 * 512) / 8, 512 / 8, false, message) end, -- SHA3-512
  shake128 = function(digest_size_in_bytes, message)
    return keccak((1600 - 2 * 128) / 8, digest_size_in_bytes, true, message)
  end, -- SHAKE128
  shake256 = function(digest_size_in_bytes, message)
    return keccak((1600 - 2 * 256) / 8, digest_size_in_bytes, true, message)
  end, -- SHAKE256
  -- HMAC:
  hmac = hmac, -- HMAC(hash_func, key, message) is applicable to any hash function from this module except SHAKE* and BLAKE*
  -- misc utilities:
  hex_to_bin = hex_to_bin, -- converts hexadecimal representation to binary string
  bin_to_hex = bin_to_hex, -- converts binary string to hexadecimal representation
  base64_to_bin = base64_to_bin, -- converts base64 representation to binary string
  bin_to_base64 = bin_to_base64, -- converts binary string to base64 representation
  -- old style names for backward compatibility:
  hex2bin = hex_to_bin,
  bin2hex = bin_to_hex,
  base642bin = base64_to_bin,
  bin2base64 = bin_to_base64,
  -- BLAKE2 hash functions:
  blake2b = blake2b, -- BLAKE2b (message, key, salt, digest_size_in_bytes)
  blake2s = blake2s, -- BLAKE2s (message, key, salt, digest_size_in_bytes)
  blake2bp = blake2bp, -- BLAKE2bp(message, key, salt, digest_size_in_bytes)
  blake2sp = blake2sp, -- BLAKE2sp(message, key, salt, digest_size_in_bytes)
  blake2xb = blake2xb, -- BLAKE2Xb(digest_size_in_bytes, message, key, salt)
  blake2xs = blake2xs, -- BLAKE2Xs(digest_size_in_bytes, message, key, salt)
  -- BLAKE2 aliases:
  blake2 = blake2b,
  blake2b_160 = function(message, key, salt) return blake2b(message, key, salt, 20) end, -- BLAKE2b-160
  blake2b_256 = function(message, key, salt) return blake2b(message, key, salt, 32) end, -- BLAKE2b-256
  blake2b_384 = function(message, key, salt) return blake2b(message, key, salt, 48) end, -- BLAKE2b-384
  blake2b_512 = blake2b, -- 64       -- BLAKE2b-512
  blake2s_128 = function(message, key, salt) return blake2s(message, key, salt, 16) end, -- BLAKE2s-128
  blake2s_160 = function(message, key, salt) return blake2s(message, key, salt, 20) end, -- BLAKE2s-160
  blake2s_224 = function(message, key, salt) return blake2s(message, key, salt, 28) end, -- BLAKE2s-224
  blake2s_256 = blake2s, -- 32       -- BLAKE2s-256
  -- BLAKE3 hash function
  blake3 = blake3, -- BLAKE3    (message, key, digest_size_in_bytes)
  blake3_derive_key = blake3_derive_key, -- BLAKE3_KDF(key_material, context_string, derived_key_size_in_bytes)
}

block_size_for_HMAC = {
  [sha.md5] = 64,
  [sha.sha1] = 64,
  [sha.sha224] = 64,
  [sha.sha256] = 64,
  [sha.sha512_224] = 128,
  [sha.sha512_256] = 128,
  [sha.sha384] = 128,
  [sha.sha512] = 128,
  [sha.sha3_224] = 144, -- (1600 - 2 * 224) / 8
  [sha.sha3_256] = 136, -- (1600 - 2 * 256) / 8
  [sha.sha3_384] = 104, -- (1600 - 2 * 384) / 8
  [sha.sha3_512] = 72, -- (1600 - 2 * 512) / 8
}

return sha
