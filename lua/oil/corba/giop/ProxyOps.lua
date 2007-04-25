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
-- Title  : Client-Side Interface Indexer                                     --
-- Authors: Renato Maia <maia@inf.puc-rio.br>                                 --
--------------------------------------------------------------------------------
-- indexer:Facet
-- 	interface:table typeof(reference:table)
-- 	member:table, [islocal:function], [cached:boolean] valueof(interface:table, name:string)
-- 
-- members:Receptacle
-- 	member:table valueof(interface:table, name:string)
-- 
-- invoker:Receptacle
-- 	[results:object], [except:table] invoke(reference:table, operation, args...)
-- 
-- types:Receptacle
-- 	[type:table] register(definition:object)
-- 	[type:table] resolve(type:string)
-- 	[type:table] lookup_id(repid:string)
--------------------------------------------------------------------------------

local type = type

local oo        = require "oil.oo"
local assert    = require "oil.assert"
local idl       = require "oil.corba.idl"
local giop      = require "oil.corba.giop"
local Indexer   = require "oil.corba.giop.Indexer"                              --[[VERBOSE]] local verbose = require "oil.verbose"

module"oil.corba.giop.ProxyOps"

oo.class(_M, Indexer)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function context(self, context)
	self.localops = {}
	
	function self.localops:_non_existent()
		local operation = giop.ObjectOperations._non_existent
		local success, result = context.invoker:invoke(self, operation)
		if success then
			success, result = success:results()
			if
				not success and
				result.exception_id == "IDL:omg.org/CORBA/OBJECT_NOT_EXIST:1.0"
			then
				success, result = true, true
			end
		elseif result.reason == "connect" or result.reason == "closed" then
			success, result = true, true
		end
		if success then
			return result
		else
			local handler = self._excepthandler
			if handler then
				return handler(self, operation, result)
			else
				assert.exception(result)
			end
		end
	end
	
	function self.localops:_narrow(iface)
		if iface == nil then
			iface = context.__component:importinterfaceof(self)
		else
			iface = assert.results(context.types:resolve(iface))
		end
		return self.__context.proxies:proxyto(self, iface)
	end
	
	self.context = context
end

function importinterfaceof(self, reference)
	local context = self.context
	local operation = giop.ObjectOperations._interface
	local success, result = context.invoker:invoke(reference, operation)
	if success then
		success, result = success:results()
		if success then
			success = context.types:lookup_id(result:_get_id()) or
			          context.types:register(result)
		end
	end
	return success or assert.exception(result)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function typeof(self, reference)
	local type = reference._type_id
	local types = self.context.types
	return type == idl.object.repID and types:resolve(idl.object) or
	       self.context.types:lookup_id(type) or
	       self:importinterfaceof(reference)
end

function valueof(self, interface, name)
	return Indexer.valueof(self, interface, name),
	       self.localops[name],
	       true
end
