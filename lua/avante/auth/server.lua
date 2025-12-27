local M = {}

function M.start_callback_server(port, callback)
  local server = vim.uv.new_tcp()

  server:bind("127.0.0.1", port)
  server:listen(128, function(err)
    assert(not err, err)

    local client = vim.uv.new_tcp()
    server:accept(client)

    client:read_start(function(err, chunk)
      assert(not err, err)

      if chunk then
        -- Simple HTTP request parser
        local path = chunk:match("GET (%S+) HTTP")
        if path then
          local code = path:match("code=([^&]+)")
          local state = path:match("state=([^&]+)")

          -- Send minimal HTTP response
          local response = "HTTP/1.1 200 OK\r\n\r\n<html><body>You can close this window</body></html>"
          client:write(response, function()
            client:close()
            server:close()

            -- Call the OAuth callback handler
            callback(code, state)
          end)
        end
      end
    end)
  end)

  return server
end

return M
