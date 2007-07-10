--------------------------------------------------------------------------------
---------------------- ##       #####    #####   ######  -----------------------
---------------------- ##      ##   ##  ##   ##  ##   ## -----------------------
---------------------- ##      ##   ##  ##   ##  ######  -----------------------
---------------------- ##      ##   ##  ##   ##  ##      -----------------------
---------------------- ######   #####    #####   ##      -----------------------
----------------------                                   -----------------------
----------------------- Lua Object-Oriented Programming ------------------------
--------------------------------------------------------------------------------
-- Project: LOOP Class Library                                                --
-- Release: 2.2 alpha                                                         --
-- Title  : Command-line Argument Processor                                   --
-- Author : Renato Maia <maia@inf.puc-rio.br>                                 --
-- Date   : 2007-07-10                                                        --
--------------------------------------------------------------------------------

local select   = select
local tonumber = tonumber
local type     = type

local oo = require "loop.base"

module("loop.compiler.Arguments", oo.class)

_badnumber = "invalid value for option '-%s', number excepted but got '%s'"
_unknown = "unknown option '-%s'"
_norepeat = "option '-%s' was already defined"
_optpat = "^%-(%w+)(=?)(.-)$"
_boolean = {
	["true"] = true,
	["false"] = false,
	yes = true,
	no = false,
}

function __call(self, ...)
	local errmsg
	local defined = self._norepeat and {} or nil
	local count = select("#", ...)
	local pos = 1
	while pos <= count do
		local opt, set, val = select(pos, ...):match(self._optpat)
		if not opt then break end
		
		-- apply option alias
		local temp = self._alias
		temp = temp and temp[opt]
		opt = temp or opt
		
		-- check repeated definitions
		local kind = type(self[opt])
		if defined then
			if not defined[opt] then
				defined[opt] = true
			elseif kind ~= "table" and kind ~= "function" then
				pos, errmsg = nil, self._norepeat:format(opt)
				break
			end
		end
		
		-- process option value
		if kind == "boolean" then
			if set == "" then -- option value was not set yet, get following argument
				val = true
			else
				temp = self._boolean
				temp = temp and temp[val]
				if temp ~= nil then val = temp end
			end
			self[opt] = val
		else
			if set == "" then -- option value was not set yet, get following argument
				pos = pos + 1
				val = select(pos, ...)
			end
			
			if kind == "number" then
				local number = tonumber(val)
				if number == nil then
					pos, errmsg = nil, self._badnumber:format(opt, val)
					break
				end
				self[opt] = number
			elseif kind == "function" then
				errmsg = self[opt](self, opt, val)
				if errmsg then
					pos = nil
					break
				end
			elseif kind == "table" then
				local list = self[opt]
				list[#list+1] = val
			elseif kind == "string" or not self._unknown then
				self[opt] = val
			else
				pos, errmsg = nil, self._unknown:format(opt)
				break
			end
		end
		pos = pos + 1
	end
	return pos, errmsg
end
