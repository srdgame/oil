local Template = require "oil.dtests.Template"
local template = Template{"Client"} -- master process name

Server = [=====================================================================[
orb = oil.dtests.init{ port = 2809 }
if oil.dtests.flavor.corba then
	iface = orb:loadidl[[
		interface Terminator {
			void startup();
			void shutdown();
		};
	]]
end
orb:newservant{
	__objkey = "object",
	__type = iface,
	startup = function() done = true end,
	shutdown = function() orb:shutdown() end,
}
repeat orb:step() until done
orb:run()
--[Server]=====================================================================]

Caller = [=====================================================================[
orb = oil.dtests.init()
obj = oil.dtests.resolve("Server", 2809, "object")
obj:startup()
--[Caller]=====================================================================]

Client = [=====================================================================[
checks = oil.dtests.checks

oil.sleep(3)
orb = oil.dtests.init()
obj = oil.dtests.resolve("Server", 2809, "object")

obj:shutdown()
oil.sleep(1)

server = orb:newproxy(os.getenv("DTEST_HELPER")):getprocess("Server")
checks:assert(server, checks.is(nil))

--checks:assert(obj:_non_existent(), checks.is(true))
--[Client]=====================================================================]

return template:newsuite{ cooperative = true }