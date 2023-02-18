-- w = window, tx = text, l = list, b = button
package.loaded.gml=nil
package.loaded.gfxbuffer=nil
local gml = require('gml')
local event = require('event')
local utf8 = require('unicode')
local computer = require('computer')
local component = require('component')
local serialization = require('serialization')
local modem = component.modem
local pim=component.pim
local i_c = component.inventory_controller
local interface = component.me_interface
component.gpu.setResolution(48, 17)
local W, H = component.gpu.getResolution()
local hW = W/2
local db = {}
--th=require('thread').create(function()while true do pcall(os.sleep, 1)end end):detach()
--th=require('thread').create(function()while true do pcall(os.sleep, 1)end end):detach()
function event.shouldInterrupt() return false end
function event.shouldSoftInterrupt() return false end

local cfg = {
  port = 3215,
  operator = 'Doob',
  logins = 30,
  fee = 0.01,
  max = 100000, -- maximum cost
  ic_side = 1, -- chest for i_c
  mei_side = 'WEST' -- chest for me_interface
}

local tmpData = {
  price_selected = 0,
  CURRENT_USER = '',
  BALANCE_TEXT = '',
  BTXT_LEN = 0,
  lastlogin = 0,
  tooltip = '',
  ttp_len = 0,
  BUFFER = {},
  uiBuffer = {},
  uiStorage = {}
}

local loc = {
  buy = 'Купить',
  sell = 'Продать',
  sell_all = 'Продать всё',
  info = 'Информация',
  cancel = 'Отмена',
  next = 'Далее',
  apply = 'Принять',
  exit = 'Выход',
  label = 'Наименование',
  amount = 'Количество',
  inStock = 'В наличии: ',
  total = 'Сумма',
  price = 'Цена',
  sell_items = 'Продать предметы?',
  sell_amount = 'Количество: ',
  sell_profit = 'На сумму: $_ (комиссия ~%)',
  operations = 'Доступно операций: ',
  reset = 'Сброс через _ минут',
  drop = 'Брось предметы для продажи перед роботом'
}

local function save_db()
  local file = io.open('market.db', 'w')
  file:write(serialization.serialize(db))
  file:close()
end

local function load_db()
  local file = io.open('market.db', 'r')
  if not file then
    file = io.open('market.db', 'w')
    file:write(serialization.serialize(db))
  else
    local serdb = file:read('a')
    db = serialization.unserialize(serdb)
  end
  file:close()
end

local function log_add(str)
  local file = io.open('market.log', 'a')
  file:write(str..'\n')
  file:close()
end

local function add_sp(str, n)
  if n-1 < utf8.len(str) then
    return utf8.sub(str, 1, n)
  else
    for i = 1, n-utf8.len(str) do
      str = str..' '
    end
    return str
  end
end

local function logout()
  save_db()
  computer.beep(220, 0.1)
  modem.broadcast(cfg.port, 'export')
  computer.removeUser(tmpData.CURRENT_USER)
  tmpData.CURRENT_USER = nil
end

local function updateCost(item)
  -- O/(I-O[+1])/I*M
  -- ((R-C)/R)*C+C
  -- (C-R)/3+R
  local R_cost = math.ceil(db.items[item].o/(db.items[item].i-db.items[item].o+1)/db.items[item].i*cfg.max)
  local C_cost = db.items[item].cost
  if C_cost <= R_cost then
    C_cost = ((R_cost-C_cost)/R_cost)*C_cost+C_cost
  elseif C_cost > R_cost then
    C_cost = (C_cost-R_cost)/3+R_cost
  end
  if C_cost < 1 then C_cost = 1 end
  db.items[item].cost = math.ceil(C_cost)
  --db.items[item].cost = R_cost
  if os.time()-db.users[tmpData.CURRENT_USER].lastlogin < 259200 then
    if db.users[tmpData.CURRENT_USER].count <= cfg.logins then
      db.users[tmpData.CURRENT_USER].count = db.users[tmpData.CURRENT_USER].count + 1
    end
  else
    db.users[tmpData.CURRENT_USER].count = 1
    db.users[tmpData.CURRENT_USER].lastlogin = os.time()
  end
end

local function buy(item, amount)
  local n = item:find('|')
  local fprint = {id = item:sub(1, n-1), dmg = item:sub(1, n+1)}
  local item_dmp = interface.getItemDetail(fprint)
  local current, result, size = amount, 0
  if item_dmp then
    item_dmp = item_dmp.basic()
    if item_dmp.qty < amount then
      amount = item_dmp.qty
    end
    for stack = 1, math.ceil(amount/item_dmp.max_size) do
      size = interface.exportItem(fprint, cfg.mei_side, current).size
      current, result = current - size, result + size
    end
  end
  db.items[tmpData.selected].o = db.items[tmpData.selected].o + result
  log_add(os.time()..'@'..tmpData.CURRENT_USER..'@'..db.users[tmpData.CURRENT_USER].balance..'@<@'..item..'@'..amount..'@'..db.items[item].i-db.items[item].o..'@'..db.items[item].cost)
  db.users[tmpData.CURRENT_USER].balance = db.users[tmpData.CURRENT_USER].balance - tmpData.price_selected * result
  updateCost(item)
  logout()
  computer.beep(440, 0.05)
end

local function sell()
  for item, amount in pairs(tmpData.selected) do
    local result = 0
    for slot = 1, i_c.getInventorySize(cfg.ic_side) do
      local fitem = i_c.getStackInSlot(cfg.ic_side, slot)
      if fitem and item == fitem.name..'|'..fitem.damage then
        local size
        if fitem.size < amount then
          size = interface.pullItem(cfg.mei_side, slot, fitem.qty)
        elseif fitem.size >= amount then
          size = interface.pullItem(cfg.mei_side, slot, amount)
        end
        amount, result = amount - size, result + size
        if amount == 0 then
          break
        end
      end
    end
    db.items[item].i = db.items[item].i + result
    log_add(os.time()..'@'..tmpData.CURRENT_USER..'@'..db.users[tmpData.CURRENT_USER].balance..'@>@'..item..'@'..result..'@'..db.items[item].i-db.items[item].o..'@'..db.items[item].cost)
    updateCost(item)
  end
  db.users[tmpData.CURRENT_USER].balance = db.users[tmpData.CURRENT_USER].balance+tmpData.price_selected
  db.users[cfg.operator].balance = db.users[cfg.operator].balance + tmpData.fee
  logout()
  computer.beep(440, 0.05)
end

local function netScan()
  tmpData.uiStorage = {[0]={}}
  for name, item in pairs(db.items) do
    if item.i and item.o and item.label and item.cost then
      local size = item.i-item.o
      if size > 0 then
        local text = add_sp(add_sp(item.label, W-26)..size, W-15)..item.cost
        table.insert(tmpData.uiStorage, text)
        tmpData.uiStorage[0][text] = name
      end
    end
  end
end

local function bufferScan()
  tmpData.BUFFER = {}
  local item, name
  for slot = 1, i_c.getInventorySize(cfg.ic_side) do
    item = i_c.getStackInSlot(cfg.ic_side, slot)
    if item then
      name = item.name..'|'..item.damage
      if db.items[name] then
        if not tmpData.BUFFER[name] then
          tmpData.BUFFER[name] = item.size
        else
          tmpData.BUFFER[name] = tmpData.BUFFER[name]+item.size
        end
      end
    end
  end
  tmpData.uiBuffer = {[0] = {}}
  for item, size in pairs(tmpData.BUFFER) do
    local text = add_sp(add_sp(db.items[item].label, W-26)..size, W-15)..db.items[item].cost
    table.insert(tmpData.uiBuffer, text)
    tmpData.uiBuffer[0][text] = item
  end
end

local function utf_find(str, match)
  local match_len = utf8.len(match)
  for i = 1, utf8.len(str) do
    if utf8.sub(str, i, i+match_len-1) == match then
      return i
    end
  end
  return 0
end

local function update_txBalance()
  tmpData.BALANCE_TEXT = tmpData.CURRENT_USER..': '..db.users[tmpData.CURRENT_USER].balance
  tmpData.BTXT_LEN = #tmpData.BALANCE_TEXT
end

local wMain = gml.create(1, 1, W, H)
local wBuyList = gml.create(1, 1, W, H)
local wBuy = gml.create(1, 1, W, H)
local wSellLoad = gml.create(1, 1, W, H)
local wSellList = gml.create(1, 1, W, H)
local wSell = gml.create(1, 1, W, H)
local wInfo = gml.create(1, 1, W, H)
wMain.style = gml.loadStyle('style')
wBuyList.style = wMain.style
wBuy.style = wMain.style
wSellLoad.style = wMain.style
wSellList.style = wMain.style
wSell.style = wMain.style
wInfo.style = wMain.style

-- Buy List -----------------------
local txBalance_wBuyList = wBuyList:addLabel(2, 1, 1, '')
local txTooltip_wBuyList = wBuyList:addLabel(2, 2, 1, '')
local lItems_wBuyList = wBuyList:addListBox('center', 3, W-4, H-6, {})
local tfFind_wBuyList = wBuyList:addTextField(W-24,1,17)
local bFind_wBuyList = wBuyList:addButton('right', 1, 6, 1, 'Find', function()
  if #tfFind_wBuyList.text > 0 and #lItems_wBuyList.list > 1 then
    local tmpList = {table.unpack(lItems_wBuyList.list)}
    for i = 1, #tmpList do
      if utf_find(utf8.lower(tmpList[i]), utf8.lower(tfFind_wBuyList.text)) > 0 then
        local tmpItem = tmpList[i]
        table.remove(tmpList, i)
        table.insert(tmpList, 1, tmpItem)
      end
    end
    tfFind_wBuyList.text = ''
    lItems_wBuyList:updateList(tmpList)
    wBuyList:draw()
  end
end)
local bCancel_wBuyList = wBuyList:addButton('left', H-2, 13, 1, loc.cancel, function()
  logout()
  wBuyList:hide()
  wBuyList.close()
end)
-----------------------------------

-- Buy ----------------------------
local txBalance_wBuy = wBuy:addLabel(1, 1, 1, '')
local txItemName_wBuy = wBuy:addLabel(1, 2, 1, '')
local txInStock_wBuy = wBuy:addLabel(1, 3, 1, '')
local txItemPrice_wBuy = wBuy:addLabel(1, 4, 1, '')
local txTotalSum_wBuy = wBuy:addLabel(1, 6, 1, '')
local txAmount_wBuy = wBuy:addLabel(1, 7, 1, '')
local nAmount_wBuy = 0
local function nUpdate(n)
  if nAmount_wBuy == 0 then
    nAmount_wBuy = n
  else
    nAmount_wBuy = nAmount_wBuy*10+n
  end
  if nAmount_wBuy*tmpData.price_selected > db.users[tmpData.CURRENT_USER].balance then
    nAmount_wBuy = math.floor(db.users[tmpData.CURRENT_USER].balance/tmpData.price_selected)
  end
  local item = db.items[tmpData.selected]
  local size = item.i-item.o
  if nAmount_wBuy > size then
    nAmount_wBuy = size
  end
  txTotalSum_wBuy.text = loc.total..': '..nAmount_wBuy*tmpData.price_selected
  txTotalSum_wBuy.width = utf8.len(txTotalSum_wBuy.text)
  txTotalSum_wBuy.posX = hW-utf_find(txTotalSum_wBuy.text, ':')
  txAmount_wBuy.text = loc.amount..': '..nAmount_wBuy
  txAmount_wBuy.width = utf8.len(txAmount_wBuy.text)
  txAmount_wBuy.posX = hW-utf_find(txAmount_wBuy.text, ':')
  wBuy:draw()
end
local num0 = wBuy:addButton(hW-1, 15, 3, 1, '0', function()nUpdate(0)end)
local num1 = wBuy:addButton(hW-6, 9, 3, 1, '1', function()nUpdate(1)end)
local num2 = wBuy:addButton(hW-1, 9, 3, 1, '2', function()nUpdate(2)end)
local num3 = wBuy:addButton(hW+4, 9, 3, 1, '3', function()nUpdate(3)end)
local num4 = wBuy:addButton(hW-6, 11, 3, 1, '4', function()nUpdate(4)end)
local num5 = wBuy:addButton(hW-1, 11, 3, 1, '5', function()nUpdate(5)end)
local num6 = wBuy:addButton(hW+4, 11, 3, 1, '6', function()nUpdate(6)end)
local num7 = wBuy:addButton(hW-6, 13, 3, 1, '7', function()nUpdate(7)end)
local num8 = wBuy:addButton(hW-1, 13, 3, 1, '8', function()nUpdate(8)end)
local num9 = wBuy:addButton(hW+4, 13, 3, 1, '9', function()nUpdate(9)end)
local numB = wBuy:addButton(hW-6, 15, 3, 1, '<', function() -- backspace
  if nAmount_wBuy == 0 then
    wBuy.close()
  elseif #tostring(nAmount_wBuy) == 1 and nAmount_wBuy ~= 0 then
    nAmount_wBuy = 0
  elseif #tostring(nAmount_wBuy) > 1 then
    nAmount_wBuy = (nAmount_wBuy-(nAmount_wBuy%10))/10
  end
  txTotalSum_wBuy.text = loc.total..': '..nAmount_wBuy*tmpData.price_selected
  txTotalSum_wBuy.width = utf8.len(txTotalSum_wBuy.text)
  txTotalSum_wBuy.posX = hW-utf_find(txTotalSum_wBuy.text, ':')
  txAmount_wBuy.text = loc.amount..': '..tostring(nAmount_wBuy)
  txAmount_wBuy.width = utf8.len(txAmount_wBuy.text)
  txAmount_wBuy.posX = hW-utf_find(txAmount_wBuy.text, ':')
  wBuy:draw()
end)
local numOk = wBuy:addButton(hW+4, 15, 3, 1, 'ok', function()
  if nAmount_wBuy > 0 then
    buy(tmpData.selected, nAmount_wBuy)
    nAmount_wBuy = 0
    wBuyList:hide()
    wBuyList.close()
    wBuy:hide()
    wBuy.close()
  end
end)
-----------------------------------

-- Buy List -- NEXT BTN -----------
local bNext_wBuyList = wBuyList:addButton('right', H-2, 13, 1, loc.next, function()
  tmpData.selected = tmpData.uiStorage[0][lItems_wBuyList:getSelected()]
  if tmpData.selected then
    tmpData.price_selected = db.items[tmpData.selected].cost
    tmpData.amount_selected = db.items[tmpData.selected].i-db.items[tmpData.selected].o
    txBalance_wBuy.text = tmpData.BALANCE_TEXT
    txBalance_wBuy.width = tmpData.BTXT_LEN
    txBalance_wBuy.posX = hW-utf_find(tmpData.BALANCE_TEXT, ':')
    txInStock_wBuy.text = loc.inStock..tmpData.amount_selected
    txInStock_wBuy.width = utf8.len(txInStock_wBuy.text)
    txInStock_wBuy.posX = hW-utf_find(txInStock_wBuy.text, ':')
    txItemName_wBuy.text = loc.label..': '..db.items[tmpData.selected].label
    txItemName_wBuy.width = utf8.len(txItemName_wBuy.text)
    txItemName_wBuy.posX = hW-utf_find(txItemName_wBuy.text, ':')
    txItemPrice_wBuy.text = loc.price..': '..tmpData.price_selected
    txItemPrice_wBuy.width = utf8.len(txItemPrice_wBuy.text)
    txItemPrice_wBuy.posX = hW-utf_find(txItemPrice_wBuy.text, ':')
    txTotalSum_wBuy.text = loc.total..': 0'
    txTotalSum_wBuy.width = utf8.len(txTotalSum_wBuy.text)
    txTotalSum_wBuy.posX = hW-utf_find(txTotalSum_wBuy.text, ':')
    txAmount_wBuy.text = loc.amount..': 0'
    txAmount_wBuy.width = utf8.len(txAmount_wBuy.text)
    txAmount_wBuy.posX = hW-utf_find(txAmount_wBuy.text, ':')
    wBuy:run()
  end
end)
-----------------------------------

-- Sell ---------------------------
local txToSell = wSell:addLabel('center', H/3, utf8.len(loc.sell_items), loc.sell_items)
local txAmount_wSell = wSell:addLabel('center', H/3+1, 1, '')
local txProfit_wSell = wSell:addLabel('center', H/3+2, 1, '')
local bCancel_wSell = wSell:addButton('left', H-2, 20, 3, loc.cancel, function()
  logout()
  wSell.close()
end)
local bNext_wSell = wSell:addButton('right', H-2, 20, 3, loc.apply, function()
  if tmpData.selected then
    sell()
    wSell.close()
  end
end)
-----------------------------------

-- Sell List ----------------------
local txBalance_wSellList = wSellList:addLabel('center', 1, 1, '')
local txTooltip_wSellList = wSellList:addLabel(2, 2, 1, '')
local lItems_wSellList = wSellList:addListBox('center', 3, W-4, H-6, {})
local bCancel_wSellList = wSellList:addButton('left', H-2, 13, 1, loc.cancel, function()
  logout()
  wSellList:hide()
  wSellList.close()
end)
local function sell_prepare(all)
  if #lItems_wSellList.list > 0 then
    local amount, item = 0
    tmpData.price_selected = 0
    if all then
      tmpData.selected = tmpData.BUFFER
      for i = 1, #lItems_wSellList.list do
        item = tmpData.uiBuffer[0][lItems_wSellList.list[i]]
        tmpData.price_selected = tmpData.price_selected + (db.items[item].cost*tmpData.BUFFER[item])
        amount = amount + tmpData.BUFFER[item]
      end
    else
      tmpData.selected = tmpData.uiBuffer[0][lItems_wSellList:getSelected()]
      if tmpData.selected then
        amount = tmpData.BUFFER[tmpData.selected]
        tmpData.price_selected = db.items[tmpData.selected].cost*amount
        tmpData.selected = {[tmpData.selected] = amount}
      end
    end
    tmpData.fee = math.ceil(tmpData.price_selected*cfg.fee)
    tmpData.price_selected = tmpData.price_selected-tmpData.fee
    txAmount_wSell.text = loc.amount..': '..amount
    txAmount_wSell.width = utf8.len(txAmount_wSell.text)
    txAmount_wSell.posX = hW-(txAmount_wSell.width/2)
    txProfit_wSell.text = loc.sell_profit:gsub('_', tmpData.price_selected):gsub('~', cfg.fee*100)
    txProfit_wSell.width = utf8.len(txProfit_wSell.text)
    txProfit_wSell.posX = hW-(txProfit_wSell.width/2)
    wSell:run()
    wSellList.close()
  end
end
local bNext1_wSellList = wSellList:addButton('center', H-2, 13, 1, loc.sell_all, function()
  sell_prepare(true)
end)
local bNext2_wSellList = wSellList:addButton('right', H-2, 13, 1, loc.sell, function()
  sell_prepare()
end)
-----------------------------------

-- Sell Load ----------------------
local txSellInfo = wSellLoad:addLabel('center', H/3, utf8.len(loc.drop), loc.drop)
local bCancel_wSellLoad = wSellLoad:addButton('left', H-2, 20, 3, loc.cancel, function()
  logout()
  wSellLoad.close()
end)
local bNext_wSellLoad = wSellLoad:addButton('right', H-2, 20, 3, loc.next, function()
  modem.broadcast(cfg.port, 'stop')
  bufferScan()
  lItems_wSellList:updateList(tmpData.uiBuffer)
  wSellList:run()
  wSellLoad.close()
end)
-----------------------------------

-- Info ---------------------------
local txBalance_wInfo = wInfo:addLabel(1, H/2-3, 1, '')
local txOperations_wInfo = wInfo:addLabel(1, H/2-1, 1, '')
local txReset_wInfo = wInfo:addLabel(1, H/2, 1, '')
local bExit_wInfo = wInfo:addButton('center', 10+(H-15)/2, 20+W%2, 3, loc.exit, function()
  logout()
  wInfo:hide()
  wInfo.close()
end)
-----------------------------------

-- Main ---------------------------
--local bExit_wMain = wMain:addButton('left', H-1, 4, 1, loc.exit, wMain.close)
local bToBuy_wMain = wMain:addButton('center', 2+(H-15)/2, 20+W%2, 3, loc.buy, function()
  if db.users[tmpData.CURRENT_USER].count < cfg.logins then
    computer.beep(1000, 0.05)
    txBalance_wBuyList.text = tmpData.BALANCE_TEXT
    txBalance_wBuyList.width = tmpData.BTXT_LEN
    txTooltip_wBuyList.text = tmpData.tooltip
    txTooltip_wBuyList.width = tmpData.ttp_len
    netScan()
    lItems_wBuyList:updateList(tmpData.uiStorage)
    wBuyList:run()
  end
end)
local bToSell_wMain = wMain:addButton('center', 6+(H-15)/2, 20+W%2, 3, loc.sell, function()
  if db.users[tmpData.CURRENT_USER].count < cfg.logins then
    modem.broadcast(cfg.port, 'import')
    computer.beep(800, 0.05)
    txTooltip_wSellList.text = tmpData.tooltip
    txTooltip_wSellList.width = tmpData.ttp_len
    txBalance_wSellList.text = tmpData.BALANCE_TEXT
    txBalance_wSellList.width = tmpData.BTXT_LEN
    txBalance_wSellList.posX = hW-(tmpData.BTXT_LEN/2)
    wSellLoad:run()
  end
end)
local bInfo_wMain = wMain:addButton('center', 10+(H-15)/2, 20+W%2, 3, loc.info, function()
  computer.beep(900, 0.05)
  txBalance_wInfo.text = tmpData.BALANCE_TEXT
  txBalance_wInfo.width = tmpData.BTXT_LEN
  txBalance_wInfo.posX = hW-(tmpData.BTXT_LEN/2)
  txOperations_wInfo.text = loc.operations..cfg.logins-db.users[tmpData.CURRENT_USER].count
  txOperations_wInfo.width = utf8.len(txOperations_wInfo.text)
  txOperations_wInfo.posX = hW-(txOperations_wInfo.width/2)
  txReset_wInfo.text = loc.reset:gsub('_', 60-math.ceil((os.time()-db.users[tmpData.CURRENT_USER].lastlogin)/4320))
  txReset_wInfo.width = utf8.len(txReset_wInfo.text)
  txReset_wInfo.posX = hW-(txReset_wInfo.width/2)
  wInfo:run()
end)
-----------------------------------
wMain:addHandler('touch', function(...)
  modem.broadcast(cfg.port, 'stop')
  local e = {...}
  tmpData.CURRENT_USER = e[6]
  tmpData.lastlogin = computer.uptime()
  computer.addUser(tmpData.CURRENT_USER)
  modem.broadcast(cfg.port, 'start')
  if not db.users[tmpData.CURRENT_USER] then
    db.users[tmpData.CURRENT_USER] = {
      balance = 0,
      count = 0,
      lastlogin = os.time()
    }
  end
  if not db.users[cfg.operator] then
    db.users[cfg.operator] = {
      balance = 0,
      count = 0,
      lastlogin = os.time()
    }
  end
  if os.time()-db.users[tmpData.CURRENT_USER].lastlogin > 259200 then
    db.users[tmpData.CURRENT_USER].lastlogin = os.time()
    db.users[tmpData.CURRENT_USER].count = 0
  end
  update_txBalance()
end)
wMain:addLabel('left', 1, 10, tmpData.CURRENT_USER)
_G.m_timer = event.timer(60, function()
  if tmpData.CURRENT_USER and computer.uptime()-tmpData.lastlogin >= 120 then
    logout()
    wMain:run()
    wBuyList.close()
    wBuy.close()
    wSellLoad.close()
    wSellList.close()
    wSell.close()
    wInfo.close()
    wMain:draw()
  end
end, math.huge)
-----------------------------------

while true do

    local signal = {computer.pullSignal(0)}
    if signal[1] == "player_on" then
        
    tmpData.tooltip = add_sp(add_sp(loc.label, W-26)..loc.amount, W-16)..' '..loc.price
tmpData.ttp_len = utf8.len(tmpData.tooltip)
modem.setStrength(10)
load_db()
wMain:run()
    logout()
    wMain:run()
    wBuyList.close()
    wBuy.close()
    wSellLoad.close()
    wSellList.close()
    wSell.close()
    wInfo.close()
    wMain:draw()
    elseif signal[1] == "player_off" then
    
  
    
    

    end
end
