local Suite = require "loop.test.Suite"
local Template = require "oil.dtests.Template"
local T = Template{"Client"} -- master process name

T.Server = [===================================================================[
checks = oil.dtests.checks

Object = {}
function Object:concat(str1, str2)
	return str1.."&"..str2
end

orb = oil.dtests.init{ port = 2809 }
orb:loadidl[[
	interface MyInterface {
		string concat(in string str1, in string str2);
	};
]]
orb:newservant(Object, "object", "::MyInterface")
orb:run()
----[Server]===================================================================]

T.Middle = [===================================================================[
checks = oil.dtests.checks

Interceptor = {}
function Interceptor:receiverequest(request)
	if request.object_key == "object" then
		request.reference = forward.__reference
	end
end

orb = oil.dtests.init{ port = 2808 }
orb:setserverinterceptor(Interceptor)
forward = oil.dtests.resolve("Server", 2809, "object")
orb:run()
----[Middle]===================================================================]

T.Client = [===================================================================[
checks = oil.dtests.checks

orb = oil.dtests.init()
sync = oil.dtests.resolve("Middle", 2808, "object")
async = orb:newproxy(sync, "asynchronous")
prot = orb:newproxy(sync, "protected")

checks:assert(sync:concat("first", "second"), checks.is("first&second"))
checks:assert(async:concat("first", "second"):evaluate(), checks.is("first&second"))
ok, res = prot:concat("first", "second")
checks:assert(ok, checks.is(true))
checks:assert(res, checks.is("first&second"))
----[Client]===================================================================]

return T:newsuite{ corba = true, interceptedcorba = true }
