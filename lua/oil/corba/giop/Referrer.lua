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
-- Title  : Interoperable Object Reference (IOR) support                      --
-- Authors: Renato Maia <maia@inf.puc-rio.br>                                 --
--------------------------------------------------------------------------------
-- Notes:                                                                     --
--   See section 13.6 of CORBA 3.0 specification.                             --
--   See section 13.6.10 of CORBA 3.0 specification for corbaloc.             --
--------------------------------------------------------------------------------
-- references:Facet
-- 	reference:table newreference(objectkey:string, accesspointinfo:table...)
-- 	reference:string encode(reference:table)
-- 	reference:table decode(reference:string)
-- 
-- codec:Receptacle
-- 	encoder:object encoder()
-- 	decoder:object decoder(stream:string)
-- 
-- profiler:HashReceptacle
-- 	profile:table decodeurl(url:string)
-- 	data:string encode(objectkey:string, acceptorinfo...)
-- 
-- types:Receptacle--[[
-- 	interface:table typeof(objectkey:string)
--------------------------------------------------------------------------------

local select       = select
local setmetatable = setmetatable
local tonumber     = tonumber

local string = require "string"

local oo        = require "oil.oo"
local idl       = require "oil.corba.idl"
local giop      = require "oil.corba.giop"
local Exception = require "oil.corba.giop.Exception"                            --[[VERBOSE]] local verbose = require "oil.verbose"

module("oil.corba.giop.Referrer", oo.class)

context = false

--------------------------------------------------------------------------------
-- String/byte conversions -----------------------------------------------------

local function byte2hexa(value)
	return (string.gsub(value, '(.)', function (char)
		-- TODO:[maia] check char to byte conversion
		return (string.format("%02x", string.byte(char)))
	end))
end

local function hexa2byte(value)
	local error
	value = (string.gsub(value, '(%x%x)', function (hexa)
		hexa = tonumber(hexa, 16)
		if hexa
			-- TODO:[maia] check byte to char conversion
			then return string.char(hexa)
			else error = true
		end
	end))
	if not error then return value end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function IOR(self, stream)
	local decoder = self.context.codec:decoder(hexa2byte(stream), true)
	return decoder:struct(giop.IOR)
end

function corbaloc(self, encoded)
	for token, data in string.gmatch(encoded, "(%w*):([^,]*)") do
		local profiler = self.context.profiler[token]
		if profiler then
			local profile, except = profiler:decodeurl(data)
			if profile then
				return setmetatable({
					type_id = idl.object.repID,
					profiles = { profile },
				}, giop.IOR)
			else
				return nil, except
			end
		end
	end
	return nil, Exception{ "INV_OBJREF",
		reason = "corbaloc",
		message = "corbaloc, no supported protocol found",
		reference = encoded,
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function newreference(self, objectkey, ...)
	local profiles = {}
	for i = 1, select("#", ...) do
		local acceptor = select(i, ...)
		local tag = acceptor.tag or 0
		local profiler = self.context.profiler[tag]
		if profiler then
			local ok, except = profiler:encode(profiles, objectkey, acceptor)
			if not ok then return nil, except end
		else
			return nil, Exception{ "IMP_LIMIT", minor_code_value = 1,
				message = "GIOP profile tag not supported",
				reason = "profiles",
				tag = tag,
			}
		end
	end
	local type = select(2, self.context.servants:retrieve(objectkey))
	if type then
		return setmetatable({
			type_id = type.repID,
			profiles = profiles,
		}, giop.IOR)
	else
		-- TODO:[maia] Is this the right exception?
		return nil, Exception{ "OBJECT_NOT_EXIST",
			reason = "objectkey",
			message = "illegal object key",
			objectkey = objectkey,
		}
	end
end

local _interface = giop.ObjectOperations._interface
function typeof(self, reference)
	local context = self.context
	local requester = context.requester
	local result, except = requester:newrequest(reference, _interface)
	if result then
		local request = result
		result, except = requester:getreply(request)
		if result then
			result, except = request:contents()
			if result then
				result = except
			end
		end
	end
	return result, except
end

--------------------------------------------------------------------------------
-- Coding ----------------------------------------------------------------------

function encode(self, ior)
	local encoder = self.context.codec:encoder(true)
	encoder:struct(ior, giop.IOR)
	return "IOR:"..byte2hexa(encoder:getdata())
end

function decode(self, encoded)
	local token, stream = encoded:match("^(%w+):(.+)$")
	local decoder = self[token]
	if not decoder then
		return nil, Exception{ "INV_OBJREF",
			reason = "reference",
			message = "illegal reference format, currently not supported",
			format = token,
			reference = enconded,
		}
	end
	return decoder(self, stream)
end
