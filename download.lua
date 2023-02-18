local REPOSITOTY = "https://raw.githubusercontent.com/TumkoZM/errbk/main"

local shell = require("shell")
shell.execute("wget -f " .. REPOSITOTY .. "/terminal.lua /home/terminal.lua")
shell.execute("wget -f " .. REPOSITOTY .. "/style.gss /home/style.gss")
shell.execute("wget -f " .. REPOSITOTY .. "/start.lua /home/start.lua")
--shell.execute("wget -f " .. REPOSITOTY .. "/robot_bios.lua /home/robot_bios.lua")
shell.execute("wget -f " .. REPOSITOTY .. "/market.db /home/market.db")
shell.execute("wget -f " .. REPOSITOTY .. "/gml.lua /home/gml.lua")
