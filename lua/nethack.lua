--nethack: Net message sniffer by Ott (STEAM_0:0:36527860)
local netTypes = {
	"Entity",
	"Bool",
	"Color",
	"Angle",
	"Bit",
	"Data",
	"Double",
	"Float",
	"Int",
	"Normal",
	"String",
	"Table",
	"Type",
	"UInt",
	"Vector",
}
local specialCases = {
	Entity = {"UInt"},
	Bool = {"Bit"},
	Color = {"UInt", "UInt", "UInt", "UInt"} --TODO: make a proper "ignore" thing
}
local COLOR_TEXT = Color(255, 255, 255)
local COLOR_NUM = Color(255, 128, 0)
local COLOR_STRING = Color(128, 255, 64)
local COLOR_VAR = Color(0, 255, 255)
local shouldPrint
local incomingCount = {}
local outgoingCount = {}
local msgSettings = {}
local lastInMsg = {}
local lastOutMsg = {}
local readQueue = {}
local writeQueue = {}
local interceptIn = {}
local interceptOut = {}
local incomingName
local outgoingName
local function logPrint(name, ...)
	if shouldPrint then
		if msgSettings[name] and not msgSettings[name].shown then return end
		MsgC(...)
	end
end
local function logIncoming(name, length, start)
	if start then
		incomingCount[name] = (incomingCount[name] or 0) + 1
		lastInMsg[name] = {header = {name = name, length = length}}
	end
	if start then
		incomingName = name
		logPrint(name, COLOR_TEXT, "\n\nStarted ", COLOR_VAR, "incoming", COLOR_TEXT, " net message ", COLOR_STRING, "\"" .. name .. "\"", COLOR_TEXT, " of length ", COLOR_NUM, length .. ".")
	else
		logPrint(name, COLOR_TEXT, "\nEnded ", COLOR_VAR, "incoming", COLOR_TEXT, " net message ", COLOR_STRING, "\"" .. name .. "\"", COLOR_TEXT, " of length ", COLOR_NUM, length .. ".\n")
		incomingName = nil
	end
end
local function logOutgoing(start, name, unreliable)
	name = name or outgoingName
	if not name then return end
	if start then
		outgoingCount[name] = (outgoingCount[name] or 0) + 1
		lastOutMsg[name] = {header = {name = name, length = 0}}
	else
		lastOutMsg[name].header.length = net.BytesWritten()
	end
	if start then
		outgoingName = name
		logPrint(name, COLOR_TEXT, "\n\nStarted ", COLOR_VAR, "outgoing", COLOR_TEXT, " net message ", COLOR_STRING, "\"" .. name .. "\"", COLOR_TEXT, ".")
	else
		logPrint(outgoingName, COLOR_TEXT, "\nEnded ", COLOR_VAR, "outgoing", COLOR_TEXT, " net message ", COLOR_STRING, "\"" .. outgoingName .. "\"", COLOR_TEXT, " of length ", COLOR_NUM, length, COLOR_TEXT, ". Total size: ", COLOR_NUM, net.BytesWritten(), COLOR_TEXT, ".\n")
		outgoingName = nil
	end
end

local function shouldLogRead(type, val, args)
	--[[
	local last = lastInMsg[incomingName]
	if not last then return end
	if #last > 0 then
		if last[#last].type == "UInt" and last[#last].arg == 16 and type == "Entity" then
			if not last.ignoredlast then
				last[#last] = nil
				last.ignoredlast = true
				return true
			else
				last.ignoredlast = false
			end
		end
	end
	--]]
	return true
end
local function logRead(type, val, ...)
	local args = {...}
	if shouldLogRead(type, val, args) then
		if lastInMsg[incomingName] then
			lastInMsg[incomingName][#lastInMsg[incomingName] + 1] = {type = type, val = val, arg = args[1]}
		end
		if #args > 0 then
			logPrint(incomingName, COLOR_TEXT, "\n\tRead ", COLOR_VAR, tostring(type), COLOR_TEXT, " of value ", COLOR_STRING, "'" .. tostring(val) .. "'", COLOR_TEXT, " with parameters ", COLOR_VAR, "{" .. table.concat(args, ", ") .. "}", COLOR_TEXT, ".")
		else
			logPrint(incomingName, COLOR_TEXT, "\n\tRead ", COLOR_VAR, tostring(type), COLOR_TEXT, " of value ", COLOR_STRING, "'" .. tostring(val) .. "'", COLOR_TEXT, ".")
		end
	end
end

local function shouldLogWrite(type, val, args)
	--[[
	local last = lastOutMsg[outgoingName]
	if not last then return end
	if #last > 0 then
		if last[#last].type == "Entity" and type == "UInt" and args[1] == 16 then
			if not last.ignoredlast then
				last.ignoredlast = true
				return false
			else
				last.ignoredlast = false
			end
		end
	end
	--]]
	return true
end
local function logWrite(type, val, ...)
	local args = {...}
	if shouldLogWrite(type, val, args) then
		if lastOutMsg[outgoingName] then
			lastOutMsg[outgoingName][#lastOutMsg[outgoingName] + 1] = {type = type, val = val, arg = args[1]}
		end
		if #args > 0 then
			logPrint(outgoingName, COLOR_TEXT, "\n\tWrote ", COLOR_VAR, tostring(type), COLOR_TEXT, " of value ", COLOR_STRING, "'" .. tostring(val) .. "'", COLOR_TEXT, " with parameters ", COLOR_VAR, "{" .. table.concat(args, ", ") .. "}", COLOR_TEXT, ".")
		else
			logPrint(outgoingName, COLOR_TEXT, "\n\tWrote ", COLOR_VAR, tostring(type), COLOR_TEXT, " of value ", COLOR_STRING, "'" .. tostring(val) .. "'", COLOR_TEXT, ".")
		end
	end
end
local function convertToType(val, type)
	local num = tonumber(val)
	if type == "Float" and num then
		return num
	elseif type == "Int" and num then
		return math.floor(num)
	elseif type == "UInt" and num then
		return math.abs(math.floor(num))
	elseif type == "Entity" then
		return Entity(val)
	elseif type == "Bool" then
		return val == "true" or false
	elseif type == "Angle" then
		local exp = string.Explode("%D+", val, true)
		return Angle(unpack(exp))
	elseif type == "Vector" then
		local exp = string.Explode("%D+", val, true)
		return Vector(unpack(exp))
	elseif type == "Color" then
		local exp = string.Explode("%D+", val, true)
		return Color(unpack(exp))
	end
	return val
end
local netFunctions = {}
local netIncoming
local netStart
local netSendToServer
local ignoreIn
local ignoreOut
local function hook()
	for i = 1, #netTypes do
		netFunctions[i] = net["Read"..netTypes[i]]
		net["Read" .. netTypes[i]] = function(...)
			if msgSettings[incomingName] and msgSettings[incomingName].sin then return end
			local val
			if #readQueue > 0 then
				local pval = convertToType(table.remove(readQueue, 1), netTypes[i])
				if pval ~= "NETHACK_NOVALUE" then
					val = pval
				else
					if specialCases[netTypes[i]] then
						ignoreIn = true
						val = netFunctions[i](...)
						ignoreIn = false
					else
						val = netFunctions[i](...)
					end
				end
			else
				if specialCases[netTypes[i]] then
					ignoreIn = true
					val = netFunctions[i](...)
					ignoreIn = false
				else
					val = netFunctions[i](...)
				end
			end
			if not ignoreIn then
				logRead(netTypes[i], val, ...)
			end
			return val
		end
	end
	for i = 1, #netTypes do
		netFunctions[i + #netTypes] = net["Write"..netTypes[i]]
		net["Write" .. netTypes[i]] = function(val, ...)
			if outgoingName and msgSettings[outgoingName] and msgSettings[outgoingName].sout then return end
			if #writeQueue > 0 then
				local pval = convertToType(table.remove(writeQueue, 1), netTypes[i])
				if pval ~= "NETHACK_NOVALUE" then
					val = pval
				end
			end
			logWrite(netTypes[i], val, ...)
			netFunctions[i + #netTypes](val, ...)
		end
	end
	netIncoming = net.Incoming
	function net.Incoming( len, client )
		local i = net.ReadHeader()
		local strName = util.NetworkIDToString( i )
		if ( !strName ) then return end
		local func = net.Receivers[ strName:lower() ]
		if ( !func ) then return end
		len = len - 16
		if msgSettings[strName] and msgSettings[strName].sin then return end
		if interceptIn[strName] then
			readQueue = table.Copy(interceptIn[strName])
		end
		logIncoming(strName, len, true)
		func(len, client)
		logIncoming(strName, len, false)
		readQueue = {}
	end
	netStart = net.Start
	function net.Start(name, unreliable)
		if msgSettings[name] and msgSettings[name].sout then return end
		if interceptOut[name] then
			writeQueue = table.Copy(interceptOut[name])
		end
		logOutgoing(true, name, unreliable)
		netStart(name, unreliable)
	end
	netSendToServer = net.SendToServer
	function net.SendToServer()
		if msgSettings[outgoingName] and msgSettings[outgoingName].sout then return end
		writeQueue = {}
		logOutgoing(false)
		netSendToServer()
	end
end
local function unhook()
	for i = 1, #netTypes do
		net["Read"..netTypes[i]] = netFunctions[i]
	end
	for i = 1, #netTypes do
		net["Write"..netTypes[i]] = netFunctions[i + #netTypes]
	end
	net.Incoming = netIncoming
	net.Start = netStart
	net.SendToServer = netSendToServer
end

CreateClientConVar("nethack_enabled", 1)
cvars.AddChangeCallback("nethack_enabled", function(name, value_old, value_new)
	if GetConVarNumber("nethack_enabled") == 1 then
		hook()
	elseif GetConVarNumber("nethack_enabled") == 0 then
		unhook()
	end
end)
if GetConVarNumber("nethack_enabled") == 1 then
	hook()
end

CreateClientConVar("nethack_print", 1)
cvars.AddChangeCallback("nethack_print", function(name, value_old, value_new)
	if GetConVarNumber("nethack_print") == 1 then
		shouldPrint = true
	elseif GetConVarNumber("nethack_print") == 0 then
		shouldPrint = false
	end
end)
if GetConVarNumber("nethack_print") ~= 0 then
	shouldPrint = true
end






concommand.Add("nethack_menu", function()
	local frame = vgui.Create( "DFrame" )
	frame:SetTitle("Nethack :: Configuration")
	frame:SetSize(500, 300)
	frame:SetVisible( true )
	frame:SetDraggable( true )
	frame:Center()
	frame:MakePopup()

	local list = vgui.Create("DListView", frame)
	list:SetPos(5, 25)
	list:SetSize(95 + 175, 270)
	list:SetMultiSelect(false)
	list:AddColumn("Message")
	local cin = list:AddColumn("In")
	local cout = list:AddColumn("Out")
	cin:SetFixedWidth(50)
	cout:SetFixedWidth(50)
	
	local msgs = table.Copy(incomingCount)
	local msgs2 = table.Copy(outgoingCount)
	table.Merge(msgs, msgs2)
	local keys = table.GetKeys(msgs)
	local lines = {}
	table.sort(keys, function (one, two)
		return one < two
	end)

	for _, name in ipairs(keys) do
		lines[name] = list:AddLine(name, incomingCount[name] or 0, outgoingCount[name] or 0)
	end
	
	timer.Destroy("nethack_update")
	timer.Create("nethack_update", 1, 0, function()
		if IsValid(frame) then
			local msgs = table.Copy(incomingCount)
			local msgs2 = table.Copy(outgoingCount)
  			table.Merge(msgs, msgs2)
  			local keys = table.GetKeys(msgs)
			for i = 1, #keys do
				local name = keys[i]
				if IsValid(lines[name]) then
					lines[name]:SetValue(2, incomingCount[name] or 0)
					lines[name]:SetValue(3, outgoingCount[name] or 0)
				else
					lines[name] = list:AddLine(name, incomingCount[name] or 0, outgoingCount[name] or 0)
				end
			end
			list:SortByColumn(1)
		end
	end)
	
	local panel = vgui.Create("DPanel", frame)
	panel:SetPos(105 + 175, 25)
	panel:SetSize(390 - 175, 270)
	panel:SetBackgroundColor(Color(234, 234, 234, 255))

	list.OnRowSelected = function(self, line)
		local name = self:GetLine(line):GetValue(1)
		panel:Clear()
 
		local props = vgui.Create("DProperties", panel)
		props:SetPos(0, 0)
		props:SetSize(390, 250 - 20)

		msgSettings[name] = msgSettings[name] or {
			shown = true,
			sin = false,
			sout = false,
		}
		local msg = msgSettings[name]
		local general = props:CreateRow("General", "Shown?")
		general:Setup("Boolean")
		general:SetValue(msg.shown)
		general.DataChanged = function (self, value)
			msg.shown = value ~= 0
		end
		local general = props:CreateRow("General", "Suppress in?")
		general:Setup("Boolean")
		general:SetValue(msg.sin)
		general.DataChanged = function (self, value)
			msg.sin = value ~= 0
		end
		local general = props:CreateRow("General", "Suppress out?")
		general:Setup("Boolean")
		general:SetValue(msg.sout)
		general.DataChanged = function (self, value)
			msg.sout = value ~= 0
		end
		
		local help = vgui.Create("DButton", panel)
		help:SetPos(390 - 175 - 20, 250 - 20)
		help:SetSize(20, 20)
		help:SetText("?")
		help.DoClick = function()
			local hframe = vgui.Create("DFrame")
			hframe:SetTitle("Nethack :: Help")
			hframe:SetSize(500, 300)
			hframe:SetVisible( true )
			hframe:SetDraggable( true )
			hframe:MakePopup()
			local fx, fy = frame:GetPos()
			hframe:SetPos(fx - 500, fy)
			local hpan = vgui.Create("DPanel", hframe)
			hpan:Dock(FILL)
		end
		
		local explore = vgui.Create("DButton", panel)
			explore:SetPos(0, 250 - 20)
			explore:SetSize(390 - 175 - 20, 20)
			explore:SetText("Explore...")
			explore.DoClick = function()
				local lastTable = lastInMsg
				local nlist
				local sprop
				local iprop
				local srows = {}
				local irows = {}
				local inorout = true
				
				local function updatesprop()
					if lastTable[name] then
						for i = 1, #lastTable[name] do
							local msg = lastTable[name][i]
							local a
							if msg.arg then
								a = sprop:CreateRow("General", i .. ". " .. (msg.type or "<none>") .. " (" .. msg.arg .. ")")
							else
								a = sprop:CreateRow("General", i .. ". " .. (msg.type or "<none>"))
							end
							a:Setup("Generic", {})
							a.DataChanged = function(self, value)
								a.val = value
							end
							srows[#srows + 1] = {row = a, msg = msg}
						end
					end
				end
				local function updateiprop()
					if lastTable[name] then
						for i = 1, #lastTable[name] do
							local msg = lastTable[name][i]
							local a
							if msg.arg then
								a = iprop:CreateRow("General", i .. ". " .. (msg.type or "<none>") .. " (" .. msg.arg .. ")")
							else
								a = iprop:CreateRow("General", i .. ". " .. (msg.type or "<none>"))
							end
							a:Setup("Generic", {})
							a.DataChanged = function(self, value)
								a.val = value
							end
							irows[#irows + 1] = {row = a, msg = msg}
						end
					end
				end
				local function updatenlist()
					if lastTable[name] then
						for i = 1, #lastTable[name] do
							nlist:AddLine(lastTable[name][i].type, lastTable[name][i].val, lastTable[name][i].arg)
						end
					end
				end
				
				local exframe = vgui.Create("DFrame")
					exframe:SetTitle("Nethack :: " .. name .. " :: Explore")
					exframe:SetSize(500, 300)
					exframe:SetVisible( true )
					exframe:SetDraggable( true )
					exframe:MakePopup()
					local fx, fy = frame:GetPos()
					local fw, fh = frame:GetSize()
					exframe:SetPos(fx + fw, fy)
					
					local props = vgui.Create("DPropertySheet", exframe)
						props:SetPos(0, 25)
						props:SetSize(500, 300 - 25)
						
						local inout = vgui.Create("DCheckBoxLabel", exframe)
							inout:SetPos(500 - 100, 25)
							inout:SetText("In/Out Toggle")
							inout:SetValue(1)
							inout:SizeToContents()
							inout.OnChange = function(val)
								if val:GetChecked() then
									lastTable = lastInMsg
									inorout = true
								else
									lastTable = lastOutMsg
									inorout = false
								end
								nlist:Clear()
								updatenlist()
								sprop:Clear()
								updatesprop()
							end
						---inout
						
						local viewpanel = vgui.Create("DPanel")
							nlist = vgui.Create("DListView", viewpanel)
								nlist:Dock(FILL)
								nlist:AddColumn("Type")
								nlist:AddColumn("Value")
								nlist:AddColumn("Parameter")
								updatenlist()
								function nlist:DoDoubleClick(id, line)
									SetClipboardText(line.Columns[2]:GetValue())
									notification.AddLegacy("Content copied to clipboard.", NOTIFY_UNDO, 3)
									surface.PlaySound("buttons/button15.wav")
								end
							---nlist
						---viewpanel
						
						local explorepanel = vgui.Create("DPanel")
							local etex = vgui.Create("RichText", explorepanel)
								etex:Dock(FILL)
								etex:InsertColorChange(128, 128, 255, 255)
								local func = net.Receivers[string.lower(name)]
								if func then
									local info = debug.getinfo(func)
									local src = info.short_src
									etex:AppendText(src .. "\n")
									etex:InsertColorChange(0, 0, 0, 196)
									local file = file.Open(src, "r", "MOD")
									if file then
										local str = file:Read(file:Size())
										file:Close()
										local lines = {}
										local cursor = 1
										while true do
											local pos = string.find(str, "\n", cursor)
											if pos then
												lines[#lines + 1] = string.sub(str, cursor, pos - 1)
												cursor = pos + 1
											else
												break
											end
										end
										for ln = 1, #lines do
											if ln == info.linedefined then
												etex:InsertColorChange(0, 0, 0, 255)
											elseif ln == info.lastlinedefined + 1 then
												etex:InsertColorChange(0, 0, 0, 196)
											end
											etex:AppendText(lines[ln] .. "\n")
										end
									else
										etex:AppendText("Could not read file.")
									end
								else
									etex:AppendText("Could not read function.")
								end
							---etex
						---explorepanel
						
						local interceptpanel = vgui.Create("DPanel")
							iprop = vgui.Create("DProperties", interceptpanel)
								iprop:Dock(FILL)
								updateiprop()
							---iprop
							local tbar = vgui.Create("DPanel", interceptpanel)
								tbar:SetSize(0, 25)
								tbar:Dock(BOTTOM)
								local ibut = vgui.Create("DButton", tbar)
									ibut:SetText("Apply")
									ibut:SetSize(242, 0)
									ibut:Dock(LEFT)
									ibut.DoClick = function()
										if inorout then
											interceptIn[name] = {}
											for i = 1, #irows do
												print(i)
												local msg = irows[i].msg
												local a = irows[i].row
												local val = a.val
												print(val, type(val), type(val) == "string" and #val)
												interceptIn[name][i] = val or "NETHACK_NOVALUE"
											end
										else
											interceptOut[name] = {}
											for i = 1, #irows do
												local msg = irows[i].msg
												local a = irows[i].row
												local val = a.val
												if type(val) == "string" then
													if #val == 0 then
														val = nil
													end
												end
												interceptOut[name][i] = val or "NETHACK_NOVALUE"
											end
										end
									end
								---ibut
								local iclear = vgui.Create("DButton", tbar)
									iclear:SetText("Clear")
									iclear:SetSize(242, 0)
									iclear:Dock(RIGHT)
									iclear.DoClick = function()
										iprop:Clear()
										updateiprop()
										if inorout then
											interceptIn[name] = nil
										else
											interceptOut[name] = nil
										end
									end
								---iclear
							---tbar
						---interceptpanel
						
						local spoofpanel = vgui.Create("DPanel")
							sprop = vgui.Create("DProperties", spoofpanel)
								sprop:Dock(FILL)
								updatesprop()
							---sprop
							local sbut = vgui.Create("DButton", spoofpanel)
								sbut:SetSize(0, 25)
								sbut:Dock(BOTTOM)
								sbut:SetText("Spoof")
								sbut.DoClick = function()
									if lastTable[name] then
										local ltab = lastTable[name]
										if inorout then
											for i = 1, #srows do
												local dmsg = ltab[i] or {}
												local msg = srows[i].msg
												local a = srows[i].row
												local val = a.val
												if type(val) == "string" and #val == 0 then
													val = nil
												end
												readQueue[i] = val or dmsg.val
												print(name, i, val, dmsg.val)
											end
											logIncoming(name, 0, true)
											net.Receivers[string.lower(name)]()
											logIncoming(name, 0, false)
										else
											net.Start(name)
											for i = 1, #srows do
												local dmsg = ltab[i] or {}
												local msg = srows[i].msg
												local a = srows[i].row
												local val = a.val
												net["Write" .. msg.type](convertToType(val or dmsg.val, msg.type), msg.arg)
											end
											net.SendToServer()
										end
									end
								end
							---sbut
						---spoofpanel
							
						local viewtab = props:AddSheet("View", viewpanel).Tab
							viewtab.DoClick = function(self)
								self:GetPropertySheet():SetActiveTab( self )
								nlist:Clear()
								updatenlist()
							end
						---viewtab
						
						props:AddSheet("Explore", explorepanel)
						props:AddSheet("Intercept", interceptpanel)
						props:AddSheet("Spoof", spoofpanel)
					---props
				---exframe
			end
		---explore
		
		local container = vgui.Create("DPanel", panel)
			container:SetPos(0, 250)
			container:SetSize(390 - 175, 20)
			container:SetToolTip(msg.Demsgion)
		---container

		local info = vgui.Create("DLabel", container)
			info:SetPos(0, 0)
			info:SetText(name)
			info:SetDark(1)
			info:SizeToContents()
			info:CenterHorizontal(0.5)
			info:CenterVertical(0.5)
		---info
	end
end)