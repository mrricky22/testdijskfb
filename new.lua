local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- Define the script to queue as a separate string
local scriptToRun = [[
    loadstring(game:HttpGet("https://raw.githubusercontent.com/mrricky22/testdijskfb/refs/heads/main/new.lua"))()
]]
-- Function to fetch server list using game:HttpGet
local function fetchServerList(placeId)
    local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"
    local success, response = pcall(function()
        return game:HttpGet(url) -- Executor-specific
    end)
    
    if success then
        local data = HttpService:JSONDecode(response)
        return data.data
    else
        warn("Failed to fetch server list: " .. response)
        return nil
    end
end

-- Function to join a server by jobId with queue_on_teleport
local function joinServer(jobId, placeId)
    print("Attempting to join server with JobId: " .. jobId)
    
    -- Queue the script and teleport
    queue_on_teleport(scriptToRun)
    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, jobId, Players.LocalPlayer)
    end)
    
    if not success then
        warn("Teleport failed: " .. err)
        queue_on_teleport(scriptToRun) -- Requeue on failure
        TeleportService:Teleport(placeId, Players.LocalPlayer) -- Fallback
    end
end

-- Main function to check bounties and hop servers
local function main()
    local placeId = game.PlaceId
    local mostWantedBoard = workspace:WaitForChild("MostWanted"):GetChildren()[2].Background.MostWanted.Board
    
    -- Check for large bounties
    local function findLargeBounties()
        for _, child in pairs(mostWantedBoard:GetDescendants()) do
            if (child:IsA("TextLabel") or child:IsA("TextButton")) and child.Name == "Bounty" then
                local bountyText = child.Text
                print("Raw bounty text: " .. bountyText)
                
                local amountString = string.match(bountyText, "%$([0-9,]+)")
                if amountString then
                    print("Extracted amount string: " .. amountString)
                    local cleanAmountString = amountString:gsub(",", "")
                    print("Cleaned amount string: " .. cleanAmountString)
                    
                    local amount = tonumber(cleanAmountString)
                    if amount then
                        print("Converted amount: " .. amount)
                        if amount > 10000 then
                            print("Found large bounty: " .. bountyText)
                            return true
                        end
                    else
                        warn("Failed to convert '" .. cleanAmountString .. "' to number")
                    end
                else
                    warn("No numeric value found in: " .. bountyText)
                end
            end
        end
        print("No bounties over 10,000 found")
        return false
    end
    
    if findLargeBounties() then
        print("Found a bounty over 10,000! Stopping.")
        return
    end
    
    -- Fetch server list if no large bounty found
    print("No large bounties found. Fetching server list...")
    local servers = fetchServerList(placeId)
    
    if servers and #servers > 0 then
        local currentJobId = game.JobId
        local targetServer
        for _, server in pairs(servers) do
            if server.id ~= currentJobId and server.playing < server.maxPlayers then
                targetServer = server
                break
            end
        end
        
        if targetServer then
            joinServer(targetServer.id, placeId)
        else
            warn("No suitable server found. Teleporting to new instance...")
            queue_on_teleport(scriptToRun)
            TeleportService:Teleport(placeId, Players.LocalPlayer)
        end
    else
        warn("No servers fetched. Teleporting to new instance...")
        queue_on_teleport(scriptToRun)
        TeleportService:Teleport(placeId, Players.LocalPlayer)
    end
end

-- Start the script
main()
