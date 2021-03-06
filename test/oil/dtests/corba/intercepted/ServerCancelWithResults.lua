local Suite = require "loop.test.Suite"
local Template = require "oil.dtests.Template"
local template = Template{"Client"} -- master process name

Server = [=====================================================================[
Interceptor = {}
function Interceptor:receiverequest(request)
	if request.object_key == "object"
	and request.operation_name == "concat"
	then
		request.success = true
		request.results = { request.parameters[1].." "..request.parameters[2] }
	end
end
function Interceptor:sendreply(request)
	if request.object_key == "object"
	and request.operation_name == "concat"
	then
		assert(request.success == true)
		assert(request.results[1] == "first second")
		request.results[1] = "first&second"
	end
end

orb = oil.dtests.init{ port = 2809 }
orb:setserverinterceptor(Interceptor)
orb:loadidl[[
	interface MyInterface {
		string concat(in string str1, in string str2);
	};
]]
orb:newservant({}, "object", "::MyInterface")
orb:run()
--[Server]=====================================================================]

Client = [=====================================================================[
orb = oil.dtests.init()
sync = oil.dtests.resolve("Server", 2809, "object")
orb:loadidl[[
	interface MyInterface {
		string concat(in string str1, in string str2);
	};
]]
sync = orb:narrow(sync, "MyInterface")
async = orb:newproxy(sync, "asynchronous")
prot = orb:newproxy(sync, "protected")

assert(sync:concat("first", "second") == "first&second")
assert(async:concat("first", "second"):evaluate() == "first&second")
ok, res = prot:concat("first", "second")
assert(ok == true)
assert(res == "first&second")

orb:shutdown()
--[Client]=====================================================================]

return template:newsuite{ corba = true, interceptedcorba = true }
