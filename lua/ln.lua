local http = require "resty.http"
local cjson = require "cjson"

local vaultURL = os.getenv("VAULT_ADDR")
local baseURI = os.getenv("LN_BASE_URI")
local symlinksPath = os.getenv("LN_SYMLINKS_PATH")
local newPath = ""
local path = ngx.var.request_uri
local realPath = path
local httpc = http.new()

ngx.req.read_body()
headers = ngx.req.get_headers()
body = ngx.req.get_body_data()

if not (ngx.req.get_method() == "GET") then
  ngx.log(ngx.INFO, "Not a GET request, passing to " .. vaultURL .. path .. " as is.")

  local res, err = httpc:request_uri(vaultURL .. path, {
    method = ngx.req.get_method(),
    body = body,
    headers = headers,
    ssl_verify = true
  })

  if err ~= nil then
    ngx.status = 503
    ngx.say(err)
    ngx.flush(true)
    return
  end

  ngx.status = res.status

  for h, v in pairs(res.headers) do
    ngx.header[h] = v
  end

  return ngx.print(res.body)
end

if not string.find(path, "/v1/secret") then
  ngx.log(ngx.INFO, "Not a secret, passing to " .. vaultURL .. path .. " as is.")
  local res, err = httpc:request_uri(vaultURL .. path, {
    method = ngx.req.get_method(),
    body = body,
    headers = headers,
    ssl_verify = true
  })

  if err ~= nil then
    ngx.status = 503
    ngx.say(err)
    ngx.flush(true)
    return
  end

  ngx.status = res.status

  for h, v in pairs(res.headers) do
    ngx.header[h] = v
  end

  return ngx.print(res.body)
end

if baseURI ~= nil and baseURI ~= "" then
  realPath = path:gsub(baseURI, "")
end

if symlinksPath == nil or symlinksPath == "" then
  symlinksPath = "symlinks"
end

ngx.log(ngx.ERR, vaultURL .. "/v1/secret/data/" .. symlinksPath)

local res, err = httpc:request_uri(vaultURL .. "/v1/secret/data/" .. symlinksPath, {
  method = "GET",
  body = body,
  headers = headers,
  ssl_verify = true
})

if err ~= nil then
  ngx.status = 503
  ngx.say(err)
  ngx.flush(true)
  return
end

ngx.log(ngx.ERR, res.status)

if res.status == 404 then
  local res, err = httpc:request_uri(vaultURL .. path, {
    method = ngx.req.get_method(),
    body = body,
    headers = headers,
    ssl_verify = true
  })

  if err ~= nil then
    ngx.status = 503
    ngx.say(err)
    ngx.flush(true)
    return
  end

  ngx.status = res.status

  for h, v in pairs(res.headers) do
    ngx.header[h] = v
  end

  return ngx.print(res.body)
end

jsonBody = cjson.decode(res.body)

for k, v in pairs(jsonBody["data"]["data"]) do
  if string.find(realPath, k) then
    newPath = v
  end
end

if newPath == "" then
  newPath = realPath
else
  newPath = "/v1/secret/data/" .. newPath
end


ngx.log(ngx.INFO, "Found symlink for " .. path .. " at " .. newPath)
local res, err = httpc:request_uri(vaultURL .. newPath, {
  method = ngx.req.get_method(),
  body = body,
  headers = headers,
  ssl_verify = true
})

ngx.status = res.status
for h, v in pairs(res.headers) do
  ngx.header[h] = v
end
return ngx.print(res.body)

