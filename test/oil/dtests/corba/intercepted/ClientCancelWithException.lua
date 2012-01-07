local Suite = require "loop.test.Suite"
local Template = require "oil.dtests.Template"
local template = Template{"Client"} -- master process name

Client = [=====================================================================[
checks = oil.dtests.checks

Exception = newproxy()

Interceptor = {}
function Interceptor:sendrequest(request)
	if request.object_key == "object"
	and request.operation_name == "concat"
	then
		request.success = false
		request.results = { Exception }
	end
end

orb = oil.dtests.init()
orb:setclientinterceptor(Interceptor)
sync = oil.dtests.resolve("Server", 2809, "object", nil, true, true)
orb:loadidl[[
	interface MyInterface {
		string concat(in string str1, in string str2);
	};
]]
sync = orb:narrow(sync, "MyInterface")
async = orb:newproxy(sync, "asynchronous")
prot = orb:newproxy(sync, "protected")

ok, res = pcall(sync.concat, sync, "first", "second")
checks:assert(ok, checks.is(false))
checks:assert(res, checks.is(Exception))

ok, res = async:concat("first", "second"):results()
checks:assert(ok, checks.is(false))
checks:assert(res, checks.is(Exception))

ok, res = prot:concat("first", "second")
checks:assert(ok, checks.is(false))
checks:assert(res, checks.is(Exception))
--[Client]=====================================================================]

return template:newsuite{ corba = true, interceptedcorba = true }
