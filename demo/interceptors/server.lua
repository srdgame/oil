local Viewer = require "loop.debug.Viewer"
local oil = require "oil"
local socket = require "socket"

oil.main(function()
	local orb = oil.init{ flavor = "cooperative;corba.intercepted" }
	orb:loadidlfile("profiler.idl")
	
	-- create and register the server interceptor
	local ClientInfo = assert(orb.types:lookup("Profiler::ClientInfo"))
	local ServerInfo = assert(orb.types:lookup("Profiler::ServerInfo"))
	local viewer = Viewer{ maxdepth = 2 }
	local profiler = {}
	function profiler:receiverequest(request)
		request.start_time = socket.gettime()
		local params = request.parameters
		print("intercepting request to "..request.operation_name..
		      "("..viewer:tostring(table.unpack(params, 1, params.n))..")")
		local data = request.service_context[1234]
		if data ~= nil then
			local decoder = orb:newdecoder(data)
			local result = decoder:get(ServerInfo)
			print("\tmemory:", result.memory)
		else
			io.stderr:write("context 1234 not found! Canceling...\n")
			request.success = false
			request.results = {
				orb:newexcept{ "CORBA::NO_PERMISSION", minor_code_value = 0 }
			}
		end
	end
	function profiler:sendreply(reply)
		print("intercepting reply of opreation "..reply.operation_name)
		print("\tsuccess:", reply.success)
		local results = reply.results
		print("\tresults:", table.unpack(results, 1, results.n))
		local encoder = orb:newencoder()
		encoder:put({
			start = reply.start_time,
			ending = socket.gettime(),
		}, ClientInfo)
		reply.reply_service_context = { [4321] = encoder:getdata() }
	end
	orb:setinterceptor(profiler, "corba.server")
	
	-- create servant and write its reference
	local impl = { __type = "Concurrency::Server" }
	function impl:do_something_for(seconds)
		oil.sleep(seconds)
		return true
	end
	local servant = orb:newservant(impl)
	assert(oil.writeto("server.ior", servant))
end)
