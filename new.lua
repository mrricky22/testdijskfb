local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- File path for logging (adjust if your executor uses a specific directory)
local LOG_FILE = "bounty_log.txt"

-- Custom logging function to append to file
local function logToFile(message)
    pcall(function()
        appendfile(LOG_FILE, os.date("%Y-%m-%d %H:%M:%S") .. " - " .. tostring(message) .. "\n")
    end)
end

-- Define the script to queue as a string
local scriptToRun = [[
    -- Wait until the game is fully loaded
    game.Loaded:Wait()
    
    -- Once the game is loaded, run the external script
    wait(1)
    loadstring(game:HttpGet("https://raw.githubusercontent.com/mrricky22/testdijskfb/refs/heads/main/new.lua"))()
]]

-- Function to join a new server - UPDATED to fetch and pick a random server
local function joinNewServer(placeId)
    logToFile("Finding a random server to join...")
    wait(5) -- Reduced wait time since we'll have additional processing
    
    local serversSuccess, servers = pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"
        local response = game:HttpGet(url)
        local data = HttpService:JSONDecode(response)
        return data.data
    end)
    
    if not serversSuccess or not servers or #servers == 0 then
        logToFile("Server fetch failed or no servers available. Trying default teleport.")
        pcall(function() 
            queue_on_teleport(scriptToRun)
            TeleportService:Teleport(placeId, Players.LocalPlayer)
        end)
        return
    end
    
    -- Find a suitable server - RANDOMLY
    local currentJobId = game.JobId
    local suitableServers = {}
    
    -- Collect all suitable servers first
    for _, server in pairs(servers) do
        if server.id ~= currentJobId and server.playing < server.maxPlayers then
            table.insert(suitableServers, server)
        end
    end
    
    -- Pick a random server from suitable ones
    if #suitableServers > 0 then
        -- Seed random with the current time to ensure different results
        math.randomseed(tick())
        local randomIndex = math.random(1, #suitableServers)
        local targetServer = suitableServers[randomIndex]
        
        logToFile("Selected random server " .. randomIndex .. " of " .. #suitableServers .. " available servers")
        logToFile("Joining server with JobId: " .. targetServer.id .. " (Players: " .. targetServer.playing .. "/" .. targetServer.maxPlayers .. ")")
        
        pcall(function()
            queue_on_teleport(scriptToRun)
            TeleportService:TeleportToPlaceInstance(placeId, targetServer.id, Players.LocalPlayer)
        end)
    else
        logToFile("No suitable servers found. Trying default teleport.")
        pcall(function() 
            queue_on_teleport(scriptToRun)
            TeleportService:Teleport(placeId, Players.LocalPlayer)
        end)
    end
end

-- Main function to check bounties and hop servers
local function main()
    local success, errorMsg = pcall(function()
        local placeId = game.PlaceId
        
        -- Try to access the most wanted board with better error logging
        local mostWantedSuccess, mostWantedResult = pcall(function()
            -- First, log what we're trying to do
            logToFile("Attempting to access MostWanted board...")
            
            -- Check if MostWanted exists in workspace
            local mostWanted = workspace:FindFirstChild("MostWanted")
            if not mostWanted then
                logToFile("ERROR: MostWanted not found in workspace")
                return nil, "MostWanted not found in workspace"
            end
            
            -- Wait for MostWanted with timeout
            local mostWantedObject = workspace:WaitForChild("MostWanted", 10)
            if not mostWantedObject then
                logToFile("ERROR: MostWanted timeout after 10 seconds")
                return nil, "Timeout waiting for MostWanted"
            end
            
            -- Log the children of MostWanted
            logToFile("MostWanted children count: " .. #mostWantedObject:GetChildren())
            for i, child in pairs(mostWantedObject:GetChildren()) do
                logToFile("Child " .. i .. ": " .. child.Name .. " (Class: " .. child.ClassName .. ")")
            end
            
            -- Check if we can access the second child
            if #mostWantedObject:GetChildren() < 2 then
                logToFile("ERROR: MostWanted has fewer than 2 children")
                return nil, "MostWanted has fewer than 2 children"
            end
            
            local secondChild = mostWantedObject:GetChildren()[2]
            logToFile("Second child name: " .. secondChild.Name)
            
            -- Check if Background exists in the second child
            local background = secondChild:FindFirstChild("Background")
            if not background then
                logToFile("ERROR: Background not found in " .. secondChild.Name)
                return nil, "Background not found in second child"
            end
            
            -- Check if MostWanted exists in Background
            local mostWantedInBackground = background:FindFirstChild("MostWanted")
            if not mostWantedInBackground then
                logToFile("ERROR: MostWanted not found in Background")
                return nil, "MostWanted not found in Background"
            end
            
            -- Check if Board exists in MostWanted
            local board = mostWantedInBackground:FindFirstChild("Board")
            if not board then
                logToFile("ERROR: Board not found in MostWanted")
                return nil, "Board not found in MostWanted"
            end
            
            logToFile("Successfully found MostWanted board")
            return board
        end)
        
        if not mostWantedSuccess then
            logToFile("Error accessing MostWanted board: " .. tostring(mostWantedResult))
            joinNewServer(placeId)
            return
        end
        
        if not mostWantedResult then
            logToFile("MostWanted board is nil despite successful pcall. Joining new server.")
            joinNewServer(placeId)
            return
        end
        
        local mostWantedBoard = mostWantedResult
        
        -- Check all bounties and log them
        local function checkAllBounties()
            local foundHighBounty = false
            local bountySuccess, bountyError = pcall(function()
                logToFile("--- Checking all bounties in current server ---")
                
                for _, child in pairs(mostWantedBoard:GetDescendants()) do
                    if (child:IsA("TextLabel") or child:IsA("TextButton")) and child.Name == "Bounty" then
                        local bountyText = child.Text
                        
                        -- Find the parent of the bounty text to access the player name
                        local parent = child.Parent
                        local playerName = "Unknown"
                        
                        -- Look for PlayerName in the same parent or siblings
                        if parent then
                            for _, sibling in pairs(parent:GetChildren()) do
                                if (sibling:IsA("TextLabel") or sibling:IsA("TextButton")) and sibling.Name == "PlayerName" then
                                    playerName = sibling.Text
                                    break
                                end
                            end
                        end
                        
                        local amountString = string.match(bountyText, "%$([0-9,]+)")
                        if amountString then
                            local cleanAmountString = amountString:gsub(",", "")
                            local amount = tonumber(cleanAmountString)
                            
                            -- Log all bounties
                            logToFile("Player: " .. playerName .. " | Bounty: " .. bountyText)
                            
                            -- Track if we found any high bounties
                            if amount and amount > 10000 then
                                logToFile("*** HIGH BOUNTY FOUND *** Player=" .. playerName .. " | Bounty=" .. bountyText)
                                foundHighBounty = true
                                -- Note: Not returning early, continuing to check all bounties
                            end
                        end
                    end
                end
                
                logToFile("--- Finished checking all bounties ---")
            end)
            
            if not bountySuccess then
                logToFile("Error checking bounties: " .. tostring(bountyError))
                return false
            end
            
            return foundHighBounty
        end
        
        -- Check all bounties but don't stop if we find high bounties
        local foundHighBounty = checkAllBounties()
        
        if foundHighBounty then
            logToFile("High bounty found in this server. Staying in server.")
            -- Stay in the server, don't hop to a new one
            return
        end
        
        -- Only join new server if no high bounties found
        logToFile("No high bounties found. Hopping to a new server...")
        joinNewServer(placeId)
    end)
    
    if not success then
        logToFile("Main function error: " .. tostring(errorMsg))
        pcall(function()
            local placeId = game.PlaceId
            joinNewServer(placeId)
        end)
    end
end

-- Wrap the entire execution in pcall
pcall(function()
    -- Start the script with error handling
    main()
end)

-- Fallback in case the entire script fails
pcall(function()
    logToFile("Script execution completed or failed. Ensuring queue_on_teleport is set.")
    queue_on_teleport(scriptToRun)
end)
