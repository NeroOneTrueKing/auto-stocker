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
 - Storage Drawer
   - Must be placed on top of the Adapter
   - Note: alternatives inventories should be possible, but aren't supported at this time
 - ME Interface
   - Must be placed adjacent to the Adapter
 
Example setup, using a server in a rack:
 ![image](https://user-images.githubusercontent.com/28197216/116165502-a447cd00-a6c1-11eb-8ac3-6e1d5564999d.png)

# Features

![image](https://user-images.githubusercontent.com/28197216/116166353-6a77c600-a6c3-11eb-8f56-7db7db992a41.png)

The left box lists all items that are being autostocked. The list is scrollable, and can be filtered by typing where it says "search".

![image](https://user-images.githubusercontent.com/28197216/116166692-2afda980-a6c4-11eb-91aa-025555aa47bf.png)

Clicking on an entry of the list brings up a context menu, from which the stocking rule can be edited or deleted:

![image](https://user-images.githubusercontent.com/28197216/116166600-f984de00-a6c3-11eb-94da-bae36788e579.png)


The right box lists current and recent autostocking events. There are the following possible states for an item to be in:

- done:  An autostocking request for this item was recently fulfilled
- inProgress:  This item is currently being crafted
- queued:  This item is below its current stocking threshold and will be crafted soon.
- canceled:  A request for this item was canceled by the AE system, probably manually.
- insufficientMaterials:  There aren't enough materials in the AE system to request the full quantity of this item needed to fill its stock  
- cpuUnavailable:  There are too few open crafting CPUs; the config specifies how many CPUs the program will leave open


Pressing the "Add Item" top menu button while an item is in the drawer brings up the following GUI:
![image](https://user-images.githubusercontent.com/28197216/116167297-8d0ade80-a6c5-11eb-9e21-538b120d4879.png)

The name field is prefilled using the item's label. For GregTech items, this will usually need to be manually added.

This same GUI is also used when editing an item's autostocking entry.
