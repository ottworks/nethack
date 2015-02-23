--Net Message Sniffer by Ott (STEAM_0:0:36527860)
local netTypes = {
	"Angle",
	"Bit",
	"Bool",
	"Color",
	"Data",
	"Double",
	"Entity",
	"Float",
	"Int",
	"Normal",
	"String",
	"Table",
	"Type",
	"UInt",
	"Vector",
}
local COLOR_TEXT = Color(255, 255, 255)
local COLOR_NUM = Color(255, 128, 0)
local COLOR_STRING = Color(128, 255, 64)
local COLOR_VAR = Color(0, 255, 255)
local shouldPrint
local incomingCount = {}
local outgoingCount = {}
local msgSettings = {}
local function snifferPrint(name, ...)
	if shouldPrint then
		if msgSettings[name] and not msgSettings[name].shown then return end
		MsgC(...)
	end
end
local incomingName
local function logIncoming(name, length, start)
	incomingCount[name] = (incomingCount[name] or 0) + 1
	if start then
		incomingName = name
		snifferPrint(name, COLOR_TEXT, "\n\nStarted ", COLOR_VAR, "incoming", COLOR_TEXT, " net message ", COLOR_STRING, "\"" .. name .. "\"", COLOR_TEXT, " of length ", COLOR_NUM, length .. ".")
	else
		snifferPrint(name, COLOR_TEXT, "\nEnded ", COLOR_VAR, "incoming", COLOR_TEXT, " net message ", COLOR_STRING, "\"" .. name .. "\"", COLOR_TEXT, " of length ", COLOR_NUM, length .. ".\n")
		incomingName = nil
	end
end
local outgoingName
local function logOutgoing(start, name, unreliable)
	name = name or outgoingName
	outgoingCount[name] = (outgoingCount[name] or 0) + 1
	if start then
		outgoingName = name
		snifferPrint(name, COLOR_TEXT, "\n\nStarted ", COLOR_VAR, "outgoing", COLOR_TEXT, " net message ", COLOR_STRING, "\"" .. name .. "\"", COLOR_TEXT, ".")
	else
		snifferPrint(outgoingName, COLOR_TEXT, "\nEnded ", COLOR_VAR, "outgoing", COLOR_TEXT, " net message ", COLOR_STRING, "\"" .. outgoingName .. "\"", COLOR_TEXT, " of length ", COLOR_NUM, length, COLOR_TEXT, ". Total size: ", COLOR_NUM, net.BytesWritten(), COLOR_TEXT, ".\n")
		outgoingName = nil
	end
end
local function logRead(type, val, ...)
	local args = {...}
	if #args > 0 then
		snifferPrint(incomingName, COLOR_TEXT, "\n\tRead ", COLOR_VAR, tostring(type), COLOR_TEXT, " of value ", COLOR_STRING, "'" .. tostring(val) .. "'", COLOR_TEXT, " with parameters ", COLOR_VAR, "{" .. table.concat(args, ", ") .. "}", COLOR_TEXT, ".")
	else
		snifferPrint(incomingName, COLOR_TEXT, "\n\tRead ", COLOR_VAR, tostring(type), COLOR_TEXT, " of value ", COLOR_STRING, "'" .. tostring(val) .. "'", COLOR_TEXT, ".")
	end
end
local function logWrite(type, val, ...)
	local args = {...}
	if #args > 0 then
		snifferPrint(outgoingName, COLOR_TEXT, "\n\tWrote ", COLOR_VAR, tostring(type), COLOR_TEXT, " of value ", COLOR_STRING, "'" .. tostring(val) .. "'", COLOR_TEXT, " with parameters ", COLOR_VAR, "{" .. table.concat(args, ", ") .. "}", COLOR_TEXT, ".")
	else
		snifferPrint(outgoingName, COLOR_TEXT, "\n\tWrote ", COLOR_VAR, tostring(type), COLOR_TEXT, " of value ", COLOR_STRING, "'" .. tostring(val) .. "'", COLOR_TEXT, ".")
	end
end
local netFunctions = {}
local netIncoming
local netStart
local netSendToServer
local function hook()
	for i = 1, #netTypes do
		netFunctions[i] = net["Read"..netTypes[i]]
		net["Read" .. netTypes[i]] = function(...)
			local val = netFunctions[i](...)
			logRead(netTypes[i], val, ...)
			return val
		end
	end
	for i = 1, #netTypes do
		netFunctions[i + #netTypes] = net["Write"..netTypes[i]]
		net["Write" .. netTypes[i]] = function(val, ...)
			if outgoingName and msgSettings[outgoingName] and msgSettings[outgoingName].sout then return end
			logWrite(netTypes[i + #netTypes], val, ...)
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
		if msgSettings[name] and msgSettings[name].sin then return end
		logIncoming(strName, len, true)
		func( len, client )
		logIncoming(strName, len, false)
	end
	netStart = net.Start
	function net.Start(name, unreliable)
		if msgSettings[name] and msgSettings[name].sout then return end
		logOutgoing(true, name, unreliable)
	end
	netSendToServer = net.SendToServer
	function net.SendToServer()
		if msgSettings[name] and msgSettings[name].sout then return end
		logOutgoing(false)
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

CreateClientConVar("sniffer_enabled", 1)
cvars.AddChangeCallback("sniffer_enabled", function(name, value_old, value_new)
	if GetConVarNumber("sniffer_enabled") == 1 then
		hook()
	elseif GetConVarNumber("sniffer_enabled") == 0 then
		unhook()
	end
end)
if GetConVarNumber("sniffer_enabled") == 1 then
	hook()
end

CreateClientConVar("sniffer_print", 1)
cvars.AddChangeCallback("sniffer_print", function(name, value_old, value_new)
	if GetConVarNumber("sniffer_print") == 1 then
		shouldPrint = true
	elseif GetConVarNumber("sniffer_print") == 0 then
		shouldPrint = false
	end
end)
if GetConVarNumber("sniffer_print") ~= 0 then
	shouldPrint = true
end

concommand.Add("sniffer_menu", function()
	PrintTable(msgSettings)
	local frame = vgui.Create( "DFrame" )
    frame:SetTitle("Sniffer :: Configuration")
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
    
    timer.Destroy("sniffer_update")
    timer.Create("sniffer_update", 1, 0, function()
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

    list.OnRowSelected = function (self, line)
        panel:Clear()
 
        local props = vgui.Create("DProperties", panel)
        props:SetPos(0, 0)
        props:SetSize(390, 250)

        msgSettings[self:GetLine(line):GetValue(1)] = msgSettings[self:GetLine(line):GetValue(1)] or {
        	shown = true,
        	sin = false,
        	sout = false,
   		}
        local msg = msgSettings[self:GetLine(line):GetValue(1)]
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
--[[
        local keys = table.GetKeys(msg.Config)
        table.sort(keys, function (one, two)
            return one < two
        end)

        for _, name in ipairs(keys) do
            local variable = msg.Config[name]
            local row = props:CreateRow("Variables", name)

            variable.VGUI(row)
            row.Container:SetToolTip(variable.Demsgion)
        end
--]]
        local container = vgui.Create("DPanel", panel)
        container:SetPos(0, 250)
        container:SetSize(390, 20)
        container:SetToolTip(msg.Demsgion)

        local info = vgui.Create("DLabel", container)
        info:SetPos(0, 0)
        info:SetText(self:GetLine(line):GetValue(1))

        info:SetDark(1)
        info:SizeToContents()
        info:CenterHorizontal(0.5)
        info:CenterVertical(0.5)
    end
end)