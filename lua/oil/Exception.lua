local Exception = require "loop.object.Exception"
local Viewer    = require "loop.debug.Viewer"

local oo = require "oil.oo"

module("oil.Exception", oo.class)

__concat = Exception.__concat

local replaced = "%s %s"
function __tostring(self)
	local message = self.message
	self.message = message:gsub("[%a_][%w_]*", function(tag)
		local value = self[tag]
		return value and replaced:format(tag, Viewer:tostring(value))
	end)
	message, self.message = Exception.__tostring(self), message
	return message
end
