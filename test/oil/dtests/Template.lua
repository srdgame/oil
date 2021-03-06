local _G = require "_G"
local assert   = _G.assert
local error    = _G.error
local ipairs   = _G.ipairs
local pairs    = _G.pairs
local rawget   = _G.rawget
local setfenv  = _G.setfenv
local tonumber = _G.tonumber
local tostring = _G.tostring
local type     = _G.type

local coroutine = require "coroutine"
local math      = require "math"
local os        = require "os"
local string    = require "string"
local table     = require "table"

local oo    = require "loop.base"
local oil   = require "oil"
local utils = require "dtest.run.utils"

local Suite = require "loop.test.Suite"

module("oil.dtests.Template", oo.class)

local sockets = oil.BasicSystem.sockets
local helper = utils.helper

local OIL_HOME = assert(os.getenv("OIL_HOME"), "OIL_HOME environment variable not defined")
local PortLowerBound = 2809 -- inclusive (never at first attempt)
local PortUpperBound = 9999 -- inclusive
local Message = "%s\n%d\n%s\n"
local TableEntry = "[%q]=%q"
local CodeBody = table.concat({
	"require 'oil.dtests.%s'",
	"oil.dtests.setup(%q, {%s}, ...)",
	"oil.main(function(...) %s\nend)",
}, ";")

local Command = oo.class{
	execpath = OIL_HOME.."/test/",
	input = "",
	output = "",
	requirements = {},
	flavor = "cooperative;corba",
}

local Packages = { {"corba"}, {"ludo"} }
local function getpackage(flavor)
	for _, names in pairs(Packages) do
		local found = true
		for _, name in ipairs(names) do
			if not flavor:find(name, 1, true) then
				found = false
				break
			end
		end
		if found then return table.concat(names) end
	end
	error("no oil.dtests package available for flavor "..flavor)
end

function __init(self, object)
	self = oo.rawnew(self, object)
	setfenv(3, self)
	return self
end

local EnvironmentVariables = {
	"PATH",
	"LUA_PATH",
	"LUA_CPATH",
	"LD_LIBRARY_PATH",
	"DYLD_LIBRARY_PATH",
}
local Empty = {}
function newtest(self, infos)
	if not infos then infos = Empty end
	return function(checks)
		repeat
			local sock = sockets:tcp()
			local ok, errmsg = sock:bind("*", 2809)
			if ok or errmsg ~= "address already in use" then
				assert(sock:close())
				break
			end
			oil.sleep(1)
		until false

		-- find a free port
		local first = PortLowerBound + math.random(PortUpperBound - PortLowerBound)
		local portno = first
		local port, errmsg
		repeat
			port, errmsg = sockets:tcp()
			if port:bind("*", portno) and port:listen() then break end
			if portno >= PortUpperBound
				then portno = PortLowerBound
				else portno = portno + 1
			end
			if portno == first then error("unable to find an available port") end	
		until false
		port:settimeout(10)
		local hostname = sockets.dns.gethostname()
		
		-- create processes
		local Master
		local Processes = {}
		local HostTable = {}
		local Environment = {}
		for index, name in ipairs(EnvironmentVariables) do
			local value = os.getenv(name)
			if value ~= nil then
				Environment[#Environment+1] = {
					name = name,
					value = value,
				}
			end
		end
		for name, code in pairs(self) do
			if type(name) == "string" then
				local command = Command(infos[name])
				command.id = name
				command.command = "lua"
				command.arguments = {
					--"-lcompat52",
					"-eHOST=[["..hostname.."]]PORT="..portno,
					"-loil.dtests.LuaProcess",
				}
				command.environment = Environment
				local process = helper:start(command)
				HostTable[#HostTable+1] = TableEntry:format(name, process:_get_host())
				Processes[name] = {
					command = command,
					process = process,
					connection = assert(port:accept()),
					code = code,
				}
			end
		end
		
		-- start processes
		for name, info in pairs(Processes) do
			local code = CodeBody:format(
				getpackage(info.command.flavor),
				info.command.flavor,
				table.concat(HostTable, ","),
				info.code
			)
			assert(info.connection:send(Message:format(name, #code, code)))
			if name == self[1] then
				Master = info.connection
			end
		end
		
		-- get master results
		local success = assert(Master:receive())
		local size = assert(tonumber(assert(Master:receive())))
		local result = assert(Master:receive(size))
		Master:close()
		
		-- kill all processes
		for name, info in pairs(Processes) do
			info.process:halt()
		end
		
		-- wait processes to be killed
		oil.sleep(1)
		
		-- get results from other processes
		result = { result }
		local function remains(conn, size)
			local result, error, partial = conn:receive(size)
			if result == nil and error == "timeout" then
				result = partial
			end
			if result and #result > 0 then
				return result
			end
		end
		for name, info in pairs(Processes) do
			if name ~= self[1] then
				local conn = info.connection
				conn:settimeout(0)
				local received = remains(conn)
				if received then
					result[#result+1] = "\n"
					result[#result+1] = name
					result[#result+1] = " ("
					result[#result+1] = received
					result[#result+1] = "): "
					received = remains(conn)
					if received then
						received = tonumber(received)
						if received then
							received = remains(conn, received)
							if received then
								result[#result+1] = received
							end
						end
					end
				end
				conn:close()
			end
		end
		result[#result+1] = "\n\n"
		result = table.concat(result)
		
		-- report results
		if success == "protocol" then
			error("LuaProcess: "..result)
		elseif success == "failure" then
			checks:fail(result)
		elseif success ~= "success" then
			error(result)
		end
	end
end
--------------------------------------------------------------------------------
-- Full Suite Generation
--
local nestedlist = oo.class()
function nestedlist:__tostring()
	local result = {}
	for _, value in ipairs(self) do
		value = tostring(value)
		if value ~= "" then
			result[#result+1] = value
		end
	end
	return table.concat(result, ";")
end

local function seqnext(self, sequence, index)
	index = index or 1
	sequence = nestedlist(sequence)
	for current in self[index]:combinations() do
		sequence[index] = current
		if index < #self
			then seqnext(self, sequence, index+1)
			else coroutine.yield(sequence)
		end
	end
end

local function altnext(self, prev, index)
	index = index or 1
	for current in self[index]:combinations() do
		coroutine.yield(current)
	end
	if index < #self then return altnext(self, prev, index+1) end
end
--------------------------------------------------------------------------------
function strnext(self, prev)
	if prev == nil then return self end
end
function string:combinations()
	return strnext, self
end

local seq = oo.class()
function seq:combinations()
	return coroutine.wrap(seqnext), self
end

local alt = oo.class()
function alt:combinations()
	return coroutine.wrap(altnext), self
end
--------------------------------------------------------------------------------
--[intercepted?;gencode?;corba;typed|ludo];cooperative?;base

local Names = {
	gencode = "Gen",
	cooperative = "Co",
	["corba.intercepted"] = "IceptGIOP",
	["corba.ssl"] = "SSL",
	corba = "CORBA",
	ludo = "LuDO",
}
local Tags = {
	"gencode",
	"cooperative",
	"corba.intercepted",
	"corba.ssl",
	"corba",
	"ludo",
}
local function findtag(flavor, tag)
	for _, flavor in ipairs(flavor) do
		if flavor == tag then return true end
	end
	return false
end
local function getname(cltflavor, srvflavor)
	local client, server, common = {}, {}, {}
	for _, tag in ipairs(Tags) do
		if srvflavor:find(tag, nil, true) then
			if cltflavor:find(tag, nil, true) then
				common[#common+1] = Names[tag]
			else
				server[#server+1] = Names[tag]
			end
		elseif cltflavor:find(tag, nil, true) then
			client[#client+1] = Names[tag]
		end
	end
	if #client > 0 then client[#client+1] = "Client" end
	if #server > 0 then server[#server+1] = "Server" end
	return table.concat(client)..
	       table.concat(server)..
	       table.concat(common)
end

function newsuite(self, required)
	required = required or {}
	local ludo = "ludo"
	local corba = seq{
		""; --alt{"corba.gencode", ""};
		alt{"corba.intercepted", "corba"};
		--alt{"kernel.ssl;corba.ssl", ""};
	}
	local flavors = seq{
		"";
		alt{"cooperative", ""};
	};
	local protocols = {
		[ludo] = true,
		[corba] = true,
	}
	if required.gencode          then corba[1][2]      = nil end
	if required.interceptedcorba then corba[2][2]      = nil end
	if required.cooperative      then flavors[2][2]    = nil end
	if rawget(required, "ludo")  then protocols[corba] = nil end
	if rawget(required, "corba") then protocols[ludo]  = nil end
	local suite = Suite()
	
	---[=[
	
	for protocol in pairs(protocols) do
		flavors[1] = protocol
		for client in flavors:combinations() do
			for server in flavors:combinations() do
				client = tostring(client)
				server = tostring(server)
				if (client:find("cooperative", 1, true) or not client:find("corba.ssl", 1, true))
				and (server:find("cooperative", 1, true) or not server:find("corba.ssl", 1, true))
				then
					local config = {
						Client = { flavor = client },
						Server = { flavor = server },
					}
					for name in pairs(self) do
						if config[name] == nil then
							config[name] = config.Server
						end
					end
					suite[getname(client, server)] = self:newtest(config)
				end
			end
		end
	end
	
	--[[]=]
	local client = "cooperative;corba.intercepted;corba.ssl;kernel.ssl"
	local server = "cooperative;corba.intercepted;corba.ssl;kernel.ssl"
	local config = {
		Client = { flavor = client },
		Server = { flavor = server },
	}
	for name in pairs(self) do
		if config[name] == nil then
			config[name] = config.Server
		end
	end
	suite[getname(client, server)] = self:newtest(config)
	--]]
	
	return suite
end
