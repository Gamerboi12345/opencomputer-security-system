local modemPort = 199

local lockDoors = false
local forceOpen = false

local component = require("component")
local event = require("event")
local modem = component.modem 
local ser = require ("serialization")
local term = require("term")
local ios = require("io")
local gpu = component.gpu

local version = "2.2.0"

local redstone = {}

--------Main Functions

local function convert( chars, dist, inv )
  return string.char( ( string.byte( chars ) - 32 + ( inv and -dist or dist ) ) % 95 + 32 )
end


local function crypt(str,k,inv)
  local enc= "";
  for i=1,#str do
    if(#str-k[5] >= i or not inv)then
      for inc=0,3 do
	if(i%4 == inc)then
	  enc = enc .. convert(string.sub(str,i,i),k[inc+1],inv);
	  break;
	end
      end
    end
  end
  if(not inv)then
    for i=1,k[5] do
      enc = enc .. string.char(math.random(32,126));
    end
  end
  return enc;
end

--// exportstring( string )
--// returns a "Lua" portable version of the string
local function exportstring( s )
	s = string.format( "%q",s )
	-- to replace
	s = string.gsub( s,"\\\n","\\n" )
	s = string.gsub( s,"\r","\\r" )
	s = string.gsub( s,string.char(26),"\"..string.char(26)..\"" )
	return s
end
--// The Save Function
function saveTable(  tbl,filename )
	local tableFile = assert(io.open(filename, "w"))
  tableFile:write(ser.serialize(tbl))
  tableFile:close()
end
 
--// The Load Function
function loadTable( sfile )
	local tableFile = io.open(sfile)
    if tableFile ~= nil then
  		return ser.unserialize(tableFile:read("*all"))
    else
        return nil
    end
end

function advWrite(text,color,wrap)
  gpu.setForeground(color or gpu.getForeground())
  term.write(text,wrap or true)
end
--------Getting tables and setting up terminal
term.clear()
local settingTable = loadTable("settings.txt")
if settingTable == nil then
  print("Security server requires settings to be set")
  print("...")
  print("If you are not leaving cryptKey at default, make sure you change it in settings.txt")
  settingTable = {["cryptKey"]={1,2,3,4,5}}
  saveTable(settingTable,"settings.txt")
end

advWrite("Security server version: " .. version .. "\n",0xFFFFFF)
advWrite("---------------------------------------------------------------------------\n")

settingTable = loadTable("settings.txt")
local userTable = loadTable("userlist.txt")
local doorTable = loadTable("doorlist.txt")
local baseVariables = {"name","uuid","date","link","blocked","staff"}
if userTable == nil then
  userTable = {["settings"]={["var"]={"level"},["label"]={"Level"},["calls"]={"checkLevel"},["type"]={"int"},["above"]={true},["data"]={false}}} --sets up setting var with one setting to start with.
end
if doorTable == nil then
  doorTable = {}
end

--------account functions

function getPassID(command)
  for i=1,#userTable.settings.calls,1 do
    if command == userTable.settings.calls[i] then
      return true, i
    end
  end
  if command == "checkStaff" then
  return command == "checkStaff" and true or false, command == "checkStaff" and 0 or false
end

function getVar(var,user)
   for key, value in pairs(userTable) do
    if value.uuid == user then
      return value[var]
    end
  end
   return "Nil "..var
end

function checkVar(rule,user,index)
  if index ~= 0 then
    if userTable.settings.type[index] == "string" or userTable.settings.type[index] == "-string" then
      return user[userTable.settings.var[index]] == rule.param
    elseif userTable.settings.type[index] == "int" or userTable.settings.type[index] == "-int" then
      if userTable.settings.above[index] == false or userTable.settings.type[index] == "-int" then
        return user[userTable.settings.var[index]] == rule.param
      else
        return user[userTable.settings.var[index]] >= rule.param
      end
    elseif userTable.settings.type[index] == "bool" then
      return user[userTable.settings.var[index]]
    end
  else
    return user.staff
  end
  return false
end
--return true, not value.blocked, value[var], value.staff
function checkAdvVar(user,rules) --{["uuid"]=uuid.next()["call"]=t1,["param"]=t2,["request"]="supreme",["data"]=false}
  local label,color = "will be set",0x000000
  for key, value in pairs(userTable) do--TODO: FInish this
    if value.uuid == user then
      local skipBase = false
      for i=1,#rules,1 do
        if rules[i].request == "reject" then
          local e, call = getPassID(rules[i].call)
          if e then
            local good = checkVar(rules[i],value,call)
            if good then
              label,color = "Denied: var " .. call ~= 0 and userTable.settings.var[call] or "staff" .. " is rejected", 0xFF0000 --TODO: set the color to right red
              skipBase = true
              break
            end
          end
        end
      end
      if ~skipBase then
        for i=1,#rules,1 do
          if rules[i].request == "base" then
            local e, call = getPassID(rules[i].call)
            if e then
              local good = checkVar(rules[i],value,call)
              if good then
                label,color = "Accepted by base var " .. call ~= 0 and userTable.settings.var[call] or "staff", 0x00FF00
                local isGood = true
                for j=1,#rules[i].data,1 do
                  e, call = getPassID(rules[i].data[j])
                  if e then
                    good = checkVar(rules[i],value,call)
                    if good == false then
                      isGood = false
                      label,color = "Denied: did not meet base requirements", 0xFF0000
                      break
                    end
                  end
                end
                if isGood then
                  return true, not value.blocked, true, value.staff,label,color
                end
              end
            end
          end
        end
      end
      for i=1,#rules,1 do
        if rules[i].request == "supreme" then
          local e,call = getPassID(rules[i].call)
          if e then
            local good = checkVar(rules[i],value,call)
            if good then
              label,color = "Accepted by supreme var " .. call ~= 0 and userTable.settings.var[call] or "staff", 0x00FF00
              return true, not value.blocked, true, value.staff,label,color
            else
              return true, not value.blocked, false, value.staff,label,color
            end
          end
        end
      end
    end
  end
  return false
end

function getDoorInfo(type,id,key)
  if type == "multi" then
    for i=1,#doorTable,1 do --doorTable[i] = {type="single or multi",id="computer's modem uuid",data={door's setting table}}
      if doorTable[i].id == id then
        if doorTable[i].data[key]~=nil then
          return {["read"]=doorTable[i].data[key].cardRead,["name"]=doorTable[i].data[key].name}
        end
      end
    end
  else
    for i=1,#doorTable,1 do --doorTable[i] = {type="single or multi",id="computer's modem uuid",data={door's setting table}}
      if doorTable[i].id == id then
        return {["read"]=doorTable[i].data.cardRead,["name"]=doorTable[i].data.name}
      end
    end
  end
  return nil
end

function checkStaff(user)
  for key, value in pairs(userTable) do
    if value.uuid == user then
      return true, not value.blocked, value.staff
    end
  end
  return false
end

function checkLink(user)
  for key, value in pairs(userTable) do
    if value.link == user then
      return true, not value.blocked, value.name
    end
  end
  return false
end

redstone = {}
redstone["lock"] = false
redstone["forceopen"] = false
while true do --TODO: Add new pass system check to this
  if modem.isOpen(modemPort) == false then
    modem.open(modemPort)
  end

  local _, _, from, port, _, command, msg, bypassLock = event.pull("modem_message")
  local data = msg
  if command ~= "autoInstallerQuery" and command ~= "remotecontrol" then data = crypt(msg, settingTable.cryptKey, true) end
  local thisUserName = false
  if command ~= "updateuserlist" and command ~= "setDoor" and command ~= "redstoneUpdated" and command ~= "checkLinked" and command ~= "autoInstallerQuery" and command ~= "remotecontrol" then
    data = ser.unserialize(data)
    thisUserName = getVar("name",data.uuid)
  end
  if command == "updateuserlist" then
    userTable = ser.unserialize(data)
    advWrite("Updated userlist received\n",0x0000C0)
    saveTable(userTable, "userlist.txt")
  elseif command == "autoInstallerQuery" then
    data = {}
    data.num = 2
    data.version = version
    data.data = userTable.settings
    modem.send(from,port,ser.serialize(data))
  elseif command == "setDoor" then
    advWrite("Received door parameters from id: " .. from .. "\n",0xFFFF80)
    local tmpTable = ser.unserialize(data)
    tmpTable["id"] = from
    local isInAlready = false
    for i=1,#doorTable,1 do
      if doorTable[i].id == from then
        isInAlready = true
        doorTable[i] = tmpTable
        break
      end
    end
    if isInAlready == false then table.insert(doorTable,tmpTable) end
    saveTable(doorTable, "doorlist.txt")
    modem.send(from,port,crypt(ser.serialize(userTable.settings),settingTable.cryptKey))
  elseif command == "remotecontrol" then
    advWrite("Coming soon?\n",0xFF0000) --IDEA: allow remote control pc sometime in future
    --data = ser.unserialize(data) --{["call"]="the call as what to do",["par1"]=stored params,["par2"]=stored params 2,continued}
    --if data.call == "openDoor" --Don't know if going to do all control on server or if it's going to send door info to the device. I'm going to send door info.
    modem.send(from,port,ser.serialize(doorTable))
    advWrite("Sent door info to remote door control tablet\n",0x0000C0)
  elseif command == "redstoneUpdated" then
    advWrite("Redstone has been updated\n",0x0000C0)
    local newRed = ser.unserialize(data)
    if newRed["lock"] ~= redstone["lock"] then
      lockDoors = newRed["lock"]
    end
    if newRed["forceopen"] ~= redstone["forceopen"] then
      forceopen = newRed["forceopen"]
      if forceopen == true then
        data = crypt("open",settingTable.cryptKey)
        modem.broadcast(199,"forceopen",data)
      else
        data = crypt("close",settingTable.cryptKey)
        modem.broadcast(199,"forceopen",data)
      end
    end
    redstone = newRed
  elseif command == "checkLinked" then
    if false == true then
      gpu.setForeground(0xFF0000)
      term.write("DONT RUN or i b sad ;-;\n")
    else
      advWrite("-Checking if device is linked to a user:\n",0xFFFF80)
      local cu, isBlocked, thisName = checkLink(data)
      local dis = {}
      if cu == true then
        if isBlocked == false then
          dis["status"] = false
          dis["reason"] = 2
          data = crypt(ser.serialize(dis), settingTable.cryptKey)
          advWrite(" user " .. thisName .. "is blocked\n",0xFF0000)
          modem.send(from, port, data)
        else
          dis["status"] = true
          dis["name"] = thisName
          data = crypt(ser.serialize(dis), settingTable.cryptKey)
          advWrite(" tablet is connected to " .. thisName .. "\n",0x00FF00)
          modem.send(from, port, data)
        end
      else
        dis["status"] = false
        dis["reason"] = 1
        data = crypt(ser.serialize(dis), settingTable.cryptKey)
        advWrite(" tablet not linked\n",0x990000)
        modem.send(from, port, data)
      end--IMPORTANT: Hello
    end
  elseif command == "checkRules" then
    if lockDoors == true and bypassLock ~= 1 then
      advWrite("Doors have been locked. Unable to open door\n",0xFF0000)
      data = crypt("locked", settingTable.cryptKey)
      modem.send(from, port, data)
    else
      local currentDoor = getDoorInfo(data.type,from,data.key)
      advWrite("-Checking user " .. thisUserName .. "'s credentials on currentDoor.name",0xFFFF80)
      local cu, isBlocked, varCheck, isStaff,label,color = checkAdvVar(data.uuid,currentDoor.read)
      if cu then
        if ~isBlocked then
          if varCheck then
            data = crypt("true", settingTable.cryptKey)
            advWrite("\n" .. label .. "\n",color)
            modem.send(from, port, data)
          else
            if isStaff then
              data = crypt("true", settingTable.cryptKey)
              advWrite("\naccess granted due to staff\n",0xFF00FF)
              modem.send(from, port, data)
            else
              data = crypt("false", settingTable.cryptKey)
              advWrite("\n" .. label .. "\n",color)
              modem.send(from, port, data)
            end
          end
        else
          data = crypt("false", settingTable.cryptKey)
          advWrite("\nuser is blocked\n",0xFF0000)
          modem.send(from, port, data)
        end
      else
        data = crypt("false", settingTable.cryptKey)
        advWrite("\nuser not found\n",0x990000)
        modem.send(from, port, data)
      end
    end
  end
   gpu.setForeground(0xFFFFFF)
end
