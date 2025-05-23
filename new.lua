local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- File paths for logging and server data
local LOG_FILE = "bounty_log.txt"
local SERVER_DATA_FILE = "server_data.txt"

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
    wait(2)
    loadstring(game:HttpGet("https://raw.githubusercontent.com/mrricky22/testdijskfb/refs/heads/main/new.lua"))()
]]

-- Function to save server data to file
local function saveServerData(servers, currentIndex)
    pcall(function()
        local dataToSave = {
            servers = servers,
            currentIndex = currentIndex,
            timestamp = os.time()
        }
        writefile(SERVER_DATA_FILE, HttpService:JSONEncode(dataToSave))
        logToFile("Saved server data with " .. #servers .. " servers, current index: " .. currentIndex)
    end)
end

-- Function to load server data from file
local function loadServerData()
    local success, data = pcall(function()
        if isfile(SERVER_DATA_FILE) then
            local content = readfile(SERVER_DATA_FILE)
            return HttpService:JSONDecode(content)
        end
        return nil
    end)
    
    if success and data then
        logToFile("Loaded server data with " .. #data.servers .. " servers, current index: " .. data.currentIndex)
        return data
    end
    return nil
end

-- Function to fetch a new list of servers
local function fetchServerList(placeId)
    logToFile("Fetching a new list of servers...")
    
    local success, servers = pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Desc&limit=100"
        local response = game:HttpGet(url)
        local data = HttpService:JSONDecode(response)
        return data.data
    end)
    
    if not success or not servers or #servers == 0 then
        logToFile("Failed to fetch servers: " .. tostring(servers))
        return nil
    end
    
    logToFile("Successfully fetched " .. #servers .. " servers")
    return servers
end

-- Function to attempt teleporting to a server with error handling
local function attemptTeleport(placeId, serverId)
    local teleportSuccess, teleportError = pcall(function()
        queue_on_teleport(scriptToRun)
        TeleportService:TeleportToPlaceInstance(placeId, serverId, Players.LocalPlayer)
    end)
    
    if not teleportSuccess then
        logToFile("Teleport failed: " .. tostring(teleportError))
        return false
    end
    
    return true
end

-- Function to join the next server from the list with better error handling
local function joinNextServer(placeId, serverData)
    wait(3)
    local currentJobId = game.JobId
    local servers = serverData.servers
    local currentIndex = serverData.currentIndex
    
    -- Track servers we've tried to join
    local triedServers = {}
    
    -- Check if we need to refresh the server list
    if currentIndex > #servers then
        logToFile("Reached the end of the server list. Fetching new servers...")
        local newServers = fetchServerList(placeId)
        if not newServers or #newServers == 0 then
            logToFile("Failed to get new servers. Using default teleport.")
            pcall(function() 
                queue_on_teleport(scriptToRun)
                TeleportService:Teleport(placeId, Players.LocalPlayer)
            end)
            return
        end
        
        servers = newServers
        currentIndex = 1
        saveServerData(servers, currentIndex)
    end
    
    -- Try to join servers until we succeed or exhaust the list
    local maxAttempts = #servers
    local attempts = 0
    
    while attempts < maxAttempts do
        -- Get the next server to try
        local server = servers[currentIndex]
        
        -- Update the index for next attempt
        local nextIndex = currentIndex + 1
        if nextIndex > #servers then nextIndex = 1 end
        
        -- Validate the server
        if server and server.id ~= currentJobId and server.playing < server.maxPlayers and server.playing < 27 and not triedServers[server.id] then
            logToFile("Attempting to join server with JobId: " .. server.id .. " (Players: " .. server.playing .. "/" .. server.maxPlayers .. ")")
            
            -- Mark this server as tried
            triedServers[server.id] = true
            
            -- Try to teleport
            local success = attemptTeleport(placeId, server.id)
            
            if success then
                -- Save the next index in case teleport still fails after success
                saveServerData(servers, nextIndex)
                wait(5) -- Give time for teleport to happen
                
                -- If we're still here, teleport might have silently failed
                logToFile("Teleport didn't complete after 5 seconds, trying next server")
            end
        end
        
        -- Move to the next server
        currentIndex = nextIndex
        attempts = attempts + 1
        
        -- Small wait between attempts
        wait(1)
    end
    
    -- If we get here, we've exhausted our options
    logToFile("Failed to join any server after " .. attempts .. " attempts. Using default teleport.")
    pcall(function() 
        queue_on_teleport(scriptToRun)
        TeleportService:Teleport(placeId, Players.LocalPlayer)
    end)
end

-- Event handler for teleport failures
TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
    if player == Players.LocalPlayer then
        logToFile("Teleport failed: " .. teleportResult.Name .. " - " .. tostring(errorMessage))
        
        -- Load the latest server data
        local serverData = loadServerData()
        if not serverData then
            local placeId = game.PlaceId
            local servers = fetchServerList(placeId)
            if not servers then
                logToFile("Failed to fetch servers after teleport error. Using default teleport.")
                queue_on_teleport(scriptToRun)
                TeleportService:Teleport(placeId, Players.LocalPlayer)
                return
            end
            serverData = {servers = servers, currentIndex = 1, timestamp = os.time()}
        else
            -- Increment the index to try the next server
            serverData.currentIndex = serverData.currentIndex + 1
            if serverData.currentIndex > #serverData.servers then
                serverData.currentIndex = 1
            end
        end
        
        -- Save updated index and try again
        saveServerData(serverData.servers, serverData.currentIndex)
        wait(2) -- Brief delay before trying again
        joinNextServer(game.PlaceId, serverData)
    end
end)

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
            
            -- Get or initialize server data
            local serverData = loadServerData()
            if not serverData then
                local servers = fetchServerList(placeId)
                if not servers then
                    logToFile("Failed to fetch initial servers. Using default teleport.")
                    queue_on_teleport(scriptToRun)
                    TeleportService:Teleport(placeId, Players.LocalPlayer)
                    return
                end
                serverData = {servers = servers, currentIndex = 1, timestamp = os.time()}
                saveServerData(servers, 1)
            end
            
            joinNextServer(placeId, serverData)
            return
        end
        
        if not mostWantedResult then
            logToFile("MostWanted board is nil despite successful pcall. Joining new server.")
            
            -- Get or initialize server data
            local serverData = loadServerData()
            if not serverData then
                local servers = fetchServerList(placeId)
                if not servers then
                    logToFile("Failed to fetch initial servers. Using default teleport.")
                    queue_on_teleport(scriptToRun)
                    TeleportService:Teleport(placeId, Players.LocalPlayer)
                    return
                end
                serverData = {servers = servers, currentIndex = 1, timestamp = os.time()}
                saveServerData(servers, 1)
            end
            
            joinNextServer(placeId, serverData)
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
        
        -- Get or initialize server data if we need to hop
        local serverData = loadServerData()
        if not serverData then
            local servers = fetchServerList(placeId)
            if not servers then
                logToFile("Failed to fetch initial servers. Using default teleport.")
                queue_on_teleport(scriptToRun)
                TeleportService:Teleport(placeId, Players.LocalPlayer)
                return
            end
            serverData = {servers = servers, currentIndex = 1, timestamp = os.time()}
            saveServerData(servers, 1)
        end
        
        -- Only join new server if no high bounties found
        logToFile("No high bounties found. Hopping to the next server...")
        joinNextServer(placeId, serverData)
    end)
    
    if not success then
        logToFile("Main function error: " .. tostring(errorMsg))
        pcall(function()
            local placeId = game.PlaceId
            
            -- Get or initialize server data
            local serverData = loadServerData()
            if not serverData then
                local servers = fetchServerList(placeId)
                if not servers then
                    logToFile("Failed to fetch initial servers after error. Using default teleport.")
                    queue_on_teleport(scriptToRun)
                    TeleportService:Teleport(placeId, Players.LocalPlayer)
                    return
                end
                serverData = {servers = servers, currentIndex = 1, timestamp = os.time()}
                saveServerData(servers, 1)
            end
            
            joinNextServer(placeId, serverData)
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
end)
