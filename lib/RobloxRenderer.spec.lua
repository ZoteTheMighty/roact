return function()
	local Binding = require(script.Parent.Binding)
	local createElement = require(script.Parent.createElement)
	local createReconciler = require(script.Parent.createReconciler)
	local createRef = require(script.Parent.createRef)
	local createSpy = require(script.Parent.createSpy)
	local Logging = require(script.Parent.Logging)
	local Portal = require(script.Parent.Portal)
	local Ref = require(script.Parent.PropMarkers.Ref)

	local RobloxRenderer = require(script.Parent.RobloxRenderer)

	local reconciler = createReconciler(RobloxRenderer)

	describe("mountHostNode", function()
		it("should create instances with correct props", function()
			local parent = Instance.new("Folder")
			local value = "Hello!"
			local key = "Some Key"

			local element = createElement("StringValue", {
				Value = value,
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			expect(#parent:GetChildren()).to.equal(1)

			local root = parent:GetChildren()[1]

			expect(root.ClassName).to.equal("StringValue")
			expect(root.Value).to.equal(value)
			expect(root.Name).to.equal(key)
		end)

		it("should create children with correct names and props", function()
			local parent = Instance.new("Folder")
			local rootValue = "Hey there!"
			local childValue = 173
			local key = "Some Key"

			local element = createElement("StringValue", {
				Value = rootValue,
			}, {
				ChildA = createElement("IntValue", {
					Value = childValue,
				}),

				ChildB = createElement("Folder"),
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			expect(#parent:GetChildren()).to.equal(1)

			local root = parent:GetChildren()[1]

			expect(root.ClassName).to.equal("StringValue")
			expect(root.Value).to.equal(rootValue)
			expect(root.Name).to.equal(key)

			expect(#root:GetChildren()).to.equal(2)

			local childA = root.ChildA
			local childB = root.ChildB

			expect(childA).to.be.ok()
			expect(childB).to.be.ok()

			expect(childA.ClassName).to.equal("IntValue")
			expect(childA.Value).to.equal(childValue)

			expect(childB.ClassName).to.equal("Folder")
		end)

		it("should attach Bindings to Roblox properties", function()
			local parent = Instance.new("Folder")
			local key = "Some Key"

			local binding, update = Binding.create(10)
			local element = createElement("IntValue", {
				Value = binding,
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			expect(#parent:GetChildren()).to.equal(1)

			local instance = parent:GetChildren()[1]

			expect(instance.ClassName).to.equal("IntValue")
			expect(instance.Value).to.equal(10)

			update(20)

			expect(instance.Value).to.equal(20)

			RobloxRenderer.unmountHostNode(reconciler, node)
		end)

		it("should connect Binding refs", function()
			local parent = Instance.new("Folder")
			local key = "Some Key"

			local ref = createRef()
			local element = createElement("Frame", {
				[Ref] = ref,
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			expect(#parent:GetChildren()).to.equal(1)

			local instance = parent:GetChildren()[1]

			expect(ref.current).to.be.ok()
			expect(ref.current).to.equal(instance)

			RobloxRenderer.unmountHostNode(reconciler, node)
		end)

		it("should call function refs", function()
			local parent = Instance.new("Folder")
			local key = "Some Key"

			local spyRef = createSpy()
			local element = createElement("Frame", {
				[Ref] = spyRef.value,
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			expect(#parent:GetChildren()).to.equal(1)

			local instance = parent:GetChildren()[1]

			expect(spyRef.callCount).to.equal(1)
			spyRef:assertCalledWith(instance)

			RobloxRenderer.unmountHostNode(reconciler, node)
		end)
	end)

	describe("updateHostNode", function()
		it("should update node props and children", function()
			-- TODO: Break up test

			local parent = Instance.new("Folder")
			local key = "updateHostNodeTest"
			local firstValue = "foo"
			local newValue = "bar"

			local defaultStringValue = Instance.new("StringValue").Value

			local element = createElement("StringValue", {
				Value = firstValue
			}, {
				ChildA = createElement("IntValue", {
					Value = 1
				}),
				ChildB = createElement("BoolValue", {
					Value = true,
				}),
				ChildC = createElement("StringValue", {
					Value = "test",
				}),
				ChildD = createElement("StringValue", {
					Value = "test",
				})
			})

			local node = reconciler.createVirtualNode(element, parent, key)
			RobloxRenderer.mountHostNode(reconciler, node)

			-- Not testing mountHostNode's work here, only testing that the
			-- node is properly updated.

			local newElement = createElement("StringValue", {
				Value = newValue,
			}, {
				-- ChildA changes element type.
				ChildA = createElement("StringValue", {
					Value = "test"
				}),
				-- ChildB changes child properties.
				ChildB = createElement("BoolValue", {
					Value = false,
				}),
				-- ChildC should reset its Value property back to the default.
				ChildC = createElement("StringValue", {}),
				-- ChildD is deleted.
				-- ChildE is added.
				ChildE = createElement("Folder", {}),
			})

			RobloxRenderer.updateHostNode(reconciler, node, newElement)

			local root = parent[key]
			expect(root.ClassName).to.equal("StringValue")
			expect(root.Value).to.equal(newValue)
			expect(#root:GetChildren()).to.equal(4)

			local childA = root.ChildA
			expect(childA.ClassName).to.equal("StringValue")
			expect(childA.Value).to.equal("test")

			local childB = root.ChildB
			expect(childB.ClassName).to.equal("BoolValue")
			expect(childB.Value).to.equal(false)

			local childC = root.ChildC
			expect(childC.ClassName).to.equal("StringValue")
			expect(childC.Value).to.equal(defaultStringValue)

			local childE = root.ChildE
			expect(childE.ClassName).to.equal("Folder")
		end)

		it("should update Bindings", function()
			local parent = Instance.new("Folder")
			local key = "Some Key"

			local bindingA, updateA = Binding.create(10)
			local element = createElement("IntValue", {
				Value = bindingA,
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			local instance = parent:GetChildren()[1]

			expect(instance.Value).to.equal(10)

			local bindingB, updateB = Binding.create(99)
			local newElement = createElement("IntValue", {
				Value = bindingB,
			})

			RobloxRenderer.updateHostNode(reconciler, node, newElement)

			expect(instance.Value).to.equal(99)

			updateA(123)

			expect(instance.Value).to.equal(99)

			updateB(123)

			expect(instance.Value).to.equal(123)

			RobloxRenderer.unmountHostNode(reconciler, node)
		end)

		it("should update Binding refs", function()
			local parent = Instance.new("Folder")
			local key = "Some Key"

			local refA = createRef()
			local refB = createRef()

			local element = createElement("Frame", {
				[Ref] = refA,
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			expect(#parent:GetChildren()).to.equal(1)

			local instance = parent:GetChildren()[1]

			expect(refA.current).to.equal(instance)
			expect(refB.current).never.to.be.ok()

			local newElement = createElement("Frame", {
				[Ref] = refB,
			})

			RobloxRenderer.updateHostNode(reconciler, node, newElement)

			expect(refA.current).never.to.be.ok()
			expect(refB.current).to.equal(instance)

			RobloxRenderer.unmountHostNode(reconciler, node)
		end)

		it("should call old function refs with nil and new function refs with a valid rbx", function()
			local parent = Instance.new("Folder")
			local key = "Some Key"

			local spyRefA = createSpy()
			local spyRefB = createSpy()

			local element = createElement("Frame", {
				[Ref] = spyRefA.value,
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			expect(#parent:GetChildren()).to.equal(1)

			local instance = parent:GetChildren()[1]

			expect(spyRefA.callCount).to.equal(1)
			spyRefA:assertCalledWith(instance)
			expect(spyRefB.callCount).to.equal(0)

			local newElement = createElement("Frame", {
				[Ref] = spyRefB.value,
			})

			RobloxRenderer.updateHostNode(reconciler, node, newElement)

			expect(spyRefA.callCount).to.equal(2)
			spyRefA:assertCalledWith(nil)
			expect(spyRefB.callCount).to.equal(1)
			spyRefB:assertCalledWith(instance)

			RobloxRenderer.unmountHostNode(reconciler, node)
		end)

		it("should not call function refs again if they didn't change", function()
			local parent = Instance.new("Folder")
			local key = "Some Key"

			local spyRef = createSpy()

			local element = createElement("Frame", {
				Size = UDim2.new(1, 0, 1, 0),
				[Ref] = spyRef.value,
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			expect(#parent:GetChildren()).to.equal(1)

			local instance = parent:GetChildren()[1]

			expect(spyRef.callCount).to.equal(1)
			spyRef:assertCalledWith(instance)

			local newElement = createElement("Frame", {
				Size = UDim2.new(0.5, 0, 0.5, 0),
				[Ref] = spyRef.value,
			})

			RobloxRenderer.updateHostNode(reconciler, node, newElement)

			-- Not called again
			expect(spyRef.callCount).to.equal(1)
		end)
	end)

	describe("unmountHostNode", function()
		it("should delete instances from the inside-out", function()
			local parent = Instance.new("Folder")
			local key = "Root"
			local element = createElement("Folder", nil, {
				Child = createElement("Folder", nil, {
					Grandchild = createElement("Folder"),
				}),
			})

			local node = reconciler.mountVirtualNode(element, parent, key)

			expect(#parent:GetChildren()).to.equal(1)

			local root = parent:GetChildren()[1]
			expect(#root:GetChildren()).to.equal(1)

			local child = root:GetChildren()[1]
			expect(#child:GetChildren()).to.equal(1)

			local grandchild = child:GetChildren()[1]

			RobloxRenderer.unmountHostNode(reconciler, node)

			expect(grandchild.Parent).to.equal(nil)
			expect(child.Parent).to.equal(nil)
			expect(root.Parent).to.equal(nil)
		end)

		-- This test breaks if detachAllBindings is called as the reconciler's responsibility
		-- instead of the renderers (which makes sense, if the reconciler understands bindings)
		itSKIP("should unsubscribe from any Bindings", function()
			local parent = Instance.new("Folder")
			local key = "Some Key"

			local binding, update = Binding.create(10)
			local element = createElement("IntValue", {
				Value = binding,
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			local instance = parent:GetChildren()[1]

			expect(instance.Value).to.equal(10)

			RobloxRenderer.unmountHostNode(reconciler, node)
			update(56)

			expect(instance.Value).to.equal(10)
		end)

		it("should clear Binding refs", function()
			local parent = Instance.new("Folder")
			local key = "Some Key"

			local ref = createRef()
			local element = createElement("Frame", {
				[Ref] = ref,
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			expect(ref.current).to.be.ok()

			RobloxRenderer.unmountHostNode(reconciler, node)

			expect(ref.current).never.to.be.ok()
		end)

		it("should call function refs with nil", function()
			local parent = Instance.new("Folder")
			local key = "Some Key"

			local spyRef = createSpy()
			local element = createElement("Frame", {
				[Ref] = spyRef.value,
			})

			local node = reconciler.createVirtualNode(element, parent, key)

			RobloxRenderer.mountHostNode(reconciler, node)

			expect(spyRef.callCount).to.equal(1)

			RobloxRenderer.unmountHostNode(reconciler, node)

			expect(spyRef.callCount).to.equal(2)
			spyRef:assertCalledWith(nil)
		end)
	end)

	describe("Portals", function()
		it("should create and destroy instances as children of `target`", function()
			local target = Instance.new("Folder")

			local function FunctionComponent(props)
				return createElement("IntValue", {
					Value = props.value,
				})
			end

			local element = createElement(Portal, {
				target = target,
			}, {
				folderOne = createElement("Folder"),
				folderTwo = createElement("Folder"),
				intValueOne = createElement(FunctionComponent, {
					value = 42,
				}),
			})
			local hostParent = nil
			local hostKey = "Some Key"
			local node = reconciler.mountVirtualNode(element, hostParent, hostKey)

			expect(#target:GetChildren()).to.equal(3)

			expect(target:FindFirstChild("folderOne")).to.be.ok()
			expect(target:FindFirstChild("folderTwo")).to.be.ok()
			expect(target:FindFirstChild("intValueOne")).to.be.ok()
			expect(target:FindFirstChild("intValueOne").Value).to.equal(42)

			reconciler.unmountVirtualNode(node)

			expect(#target:GetChildren()).to.equal(0)
		end)

		it("should pass prop updates through to children", function()
			local target = Instance.new("Folder")

			local firstElement = createElement(Portal, {
				target = target,
			}, {
				ChildValue = createElement("IntValue", {
					Value = 1,
				}),
			})

			local secondElement = createElement(Portal, {
				target = target,
			}, {
				ChildValue = createElement("IntValue", {
					Value = 2,
				}),
			})

			local hostParent = nil
			local hostKey = "A Host Key"
			local node = reconciler.mountVirtualNode(firstElement, hostParent, hostKey)

			expect(#target:GetChildren()).to.equal(1)

			local firstValue = target.ChildValue
			expect(firstValue.Value).to.equal(1)

			node = reconciler.updateVirtualNode(node, secondElement)

			expect(#target:GetChildren()).to.equal(1)

			local secondValue = target.ChildValue
			expect(firstValue).to.equal(secondValue)
			expect(secondValue.Value).to.equal(2)

			reconciler.unmountVirtualNode(node)

			expect(#target:GetChildren()).to.equal(0)
		end)

		it("should throw if `target` is nil", function()
			-- TODO: Relax this restriction?
			local element = createElement(Portal)
			local hostParent = nil
			local hostKey = "Keys for Everyone"

			expect(function()
				reconciler.mountVirtualNode(element, hostParent, hostKey)
			end).to.throw()
		end)

		it("should throw if `target` is not a Roblox instance", function()
			local element = createElement(Portal, {
				target = {},
			})
			local hostParent = nil
			local hostKey = "Unleash the keys!"

			expect(function()
				reconciler.mountVirtualNode(element, hostParent, hostKey)
			end).to.throw()
		end)

		it("should recreate instances if `target` changes in an update", function()
			local firstTarget = Instance.new("Folder")
			local secondTarget = Instance.new("Folder")

			local firstElement = createElement(Portal, {
				target = firstTarget,
			}, {
				ChildValue = createElement("IntValue", {
					Value = 1,
				}),
			})

			local secondElement = createElement(Portal, {
				target = secondTarget,
			}, {
				ChildValue = createElement("IntValue", {
					Value = 2,
				}),
			})

			local hostParent = nil
			local hostKey = "Some Key"
			local node = reconciler.mountVirtualNode(firstElement, hostParent, hostKey)

			expect(#firstTarget:GetChildren()).to.equal(1)
			expect(#secondTarget:GetChildren()).to.equal(0)

			local firstChild = firstTarget.ChildValue
			expect(firstChild.Value).to.equal(1)

			local logs = Logging.capture(function()
				node = reconciler.updateVirtualNode(node, secondElement)
			end)

			expect(#logs.warnings).to.equal(1)
			expect(#logs.infos).to.equal(0)
			expect(#logs.errors).to.equal(0)
			expect(logs.warnings[1]:find("Portal")).to.be.ok()
			expect(logs.warnings[1]:find("target")).to.be.ok()

			expect(#firstTarget:GetChildren()).to.equal(0)
			expect(#secondTarget:GetChildren()).to.equal(1)

			local secondChild = secondTarget.ChildValue
			expect(secondChild.Value).to.equal(2)

			reconciler.unmountVirtualNode(node)

			expect(#firstTarget:GetChildren()).to.equal(0)
			expect(#secondTarget:GetChildren()).to.equal(0)
		end)
	end)
end