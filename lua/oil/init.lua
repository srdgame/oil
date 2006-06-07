-- $Id$
--******************************************************************************
-- Copyright 2002 Noemi Rodriquez & Roberto Ierusalimschy. All rights reserved. 
--******************************************************************************

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
-- Release: 0.3 alpha                                                         --
-- Title  : OiL main programming interface (API)                              --
-- Authors: Renato Maia           <maia@inf.puc-rio.br>                       --
--------------------------------------------------------------------------------
-- Interface:                                                                 --
--   loadidl(code)                                                            --
--   loadidlfile(path, pre)                                                   --
--                                                                            --
--   getLIR()                                                                 --
--   getIR()                                                                  --
--   setIR(ir)                                                                --
--                                                                            --
--   newobject(obj, iface, key)                                               --
--   newproxy(obj, iface)                                                     --
--   narrow(proxy, iface)                                                     --
--                                                                            --
--   init()                                                                   --
--   pending()                                                                --
--   step()                                                                   --
--   run()                                                                    --
--------------------------------------------------------------------------------
-- Notes:                                                                     --
--------------------------------------------------------------------------------

local type     = type
local pairs    = pairs
local ipairs   = ipairs
local tostring = tostring
local require  = require
local rawset   = rawset

local io = require "io"

--------------------------------------------------------------------------------
-- OiL main programming interface (API).

-- This API provides access to the basic functionalities of the OiL ORB.
-- More advanced features may be accessed through more speciatialized interfaces
-- that currently are only supported as part of the internal implementation and
-- therefore may change in the future.

module "oil"

--------------------------------------------------------------------------------
-- Dependencies ----------------------------------------------------------------

local luaidl     = require "luaidl"
local idl        = require "oil.idl"
local idlparser  = require "oil.idl.compiler"
local assert     = require "oil.assert"
local ior        = require "oil.ior"
local proxy      = require "oil.proxy"
local orb        = require "oil.orb"
                   require "oil.iiop"
local manager    = require "oil.ir"
local iridl      = require "oil.ir.idl"

--------------------------------------------------------------------------------
-- Local module variables and functions ----------------------------------------

Manager = manager.new()

Manager:putiface(iridl.Repository             )
Manager:putiface(iridl.Container              )
Manager:putiface(iridl.ModuleDef              )
Manager:putiface(iridl.ConstantDef            )
Manager:putiface(iridl.IDLType                )
Manager:putiface(iridl.StructDef              )
Manager:putiface(iridl.UnionDef               )
Manager:putiface(iridl.EnumDef                )
Manager:putiface(iridl.AliasDef               )
Manager:putiface(iridl.InterfaceDef           )
Manager:putiface(iridl.ExceptionDef           )
Manager:putiface(iridl.NativeDef              )
Manager:putiface(iridl.ValueDef               )
Manager:putiface(iridl.ValueBoxDef            )
Manager:putiface(iridl.AbstractInterfaceDef   )
Manager:putiface(iridl.LocalInterfaceDef      )
Manager:putiface(iridl.ExtInterfaceDef        )
Manager:putiface(iridl.ExtValueDef            )
Manager:putiface(iridl.ExtAbstractInterfaceDef)
Manager:putiface(iridl.ExtLocalInterfaceDef   )
Manager:putiface(iridl.PrimitiveDef           )
Manager:putiface(iridl.StringDef              )
Manager:putiface(iridl.SequenceDef            )
Manager:putiface(iridl.ArrayDef               )
Manager:putiface(iridl.WstringDef             )
Manager:putiface(iridl.FixedDef               )
Manager:putiface(iridl.TypedefDef             )
Manager:putiface(iridl.AttributeDef           )
Manager:putiface(iridl.ExtAttributeDef        )
Manager:putiface(iridl.OperationDef           )
Manager:putiface(iridl.InterfaceAttrExtension )
Manager:putiface(iridl.ValueMemberDef         )

--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- Default configuration for creation of the default ORB instance.

-- The configuration values may differ accordingly to the IOP protocol.
-- For Internet IOP (IIOP) protocol the current options are the host name or IP
-- address and port that ORB must bind to, as well as the host name or IP
-- address and port that must be used in creation of object references.

-- @field protocoltag number Tag of the protocol the ORB shall use. Default is
-- tag 0, that indicates IIOP. (must be set before registration of any servant).
-- @field host string Host name or IP address (must be set before registration
-- of any servant).
-- @field host string Host name or IP address (must be set before registration
-- of any servant).
-- @field port number Port the ORB must listen (must be set before registration
-- of any servant).
-- @field iorhost string Host name or IP address informed in object references
-- (must be set before registration of any servant).
-- @field iorport number Port informed in object references (must be set before
-- registration of any servant).

-- @usage oil.Config.host = "middleware.inf.puc-rio.br"                        .
-- @usage oil.Config.host = "10.223.10.56"                                     .
-- @usage oil.Config.port = 8080                                               .
-- @usage oil.Config = {host = "10.223.10.56", port = 8080 }                   .

-- @see init

Config = {}

--------------------------------------------------------------------------------
-- Loads an IDL code strip into the local Interface Repository.

-- @param idlspec string The IDL code strip to be loaded into the local IR.

-- @usage oil.loadidl [[
--          interface Hello {
--            attribute boolean quiet;
--            readonly attribute unsigned long count;
--            string say_hello_to(in string msg);
--          };
--        ]]                                                                   .

function loadidl(idlspec)
  return idlparser.parse(idlspec,Manager)
end

--------------------------------------------------------------------------------
-- Loads an IDL file into the local Interface Repository.

-- The file specified will be optionally preprocessed by a command-line C++ pre-
-- processor prior to process directives like #include, #define, #ifdef and the
-- like.
-- The pre-processing is activated by parameter preprocess. 
-- In this case a new file is created in the path defined by the preprocess
-- parameter.

-- @param filename string The path to the IDL file that must be loaded.
-- @param preprocessed string [optional] Path to a temporary file used to store
-- the preprocessed data.

-- @usage oil.loadidlfile "/usr/local/corba/idl/CosNaming.idl"                 .
-- @usage oil.loadidlfile("HelloWorld.idl", "/tmp/preprocessed.idl")           .

function loadidlfile(filename, preprocessed)
  return idlparser.parsefile(filename,Manager)
end

--------------------------------------------------------------------------------
-- Get the local Interface Repository that exports local cached definitions.

-- @return 1 proxy CORBA object that exports the local Interface Repository.

local LocalIR
function getLIR()
	if not LocalIR then
		LocalIR = init():object(Manager, "IDL:omg.org/CORBA/Repository:1.0")
	end
	return LocalIR
end

--------------------------------------------------------------------------------
-- Get the remote Interface Repository used to retrieve interface definitions.

-- @return 1 proxy Proxy for the remote IR currently used.

function getIR()
	return Manager.ir
end

--------------------------------------------------------------------------------
-- Defines a remote Interface Repository used to retrieve interface definitions.

-- @param ir proxy Proxy for the remote IR to be used.

-- @usage oil.setIR(oil.newproxy("corbaloc::cos_host/InterfaceRepository",
--                               "IDL:omg.org/CORBA/Repository:1.0"))          .

function setIR(ir)
	Manager.ir = ir
end

--------------------------------------------------------------------------------
-- Creates a new CORBA object implemented in Lua that supports some interface.

-- The value of object is used as the servant of a CORBA object that supports
-- the interface with repID (Interface Repository ID) defined in 'interface'.
-- Optionally, an object key value may be specified to create persistent
-- references.
-- The CORBA object returned by this function offers all servant attributes and
-- methods, as well as CORBA::Object basic operations like _ior().

-- @param object table Value used as the object servant (may be an indexable
-- value, e.g. userdata with a metatable that defined the __index field).
-- @param interface string Interface Repository ID or absolute name of the
-- interface the object supports.
-- @param key string [optional] User-defined object key used in creation of the
-- object reference.

-- @return table CORBA object created.

-- @usage oil.newobject({say_hello_to=print},"IDL:HelloWorld/Hello:1.0")       .
-- @usage oil.newobject({say_hello_to=print},"IDL:HelloWorld/Hello:1.0", "Key").

function newobject(object, interface, key)
	if type(interface) == "string" then
		if Manager.lookup then
			interface = Manager:lookup(interface) or interface
		end
	end
	return init():object(object, interface, key)
end

--------------------------------------------------------------------------------
-- Creates a proxy for a CORBA object defined by an IOR (Inter-operable Object
-- Reference).

-- The value of object must be a string containing the IOR of the object the new
-- new proxy will represent.
-- Optionally, an interface supported by the CORBA object may be defined, in
-- this case no attempt is made to determine the actual object interface, i.e.
-- no network communication is made to check the object's interface.

-- @param object string Representation of Inter-operable Object Reference of the
-- object the new proxy will represent.
-- @param interface string [optional] Repository Interface ID or absolute name
-- of a interface the CORBA object supports (no interface or type check done).

-- @return table Proxy to the CORBA object.

-- @usage oil.newproxy("IOR:00000002B494...")                                  .
-- @usage oil.newproxy("IOR:00000002B494...", "HelloWorld::Hello")             .
-- @usage oil.newproxy("IOR:00000002B494...", "IDL:HelloWorld/Hello:1.0")      .
-- @usage oil.newproxy("corbaloc::host:8080/Key", "IDL:HelloWorld/Hello:1.0")  .

function newproxy(object, interface)
	object = ior.decode(object)
	if not interface then
		interface = object._type_id
	end
	
	local class = Manager:getclass(interface)
	if not class then
		if Manager.lookup then
			interface = Manager:lookup(interface)
			if interface then
				class = Manager:getclass(interface.repID)
			end
		end
		if not class then
			object = Manager:getclass("IDL:omg.org/CORBA/Object:1.0")(object)
			object = object:_narrow()
		end
	end
	if class then object = class(object) end

	rawset(object, "_orb", init())
	
	return object
end

--------------------------------------------------------------------------------
-- Narrow an object reference into some more specific interface supported by the
-- CORBA object.

-- The object reference is defined as a proxy object.
-- If you wish to create a proxy to an object specified by an IOR that must be
-- created already narrowed into some interface, use newproxy function.
-- The interface the object reference must be narrowed into is defined by the
-- Interface Repository ID stored in parameter 'interface'.
-- If no interface is defined, then the object reference is narrowed to the most
-- specific interface supported by the COBRA object.
-- Note that in the former case, no attempt is made to determine the actual
-- object interface, i.e. no network communication is made to check the object's
-- interface.

-- @param proxy table Proxy that represents the CORBA object which reference
-- must be narrowed.
-- @param interface string [optional] Repository Interface ID of the interface
-- the object reference must be narrowed into (no interface or type check is
-- made).

-- @return table New proxy to the CORBA object narrowed into some interface
-- supported by the CORBA object.

-- @usage oil.narrow(ns:resolve_str("HelloWorld"))                             .
-- @usage oil.narrow(ns:resolve_str("HelloWorld"), "IDL:HelloWorld/Hello:1.0") .

-- @see newproxy

function narrow(proxy, interface)
	if proxy then
		if type(interface) == "string" then
			if Manager.lookup then
				interface = Manager:lookup(interface) or interface
			end
		end
		return proxy:_narrow(interface)
	end
end

--------------------------------------------------------------------------------
-- Initialize the OiL main ORB.

-- Initialize the default ORB instance with the provided configurations. The
-- configuration values may differ accordingly to the IOP protocol.
-- For Internet IOP (IIOP) protocol the current options are the host name or IP
-- address and port that ORB must bind to, as well as the host name or IP
-- address and port that must be used in creation of object references.
-- If the default ORB already is created then this instance is returned.
-- This default ORB is used by all objects and proxies created by newobject and
-- newproxy functions.

-- @param config table Configurations used to create the default ORB instance.

-- @usage oil.init()                                                           .
-- @usage oil.init{ host = "middleware.inf.puc-rio.br" }                       .
-- @usage oil.init{ host = "10.223.10.56", port = 8080 }                       .

-- @see Config

function init(config)
	if not MainORB then
		local except
		if not config then config = Config end
		if config.manager
			then Manager = config.manager
			else config.manager = Manager
		end
		MainORB, except = orb.init(config or Config)
		if not MainORB then assert.error(except) end
	end
	return MainORB
end

--------------------------------------------------------------------------------
-- Checks whether there is some request pending

-- Returns true if there is some ORB request pending or false otherwise.

function pending()
	return init():workpending()
end

--------------------------------------------------------------------------------
-- Waits for an ORB request and process it.

-- Process one single ORB request at each call. Returns true if success or nil
-- and an exception.

function step()
	return init():performwork()
end

--------------------------------------------------------------------------------
-- Runs the ORB main loop.

-- Requests the ORB to process remote CORBA requisitions repeatedly until some
-- error occours.

function run()
	return init():run()
end

--------------------------------------------------------------------------------
-- Alias of 'newobject' function.

-- For compatibility with LuaOrb applications.

-- @see newobject

createservant = newobject

--------------------------------------------------------------------------------
-- Alias of 'newproxy' function.

-- For compatibility with LuaOrb applications.

-- @see newproxy

createproxy = newproxy

--------------------------------------------------------------------------------
-- Creates a file with the IOR of an object.

-- Utility function for writing stringfied IORs into a file.

function writeIOR(object, file)
	file = io.open(file, "w")
	if file then
		file:write(object:_ior())
		file:close()
		return true
	end
	return nil, "unable to write file"
end

--------------------------------------------------------------------------------
-- Read the contents of a file.

-- Utility function for reading stringfied IORs from a file.

function readIOR(filename)
	local file = io.open(filename)
	if file then
		local ior = file:read("*a")
		file:close()
		return ior
	end
	return nil, "unable to read file"
end