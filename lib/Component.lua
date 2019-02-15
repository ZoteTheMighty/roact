local assign = require(script.Parent.assign)
local Type = require(script.Parent.Type)
local Symbol = require(script.Parent.Symbol)
local invalidSetStateMessages = require(script.Parent.invalidSetStateMessages)

local InternalData = Symbol.named("InternalData")

local SetStateStatus = {
	-- setState calls will accumulate a queue of pending state updates that will
	-- be resolved together
	Suspended = "Suspended",

	-- setState will resolve as soon as it's invoked
	Enabled = "Enabled",

	-- setState is not allowed, and will throw an error
	DisallowedRendering = "DisallowedRendering",

	-- setState is not allowed, and will throw an error
	DisallowedUnmounting = "DisallowedUnmounting",
}

local componentMissingRenderMessage = [[
The component %q is missing the `render` method.
`render` must be defined when creating a Roact component!]]

local componentClassMetatable = {}

function componentClassMetatable:__tostring()
	return self.__componentName
end

local Component = {}
setmetatable(Component, componentClassMetatable)

Component[Type] = Type.StatefulComponentClass
Component.__index = Component
Component.__componentName = "Component"

--[[
	A method called by consumers of Roact to create a new component class.
	Components can not be extended beyond this point, with the exception of
	PureComponent.
]]
function Component:extend(name)
	assert(Type.of(self) == Type.StatefulComponentClass)
	assert(typeof(name) == "string")

	local class = {}

	for key, value in pairs(self) do
		-- Roact opts to make consumers use composition over inheritance, which
		-- lines up with React.
		-- https://reactjs.org/docs/composition-vs-inheritance.html
		if key ~= "extend" then
			class[key] = value
		end
	end

	class[Type] = Type.StatefulComponentClass
	class.__index = class
	class.__componentName = name

	setmetatable(class, componentClassMetatable)

	return class
end

function Component:__resolveStateUpdate(targetState, mapState)
	assert(Type.of(self) == Type.StatefulComponentInstance)

	local partialState

	if typeof(mapState) == "function" then
		partialState = mapState(self.state, self.props)

		if partialState == nil then
			return nil
		end
	elseif typeof(mapState) == "table" then
		partialState = mapState
	else
		error("Invalid argument to setState, expected function or table", 2)
	end

	return assign({}, targetState, partialState)
end

function Component:setState(mapState)
	assert(Type.of(self) == Type.StatefulComponentInstance)

	local internalData = self[InternalData]

	-- This value will be set when we're in a place that `setState` should not
	-- be used. It will be set to the name of a message to display to the user.
	if internalData.setStateStatus == SetStateStatus.DisallowedRendering
		or internalData.setStateStatus == SetStateStatus.DisallowedUnmounting then
		-- TODO: real error message here
		local messageTemplate = internalData.setStateStatus

		local message = messageTemplate:format(tostring(internalData.componentClass))

		error(message, 2)
	elseif internalData.setStateStatus == SetStateStatus.Suspended then
		local targetState

		if internalData.pendingStateUpdate == nil then
			targetState = self.state
		else
			targetState = internalData.pendingStateUpdate
		end

		local stateUpdate = self:__resolveStateUpdate(targetState, mapState)

		if stateUpdate ~= nil then
			internalData.pendingStateUpdate = stateUpdate
		end

		return
	end

	local targetState = internalData.pendingStateUpdate or self.state

	local newState = self:__resolveStateUpdate(targetState, mapState)

	-- If `setState` is called in `init`, we can skip triggering an update!
	if internalData.setStateShouldSkipUpdate then
		self.state = newState
	else
		if newState ~= nil then
			self:__update(nil, newState)
		end
	end
end

--[[
	Returns the stack trace of where the element was created that this component
	instance's properties are based on.

	Intended to be used primarily by diagnostic tools.
]]
function Component:getElementTraceback()
	return self[InternalData].virtualNode.currentElement.source
end

--[[
	Returns a snapshot of this component given the current props and state. Must
	be overridden by consumers of Roact and should be a pure function with
	regards to props and state.

	TODO: Accept props and state as arguments.
]]
function Component:render()
	local internalData = self[InternalData]

	local message = componentMissingRenderMessage:format(
		tostring(internalData.componentClass)
	)

	error(message, 0)
end

--[[
	An internal method used by the reconciler to construct a new component
	instance and attach it to the given virtualNode.
]]
function Component:__mount(reconciler, virtualNode)
	assert(Type.of(self) == Type.StatefulComponentClass)
	assert(reconciler ~= nil)
	assert(Type.of(virtualNode) == Type.VirtualNode)

	local currentElement = virtualNode.currentElement
	local hostParent = virtualNode.hostParent

	-- Contains all the information that we want to keep from consumers of
	-- Roact, or even other parts of the codebase like the reconciler.
	local internalData = {
		reconciler = reconciler,
		virtualNode = virtualNode,
		componentClass = self,

		setStateShouldSkipUpdate = false,
	}

	local instance = {
		[Type] = Type.StatefulComponentInstance,
		[InternalData] = internalData,
	}

	setmetatable(instance, self)

	virtualNode.instance = instance

	local props = currentElement.props

	if self.defaultProps ~= nil then
		props = assign({}, self.defaultProps, props)
	end

	instance.props = props
	instance.state = {}

	if self.getDerivedStateFromProps ~= nil then
		local derivedState = self.getDerivedStateFromProps(instance.props, instance.state)

		if derivedState ~= nil then
			assert(typeof(derivedState) == "table", "getDerivedStateFromProps must return a table!")

			assign(instance.state, derivedState)
		end
	end

	local newContext = assign({}, virtualNode.context)
	instance._context = newContext

	if instance.init ~= nil then
		internalData.setStateShouldSkipUpdate = true
		instance:init(instance.props)
		internalData.setStateShouldSkipUpdate = false
	end

	-- It's possible for init() to redefine _context!
	virtualNode.context = instance._context

	internalData.setStateStatus = SetStateStatus.DisallowedRendering
	local renderResult = instance:render()
	internalData.setStateStatus = SetStateStatus.Suspended

	reconciler.updateVirtualNodeWithRenderResult(virtualNode, hostParent, renderResult)

	if instance.didMount ~= nil then
		instance:didMount()
	end

	internalData.setStateStatus = SetStateStatus.Enabled

	if internalData.pendingStateUpdate ~= nil then
		instance:__update(renderResult, internalData.pendingStateUpdate)
	end

end

--[[
	Internal method used by the reconciler to clean up any resources held by
	this component instance.
]]
function Component:__unmount()
	assert(Type.of(self) == Type.StatefulComponentInstance)

	local internalData = self[InternalData]
	local virtualNode = internalData.virtualNode
	local reconciler = internalData.reconciler

	-- TODO: Set unmounted flag to disallow setState after this point

	if self.willUnmount ~= nil then
		internalData.setStateStatus = SetStateStatus.DisallowedUnmounting
		self:willUnmount()
		internalData.setStateStatus = SetStateStatus.Enabled
	end

	for _, childNode in pairs(virtualNode.children) do
		reconciler.unmountVirtualNode(childNode)
	end
end

--[[
	Internal method used by `setState` and the reconciler to update the
	component instance.

	Both `updatedElement` and `updatedState` are optional and indicate different
	kinds of updates. Both may be supplied to update props and state in a single
	pass, as in the case of a batched update.
]]
function Component:__update(updatedElement, updatedState)
	assert(Type.of(self) == Type.StatefulComponentInstance)
	assert(Type.of(updatedElement) == Type.Element or updatedElement == nil)
	assert(typeof(updatedState) == "table" or updatedState == nil)

	local internalData = self[InternalData]
	local virtualNode = internalData.virtualNode
	local reconciler = internalData.reconciler
	local componentClass = internalData.componentClass

	if internalData.pendingStateUpdate ~= nil then
		local pendingState = internalData.pendingStateUpdate

		local collapsedPendingUpdate = self:__resolveStateUpdate(updatedState, pendingState)

		if collapsedPendingUpdate ~= nil then
			updatedState = collapsedPendingUpdate
		end

		internalData.pendingStateUpdate = nil
	end

	local oldProps = self.props
	local oldState = self.state

	-- These will be updated based on `updatedElement` and `updatedState`
	local newProps = oldProps
	local newState = oldState

	if updatedElement ~= nil then
		newProps = updatedElement.props

		if componentClass.defaultProps ~= nil then
			newProps = assign({}, componentClass.defaultProps, newProps)
		end
	end

	if updatedState ~= nil then
		newState = updatedState
	end

	if componentClass.getDerivedStateFromProps ~= nil then
		local derivedState = componentClass.getDerivedStateFromProps(newProps, newState)

		if derivedState ~= nil then
			assert(typeof(derivedState) == "table", "getDerivedStateFromProps must return a table!")

			newState = assign({}, newState, derivedState)
		end
	end

	-- During shouldUpdate, willUpdate, and render, setState calls are suspended
	internalData.setStateStatus = SetStateStatus.DisallowedRendering
	if self.shouldUpdate ~= nil then
		local continueWithUpdate = self:shouldUpdate(newProps, newState)

		if not continueWithUpdate then
			print("State update aborted")
			return false
		end
	end

	if self.willUpdate ~= nil then
		self:willUpdate(newProps, newState)
	end

	self.props = newProps
	self.state = newState

	local renderResult = virtualNode.instance:render()

	internalData.setStateStatus = SetStateStatus.Suspended

	reconciler.updateVirtualNodeWithRenderResult(virtualNode, virtualNode.hostParent, renderResult)

	if self.didUpdate ~= nil then
		self:didUpdate(oldProps, oldState)
	end

	internalData.setStateStatus = SetStateStatus.Enabled

	if internalData.pendingStateUpdate ~= nil then
		self:__update(nil, nil)
	end

	return true
end

return Component