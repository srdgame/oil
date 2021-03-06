-- Project: OiL - ORB in Lua
-- Release: 0.6
-- Title  : Interoperable Object Reference (IOR) support
-- Authors: Renato Maia <maia@inf.puc-rio.br>


local _G = require "_G"                                                         --[[VERBOSE]] local verbose = require "oil.verbose"
local error = _G.error
local ipairs = _G.ipairs
local pcall = _G.pcall
local setmetatable = _G.setmetatable
local tonumber = _G.tonumber

local string = require "string"
local format = string.format
local char = string.char

local oo = require "oil.oo"
local class = oo.class

local idl = require "oil.corba.idl"
local objrepID = idl.object.repID

local giop = require "oil.corba.giop"
local IOR = giop.IOR
local _interface = giop.ObjectOperations._interface

local Exception = require "oil.corba.giop.Exception"



local function byte2hexa(value)
	return (value:gsub('(.)', function (char)
		return (format("%02x", char:byte()))
	end))
end

local function hexa2byte(value)
	return (value:gsub('(%x%x)', function (hexa)
		return (char(tonumber(hexa, 16)))
	end))
end



IOR = class(IOR)

function IOR:getprofile(index)
	local profile = self.profiles[index]
	if profile then
		if profile.decoded == nil then
			profile.decoded, profile.except = self.referrer:decodeprofile(profile)
		end
		return profile
	end
end

local function iprofiles(self, index)
	index = index+1
	local profile = self:getprofile(index)
	if profile then return index, profile end
end
function IOR:allprofiles()
	return iprofiles, self, 0
end

function IOR:equivalentto(other)
	local profilers = self.referrer.profiler
	for i, profile in ipairs(self.profiles) do
		local tag = profile.tag
		local profiler = profilers[tag]
		if profiler ~= nil then
			for j, otherprof in ipairs(other.profiles) do
				if otherprof.tag == tag then
					profile = self:getprofile(i)
					otherprof = other:getprofile(j)
					profile = profile.decoded
					otherprof = otherprof.decoded
					if profile ~= nil and otherprof ~= nil
					and profiler:equivalent(profile,otherprof) then
						return true
					end
				end
			end
		end
	end
	return false
end

function IOR:islocal(address)
	for i, profile in ipairs(self.profiles) do
		local profiler = self.referrer.profiler[profile.tag]
		if profiler ~= nil then
			local decoded = self:getprofile(i).decoded
			if decoded ~= nil then
				local objkey = profiler:belongsto(decoded, address)
				if objkey ~= nil then return objkey end
			end
		end
	end
end

function IOR:gettype(timeout)
	local requester = self.referrer.requester
	if requester then                                                             --[[VERBOSE]] verbose:proxies(true, "attempt to discover interface a remote object")
		local request = requester:newrequest{reference=self,operation=_interface}
		if request then
			local ok, type = request:getreply(timeout)
			if ok then                                                                --[[VERBOSE]] verbose:proxies(false, "interface discovered")
				return type
			end                                                                       --[[VERBOSE]] verbose:proxies("discovery failed: ",type)
		end
	end                                                                           --[[VERBOSE]] verbose:proxies(false, "using interface from the IOR")
	return self.type_id
end

function IOR:__tostring()                                                       --[[VERBOSE]] verbose:references("encoding stringfied IOR")
	local encoder = self.referrer.codec:encoder(true)
	encoder:struct(self, IOR)
	return "IOR:"..byte2hexa(encoder:getdata())
end



local Referrer = class()

local function decodeIorString(self, encoded)
	local decoder = self.codec:decoder(hexa2byte(encoded), true)
	return decoder:IOR()
end
local function decodeIOR(self, encoded)
	local ok, result = pcall(decodeIorString, self, encoded)                      --[[VERBOSE]] verbose:references(false)
	if not ok then
		return nil, result
	end
	return result
end

local function decodeCorbaloc(self, encoded)
	local profiles = {}
	for token, data in encoded:gmatch("(%w*):([^,]*)") do
		if token == "" then token = "iiop" end
		local profiler = self.profiler[token]
		if profiler then
			local profile, except = profiler:decodeurl(data)
			if profile == nil then                                                    --[[VERBOSE]] verbose:references("unable to decode corbaloc URL with profile ",token,": ",except)
				return nil, except
			end
			profiles[#profiles+1] = profile
		end
	end
	if #profiles == 0 then                                                        --[[VERBOSE]] verbose:references(false, "no supported protocol found in corbaloc")
		return nil, Exception{
			"no supported protocol found in corbaloc (got $reference)",
			error = "badcorbaloc",
			reference = encoded,
		}
	end                                                                           --[[VERBOSE]] verbose:references(false)
	return IOR{
		referrer = self,
		type_id = objrepID,
		profiles = profiles,
	}
end

local function decodeCorbaname(self, encoded)
	local nsloc, name = encoded:match("^([^#]+)#(.*)")
	if nsloc ~= nil then
		local ns, except = decodeCorbaloc(self, nsloc)
		if ns ~= nil then
			error("NOT IMPLEMENTED") -- ns = orb:newproxy(ns)
			return ns:resolve_name(name)
		end
		return ns, except
	end
	return nil, Exception{
		"invalid stringfied corbaname reference (got $reference)",
		error = "badobjref",
		reference = encoded,
	}
end

local StringfiedDecoder = {
	IOR = decodeIOR,
	corbaloc = decodeCorbaloc,
	--corbaname = decodeCorbaname,
}
function Referrer:decodestring(encoded)
	local token, stream = encoded:match("^(%w+):(.+)$")
	local decoder = StringfiedDecoder[token]
	if decoder then
		return decoder(self, stream)
	end
	return nil, Exception{
		"invalid stringfied reference (got $reference)",
		error = "badobjref",
		reference = encoded,
		format = token,
	}
end

function Referrer:decodeprofile(encoded)
	local profiler = self.profiler[encoded.tag]
	if profiler == nil then
		return nil, Exception{
			"IOR profile tag not supported",
			error = "badversion",
			errmsg = "unsupported IOR profile",
			minor = 1,
			profile = encoded,
		}
	end
	return profiler:decode(encoded.profile_data)
end

function Referrer:newreference(entry, access)                                   --[[VERBOSE]] verbose:references(true, "create reference for local servant")
	local profiles = {}
	local ok, except = self.profiler[0]:encode(profiles, entry, access)--[[VERBOSE]] verbose:references(false)
	if ok == nil then return nil, except end
	return IOR{
		referrer = self,
		type_id = entry.__type.repID,
		profiles = profiles,
	}
end

return Referrer
