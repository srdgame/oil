local Suite = require "loop.test.Suite"
local Template = require "oil.dtests.Template"
local template = Template{"Client"} -- master process name

Server = [=====================================================================[
checks = oil.dtests.checks

Interceptor = {}
function Interceptor:receiverequest(request)
	if request.object_key == "object"
	and request.operation_name == "concat"
	then
		request.success = false
		request.results = { orb:newexcept{
			"CORBA::NO_PERMISSION",
			completed = "COMPLETED_NO",
			minor = 321,
		} }
	end
end
function Interceptor:sendreply(request)
	if request.object_key == "object"
	and request.operation_name == "concat"
	then
		assert(request.success == false)
		checks.assert(request.results[1], checks.like{
		              	_repid = "IDL:omg.org/CORBA/NO_PERMISSION:1.0",
		              	completed = "COMPLETED_NO",
		              	minor = 321,
		              })
		request.results[1].minor = 123
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
checks = oil.dtests.checks

orb = oil.dtests.init()
sync = oil.dtests.resolve("Server", 2809, "object")
async = orb:newproxy(sync, "asynchronous")
prot = orb:newproxy(sync, "protected")

ok, res = pcall(sync.concat, sync, "first", "second")
assert(ok == false)
checks.assert(res, checks.like{
                   	_repid = "IDL:omg.org/CORBA/NO_PERMISSION:1.0",
                   	completed = "COMPLETED_NO",
                   	minor = 123,
                   })

ok, res = async:concat("first", "second"):results()
assert(ok == false)
checks.assert(res, checks.like{
                   	_repid = "IDL:omg.org/CORBA/NO_PERMISSION:1.0",
                   	completed = "COMPLETED_NO",
                   	minor = 123,
                   })

ok, res = prot:concat("first", "second")
assert(ok == false)
checks.assert(res, checks.like{
                   	_repid = "IDL:omg.org/CORBA/NO_PERMISSION:1.0",
                   	completed = "COMPLETED_NO",
                   	minor = 123,
                   })

orb:shutdown()
--[Client]=====================================================================]

return template:newsuite{ corba = true, interceptedcorba = true }
