local Viewer = require "loop.debug.Viewer"
local oil = require "oil"

if select("#", ...) == 0 then
	io.stderr:write "usage: lua client.lua <time of client 1>, <time of client 2>, ..."
	os.exit(-1)
end
local arg = {...}

oil.main(function()
	local orb = oil.init{ flavor = "cooperative;corba.intercepted" }
	orb:loadidlfile("profiler.idl")
	
	local ClientInfo = assert(orb.types:lookup("Profiler::ClientInfo"))
	local ServerInfo = assert(orb.types:lookup("Profiler::ServerInfo"))
	local viewer = Viewer{ maxdepth = 2 }
	local profiler = {}
	function profiler:sendrequest(request)
		local params = request.parameters
		print("intercepting request to "..request.operation_name..
		      "("..viewer:tostring(table.unpack(params, 1, params.n))..")")
		local encoder = orb:newencoder()
		encoder:put({
			memory = collectgarbage("count"),
		}, ServerInfo)
		request.service_context = { [1234] = encoder:getdata() }
	end
	function profiler:receivereply(request)
		print("intercepting reply of opreation "..request.operation_name)
		print("\tsuccess:", request.success)
		local results = request.results
		print("\tresults:", table.unpack(results, 1, results.n))
		local data = request.reply_service_context[4321]
		if data ~= nil then
			local decoder = orb:newdecoder(data)
			local result = decoder:get(ClientInfo)
			print("\ttime:", result.ending - result.start)
		else
			io.stderr:write("context 4321 not found! Canceling ...\n")
			request.success = false
			request.results = {
				orb:newexcept{ "NoProfiling", -- local exception, unknown to CORBA
					operation = operation
				}
			}
		end
	end
	orb:setinterceptor(profiler, "corba.client")
	
	local server = orb:newproxy(assert(oil.readfrom("server.ior")))
	local function showprogress(id, time)
		print(id, "about to request work for "..time.." seconds")
		if server:do_something_for(time)
			then print(id, "result received successfully")
			else print(id, "got an unexpected result")
		end
	end
	for id, time in ipairs(arg) do
		oil.newthread(showprogress, id, tonumber(time))
	end

	orb:shutdown()
end)
