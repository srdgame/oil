local oo = require "loop.simple"                                                local verbose = require "oil.verbose"

--------------------------------------------------------------------------------
-- Fork Component
--------------------------------------------------------------------------------

Fork = oo.class{ inuse = false }

function Fork:get()
	local ok = not self.inuse
	if ok then self.inuse = true end
	return ok
end

function Fork:release()
	assert(self.inuse, "attempt to release an unused fork")
	self.inuse = false
end

--------------------------------------------------------------------------------
-- Fork Home
--------------------------------------------------------------------------------

require "adaptor"

ForkHome = oo.class(nil, Adaptor)

function ForkHome:create()
	return Fork()
end

--------------------------------------------------------------------------------
-- Exporting
--------------------------------------------------------------------------------

local oil = require "oil"
oil.main(function()
	local orb = oil.init()
	orb:loadidlfile("philo.idl")
	oil.writeto("fork.ior",
		tostring(
			orb:newservant(ForkHome, nil, "ForkHome")))
end)
