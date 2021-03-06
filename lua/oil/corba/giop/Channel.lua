-- Project: OiL - ORB in Lua
-- Release: 0.6
-- Title  : Marshaling of CORBA GIOP Protocol Messages
-- Authors: Renato Maia <maia@inf.puc-rio.br>


local _G = require "_G"                                                       --[[VERBOSE]] local verbose = require "oil.verbose"
local assert = _G.assert
local error = _G.error
local ipairs = _G.ipairs
local next = _G.next
local pairs = _G.pairs
local pcall = _G.pcall
local setmetatable = _G.setmetatable
local type = _G.type

local coroutine = require "coroutine"
local running = coroutine.running

local math = require "math"
local floor = math.floor

local struct = require "struct"
local littleendian = (struct.unpack("B", struct.pack("I2", 1)) == 1)

local Queue = require "loop.collection.Queue"

local Mutex = require "cothread.Mutex"

local oo = require "oil.oo"
local class = oo.class

local idl = require "oil.corba.idl"

local giop = require "oil.corba.giop"                                         --[[VERBOSE]] local MessageType = giop.MessageType
local MagicTag = giop.MagicTag
local HeaderSize = giop.HeaderSize
local GIOPHeader_v1_ = giop.Header_v1_
local MessageHeader_v1_ = giop.MessageHeader_v1_
local RequestID = giop.RequestID
local ReplyID = giop.ReplyID
local CancelRequestID = giop.CancelRequestID
local LocateRequestID = giop.LocateRequestID
local LocateReplyID = giop.LocateReplyID
local CloseConnectionID = giop.CloseConnectionID
local MessageErrorID = giop.MessageErrorID
local FragmentID = giop.FragmentID
local SystemExceptionIDL = giop.SystemExceptionIDL
local SystemExceptionIDs = giop.SystemExceptionIDs

local Request = require "oil.protocol.Request"
local Channel = require "oil.protocol.Channel"
local Exception = require "oil.corba.giop.Exception"



local Empty = {}
local MessageBuilder_v1_ = {}
local MessageAdapter_v1_ = {}
do
	local values = {
		reserved = "\000\000\000",
		response_expected = nil, -- defined later, see below
		requesting_principal = Empty,
	}
	local meta = {}
	setmetatable(values, meta)
	MessageBuilder_v1_[0] = {
		[RequestID] = function(header)
			meta.__index = header
			values.response_expected = (header.sync_scope~="channel")
			return values
		end,
		[ReplyID] = function(header)
			meta.__index = header
			return values
		end,
	}
	MessageAdapter_v1_[0] = {
		[RequestID] = function(header)
			header.sync_scope = header.response_expected and "servant" or "channel"
			return header
		end
	}
	MessageBuilder_v1_[1] = MessageBuilder_v1_[0]
	MessageAdapter_v1_[1] = MessageAdapter_v1_[0]
end
do
	local targetkey = {
		_switch = 0,
		_value = nil, -- defined later, see below
	}
	local values = {
		reserved = "\000\000\000",
		response_flags = nil, -- defined later, see below
		target = nil, -- defined later, see below
	}
	local meta = {}
	setmetatable(values, meta)
	local response_flags = {
		channel = 0x0,
		server  = 0x1,
		servant = 0x3,
	}
	MessageBuilder_v1_[2] = {
		[RequestID] = function(header)
			meta.__index = header
			values.response_flags = response_flags[header.sync_scope]
			if header.target == nil then
				targetkey._value = header.object_key
				values.target = targetkey
			else
				values.target = nil
			end
			return values
		end,
		[LocateRequestID] = function(header)
			meta.__index = header
			targetkey._value = header.object_key
			values.target = targetkey
			return values
		end,
	}
	local sync_scopes = {}
	for scope, flag in pairs(response_flags) do
		sync_scopes[flag] = scope
	end
	local function target2objkey(target, self)
		local kind = target._switch
		if kind == 0 then
			return target._value
		elseif kind == 1 then
			local context = self.context
			local referrer = context.referrer or context.codec.referrer
			if referrer then
				local profile = referrer:decodeprofile(target._value)
				if profile then
					return profile.object_key
				end
			end
		elseif kind == 2 then
			local target = target._value
			local profile = target.ior:getprofile(target.selected_profile_index)
			if profile.decoded then
				return profile.object_key
			end
		end
	end
	MessageAdapter_v1_[2] = {
		[RequestID] = function(header, self)
			header.sync_scope = sync_scopes[header.response_flags]
			header.object_key = target2objkey(header.target, self)
			return header
		end,
		[LocateRequestID] = function(header, self)
			header.object_key = target2objkey(header.target, self)
			return header
		end,
	}
end
MessageBuilder_v1_[3] = MessageBuilder_v1_[2]


local function pdecode_cont(ok, ...)
	if ok then return true, ... end
	if type(...) ~= "string" then return false, Exception(...) end
	return false, Exception{ (...), error = "badvalue" }
end
local function pdecode(func, ...)
	return pdecode_cont(pcall(func, ...))
end

local function encodevalues(self, types, values, encoder)
	local count = values.n or #values
	for index, idltype in ipairs(types) do
		local value
		if index <= count then
			value = values[index]
		end
		encoder:put(value, idltype)
	end
end

local function encodemsg(self, kind, header, types, values)
	local codec = self.context.codec
	-- create GIOP message body
	local encoder = codec:encoder()
	encoder:shift(self.headersize) -- alignment accordingly to GIOP header size
	if header then
		local builder = self.messagebuilder[kind]
		if builder then header = builder(header) end
		encoder:struct(header, self.messagetype[kind])
	end
	if types and #types > 0 then
		if self.version > 1 and (kind == RequestID or kind == ReplyID) then
			encoder:align(8)
			local encoded = values.encoded
			if encoded ~= nil then
				local length = #encoded
				encoder:rawput('c'..length, encoded, length)
			else
				encodevalues(self, types, values, encoder)
			end
		else
			encodevalues(self, types, values, encoder)
		end
	end
	local stream = encoder:getdata()
	-- create GIOP message header
	local header = self.header
	header.message_size = #stream
	header.message_type = kind
	encoder = codec:encoder()
	encoder:struct(header, self.headertype)
	return encoder:getdata()..stream
end
local function sendmsg(self, kind, header, types, values)                     --[[VERBOSE]] verbose:message(true, "send message ",MessageType[kind],header or "")
	local ok, result = pcall(encodemsg, self, kind, header, types, values)
	if ok then
		self:trylock("write")
		ok, result = self:send(result)
		if not ok and type(result) == "table" then result = Exception(result) end
		self:freelock("write")
	else                                                                        --[[VERBOSE]] verbose:message("message encoding failed")
		if type(result) ~= "string" then
			result = Exception(result)
		else
			result = Exception{ result, error = "badvalue" }
		end
	end                                                                         --[[VERBOSE]] verbose:message(false)
	return ok, result
end

local function decodeheader(self, stream)
	local decoder = self.context.codec:decoder(stream)
	local header = self.headertype
	local magic = decoder:array(header[1].type)
	if magic ~= self.magictag then                                              --[[VERBOSE]] verbose:message("got invalid magic tag: ",magic)
		error(Exception{
			"illegal GIOP magic tag (got $actualtag)",
			error = "badstream",
			actualtag = magic,
		})
	end
	local version = decoder:struct(header[2].type)
	local minor = version.minor
	header = GIOPHeader_v1_[minor]
	if version.major ~= 1 or header == nil then                                 --[[VERBOSE]] verbose:message("got unsupported GIOP version: ",version)
		error(Exception{
			"illegal GIOP version (got $majorversion.$minorversion)",
			error = "badversion",
			majorversion = version.major,
			minorversion = version.minor,
		})
	end
	local incomplete
	if minor == 0 then
		decoder:order(decoder:boolean())
	else
		local flags = decoder:octet()
		local orderbit = flags%2
		decoder:order(orderbit == 1)
		local fragbit = (flags-orderbit)%4
		incomplete = (fragbit == 2)
	end
	return minor, -- version
	       decoder:octet(), -- type
	       decoder:ulong(), -- size
	       incomplete,
	       decoder
end
local function decodemsgbody(self, decoder, minor, kind)
	local struct = MessageHeader_v1_[minor][kind]
	if struct then
		local body = decoder:struct(struct)
		local adapter = MessageAdapter_v1_[minor][kind]
		if adapter then
			body = adapter(body, self)
		end
		if minor > 1 and (kind == RequestID or kind == ReplyID)
		and decoder.cursor <= #decoder.data then
			decoder:align(8)
		end
		return body
	end
end
local IncompleteMessages = {}
local function receivemsg(self, timeout)                                      --[[VERBOSE]] verbose:message(true, "get message from channel")
	while true do
		local minor, kind, size, decoder, incomplete
		local pending = self.pendingmessage
		if pending == nil then
			-- unmarshal message header
			local stream, except = self:receive(self.headersize, timeout)
			if stream == nil then                                                   --[[VERBOSE]] verbose:message(false, except.error == "timeout" and "message data is not available yet" or "error while reading message header data")
				return nil, Exception(except)
			end
			local ok
			ok, minor, kind, size, incomplete, decoder = pdecode(decodeheader,
			                                                     self, stream)
			if not ok then                                                          --[[VERBOSE]] verbose:message(false, "error in message header decoding: ",minor.error)
				return nil, minor
			end
		else                                                                      --[[VERBOSE]] verbose:message("continue message from a previous decoded header")
			-- continue decoding of a previous decoded header
			minor = pending.minor
			kind = pending.kind
			size = pending.size
			decoder = pending.decoder
			incomplete = pending.incomplete
		end
		-- upgrade channel version
		self:upgradeto(minor)
		-- unmarshal message body
		local message
		if size > 0 then
			local stream, except = self:receive(size, timeout)
			if stream == nil then
				if except.error ~= "timeout" then                                     --[[VERBOSE]] verbose:message(false, "error while reading message body data")
					self.pendingmessage = nil
				elseif pending == nil then                                            --[[VERBOSE]] verbose:message(false, "message body data is not available yet")
					self.pendingmessage = {
						minor = minor,
						kind = kind,
						size = size,
						decoder = decoder,
						incomplete = incomplete,
					}                                                                   --[[VERBOSE]] else verbose:message(false)
				end
				return nil, Exception(except)
			end
			decoder:append(stream)
		end
		self.pendingmessage = nil
		local fragment = (kind == FragmentID) or incomplete
		if fragment then
			local cursor
			local id
			if minor == 1 then
				id = #IncompleteMessages
				if kind ~= FragmentID then id = id+1 end
			else
				cursor = decoder.cursor
				local ok
				ok, id = pdecode(decoder.ulong, decoder)
				if not ok then                                                        --[[VERBOSE]] verbose:message(false, "error in decoding request id: ",message.error)
					return nil, id
				end
			end
			-- handle incomplete fragmented messages
			if kind == FragmentID then
				local previous = IncompleteMessages[id]
				previous:append(decoder:remains())
				if not incomplete then
					decoder = previous
					kind = decoder.kind                                                 --[[VERBOSE]] verbose:message("got final fragment of message ",MessageType[kind])
					fragment = false
					IncompleteMessages[id] = nil                                        --[[VERBOSE]] else verbose:message("fragment of an incomplete message")
				end
			else                                                                    --[[VERBOSE]] verbose:message("got the begin of a fragmented message")
				if cursor then decoder.cursor = cursor end
				decoder.kind = kind
				IncompleteMessages[id] = decoder
			end
		end
		if not fragment then
			local ok
			ok, message = pdecode(decodemsgbody, self, decoder, minor, kind)
			if not ok then                                                          --[[VERBOSE]] verbose:message(false, "error in message body decoding: ",message.error)
				return nil, message
			end                                                                     --[[VERBOSE]] verbose:message(false, "got message ",MessageType[kind],message or "")
			return kind, message or minor, decoder
		end
	end
end

local function failedGIOP(self, errmsg)
	self:close()
	return nil, Exception{
		"GIOP Failure ($errmsg)",
		error = "badmessage",
		errmsg = errmsg,
	}
end

local function unknownex(self, error)
	self.unotifiederror = error
	return Exception{ SystemExceptionIDs.UNKNOWN,
		minor = 0,
		completed = "COMPLETED_MAYBE",
		error = error,
	}
end



local GIOPServerRequest = class({}, Request)

local function noresponse() return true end
function GIOPServerRequest:__init()
	if self.sync_scope == "channel" then
		self.sendreply = noresponse
	end
	self.objectkey = self.object_key
end

function GIOPServerRequest:preinvoke(entry, member)
	if member ~= nil then
		local inputs = member.inputs
		local count = #inputs
		self.n = count
		self.outputs = member.outputs
		self.exceptions = member.exceptions
		local decoder = self.decoder
		for i = 1, count do
			local ok, result = pcall(decoder.get, decoder, inputs[i])
			if not ok then
				assert(type(result) == "table", result)
				self:setreply(false, result)
				return -- request cancelled
			end
			self[i] = result
		end
		local object = entry.__servant
		local method = object[member.name]
		if method == nil then
			return entry, member.implementation, "internal"
		end
		return object, method
	end
end

local UserExTypes = { idl.string, --[[defined later, see below]] }
local SysExTypes = { idl.string, giop.SystemExceptionIDL }
local ExMsgBody = {}
local SystemExceptions = {}
for _, repID in pairs(SystemExceptionIDs) do
	SystemExceptions[repID] = true
end
local OiLEx2SysEx = {
	badobjkey = {
		_repid = SystemExceptionIDs.OBJECT_NOT_EXIST,
		minor = 1,
		completed = "COMPLETED_NO",
	},
	badobjimpl = {
		_repid = SystemExceptionIDs.NO_IMPLEMENT,
		minor = 1,
		completed = "COMPLETED_NO",
	},
	badobjop = {
		_repid = SystemExceptionIDs.BAD_OPERATION,
		minor = 1,
		completed = "COMPLETED_NO",
	},
	badsecurity = {
		_repid = SystemExceptionIDs.NO_PERMISSION,
		minor = 1,
		completed = "COMPLETED_NO",
	},
}
function GIOPServerRequest:getreplybody()
	self.service_context = nil
	if self.success then                                                        --[[VERBOSE]] verbose:listen("got successful results")
		self.reply_status = "NO_EXCEPTION"
		return self.outputs, self
	end
	local except = self[1]
	if type(except) == "table" then
		local repid = except._repid
		local excepttype = self.exceptions
		excepttype = excepttype and excepttype[repid]
		if excepttype then                                                        --[[VERBOSE]] verbose:listen("got exception ",except)
			self.reply_status = "USER_EXCEPTION"
			UserExTypes[2] = excepttype
			ExMsgBody[1] = repid
			ExMsgBody[2] = except
			return UserExTypes, ExMsgBody
		elseif not SystemExceptions[repid] then                                   --[[VERBOSE]] verbose:listen("got unexpected exception: ",except)
			except = OiLEx2SysEx[except.error] or unknownex(self, except)           --[[VERBOSE]] else verbose:listen("got system exception: ",except)
		end
	else
		except = unknownex(self, except)
	end
	self.reply_status = "SYSTEM_EXCEPTION"
	ExMsgBody[1] = except._repid
	ExMsgBody[2] = except
	return SysExTypes, ExMsgBody
end

function GIOPServerRequest:setreply(success, ...)
	local channel = self.channel
	if channel ~= nil then                                                      --[[VERBOSE]] verbose:listen("set reply for request ",self.request_id," to ",self.objectkey,":",self.operation)
		Request.setreply(self, success, ...)
		local success, except = channel:sendreply(self)
		if not success and except.error ~= "closed" then                          --[[VERBOSE]] verbose:listen("error sending reply for request ",self.request_id," to ",self.objectkey,":",self.operation)
			return false, except
		end                                                                       --[[VERBOSE]] else verbose:listen("ignoring reply for cancelled request ",self.request_id," to ",self.objectkey,":",self.operation)
	end
	return true
end


local GIOPChannel = class({
	magictag = MagicTag,
	headersize = HeaderSize,
	version = -1,
	ServerRequest = GIOPServerRequest,
}, Channel)

function GIOPChannel:__init()
	self.header = {
		magic = MagicTag,
		GIOP_version = {major=1, minor=nil}, -- 'minor' is defined later
		byte_order = littleendian,
		flags = littleendian and 1 or 0,
		message_type = nil, -- defined later
		message_size = nil, -- defined later
	}
	self.unprocessed = Queue()
	self.incoming = {}
	self.outgoing = {}
	self[self.incoming] = 0
	self[self.outgoing] = 0
	self:upgradeto(0)
end

function GIOPChannel:register(request, direction)
	if request.channel == nil then
		request.channel = self
		local set = self[direction]
		local id
		if direction == "outgoing" then
			id = #set+1
			request.id = id
			request.request_id = 2*id + (self.bidir_role=="acceptor" and 1 or 0)
		else
			id = request.request_id
		end
		set[id] = request
		self[set] = self[set]+1
		return true
	end
end

function GIOPChannel:unregister(requestid, direction, sentinel)
	local set = self[direction]
	local request = set[requestid]
	if request ~= nil then
		self[set] = self[set]-1
		set[requestid] = sentinel
		if request then
			request.channel = nil
			if direction == "outgoing" then
				request.id = nil
				request.request_id = nil
			end
		end
		if self.closing then
			self:close(self.closing)
		end
		return request
	end
end

function GIOPChannel:regcount(direction)
	return self[self[direction]]
end

function GIOPChannel:upgradeto(minor)
	if minor > self.version and GIOPHeader_v1_[minor] ~= nil then               --[[VERBOSE]] verbose:message("GIOP channel upgraded to version 1.",minor)
		self.headertype = GIOPHeader_v1_[minor]
		self.messagetype = MessageHeader_v1_[minor]
		self.messagebuilder = MessageBuilder_v1_[minor]
		self.header.GIOP_version.minor = minor
		self.version = minor
	end
end

local AddressingType = {giop.AddressingDisposition}
local KeyAddrValue = {giop.KeyAddr}
local CancelledReply = {
	reply_status = "SYSTEM_EXCEPTION",
	service_context = Empty,
}
local CancelledSysEx = {
	SystemExceptionIDs.NO_RESPONSE,
	{
		completed = "COMPLETED_MAYBE",
		minor = 0,
	},
}
local MessageHandlers = {
	[RequestID] = function(channel, header, decoder)
		if channel.closing == "incoming" or channel.closing == true then return true end
		local requestid = header.request_id
		if channel.incoming[requestid] ~= nil then                                --[[VERBOSE]] verbose:listen("got replicated request id ",requestid)
			return failedGIOP(channel, "remote ORB issued a request with duplicated ID")
		end
		local response = header.sync_scope ~= "channel"
		if header.object_key == nil then                                          --[[VERBOSE]] verbose:listen("got request ",requestid," with wrong addressing information")
			if response then                                                        --[[VERBOSE]] verbose:listen("send reply requesting different addressing information")
				local reply = {
					request_id = requestid,
					reply_status = "NEEDS_ADDRESSING_MODE",
					service_context = Empty,
				}
				return sendmsg(channel, ReplyID, reply, AddressingType, KeyAddrValue)
			end                                                                     --[[VERBOSE]] verbose:listen("ignoring request because no reply is expected, so it is not possible to request different addressing information")
			return true
		end
		if response then
			channel:register(header, "incoming")                                    --[[VERBOSE]] else verbose:listen("no reply is expected")
		end
		header.decoder = decoder
		header.secured = (channel.socket.getpeercertificate ~= nil)
		local unprocessed = channel.unprocessed
		unprocessed:enqueue(header)
		channel:signal("read", unprocessed)
		return true
	end,
	[ReplyID] = function(channel, header, decoder)
		local request = channel:unregister(floor(header.request_id/2), "outgoing")
		if request == nil then                                                    --[[VERBOSE]] verbose:invoke("got reply for invalid request ID: ",header.request_id)
			return failedGIOP(channel, "remote ORB issued a reply with unknown ID")
		elseif not request then -- cancelled request
			return true
		end
		request.reply = header
		request.decoder = decoder
		channel:signal("read", request) -- notify thread waiting for this reply
		return request
	end,
	[CancelRequestID] = function(channel, header, decoder)                      --[[VERBOSE]] verbose:listen("got cancelation of request ",header.requestid)
		local requestid = header.request_id
		if channel:unregister(requestid, "incoming") == nil then          --[[VERBOSE]] verbose:listen("canceled request ",header.requestid," does not exist")
			return failedGIOP(channel, "remote ORB canceled a request with unknown ID")
		end
		CancelledReply.request_id = requestid
		return sendmsg(self, ReplyID, CancelledReply, SysExTypes, CancelledSysEx)
	end,
	[LocateRequestID] = function(channel, header, decoder)
		local types, values
		local objkey = header.object_key                                          --[[VERBOSE]] verbose:listen(true, "got request ",header.request_id," to locate object ",objkey)
		local reply = { request_id = header.request_id }
		if objkey == nil then
			reply.locate_status = "LOC_NEEDS_ADDRESSING_MODE"                       --[[VERBOSE]] verbose:listen("different addressing information is required")
			types = AddressingType
			values = KeyAddrValue
		elseif channel.context.servants:retrieve(objkey) then
			reply.locate_status = "OBJECT_HERE"                                     --[[VERBOSE]] verbose:listen("object found here")
		else
			reply.locate_status = "UNKNOWN_OBJECT"                                  --[[VERBOSE]] verbose:listen("object is unknown")
		end                                                                       --[[VERBOSE]] verbose:listen(false)
		return sendmsg(channel, LocateReplyID, reply, types, values)
	end,
	[CloseConnectionID] = function(channel)
		local result, except = channel:close("outgoing")
		-- notify threads waiting for replies to reissue them in a new connection
		for requestid in pairs(channel.outgoing) do
			local request = channel:unregister(requestid, "outgoing")
			if request then
				channel:signal("read", request)
			end
		end
		return result, except
	end,
	[MessageErrorID] = function(channel, minor)
		if self:regcount("incoming") == 0 and minor < channel.version then         --[[VERBOSE]] verbose:invoke("got remote request to use GIOP 1.",minor," instead of GIOP 1.",channel.version)
			local result, except = channel:close()
			-- notify threads waiting for replies to reissue them in a new connection
			for requestid, request in pairs(channel.outgoing) do
				channel:unregister(requestid, "outgoing")
				if request then
					request.reference.ior_profile.decoded.giop_minor = minor
					channel:signal("read", request)
				end
			end
			return result, except
		end                                                                       --[[VERBOSE]] verbose:invoke("got remote indication of error in protocol messages")
		return failedGIOP(channel, "remote ORB reported error in GIOP messages")
	end,
}
function GIOPChannel:processmessage(timeout)
	local msgid, header, decoder = receivemsg(self, timeout)
	if msgid == nil then
		if header.error == "badversion" or header.error == "badstream" then
			self:close()
			sendmsg(self, MessageErrorID)
		end
		return nil, header
	end
	local handler = MessageHandlers[msgid]
	if handler == nil then                                                        --[[VERBOSE]] verbose:message("message error: ",header)
		return sendmsg(self, MessageErrorID)
	end
	return handler(self, header, decoder)
end

function GIOPChannel:sendrequest(request)
	local bidir = self.bidir_role
	if request.sync_scope ~= "channel" then
		self:register(request, "outgoing") -- defines the 'request_id'
	else
		request.request_id = (bidir=="acceptor" and 1 or 0)
	end
	local types = request.inputs
	if self.version > 1 and request.encoded == nil then
		local encoder = self.context.codec:encoder()
		encodevalues(self, types, request, encoder)
		request.encoded = encoder:getdata()
	end
	-- add Bi-Directional GIOP service context
	local listener
	if bidir == nil then
		local context = self.context
		listener = context.listener
		if listener ~= nil then
			local encoder = context.bidircodec
			if encoder ~= nil then
				local address = listener:getaddress("probe")
				if address ~= nil then
					local servctxt = request.service_context or {}
					encoder:encodebidir(servctxt, address)
					if servctxt ~= nil then                                             --[[VERBOSE]] verbose:invoke("bi-directional GIOP indication added to the request")
						request.service_context = servctxt
						bidir = "connector"
					end
				end
			end
		end
	end
	local service_context = request.service_context
	if service_context == nil then request.service_context = Empty end
	local success, except = sendmsg(self, RequestID, request, types, request)
	if service_context == nil then request.service_context = nil end
	if not success then                                                         --[[VERBOSE]] verbose:invoke("unable to send the request")
		self:unregister(request.id, "outgoing")
	elseif bidir ~= nil and listener ~= nil then
		self.bidir_role = bidir
		listener:addbidirchannel(self)
	end
	return success, except
end

local CancelRequest = { request_id = nil }
function GIOPChannel:cancelrequest(request)
	local requestid = request.id
	if self:unregister(requestid, "outgoing", false) == request then            --[[VERBOSE]] verbose:invoke("canceling request ",requestid)
		CancelRequest.request_id = requestid
		return sendmsg(self, CancelRequestID, CancelRequest)
	end
	return false, Exception{ error = "badinvorder" }
end

function GIOPChannel:getreply(request, timeout)
	local granted, expired = self:trylock("read", timeout, request)
	if granted then
		local result, except
		repeat
			result, except = self:processmessage(timeout)
		until result == nil or result == request or request.channel ~= self
		self:freelock("read")
		if result == nil then                                                     --[[VERBOSE]] verbose:invoke("failed to get reply")
			return nil, except
		end
	elseif expired then --[[timeout of 'trylock' expired]]                      --[[VERBOSE]] verbose:invoke("got no reply before timeout")
		return nil, Exception{ "timeout", error = "timeout" }
	end
	return true
end

function GIOPChannel:getrequest(timeout)
	local unprocessed = self.unprocessed
	if unprocessed:empty() then                                                 --[[VERBOSE]] verbose:listen(true, "no request ready to be processed, read from channel")
		if self:trylock("read", timeout, unprocessed) then
			local ok, except
			repeat
				ok, except = self:processmessage(timeout)
			until not ok or not unprocessed:empty() or self.acceptor == nil
			self:freelock("read")
			if not ok then                                                          --[[VERBOSE]] verbose:listen(false, "failed to get request")
				return nil, except
			elseif self.acceptor == nil then                                        --[[VERBOSE]] verbose:listen(false, "channel closed for incoming request")
				return nil, Exception{ "closed for incoming request", error = "closed" }
			end
		end                                                                       --[[VERBOSE]] verbose:listen(false, "request was successfully read from channel")
	end
	local request = unprocessed:dequeue()
	-- handle Bi-Directional GIOP service context
	local bidir = self.bidir_role
	if bidir == nil then
		local context = self.context
		local requester = context.requester
		if requester ~= nil then
			local decoder = context.bidircodec
			if decoder ~= nil then
				local addresses = decoder:decodebidir(request.service_context)
				if addresses ~= nil then
					self.bidir_role = "acceptor"
					requester:addbidirchannel(self, addresses)                          --[[VERBOSE]] else verbose:listen("no bi-directional GIOP indication found in request received")
				end
			end
		end
	end
	return self.ServerRequest(request)
end

function GIOPChannel:sendreply(request)
	local success, except = true
	local requestid = request.request_id                                        --[[VERBOSE]] verbose:listen(true, "replying for request ",request.request_id," for ",request.objectkey,":",request.operation)
	if self.incoming[requestid] == request then
		self.incoming[requestid] = nil -- free request ID to client can reuse it
		self.incoming[request] = request -- keep request register to avoid channel be closed
		local types, values = request:getreplybody()
		local service_context = request.service_context
		if service_context == nil then request.service_context = Empty end
		success, except = sendmsg(self, ReplyID, request, types, values)
		if not success then                                                       --[[VERBOSE]] verbose:listen(true, "unable to send reply: ",except)
			if except.error == "closed" then                                        --[[VERBOSE]] verbose:listen("connection terminated")
				success, except = true
			else
				if request.reply_status == "SYSTEM_EXCEPTION" then
					except.completed = values[2].completed
				else
					request.reply_status = "SYSTEM_EXCEPTION"
					except.completed = "COMPLETED_YES"
				end
				ExMsgBody[1], ExMsgBody[2] = except._repid, except
				success, except = sendmsg(self, ReplyID, request, SysExTypes, ExMsgBody)
				if not success then                                                   --[[VERBOSE]] verbose:listen("unable to send exception on reply: ",except)
					if except.error == "closed" then                                    --[[VERBOSE]] verbose:listen("connection terminated")
						success, except = true                                            --[[VERBOSE]] else verbose:listen(false, "unable to send the error on reply as well")
					end                                                                 --[[VERBOSE]] else verbose:listen(false, "error on reply was sent instead of the original result")
				end
			end
		end
		if service_context == nil then request.service_context = nil end
		self:unregister(request, "incoming")                                      --[[VERBOSE]] else verbose:listen("no pending request found with id ",requestid,", reply discarded")
	end                                                                         --[[VERBOSE]] verbose:listen(false, "reply ", success and "successfully processed" or "failed: ", except or "")
	return success, except
end

function GIOPChannel:close(direction)
	local result, except = true
	if direction ~= "outgoing" then
		local acceptor = self.acceptor
		if acceptor then -- might be 'false' or 'nil'
			acceptor:unregister(self)
			self.requestclose = true
		end
		if self:regcount("incoming") == 0 then
			if self.requestclose then                                                 --[[VERBOSE]] verbose:listen("sending channel closing notification")
				if not sendmsg(self, CloseConnectionID) then                            --[[VERBOSE]] verbose:listen("closing notification failed, closing channel in both directions")
					direction = "both"                                                    --[[VERBOSE]] else verbose:listen("closing notification successfully sent")
				end
				self.requestclose = nil
			end
		elseif self.closing == nil then                                             --[[VERBOSE]] verbose:listen("channel marked for closing (incoming only)")
			self.closing = "incoming"
		elseif self.closing ~= "incoming" then                                      --[[VERBOSE]] if self.closing ~= true then verbose:listen("channel marked for closing") end
			self.closing = true
		end
	end
	if direction ~= "incoming" then
		local connector = self.connector
		if connector ~= nil then
			connector:unregister(self)
		end
		if self:regcount("outgoing") > 0 then
			if self.closing == nil then                                               --[[VERBOSE]] verbose:listen("channel marked for closing (outgoing only)")
				self.closing = "outgoing"
			elseif self.closing ~= "outgoing" then                                    --[[VERBOSE]] if self.closing ~= true then verbose:listen("channel marked for closing") end
				self.closing = true
			end
		end
	end
	if self.acceptor == nil and self:regcount("incoming") == 0
	and self.connector == nil and self:regcount("outgoing") == 0
	then
		result, except = Channel.close(self)                                        --[[VERBOSE]] verbose:invoke("channel closed")
	end
	return result, except
end

function GIOPChannel:idle()
	return self:regcount("incoming") == 0 and self:regcount("outgoing") == 0
end

return GIOPChannel
