--
-- Project:  LuaIDL
-- Author:   Ricardo Cosme <rcosme@tecgraf.puc-rio.br>
-- Filename: init.lua
-- 
local _G = require "_G"
local assert  = _G.assert
local error   = _G.error
local pcall   = _G.pcall
local require = _G.require
local type    = _G.type

local io      = require "io"
local os      = require "os"
local string  = require "string"

local array   = require "table"
local unpack  = array.unpack

local _ENV = {}
if _G._VERSION=="Lua 5.1" then _G.setfenv(1,_ENV) end -- Lua 5.1 compatibility


local preprocessor  = require 'luaidl.pre'
local parser        = require 'luaidl.sin'

VERSION = '1.0.5'

---
-- Auxiliar functions
--------------------------------------------------------------------------

local function parseAux(idl, options)
  local status, output = pcall(parser.parse, idl, options)
  if status then
    return unpack(output)
  else
    return nil, output
  end
end
--------------------------------------------------------------------------


---
-- API
--------------------------------------------------------------------------

--- Preprocesses an IDL code. 
-- 
-- @param idl String with IDL code.
-- @param options (optional)Table with preprocessor options, the available keys are:
-- 'incpath', a table with include paths;
-- 'filename', the IDL filename.
-- @return String with the given IDL preprocessed.
function pre(idl, options)
  if not options then
    options = { }
  end
  return preprocessor.run(idl, options)
end

--- Preprocesses an IDL file.
-- 
-- @param filename The IDL filename.
-- @param options (optional)Table with preprocessor options, the available keys are:
-- 'incpath', a table with include paths. LuaIDL sets options.filename to filename.
-- @return String with the given IDL preprocessed.
-- @see pre
function prefile(filename, options)
  local _type = type(filename)
  if (_type ~= "string") then
    error(string.format("bad argument #1 to 'prefile' (filename expected, got %s)", _type), 2)
  end
  local fh, msg = io.open(filename)
  if not fh then
    error(msg, 2)
  end
  if not options then
    options = { }
  end
  options.filename = filename
  local str = pre(fh:read('*a'), options)
  fh:close()
  return str
end

--- Parses an IDL code.
-- 
-- @param idl String with IDL code.
-- @param options (optional)Table with parser and preprocessor options, the available keys are:
-- 'callbacks', a table of callback methods;
-- 'incpath', a table with include paths;
-- 'filename',the IDL filename.
-- @return A graph(lua table),
-- that represents an IDL definition in Lua, for each IDL definition found.
function parse(idl, options)
  idl = pre(idl, options)
  return parseAux(idl, options)
end

--- Parses an IDL file.
-- Calls the method 'prefile' with 
-- the given arguments, and so it parses the output of 'prefile'
-- calling the method 'parse'.
-- @param filename The IDL filename.
-- @param options (optional)Table with parser and preprocessor options, the available keys are:
-- 'callbacks', a table of callback methods;
-- 'incpath', a table with include paths.
-- @return A graph(lua table),
-- that represents an IDL definition in Lua, for each IDL definition found.
-- @see prefile 
-- @see parse
function parsefile(filename, options)
  local _type = type(filename)
  if (_type ~= "string") then
    error(string.format("bad argument #1 to 'parsefile' (filename expected, got %s)", _type), 2)
  end
  local stridl = prefile(filename, options)
  return parseAux(stridl, options)
end
--------------------------------------------------------------------------

return _ENV