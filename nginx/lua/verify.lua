local rsa = require "resty.rsa"
local str = require "resty.string"
local timestamp_threshold = 300  -- 5 minutes in seconds

local function respond(code, msg)
    ngx.status = code
    ngx.say(msg)
    ngx.exit(code)
end

local function is_local_ip(ip)
    return ip == "127.0.0.1" or 
           ip:match("^10%.[0-9]+%.[0-9]+%.[0-9]+$") or
           ip:match("^192%.168%.[0-9]+%.[0-9]+$") or
           ip:match("^172%.(1[6-9]|2[0-9]|3[0-1])%.[0-9]+%.[0-9]+$")
end

ngx.req.read_body()
local args = ngx.req.get_post_args()
local client_ip = ngx.var.remote_addr

if is_local_ip(client_ip) then
    ngx.log(ngx.DEBUG, "Local IP bypass: ", client_ip)
else
    -- Validate required parameters
    local signature = args.signature
    local message = args.message
    local timestamp = args.timestamp
    
    if not (signature and message and timestamp) then
        return respond(400, "Missing required parameters")
    end

    -- Validate timestamp format and freshness
    local current_time = ngx.time()
    local ts_num = tonumber(timestamp)
    
    if not ts_num or ts_num > current_time or 
       (current_time - ts_num) > timestamp_threshold then
        return respond(403, "Invalid or expired timestamp")
    end

    -- Validate message format
    if message ~= "clear-cache-" .. timestamp then
        return respond(400, "Invalid message format")
    end

    -- Signature processing
    signature = signature:gsub("%s+", ""):gsub("-", "+"):gsub("_", "/")
    local padding = 4 - (#signature % 4)
    if padding > 0 and padding < 4 then
        signature = signature .. string.rep("=", padding)
    end

    -- Load public key
    local file, err = io.open("/usr/local/openresty/nginx/keys/public.pem", "r")
    if not file then
        return respond(500, "Error loading public key: " .. (err or ""))
    end
    
    local pub, err = rsa:new({
        public_key = file:read("*a"),
        key_type = rsa.KEY_TYPE.PKCS1,
        algorithm = "sha256",
    })
    file:close()
    
    if not pub then
        return respond(500, "RSA init failed: " .. (err or ""))
    end

    -- Cryptographic verification
    local decoded_sig = ngx.decode_base64(signature)
    if not decoded_sig then
        return respond(400, "Invalid base64 encoding")
    end
    
    local ok, err = pub:verify(message, decoded_sig)
    if not ok then
        ngx.log(ngx.ERR, "Signature verification failed: ", err)
        return respond(403, "Invalid signature")
    end
end

-- Perform cache clearance
os.execute("find /usr/local/openresty/nginx/proxy-cache/ -type f -delete")
return respond(200, "Cache cleared successfully")