local M = {}

---Generates a random N number of bytes using crypto lib over ffi, falling back to urandom
---@param n integer number of bytes to generate
---@return string|nil bytes string of bytes generated, or nil if all methods fail
---@return string|nil error error message if generation failed
local function get_random_bytes(n)
  local ok, ffi = pcall(require, "ffi")
  if ok then
    -- Try OpenSSL first (cross-platform)
    local lib_ok, lib = pcall(ffi.load, "crypto")
    if lib_ok then
      local cdef_ok = pcall(
        ffi.cdef,
        [[
        int RAND_bytes(unsigned char *buf, int num);
      ]]
      )
      if cdef_ok then
        local buf = ffi.new("unsigned char[?]", n)
        if lib.RAND_bytes(buf, n) == 1 then return ffi.string(buf, n), nil end
      end
      return nil, "OpenSSL RAND_bytes failed - OpenSSL may not be properly installed"
    end
    return nil, "Failed to load OpenSSL crypto library - please install OpenSSL"
  end

  -- Fallback
  local f = io.open("/dev/urandom", "rb")
  if f then
    local bytes = f:read(n)
    f:close()
    return bytes, nil
  end

  return nil, "FFI not available and /dev/urandom is not accessible - cannot generate secure random bytes"
end

--- URL-safe base64
--- @param data string value to base64 encode
--- @return string base64String base64 encoded string
local function base64url_encode(data)
  local b64 = vim.base64.encode(data)
  local b64_string, _ = b64:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
  return b64_string
end

-- Generate code_verifier (43-128 characters)
--- @return string|nil verifier String representing pkce verifier or nil if generation fails
--- @return string|nil error error message if generation failed
function M.generate_verifier()
  local bytes, err = get_random_bytes(32) -- 256 bits
  if bytes then return base64url_encode(bytes), nil end

  return nil, err or "Failed to generate random bytes"
end

-- Generate code_challenge (S256 method)
---@return string|nil challenge String representing pkce challenge or nil if generation fails
---@return string|nil error error message if generation failed
function M.generate_challenge(verifier)
  local ok, ffi = pcall(require, "ffi")
  if ok then
    local lib_ok, lib = pcall(ffi.load, "crypto")
    if lib_ok then
      local cdef_ok = pcall(
        ffi.cdef,
        [[
        typedef unsigned char SHA256_DIGEST[32];
        void SHA256(const unsigned char *d, size_t n, SHA256_DIGEST md);
      ]]
      )
      if cdef_ok then
        local digest = ffi.new("SHA256_DIGEST")
        lib.SHA256(verifier, #verifier, digest)
        return base64url_encode(ffi.string(digest, 32)), nil
      end
      return nil, "Failed to define SHA256 function - OpenSSL may not be properly configured"
    end
    return nil, "Failed to load OpenSSL crypto library - please install OpenSSL"
  end

  return nil, "FFI not available - LuaJIT is required for PKCE authentication"
end

return M
