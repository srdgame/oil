
local assert = assert
local error = error
local type  = type

local oil = require "oil"
require "oil.dtests"
module "oil.dtests"

timeout = 3
querytime = .5

Reference = "%q,%q,%d\0"
function resolve(proc, port, objkey, kind, nowait)
	assert(orb ~= nil, "DTest not initialized")
	local proxy = orb:newproxy(Reference:format(objkey, hosts[proc] or proc, port))
	if nowait then return proxy end
	for i = 1, timeout/querytime do
		local success, errmsg = oil.pcall(proxy._non_existent, proxy)
		if success or (type(errmsg) == "table" and errmsg.reason == "noimplement")
		then -- '_non_existent' may not provided but such object exists ;-)
			return proxy
		end
		oil.sleep(querytime)
	end
	error("object not found")
end
