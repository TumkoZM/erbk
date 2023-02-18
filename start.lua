local component = require('component')
local computer = require('computer')
local event = require('event')
local redstone = component.redstone
local screen = component.screen
local signal = computer.pullSignal
redstone.setWakeThreshold(15)
screen.setTouchModeInverted(true)

function computer.pullSignal(...)
  local e = {signal(...)}
  if e[1] == 'redstone_changed' and e[5] == 15 then
    computer.shutdown(true)
  end
  return table.unpack(e)
end

while true do
  if _G.m_timer then
    event.cancel(_G.m_timer)
    _G.m_timer = nil
  end
  local a = {computer.users()}
  for i = 1, #a do
    computer.removeUser(a[i])
  end
  os.execute('terminal')
end
