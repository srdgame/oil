require "oil"

oil.loadidlfile "../hello/hello.idl"

local hello_impl = Hello.HelloWorld:new(true)
local hello = oil.newobject(hello_impl, "IDL:Hello:1.0")

oil.writeIOR(hello, "../hello/hello.ior")

oil.run()
