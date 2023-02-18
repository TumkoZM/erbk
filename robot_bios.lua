local modem = component.proxy(component.list('modem')())
local robot = component.proxy(component.list('robot')())
local address = '----' -- terminal address
modem.open(3215)
modem.setWakeMessage('start')
local status = 'stop'
local signal = computer.pullSignal

function computer.pullSignal(...)
  local e = {signal(...)}
  if e[1] == 'modem_message' and e[3]:sub(1, 4) == address then
    status = e[6]
  end
end
while true do
  computer.pullSignal(0.05)
  if status == 'import' then
    if robot.suck(3) then
      robot.drop(0)
    end
  elseif status == 'export' then
    if robot.suck(0) then
      robot.drop(3)
    end
  elseif status == 'stop' then
    computer.pullSignal(0.5)
  end
end
