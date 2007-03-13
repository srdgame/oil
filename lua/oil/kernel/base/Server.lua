--------------------------------------------------------------------------------
------------------------------  #####      ##     ------------------------------
------------------------------ ##   ##  #  ##     ------------------------------
------------------------------ ##   ## ##  ##     ------------------------------
------------------------------ ##   ##  #  ##     ------------------------------
------------------------------  #####  ### ###### ------------------------------
--------------------------------                --------------------------------
----------------------- An Object Request Broker in Lua ------------------------
--------------------------------------------------------------------------------
-- Project: OiL - ORB in Lua: An Object Request Broker in Lua                 --
-- Release: 0.4                                                               --
-- Title  : Server-Side Broker                                                --
-- Authors: Renato Maia <maia@inf.puc-rio.br>                                 --
--------------------------------------------------------------------------------
-- broker:Facet
-- 	[configs:table], [except:table] initialize([configs:table])
-- 	servant:object object(impl:object, [objectkey:string])
-- 	reference:string tostring(servant:object)
-- 	success:boolean, [except:table] pending()
-- 	success:boolean, [except:table] step()
-- 	success:boolean, [except:table] run()
-- 	success:boolean, [except:table] shutdown()
-- 
-- objects:Receptacle
-- 	objectkey:string register(impl:object, objectkey:string)
-- 
-- acceptor:Receptacle
-- 	configs:table, [except:table] setup([configs:table])
-- 	success:boolean, [except:table] hasrequest(configs:table)
-- 	success:boolean, [except:table] acceptone(configs:table)
-- 	success:boolean, [except:table] acceptall(configs:table)
-- 	success:boolean, [except:table] halt(configs:table)
-- 
-- references:Receptacle
-- 	reference:table referenceto(objectkey:string, accesspointinfo:table...)
-- 	stringfiedref:string encode(reference:table)
--------------------------------------------------------------------------------

local getmetatable = getmetatable
local rawget       = rawget
local rawset       = rawset
local setmetatable = setmetatable
local luatostring  = tostring

local oo    = require "oil.oo"
local table = require "loop.table"                                              --[[VERBOSE]] local verbose = require "oil.verbose"

module("oil.kernel.base.Server", oo.class)

context = false

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function initialize(self, config)
	local except
	self.config, except = self.context.acceptor:setup(config)
	return self.config, except
end

function object(self, object, key)
	local context = self.context
	if not key then
		local meta = getmetatable(object)
		local backup
		if meta then
			backup = rawget(meta, "__tostring")
			if backup ~= nil then rawset(meta, "__tostring", nil) end
		end
		key = luatostring(object):match("%l+: (%w+)")
		if meta then
			if backup ~= nil then rawset(meta, "__tostring", backup) end
		end
	end
	local result, except = context.objects:register(object, key)
	if result then
		local object = result
		result, except = context.references:referenceto(key, self.config)
		if result then
			result = table.copy(result, object)
		end
	end
	return result, except
end

function tostring(self, object)
	return self.context.references:encode(object)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function pending(self)
	return self.context.acceptor:hasrequest(self.config)
end

function step(self)
	return self.context.acceptor:acceptone(self.config)
end

function run(self)
	return self.context.acceptor:acceptall(self.config)
end

function shutdown(self)
	return self.context.acceptor:halt(self.config)
end