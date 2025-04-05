local rsa = require "resty.rsa"
local str = require "resty.string"

local function respond(code, msg)
    ngx.status = code
    ngx.say(msg)
    ngx.exit(code)
end

-- Check if the client is from a local IP (e.g., 127.0.0.1 or any other local range)
local function is_local_ip(ip)
    return ip == "127.0.0.1" or ip:match("^10%.[0-9]+%.[0-9]+%.[0-9]+$") or ip:match("^192%.168%.[0-9]+%.[0-9]+$") or ip:match("^172%.[16-31]%.[0-9]+%.[0-9]+$")
end

-- Read POST body
ngx.req.read_body()
local args = ngx.req.get_post_args()

-- Get the client's IP address
local client_ip = ngx.var.remote_addr

-- If the client is from a local IP, skip the signature verification
if is_local_ip(client_ip) then
    ngx.log(ngx.DEBUG, "Request from local IP: skipping signature verification")
else
    local signature = args["signature"]
    if not signature then
        return respond(400, "Missing signature")
    end

    -- Remove all whitespace (spaces, newlines, etc.) from the signature
    signature = signature:gsub("%s+", "")
    if #signature % 4 ~= 0 then
        signature = signature .. string.rep("=", 4 - (#signature % 4))
    end

    local message = args["message"]
    if not message then
        return respond(400, "Missing message")
    end

    -- Load public key
    local file = io.open("/usr/local/openresty/nginx/keys/public.pem", "r")
    if not file then
        return respond(500, "Error opening public key file")
    end
    local pubkey = file:read("*a")
    file:close()

    -- Create RSA object (using PKCS1 format) and specify digest as SHA-256
    local pub, err = rsa:new({
        public_key = pubkey,
        key_type = rsa.KEY_TYPE.PKCS1,
        algorithm = "sha256",  -- Digest is set here during creation
    })
    if not pub then
        return respond(500, "Failed to create RSA object: " .. err)
    end

    -- Verify the signature (no need to pass digest here since it's already set during creation)
    local ok, err = pub:verify(message, ngx.decode_base64(signature))
    if not ok then
        ngx.log(ngx.ERR, "Verification failed: " .. (err or ""))
        return respond(403, "Invalid signature")
    end

    if message ~= "clear-cache-now" then
        return respond(400, "Invalid message")
    end
end

-- Clear cache
os.execute("rm -rf /usr/local/openresty/nginx/proxy-cache/*")
return respond(200, "Cache cleared")
