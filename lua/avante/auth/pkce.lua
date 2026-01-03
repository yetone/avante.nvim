local M = {}

---Generates a random N number of bytes using crypto lib over ffi, falling back
---to less secure methods
---@param n integer number of bytes to generate
---@return string bytes string of bytes generated
local function get_random_bytes(n)
  local ok, ffi = pcall(require, "ffi")
  if ok then
    -- Try OpenSSL first (cross-platform)
    local lib = ffi.load("crypto")
    ffi.cdef([[
      int RAND_bytes(unsigned char *buf, int num);
    ]])
    local buf = ffi.new("unsigned char[?]", n)
    if lib.RAND_bytes(buf, n) == 1 then return ffi.string(buf, n) end
  end
  -- Fallback: read from /dev/urandom (Unix) or use time-based seed
  -- For Windows, you'd need CryptGenRandom via FFI
  local f = io.open("/dev/urandom", "rb")
  if f then
    local bytes = f:read(n)
    f:close()
    return bytes
  end
  -- Last resort (NOT crypto-secure): use math.random
  local bytes = {}
  for i = 1, n do
    bytes[i] = string.char(math.random(0, 255))
  end
  return table.concat(bytes)
end

--- URL-safe base64
--- @param data string value to base64 encode
local function base64url_encode(data)
  local b64 = vim.base64.encode(data)
  return b64:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

-- Generate code_verifier (43-128 characters)
function M.generate_verifier()
  local bytes = get_random_bytes(32) -- 256 bits
  return base64url_encode(bytes)
end

-- Generate code_challenge (S256 method)
function M.generate_challenge(verifier)
  local ok, ffi = pcall(require, "ffi")
  if ok then
    local lib = ffi.load("crypto")
    ffi.cdef([[
      typedef unsigned char SHA256_DIGEST[32];
      void SHA256(const unsigned char *d, size_t n, SHA256_DIGEST md);
    ]])
    local digest = ffi.new("SHA256_DIGEST")
    lib.SHA256(verifier, #verifier, digest)
    return base64url_encode(ffi.string(digest, 32))
  end

  -- Pure Lua SHA-256 fallback
  local sha256 = require("avante.auth.sha2")
  local hash = sha256(verifier)
  return base64url_encode(hash)
end

return M
