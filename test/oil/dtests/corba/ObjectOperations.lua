local Suite = require "loop.test.Suite"
local Template = require "oil.dtests.Template"
local template = Template{"Client"} -- master process name

Server = [=====================================================================[
orb = oil.dtests.init{ port = 2809 }
orb:newservant{ __type = "::CORBA::InterfaceDef", __objkey = "object" }
orb:run()
--[Server]=====================================================================]

Client = [=====================================================================[
orb = oil.dtests.init()
checks = oil.dtests.checks
object = oil.dtests.resolve("Server", 2809, "object", nil, false, true)
inexistent = oil.dtests.resolve("Server", 2809, "inexistent", nil, true, true)
fake = oil.dtests.resolve("_", 0, "", nil, true, true)

cases = {
	_interface = {
		[object] = checks.like{
			__type = "IDL:omg.org/CORBA/InterfaceDef:1.0",
			__reference = {
				type_id = "IDL:omg.org/CORBA/InterfaceDef:1.0",
				profiles = { { tag = 0 } },
			},
		},
	},
	_component = {
		[object] = checks.is(nil),
	},
	_is_a = { "IDL:omg.org/CORBA/InterfaceDef:1.0",
		[object] = checks.is(true),
	},
	_non_existent = {
		[object] = checks.is(false),
		[inexistent] = checks.is(true),
	},
	_is_equivalent = { object,
		[object] = checks.is(true),
		[fake] = checks.is(false),
	},
}

for opname, opdesc in pairs(cases) do
	for proxy, checker in pairs(opdesc) do
		if proxy ~= 1 then
			-- synchronous call
			result = proxy[opname](proxy, table.unpack(opdesc))
			checks.assert(result, checker)
			
			-- asynchronous call
			async = orb:newproxy(proxy, "asynchronous", proxy.__type)
			future = async[opname](async, table.unpack(opdesc))
			ok, result = future:results()
			assert(ok == true, "operation results indicated a unexpected error.")
			checks.assert(result, checker)
			checks.assert(future:evaluate(), checker)
			
			-- protected synchronous call
			prot = orb:newproxy(proxy, "protected", proxy.__type)
			ok, result = prot[opname](prot, table.unpack(opdesc))
			assert(ok == true, "operation results indicated a unexpected error.")
			checks.assert(result, checker)
		end
	end
end

orb:shutdown()
--[Client]=====================================================================]

return template:newsuite{ corba = true }
