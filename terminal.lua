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
  
  cancel = 'Отмена',
  next = 'Далее',
  apply = 'Принять',
  exit = 'Выход',
  label = 'Наименование',
  amount = 'Количество',
  inStock = 'В наличии: ',
  total = 'Сумма',
  price = 'Цена',
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
wMain.style = gml.loadStyle('style')
wBuyList.style = wMain.style
wBuy.style = wMain.style


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
    wMain:draw()
  end
end, math.huge)
-----------------------------------
tmpData.tooltip = add_sp(add_sp(loc.label, W-26)..loc.amount, W-16)..' '..loc.price
tmpData.ttp_len = utf8.len(tmpData.tooltip)
modem.setStrength(10)
load_db()
wMain:run()
