-- Import libraries
local GUI = require("GUI")
local system = require("System")
local screen = require("Screen")
local event = require("Event")
local component = require("component")
local fs = require("Filesystem")
---------------------------------------------------------------------------------
-- misc globals
local ae2				-- ae2 network we are attached to
local db				-- database we are using
local lvmList			-- list of all level maintainers we have
local nLvms = 0			-- how many level maintainers we have
local stockedItems = {}	-- table of all items currently being stocked
local iStocked = {}		-- list of all items currently being stocked; generated from stockedItems
local openStockers = {}	-- list of all open level maintainers' slots
local watchList = {}	-- list of items that have dipped below their stock qty
local lvmSlots = {1,2,3,4,5};
local qtySuffixes = {"K", "M", "G", "T",
						K=1000,
						M=1000000,
						G=1000000000,
						T=1000000000000
					};
local currentI = 0;

---------------------------------------------------------------------------------
-- default config options
local defaultOptions = {
-- time between inventory checks and updates, in seconds. If zero, never automatically checks item quantities.
	checkFrequency = 2,
-- time between additional AE2 pulls of 'watched' items, in cycles. min 1, whole numbers only
	watchFrequency = 12,
-- uses this address as the proxy for the AE2 me interface. needed if there are several me interface components connected.
	ae2address = nil,
-- main program colors
	programColor = {
		["header"]=0x2D2D2D,
		["headerText"]=0xFFFFFF,
		["windowFill"]=0xE1E1E1,
		["textbox"]=0xEEEEEE,
		["textboxFocused"]=0xFFFFFF,
		["textboxText"]=0x2D2D2D,
		["textboxTextFaint"]=0x555555,
		["textboxTextHighlight"]=0x880000
	},
-- colored button colors
	buttonColor = {
		["save"]=0x00EE00,
		["savePressed"]=0x008800,
		["cancel"]=0xEE4444,
		["cancelPressed"]=0x880000,
		["text"]=0x555555,
		["textPressed"]=0xFFFFFF
	}
}

---------------------------------------------------------------------------------
-- other files

local currentFolder = fs.path(system.getCurrentScript())
local pseudonymFilePath = currentFolder.."/pseudonyms.txt"
local configFilePath = currentFolder.."/config.txt"
---- if we have one, open the saved list of config options
local config;
if (fs.exists(configFilePath)) then
	config = fs.readTable(configFilePath);
else
	config = defaultOptions;
end
---- if we have one, open the saved list of pseudonyms (so user can rename items in the GUI)
local pseudonyms;
if (fs.exists(pseudonymFilePath)) then
	pseudonyms = fs.readTable(pseudonymFilePath);
else
	pseudonyms = {};
end

---------------------------------------------------------------------------------
-- Add a new window to MineOS workspace
local workspace, window, menu = system.addWindow(GUI.filledWindow(1, 1, screen.getWidth(), screen.getHeight()-1, config.programColor.windowFill))
--local workspace, window, menu = system.addWindow(GUI.Window(1, 1, screen.getWidth(), screen.getHeight()-1))
--window:addChild(GUI.panel(1, 1, window.width, window.height, config.programColor.windowFill))
window:maximize()

window.actionButtons.close.onTouch = function()
	stopCheckingStock()
	window:remove();
end

menu:addItem("Add Item").onTouch = function()
	addAutoStock();
end

menu:addItem("Reload Maintainers").onTouch = function()
	loadAllLvms();
end

menu:addItem("Update All Quantities").onTouch = function()
	updateAll();
end

menu:addItem("Edit Configs").onTouch = function()
	editConfigs();
end


local layout = window:addChild(GUI.layout(1, 1, window.width, window.height, 2, 1))
--:setSpacing(int column, int row, int spacing)
layout:setSpacing(1, 1, 0);
--:setDirection(int column, int row, enum direction)
layout:setDirection(1, 1, GUI.DIRECTION_VERTICAL);
--:setMargin(int column, int row, int horizontalMargin, int verticalMargin)
layout:setMargin(1, 1, 1, 3);
--:setAlignment(int column, int row, enum horizontalAlignment, enum verticalAlignment)
layout:setAlignment(1, 1, GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP);
--:setFitting(int column, int row, int horizontalFitting, int verticalFitting[, int horizontalOffset, int verticalOffset] )
layout:setFitting(1, 1, true, true, 4, 6);

--:setColumnWidth(int column, enum sizePolicy, float size)
layout:setColumnWidth(1, GUI.SIZE_POLICY_ABSOLUTE, 95);
layout:setColumnWidth(2, GUI.SIZE_POLICY_ABSOLUTE, 65);

local layoutRight = layout:setPosition(2,1,layout:addChild(GUI.layout(1,1,layout.columnSizes[2].size,layout.height,1,2)));
for row=1,2 do
	--:setSpacing(int column, int row, int spacing)
	layoutRight:setSpacing(1, row, 0);
	--:setDirection(int column, int row, enum direction)
	layoutRight:setDirection(1, row, GUI.DIRECTION_VERTICAL);
	--:setMargin(int column, int row, int horizontalMargin, int verticalMargin)
	layoutRight:setMargin(1, row, 1, 3)
	--:setAlignment(int column, int row, enum horizontalAlignment, enum verticalAlignment)
	layoutRight:setAlignment(1, row, GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP)
	--:setFitting(int column, int row, int horizontalFitting, int verticalFitting[, int horizontalOffset, int verticalOffset] )
	layoutRight:setFitting(1, row, true, true, 5, 5)
end
layoutRight:setRowHeight(1, GUI.SIZE_POLICY_RELATIVE, 0.65);

window.onResize = function(newWidth, newHeight)
	window.backgroundPanel.width, window.backgroundPanel.height = newWidth, newHeight
	layout.width, layout.height = newWidth, newHeight
end

---------------------------------------------------------------------------------
function prelim()
	-- need an ME Interface
	if (config.ae2address ~= nil) then
		ae2 = component.proxy(config.ae2address);
	else
		ae2 = component["me_interface"];
	end
	if (ae2 == nil) then
		GUI.alert("Not connected to an ME interface! Aborting.");
		window:remove();
	end
	-- need a database
	db = component["database"];
	if (db == nil) then
		GUI.alert("No database! Aborting.");
		window:remove();
	end
	-- need one or more level maintainers
	lvmList = component.list("level_maintainer");
	if next(lvmList) == nil then
		GUI.alert("Needs at least one level maintainer! Aborting.");
		window:remove();
	end

	loadAllLvms();

	-- start functionality
	doInventory()
	if config.checkFrequency > 0 then
		startCheckingStock(config.checkFrequency)
	end
end


---------------------------------------------------------------------------------
-- data structure functions

-- to store items as a lookuptable instead of a list
function itemID(item)
	return item.name ..":".. item.damage ..":".. item.label;
end

-- to query AE2 with
function itemFilter(item, useIsCraftable)
	return {name=item.name, damage=item.damage, label=item.label, isCraftable=((useIsCraftable == nil) or useIsCraftable)};
end

-- turns quantities into strings
function qtyStr(qtyNbr)
	if qtyNbr == nil then
		return "      ";
	elseif qtyNbr < 10000 then
		return string.format("  %4d", qtyNbr);
	else
		local e = math.floor(math.log(qtyNbr, 1000));
		return string.format("%4d %s",math.floor(qtyNbr/math.pow(1000,e)),qtySuffixes[e]);
	end
end

-- turns strings into quantities
function strQty(qtyStr)
	local match = string.match(qtyStr, " ?([KMGTkmgt])");
	qtyStr = string.gsub(qtyStr, " ?([KMGTkmgt])", "");

	local n = tonumber(qtyStr);
	if n ~= nil then
		if match ~= nil then
			n = n * qtySuffixes[string.upper(match)];
		end
		if n < 1 then
			return nil;
		else
			return math.floor(n);
		end
	else
		return nil
	end
end

-- pseudonym handling for itmes
function dispName(item)
	return pseudonyms[itemID(item)] or item.label;
end

---------------------------------------------------------------------------------
-- level maintainer functions

-- loads data from a single level maintainer
function loadLvm(lvmAddress)
	local lvm = component.proxy(lvmAddress);
	local outInfo = {nil, nil, nil, nil, nil};

	for i=1, #lvmSlots do
		local stockedItem = lvm.getSlot(i);
		if stockedItem ~= nil and lvm.isEnable(i)
		then
			stockedItems[itemID(stockedItem)] = {
				name	= stockedItem.name,
				label	= stockedItem.label,
				damage	= stockedItem.damage,
				isDone	= stockedItem.isDone,
				quantity= stockedItem.quantity,
				batch	= stockedItem.batch,
				address	= lvmAddress,
				slot	= i
			};
		else
			table.insert( openStockers, {
				address	= lvmAddress,
				slot	= i
			});
		end
	end
end

-- resets globals, and loads all level maintainers
function loadAllLvms()
	stockedItems = {};
	openStockers = {};
	currentI = 0;
	nLvms = 0;
	lvmList = component.list("level_maintainer");

	for k,v in pairs(lvmList) do
		loadLvm(k);
		nLvms = nLvms+1;
	end
	sortStocked();
end

-- creates a sorted version of stockedItems, to print
function sortStocked()
	iStocked = {};
	for k, v in pairs(stockedItems) do
		table.insert(iStocked, v);
	end
	-- sort by name, id, and label. good enough.
	table.sort(iStocked, function(a, b) return
		(a.name > b.name) or
		(a.name==b.name and a.damage > b.damage) or
		(a.name==b.name and a.damage== b.damage and a.label > b.label)
		end);
end
	

-- returns address and slot of an open levelmaintainer, or nil/nil if none exist
function getOpenSlot()
	if next(openStockers) then
		return openStockers[1].address, openStockers[1].slot;
	else
		return nil, nil;
	end
end

function consumeOpenSlot()
	table.remove(openStockers, 1);
end

-- stops stocking the given item
function stopStockingItem(item)
	local stockedItem = stockedItems[itemID(item)];

	if stockedItem ~= nil then
		-- disable in level maintainer
		component.proxy(stockedItem.address).setEnable(stockedItem.slot, false);
		-- mark as available
		table.insert( openStockers, {
			address = stockedItem.address,
			slot = stockedItem.slot
		});
		-- remove pseudonym, if any
		removePseudonym(itemID(item));
		-- remove watch, if any
		watchList[itemID(item)] = nil;
		-- remove from stockedItems
		stockedItems[itemID(item)] = nil;
	end
end

function setLvm(item, quantity, batch)
	-- is it currently being stocked?
	local id = itemID(item);
	if stockedItems[id] then
		local address, slot = stockedItems[id].address, stockedItems[id].slot;
		component.invoke(address, "setSlot", slot, quantity, batch);
		stockedItems[id].quantity = quantity;
		stockedItems[id].batch = batch;
	else
		local address, slot = getOpenSlot();
		
		if address == nil then
			GUI.alert("No open slots!");
		else
			-- reuse database slot 1
			db.clear(1);
			if ae2.store( itemFilter(item), db.address, 1 ) then
				if component.invoke(address, "setSlot", slot, db.address, 1, quantity, batch) then
					local newItem = item;
					newItem.quantity = quantity;
					newItem.batch = batch;
					newItem.address = address;
					newItem.slot = slot;
					stockedItems[id] = newItem;
					consumeOpenSlot();
					sortStocked();
				else
					GUI.alert("Failed to set slot?");
				end
			else
				GUI.alert("Could not store item into database?");
			end
		end
	end
end

---------------------------------------------------------------------------------
-- primary window

local primaryContainer = layout:setPosition(1,1,layout:addChild(GUI.container(0, 0, layout.columnSizes[1].size - 5, layout.height - 3)))
primaryContainer:addChild(GUI.panel(1,1,primaryContainer.width,2,config.programColor.header))
primaryContainer:addChild(GUI.label(1,2,primaryContainer.width,1,config.programColor.headerText,"                                         Item Name     Quantity     Stock     Batch  "))

local stockingTextbox = primaryContainer:addChild(
	-- .textBox(x, y, width, height, backgroundColor, textColor, lines, currentLine, horizontalOffset, verticalOffset[, autoWrap, autoHeight])
	GUI.textBox(1, 3, primaryContainer.width, primaryContainer.height - 3, config.programColor.textbox, config.programColor.textboxText, {}, 1, 0, 0)
)

-- add an invisible overlay panel to allow clicking on an entry to edit or delete its rule
local overlayPanel = primaryContainer:addChild(GUI.object(0,3,stockingTextbox.width-2,stockingTextbox.height))
overlayPanel.passScreenEvents = true;
overlayPanel.eventHandler = function(workspace, object, e1, e2, e3, e4)
	if e1 == "touch" then
		local lineNumber = stockingTextbox.currentLine+e4-overlayPanel.y
		if #stockingTextbox.lines >= lineNumber then
			itemContextMenu(stockedItems[stockingTextbox.lines[lineNumber].id], e3, e4)
		end
	end
end
--
function itemContextMenu(stockedItem, x, y)
	if (stockedItem ~= nil) then
		local contextMenu = GUI.addContextMenu(workspace, x, y)
		contextMenu:addItem("Craft "..dispName(stockedItem)).onTouch = function()
			craft(stockedItem, stockedItem.batch);
		end
		contextMenu:addItem("Edit rule for "..dispName(stockedItem)).onTouch = function()
			GUI_editAutoStock(stockedItem, true);
		end
		contextMenu:addItem("Show details for "..dispName(stockedItem)).onTouch = function()
			debugDetails(stockedItem, x, y);
		end
		contextMenu:addItem("Refresh data for  "..dispName(stockedItem)).onTouch = function()
			updateItem(stockedItem);
		end
		contextMenu:addSeparator()
		contextMenu:addItem("Delete rule for "..dispName(stockedItem)).onTouch = function()
			stopStockingItem(stockedItem);
		end
		workspace:draw()
	end
end

-- watchlist
local watchContainer = layoutRight:setPosition(1,1,layoutRight:addChild(
	GUI.container(0, 0, layoutRight.width, layoutRight.height * layoutRight.rowSizes[1].size)
))
watchContainer:addChild(GUI.panel(1,1,watchContainer.width,2,config.programColor.header))
watchContainer:addChild(GUI.label(1,2,watchContainer.width,1,config.programColor.headerText,string.format("%45s", "Understocked Items")))
local watchTextbox = watchContainer:addChild(
	GUI.textBox(1, 3, watchContainer.width, watchContainer.height - 3, config.programColor.textbox, config.programColor.textboxText, {}, 1, 0, 0)
)
-- add another invisible overlay panel to allow clicking on an entry to edit or delete its rule
local overlayPanelWatch = watchContainer:addChild(GUI.object(0,3,watchTextbox.width-2,watchTextbox.height))
overlayPanelWatch.passScreenEvents = true;
overlayPanelWatch.eventHandler = function(workspace, object, e1, e2, e3, e4)
	if e1 == "touch" then
		local lineNumber = watchTextbox.currentLine+e4-overlayPanelWatch.y
		if #watchTextbox.lines >= lineNumber then
			itemContextMenu(stockedItems[watchTextbox.lines[lineNumber].id], e3, e4)
		end
	end
end

-- searchbar; located on top of Primary container, uses both primary and watch
local searchBar = primaryContainer:addChild(
	GUI.input(1,1,primaryContainer.width,1,config.programColor.header,config.programColor.headerText,config.programColor.textboxTextFaint,config.programColor.header,config.programColor.headerText, "", "Search", true)
)
searchBar.onInputFinished = function()
	doInventory();
	stockingTextbox:scrollToStart();
	watchTextbox:scrollToStart();
end

-- info panel
local infoContainer = layoutRight:setPosition(1,2,layoutRight:addChild(
	GUI.container(0, 0, layoutRight.width, layoutRight.height * layoutRight.rowSizes[2].size)
))
infoContainer:addChild(GUI.panel(1, 1,infoContainer.width,2,config.programColor.header))
infoContainer:addChild(GUI.label(1, 2,infoContainer.width,1,config.programColor.headerText,string.format("%45s", "Program Information")))
infoContainer:addChild(GUI.panel(1, 3,infoContainer.width, infoContainer.height - 3, config.programColor.textbox))
infoContainer:addChild(GUI.text( 1, 4,config.programColor.textboxText, string.format("%45s", "CPUs Total:")))
infoContainer:addChild(GUI.text( 1, 5,config.programColor.textboxText, string.format("%45s", "CPUs In Use:")))
infoContainer:addChild(GUI.text( 1, 6,config.programColor.textboxText, string.format("%45s", "CPUs Available:")))
infoContainer:addChild(GUI.text( 1, 8,config.programColor.textboxText, string.format("%45s", "Level Maintainers:")))
infoContainer:addChild(GUI.text( 1, 9,config.programColor.textboxText, string.format("%45s", "Items Stocked:")))
infoContainer:addChild(GUI.text( 1,10,config.programColor.textboxText, string.format("%45s", "Slots Available:")))
local infoText = {}
infoText.CPUTotal = infoContainer:addChild(GUI.text(48, 4, config.programColor.textboxText, "-")); 
infoText.CPUInUse = infoContainer:addChild(GUI.text(48, 5, config.programColor.textboxText, "-")); 
infoText.CPUAvail = infoContainer:addChild(GUI.text(48, 6, config.programColor.textboxText, "-")); 
infoText.LVMTotal = infoContainer:addChild(GUI.text(48, 8, config.programColor.textboxText, "-")); 
infoText.ItemsTot = infoContainer:addChild(GUI.text(48, 9, config.programColor.textboxText, "-")); 
infoText.SltAvail = infoContainer:addChild(GUI.text(48,10, config.programColor.textboxText, "-")); 

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
-- Main loop

function doInventory()
	if next(stockedItems) then
		-- each cycle, update ONE item's quantity in AE2
		currentI = currentI + 1;
		if iStocked[currentI] == nil then
			currentI = 1;
		end
		updateItem(iStocked[currentI]);

		-- each cycle, check Lvm status (and AE2 quantity?) of all watched items
		watchTextbox.lines = {};
		for k,v in pairs(watchList) do
			checkWatched(k, v);
		end

		-- print misc info
		printMisc();
		
		-- print current info
		printStocking();
	else
		stockingTextbox.lines = {};
	end
end

function checkWatched(itemID, watchObj)
	local stockedItem = stockedItems[itemID];

	watchList[itemID].crafting = not component.proxy(stockedItem.address).isDone(stockedItem.slot);
	watchList[itemID].cycles = watchObj.cycles + 1;

	if watchObj.cycles % config.watchFrequency == 0 then
		updateItem(stockedItem)
	end

	if watchList[itemID] ~= nil then
		if (searchBar.text == nil or string.find(string.lower(dispName(stockedItem)), string.lower(searchBar.text))) then
			table.insert(watchTextbox.lines, {
				text = string.format("%45s", dispName(stockedItem)),
				color = (not watchList[itemID].crafting and watchList[itemID].cycles > 3) and config.programColor.textboxTextHighlight or config.programColor.textboxText,
				id = itemID
			})
		end
	end
end

function listStockedItem(stockedItem, textbox, mustMatchStr, i)
	if (mustMatchStr == nil or string.find(string.lower(dispName(stockedItem)), string.lower(mustMatchStr))) then
		table.insert(textbox.lines, {
			text = string.format("%3s  %45s       %6s  / %6s    %6s  ",
					(i == currentI) and "-->" or "",
					dispName(stockedItem),
					qtyStr(stockedItem.size),
					qtyStr(stockedItem.quantity),
					qtyStr(stockedItem.batch)),
			color = (watchList[itemID(stockedItem)] and (not watchList[itemID(stockedItem)].crafting) and watchList[itemID(stockedItem)].cycles > 3)
				and config.programColor.textboxTextHighlight or config.programColor.textboxText,
			id = itemID(stockedItem)
		});
	end
end

function printStocking()
	stockingTextbox.lines = {}
	for i=1, #iStocked do
		listStockedItem(iStocked[i], stockingTextbox, searchBar.text, i);
	end
end


function printMisc()
	local cpuData = CPUInfo();
	infoText.CPUTotal.text = cpuData.total;
	infoText.CPUInUse.text = cpuData.inuse;
	infoText.CPUAvail.text = cpuData.available;
	infoText.LVMTotal.text = nLvms;
	infoText.ItemsTot.text = #iStocked;
	infoText.SltAvail.text = nLvms*5 - #iStocked;
end

function updateItem(item)
	local id = itemID(item);
	local ae2Query = ae2.getItemsInNetwork(itemFilter(item));
	if next(ae2Query) then
		stockedItems[id].size = ae2Query[1].size;
	end

	if stockedItems[id].size < item.quantity then
		if watchList[id] == nil then
			watchList[id] = {
				crafting = not (component.proxy(item.address).isDone(item.slot)),
				cycles = 1
			}
		end
	else
		watchList[id] = nil;
	end
end

function debugDetails(item, x, y)
	-- make a subwindow
	local itemInfoMenu = GUI.addContextMenu(workspace, x, y);

	itemInfoMenu:addItem("Debug Details for "..dispName(item));
	itemInfoMenu:addSeparator();
	for k, v in pairs(item) do
		itemInfoMenu:addItem(string.format("%-10s: %40s", k, v), true);
	end
	itemInfoMenu:addItem(string.format("%-10s: %40s", "pseudonym", pseudonyms[itemID(item)]), true);
	workspace:draw();
end

-- queries AE2 for all currently stocked items.
-- warning: tps intensive
function updateAll()
	for i=1,#iStocked do
		updateItem(iStocked[i]);
	end
	doInventory();
end

function CPUInfo()
	local cpus = ae2.getCpus()
	local openCpus = 0
	for i=1, #cpus do
		if (cpus[i].busy == false) then
			openCpus = openCpus + 1
		end
	end
	return {
		total = #cpus,
		available = openCpus,
		inuse = #cpus - openCpus
	};
end

function craft(item, amt)
	if (CPUInfo().available > 0) then
		local recipe = ae2.getCraftables(itemFilter(item, false))[1];
		if recipe then
			local order = recipe.request(amt);
			if (order.isCanceled()) then
				GUI.alert("Insufficient resources for craft!");
			end
		else
			GUI.alert("No crafting recipe!");
		end
	else
		GUI.alert("CPU not available!");
	end
end

---------------------------------------------------------------------------------
function addAutoStock()
	local invController = component["inventory_controller"];

	if (invController == nil) then
		GUI.alert("No inventory controller detected on network!");
	elseif (invController.getInventoryName(1) == nil) then
		GUI.alert("Place an inventory on top of the inventory controller.");
	else
		for item in invController.getAllStacks(1) do
			if next(item) then
				local stockedItem = stockedItems[itemID(item)];
				if (stockedItem ~= nil) then
					GUI_editAutoStock(stockedItem, true);
				elseif next(ae2.getItemsInNetwork(itemFilter(item))) then
					if getOpenSlot() then
						GUI_editAutoStock(item, false);
					else
						GUI.alert("No open slots!");
					end
				end
			end
		end
	end
end

function GUI_editAutoStock(stockedItem, alreadystocking)
	local defaultQuan
	local defaultSize
	if (alreadystocking) then
		defaultQuan = stockedItem.quantity
		defaultSize = stockedItem.batch
	else
		defaultQuan = 1
		defaultSize = 1
	end

	local topstr = {[true]="Editing Stocked Item",[false]="Stocking New Item"}
	local savestr = {[true]="Save Changes",[false]="Stock Item"}
	local cancelstr = {[true]="Discard Changes",[false]="Cancel"}

	-- make a subwindow
	local subwindow = window:addChild(GUI.filledWindow(20,10,60,20,config.programColor.windowFill))
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
		dispName(stockedItem), "Enter display name", true)))
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
		GUI.label(0, 0, 8, 1, config.programColor.headerText,"Quantity")):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP))
	local quantityinput = stocksizelayer:setPosition(1,1,
		stocksizelayer:addChild(
		GUI.input(0, 0, stocksizelayer.width/2-4, 3, config.programColor.textbox, config.programColor.textboxTextFaint, 0x0, config.programColor.textboxFocused, config.programColor.textboxText,
		defaultQuan, "Enter stocking quantity", true)))
	quantityinput.validator = function(text)
		local n = strQty(text);
		if n then
			quantityinput.text = n;
		end
		return (n ~= nil);
	end
	-- batch size
	stocksizelayer:setPosition(2,1,
			stocksizelayer:addChild(
			GUI.label(0, 0, 9, 1, config.programColor.headerText,"Batch")):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP))
	local batchinput = stocksizelayer:setPosition(2,1,
		stocksizelayer:addChild(
			GUI.input(0, 0, stocksizelayer.width/2-4, 3, config.programColor.textbox, config.programColor.textboxTextFaint, 0x0, config.programColor.textboxFocused, config.programColor.textboxText,
			defaultSize, "Enter batch quantity", true)))
	batchinput.validator = function(text)
		local n = strQty(text);
		if n then
			batchinput.text = math.floor(n)
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
		if (nameinput.text ~= dispName(stockedItem)) then
			addPseudonym(itemID(stockedItem), nameinput.text);
		end
			
		if (quantityinput.text ~= defaultQuan or batchinput.text ~= defaultSize or not alreadystocking) then
			setLvm(stockedItem, quantityinput.text, batchinput.text);
		end
		subwindow:remove();
		workspace:draw();
	end
	-- Discard Changes
	buttonlayer:setPosition(2,1,
		buttonlayer:addChild(
		GUI.roundedButton(0, 0, buttonlayer.width/2-4, 3, config.buttonColor.cancel, config.buttonColor.text, config.buttonColor.cancelPressed, config.buttonColor.textPressed, cancelstr[alreadystocking])
		)).onTouch = function()
		subwindow:remove();
		workspace:draw();
	end
end

function addPseudonym(id, pseudonym)
	pseudonyms[id] = pseudonym;
	fs.writeTable(pseudonymFilePath, pseudonyms);
end

function removePseudonym(id)
	pseudonyms[id] = nil;
	fs.writeTable(pseudonymFilePath, pseudonyms);
end

---------------------------------------------------------------------------------
-- edit config options
function editConfigs()
	-- make a subwindow
	local subwindow = window:addChild(GUI.filledWindow(40,20,60,36,config.programColor.windowFill));
	subwindow.actionButtons.close.onTouch = function()
		subwindow:remove();
		workspace:draw();
	end

	subwindow:addChild(GUI.text(10, 2, config.programColor.textboxText, "EDITING CONFIG"));

	subwindow:addChild(GUI.text(3, 4, config.programColor.textboxText, "Time between inventory checks and updates, in seconds."));
	subwindow:addChild(GUI.text(3, 5, config.programColor.textboxText, "If zero, never automatically checks item quantities."));
	local checkFrequency = subwindow:addChild(
		GUI.input(5, 6, subwindow.width-10, 1, config.programColor.textbox, config.programColor.textboxTextFaint, 0x0, config.programColor.textboxFocused, config.programColor.textboxText,
		config.checkFrequency, "Cycle time", true));
	checkFrequency.validator = function(text)
		local n = strQty(text);
		if n then
			checkFrequency.text = math.max(0, math.floor(n));
		end
		return (n ~= nil);
	end

	subwindow:addChild(GUI.text(3, 8, config.programColor.textboxText, "Cycles between additional AE2 pulls of 'watched' items."));
	local watchFrequency = subwindow:addChild(
		GUI.input(5, 9, subwindow.width-10, 1, config.programColor.textbox, config.programColor.textboxTextFaint, 0x0, config.programColor.textboxFocused, config.programColor.textboxText,
		config.watchFrequency, "Cycle time", true));
	watchFrequency.validator = function(text)
		local n = strQty(text);
		if n then
			watchFrequency.text = math.max(1, math.floor(n));
		end
		return (n ~= nil);
	end

	subwindow:addChild(GUI.text(3, 11, config.programColor.textboxText, "Optional: ME Interface address."));
	subwindow:addChild(GUI.text(3, 12, config.programColor.textboxText, "For if the computer can also see non-block interfaces."));	
	local ae2address = subwindow:addChild(
		GUI.input(5, 13, subwindow.width-10, 1, config.programColor.textbox, config.programColor.textboxTextFaint, 0x0, config.programColor.textboxFocused, config.programColor.textboxText,
		config.ae2address, "Cycle time", true));
	ae2address.validator = function(text)
		return (component.proxy(text) ~= nil);
	end

	subwindow:addChild(GUI.text(3, 15, config.programColor.textboxText, "Program Colors"));
	programColorheader					= subwindow:addChild(GUI.colorSelector(	5, 16, 35, 1, config.programColor.header, "header"))
	programColorheaderText				= subwindow:addChild(GUI.colorSelector(	5, 17, 35, 1, config.programColor.headerText, "headerText"))
	programColorwindowFill				= subwindow:addChild(GUI.colorSelector(	5, 18, 35, 1, config.programColor.windowFill, "windowFill"))
	programColortextbox					= subwindow:addChild(GUI.colorSelector(	5, 19, 35, 1, config.programColor.textbox, "textbox"))
	programColortextboxFocused			= subwindow:addChild(GUI.colorSelector(	5, 20, 35, 1, config.programColor.textboxFocused, "textboxFocused"))
	programColortextboxText				= subwindow:addChild(GUI.colorSelector(	5, 21, 35, 1, config.programColor.textboxText, "textboxText"))
	programColortextboxTextFaint		= subwindow:addChild(GUI.colorSelector(	5, 22, 35, 1, config.programColor.textboxTextFaint, "textboxTextFaint"))
	programColortextboxTextHighlight	= subwindow:addChild(GUI.colorSelector(	5, 23, 35, 1, config.programColor.textboxTextHighlight, "textboxTextHighlight"))
	
	subwindow:addChild(GUI.text(3, 25, config.programColor.textboxText, "Button Colors"));
	buttonColorsave						= subwindow:addChild(GUI.colorSelector(	5, 26, 35, 1, config.buttonColor.save, "save"))
	buttonColorsavePressed				= subwindow:addChild(GUI.colorSelector(	5, 27, 35, 1, config.buttonColor.savePressed, "savePressed"))
	buttonColorcancel					= subwindow:addChild(GUI.colorSelector(	5, 28, 35, 1, config.buttonColor.cancel, "cancel"))
	buttonColorcancelPressed			= subwindow:addChild(GUI.colorSelector(	5, 29, 35, 1, config.buttonColor.cancelPressed, "cancelPressed"))
	buttonColortext						= subwindow:addChild(GUI.colorSelector(	5, 30, 35, 1, config.buttonColor.text, "text"))
	buttonColortextPressed				= subwindow:addChild(GUI.colorSelector(	5, 31, 35, 1, config.buttonColor.textPressed, "textPressed"))

	-- Apply Changes
	subwindow:addChild(
			GUI.roundedButton(3, 33, subwindow.width/3-2, 3, config.buttonColor.save, config.buttonColor.text, config.buttonColor.savePressed, config.buttonColor.textPressed, "Apply changes")
			).onTouch = function()
		
		config.checkFrequency = checkFrequency.text;
		config.watchFrequency = watchFrequency.text;
		config.ae2address = ae2address.text;

		config.programColor.header = programColorheader.color;
		config.programColor.headerText = programColorheaderText.color;
		config.programColor.windowFill = programColorwindowFill.color;
		config.programColor.textbox = programColortextbox.color;
		config.programColor.textboxFocused = programColortextboxFocused.color;
		config.programColor.textboxText = programColortextboxText.color;
		config.programColor.textboxTextFaint = programColortextboxTextFaint.color;
		config.programColor.textboxTextHighlight = programColortextboxTextHighlight.color;
		config.buttonColor.save = buttonColorsave.color;
		config.buttonColor.savePressed = buttonColorsavePressed.color;
		config.buttonColor.cancel = buttonColorcancel.color;
		config.buttonColor.cancelPressed = buttonColorcancelPressed.color;
		config.buttonColor.text = buttonColortext.color;
		config.buttonColor.textPressed = buttonColortextPressed.color;

		-- write to file
		fs.writeTable(configFilePath, config);

		GUI.alert("Config updated -- restart program.");
		stopCheckingStock();
		subwindow:remove();
		window:remove();
		workspace:draw();
	end
	-- Discard Changes
	subwindow:addChild(
		GUI.roundedButton(1*subwindow.width/3+2, 33, subwindow.width/3-2, 3, config.buttonColor.cancel, config.buttonColor.text, config.buttonColor.cancelPressed, config.buttonColor.textPressed, "Discard changes")
		).onTouch = function()
		subwindow:remove();
		workspace:draw();
	end
	-- Reset Config
	subwindow:addChild(
		GUI.roundedButton(2*subwindow.width/3+2, 33, subwindow.width/3-2, 3, config.buttonColor.cancel, config.buttonColor.text, config.buttonColor.cancelPressed, config.buttonColor.textPressed, "Reset all")
		).onTouch = function()
		local needRestart = (table.concat(config.programColor) .. table.concat(config.buttonColor)) ~= (table.concat(defaultOptions.programColor) .. table.concat(defaultOptions.buttonColor));
		config = defaultOptions;
		fs.writeTable(configFilePath, config);
		GUI.alert("Config reset -- restart program.");
		stopCheckingStock();
		subwindow:remove();
		window:remove();
		workspace:draw();
	end
end

-- Run preliminary setup
prelim();
-- Draw changes on screen after customizing your window
workspace:draw();
