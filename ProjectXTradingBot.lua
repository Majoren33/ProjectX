-- ============================================
-- PET SIMULATOR TRADING BOT - FULL VERSION
-- WARNING: Using this violates Roblox TOS
-- ============================================

-- Wait for game to load
if not game:IsLoaded() then 
    game.Loaded:Wait()
end

-- Configuration Check
if not getgenv().Settings then
    return error("Configuration not found! Please load getgenv().Settings before running the script.")
end

local Settings = getgenv().Settings

-- Debug mode (set to true for detailed logs)
local DEBUG_MODE = getgenv().DEBUG_MODE or false
local WEBHOOK_IMAGE_URL = "https://media.discordapp.net/attachments/1358102605594886288/1358103169447756087/stsmall507x507-pad600x600f8f8f8.jpg?format=webp"

local function DebugPrint(...)
    if DEBUG_MODE then
        print("[DEBUG]", ...)
    end
end

-- Validate configuration
if not Settings.Sniper and not Settings.Seller then
    return error("[Bot] Invalid config: Must have Sniper or Seller table")
end

-- Ensure both tables exist (even if not active)
Settings.Sniper = Settings.Sniper or {Active = false, Items = {}}
Settings.Seller = Settings.Seller or {Active = false, Items = {}}

-- Validate at least one mode is active
if not Settings.Sniper.Active and not Settings.Seller.Active then
    return error("[Bot] Invalid config: Either Sniper or Seller must be Active = true")
end

-- Ensure sub-tables exist
Settings.Sniper["Switch Servers"] = Settings.Sniper["Switch Servers"] or {Active = false}
Settings.Sniper["Webhook"] = Settings.Sniper["Webhook"] or {Active = false, URL = ""}
Settings.Sniper["Kill Switch"] = Settings.Sniper["Kill Switch"] or {}

Settings.Seller["Switch Servers"] = Settings.Seller["Switch Servers"] or {Active = false}
Settings.Seller["Webhook"] = Settings.Seller["Webhook"] or {Active = false, URL = ""}
Settings.Seller["Kill Switch"] = Settings.Seller["Kill Switch"] or {}
Settings.Seller["Diamonds Sendout"] = Settings.Seller["Diamonds Sendout"] or {Active = false}

-- ============================================
-- SERVICES & GAME DETECTION
-- ============================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local StartTime = os.time()
local LastDiamonds = 0

-- Wait for player to load
repeat task.wait() 
    LocalPlayer = Players.LocalPlayer
until LocalPlayer and LocalPlayer.GetAttribute and LocalPlayer:GetAttribute("__LOADED")

if not LocalPlayer.Character then 
    LocalPlayer.CharacterAdded:Wait() 
end
local HumanoidRootPart = LocalPlayer.Character:WaitForChild("HumanoidRootPart")

-- Game IDs
local GAME_IDS = {
    PS99 = {Pro = 15588442388, Normal = 15502339080},
    PETSGO = {Pro = 133783083257328, Normal = 19006211286}
}

local CurrentGame = nil
local IsInPlaza = false

if table.find({GAME_IDS.PS99.Normal, GAME_IDS.PS99.Pro}, game.PlaceId) then
    CurrentGame = "PS99"
    IsInPlaza = true
elseif table.find({GAME_IDS.PETSGO.Normal, GAME_IDS.PETSGO.Pro}, game.PlaceId) then
    CurrentGame = "PETSGO"
    IsInPlaza = true
end

if not IsInPlaza then
    warn("[Bot] Not in Trading Plaza! Attempting to travel...")
    
    -- Try to travel to plaza
    local travelAttempts = 0
    while travelAttempts < 5 do
        travelAttempts = travelAttempts + 1
        
        local success = pcall(function()
            Library.Network.Invoke("Travel to Trading Plaza")
        end)
        
        if success then
            print("[Bot] Travel initiated, waiting for load...")
            task.wait(10)
            
            -- Check if we're in plaza now
            if table.find({GAME_IDS.PS99.Normal, GAME_IDS.PS99.Pro, GAME_IDS.PETSGO.Normal, GAME_IDS.PETSGO.Pro}, game.PlaceId) then
                if CurrentGame == "PS99" or CurrentGame == "PETSGO" then
                    IsInPlaza = true
                    break
                end
            end
        end
        
        task.wait(5)
    end
    
    if not IsInPlaza then
        return error("[Bot] ERROR: Not in Trading Plaza! Please manually join the Trading Plaza and try again.")
    end
end

-- ============================================
-- GAME LIBRARY SETUP
-- ============================================
local NLibrary = ReplicatedStorage:WaitForChild("Library")
local PlayerSave = require(NLibrary.Client.Save)
local Directory = require(NLibrary.Directory)
local Rarities = require(NLibrary.Directory.Rarity)
local PlayerScripts = LocalPlayer.PlayerScripts.Scripts

-- Load game-specific modules
local Library = getgenv().Library or {}
if not getgenv().Library then
    getgenv().Library = {}
    for _, v in pairs(NLibrary.Client:GetChildren()) do
        if v:IsA("ModuleScript") and not v:GetAttribute("NOLOAD") then
            local success, module = pcall(require, v)
            if success then
                Library[v.Name] = module
            end
        end
    end
    for _, v in pairs(NLibrary:GetChildren()) do
        if v:IsA("ModuleScript") and not v:GetAttribute("NOLOAD") then
            local success, module = pcall(require, v)
            if success then
                Library[v.Name] = module
            end
        end
    end
    getgenv().Library = Library
end

-- Game-specific modules
local Constants, Variables, UpgradeCmds, Mailbox
if CurrentGame == "PS99" then
    Constants = require(NLibrary.Balancing.Constants)
    Mailbox = require(NLibrary.Types.Mailbox)
elseif CurrentGame == "PETSGO" then
    UpgradeCmds = require(NLibrary.Client.UpgradeCmds)
    Variables = require(NLibrary.Shared.Variables)
end

-- Booth system
local Booths, ClaimedBooths, BoothsInteractive

local function SetupBoothSystem()
    local success, err = pcall(function()
        DebugPrint("Starting booth setup...")
        
        -- Find BoothCmds module
        local boothModule = NLibrary.Client:FindFirstChild("BoothCmds")
        DebugPrint("BoothCmds in Client:", boothModule)
        
        if not boothModule then
            local plaza = PlayerScripts.Game:FindFirstChild("Trading Plaza")
            DebugPrint("Trading Plaza found:", plaza)
            
            if plaza then
                boothModule = plaza:FindFirstChild("Booths Frontend")
                DebugPrint("Booths Frontend found:", boothModule)
            end
        end
        
        if not boothModule then
            error("Could not find booth module")
        end
        
        -- Get booth environment
        DebugPrint("Getting booth environment...")
        local boothEnv = getsenv(boothModule)
        if not boothEnv then
            error("Could not get booth environment")
        end
        
        DebugPrint("Booth environment obtained")
        
        -- Get getState function
        local getState = boothEnv.getState
        DebugPrint("getState function:", getState, type(getState))
        
        if not getState or type(getState) ~= "function" then
            error("Could not find getState function")
        end
        
        -- Get booths data
        DebugPrint("Getting booth upvalues...")
        local upvalues = getupvalues(getState)
        DebugPrint("Upvalues count:", upvalues and #upvalues or 0)
        
        if not upvalues or #upvalues == 0 then
            error("Could not get booth upvalues")
        end
        Booths = upvalues
        
        -- Get updateAllInteracts function
        local updateInteracts = boothEnv.updateAllInteracts
        DebugPrint("updateAllInteracts function:", updateInteracts, type(updateInteracts))
        
        if not updateInteracts or type(updateInteracts) ~= "function" then
            error("Could not find updateAllInteracts function")
        end
        
        -- Get claimed booths and interactive booths
        DebugPrint("Getting interact upvalues...")
        local interactUpvalues = getupvalues(updateInteracts)
        DebugPrint("Interact upvalues count:", interactUpvalues and #interactUpvalues or 0)
        
        if not interactUpvalues or #interactUpvalues < 3 then
            error("Could not get interact upvalues")
        end
        
        ClaimedBooths = interactUpvalues[1]
        BoothsInteractive = interactUpvalues[3]
        
        DebugPrint("ClaimedBooths:", ClaimedBooths and "Found" or "nil")
        DebugPrint("BoothsInteractive:", BoothsInteractive and "Found" or "nil")
        
        if not ClaimedBooths or not BoothsInteractive then
            error("Booth tables not found in upvalues")
        end
        
        print("[Booth] System initialized successfully")
        return true
    end)
    
    if not success then
        warn("[Booth] Setup failed: " .. tostring(err))
        return false
    end
    
    return true
end

-- Try to setup booth system with retries
local boothSetupAttempts = 0
local maxBoothAttempts = 10

repeat
    task.wait(1)
    boothSetupAttempts = boothSetupAttempts + 1
    print("[Booth] Setup attempt " .. boothSetupAttempts .. "/" .. maxBoothAttempts)
until SetupBoothSystem() or boothSetupAttempts >= maxBoothAttempts

if not Booths or not ClaimedBooths or not BoothsInteractive then
    return error("[Bot] ERROR: Booth system initialization failed! Make sure you are in the Trading Plaza and all booths are loaded. Try rejoining and waiting 30 seconds before running the script.")
end

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

local Suffixes = {"k", "m", "b", "t", "qa", "qi"}

local function AddSuffix(num)
    if not num or type(num) ~= "number" then return "0" end
    if num == 0 then return "0" end
    
    local negative = num < 0
    num = math.abs(num)
    
    local exp = math.floor(math.log(num, 1000))
    local suffix = Suffixes[exp] or ""
    local value = num / math.pow(1000, exp)
    
    return (negative and "-" or "") .. string.format("%.2f", value):gsub("%.?0+$", "") .. suffix
end

local function RemoveSuffix(str)
    if type(str) == "number" then return str end
    str = tostring(str)
    local num, suffix = str:gsub("%a", ""), str:match("%a+")
    if not suffix then return tonumber(num) or 0 end
    
    local exp = 0
    for i, s in ipairs(Suffixes) do
        if s:lower() == suffix:lower() then
            exp = i
            break
        end
    end
    
    return tonumber(num) * math.pow(1000, exp)
end

local function AddCommas(num)
    local str = tostring(num)
    while true do
        str, k = string.gsub(str, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return str
end

-- Roman numeral conversion
local RomanNumerals = {I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000}

local function ConvertToRoman(num)
    local result = ""
    local sorted = {{1000, "M"}, {500, "D"}, {100, "C"}, {50, "L"}, {10, "X"}, {5, "V"}, {1, "I"}}
    for _, pair in ipairs(sorted) do
        while num >= pair[1] do
            result = result .. pair[2]
            num = num - pair[1]
        end
    end
    return result
end

local function ConvertFromRoman(roman)
    local total = 0
    local prev = 0
    for i = #roman, 1, -1 do
        local curr = RomanNumerals[roman:sub(i, i)]
        if curr < prev then
            total = total - curr
        else
            total = total + curr
        end
        prev = curr
    end
    return total
end

-- ============================================
-- FILE MANAGEMENT
-- ============================================

local SaveData = {
    Mode = Settings.Seller.Active and "Seller" or "Sniper",
    StartTime = os.time(),
    LastServers = {},
    CosmicValues = {},
    ManipulationData = {},
    Statistics = {
        TotalProfit = 0,
        ItemsBought = 0,
        ItemsSold = 0,
        ServersVisited = 0,
        DiamondsEarned = 0
    }
}

local FolderName = "TradingBot_" .. CurrentGame
local FileName = FolderName .. "/" .. LocalPlayer.Name .. ".json"

local function SaveToFile()
    if not isfolder(FolderName) then makefolder(FolderName) end
    writefile(FileName, HttpService:JSONEncode(SaveData))
end

local function LoadFromFile()
    if not isfolder(FolderName) then makefolder(FolderName) end
    if isfile(FileName) then
        local success, data = pcall(function()
            return HttpService:JSONDecode(readfile(FileName))
        end)
        if success and type(data) == "table" then
            SaveData = data
            SaveData.StartTime = os.time() -- Reset timer on load
        end
    end
    SaveToFile()
end

LoadFromFile()

-- ============================================
-- ANTI-AFK SYSTEM
-- ============================================

local function SetupAntiAFK()
    -- Disable idle scripts
    if PlayerScripts.Core:FindFirstChild("Server Closing") then
        PlayerScripts.Core["Server Closing"].Enabled = false
    end
    if PlayerScripts.Core:FindFirstChild("Idle Tracking") then
        PlayerScripts.Core["Idle Tracking"].Enabled = false
    end
    
    Library.Network.Fire("Idle Tracking: Stop Timer")
    
    -- Virtual user input
    LocalPlayer.Idled:Connect(function()
        local VirtualUser = game:GetService("VirtualUser")
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
    
    print("[Bot] Anti-AFK enabled")
end

-- ============================================
-- INVENTORY FUNCTIONS
-- ============================================

local function GetInventoryByClass(class)
    return Library.InventoryCmds.State().container._store._byType[class]
end

local BlacklistedUIDs = {}
local LastUIDs = {}

local function FindItemsInBooth(itemId, class)
    local itemCount = 0
    local boothCount = 0
    
    for _, users in pairs(Booths) do
        for username, booth in pairs(users) do
            if tostring(username):find(LocalPlayer.Name) and booth.Listings then
                for uid, info in pairs(booth.Listings) do
                    boothCount = boothCount + 1
                    if itemId and class then
                        local petData = info.Item._data
                        if petData.id == itemId and info.Item.Class.Name == class then
                            itemCount = itemCount + (petData._am or 1)
                        end
                    end
                end
                return boothCount, itemCount
            end
        end
    end
    return 0, 0
end

local function ValidateItem(boothItem, wantedItem)
    -- Check special cases
    if wantedItem.ID:find("All Huges") and not boothItem.IsHuge then
        return false
    end
    if wantedItem.ID:find("All Titanics") and not boothItem.IsTitanic then
        return false
    end
    if wantedItem.ID:find("All Exclusives") then
        if not boothItem.IsExclusive or boothItem.IsHuge or boothItem.IsTitanic or boothItem.Class ~= "Pet" then
            return false
        end
    end
    if wantedItem.ID:find("All Rarity") then
        local rarity = wantedItem.ID:split(":")[2]:gsub(" ", "")
        if not boothItem.Rarity or boothItem.Rarity:gsub(" ", "") ~= rarity then
            return false
        end
    end
    if wantedItem.ID:find("All Class") then
        local class = wantedItem.ID:split(":")[2]:gsub(" ", "")
        if not boothItem.Class or boothItem.Class ~= class then
            return false
        end
    end
    
    -- Check exact ID match
    if not wantedItem.ID:find("All ") and wantedItem.ID ~= boothItem.ID then
        return false
    end
    
    -- Check class
    if wantedItem.Class and wantedItem.Class ~= boothItem.Class then
        return false
    end
    
    -- Check variants (unless AllTypes is true)
    if not wantedItem.AllTypes then
        if (wantedItem.Shiny and not boothItem.Shiny) or (not wantedItem.Shiny and boothItem.Shiny) then
            return false
        end
        if (wantedItem.Rainbow and not boothItem.Rainbow) or (not wantedItem.Rainbow and boothItem.Rainbow) then
            return false
        end
        if (wantedItem.Golden and not boothItem.Golden) or (not wantedItem.Golden and boothItem.Golden) then
            return false
        end
    end
    
    -- Check tier
    if not wantedItem.AllTiers and wantedItem.Tier and boothItem.Tier then
        if tonumber(wantedItem.Tier) ~= tonumber(boothItem.Tier) then
            return false
        end
    end
    
    return true
end

local function FindItem(searchData, returnAmount)
    local count = 0
    local inventories = {}
    
    -- Determine which inventories to search
    if searchData.ID:find("All Huges") or searchData.ID:find("All Titanics") then
        table.insert(inventories, GetInventoryByClass("Pet"))
    elseif searchData.Class then
        table.insert(inventories, GetInventoryByClass(searchData.Class))
    else
        for class in pairs(Library.InventoryCmds.State().container._store._byType) do
            table.insert(inventories, GetInventoryByClass(class))
        end
    end
    
    for _, inventory in pairs(inventories) do
        if not inventory or not inventory._byUID then continue end
        
        for uid, itemTable in pairs(inventory._byUID) do
            -- Check if already in booth
            if not returnAmount then
                if table.find(LastUIDs, uid) then
                    local boothCount, itemCount = FindItemsInBooth(
                        itemTable.GetId and itemTable:GetId(),
                        itemTable.GetClass and itemTable:GetClass() or itemTable.Class and itemTable.Class.Name
                    )
                    if itemCount >= 1 then
                        continue
                    else
                        table.remove(LastUIDs, table.find(LastUIDs, uid))
                    end
                end
            end
            
            -- Build item info
            local itemInfo = {
                UID = uid,
                ID = itemTable.GetId and itemTable:GetId() or nil,
                Display = itemTable.GetId and itemTable:GetId() or "Unknown",
                Class = itemTable.GetClass and itemTable:GetClass() or itemTable.Class and itemTable.Class.Name or searchData.Class or "Pet",
                Rainbow = itemTable.IsRainbow and itemTable:IsRainbow() or false,
                Golden = itemTable.IsGolden and itemTable:IsGolden() or false,
                Shiny = itemTable.IsShiny and itemTable:IsShiny() or false,
                IsHuge = itemTable.IsHuge and itemTable:IsHuge() or false,
                IsTitanic = itemTable.IsTitanic and itemTable:IsTitanic() or false,
                IsExclusive = itemTable.GetRarity and itemTable:GetRarity()._id == "Exclusive" or false,
                NotTradeable = itemTable.AbstractIsTradable and itemTable:AbstractIsTradable() == false,
                IsLocked = itemTable._data["_lk"],
                Amount = itemTable._data["_am"] or 1,
                Tier = itemTable._data["tn"],
                Difficulty = itemTable.GetDifficulty and itemTable:GetDifficulty(),
                Rarity = itemTable.GetRarity and itemTable:GetRarity()._id,
            }
            
            -- Build display name with variants
            if itemInfo.Shiny then
                itemInfo.Display = "Shiny " .. itemInfo.Display
            end
            if itemInfo.Rainbow then
                itemInfo.Display = "Rainbow " .. itemInfo.Display
            end
            if itemInfo.Golden then
                itemInfo.Display = "Golden " .. itemInfo.Display
            end
            
            DebugPrint("Checking item:", itemInfo.Display, "Locked:", itemInfo.IsLocked, "Tradeable:", not itemInfo.NotTradeable)
            
            -- Skip locked/untradeable items
            if itemInfo.IsLocked or itemInfo.NotTradeable or BlacklistedUIDs[uid] or not uid then
                continue
            end
            
            -- Validate against search criteria
            if ValidateItem(itemInfo, searchData) then
                if returnAmount then
                    count = count + itemInfo.Amount
                else
                    DebugPrint("Found matching item:", itemInfo.Display, "UID:", uid)
                    table.insert(LastUIDs, uid)
                    return uid, itemInfo
                end
            end
        end
    end
    
    return returnAmount and count or nil
end

-- ============================================
-- CURRENCY FUNCTIONS
-- ============================================

local function GetDiamonds(returnUID)
    for uid, item in pairs(PlayerSave.Get()["Inventory"].Currency) do
        if item.id == "Diamonds" then
            return returnUID and uid or (item._am or 0)
        end
    end
    return 0
end

local function GetMailCost()
    if CurrentGame == "PETSGO" then
        return Variables.MailboxCoinsCost * (Library.UpgradeCmds.IsUnlocked("Cheaper Mailbox") and 0.75 or 1)
    else
        local baseCost = Constants.MailboxDiamondCost
        local shouldReset = not (PlayerSave.Get().MailboxResetTime and PlayerSave.Get().MailboxResetTime >= workspace:GetServerTimeNow())
        
        if shouldReset then return baseCost end
        
        local cost = baseCost * math.pow(Mailbox.DiamondCostGrowthRate, PlayerSave.Get().MailboxSendsSinceReset)
        cost = math.min(cost, Mailbox.DiamondCostCap)
        
        if PlayerSave.Get().Gamepasses.VIP or LocalPlayer:GetAttribute("Partner") then
            return baseCost
        end
        
        return cost
    end
end

-- ============================================
-- RAP & VALUE FUNCTIONS
-- ============================================

local function GetRAP(itemObject)
    if CurrentGame == "PS99" then
        return itemObject.GetDevRAP and itemObject:GetDevRAP()
    else
        return itemObject.GetRAP and itemObject:GetRAP()
    end
end

local function FetchCosmicValue(itemName)
    local apiUrl = CurrentGame == "PETSGO" and "https://petsgovalues.com/details.php?Name=" or "https://petsimulatorvalues.com/details.php?Name="
    local url = apiUrl .. itemName:gsub(" ", "+")
    
    local success, response = pcall(function()
        return game:HttpGet(url)
    end)
    
    if not success then return nil end
    
    local value = response:split('value</Span><Span class="float-right">')[2]
    if value then
        value = value:split("</Span>")[1]
        if value:find("%d") then
            return RemoveSuffix(value)
        end
    end
    
    return nil
end

local function GetCosmicValue(itemName)
    -- Check cache
    if SaveData.CosmicValues[itemName] and SaveData.CosmicValues[itemName] ~= "nil" then
        return SaveData.CosmicValues[itemName]
    end
    
    -- Fetch new value
    if not SaveData.CosmicValues[itemName] or SaveData.CosmicValues[itemName] == "nil" then
        local value = FetchCosmicValue(itemName)
        if value then
            SaveData.CosmicValues[itemName] = value
            SaveToFile()
            return value
        else
            SaveData.CosmicValues[itemName] = "nil"
            SaveToFile()
        end
    end
    
    return nil
end

local function CheckManipulation(itemName, currentRAP)
    -- Check cache
    if SaveData.ManipulationData[itemName] and SaveData.ManipulationData[itemName].RAP == currentRAP then
        return SaveData.ManipulationData[itemName].Result
    end
    
    -- Fetch RAP history
    local success, response = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://ps99rap.com/api/get/rap?id=" .. itemName:lower():gsub(" ", "%%20"))
        )
    end)
    
    if not success or not response.data then return "Unknown" end
    
    local data = response.data
    if #data <= 1 then return "Unknown" end
    
    -- Calculate trend
    local current = data[#data][2]
    local dayAgo = os.time() - (24 * 60 * 60)
    local dailyData = {}
    
    for i = #data, 1, -1 do
        if data[i][1] / 1000 >= dayAgo then
            table.insert(dailyData, data[i])
        else
            break
        end
    end
    
    local avgRAP = 0
    local count = math.min(#data, 30)
    for i = #data, #data - count + 1, -1 do
        avgRAP = avgRAP + data[i][2]
    end
    avgRAP = avgRAP / count
    
    local deviation = ((current - avgRAP) / math.max(avgRAP, 1)) * 100
    local result = "Stable"
    
    if math.abs(deviation) > 10 then
        result = "Manipulated"
    elseif #dailyData > 0 then
        local starting = dailyData[1][2]
        if math.abs(current - starting) > 0.1 * starting then
            result = current > starting and "Increasing" or "Decreasing"
        end
    end
    
    -- Cache result
    SaveData.ManipulationData[itemName] = {Result = result, RAP = currentRAP}
    SaveToFile()
    
    return result
end

-- ============================================
-- DISCORD WEBHOOK
-- ============================================

local function SendWebhook(title, description, color, thumbnail)
    local mode = SaveData.Mode
    if not Settings[mode] or not Settings[mode].Webhook then return end
    if not Settings[mode].Webhook.Active or Settings[mode].Webhook.URL == "" then return end
    
    -- Custom webhook image (you can change this URL)
    local customAvatarUrl = WEBHOOK_IMAGE_URL
    local customUsername = Settings[mode].Webhook.Username or "Pet Sim Trading Bot"
    
    local embed = {
        username = customUsername,
        avatar_url = customAvatarUrl,
        embeds = {{
            title = title,
            description = description,
            color = color or 3447003,
            thumbnail = thumbnail and {url = thumbnail} or nil,
            timestamp = DateTime.now():ToIsoDate(),
            footer = {
                text = LocalPlayer.Name .. " | " .. CurrentGame .. " | Trading Bot"
            }
        }}
    }
    
    task.spawn(function()
        local success = pcall(function()
            request({
                Url = Settings[mode].Webhook.URL,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = HttpService:JSONEncode(embed)
            })
        end)
        if not success then
            warn("[Webhook] Failed to send")
        end
    end)
end

-- ============================================
-- SERVER HOPPING
-- ============================================

local ServerList = {}

local function FetchServers(placeId)
    ServerList = {}
    local url = string.format(
        "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Desc&limit=100",
        placeId
    )
    
    local success, response = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    
    if success and response.data then
        for _, server in ipairs(response.data) do
            if server.id ~= game.JobId and server.playing >= 5 and server.playing < server.maxPlayers then
                table.insert(ServerList, {
                    PlaceID = placeId,
                    JobID = server.id,
                    Players = server.playing
                })
            end
        end
        print("[Server Hop] Found " .. #ServerList .. " available servers")
    else
        warn("[Server Hop] Failed to fetch servers")
        task.wait(15)
    end
end

local function ServerHop()
    local mode = SaveData.Mode
    if not Settings[mode] or not Settings[mode]["Switch Servers"] then return end
    local settings = Settings[mode]["Switch Servers"]
    
    if not settings.Active then return end
    
    -- Determine target place
    local targetPlace = game.PlaceId
    if settings.OnlyPRO then
        if CurrentGame == "PS99" then
            targetPlace = GAME_IDS.PS99.Pro
        else
            targetPlace = GAME_IDS.PETSGO.Pro
        end
    end
    
    -- Fetch servers if needed
    if #ServerList == 0 then
        FetchServers(targetPlace)
        if #ServerList == 0 then
            warn("[Server Hop] No servers available, retrying in 10s...")
            task.wait(10)
            return ServerHop()
        end
    end
    
    -- Find unvisited server
    for attempt = 1, #ServerList do
        local server = ServerList[math.random(1, #ServerList)]
        
        if not table.find(SaveData.LastServers, server.JobID) then
            -- Update history
            table.insert(SaveData.LastServers, server.JobID)
            if #SaveData.LastServers > 15 then
                table.remove(SaveData.LastServers, 1)
            end
            
            SaveData.Statistics.ServersVisited = SaveData.Statistics.ServersVisited + 1
            SaveData.StartTime = os.time()
            SaveToFile()
            
            print("[Server Hop] Teleporting to new server...")
            SendWebhook("Server Hop", "Joining new server (#" .. SaveData.Statistics.ServersVisited .. ")", 3447003)
            
            TeleportService:TeleportToPlaceInstance(server.PlaceID, server.JobID, LocalPlayer)
            task.wait(5)
            return
        end
    end
    
    -- All servers visited, refetch
    warn("[Server Hop] All servers visited, refetching...")
    ServerList = {}
    task.wait(5)
    ServerHop()
end

-- ============================================
-- BOOTH MANAGEMENT
-- ============================================

local function IsBoothAvailable(boothID)
    for _, booth in pairs(ClaimedBooths) do
        if booth.BoothID == boothID then
            return false
        end
    end
    return true
end

local function GetOptimalBooth()
    local candidates = {}
    local centerX = 0
    local count = 0
    
    -- Calculate center
    for _, boothModel in pairs(BoothsInteractive) do
        centerX = centerX + boothModel.Pets.Position.X
        count = count + 1
    end
    centerX = centerX / count
    
    -- Find available booths
    for boothID, boothModel in pairs(BoothsInteractive) do
        if IsBoothAvailable(boothID) then
            local pos = boothModel.Pets.Position
            table.insert(candidates, {
                ID = boothID,
                Model = boothModel,
                Y = pos.Y,
                XDist = math.abs(pos.X - centerX)
            })
        end
    end
    
    -- Sort by Y (priority), then X distance
    table.sort(candidates, function(a, b)
        if math.abs(a.Y - b.Y) < 0.1 then
            return a.XDist < b.XDist
        end
        return a.Y < b.Y
    end)
    
    return candidates[1]
end

local function ClaimBooth()
    if ClaimedBooths[LocalPlayer] then
        print("[Booth] Already have a booth")
        return true
    end
    
    local booth = GetOptimalBooth()
    if not booth then
        warn("[Booth] No available booths!")
        return false
    end
    
    local success = Library.Network.Invoke("Booths_ClaimBooth", booth.ID)
    if success then
        print("[Booth] Claimed booth successfully!")
        
        -- Move to booth
        Library.Network.Fire("Hoverboard_RequestUnequip")
        task.wait(0.5)
        
        local interact = booth.Model:WaitForChild("Interact", 5)
        if interact then
            HumanoidRootPart.CFrame = interact.CFrame * CFrame.new(0, -2, -6) * CFrame.Angles(0, math.rad(180), 0)
        end
        
        task.wait(1)
        return true
    end
    
    warn("[Booth] Failed to claim booth")
    return false
end

-- ============================================
-- ITEM LISTING
-- ============================================

local function CalculatePrice(priceConfig, itemRAP)
    if type(priceConfig) == "number" then
        return priceConfig
    end
    
    local str = tostring(priceConfig)
    
    -- Percentage below RAP (e.g., "10%")
    if str:match("^%d+%%$") then
        local percent = tonumber(str:match("%d+"))
        return itemRAP * (1 - percent / 100)
    end
    
    -- Percentage above RAP (e.g., "+10%")
    if str:match("^%+%d+%%$") then
        local percent = tonumber(str:match("%d+"))
        return itemRAP * (1 + percent / 100)
    end
    
    -- Negative offset (e.g., "-1000")
    if str:match("^%-") then
        return itemRAP + tonumber(str)
    end
    
    -- Fixed amount (e.g., "100k")
    return RemoveSuffix(str)
end

local function CreateItemObject(itemData)
    local itemObj = Library.Items.Types[itemData.Class](itemData.ID)
    
    if itemData.Golden then itemObj:SetGolden() end
    if itemData.Rainbow then itemObj:SetRainbow() end
    if itemData.Shiny then itemObj:SetShiny(true) end
    if itemData.Tier then itemObj:SetTier(itemData.Tier) end
    
    return itemObj
end

local function GenerateFindInfo(name, config)
    local findInfo = {
        ID = name,
        AllTypes = config.AllTypes,
        AllTiers = config.AllTiers,
        Rainbow = false,
        Golden = false,
        Shiny = false
    }
    
    if type(config) == "table" then
        if config.Class and config.Item then
            local className = tostring(config.Class)
            local target = tostring(config.Item)
            local success, directory = pcall(function()
                if className == "Misc" or className == "Card" then
                    return require(NLibrary.Directory[className .. "Items"])
                elseif className == "Lootbox" or className == "Box" then
                    return require(NLibrary.Directory[className .. "es"])
                else
                    return require(NLibrary.Directory[className .. "s"])
                end
            end)
            if success and directory then
                for itemId, itemInfo in pairs(directory) do
                    local displayName = itemInfo.DisplayName
                    if type(displayName) == "function" then
                        displayName = displayName(findInfo.Tier or 1)
                    end
                    if itemId == target or (displayName and tostring(displayName):lower() == target:lower()) then
                        findInfo.Class = className
                        findInfo.ID = itemId
                        findInfo.Display = displayName or itemId
                        return findInfo
                    end
                end
            end
        elseif config.ID then
            local targetId = tostring(config.ID)
            local itemTypes = require(NLibrary.Items.Types).Types
            for className in pairs(itemTypes) do
                local success, directory = pcall(function()
                    if className == "Misc" or className == "Card" then
                        return require(NLibrary.Directory[className .. "Items"])
                    elseif className == "Lootbox" or className == "Box" then
                        return require(NLibrary.Directory[className .. "es"])
                    else
                        return require(NLibrary.Directory[className .. "s"])
                    end
                end)
                if success and directory and directory[targetId] then
                    findInfo.Class = className
                    findInfo.ID = targetId
                    local displayName = directory[targetId].DisplayName
                    if type(displayName) == "function" then
                        displayName = displayName(findInfo.Tier or 1)
                    end
                    findInfo.Display = displayName or targetId
                    return findInfo
                end
            end
        end
    end
    
    -- Handle special search terms (don't parse these)
    if name:find("All Huges") or name:find("All Titanics") or name:find("All Exclusives") or 
       name:find("All Rarity") or name:find("All Class") or name:find("All Items") then
        findInfo.Display = name
        return findInfo
    end
    
    -- Parse variants from the name
    local workingName = name
    if not name:find("Board") and not name:find("Gem") then
        local rainbowPos = name:find("Rainbow")
        local hugePos = name:find("Huge")
        findInfo.Rainbow = (rainbowPos and (not hugePos or rainbowPos < hugePos))
        findInfo.Golden = name:find("Golden") and true
        findInfo.Shiny = name:find("Shiny") and true
        
        workingName = workingName:gsub("Rainbow ", "")
        workingName = workingName:gsub("Golden ", "")
        workingName = workingName:gsub("Shiny ", "")
    end
    
    -- Parse tier (both numeric and roman numerals)
    local main, tier = workingName:match("(.+)%s+(%d+)%s*$")
    if tier then
        findInfo.Tier = tonumber(tier)
        workingName = main .. " " .. ConvertToRoman(findInfo.Tier)
    elseif workingName:find("(%u+)%s*$") then
        local romanNumeral = workingName:match("(%u+)%s*$")
        local tierNum = ConvertFromRoman(romanNumeral)
        if tierNum and tierNum > 0 then
            findInfo.Tier = tierNum
        end
    end
    
    findInfo.Display = workingName
    
    -- Try to find the item in the game directory
    local itemTypes = require(NLibrary.Items.Types).Types
    for className in pairs(itemTypes) do
        local success, directory = pcall(function()
            if className == "Misc" or className == "Card" then
                return require(NLibrary.Directory[className .. "Items"])
            elseif className == "Lootbox" or className == "Box" then
                return require(NLibrary.Directory[className .. "es"])
            else
                return require(NLibrary.Directory[className .. "s"])
            end
        end)
        
                if success and directory then
                    for itemId, itemInfo in pairs(directory) do
                        local displayName = itemInfo.DisplayName
                        if type(displayName) == "function" then
                            displayName = displayName(findInfo.Tier or 1)
                        end
                        
                        -- Try exact match first
                        if displayName == workingName then
                            findInfo.Class = className
                            findInfo.ID = itemId
                            DebugPrint("Found exact match:", itemId, "in class:", className)
                            return findInfo
                        end
                        
                        -- Try case-insensitive match
                        if displayName and displayName:lower() == workingName:lower() then
                            findInfo.Class = className
                            findInfo.ID = itemId
                            findInfo.Display = displayName  -- Use correct casing
                            DebugPrint("Found case-insensitive match:", itemId, "in class:", className)
                            return findInfo
                        end
                        
                        -- Fuzzy match: ignore spaces/punctuation and check substring
                        local function norm(s)
                            return tostring(s):lower():gsub("%W", "")
                        end
                        local targetNorm = norm(workingName)
                        local displayNorm = norm(displayName or "")
                        local idNorm = norm(itemId or "")
                        if targetNorm ~= "" and (displayNorm:find(targetNorm, 1, true) or idNorm:find(targetNorm, 1, true)) then
                            findInfo.Class = className
                            findInfo.ID = itemId
                            findInfo.Display = displayName or itemId
                            DebugPrint("Found fuzzy match:", itemId, "in class:", className)
                            return findInfo
                        end
                    end
                end
            end
    
    -- If not found in directory, log for debugging
    DebugPrint("Item not found in directory:", workingName)
    warn("[Item Search] Could not find '" .. name .. "' in game directory. The item might have a different name.")
    
    return findInfo
end

local function ListItemToBooth(uid, itemData, price, amount)
    local maxPerListing = CurrentGame == "PS99" and 50000 or 5000
    local maxPrice = RemoveSuffix("100b")
    
    -- Validate price (fix malformed number error)
    if type(price) ~= "number" then
        price = tonumber(price)
    end
    
    if not price or price <= 0 or price ~= price then -- NaN check
        warn("[Listing] Invalid price for " .. itemData.Display .. ": " .. tostring(price))
        return false
    end
    
    -- Floor the price to remove decimals
    price = math.floor(price)
    
    -- Adjust amount if price too high
    if price * amount > maxPrice then
        amount = math.floor(maxPrice / price)
    end
    
    if amount <= 0 then
        warn("[Listing] Amount too low after price adjustment")
        return false
    end
    
    -- Ensure UID type correctness
    if type(uid) ~= "string" then
        uid = tostring(uid)
    end
    if not uid or uid == "" then
        warn("[Listing] Invalid UID for item: " .. tostring(itemData.Display))
        return false
    end
    
    -- Huge pets must be listed one at a time in PS99
    if itemData.IsHuge then
        amount = 1
        maxPerListing = 1
    end
    
    local totalListed = 0
    
    while amount > 0 do
        local listAmount = math.min(amount, maxPerListing)
        
        -- Extensive Debug Logging for Malformed Error
        print(string.format("[Listing Debug] Item: %s | UID: %s (Type: %s) | Price: %s (Type: %s) | Amount: %s (Type: %s)", 
            tostring(itemData.Display), 
            tostring(uid), type(uid),
            tostring(price), type(price),
            tostring(listAmount), type(listAmount)
        ))

        -- Defensive invoke with retry on malformed args
        local ok, result = pcall(function()
            -- Ensure strictly numbers are passed, and format integers as strings if game requires, but standard is number
            -- Some PS99 remotes are picky about scientific notation or float artifacts
            return Library.Network.Invoke("Booths_CreateListing", uid, tonumber(price), tonumber(listAmount))
        end)
        
        local success = ok and result == true
        
        if success then
            print("[Listing] Listed: " .. itemData.Display .. " x" .. listAmount .. " @ " .. AddSuffix(price))
            totalListed = totalListed + listAmount
            amount = amount - listAmount
        else
            warn("[Listing] Failed to list item: " .. tostring(itemData.Display) .. " (Error: " .. tostring(result) .. ")")
            
            -- Attempt a single corrective retry for common 'Malformed' cases
            print("[Listing] Retrying with strictly formatted values...")
            local retryOk, retryResult = pcall(function()
                -- Force strictly integer-like numbers
                local fixedPrice = tonumber(string.format("%.0f", price))
                local fixedAmount = tonumber(string.format("%.0f", listAmount))
                
                print("[Listing Debug Retry] Price: " .. tostring(fixedPrice) .. " | Amount: " .. tostring(fixedAmount))
                
                return Library.Network.Invoke("Booths_CreateListing", uid, fixedPrice, fixedAmount)
            end)
            
            if retryOk and retryResult == true then
                print("[Listing] Retry succeeded for " .. itemData.Display)
                totalListed = totalListed + listAmount
                amount = amount - listAmount
            else
                warn("[Listing] Retry failed; skipping item. Details: ok=" .. tostring(retryOk) .. ", result=" .. tostring(retryResult))
                return false
            end
        end
        
        task.wait(0.5)
    end
    
    return totalListed > 0
end

-- ============================================
-- SELLER MODE
-- ============================================

local SoldItemTracker = {}

local function SetupSoldItemListener()
    -- Listen for booth sales
    local connection = Library.Network.Fired("Booths: Add History"):Connect(function(Info)
        if not Info or not Info.Given then return end
        
        pcall(function()
            local receivedDiamonds = 0
            if Info.Received and Info.Received.Currency then
                for _, currencyData in pairs(Info.Received.Currency) do
                    if currencyData.id == "Diamonds" then
                        receivedDiamonds = (currencyData._am or 0)
                    end
                end
            end
            local givenDiamonds = 0
            if Info.Given and Info.Given.Currency then
                for _, currencyData in pairs(Info.Given.Currency) do
                    if currencyData.id == "Diamonds" then
                        givenDiamonds = (currencyData._am or 0)
                    end
                end
            end
            local netDiamonds = receivedDiamonds - givenDiamonds
            DebugPrint("[SaleCheck] received=", receivedDiamonds, "given=", givenDiamonds, "net=", netDiamonds)
            if netDiamonds <= 0 then return end
            
            -- Process sold items
            for class, classTable in pairs(Info.Given) do
                for uid, itemData in pairs(classTable) do
                    if class == "Currency" then
                        continue
                    end
                    local itemName = itemData.id
                    local amount = itemData._am or 1
                    
                    -- Avoid duplicate notifications
                    local trackKey = uid .. "_" .. os.time()
                    if SoldItemTracker[trackKey] then
                        continue
                    end
                    SoldItemTracker[trackKey] = true
                    
                    -- Clean old tracker entries (older than 5 minutes)
                    for key, _ in pairs(SoldItemTracker) do
                        local timestamp = tonumber(key:split("_")[2])
                        if timestamp and (os.time() - timestamp) > 300 then
                            SoldItemTracker[key] = nil
                        end
                    end
                    
                    DebugPrint("[Sold] item=", itemName, "amount=", amount, "earned=", netDiamonds)
                    
                    -- Get item icon
                    local icon = nil
                    pcall(function()
                        local itemTypes = require(NLibrary.Items.Types).Types
                        for className in pairs(itemTypes) do
                            local success, directory = pcall(function()
                                if className == "Misc" or className == "Card" then
                                    return require(NLibrary.Directory[className .. "Items"])
                                elseif className == "Lootbox" or className == "Box" then
                                    return require(NLibrary.Directory[className .. "es"])
                                else
                                    return require(NLibrary.Directory[className .. "s"])
                                end
                            end)
                            
                            if success and directory and directory[itemName] then
                                icon = directory[itemName].Icon or directory[itemName].thumbnail
                                if type(icon) == "function" then
                                    icon = icon(1)
                                end
                                break
                            end
                        end
                    end)
                    
                    -- Get booth status
                    local boothCount, itemsInBooth = FindItemsInBooth(itemName, class)
                    local inventoryCount = 0
                    pcall(function()
                        local inv = GetInventoryByClass(class)
                        if inv and inv._byUID then
                            for _, item in pairs(inv._byUID) do
                                if item.GetId and item:GetId() == itemName then
                                    inventoryCount = inventoryCount + (item._data._am or 1)
                                end
                            end
                        end
                    end)
                    
                    -- Send webhook
                    if Settings.Seller and Settings.Seller.Webhook and Settings.Seller.Webhook.Active then
                        local earnedTotal = netDiamonds
                        task.wait(0.1)
                        local totalDiamondsNow = GetDiamonds()
                        
                        local desc = string.format(
                            "**Item Statistics:**\n- 🎉 Sold: %s (x%d)\n- � Gained: %s\n\n**Other Statistics:**\n- � In Booth: %d\n- � Current Diamonds: %s",
                            itemName,
                            amount,
                            AddSuffix(earnedTotal),
                            itemsInBooth,
                            AddSuffix(totalDiamondsNow)
                        )
                        
                        local thumbnailUrl = nil
                        if icon then
                            local okParse, assetId = pcall(function()
                                return Library.Functions.ParseAssetId(icon)
                            end)
                            if okParse and assetId then
                                thumbnailUrl = "https://biggamesapi.io/image/" .. assetId
                            end
                        end
                        
                        local titleText = LocalPlayer.Name .. " has sold an item!"
                        SendWebhook(titleText, desc, 5763719, thumbnailUrl)
                    end
                    
                    SaveData.Statistics.ItemsSold = SaveData.Statistics.ItemsSold + amount
                        SaveData.Statistics.DiamondsEarned = SaveData.Statistics.DiamondsEarned + earnedTotal
                    SaveToFile()
                end
            end
        end)
    end)
    
    return connection
end

local function RunSellerMode()
    print("=================================")
    print("[SELLER] Starting seller mode...")
    print("=================================")
    
    -- Validate seller config
    if not Settings.Seller or not Settings.Seller.Items then
        warn("[Seller] No items configured")
        return
    end
    
    -- Set up sold item listener
    SetupSoldItemListener()
    
    -- Claim booth
    if not ClaimBooth() then
        warn("[Seller] Failed to claim booth, waiting...")
        task.wait(30)
        return RunSellerMode()
    end
    
    -- Sort items by priority
    local itemList = {}
    for name, config in pairs(Settings.Seller.Items) do
        if type(name) == "string" then
            table.insert(itemList, {
                Name = name,
                Config = config,
                Priority = config.Priority or false
            })
        end
    end
    
    table.sort(itemList, function(a, b)
        return a.Priority and not b.Priority
    end)
    
    -- Track items that have no inventory (to prevent spam)
    local noInventoryItems = {}
    
    -- Process each item
    local listedCount = 0
    for _, item in ipairs(itemList) do
        -- Skip if we already know there's no inventory
        if noInventoryItems[item.Name] then
            continue
        end
        
        local findInfo = GenerateFindInfo(item.Name, item.Config)
        if not findInfo.Class and not findInfo.ID:find("All ") then
            if not noInventoryItems[item.Name] then
                warn("[Seller] Could not find item type: " .. item.Name)
                noInventoryItems[item.Name] = true
            end
            continue
        end
        
        -- Get booth status
        local maxSlots = CurrentGame == "PS99" and PlayerSave.Get().BoothSlots or (4 + UpgradeCmds.GetPower("BiggerBooth"))
        local usedSlots, itemsInBooth = FindItemsInBooth(findInfo.ID, findInfo.Class)
        
        if usedSlots >= maxSlots then
            print("[Seller] Booth is full!")
            break
        end
        
        -- Check if already listed enough
        if item.Config.Amount and itemsInBooth >= item.Config.Amount then
            DebugPrint("Already listed enough: " .. item.Name)
            continue
        end
        
        -- Find items to list
        local uid, itemData = FindItem(findInfo, false)
        if not uid then
            if not noInventoryItems[item.Name] then
                DebugPrint("No items found in inventory for: " .. item.Name)
                noInventoryItems[item.Name] = true
            end
            continue
        end
        
        -- Clear from no-inventory tracker since we found it
        noInventoryItems[item.Name] = nil
        
        -- Calculate price
        local itemObj = nil
        local rap = nil
        
        -- For "All Huges" and similar, we need to create the item object from actual item data
        pcall(function()
            itemObj = CreateItemObject(itemData)
            rap = GetRAP(itemObj)
        end)
        
        -- If RAP is needed for pricing but not available, try alternative methods
        if not rap and (type(item.Config.Price) == "string" and (item.Config.Price:find("%%") or item.Config.Price:find("%+"))) then
            -- Try to get RAP from the inventory item directly
            local uid, invItem = FindItem(findInfo, false)
            if invItem then
                pcall(function()
                    local inventoryObj = GetInventoryByClass(invItem.Class)
                    if inventoryObj and inventoryObj._byUID and inventoryObj._byUID[invItem.UID] then
                        local actualItem = inventoryObj._byUID[invItem.UID]
                        rap = GetRAP(actualItem)
                    end
                end)
            end
            
            -- Still no RAP? Try cosmic values
            if not rap and item.Config.UseCosmicValues then
                rap = GetCosmicValue(itemData.Display)
            end
            
            -- Last resort: Use a fixed price instead
            if not rap then
                warn("[Seller] Cannot list " .. item.Name .. " - no RAP available. Consider using a fixed price instead of percentage.")
                BlacklistedUIDs[uid] = true
                continue
            end
        end
        
        -- Check manipulation
        if item.Config.DetectManipulation and rap then
            local status = CheckManipulation(itemData.Display, rap)
            if status == "Manipulated" then
                warn("[Seller] Skipping manipulated item: " .. item.Name)
                BlacklistedUIDs[uid] = true
                continue
            end
        end
        
        -- Use Cosmic Values if enabled
        if item.Config.UseCosmicValues then
            local cosmicValue = GetCosmicValue(itemData.Display)
            if cosmicValue then
                rap = cosmicValue
            end
        end
        
        local price = CalculatePrice(item.Config.Price, rap or 0)
        
        -- Apply min/max constraints
        if item.Config.MinPrice then
            price = math.max(price, RemoveSuffix(item.Config.MinPrice))
        end
        if item.Config.MaxPrice then
            price = math.min(price, RemoveSuffix(item.Config.MaxPrice))
        end
        
        -- Determine amount to list
        local listAmount = item.Config.Amount or itemData.Amount
        if item.Config.Amount and itemsInBooth > 0 then
            listAmount = math.max(0, item.Config.Amount - itemsInBooth)
        end
        listAmount = math.min(listAmount, itemData.Amount)
        
        if listAmount <= 0 then continue end
        
        -- List the item
        local success = ListItemToBooth(uid, itemData, price, listAmount)
        if success then
            listedCount = listedCount + 1
        end
        
        task.wait(1)
    end
    
    print("[Seller] Listed " .. listedCount .. " items")
end

-- ============================================
-- MAILBOX AUTO-CLAIM
-- ============================================

local mailboxNames = {"Flower", "Mountain", "Ocean", "Tiger", "Castle", "Star"}

local function GenerateMailboxMessage()
    return mailboxNames[math.random(#mailboxNames)] .. " " .. mailboxNames[math.random(#mailboxNames)]
end

task.spawn(function()
    while task.wait(30) do
        -- Claim all mail
        pcall(function()
            Library.Network.Invoke("Mailbox: Claim All")
        end)
        
        -- Send diamonds if configured
        if not Settings.Seller or not Settings.Seller["Diamonds Sendout"] then continue end
        local sendout = Settings.Seller["Diamonds Sendout"]
        if sendout.Active and sendout.Username ~= "" then
            local targetAmount = RemoveSuffix(sendout.Amount)
            local currentDiamonds = GetDiamonds()
            
            if currentDiamonds >= targetAmount then
                local cost = GetMailCost()
                if currentDiamonds >= targetAmount + cost then
                    local diamondUID = GetDiamonds(true)
                    pcall(function()
                        local success = Library.Network.Invoke(
                            "Mailbox: Send",
                            sendout.Username,
                            GenerateMailboxMessage(),
                            "Currency",
                            diamondUID,
                            targetAmount
                        )
                        
                        if success then
                            print("[Mailbox] Sent " .. AddSuffix(targetAmount) .. " diamonds to " .. sendout.Username)
                            SendWebhook(
                                "Diamonds Sent",
                                "Sent **" .. AddSuffix(targetAmount) .. "** diamonds to **" .. sendout.Username .. "**",
                                15844367
                            )
                        end
                    end)
                end
            end
        end
    end
end)

-- ============================================
-- KILL SWITCH MONITORING
-- ============================================

local function CheckKillSwitch()
    local mode = SaveData.Mode
    if not Settings[mode] or not Settings[mode]["Kill Switch"] then return false end
    local killSwitch = Settings[mode]["Kill Switch"]
    
    -- Check diamonds goal
    for key, active in pairs(killSwitch) do
        if key:match("Diamonds Hit") and active then
            local target = RemoveSuffix(key:match(": (.+)"))
            local current = GetDiamonds()
            
            if (mode == "Seller" and current >= target) or (mode == "Sniper" and current <= target) then
                local switchKey = mode == "Sniper" and "Switch To Selling" or "Switch To Sniping"
                
                if killSwitch["^^^ " .. switchKey] then
                    SaveData.Mode = mode == "Sniper" and "Seller" or "Sniper"
                    SaveData.StartTime = os.time()
                    SaveToFile()
                    
                    print("[Kill Switch] Switching modes: " .. SaveData.Mode)
                    SendWebhook("Mode Switch", "Switched to **" .. SaveData.Mode .. "** mode", 15844367)
                    
                    ServerHop()
                    return true
                else
                    print("[Kill Switch] Diamond goal reached - shutting down")
                    SendWebhook("Kill Switch", "Diamond goal reached: " .. AddSuffix(target), 15158332)
                    LocalPlayer:Kick("Kill Switch: Diamond goal reached")
                end
            end
        end
    end
    
    -- Check time limit
    if killSwitch["60 Minutes Timer"] then
        local elapsed = os.time() - SaveData.StartTime
        if elapsed >= 3600 then
            local switchKey = mode == "Sniper" and "Switch To Selling" or "Switch To Sniping"
            
            if killSwitch["^^^ " .. switchKey] then
                SaveData.Mode = mode == "Sniper" and "Seller" or "Sniper"
                SaveData.StartTime = os.time()
                SaveToFile()
                
                print("[Kill Switch] Time limit reached - switching modes")
                ServerHop()
                return true
            else
                print("[Kill Switch] Time limit reached - shutting down")
                LocalPlayer:Kick("Kill Switch: Time limit reached")
            end
        end
    end
    
    -- Check booth runout (seller only)
    if mode == "Seller" and killSwitch["Booth Runout"] then
        local usedSlots = FindItemsInBooth()
        if usedSlots == 0 then
            task.wait(3)
            usedSlots = FindItemsInBooth()
            
            if usedSlots == 0 then
                if killSwitch["^^^ Switch To Sniping"] then
                    SaveData.Mode = "Sniper"
                    SaveData.StartTime = os.time()
                    SaveToFile()
                    
                    print("[Kill Switch] Booth empty - switching to sniper")
                    ServerHop()
                    return true
                else
                    print("[Kill Switch] Booth empty - shutting down")
                    LocalPlayer:Kick("Kill Switch: Booth runout")
                end
            end
        end
    end
    
    return false
end

-- ============================================
-- MAIN LOOP
-- ============================================

local function Initialize()
    print("===========================================")
    print("     PET SIMULATOR TRADING BOT v2.0")
    print("     Game: " .. CurrentGame)
    print("     Mode: " .. SaveData.Mode)
    print("     User: " .. LocalPlayer.Name)
    print("===========================================")
    
    SetupAntiAFK()
    LastDiamonds = GetDiamonds()
    
    SendWebhook(
        "Bot Started",
        "**Mode:** " .. SaveData.Mode .. "\n**Game:** " .. CurrentGame .. "\n**Diamonds:** " .. AddSuffix(GetDiamonds()),
        3447003
    )
    
    while true do
        -- Check kill switch
        if CheckKillSwitch() then
            task.wait(5)
            continue
        end
        
        -- Run current mode
        if SaveData.Mode == "Seller" then
            RunSellerMode()
        else
            warn("[Sniper] Sniper mode not implemented in this version")
        end
        
        -- Check server hop timing
        local settings = Settings[SaveData.Mode] and Settings[SaveData.Mode]["Switch Servers"]
        if settings and settings.Active then
            local delay = settings.SecondDelay or (settings.MinuteDelay and settings.MinuteDelay * 60) or 600
            local elapsed = os.time() - StartTime
            
            if elapsed >= delay then
                ServerHop()
            end
        end
        
        task.wait(10)
    end
end

-- Start bot
local success, err = pcall(Initialize)
if not success then
    warn("[Bot] Fatal error: " .. tostring(err))
    SendWebhook("Bot Error", "Fatal error occurred:\n```" .. tostring(err) .. "```", 15158332)
end
