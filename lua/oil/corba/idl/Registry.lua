-- Project: OiL - ORB in Lua: An Object Request Broker in Lua
-- Release: 0.6
-- Title  : IDL Definition Registry
-- Authors: Renato Maia <maia@inf.puc-rio.br>

local _G = require "_G"                                                         --[[VERBOSE]] local verbose = require "oil.verbose"
local error = _G.error
local getmetatable = _G.getmetatable
local ipairs = _G.ipairs
local next = _G.next
local pairs = _G.pairs
local rawget = _G.rawget
local rawset = _G.rawset
local select = _G.select
local setmetatable = _G.setmetatable
local type = _G.type

local string = require "string"
local gmatch = string.gmatch

local array = require "table"
local remove = array.remove
local unpack = array.unpack or _G.unpack

local OrderedSet = require "loop.collection.OrderedSet"
local Publisher = require "loop.object.Publisher"

local oo = require "oil.oo"
local class = oo.class
local getclass = oo.getclass
local getmember = oo.getmember
local isclass = oo.isclass
local isinstanceof = oo.isinstanceof
local rawnew = oo.rawnew
local topdown = oo.topdown

local assert = require "oil.assert"
local asserttype = assert.type
local assertillegal = assert.illegal

local idl = require "oil.corba.idl"
local idlContainer = idl.Container
local void = idl.void
local null = idl.null
local ValueBase = idl.ValueBase

local iridl = require("oil.corba.idl.ir").definitions
local Exception = require "oil.corba.giop.Exception"

--------------------------------------------------------------------------------
-- Internal classes ------------------------------------------------------------

  local IRObject                = class()
  local Contained               = class({}, IRObject)
  local Container               = class({}, IRObject)
  local IDLType                 = class({}, IRObject)
  
  local PrimitiveDef            = class({ __type = "IDL:omg.org/CORBA/PrimitiveDef:1.0"            }, IDLType)
  local ArrayDef                = class({ __type = "IDL:omg.org/CORBA/ArrayDef:1.0"                }, IDLType)
  local SequenceDef             = class({ __type = "IDL:omg.org/CORBA/SequenceDef:1.0"             }, IDLType)
  local StringDef               = class({ __type = "IDL:omg.org/CORBA/StringDef:1.0"               }, IDLType)
--local WstringDef              = class({ __type = "IDL:omg.org/CORBA/WstringDef:1.0"              }, IDLType)
--local FixedDef                = class({ __type = "IDL:omg.org/CORBA/FixedDef:1.0"                }, IDLType)
  
  local MemberDef               = class(nil                                                         , Contained)
  
  local AttributeDef            = class({ __type = "IDL:omg.org/CORBA/AttributeDef:1.0"            }, MemberDef)
  local OperationDef            = class({ __type = "IDL:omg.org/CORBA/OperationDef:1.0"            }, MemberDef)
  local ValueMemberDef          = class({ __type = "IDL:omg.org/CORBA/ValueMemberDef:1.0"          }, MemberDef)
  local ConstantDef             = class({ __type = "IDL:omg.org/CORBA/ConstantDef:1.0"             }, Contained)
  local TypedefDef              = class({ __type = "IDL:omg.org/CORBA/TypedefDef:1.0"              }, IDLType, Contained)
  
  local StructDef               = class({ __type = "IDL:omg.org/CORBA/StructDef:1.0"               }, TypedefDef , Container)
  local UnionDef                = class({ __type = "IDL:omg.org/CORBA/UnionDef:1.0"                }, TypedefDef , Container)
  local EnumDef                 = class({ __type = "IDL:omg.org/CORBA/EnumDef:1.0"                 }, TypedefDef)
  local AliasDef                = class({ __type = "IDL:omg.org/CORBA/AliasDef:1.0"                }, TypedefDef)
--local NativeDef               = class({ __type = "IDL:omg.org/CORBA/NativeDef:1.0"               }, TypedefDef)
  local ValueBoxDef             = class({ __type = "IDL:omg.org/CORBA/ValueBoxDef:1.0"             }, TypedefDef)
  
  local Repository              = class({ __type = "IDL:omg.org/CORBA/Repository:1.0"              }, Container)
  local ModuleDef               = class({ __type = "IDL:omg.org/CORBA/ModuleDef:1.0"               }, Contained, Container)
  local ExceptionDef            = class({ __type = "IDL:omg.org/CORBA/ExceptionDef:1.0"            }, Contained, Container)
  local InterfaceDef            = class({ __type = "IDL:omg.org/CORBA/InterfaceDef:1.0"            }, IDLType, Contained, Container)
  local ValueDef                = class({ __type = "IDL:omg.org/CORBA/ValueDef:1.0"                }, Container, Contained, IDLType)
  
  local AbstractInterfaceDef    = class({ __type = "IDL:omg.org/CORBA/AbstractInterfaceDef:1.0"    }, InterfaceDef)
  local LocalInterfaceDef       = class({ __type = "IDL:omg.org/CORBA/LocalInterfaceDef:1.0"       }, InterfaceDef)
  
--local ExtAttributeDef         = class({ __type = "IDL:omg.org/CORBA/ExtAttributeDef:1.0"         }, AttributeDef)
--local ExtValueDef             = class({ __type = "IDL:omg.org/CORBA/ExtValueDef:1.0"             }, ValueDef)
--local ExtInterfaceDef         = class({ __type = "IDL:omg.org/CORBA/ExtInterfaceDef:1.0"         }, InterfaceDef, InterfaceAttrExtension)
--local ExtAbstractInterfaceDef = class({ __type = "IDL:omg.org/CORBA/ExtAbstractInterfaceDef:1.0" }, AbstractInterfaceDef, InterfaceAttrExtension)
--local ExtLocalInterfaceDef    = class({ __type = "IDL:omg.org/CORBA/ExtLocalInterfaceDef:1.0"    }, LocalInterfaceDef, InterfaceAttrExtension)
  
  local ObjectRef               = class() -- fake class

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local Empty = setmetatable({}, { __newindex = function(_, field) verbose:debug("attempt to set table 'Empty'") end })

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--
-- Implementation
--

function IRObject:__new(...)
	self = rawnew(self, ...)
	self.references = self.references or {}
	self.observer = self.observer or Publisher()
	return self
end

function IRObject:watch(object, field)
	local references = object.references
	if references then
		if not references[self] then
			references[self] = {}
		end
		references[self][field] = true
	end
	return object
end

function IRObject:nowatch(object, field)
	local references = object.references
	if references then
		references[self][field] = nil
		if next(references[self]) == nil then
			references[self] = nil
		end
	end
end

function IRObject:notify(...)
	local queue = OrderedSet()
	queue:enqueue(self)
	repeat
		if self.observer then self.observer:notify(...) end
		if self.references then
			for ref in pairs(self.references) do queue:enqueue(ref) end
		end
		self = queue:successor(self)
	until self == nil
end

--
-- Operations
--
function IRObject:destroy()
	if self.observer == nil or next(self.references) ~= nil then
		error(Exception{ "BAD_INV_ORDER", minor_error_code = 1,
			"attempt to destroy IR definition in use",
			error = "irdestroy",
			object = self,
		})
	end
	if self.defined_in then
		self.defined_in.definitions:_remove(self)
	end
	self.containing_repository.definition_map[self.repID] = nil
end

--------------------------------------------------------------------------------

--
-- Implementation
--
Contained.version = "1.0"
Contained.definition_fields = {
	defined_in = { type = Container, optional = true },
	repID      = { type = "string" , optional = true },
	version    = { type = "string" , optional = true },
	name       = { type = "string" },
}

function Contained:update(new)
	new.defined_in = new.defined_in or self.containing_repository
	if new.defined_in.containing_repository ~= self.containing_repository then
		assertillegal(new.defined_in,
		              "container, repository does not match",
		              "BAD_PARAM")
	end
	if new.repID then
		self:_set_id(new.repID)
	end
	self:move(new.defined_in, new.name, new.version)
end

local RepIDFormat = "IDL:%s:%s"
function Contained:updatename()
	local old = self.absolute_name
	self.absolute_name = self.defined_in.absolute_name.."::"..self.name
	if not self.repID then
		self:_set_id(RepIDFormat:format(self.absolute_name:gsub("::", "/"):sub(2),
		                                self.version))
	end
	if self.definitions then
		for _, contained in ipairs(self.definitions) do
			contained:updatename()
		end
	end
	if self.absolute_name ~= old then self:notify("absolute_name") end
end

--
-- Attributes
--
function Contained:_set_id(id)
	local definitions = self.containing_repository.definition_map
	if definitions[id] and definitions[id] ~= self then
		assertillegal(id, "repository ID, already exists", "BAD_PARAM", 2)
	end
	if self.repID then
		definitions[self.repID] = nil
	end
	local old = self.repID
	self.repID = id
	self.id = id
	definitions[id] = self
	if self.repID ~= old then self:notify("repID") end
end

function Contained:_set_name(name)
	local contents = self.defined_in.definitions
	if contents[name] and contents[name] ~= self then
		assertillegal(name, "contained name, name clash", "BAD_PARAM", 1)
	end
	local old = self.name
	contents:_remove(self)
	self.name = name
	contents:_add(self)
	self:updatename()
	if self.name ~= old then self:notify("name") end
end

--
-- Operations
--
local ContainedDescription = iridl.Contained.definitions.Description
function Contained:describe()
	local description = self:get_description()
	description.name       = self.name
	description.id         = self.repID
	description.defined_in = self.defined_in.repID
	description.version    = self.version
	return setmetatable({
		kind = self.def_kind,
		value = description,
	}, ContainedDescription)
end

--function Contained:within() -- TODO:[maia] This op is described in specs but
--end                         --             is not listed in IR IDL!

function Contained:move(new_container, new_name, new_version)
	if new_container.containing_repository ~= self.containing_repository then
		assertillegal(new_container, "container", "BAD_PARAM", 4)
	end
	
	local new = new_container.definitions
	if new[new_name] and new[new_name] ~= self then
		assertillegal(new_name, "contained name, already exists", "BAD_PARAM", 3)
	end
	
	if self.defined_in then
		self.defined_in.definitions:_remove(self)
	end
	
	local old = self.defined_in
	self.defined_in = new_container
	self.version = new_version
	self:_set_name(new_name)
	if self.defined_in ~= old then
		if old then old:notify("contents") end
		self.defined_in:notify("contents")
		self:notify("defined_in")
	end
end

--------------------------------------------------------------------------------

--
-- Implementation
--
function Container:update()
	if not self.expandable then self.definitions = nil end
	idlContainer(self)
end

local function isingle(self, ended)
	if not ended then return self end
end
function Container:hierarchy()
	return isingle, self
end

--
-- Read interface
--

function Container:lookup(search_name)
	local scope
	if search_name:find("^::") then
		scope = self.containing_repository
	else
		scope = self
		search_name = "::"..search_name
	end
	for nextscope in gmatch(search_name, "::([^:]+)") do
		if not scope or not scope.definitions then return nil end
		scope = scope.definitions[nextscope]
	end
	return scope
end

function Container:contents(limit_type, exclude_inherited, max_returned_objs)
	max_returned_objs = max_returned_objs or -1
	local contents = {}
	for container in self:hierarchy() do
		for _, contained in ipairs(container.definitions)	do
			if limit_type == "dk_all" or contained.def_kind == limit_type then
				if max_returned_objs == 0 then break end
				contents[#contents+1] = contained
				max_returned_objs = max_returned_objs - 1
			end
		end
		if exclude_inherited then break end
	end
	return contents, max_returned_objs
end

function Container:lookup_name(search_name, levels_to_search,
                               limit_type, exclude_inherited)
	local results = {}
	for container in self:hierarchy() do
		for _, contained in ipairs(container.definitions)	do
			if
				contained.name == search_name and
				(limit_type == "dk_all" or contained.def_kind == limit_type)
			then
				results[#results+1] = contained
			end
		end
		if exclude_inherited then break end
	end
	return results
end

local ContainerDescription = iridl.Container.definitions.Description
function Container:describe_contents(limit_type, exclude_inherited,
                                     max_returned_objs)
	local contents = self:contents(limit_type,
	                               exclude_inherited,
	                               max_returned_objs)
	for index, content in ipairs(contents) do
		contents[index] = setmetatable({
			contained_object = content,
			kind = content.def_kind,
			value = content:describe(),
		}, ContainerDescription)
	end
	return contents
end

--
-- Write interface
--

function Container:create_module(id, name, version)
	local created = ModuleDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,
	}
	return created
end

function Container:create_constant(id, name, version, type, value)
	local created = ConstantDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,
		
		type = type,
		value = value,
	}
	return created
end

function Container:create_struct(id, name, version, members)
	local created = StructDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,
		
		fields = members,
	}
	return created
end

function Container:create_union(id, name, version, discriminator_type, members)
	local created = UnionDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,
		
		switch = discriminator_type.type,
		members = members,
	}
	return created
end

function Container:create_enum(id, name, version, members)
	local created = EnumDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,
		
		enumvalues = members,
	}
	return created
end

function Container:create_alias(id, name, version, original_type)
	local created = AliasDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,
		
		original_type = original_type.type
	}
	return created
end

function Container:create_interface(id, name, version, base_interfaces)
	local created = InterfaceDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,

		base_interfaces = base_interfaces,
	}
	return created
end

function Container:create_value(id, name, version,
                                is_custom,
                                is_abstract,
                                base_value,
                                is_truncatable,
                                abstract_base_values,
                                supported_interfaces,
                                initializers)
	local created = ValueDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,
		
		is_custom = is_custom,
		is_abstract = is_abstract,
		is_truncatable = is_truncatable,
		
		base_value = base_value,
		abstract_base_values = abstract_base_values,
		supported_interfaces = supported_interfaces,
		
		initializers = initializers,
	}
	return created
end

function Container:create_value_box(id, name, version, original_type)
	local created = ValueBoxDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
	
		repID = id,
		name = name,
		version = version,
	
		original_type = original_type.type
	}
	return created
end

function Container:create_exception(id, name, version, members)
	local created = ExceptionDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,
		
		members = members,
	}
	return created
end

--function Container:create_native(id, name, version)
--end

function Container:create_abstract_interface(id, name, version, base_interfaces)
	local created = AbstractInterfaceDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,

		base_interfaces = base_interfaces,
	}
	return created
end

function Container:create_local_interface(id, name, version, base_interfaces)
	local created = LocalInterfaceDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,

		base_interfaces = base_interfaces,
	}
	return created
end

--function Container:create_ext_value(id, name, version,
--                                    is_custom,
--                                    is_abstract,
--                                    base_value,
--                                    is_truncatable,
--                                    abstract_base_values,
--                                    supported_interfaces,
--                                    initializers)
--end

--------------------------------------------------------------------------------

function IDLType:update()
	self.type = self
end

--------------------------------------------------------------------------------

local PrimitiveTypes = {
	pk_null       = idl.null,
	pk_void       = idl.void,
	pk_short      = idl.short,
	pk_long       = idl.long,
	pk_longlong   = idl.longlong,
	pk_ushort     = idl.ushort,
	pk_ulong      = idl.ulong,
	pk_ulonglong  = idl.ulonglong,
	pk_float      = idl.float,
	pk_double     = idl.double,
	pk_longdouble = idl.double,
	pk_boolean    = idl.boolean,
	pk_char       = idl.char,
	pk_octet      = idl.octet,
	pk_any        = idl.any,
	pk_TypeCode   = idl.TypeCode,
	pk_string     = idl.string,
	pk_objref     = idl.object,
}

PrimitiveTypes.pk_objref.absolute_name = "CORBA::Object"
PrimitiveDef.def_kind = "dk_Primitive"

function PrimitiveDef:__new(object)
	self = rawnew(self, object)
	IDLType.update(self)
	return self
end

for kind, type in pairs(PrimitiveTypes) do
	PrimitiveDef(type).kind = kind
end

--------------------------------------------------------------------------------

function ObjectRef:__new(object, registry)
	local pk_objref = PrimitiveTypes.pk_objref
	if object.repID ~= pk_objref.repID then
		return registry.repository:lookup_id(object.repID) or
		       assertillegal(object,"Object type, use interface definition instead")
	end
	return pk_objref
end

--------------------------------------------------------------------------------

ArrayDef._type = "array"
ArrayDef.def_kind = "dk_Array"
ArrayDef.definition_fields = {
	length      = { type = "number" },
	elementtype = { type = IDLType  },
}

function ArrayDef:update(new, registry)
	self.length = new.length
	self:_set_element_type_def(new.elementtype, registry)
end

function ArrayDef:_get_element_type() return self.elementtype end

function ArrayDef:_set_element_type_def(type_def, registry)
	local old = self.elementtype
	type_def = self.containing_repository:put(type_def, registry)
	if self.element_type_def then
		self:nowatch(self.element_type_def, "elementtype")
	end
	self.element_type_def = type_def
	self.elementtype = type_def.type
	self:watch(self.element_type_def, "elementtype")
	if self.elementtype ~= old then self:notify("elementtype") end
end

--------------------------------------------------------------------------------

SequenceDef._type = "sequence"
SequenceDef.def_kind = "dk_Sequence"
SequenceDef.maxlength = 0
SequenceDef.definition_fields = {
	maxlength   = { type = "number", optional = true },
	elementtype = { type = IDLType  },
}

function SequenceDef:update(new, registry)
	self.maxlength = new.maxlength
	self:_set_element_type_def(new.elementtype, registry)
end

SequenceDef._get_element_type = ArrayDef._get_element_type
SequenceDef._set_element_type_def = ArrayDef._set_element_type_def
function SequenceDef:_set_bound(value) self.maxlength = value end
function SequenceDef:_get_bound() return self.maxlength end

--------------------------------------------------------------------------------

StringDef._type = "string"
StringDef.def_kind = "dk_String"
StringDef.maxlength = 0
StringDef.definition_fields = {
	maxlength = { type = "number", optional = true },
}
StringDef._set_bound = SequenceDef._set_bound
StringDef._get_bound = SequenceDef._get_bound

function StringDef:update(new)
	self.maxlength = new.maxlength
end

--------------------------------------------------------------------------------

function MemberDef:move(new_container, new_name, new_version)
	local name = self.name
	local container = self.defined_in
	Contained.move(self, new_container, new_name, new_version)
	if container then container:nowatch(self, name) end
	self.defined_in:watch(self, self.name)
end

--------------------------------------------------------------------------------

AttributeDef._type = "attribute"
AttributeDef.def_kind = "dk_Attribute"
AttributeDef.definition_fields = {
	defined_in = { type = Container, optional = true },
	readonly   = { type = "boolean", optional = true },
	type       = { type = IDLType },
}

function AttributeDef:update(new, registry)
	self:_set_mode(new.readonly and "ATTR_READONLY" or "ATTR_NORMAL")
	self:_set_type_def(new.type, registry)
end

function AttributeDef:_set_mode(value)
	local old = self.readonly
	self.mode = value
	self.readonly = (value == "ATTR_READONLY")
	if self.readonly ~= old then self:notify("readonly") end
end

function AttributeDef:_set_type_def(type_def, registry)
	local old = self.type
	type_def = self.containing_repository:put(type_def, registry)
	if self.type_def then
		self:nowatch(self.type_def, "type")
	end
	self.type_def = type_def
	self.type = type_def.type
	self:watch(self.type_def, "type")
	if self.type ~= old then self:notify("type") end
end

function AttributeDef:get_description()
	return setmetatable({
		type = self.type,
		mode = self.mode,
	}, iridl.AttributeDescription)
end

--------------------------------------------------------------------------------

OperationDef._type = "operation"
OperationDef.def_kind = "dk_Operation"
OperationDef.contexts = Empty
OperationDef.parameters = Empty
OperationDef.inputs = Empty
OperationDef.outputs = Empty
OperationDef.exceptions = Empty
OperationDef.result = idl.void
OperationDef.result_def = idl.void
OperationDef.definition_fields = {
	defined_in = { type = Container   , optional = true },
	oneway     = { type = "boolean"   , optional = true },
	contexts   = { type = "table"     , optional = true },
	exceptions = { type = ExceptionDef, optional = true, list = true },
	result     = { type = IDLType     , optional = true },
	parameters = { type = {
		name = { type = "string" },
		type = { type = IDLType },
		mode = { type = "string", optional = true },
	}, optional = true, list = true },
}

function OperationDef:update(new, registry)
	self:_set_mode(new.oneway and "OP_ONEWAY" or "OP_NORMAL")
	if new.exceptions then self:_set_exceptions(new.exceptions, registry) end
	if new.result then self:_set_result_def(new.result, registry) end
	if new.parameters then self:_set_params(new.parameters, registry) end
	self.contexts = new.contexts
end

function OperationDef:_set_mode(value)
	local old = self.oneway
	self.mode = value
	self.oneway = (value == "OP_ONEWAY")
	if self.oneway ~= old then self:notify("oneway") end
end

function OperationDef:_set_result_def(type_def, registry)
	type_def = self.containing_repository:put(type_def, registry)
	local current = self.result
	local newval = type_def.type
	if current ~= newval then
		if self.result_def then
			self:nowatch(self.result_def, "result")
		end
		self.result_def = type_def
		self.result = newval
		self:watch(self.result_def, "result")
		if current == void then
			if self.outputs == Empty then
				self.outputs = { newval }
			else
				self.outputs = { newval, unpack(self.outputs) }
			end
		elseif newval == void then
			self.outputs = { unpack(self.outputs, 2) }
		else
			self.outputs = { newval, unpack(self.outputs, 2) }
		end
		self:notify("result")
	end
end

function OperationDef:_get_params() return self.parameters end
function OperationDef:_set_params(parameters, registry)
	local inputs = {}
	local outputs = {}
	if self.result ~= void then
		outputs[#outputs+1] = self.result
	end
	for index, param in ipairs(parameters) do
		param.type_def = self.containing_repository:put(param, registry)
		param.type = param.type_def.type
		param.mode = param.mode or "PARAM_IN"
		if param.mode == "PARAM_IN" then
			inputs[#inputs+1] = param.type
		elseif param.mode == "PARAM_OUT" then
			outputs[#outputs+1] = param.type
		elseif param.mode == "PARAM_INOUT" then
			inputs[#inputs+1] = param.type
			outputs[#outputs+1] = param.type
		else
			assertillegal(param.mode, "operation parameter mode")
		end
	end
	for index, param in ipairs(self.parameters) do
		self:nowatch(param.type_def, "parameter "..index)
	end
	self.parameters = parameters
	self.inputs = inputs
	self.outputs = outputs
	for index, param in ipairs(self.parameters) do
		self:watch(param.type_def, "parameter "..index)
	end
	self:notify("parameters")
end

function OperationDef:_set_exceptions(exceptions, registry)
	for index, except in ipairs(exceptions) do
		except = self.containing_repository:put(except:get_description(), registry)
		exceptions[index] = except
		exceptions[except.repID] = except
	end
	for index, except in ipairs(self.exceptions) do
		self:nowatch(except, "exception "..index)
	end
	self.exceptions = exceptions
	for index, except in ipairs(self.exceptions) do
		self:watch(except, "exception "..index)
	end
	self:notify("exceptions")
end

function OperationDef:get_description()
	local exceptions = {}
	for _, except in ipairs(self.exceptions) do
		exceptions[#exceptions+1] = except:describe().value
	end
	return setmetatable({
		result     = self.result,
		mode       = self.mode,
		contexts   = self.contexts,
		parameters = self.parameters,
		exceptions = exceptions,
	}, iridl.OperationDescription)
end

--------------------------------------------------------------------------------

ValueMemberDef._type = "valuemember"
ValueMemberDef.def_kind = "dk_ValueMember"
ValueMemberDef.access = 0
ValueMemberDef.definition_fields = {
	defined_in = { type = ValueDef, optional = true },
	type       = { type = IDLType },
	access     = { type = "number" },
}

function ValueMemberDef:update(new, registry)
	self.access = new.access
	self:_set_type_def(new.type, registry)
end

function ValueMemberDef:move(new_container, new_name, new_version)
	local old_container = self.defined_in
	if old_container and old_container ~= self.containing_repository then
		local members = old_container.members
		for index, member in ipairs(members) do
			if member == self then
				remove(members, index)
				break
			end
		end
	end
	MemberDef.move(self, new_container, new_name, new_version)
	if new_container._type == "valuetype" then
		local members = new_container.members
		members[#members+1] = self
	elseif new_container ~= self.containing_repository then
		assertillegal(new_container, "ValueMemberDef container", "BAD_PARAM", 4)
	end
end

function ValueMemberDef:get_description()
	return setmetatable({
		type = self.type,
		type_def = self.type_def,
		access = self.access,
	}, iridl.ValueMember)
end

function ValueMemberDef:_set_type_def(type_def, registry)
	local old = self.type
	type_def = self.containing_repository:put(type_def, registry)
	self.type_def = type_def
	self.type = type_def.type
	if self.type ~= old then self:notify("type") end
end

--------------------------------------------------------------------------------

ConstantDef._type = "const"
ConstantDef.def_kind = "dk_Constant"
ConstantDef.definition_fields = {
	type = { type = IDLType },
	val  = { type = nil },
}

function ConstantDef:get_description()
	return setmetatable({
		type = self.type,
		value = self.value,
	}, iridl.ConstantDescription)
end

function ConstantDef:update(new, registry)
	self:_set_type(new.type, registry)
	self:_set_value({_anyval=new.val, _anytype=new.type}, registry)
end

function ConstantDef:_set_type(type_def, registry)
	local old = self.type
	type_def = self.containing_repository:put(type_def, registry)
	if self.type_def then
		self:nowatch(self.type_def, "type")
	end
	self.type_def = type_def
	self.type = type_def.type
	self:watch(self.type_def, "type")
	if self.type ~= old then self:notify("type") end
end

function ConstantDef:_set_value(value, registry)
	self.value = value
	self.val = value._anyval
end

--------------------------------------------------------------------------------

TypedefDef._type = "typedef"
TypedefDef.def_kind = "dk_Typedef"

function TypedefDef:get_description()
	return setmetatable({ type = self.type }, iridl.TypeDescription)
end

--------------------------------------------------------------------------------

StructDef._type = "struct"
StructDef.def_kind = "dk_Struct"
StructDef.fields = Empty
StructDef.definition_fields = {
	fields = {
		type = {
			name = { type = "string" },
			type = { type = IDLType },
		},
		optional = true,
		list = true,
	},
}

function StructDef:update(new, registry)
	if new.fields then self:_set_members(new.fields, registry) end
end

function StructDef:_get_members() return self.fields end
function StructDef:_set_members(members, registry)
	for index, field in ipairs(members) do
		field.type_def = self.containing_repository:put(field, registry)
		field.type = field.type_def.type
	end
	for index, field in ipairs(self.fields) do
		self:nowatch(field.type_def, "field "..field.name)
	end
	self.fields = members
	for index, field in ipairs(self.fields) do
		self:watch(field.type_def, "field "..field.name)
	end
	self:notify("fields")
end

--------------------------------------------------------------------------------

UnionDef._type = "union"
UnionDef.def_kind = "dk_Union"
UnionDef.default = -1
UnionDef.options = Empty
UnionDef.members = Empty
UnionDef.definition_fields = {
	switch  = { type = IDLType },
	default = { type = "number", optional = true },
	options = { type = {
		label = { type = nil },
		name  = { type = "string" },
		type  = { type = IDLType },
	}, optional = true, list = true },
}

function UnionDef:update(new, registry)
	self:_set_discriminator_type_def(new.switch, registry)
	
	if new.options then
		for _, option in ipairs(new.options) do
			option.label = {
				_anyval = option.label,
				_anytype = self.switch,
			}
		end
		self:_set_members(new.options)
	end
	
	function self.__index(union, field)
		if rawget(union, "_switch") == self.selector[field] then
			return rawget(union, "_value")
		end
	end
	function self.__newindex(union, field, value)
		local label = self.selector[field]
		if label then
			rawset(union, "_switch", label)
			rawset(union, "_value", value)
			rawset(union, "_field", field)
		end
	end
end

function UnionDef:_get_discriminator_type() return self.switch end

function UnionDef:_set_discriminator_type_def(type_def, registry)
	local old = self.switch
	type_def = self.containing_repository:put(type_def, registry)
	if self.discriminator_type_def then
		self:nowatch(self.discriminator_type_def, "switch")
	end
	self.discriminator_type_def = type_def
	self.switch = type_def.type
	self:watch(self.discriminator_type_def, "switch")
	if self.switch ~= old then self:notify("switch") end
end

function UnionDef:_set_members(members, registry)
	local options = {}
	local selector = {}
	local selection = {}
	for index, member in ipairs(members) do
		member.type_def = self.containing_repository:put(member, registry)
		member.type = member.type_def.type
		local option = {
			label = member.label._anyval,
			name = member.name,
			type = member.type,
			type_def = member.type_def,
		}
		options[index] = option
		selector[option.name] = option.label
		selection[option.label] = option
	end
	for index, member in ipairs(self.members) do
		self:nowatch(member.type_def, "option "..index)
	end
	self.options = options
	self.selector = selector
	self.selection = selection
	self.members = members
	for index, member in ipairs(self.members) do
		self:watch(member.type_def, "option "..index)
	end
	self:notify("options")
end

--------------------------------------------------------------------------------

EnumDef._type = "enum"
EnumDef.def_kind = "dk_Enum"
EnumDef.definition_fields = {
	enumvalues = { type = "string", list = true },
}

function EnumDef:update(new)
	self:_set_members(new.enumvalues)
end

function EnumDef:_get_members() return self.enumvalues end
function EnumDef:_set_members(members)
	local labelvalue = {}
	for index, label in ipairs(members) do
		labelvalue[label] = index - 1
	end
	self.enumvalues = members
	self.labelvalue = labelvalue
	self:notify("enumvalues")
end

--------------------------------------------------------------------------------

AliasDef._type = "typedef"
AliasDef.def_kind = "dk_Alias"
AliasDef.definition_fields = {
	original_type = { type = IDLType },
}

function AliasDef:update(new, registry)
	self:_set_original_type_def(new.original_type, registry)
end

function AliasDef:_set_original_type_def(type_def, registry)
	local old = self.type
	type_def = self.containing_repository:put(type_def, registry)
	self.original_type_def = type_def
	self.original_type = type_def.type
	if self.type ~= old then self:notify("type") end
end

--------------------------------------------------------------------------------

ValueBoxDef._type = "valuebox"
ValueBoxDef.def_kind = "dk_ValueBox"
ValueBoxDef.definition_fields = AliasDef.definition_fields
ValueBoxDef.update = AliasDef.update
ValueBoxDef._set_original_type_def = AliasDef._set_original_type_def

--------------------------------------------------------------------------------

Repository.def_kind = "dk_Repository"
Repository.repID = ""
Repository.absolute_name = ""

function Repository:__new(object)
	self = rawnew(self, object)
	self.containing_repository = self
	self.definition_map = self.definition_map or {}
	Container.update(self, self)
	return self
end

--
-- Read interface
--

function Repository:lookup_id(search_id)
	return self.definition_map[search_id]
end

--function Repository:get_canonical_typecode(tc)
--end

function Repository:get_primitive(kind)
	return PrimitiveTypes[kind]
end

--
-- Write interface
--
--
--function Repository:create_string(bound)
--end
--
--function Repository:create_wstring(bound)
--end

function Repository:create_sequence(bound, element_type)
	local created = SequenceDef{ containing_repository=self.containing_repository }
	created:update{
		elementtype = element_type.type,
		maxlength = bound,
	}
	return created
end

function Repository:create_array(length, element_type)
	local created = ArrayDef{ containing_repository=self.containing_repository }
	created:update{
		elementtype = element_type.type,
		length = length,
	}
	return created
end

--function Repository:create_fixed(digits, scale)
--end

--------------------------------------------------------------------------------

--function ExtAttributeDef:describe_attribute()
--end

--------------------------------------------------------------------------------

ModuleDef._type = "module"
ModuleDef.def_kind = "dk_Module"
ModuleDef.expandable = true

function ModuleDef:get_description()
	return setmetatable({}, iridl.ModuleDescription)
end

--------------------------------------------------------------------------------

ExceptionDef._type = "except"
ExceptionDef.def_kind = "dk_Exception"
ExceptionDef.members = Empty
ExceptionDef.definition_fields = {
	members = { type = {
		name = { type = "string" },
		type = { type = IDLType },
	}, optional = true, list = true },
}

function ExceptionDef:update(new, registry)
	self.type = self
	if new.members then self:_set_members(new.members, registry) end
end

function ExceptionDef:_set_members(members, registry)
	for index, member in ipairs(members) do
		member.type_def = self.containing_repository:put(member, registry)
		member.type = member.type_def.type
	end
	for index, member in ipairs(self.members) do
		self:nowatch(member.type_def, "member "..member.name)
	end
	self.members = members
	for index, member in ipairs(self.members) do
		self:watch(member.type_def, "member "..member.name)
	end
	self:notify("members")
end

function ExceptionDef:get_description()
	return setmetatable({ type = self }, iridl.ExceptionDescription)
end

--------------------------------------------------------------------------------

local function changeinheritance(container, old, new, type)
	local actual = {}
	for index, base in ipairs(new) do
		if type then
			actual[index] = asserttype(base, type, "inherited definition",
			                            "BAD_PARAM", 4)
		end
		for _, contained in ipairs(container.definitions) do
			if #base:lookup_name(contained.name, -1, "dk_All", false) > 0 then
				assertillegal(base,
				              "inheritance, member '"..
				              contained.name..
				              "' override not allowed",
				              "BAD_PARAM", 5)
			end
		end
	end
	for index, base in ipairs(old) do
		container:nowatch(base, "base "..index)
	end
	for index, base in ipairs(new) do
		container:watch(base, "base "..index)
	end
	container:notify("inheritance", type)
	return new, actual
end

--------------------------------------------------------------------------------

InterfaceDef._type = "interface"
InterfaceDef.def_kind = "dk_Interface"
InterfaceDef.base_interfaces = Empty
InterfaceDef.definition_fields = {
	base_interfaces = { type = InterfaceDef, optional = true, list = true },
}

InterfaceDef.hierarchy = idl.basesof

function InterfaceDef:update(new)
	if new.base_interfaces then
		self:_set_base_interfaces(new.base_interfaces)
	end
end

function InterfaceDef:get_description()
	local base_interfaces = {}
	for index, base in ipairs(self.base_interfaces) do
		base_interfaces[index] = base.repID
	end
	return setmetatable({ base_interfaces = base_interfaces },
	                    iridl.InterfaceDescription)
end

--
-- Read interface
--

function InterfaceDef:is_a(interface_id)
	if interface_id == PrimitiveTypes.pk_objref.repID then return true end
	if interface_id == self.repID then return true end
	for _, base in ipairs(self.inherited) do
		if base:is_a(interface_id) then return true end
	end
	return false
end

local FullIfaceDescription = iridl.InterfaceDef.definitions.FullInterfaceDescription
function InterfaceDef:describe_interface()
	local operations = {}
	local attributes = {}
	local base_interfaces = {}
	for index, base in ipairs(self.base_interfaces) do
		base_interfaces[index] = base.repID
	end
	for base in self:hierarchy() do
		for _, contained in ipairs(base.definitions) do
			if contained._type == "attribute" then
				attributes[#attributes+1] = contained:describe().value
			elseif contained._type == "operation" then
				operations[#operations+1] = contained:describe().value
			end
		end
	end
	return setmetatable({
		name = self.name,
		id = self.id,
		defined_in = self.defined_in.repID,
		version = self.version,
		base_interfaces = base_interfaces,
		type = self,
		operations = operations,
		attributes = attributes,
	}, FullIfaceDescription)
end

--
-- Write interface
--

function InterfaceDef:_set_base_interfaces(bases)
	self.base_interfaces, self.inherited = changeinheritance(
		self, self.base_interfaces, bases, "idl interface|abstract_interface")
end

function InterfaceDef:create_attribute(id, name, version, type, mode)
	local created = AttributeDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,
		
		type = type.type,
		readonly = (mode == "ATTR_READONLY"),
	}
	return created
end

function InterfaceDef:create_operation(id, name, version,
                                       result, mode, params,
                                       exceptions, contexts)
	local created = OperationDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
		
		repID = id,
		name = name,
		version = version,
		
		result = result.type,
		
		parameters = params,
		exceptions = exceptions,
		contexts = contexts,
		
		oneway = (mode == "OP_ONEWAY"),
	}
	return created
end

--------------------------------------------------------------------------------

--
-- Write interface
--

AbstractInterfaceDef._type = "abstract_interface"
AbstractInterfaceDef.def_kind = "dk_AbstractInterface"
AbstractInterfaceDef.definition_fields = {
	base_interfaces = { type = AbstractInterfaceDef, optional = true, list = true },
}
function AbstractInterfaceDef:_set_base_interfaces(bases)
	self.base_interfaces, self.inherited = changeinheritance(
		self, self.base_interfaces, bases, "idl abstract_interface")
end

--------------------------------------------------------------------------------

--
-- Write interface
--

LocalInterfaceDef._type = "local_interface"
LocalInterfaceDef.def_kind = "dk_LocalInterface"
function LocalInterfaceDef:_set_base_interfaces(bases)
	self.base_interfaces, self.inherited = changeinheritance(
		self, self.base_interfaces, bases, "idl interface|local_interface")
end

--------------------------------------------------------------------------------

--
-- Read interface
--
--
--function InterfaceAttrExtension:describe_ext_interface()
--end

--
-- Write interface
--
--
--function InterfaceAttrExtension:create_ext_attribute()
--end

--------------------------------------------------------------------------------

ValueDef._type = "valuetype"
ValueDef.def_kind = "dk_Value"
ValueDef.supported_interfaces = Empty
ValueDef.abstract_base_values = Empty
ValueDef.initializers = Empty
ValueDef.kind = 0
ValueDef.definition_fields = {
	kind                 = { type = "number", optional = true },
	is_abstract          = { type = "boolean", optional = true },
	is_custom            = { type = "boolean", optional = true },
	is_truncatable       = { type = "boolean", optional = true },
	base_value           = { type = IDLType, optional = true },
	abstract_base_values = { type = ValueDef, optional = true, list = true },
	supported_interfaces = { type = InterfaceDef, optional = true, list = true },
	initializers = {
		type = {
			name = { type = "string" },
			members = {
				type = {
					name = { type = "string" },
					type = { type = IDLType },
				},
				list = true,
			},
		},
		optional = true,
		list = true,
	},
}

function ValueDef:update(new)
	self.members = {}
	if new.kind then
		self:_set_is_custom(new.kind==1)
		self:_set_is_abstract(new.kind==2)
		self:_set_is_truncatable(new.kind==3)
	else
		self:_set_is_custom(new.is_custom)
		self:_set_is_abstract(new.is_abstract)
		self:_set_is_truncatable(new.is_truncatable)
	end
	if new.base_value == null then
		self:_set_base_value(nil)
	else
		self:_set_base_value(new.base_value)
	end
	if new.abstract_base_values then
		self:_set_abstract_base_values(new.abstract_base_values)
	end
	if new.supported_interfaces then
		self:_set_supported_interfaces(new.supported_interfaces)
	end
end

function ValueDef:get_description()
	local base_value = self.base_value
	if base_value == null then
		base_value = ValueBase
	end
	local abstract_base_values = {}
	for index, base in ipairs(self.abstract_base_values) do
		abstract_base_values[index] = base.repID
	end
	local supported_interfaces = {}
	for index, iface in ipairs(self.supported_interfaces) do
		supported_interfaces[index] = iface.repID
	end
	return setmetatable({
		is_abstract          = self.is_abstract,
		is_custom            = self.is_custom,
		is_truncatable       = self.is_truncatable,
		base_value           = base_value.repID,
		abstract_base_values = abstract_base_values,
		supported_interfaces = supported_interfaces,
	}, iridl.ValueDescription)
end

--
-- Read interface
--

function ValueDef:is_a(id)
	if id == self.repID then return true end
	local base = self.inherited
	if base ~= null and base:is_a(id) then return true end
	for _, base in ipairs(self.abstract_base_values) do
		if base:is_a(id) then return true end
	end
	for _, iface in ipairs(self.supported_interfaces) do
		if iface:is_a(id) then return true end
	end
	return false
end

local FullValueDescription = iridl.ValueDef.definitions.FullValueDescription
function ValueDef:describe_value()
	local operations = {}
	local attributes = {}
	local members = {}
	for base in self:hierarchy() do
		for _, contained in ipairs(base.definitions) do
			if contained._type == "attribute" then
				attributes[#attributes+1] = contained:describe().value
			elseif contained._type == "operation" then
				operations[#operations+1] = contained:describe().value
			elseif contained._type == "valuemember" then
				members[#members+1] = contained:describe().value
			end
		end
	end
	local desc = self:get_description()
	desc.name = self.name
	desc.id = self.id
	desc.defined_in = self.defined_in.repID
	desc.version = self.version
	desc.type = self
	desc.operations = operations
	desc.attributes = attributes
	desc.members = members
	desc.initializers = self.initializers
	return setmetatable(desc, FullValueDescription)
end

--
-- Write interface
--

function ValueDef:_set_is_custom(value)
	self.is_custom = value
	if value then self.kind = 1 end
end

function ValueDef:_set_is_abstract(value)
	self.is_abstract = value
	if value then self.kind = 2 end
end

function ValueDef:_set_is_truncatable(value)
	self.is_truncatable = value
	if value then self.kind = 3 end
end

function ValueDef:_set_supported_interfaces(ifaces)
	self.supported_interfaces = changeinheritance(
		self, self.supported_interfaces, ifaces, "idl interface")
end

function ValueDef:_set_base_value(base)
	if base then
		local actual = asserttype(base, "idl valuetype", "base value",
		                           "BAD_PARAM", 4)
		if actual.is_abstract then
			assertillegal(actual, "invalid base value", "BAD_PARAM", 4)
		end
		local list = changeinheritance(
			self, {self.base_value}, {base}, "idl valuetype")
		self.inherited = actual
		base = list[1]
	else
		base = null
	end
	self.base_value = base
end

function ValueDef:_get_base_value()
	local base = self.base_value
	if base == null then base = nil end
	return base
end

function ValueDef:_set_abstract_base_values(bases)
	for i = 1, #bases do
		local base = bases[i]
		if not base.is_abstract then
			assertillegal(base, "invalid abstract base value", "BAD_PARAM", 4)
		end
	end
	self.abstract_base_values, self.inherited = changeinheritance(
		self, self.abstract_base_values, bases, "idl valuetype")
end

function ValueDef:create_value_member(id, name, version, type, access)
	local created = ValueMemberDef{ containing_repository=self.containing_repository }
	created:update{
		defined_in = self,
	
		repID = id,
		name = name,
		version = version,
	
		type = type.type,
		access = access,
	}
	return created
end

ValueDef.create_attribute = InterfaceDef.create_attribute
ValueDef.create_operation = InterfaceDef.create_operation

--------------------------------------------------------------------------------

--
-- Read interface
--
--
--function ExtValueDef:describe_ext_value()
--end

--
-- Write interface
--
--
--function ExtValueDef:create_ext_attribute(id, name, version, type, mode,
--                                          get_exceptions, set_exceptions)
--end


--------------------------------------------------------------------------------

local function getupdate(self, value, name, typespec)                           --[[VERBOSE]] verbose:repository("[attribute ",name,"]")
	if type(typespec) == "string" then
		asserttype(value, typespec, name, "BAD_PARAM")
	elseif type(typespec) == "table" then
		if isclass(typespec) then
			value = self[value]
			local actual = value
			while actual._type=="typedef" and not isinstanceof(actual, typespec) do
				actual = actual.original_type
			end
			if not isinstanceof(actual, typespec) then
				assertillegal(value, name)
			end
		else
			local new = {}
			for name, field in pairs(typespec) do
				local result = value[name]
				if result ~= nil or not field.optional then
					if field.list then
						local new = {}
						for index, value in ipairs(result) do
							new[index] = getupdate(self, value, name, field.type)
						end
						result = new
					else
						result = getupdate(self, result, name, field.type)
					end
				end
				new[name] = result
			end
			value = new
		end
	end
	return value
end

local DefinitionRegistry = class()

function DefinitionRegistry:__new(object)
	self = rawnew(self, object)
	self[PrimitiveTypes.pk_null      ] = PrimitiveTypes.pk_null
	self[PrimitiveTypes.pk_void      ] = PrimitiveTypes.pk_void
	self[PrimitiveTypes.pk_short     ] = PrimitiveTypes.pk_short
	self[PrimitiveTypes.pk_long      ] = PrimitiveTypes.pk_long
	self[PrimitiveTypes.pk_longlong  ] = PrimitiveTypes.pk_longlong
	self[PrimitiveTypes.pk_ushort    ] = PrimitiveTypes.pk_ushort
	self[PrimitiveTypes.pk_ulong     ] = PrimitiveTypes.pk_ulong
	self[PrimitiveTypes.pk_ulonglong ] = PrimitiveTypes.pk_ulonglong
	self[PrimitiveTypes.pk_float     ] = PrimitiveTypes.pk_float
	self[PrimitiveTypes.pk_double    ] = PrimitiveTypes.pk_double
	self[PrimitiveTypes.pk_longdouble] = PrimitiveTypes.pk_longdouble
	self[PrimitiveTypes.pk_boolean   ] = PrimitiveTypes.pk_boolean
	self[PrimitiveTypes.pk_char      ] = PrimitiveTypes.pk_char
	self[PrimitiveTypes.pk_octet     ] = PrimitiveTypes.pk_octet
	self[PrimitiveTypes.pk_any       ] = PrimitiveTypes.pk_any
	self[PrimitiveTypes.pk_TypeCode  ] = PrimitiveTypes.pk_TypeCode
	self[PrimitiveTypes.pk_string    ] = PrimitiveTypes.pk_string
	self[PrimitiveTypes.pk_objref    ] = PrimitiveTypes.pk_objref
	self[self.repository             ] = self.repository
	return self
end

local Registry -- forward declaration of class

function DefinitionRegistry:__index(definition)
	if definition then
		local repository = self.repository
		local class = repository.Classes[definition._type]
		
		--<PROBLEM WITH LUAIDL>
		if class == InterfaceDef then
			if definition.abstract then
				class = AbstractInterfaceDef
			elseif definition["local"] then
				class = LocalInterfaceDef
			end
		end
		--<\PROBLEM WITH LUAIDL>
		
		local result
		if class then
			result = repository:lookup_id(definition.repID)
			if definition ~= result then                                              --[[VERBOSE]] verbose:repository(true, definition._type," ",definition.repID or definition.name)
				result = class(result)
				result.containing_repository = repository
				self[definition] = result -- to avoid loops in cycles during 'getupdate'
				self[result] = result
				for class in topdown(class) do                                       --[[VERBOSE]] verbose:repository("[",class.__type,"]")
					local update = getmember(class, "update")
					if update then
						local fields = getmember(class, "definition_fields")
						local new = fields and getupdate(self, definition, "object", fields)
						update(result, new, self)
					end
				end                                                                     --[[VERBOSE]] verbose:repository(false)
				if isinstanceof(result, Container) then
					for _, contained in ipairs(definition.definitions) do
						getupdate(self, contained, "contained", Contained)
					end
				end
			end
		elseif getclass(definition) == Registry then
			result = self.repository
		end
		self[definition] = result
		self[result] = result
		return result
	end
end

--------------------------------------------------------------------------------
-- Implementation --------------------------------------------------------------

Registry = class({
	Registry = DefinitionRegistry,
	Classes = {
		const              = ConstantDef,
		struct             = StructDef,
		union              = UnionDef,
		enum               = EnumDef,
		sequence           = SequenceDef,
		array              = ArrayDef,
		string             = StringDef,
		typedef            = AliasDef,
		except             = ExceptionDef,
		module             = ModuleDef,
		interface          = InterfaceDef,
		abstract_interface = AbstractInterfaceDef,
		local_interface    = LocalInterfaceDef,
		attribute          = AttributeDef,
		operation          = OperationDef,
		valuetype          = ValueDef,
		valuemember        = ValueMemberDef,
		valuebox           = ValueBoxDef,
		Object             = ObjectRef,
	},
}, Repository)

function Registry:put(definition, registry)
	definition = definition.type or definition
	registry = registry or self.Registry{ repository = self }
	return registry[definition]
end

function Registry:register(...)
	local registry = self.Registry{ repository = self }
	local results = {}
	local count = select("#", ...)
	for i = 1, count do
		local definition = select(i, ...)
		asserttype(definition, "table", "IR object definition", "BAD_PARAM")
		results[i] = registry[definition]
	end
	return unpack(results, 1, count)
end

local TypeCodesOfInterface = {
	Object = true,
	abstract_interface = true,
}
function Registry:resolve(typeref, servant)
	local luatype = type(typeref)
	local result, errmsg
	if luatype == "table" then
		if typeref._type == "interface" then
			result, errmsg = self:register(typeref)
		elseif TypeCodesOfInterface[typeref._type] then
			typeref, luatype = typeref.repID, "string"
		end
	end
	if luatype == "string" then
		result = self:lookup_id(typeref) or self:lookup(typeref)
		if not result then
			local pk_objref = PrimitiveTypes.pk_objref
			if typeref == pk_objref.repID or typeref == pk_objref.absolute_name then
				result, errmsg = PrimitiveTypes.pk_objref
			else
				errmsg = Exception{
					"unknown interface (got $interface_id)",
					error = "badtype",
					interface_id = typeref,
				}
			end
		end
	elseif result == nil then
		result, errmsg = nil, Exception{
			"illegal IDL type (got $idltype)",
			error = "badtype",
			idltype = typeref,
		}
	end
	if result ~= nil and servant ~= nil then
		if result==PrimitiveTypes.pk_objref
		or result._type=="abstract_interface" then
			result, errmsg = nil, Exception{
				"interface $type is illegal for servants",
				type = result.absolute_name,
				error = "badtype",
			}
		end
	end
	return result, errmsg
end

return Registry
