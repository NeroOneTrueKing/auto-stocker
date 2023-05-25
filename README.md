# auto-stocker
An OpenComputers autostocking program for AE2 built on MineOS and the GUI API.

# Minimum Requirements
The minimum requirement is an OpenComputers system running [MineOS](https://github.com/IgorTimofeev/MineOS), including but not limited to:
 - Tier 3 computer case / server
   - Tier 3 graphics card
   - 2x Tier 3.5 memory (minimum)
   - CPU
   - HDD
 - Tier 3 screen
 - Adapter
   - Inventory Controller upgrade
 - Adapter
   - Database upgrade
 - ME Level Maintainers
   - adjacent to adapters
 - any inventory
   - Must be placed on top of the Adapter
 - ME Interface
   - Must be placed adjacent to the Adapter
 
Example setup, using a server in a rack:
 ![image](https://user-images.githubusercontent.com/28197216/235812244-7815d0d2-1b34-433f-9dc0-c492cac187fd.png)

# Features

![image](https://user-images.githubusercontent.com/28197216/235812401-3cf87024-cd2f-49ce-bf18-92fc1047d90d.png)

The left box lists all items that are being autostocked. The list is scrollable, and can be filtered by typing where it says "search".

![image](https://user-images.githubusercontent.com/28197216/235812447-33c850bf-68f6-47db-bb24-588bea4a318b.png)

Clicking on an entry of the list brings up a context menu, from which the stocking rule can be edited or deleted:

![image](https://user-images.githubusercontent.com/28197216/235812503-caaa9c85-f29a-4b11-9aae-978ac656b3a5.png)


The top-right box lists items which are understocked. The program slowly queries AE2 (see config), and if it sees an item is currently understocked it is added to this list. Even with very slow polling rates, this serves to help manage your stocked items.
- Items in black are understocked, but crafting
  - if an item is sitting on this list for a long time, likely the crafting recipe is stalled somewhere
- Items in red are understocked and not crafting
  - if an item is on this list, likely the system is missing resources needed to make the craft
Items on this list are queried from AE2 every N regular cycles (see config).

Pressing the "Add Item" top menu button while a craftable item is in the inventory brings up the following GUI:
![image](https://user-images.githubusercontent.com/28197216/235813525-1ebb6226-2d25-4ed8-af06-f222d2d24545.png)

The name field is prefilled using the item's label. It can be renamed to use a different display name, if desired.
If multiple craftable items are in the inventory, a window will be opened for each.

This same GUI is also used when editing an item's autostocking entry.

# Config

The program colours are configurable, as are the AE2 querying rates:
![image](https://user-images.githubusercontent.com/28197216/235814119-430c467a-95dc-41bb-906c-75184b11754c.png)

