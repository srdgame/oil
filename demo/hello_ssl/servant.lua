local require "oil"                       -- Load OiL package

local params = {
   key = "certs/serverkey.pem",
   cert = "certs/server.pem",
   cafile = "certs/rootA.pem",
   method = "SSLv3",
   verify = {"peer", "fail_if_no_peer_cert"},
   options = {"all", "no_sslv2"},
}

oil.Config.flavor = "CORBASslSimple"
oil.Config.ssl = params
oil.verbose:level(5)
oil.init()

oil.loadidlfile("hello.idl")              -- Load the interface from IDL file

local hello = { count = 0, quiet = true } -- Get object implementation
function hello:say_hello_to(name)
	self.count = self.count + 1
	local msg = "Hello " .. name .. "! ("..self.count.." times)"
	if not self.quiet then print(msg) end
	return msg
end

hello = oil.newobject(hello, "Hello")     -- Create CORBA object

local file = io.open("hello.ior", "w")
if file then
	file:write(oil.getreference(hello))     -- Write object ref. into file
	file:close()
else
	print(oil.getreference(hello))          -- Show object ref. on screen
end
