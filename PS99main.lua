--// SERVICES
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

--// Initialize game state
if not game:IsLoaded() then 
    game.Loaded:Wait()
end

repeat task.wait() 
    LocalPlayer = Players.LocalPlayer
until LocalPlayer and LocalPlayer:GetAttribute("__LOADED")

--// Character setup
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 10)
if not HumanoidRootPart then
    warn("HumanoidRootPart not found! Exiting script.")
    return
end

local NLibrary = ReplicatedStorage:WaitForChild("Library")

--// Load Library (cached)
local function LoadModules(Path, IsOne, LoadItself)
    if IsOne then
        local Status, Module = pcall(require, Path)
        if Status then getgenv().Library[Path.Name] = Module end
        return
    end
    if LoadItself then
        local Status, Module = pcall(require, Path)
        if Status then getgenv().Library[Path.Name] = Module end
    end
    for _, v in Path:GetChildren() do
        if v:IsA("ModuleScript") and not v:GetAttribute("NOLOAD") and v.Name ~= "ToRomanNum" then
            local Status, Module = pcall(require, v)
            if Status then getgenv().Library[v.Name] = Module end
        end
    end
end

if not getgenv().Library then
    getgenv().Library = {}
    for _, v in {
        NLibrary,
        NLibrary.Directory,
        NLibrary.Client,
        NLibrary.Util,
        NLibrary.Types,
        NLibrary.Items,
        NLibrary.Functions,
        NLibrary.Modules,
        NLibrary.Balancing
    } do
        LoadModules(v)
    end
    LoadModules(NLibrary.Shared.Variables, true)
end

--// Remove Egg Animation
task.spawn(function()
    repeat task.wait() until getgenv().Library and getgenv().Library.EggFrontend
    getgenv().Library.EggFrontend.PlayEggAnimation = function() end
    print("[World Egg] Egg animation disabled (Library)")
end)

task.spawn(function()
    local success = pcall(function()
        local Eggs = LocalPlayer.PlayerScripts.Scripts.Game['Egg Opening Frontend']
        getsenv(Eggs).PlayEggAnimation = function() return end
        print("[World Egg] Egg animation disabled (PlayerScripts)")
    end)
    if not success then
        warn("Could not disable PlayerScripts egg animation")
    end
end)

--// RAYFIELD UI
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "ProjectX",
    Icon = 0,
    LoadingTitle = "ProjectX Loding",
    LoadingSubtitle = "by Kings00",
    ShowText = "ProjectX",
    Theme = "Default",
    ToggleUIKeybind = "K",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,
    ConfigurationSaving = {Enabled = true, FolderName = nil, FileName = "Big Hub"},
    Discord = {Enabled = false, Invite = "https://discord.gg/yCjxFgHpfE", RememberJoins = true},
    KeySystem = false,
    KeySettings = {
        Title = "ProjectX-Key",
        Subtitle = "Key System",
        Note = "No method of obtaining the key is provided",
        FileName = "Cake",
        SaveKey = true,
        GrabKeyFromSite = false,
        Key = {"Hello"}
    }
})

--// TABS
local HomeTab = Window:CreateTab("Home", "home")
HomeTab:CreateButton({Name = "Stats", Callback = function() end})
local CurrentEventTab = Window:CreateTab("CurrentEvent", "egg")
local WorldEggTab = Window:CreateTab("World Egg", "egg")
local AutomaticTab = Window:CreateTab("Automatic", "settings")
Window:CreateTab("Mailbox", "mail")
Window:CreateTab("Webhook", "webhook")
local OptimizationTab = Window:CreateTab("Optimization", "rocket")

--// Cached references
local NetworkFolder = ReplicatedStorage:WaitForChild("Network")
local ThingsFolder = workspace:FindFirstChild("__THINGS")

--// Helper: Anti-AFK
local function EnableAntiAFK()
    local vu = game:GetService("VirtualUser")
    local Plr = game:GetService("Players").LocalPlayer

    -- Disable Roblox's default idle kicker
    if getconnections then
        for _, v in pairs(getconnections(Plr.Idled)) do
            v:Disable()
        end
    end

    Plr.Idled:connect(function()
        vu:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
        wait(1)
        vu:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
        print("[Anti-AFK] Action performed")
    end)
end
EnableAntiAFK()

--// Helper: Auto loop with error handling
local function CreateAutoLoop(flagName, callback, interval)
    interval = interval or 0.5
    return function(Value)
        _G[flagName] = Value
        if Value then
            task.spawn(function()
                while _G[flagName] do
                    local success, err = pcall(callback)
                    if not success then warn(flagName .. " error:", err) end
                    task.wait(interval)
                end
            end)
        end
    end
end

--------------------------------------------------
-- AUTO HATCH MAX
--------------------------------------------------
CurrentEventTab:CreateButton({
    Name = "Teleport to Event Egg",
    Callback = function()
        local function IsInEventWorld()
            local success, result = pcall(function()
                local InstanceContainer = workspace.__THINGS.__INSTANCE_CONTAINER.Active:FindFirstChild("XmasWorld")
                return InstanceContainer ~= nil
            end)
            return success and result
        end
        
        local function TeleportToEventWorld()
            pcall(function()
                local Portal = workspace.__THINGS.Instances.XmasWorld.Teleports.Enter
                if Portal and HumanoidRootPart then
                    HumanoidRootPart.CFrame = Portal.CFrame
                    print("[Teleport] Entered Event World via portal")
                end
            end)
        end
        
        local function TeleportToEgg()
            pcall(function()
                local InstanceContainer = workspace.__THINGS.__INSTANCE_CONTAINER.Active.XmasWorld:GetChildren()[299]
                local EventEgg = InstanceContainer:GetChildren()[6]:GetChildren()[11].Model.Model:GetChildren()[2]:GetChildren()[4]
                if EventEgg and HumanoidRootPart then
                    local targetPos = EventEgg.Position
                    local backwardOffset = HumanoidRootPart.CFrame.LookVector * -10
                    local leftOffset = HumanoidRootPart.CFrame.RightVector * -8
                    local newPos = targetPos + backwardOffset + leftOffset
                    HumanoidRootPart.CFrame = CFrame.new(newPos.X, newPos.Y, newPos.Z)
                    print("[Teleport] Teleported to Event Egg (back & left)")
                else
                    warn("[Teleport] Event Egg not found")
                end
            end)
        end
        
        -- Check if already in event world
        if IsInEventWorld() then
            print("[Teleport] Already in Event World, going to egg...")
            TeleportToEgg()
            task.wait(0.1)
            TeleportToEgg()
        else
            print("[Teleport] Entering Event World first...")
            TeleportToEventWorld()
            -- Wait longer for world to fully load
            task.wait(1.5)
            -- Wait until we confirm we're in the event world
            local attempts = 0
            while not IsInEventWorld() and attempts < 10 do
                task.wait(0.2)
                attempts = attempts + 1
            end
            print("[Teleport] World loaded, teleporting to egg...")
            TeleportToEgg()
            task.wait(0.1)
            TeleportToEgg()
        end
    end
})

CurrentEventTab:CreateToggle({
    Name = "Auto Hatch Max",
    CurrentValue = false,
    Flag = "AutoHatchMax",
    Callback = function(Value)
        _G.AutoOpen = Value
        if Value then
            -- EnableAntiAFK() is now global
            task.spawn(function()
                while _G.AutoOpen do
                    pcall(function()
                        local CustomEggsFolder = ThingsFolder and ThingsFolder:FindFirstChild("CustomEggs")
                        if not CustomEggsFolder then return end

                        local nearest, nearest_distance = nil, math.huge
                        for _, v in CustomEggsFolder:GetChildren() do
                            if v:IsA("Model") and v.PrimaryPart then
                                local dist = (HumanoidRootPart.Position - v.PrimaryPart.Position).Magnitude
                                if dist < nearest_distance then
                                    nearest = v.Name
                                    nearest_distance = dist
                                end
                            end
                        end

                        if nearest and getgenv().Library and getgenv().Library.EggCmds then
                            local MaxEggHatch = getgenv().Library.EggCmds.GetMaxHatch()
                            local HatchRemote = NetworkFolder:FindFirstChild("CustomEggs_Hatch")
                            if HatchRemote then
                                HatchRemote:InvokeServer(nearest, MaxEggHatch)
                            end
                        end
                    end)
                    task.wait(0.5)
                end
            end)
        end
    end
})

CurrentEventTab:CreateSection("Secret Santa")

local SecretSantaAmount = 5

CurrentEventTab:CreateSlider({
    Name = "Select Amount",
    Range = {0, 500},
    Increment = 1,
    Suffix = "Gifts",
    CurrentValue = 5,
    Flag = "SecretSantaAmount",
    Callback = function(Value)
        SecretSantaAmount = Value
    end
})

CurrentEventTab:CreateButton({
    Name = "Send Secret Santa",
    Callback = function()
        local args = {
            {
                ["1a395641622044dfad4c9c44bbb81f6e"] = SecretSantaAmount
            }
        }
        game:GetService("ReplicatedStorage"):WaitForChild("Network"):WaitForChild("Secret Santa: Send"):InvokeServer(unpack(args))
        print("[Secret Santa] Sent " .. SecretSantaAmount .. " gifts")
    end
})

--------------------------------------------------
-- LOW GRAPHICS / FPS BOOST
--------------------------------------------------
OptimizationTab:CreateToggle({
    Name = "Low Graphics / FPS Boost",
    CurrentValue = false,
    Flag = "LowGraphics",
    Callback = function(Value)
        _G.LowGraphics = Value
        local w = workspace

        local function OptimizeObject(v)
            if v:IsA("BasePart") then
                v.Material = Enum.Material.Plastic
                v.Reflectance = 0
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
                v.Lifetime = NumberRange.new(0)
            elseif v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
                v.Enabled = false
            end
        end

        if Value then
            task.spawn(function()
                for _, v in w:GetDescendants() do
                    OptimizeObject(v)
                end
                w.DescendantAdded:Connect(function(v)
                    if _G.LowGraphics then OptimizeObject(v) end
                end)
            end)
        end
    end
})

--------------------------------------------------
-- WORLD EGG TAB
--------------------------------------------------
local SelectedWorldEgg = "Flora Egg"

WorldEggTab:CreateDropdown({
    Name = "Select Egg",
    Options = {"Flora Egg", "Ocean Egg", "Forest Egg"},
    CurrentOption = SelectedWorldEgg,
    Flag = "SelectedWorldEgg",
    Callback = function(option)
        SelectedWorldEgg = option
    end
})

WorldEggTab:CreateButton({
    Name = "Teleport to Last Egg",
    Callback = function()
        pcall(function()
            local ZoneEggs = workspace.__THINGS.ZoneEggs.World4
            local EggCapsule = ZoneEggs:FindFirstChild("286 - Egg Capsule")
            if EggCapsule and EggCapsule:FindFirstChild("Tier") and HumanoidRootPart then
                local targetPos = EggCapsule.Tier.Position
                HumanoidRootPart.CFrame = CFrame.new(targetPos.X, targetPos.Y + 5, targetPos.Z)
                print("[Teleport] Teleported to Egg Capsule 286")
            else
                warn("[Teleport] Egg Capsule 286 not found")
            end
        end)
    end
})

WorldEggTab:CreateToggle({
    Name = "Auto Open World Egg",
    CurrentValue = false,
    Flag = "AutoOpenWorldEgg",
    Callback = CreateAutoLoop("AutoOpenWorldEgg", function()
        local PurchaseRemote = NetworkFolder:FindFirstChild("Eggs_RequestPurchase")
        if PurchaseRemote and getgenv().Library and getgenv().Library.EggCmds then
            local MaxEggHatch = getgenv().Library.EggCmds.GetMaxHatch()
            PurchaseRemote:InvokeServer(SelectedWorldEgg, MaxEggHatch)
        end
    end)
})

--------------------------------------------------
-- AUTOMATIC TAB: Wheels & Chests
--------------------------------------------------
local SpinRemote = NetworkFolder:WaitForChild("Spinny Wheel: Request Spin")

AutomaticTab:CreateSection("🎡 Wheels")

-- Create wheel toggles efficiently
local wheels = {"FantasyWheel", "VoidWheel", "TechWheel"}
for _, wheelName in wheels do
    AutomaticTab:CreateToggle({
        Name = "Auto Spin " .. wheelName,
        CurrentValue = false,
        Flag = "AutoSpin" .. wheelName,
        Callback = CreateAutoLoop("AutoSpin" .. wheelName, function()
            SpinRemote:InvokeServer(wheelName)
        end, 1)
    })
end

--------------------------------------------------
AutomaticTab:CreateSection("🔑 Chests")

-- Create chest toggles efficiently
local chests = {
    {name = "Fantasy", remote = "FantasyKey_Unlock"},
    {name = "VoidKey", remote = "VoidKey_Unlock"},
    {name = "TechKey", remote = "TechKey_Unlock"}
}

for _, chest in chests do
    AutomaticTab:CreateToggle({
        Name = "Auto Unlock " .. chest.name,
        CurrentValue = false,
        Flag = "AutoUnlock" .. chest.name,
        Callback = CreateAutoLoop("AutoUnlock" .. chest.name, function()
            local UnlockRemote = NetworkFolder:FindFirstChild(chest.remote)
            if UnlockRemote then
                UnlockRemote:InvokeServer(100)
            end
        end, 2)
    })
end
