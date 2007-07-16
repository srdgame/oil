local oo        = require "oil.oo"
local Exception = require "oil.Exception"
local assert    = require "oil.assert"
local giop      = require "oil.corba.giop"                                      --[[VERBOSE]] local verbose = require "oil.verbose"

module("oil.corba.giop.Exception", oo.class)

__concat   = Exception.__concat
__tostring = Exception.__tostring

minor_code_value = 0

function __init(_, except, ...)
	local name = except[1]
	except[1] = giop.SystemExceptionIDs[name] or name
	return Exception.__init(_, except, ...)
end

assert.Exception = _M -- use GIOP exception as the default exception