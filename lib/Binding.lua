local createSignal = require(script.Parent.createSignal)
local Symbol = require(script.Parent.Symbol)
local Type = require(script.Parent.Type)

--[[
	Default mapping function used for non-mapped bindings
]]
local function identity(value)
	return value
end

local Binding = {}

--[[
	Set of keys for fields that are internal to Bindings
]]
local InternalData = Symbol.named("InternalData")

local bindingPrototype = {}
bindingPrototype.__index = bindingPrototype
bindingPrototype.__tostring = function(self)
	return ("RoactBinding(%s)"):format(tostring(self[InternalData].value))
end

--[[
	Get the current value from a binding
]]
function bindingPrototype:getValue()
	local internalData = self[InternalData]

	return internalData.value
end

--[[
	Creates a new binding from this one with the given mapping.
]]
function bindingPrototype:map(valueTransform)
	local binding = Binding.create(valueTransform(self:getValue()))

	binding[InternalData].valueTransform = valueTransform
	-- Subscribe to upstream binding
	binding[InternalData].upstreamDisconnect = Binding.subscribe(self, function(value)
		Binding.update(binding, value)
	end)

	return binding
end

--[[
	Update a binding's value. This is only accessible by Roact.
]]
function Binding.update(binding, newValue)
	local internalData = binding[InternalData]

	newValue = internalData.valueTransform(newValue)

	internalData.value = newValue
	internalData.changeSignal:fire(newValue)
end

--[[
	Subscribe to a binding's change signal. This is only accessible by Roact.
]]
function Binding.subscribe(binding, handler)
	local internalData = binding[InternalData]

	local disconnect = internalData.changeSignal:subscribe(handler)
	internalData.subscriberCount = internalData.subscriberCount + 1

	--[[
		If we're subscribed to an upstream binding (from calling `map`), we need
		to make sure to clean up that subscription in our own disconnect function
	]]
	if internalData.upstreamDisconnect ~= nil then
		local disconnected = false

		return function()
			if disconnected then
				return
			end

			--[[
				Disconnect from upstream connection
			]]
			if internalData.upstreamDisconnect ~= nil then
				internalData.upstreamDisconnect()
				--[[
					We need to nil-ify this so that any other subscriptions won't also
					try to disconnect it again later
				]]
				internalData.upstreamDisconnect = nil
			end

			disconnect()
			disconnected = true
		end
	else
		return disconnect
	end
end

--[[
	Create a new binding object with the given starting value. This
	function will be exposed to users of Roact.
]]
function Binding.create(initialValue)
	local binding = {
		[Type] = Type.Binding,

		[InternalData] = {
			value = initialValue,
			changeSignal = createSignal(),
			subscriberCount = 0,

			valueTransform = identity,
			upstreamDisconnect = nil,
		},
	}

	setmetatable(binding, bindingPrototype)

	local setter = function(newValue)
		Binding.update(binding, newValue)
	end

	return binding, setter
end

return Binding