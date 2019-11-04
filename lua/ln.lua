local http = require "resty.http"
local cjson = require "cjson"

local vaultURL = os.getenv("VAULT_ADDR")
local baseURI = os.getenv("LN_BASE_URI")
local symlinksPath = os.getenv("LN_SYMLINKS_PATH")
local newPath = ""
local httpc = http.new()
local path = ngx.var.request_uri
local realPath = path

local _M = {}

local get_headers = ngx.req.get_headers
local get_body_data = ngx.req.get_body_data
local get_method = ngx.req.get_method
local read_body = ngx.req.read_body
local log = ngx.log
local say = ngx.say


local ERR = ngx.ERR
local INFO = ngx.INFO

-- Functions
--

local function proxy_vault(path, body, headers, method)
  log(INFO, "Processing request to " .. vaultURL .. path)
  log(INFO, "Method: " .. method)
  local res, err = httpc:request_uri(vaultURL .. path, {
    method = method,
    body = body,
    headers = headers,
    ssl_verify = true
  })

  if err ~= nil then
    log(INFO, "Error in proxy request")
    return nil, err
  end

  return res, nil
end

local function get_symlinks(path, body, headers)
  res, err =  proxy_vault("/v1/secret/data/" .. path, body, headers, "GET")
  return res, err
end

-- Main Program
--

function _M.go()
  read_body()
  local method = get_method()
  local body = get_body_data()
  local headers = get_headers()

  if method ~= "GET" then
    log(INFO, "Not a GET request, passing to " .. vaultURL .. path .. " as is.")
    res, err = proxy_vault(path, body, headers, method)
    ngx.status = res.status

    for h, v in pairs(res.headers) do
      ngx.header[h] = v
    end
    log(INFO, "Returning not GET")
    return ngx.print(res.body)
  end

  if not string.find(path, "/v1/secret") then
    log(INFO, "Not a secret, passing to " .. vaultURL .. path .. " as is.")
    res, err = proxy_vault(path, body, headers, method)
    ngx.status = res.status

    for h, v in pairs(res.headers) do
      ngx.header[h] = v
    end
    log(INFO, "Returning not /v1/secret")
    return ngx.print(res.body)
  end

  if baseURI ~= nil and baseURI ~= "" then
    realPath = path:gsub(baseURI, "")
  end

  if symlinksPath == nil or symlinksPath == "" then
    symlinksPath = "symlinks"
  end

  log(INFO, "Checking for symlinks at " .. vaultURL .. "/v1/secret/data/" .. symlinksPath)

  res, err = get_symlinks(symlinksPath, body, headers)

  -- if vault backend returns connection refused
  if err ~= nil then
    ngx.status = 503
    ngx.say(err)
    ngx.flush(true)
    return
  end

  if res.status == 404 then
    log(INFO, "Symlinks not found, proxying to vault as is: " .. path)
    res, err = proxy_vault(path, body, headers, method)
    ngx.status = res.status

    for h, v in pairs(res.headers) do
      ngx.header[h] = v
    end
    log(INFO, "Returning no symlinks at " .. symlinksPath)
    return ngx.print(res.body)
  end
  
  jsonBody = cjson.decode(res.body)
  
  for k, v in pairs(jsonBody["data"]["data"]) do
    if string.find(realPath, k) then
      newPath = v

      log(INFO, "Found " .. realPath .. " pointing to " .. newPath)
    end
  end

  log(INFO, newPath)

  if newPath == "" then
    newPath = realPath
  else
    newPath = "/v1/secret/data/" .. newPath
    log(INFO, "Found symlink for " .. path .. " at " .. newPath)
  end

  res, err = proxy_vault(newPath, body, headers, method)

  ngx.status = res.status
  for h, v in pairs(res.headers) do
    ngx.header[h] = v
  end
  return ngx.print(res.body)
end

return _M.go()