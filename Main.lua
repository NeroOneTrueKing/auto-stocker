
-- Import libraries
local GUI = require("GUI")
local system = require("System")
local screen = require("Screen")
local event = require("Event")
local component = require("component")
local fs = require("Filesystem")
-- Import other files
local currentFolder = fs.path(system.getCurrentScript())
local config = dofile(currentFolder .."/Config.lua")
---------------------------------------------------------------------------------
-- misc globals
local ae2             -- ae2 network we are attached to
local stockList       -- list of items to autostock
local craftQueue = {} -- table of crafting recipes either currently happening or waiting to happen
local stockFilePath = currentFolder.."/"..config.stockFileName
---------------------------------------------------------------------------------
-- Add a new window to MineOS workspace
local workspace, window, menu = system.addWindow(GUI.filledWindow(1, 1, screen.getWidth(), screen.getHeight()-1, 0xE1E1E1))
window:maximize()

window.actionButtons.close.onTouch = function()
	stopCheckingStock()
	window:remove()
end

menu:addItem("Add Item").onTouch = function()
	editAutoStock()
end

menu:addItem("Check Now").onTouch = function()
	doInventory()
end

local layout = window:addChild(GUI.layout(1, 1, window.width, window.height, 2, 1))
for col=1,2 do layout:setSpacing(col, 1, 0) end

window.onResize = function(newWidth, newHeight)
	window.backgroundPanel.width, window.backgroundPanel.height = newWidth, newHeight
	layout.width, layout.height = newWidth, newHeight
end

---------------------------------------------------------------------------------
function prelim()
	if (config.ae2address ~= nil) then
		ae2 = component.proxy(config.ae2address)
	else
		ae2 = component["me_interface"]
	end
	if (ae2 == nil) then
		GUI.alert("Not connected to an ME interface! Aborting.")
		os.exit()
	end
	if (fs.exists(stockFilePath)) then
		stockList = fs.readTable(stockFilePath)
	else
		stockList = {}
	end
	doInventory()
	startCheckingStock(config.checkFrequency)
end

---------------------------------------------------------------------------------
-- left side
local leftcontainer = layout:setPosition(1,1,layout:addChild(GUI.container(0, 0, 60, layout.height-4)))
leftcontainer:addChild(GUI.panel(0,1,60,2,config.programColor.header))
leftcontainer:addChild(GUI.label(0,2,60,1,config.programColor.headerText,"                     Item Name     Stock    Min     Group"))
local lefttextbox = leftcontainer:addChild(GUI.textBox(0, 3, 60, layout.height-5, config.programColor.textbox, config.programColor.textboxText, {}, 1, 0, 0))
local leftsearch = leftcontainer:addChild(GUI.input(0,1,60,1,config.programColor.header,config.programColor.headerText,config.programColor.textboxTextFaint,config.programColor.header,config.programColor.headerText, "", "Search", true))
leftsearch.onInputFinished = function() doInventory() end

-- add an invisible overlay panel to allow clicking on an entry to edit or delete its rule
local leftPanel = leftcontainer:addChild(GUI.object(0,3,lefttextbox.width-2,lefttextbox.height-3))
leftPanel.passScreenEvents = true
leftPanel.eventHandler = function(workspace, object, e1, e2, e3, e4)
	if e1 == "touch" then
		local lineNumber = lefttextbox.currentLine+e4-leftPanel.y
		if #lefttextbox.lines >= lineNumber then
			local stockedItem = stockList[lefttextbox.lines[lineNumber].id]
			-- bug: stocklist is sometimes in flux due to autocheck process, check that it exists before indexing
			if (stockedItem ~= nil) then
				local dispName = stockedItem.dispName
				local contextMenu = GUI.addContextMenu(workspace, e3, e4)
				contextMenu:addItem("Edit rule for "..dispName).onTouch = function()
					editAutoStock(stockedItem)
				end
				contextMenu:addSeparator()
				contextMenu:addItem("Delete rule for "..dispName).onTouch = function()
					removeStockFileEntry(stockedItem)
				end
				workspace:draw()
			end
		end
	end
end

---------------------------------------------------------------------------------
-- right side
local rightcontainer = layout:setPosition(2,1,layout:addChild(GUI.container(0, 0, 60, layout.height-4)))
rightcontainer:addChild(GUI.panel(0,1,60,2,config.programColor.header))
rightcontainer:addChild(GUI.label(0,2,60,1,config.programColor.headerText,string.format("%30s     %20s","Name","Current Status")))
local righttextbox = rightcontainer:addChild(GUI.textBox(0, 3, 60, layout.height-5, config.programColor.textbox, config.programColor.textboxText, {}, 1, 0, 0))

---------------------------------------------------------------------------------
function itemID(item)
	return item.name ..":".. item.damage ..":".. item.label
end

function resetTextboxes()
	lefttextbox.lines = {}
	righttextbox.lines = {}
end

function listStockedItem(aeItem, textbox, mustMatchStr)
	if (stockList[itemID(aeItem)] ~= nil) then
		local id = itemID(aeItem)
		local stockedItem = stockList[id]
		if (mustMatchStr == nil or string.find(string.lower(stockedItem.dispName), string.lower(mustMatchStr))) then
			local text = string.format("%30s     %5d /%5d     [%3d]", stockedItem.dispName, aeItem.size, stockedItem.stockquan, stockedItem.groupsize)
			table.insert(textbox.lines, {text=text,color=config.programColor.textboxText,id=id})
		end
	end
end

function listQueuedItem(aeItem, textbox, mustMatchStr)
	if (craftQueue[itemID(aeItem)] ~= nil) then
		local craftedItem = craftQueue[itemID(aeItem)]
		if (mustMatchStr == nil or string.find(string.lower(craftedItem.dispName), string.lower(mustMatchStr))) then
			local text = string.format("%30s     %20s", craftedItem.dispName, craftedItem.status)
			local color = config.statusColor[craftedItem.status]
			table.insert(textbox.lines, {text=text,color=color})
		end
	end
end

---------------------------------------------------------------------------------
-- event handling
local checkingEvent
function startCheckingStock(interval)
	checkingEvent = event.addHandler(doInventory, interval)
end
function stopCheckingStock()
	if (checkingEvent ~= nil) then
		event.removeHandler(checkingEvent)
		checkingEvent = nil
	end
end

---------------------------------------------------------------------------------
currentlyChecking = false
function doInventory()
	if (currentlyChecking) then
		GUI.alert("Multiple events running -- reboot computer!")
	else
		currentlyChecking = true
		resetTextboxes()
		local allItems = ae2.getItemsInNetwork({isCraftable=true})

		for j=1, #allItems do
			-- check that we're stocking this
			i = allItems[j]
			local stockedItem = stockList[itemID(i)]

			if (stockedItem ~= nil) then
				-- check if we're currently attempting to craft this
				local activeStockedItem = craftQueue[itemID(stockedItem)]

				-- not currently on the active list, check if it needs stocking
				if (activeStockedItem == nil or (activeStockedItem.status == "insufficientResources" or activeStockedItem.status == "cpuUnavailable")) then
					if (stockedItem.stockquan - i.size > 0) then
						activeStockedItem = queue(stockedItem)
					else
						activeStockedItem = nil
					end
				-- item is in queue to craft
				elseif (activeStockedItem.status == "queued") then
					if (activeStockedItem.delay == 0) then
						local amt = math.ceil((stockedItem.stockquan - i.size) / stockedItem.groupsize) * stockedItem.groupsize
						if (amt > 0) then
							activeStockedItem = craft(stockedItem, amt)
						else
							activeStockedItem = nil
						end
					else
						activeStockedItem.delay = activeStockedItem.delay - 1
					end
				-- currently in progress, check if it has finished or has been manually cancelled
				elseif (activeStockedItem.status == "inProgress") then
					if (activeStockedItem.order.isDone()) then
						activeStockedItem.status = "done"
						activeStockedItem.delay = config.delayDoneItem
					elseif (activeStockedItem.order.isCanceled()) then
						activeStockedItem.status = "canceled"
						activeStockedItem.delay = config.delayCanceledItem
					end
				-- delay, to show "Done" and "Canceled" orders
				elseif (activeStockedItem.delay ~= nil) then
					if (activeStockedItem.delay > 0) then
						activeStockedItem.delay = activeStockedItem.delay - 1
					else
						activeStockedItem = nil
					end
				else
					-- oh uh!
					GUI.alert("Error, unhandled case! Status is "..activeStockedItem.status..", and delay is "..tostring(activeStockedItem.delay)..". Stopping stock checking.")
					stopCheckingStock()
				end
				-- propagate activeStockedItem to global queue
				craftQueue[itemID(stockedItem)] = activeStockedItem
				-- update textboxes
				listStockedItem(i, lefttextbox, leftsearch.text)
				listQueuedItem(i, righttextbox)
			end
		end
		currentlyChecking = false
	end
end

function queue(item)
	local activeStockedItem = {}
	activeStockedItem.dispName = item.dispName
	activeStockedItem.status = "queued"
	activeStockedItem.delay = config.delayCraft
	return activeStockedItem
end

function isCpuAvailable()
	local cpus = ae2.getCpus()
	local openCpus = 0
	for i=1, #cpus do
		if (cpus[i].busy == false) then
			openCpus = openCpus + 1
		end
	end
	return (openCpus > config.reserveCpus)
end

function craft(item, amt)
	local activeStockedItem = {}
	activeStockedItem.dispName = item.dispName

	if (isCpuAvailable()) then
		local recipe = ae2.getCraftables({name=item.name, damage=item.damage, label=item.label})[1]
		activeStockedItem.order = recipe.request(amt)
		if (activeStockedItem.order.isCanceled() == false) then
			activeStockedItem.status = "inProgress"
		else
			activeStockedItem.status = "insufficientResources"
			activeStockedItem.order = nil
		end
	else
		activeStockedItem.status = "cpuUnavailable"
	end
	return activeStockedItem
end

---------------------------------------------------------------------------------
function editAutoStock(stockFileEntry)
	if (stockFileEntry ~= nil) then
		GUI_editAutoStock(stockFileEntry, true)
	else
		local foundit = false
		local item = getItemFromDrawer()
		if (item == nil) then
			GUI.alert("No item located in drawer.")
		elseif (ae2.getCraftables({name=item.name, damage=item.damage, label=item.label}).n == 0) then
			GUI.alert("Cannot autostock those; create an AE2 pattern first.")
		else
			for k,v in pairs(stockList) do
				if v.name == item.name and v.damage == item.damage and v.label == item.label then
					GUI_editAutoStock(stockFileEntry, true)
					foundit = true
				end
			end
			if (not foundit) then
				local newEntry = {}
				newEntry.dispName = item.dispName
				newEntry.name = item.name
				newEntry.damage = item.damage
				newEntry.label = item.label
				GUI_editAutoStock(newEntry, false)
			end
		end
	end
end

function getItemFromDrawer()
	local invController = component["inventory_controller"]
	local item
	if (invController == nil) then
		GUI.alert("No inventory controller detected on network!")
	elseif (invController.getAllStacks(1) == nil) then
		GUI.alert("Place a drawer on top of an inventory controller.")
	else
		item = invController.getAllStacks(1).getAll()[1]
		if (not next(item)) then
			item = nil
		end
	end
	return item
end

function GUI_editAutoStock(stockFileEntry, alreadystocking)
	local defaultQuan
	local defaultSize
	if (alreadystocking) then
		defaultQuan = stockFileEntry.stockquan
		defaultSize = stockFileEntry.groupsize
	else
		defaultQuan = 1
		defaultSize = 1
	end

	local topstr = {[true]="Editing Stocked Item",[false]="Stocking New Item"}
	local savestr = {[true]="Save Changes",[false]="Stock Item"}
	local cancelstr = {[true]="Discard Changes",[false]="Cancel"}

	-- make a subwindow
	local subwindow = window:addChild(GUI.filledWindow(20,10,60,20,0xE1E1E1))
	subwindow.actionButtons.close.onTouch = function()
		subwindow:remove()
		workspace:draw()
	end
	subwindow:addChild(GUI.panel(1,1,subwindow.width,2,config.programColor.header))
	subwindow:addChild(GUI.label(1,2,subwindow.width,1,config.programColor.headerText,topstr[alreadystocking])):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP)

	local sublayout = subwindow:addChild(GUI.layout(1,3,subwindow.width,subwindow.height-2,1,3))
	for row=1,3 do
		sublayout:setSpacing(1, row, 0)
	end

	-- 1st layer: label
	sublayout:setPosition(1,1,
		sublayout:addChild(
		GUI.label(0, 0, 4, 1, config.programColor.textboxText,"Name"))
		:setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP))
	local nameinput = sublayout:setPosition(1,1,
		sublayout:addChild(
		GUI.input(0, 0, sublayout.width-4, 3, config.programColor.textbox, config.programColor.textboxTextFaint, 0x0, config.programColor.textboxFocused, config.programColor.textboxText,
		stockFileEntry.dispName or stockFileEntry.label, "Enter display name", true)))
	nameinput.validator = function()
		return (nameinput.text ~= "")
	end
	-- 2nd layer: stocking quantity and group size
	local stocksizelayer = sublayout:setPosition(1,2,
		sublayout:addChild(
		GUI.layout(0,0,sublayout.width,sublayout.height/3,2,1)
		))
	for col=1,2 do
		stocksizelayer:setSpacing(col,1,0)
	end
	-- stock quantity
	stocksizelayer:setPosition(1,1,
		stocksizelayer:addChild(
		GUI.label(0, 0, 8, 1, 0x2D2D2D,"Quantity")):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP))
	local stockquaninput = stocksizelayer:setPosition(1,1,
		stocksizelayer:addChild(
		GUI.input(0, 0, stocksizelayer.width/2-4, 3, config.programColor.textbox, config.programColor.textboxTextFaint, 0x0, config.programColor.textboxFocused, config.programColor.textboxText,
		defaultQuan, "Enter stocking quantity", true)))
	stockquaninput.validator = function(text)
		local n = tonumber(text)
		if (n == nil or n < 1) then n = nil
		else
			stockquaninput.text = math.floor(n)
		end
		return (n ~= nil)
	end
	-- group size
	stocksizelayer:setPosition(2,1,
			stocksizelayer:addChild(
			GUI.label(0, 0, 9, 1, 0x2D2D2D,"GroupSize")):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP))
	local groupsizeinput = stocksizelayer:setPosition(2,1,
		stocksizelayer:addChild(
			GUI.input(0, 0, stocksizelayer.width/2-4, 3, config.programColor.textbox, config.programColor.textboxTextFaint, 0x0, config.programColor.textboxFocused, config.programColor.textboxText,
			defaultSize, "Enter group quantity", true)))
	groupsizeinput.validator = function(text)
		local n = tonumber(text)
		if (n == nil or n < 1) then n = nil
		else
			groupsizeinput.text = math.floor(n)
		end
		return (n ~= nil)
	end
	-- 3rd layer: save/discard buttons
	local buttonlayer = sublayout:setPosition(1,3,
		sublayout:addChild(
		GUI.layout(0,0,sublayout.width,sublayout.height/3,2,1)
		))
	-- Save Changes
	buttonlayer:setPosition(1,1,
			buttonlayer:addChild(
			GUI.roundedButton(0, 0, buttonlayer.width/2-4, 3, config.buttonColor.save, config.buttonColor.text, config.buttonColor.savePressed, config.buttonColor.textPressed, savestr[alreadystocking])
			)).onTouch = function()
		if (nameinput.text ~= stockFileEntry.dispName or stockquaninput.text ~= defaultQuan or groupsizeinput.text ~= defaultSize) then
			stockFileEntry.dispName = nameinput.text
			stockFileEntry.stockquan = stockquaninput.text
			stockFileEntry.groupsize = groupsizeinput.text
			addstockfileentry(stockFileEntry)
		end
		subwindow:remove()
		workspace:draw()
	end
	-- Discard Changes
	buttonlayer:setPosition(2,1,
		buttonlayer:addChild(
		GUI.roundedButton(0, 0, buttonlayer.width/2-4, 3, config.buttonColor.cancel, config.buttonColor.text, config.buttonColor.cancelPressed, config.buttonColor.textPressed, cancelstr[alreadystocking])
		)).onTouch = function()
		subwindow:remove()
		workspace:draw()
	end
end

function addstockfileentry(newEntry)
	-- add it to current stocking rules
	stockList[itemID(newEntry)] = newEntry
	-- add it to savefile of stocking rules
	fs.writeTable(stockFilePath, stockList)
	if (config.quickUpdate) then
		doInventory()
	end
end

function removeStockFileEntry(stockFileEntry)
	stockList[itemID(stockFileEntry)] = nil
	-- update stocking rules
	fs.writeTable(stockFilePath, stockList)
end

-- Run preliminary setup
prelim()
-- Draw changes on screen after customizing your window
workspace:draw()