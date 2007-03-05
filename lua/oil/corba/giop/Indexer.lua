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
-- Release: 0.4 alpha                                                         --
-- Title  : CORBA Interface Indexer                                           --
-- Authors: Renato Maia <maia@inf.puc-rio.br>                                 --
--------------------------------------------------------------------------------
-- members:Receptacle
-- 	member:table valueof(interface:table, name:string)
--------------------------------------------------------------------------------

local oo   = require "oil.oo"
local giop = require "oil.corba.giop"                                           --[[VERBOSE]] local verbose = require "oil.verbose"

module("oil.corba.giop.Indexer", oo.class)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

context = false

function valueof(self, interface, name)
	return self.context.members:valueof(interface, name) or
	       giop.ObjectOperations[name], nil, true
end
