local version = "2.2.0"
--testR = true

local security = {}

local cardRead = {};

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

--------TableToFile

function saveTable(  tbl,filename )
	local tableFile = assert(io.open(filename, "w"))
  tableFile:write(ser.serialize(tbl))
  tableFile:close()
end
 
function loadTable( sfile )
	local tableFile = io.open(sfile)
    if tableFile ~= nil then
  		return ser.unserialize(tableFile:read("*all"))
    else
        return nil
    end
end

--------Base Functions

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

  --------Called Functions

  function security.setup()
    local fill = io.open("extraConfig.txt", "r")
    if fill ~= nil then
      io.close(fill)
    else
      local config = {}
      config.cryptKey = {}
      term.clear()
      print("First Time Config Setup: Would you like to use default cryptKey? 1 for yes, 2 for no")
      local text = term.read()
      if tonumber(text) == 2 then
        print("there are 5 parameters, each requiring a number. Recommend doing 1 digit numbers")
        for i=1,5,1 do
          print("enter param " .. i)
          text = term.read()
          config.cryptKey[i] = tonumber(text)
        end
      else
        config.cryptKey = {1,2,3,4,5}
      end
      config.type = "single"
      config.num = 2
      config.version = version
      saveTable(config,"extraConfig.txt")
    end
    fill = io.open("securitySettings.txt")
    if fill ~= nil then
      io.close(fill)
    else
      term.clear()
      settingData = {}
      print("First time pass setup")
      print("Would you like to use the simple pass setup or new advanced one?","1 for simple, 2 for advanced")
      local text = term.read()
      modem.open(modemPort)
      modem.broadcast(modemPort,"autoInstallerQuery")
      local e,_,_,_,_,query = event.pull(3,"modem_message")
      if e == nil then
        print("Failed query. Is the server on?")
        os.exit()
      end
      query = ser.unserialize(query)
      if query.num == 1 then
        print("Server is a 1.#.# version, which isn't supported!")
        os.exit()
      end
      if tonumber(text) == 1 then
        local nextmsg = "What should be read? 0 = staff,"
        for i=1,#query.data.var,1 do
          nextmsg = nextmsg .. ", " .. i .. " = " .. query.data.label[i]
        end
        text = sendMsg(nextmsg,1)
        settingData.cardRead = {{["uuid"]=uuid.next(),["call"]="",["param"]=0,["request"]="supreme",["data"]=false}}
        if tonumber(text) == 0 then
          settingData.cardRead[1].call = "checkStaff"
          settingData.cardRead[1].param = 0
          sendMsg("No need to set access level. This mode doesn't require it :)")
        else
          settingData.cardRead[1].call = query.data.calls[tonumber(text)]
          if query.data.type[tonumber(text)] == "string" or query.data.type[tonumber(text)] == "-string" then
            text = sendMsg("What is the string you would like to read? Enter text.",1)
            settingData.cardRead[1].param = text
          elseif query.data.type[tonumber(text)] == "bool" then
            settingData.cardRead[1].param = 0
            sendMsg("No need to set access level. This mode doesn't require it :)")
          elseif query.data.type[tonumber(text)] == "int" then
            if query.data.above[tonumber(text)] == true then
              text = sendMsg("What level and above should be required?",1)
            else
              text = sendMsg("what level exactly should be required?",1)
            end
            settingData.cardRead[1].param = tonumber(text)
          elseif query.data.type[tonumber(text)] == "-int" then
            local nextmsg = "What group are you wanting to set?"
            for i=1,#query.data.data[tonumber(text)],1 do
              nextmsg = nextmsg .. ", " .. i .. " = " .. query.data.data[tonumber(text)][i]
            end
            text = sendMsg(nextmsg,1)
            settingData.cardRead[1].param = tonumber(text)
          else
            sendMsg("error in cardRead area for num 2")
            settingData.cardRead[1].param = 0
          end
        end
      else
        local readLoad = {}
        sendMsg("Remember how many of each pass you want before you start.","Press enter to continue",1)
        readLoad.add = tonumber(sendMsg("How many add passes do you want to add?","remember multiple base passes can use the same add pass",1))
        readLoad.base = tonumber(sendMsg("How many base passes do you want to add?",1))
        readLoad.reject = tonumber(sendMsg("How many reject passes do you want to add?","These don't affect supreme passes",1))
        readLoad.supreme = tonumber(sendMsg("How many supreme passes do you want to add?",1))
        loopArray.cardRead = {}
        local nextmsg = {}
        nextmsg.beg, nextmsg.mid, nextmsg.back = "What should be read for "," pass number ","? 0 = staff"
        for i=1,#settingData.cardRead.var,1 do
          nextmsg.back = nextmsg.back .. ", " .. i .. " = " .. settingData.cardRead.label[i]
        end
        local passFunc = function(type,num)
        local newRules = {["uuid"]=uuid.next(),["request"]=type,["data"]=type == "base" and {} or false}
        local text = sendMsg(nextmsg.beg..type..nextmsg.mid..num..nextmsg.back,1)
        if tonumber(text) == 0 then
          newRules.call = "checkstaff"
          newRules.param = 0
          sendMsg("No need for extra parameter. This mode doesn't require it :)")
        else
          newRules["tempint"] = tonumber(text)
          newRules["call"] = settingData.cardRead.calls[tonumber(text)]
          if settingData.cardRead.type[tonumber(text)] == "string" or settingData.cardRead.type == "-string" then
            text = sendMsg("What is the string you would like to read? Enter text.",1)
            newRules["param"] = text
          elseif settingData.cardRead.type[tonumber(text)] == "bool" then
            newRules["param"] = 0
            sendMsg("No need for extra parameter. This mode doesn't require it :)")
          elseif settingData.cardRead.type[tonumber(text)] == "int" then
            if settingData.cardRead.above[tonumber(text)] == true then
              text = sendMsg("What level and above should be required?",1)
            else
              text = sendMsg("what level exactly should be required?",1)
            end
            newRules["param"] = tonumber(text)
          elseif settingData.cardRead.type[tonumber(text)] == "-int" then
            local nextmsg = "What group are you wanting to set?"
            for i=1,#settingData.cardRead.data[tonumber(text)],1 do
              nextmsg = nextmsg .. ", " .. i .. " = " .. settingData.cardRead.data[tonumber(text)][i]
            end
            text = sendMsg(nextmsg,1)
            newRules["param"] = tonumber(text)
          else
            sendMsg("error in cardRead area for num 2")
            newRules["param"] = 0
          end
        end
        return newRules
        end
        for i=1,readLoad.add,1 do
            local rule = passFunc("add",i)
            table.insert(loopArray.cardRead,rule)
        end
        local addNum = #loopArray.cardRead
        for i=1,readLoad.base,1 do
            local rule = passFunc("base",i)
            text = tonumber(sendMsg("How many add passes do you want to link?",1))
            if text ~= 0 then
                local nextAdd = "Which pass do you want to add? "
                for j=1,addNum,1 do
                    nextAdd = nextAdd .. ", " .. j .. " = " .. settingData.cardRead.label[loopArray.cardRead[j].tempint]
                end
                for j=1,text,1 do
                    text = tonumber(sendMsg(nextAdd,1))
                    table.insert(rule.data,loopArray.cardRead[text].uuid)
                end
            end
            table.insert(loopArray.cardRead,rule)
        end
        for i=1,readLoad.reject,1 do
            local rule = passFunc("reject",i)
            table.insert(loopArray.cardRead,rule)
        end
        for i=1,readLoad.supreme,1 do
            local rule = passFunc("supreme",i)
            table.insert(loopArray.cardRead,rule)
        end
      end
      saveTable(settingData,"securitySettings.txt")
    end
    term.clear()
    settingData = loadTable("securitySettings.txt")
    extraConfig = loadTable("extraConfig.txt")
  end

  function security.checkPass(str,port,loc)
    local data = crypt(str,extraConfig.cryptKey,true)
    local tmpTable = ser.unserialize(data)
    tmpTable["type"] = "single"
    data = crypt(ser.serialize(tmpTable), extraConfig.cryptKey)
    if loc ~= nil then
        modem.send(loc,port,"checkRules",data,true)
    else
        modem.broadcast(port,"checkRules",data,true)
    end
    modem.open(port)
    local e, _, from, port, _, msg = event.pull(1, "modem_message")
    if e then
        data = crypt(msg, extraConfig.cryptKey, true)
        if data == "true" then
            return true, true
        else
            return true, false
        end
    else

    end
  end

return security

