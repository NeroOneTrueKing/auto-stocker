-- Config file for autostocking program

return {
-- what the stockfile is named
  stockFileName = "StockFile.txt",
-- time between inventory checks and updates, in seconds
  checkFrequency = 5,
-- time to wait between detecting a deficit of an item and attempting to craft it, in cycles
  delayCraft = 2,
-- time to wait between recrafts of a single item and how long it is displayed as "done", in cycles
  delayDoneItem = 6,
-- time to wait between reattempts of a single item; how long it is displayed as "canceled", in cycles
  delayCanceledItem = 6,
-- how many crafting CPUs to reserve for manual crafting requests
  reserveCpus = 3,
-- if TRUE, immediately recheck inventory on adding or updating a stocking rule
  quickUpdate = true,

-- colors of each status
  statusColor = {
    ["done"]=0x008800,
    ["inProgress"]=0x2D2D2D,
    ["queued"]=0x2D2D2D,
    ["canceled"]=0x880000,
    ["insufficientResources"]=0x880000,
    ["cpuUnavailable"]=0xFF0000
  },
-- main program colors
  programColor = {
    ["header"]=0x2D2D2D,
    ["headerText"]=0xFFFFFF,
    ["textbox"]=0xEEEEEE,
    ["textboxFocused"]=0xFFFFFF,
    ["textboxText"]=0x2D2D2D,
    ["textboxTextFaint"]=0x555555
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