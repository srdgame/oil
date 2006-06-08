--------------------------------------------------------------------------------
-- Project: LOOP Debugging Utilities for Lua                                  --
-- Release: 2.0 alpha                                                         --
-- Title  : Verbose/Log Mechanism for Layered Applications                    --
-- Author : Renato Maia <maia@inf.puc-rio.br>                                 --
-- Date   : 24/02/2006 14:26                                                  --
--[[----------------------------------------------------------------------------

-------------------------------------
LOG = loop.debug.Verbose{
	groups = {
		-- levels
		{"main"},
		{"counter"},
		-- aliases
		all = {"main", "counter"},
	},
}
LOG:flag("all", true)
-------------------------------------
local Counter = loop.base.class{
	value = 0,
	step = 1,
}
function Counter:add()                LOG:counter "Adding step to counter"
	self.value = self.value + self.step
end
-------------------------------------
counter = Counter()                   LOG:main "Counter object created"
steps = 10                            LOG:main(true, "Counting ",steps," steps")
for i=1, steps do counter:add() end   LOG:main(false, "Done! Counter=",counter)
-------------------------------------
--> [main]    Counter object created
--> [main]    Counting 10 steps
--> [counter] |  Adding step to counter
--> [counter] |  Adding step to counter
--> [counter] |  Adding step to counter
--> [counter] |  Adding step to counter
--> [counter] |  Adding step to counter
--> [counter] |  Adding step to counter
--> [counter] |  Adding step to counter
--> [counter] |  Adding step to counter
--> [counter] |  Adding step to counter
--> [counter] |  Adding step to counter
--> [main]    Done! Counter={ table: 0x9c3e390
-->           |  value = 10,
-->           }
----------------------------------------------------------------------------]]--

local type         = type
local rawget       = rawget
local setmetatable = setmetatable
local assert       = assert
local ipairs       = ipairs
local tostring     = tostring
local pairs        = pairs
local error        = error
local select       = select

local os        = require "os"
local math      = require "math"
local table     = require "table"
local string    = require "string"
local coroutine = require "coroutine"

local oo          = require "loop.base"
local Viewer      = require "loop.debug.Viewer"
local ObjectCache = require "loop.collection.ObjectCache"

module("loop.debug.Verbose", oo.class)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local firstcol = 8

viewer = Viewer
tabcount = ObjectCache{ default = 0 }

function __init(class, verbose)
	verbose = oo.rawnew(class, verbose)
	verbose.flags    = {}
	verbose.groups   = rawget(verbose, "groups")  or {}
	verbose.custom   = rawget(verbose, "custom")  or {}
	verbose.inspect  = rawget(verbose, "inspect") or {}
	verbose.timed    = rawget(verbose, "timed")   or {}
	verbose.viewer   = rawget(verbose, "viewer")  or Viewer{ identation = "|  " }
	return verbose
end

local function dummy() end
function __index(self, field)
	return field and ( _M[field] or self.flags[field] or dummy )
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function write(self, flag, ...)
	local count = select("#", ...)
	if count > 0 then
		local viewer  = self.viewer
		local output  = self.viewer.output
		local timed   = self.timed
		local custom  = self.custom
		local inspect = self.inspect
		
		output:write("[", flag, "]")
		output:write(viewer.prefix:sub(#flag + 3))
	
		timed = (type(timed) == "table") and timed[flag] or timed
		if timed == true then
			output:write(os.date(), " - ")
		elseif type(timed) == "string" then
			output:write(os.date(timed), " ")
		end
		
		custom = custom[flag]
		if custom == nil or custom(self, ...) then
			for i = 1, count do
				local value = select(i, ...)
				if type(value) == "string"
					then output:write(value)
					else viewer:write(value)
				end
			end
		end
	
		inspect = (type(inspect) == "table") and inspect[flag] or inspect
		if inspect == true then
			io.read()
		else
			output:write("\n")
			if type(inspect) == "function" then inspect() end
		end
	
		output:flush()
	end
end

local function taggedprint(tag)
	return function (self, start, ...)
		local running = coroutine.running()
		if rawget(self, "current") ~= running then
			self.current = running
			self:updatetabs()
		end
		if start == false then
			self:updatetabs(-1)
			write(self, tag, ...)
		elseif start == true then
			write(self, tag, ...)
			self:updatetabs(1)
		else
			write(self, tag, start, ...)
		end
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function updatetabs(self, shift)
	local current = rawget(self, "current")
	local tabcount = self.tabcount
	local viewer = self.viewer
	local tabs = tabcount[current]
	if shift then
		tabs = math.max(tabs + shift, 0)
		if current
			then tabcount[current] = tabs
			else tabcount.default = tabs
		end
	end
	viewer.prefix = string.rep(" ", firstcol)..
	                viewer.identation:rep(tabs)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function addgroup(self, name, group)
	self.groups[name] = group
end

function insertlevel(self, level, group)
	table.insert(self.groups, level, group)
end

setlevel = addgroup

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function flag(self, name, value)
	local group = self.groups[name]
	if group then
		for _, name in ipairs(group) do
			if not self:flag(name, value) then return false end
		end
	elseif value ~= nil then
		self.flags[name] = value and taggedprint(name) or nil
		local largest = 5
		for name in pairs(self.flags) do
			largest = math.max(largest, #name)
		end
		firstcol = math.max(largest + 3, firstcol)
		self:updatetabs()
	else
		return self.flags[name] ~= nil
	end
	return true
end

function level(self, value)
	if value ~= nil then
		for level = 1, #self.groups do
			self:flag(level, level <= value)
		end
	else
		for level = 1, #self.groups do
			if not self:flag(level) then return level - 1 end
		end
		return #self.groups
	end
end