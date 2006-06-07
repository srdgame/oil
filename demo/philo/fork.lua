local oo = require "loop.simple"

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

local scheduler = require "scheduler"
local oil       = require "oil"

oil.loadidlfile("philo.idl")
oil.writeIOR(oil.newobject(ForkHome, "ForkHome"), "fork.ior")
scheduler.new(oil.run)
scheduler.run()