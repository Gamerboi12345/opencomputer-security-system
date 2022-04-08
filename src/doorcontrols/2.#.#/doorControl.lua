--Experimental, combined door control with ability to be a multi or single door.

--Library for saving/loading table for all this code. all the settings below are saved in it.
local ttf=require("tableToFile")
local doorVersion = "2.2.0"
testR = true

--0 = doorcontrol block. 1 = redstone. 2 = bundled redstone. Always bundled redstone with this version of the code.
local doorType = 2
--if door type is 1 or 2, set this to a num between 0 and 5 for which side.
--bottom = 0; top = 1; back = 2 front = 3 right = 4 left = 5. Should always be 2 for back.
local redSide = 2
--if doortype =2, set this to the color you want to output in.
local redColor = 0
--Delay before the door closes again
local delay = 5
--Which term you want to have the door read.
--Changed heavilly to table of passes. Info in singleDoor
local cardRead = {};

local forceOpen = 1
local bypassLock = 0

local doorAddress = ""

local toggle = 0

local adminCard = "admincard"

local modemPort = 199
local diagPort = 180

local component = require("component")
local gpu = component.gpu
local event = require("event")
local ser = require("serialization")
local term = require("term")
local thread = require("thread")
local process = require("process")
local uuid = require("uuid")
local computer = component.computer

local magReader = component.os_magreader
local modem = component.modem 

local baseVariables = {"name","uuid","date","link","blocked","staff"}
local varSettings = {}
 
local settingData = {}
local extraConfig = {}

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
  
  function splitString(str, sep)
          local sep, fields = sep or ":", {}
          local pattern = string.format("([^%s]+)", sep)
          str:gsub(pattern, function(c) fields[#fields+1] = c end)
          return fields
  end
  
  function openDoor(delayH, redColorH, doorAddressH, toggleH, doorTypeH, redSideH)
    if(toggleH == 0) then
      if(doorTypeH == 0 or doorTypeH == 3)then
        if doorAddressH ~= true then
          component.proxy(doorAddressH).open()
          os.sleep(delayH)
          component.proxy(doorAddressH).close()
        else
          if doorTypeH == 0 then
            component.os_doorcontroller.open()
            os.sleep(delayH)
            component.os_doorcontroller.close()
          else
            component.os_rolldoorcontroller.open()
            os.sleep(delayH)
            component.os_rolldoorcontroller.close()
          end
        end
      elseif(doorTypeH == 1)then
        component.redstone.setOutput(redSideH,15)
        os.sleep(delayH)
        component.redstone.setOutput(redSideH,0)
      elseif(doorTypeH == 2)then
        component.redstone.setBundledOutput(redSideH, { [redColorH] = 255 } )
        os.sleep(delayH)
        component.redstone.setBundledOutput(redSideH, { [redColorH] = 0 } )
      else
        os.sleep(1)
      end
    else
      if(doorTypeH == 0 or doorTypeH == 3)then
        if doorAddressH ~= true then
          component.proxy(doorAddressH).toggle()
        else
          if doorTypeH == 0 then
            component.os_doorcontroller.toggle()
          else
            component.os_rolldoorcontroller.toggle()
          end
        end
      elseif(doorTypeH == 1)then
        if(component.redstone.getOutput(redSideH) == 0) then
            component.redstone.setOutput(redSideH,15)
        else
            component.redstone.setOutput(redSideH,0)
        end
      elseif(doorTypeH == 2)then
        if(component.redstone.getBundledOutput(redSideH, redColorH) == 0) then
        component.redstone.setBundledOutput(redSideH, { [redColorH] = 255 } )
      else
        component.redstone.setBundledOutput(redSideH, { [redColorH] = 0 } )
      end
      else
        os.sleep(1)
      end
    end
  end

  local function update(msg, localAddress, remoteAddress, port, distance, msg, data) --TODO: Move code from all door types here & make it work as single or multi door.
    if (testR == true) then
      data = crypt(data, extraConfig.cryptKey, true)
      if msg == "forceopen" then
        if extraConfig.type == "single" then
          if(doorType == 0)then
            if data == "open" then
              component.os_doorcontroller.open()
            else
              component.os_doorcontroller.close()
            end
          elseif(doorType == 1)then
            component.redstone.setOutput(redSide,data == "open" and 15 or 0)
          elseif(doorType == 2)then
            component.redstone.setBundledOutput(redSide, { [redColor] = data == "open" and 255 or 0 } )
          else
            if data == "open" then
              component.os_rolldoorcontroller.open()
            else
              component.os_rolldoorcontroller.close()
            end
          end
        else
          local keyed = nil
          if data == "open" then
            for key, valued in pairs(settingData) do
              if valued.forceOpen ~= 0 then
                if valued.doorType == 0 then
                  component.proxy(valued.doorAddress).open()
                elseif valued.doorType == 1 then
                  print("potentially broken door at key " .. key .. ": set to redstone")
                elseif valued.doorType == 2 then
                  component.redstone.setBundledOutput(redSide, { [valued.redColor] = 255})
                elseif valued.doorType == 3 then
                  component.proxy(valued.doorAddress).open()
                end
              end
            end
          else
            for key, valued in pairs(settingData) do
              if valued.forceOpen ~= 0 then
                if valued.doorType == 0 then
                  component.proxy(valued.doorAddress).close()
                elseif valued.doorType == 1 then
                  print("potentially broken door at key " .. key .. ": set to redstone")
                elseif valued.doorType == 2 then
                  component.redstone.setBundledOutput(redSide, { [valued.redColor] = 0})
                elseif valued.doorType == 3 then
                  component.proxy(valued.doorAddress).close()
                end
              end
            end
          end
        end
      elseif msg == "remoteControl" then --needs to receive {["id"]="modem id",["key"]="door key if multi",["type"]="type of door change",extras like delay and toggle}
        data = ser.unserialize(data)
        if data.id == component.modem.address then
          if extraConfig.type == "single" then
            if data.type == "base" then
              openDoor(delay,redColor,doorType == 0 and true or doorType == 3 and true or nil,toggle,doorType,redSide)
            elseif data.type == "toggle" then
              openDoor(delay,redColor,doorType == 0 and true or doorType == 3 and true or nil,1,doorType,redSide)
            elseif data.type == "delay" then
              openDoor(data.delay,redColor,doorType == 0 and true or doorType == 3 and true or nil,0,doorType,redSide)
            end
          else
            if data.type == "base" then
              thread.create(openDoor, settingData[data.key].delay, settingData[data.key].redColor, settingData[data.key].doorAddress, settingData[data.key].toggle, settingData[data.key].doorType, settingData[data.key].redSide)
            elseif data.type == "toggle" then
              thread.create(openDoor, settingData[data.key].delay, settingData[data.key].redColor, settingData[data.key].doorAddress, 1, settingData[data.key].doorType, settingData[data.key].redSide)
            elseif data.type == "delay" then
              thread.create(openDoor, data.delay, settingData[data.key].redColor, settingData[data.key].doorAddress, 0, settingData[data.key].doorType, settingData[data.key].redSide)
            end
          end
        end
      end
    end
  end

term.clear()
local fill = io.open("doorSettings.txt", "r")
if fill~=nil then 
  io.close(fill) 
else 
  print("No doorSettings.txt detected. Reinstall door control")
  os.exit()
end
fill = io.open("extraConfig.txt","r")
if fill ~= nil then
  io.close(fill)
else
  print("No config detected. Reinstall door control")
end

extraConfig = ttf.load("extraConfig.txt")
settingData = ttf.load("doorSettings.txt")
extraConfig.version = version
ttf.save(extraConfig,"extraConfig.txt")

local checkBool = false
modem.broadcast(modemPort,"autoInstallerQuery")
local e,_,_,_,_,query = event.pull(3,"modem_message")
query = ser.unserialize(query)
if e ~= nil then
  if extraConfig.type == "single" then
    if type(settingData.cardRead) == "number" then
      modem.broadcast(modemPort,"autoInstallerQuery")
      local e,_,from,port,_,query = event.pull(3,"modem_message")
      query = ser.unserialize(query)
      if e ~= nil then
          settingData.cardRead = settingData.cardRead == 6 and "checkstaff" or query.data.calls[settingData.cardRead - #baseVariables]
      end
      ttf.save(settingData,"doorSettings.txt")
    end
    if type(settingData.cardRead) ~= "table" then
        local t1, t2 = settingData.cardRead, settingData.accessLevel
        settingData.accessLevel = nil
        settingData.cardRead = {}
        settingData.cardRead[1] = {["uuid"]=uuid.next(),["call"]=t1,["param"]=t2,["request"]="supreme",["data"]=false}
        ttf.save(settingData,"doorSettings.txt")
    end
  else
    for key, value in pairs(settingData) do
      if type(value.cardRead) == "number" then
        checkBool = true
        if value.cardRead ~= 6 then
          settingData[key].cardRead = query.data.calls[settingData[key].cardRead - #baseVariables]
        else
          settingData[key].cardRead = "checkstaff"
        end
      end
      if type(value.cardRead) ~= "table" then
        checkBool = true
        local t1, t2 = settingData[key].cardRead, settingData[key].accessLevel
          settingData[key].accessLevel = nil
          settingData[key].cardRead = {}
          settingData[key].cardRead[1] = {["uuid"]=uuid.next(),["call"]=t1,["param"]=t2,["request"]="supreme",["data"]=false}
      end
    end
    if checkBool == true then
      ttf.save(settingData,"doorSettings.txt")
    end
  end
end
checkBool = nil

if modem.isOpen(modemPort) == false then
  modem.open(modemPort)
end

fill = {}
fill["type"] = extraConfig.type
fill["data"] = settingData
modem.broadcast(modemPort,"setDoor",crypt(ser.serialize(fill),extraConfig.cryptKey))
local got, _, _, _, _, fill = event.pull(2, "modem_message")
if got then
  varSettings = ser.unserialize(crypt(fill,extraConfig.cryptKey,true))
else
  print("Failed to receive confirmation from server")
  os.exit()
end
got = nil

if extraConfig.type == "single" then
  doorType = settingData.doorType
	redSide = settingData.redSide
	redColor = settingData.redColor
	delay = settingData.delay
	cardRead = settingData.cardRead
	toggle = settingData.toggle
	forceOpen = settingData.forceOpen
	bypassLock = settingData.bypassLock
  if #cardRead == 1 then
    if cardRead[1].call == "checkstaff" then
      print("STAFF ONLY")
      print("")
    else
      local cardRead2 = 0
      for i=1,#varSettings.calls,1 do
        if varSettings.calls[i] == cardRead[1].call then
          cardRead2 = i
          break
        end
      end
      if cardRead2 ~= 0 then
        print("Checking: " .. varSettings.var[cardRead2])
        if varSettings.type[cardRead2] == "string" or varSettings.type[cardRead2] == "-string" then
          print("Must be exactly " .. cardRead[1].param)
        elseif varSettings.type[cardRead2] == "int" then
          if varSettings.above[cardRead2] == true then
            print("Level " .. tostring(cardRead[1].param) .. " or above required")
          else
            print("Level " .. tostring(cardRead[1].param) .. " exactly required")
          end
        elseif varSettings.type[cardRead2] == "-int" then
          print("Must be group " .. varSettings.data[cardRead2][cardRead[1].param] .. " to enter")
        elseif varSettings.type[cardRead2] == "bool" then
          print("Must have pass to enter")
        end
      else
        print("Code is either broken or config not set up right")
        os.exit()
      end
    end
  else
      print("Multi-Pass Single Door")
      print("Length: " .. #cardRead)
  end
else
  print("Multi-Door Control terminal")
end
print("---------------------------------------------------------------------------")

if modem.isOpen(modemPort) == false then
  modem.open(modemPort)
end
event.listen("modem_message", update)
process.info().data.signal = function(...)
  print("caught hard interrupt")
  event.ignore("modem_message", update)
  testR = false
  os.exit()
end

while true do
  if modem.isOpen(modemPort) == false then
    modem.open(modemPort)
  end
  ev, address, user, str, uuid, data = event.pull("magData")
  local isOk = "ok"
  local keyed = nil
  if extraConfig.type == "multi" then
    for key, valuedd in pairs(settingData) do
      if(valuedd.reader == address) then
        keyed = key
      end
    end
    isOk = "incorrect magreader"
    if(keyed ~= nil)then
      term.write(settingData[keyed].redColor)
      redColor = settingData[keyed].redColor
      delay = settingData[keyed].delay
      cardRead = settingData[keyed].cardRead
      doorType = settingData[keyed].doorType
      doorAddress = settingData[keyed].doorAddress
      toggle = settingData[keyed].toggle
      forceOpen = settingData[keyed].forceOpen
      bypassLock = settingData[keyed].bypassLock
      isOk = "ok"
    else
      print("MAG READER IS NOT SET UP! PLEASE FIX")
      os.exit()
    end
  end
  local data = crypt(str, extraConfig.cryptKey, true)
  if ev then
    if (data == adminCard) then
      term.write("Admin card swiped. Sending diagnostics\n")
      modem.open(diagPort)
      local diagData = extraConfig.type == "multi" and settingData[keyed] or settingData
      if diagData == nil then
        diagData = {}
      end
      diagData["status"] = isOk
      diagData["type"] = extraConfig.type
      diagData["version"] = doorVersion
      diagData["key"] = extraConfig.type == "multi" and keyed or nil
      diagData["num"] = 2
      local counter = 0
      if extraConfig.type == "multi" then
        for index in pairs(settingData) do
          counter = counter + 1
        end
        diagData["entries"] = counter
      end
      data = ser.serialize(diagData)
      modem.broadcast(diagPort, "diag", data)
    else
      if keyed == nil and extraConfig.type == "multi" then
        os.exit()
      end
      local tmpTable = ser.unserialize(data)
      term.write(tmpTable["name"] .. ":")
      if modem.isOpen(modemPort) == false then
        modem.open(modemPort)
      end
      tmpTable["type"] = extraConfig.type
      tmpTable["key"] = extraConfig.type == "multi" and keyed or nil
      data = crypt(ser.serialize(tmpTable), extraConfig.cryptKey)
      modem.broadcast(modemPort, "checkRules", data, bypassLock)
      local e, _, from, port, _, msg = event.pull(1, "modem_message")
      if e then
        data = crypt(msg, extraConfig.cryptKey, true)
        if data == "true" then
          term.write("Access granted\n")
          computer.beep()
          if extraConfig.type == "single" then
            openDoor(delay,redColor,true,toggle,doorType,redSide)
          else
            thread.create(openDoor, delay, redColor, doorAddress, toggle, doorType, redSide)
          end
        elseif data == "false" then
          term.write("Access denied\n")
          computer.beep()
          computer.beep()
        elseif data == "locked" then
          term.write("Doors have been locked\n")
          computer.beep()
          computer.beep()
          computer.beep()
        else
          term.write("Unknown command\n")
        end
      else
        term.write("server timeout\n")
      end
    end
  end
end