VORPcore = exports.vorp_core:GetCore()
local BccUtils = exports['bcc-utils'].initiate()
local discord = BccUtils.Discord.setup(Config.Webhook, Config.WebhookTitle, Config.WebhookAvatar)

-- Helper functions
function devPrint(message)
    if Config.devMode then
        print(message)
    end
end

function getItemDetails(itemName, callback)
    fetchDetails('unified_items', 'item_name', itemName, callback)
end

function getWeaponDetails(weaponName, callback)
    fetchDetails('unified_items', 'item_name', weaponName, callback)
end

function fetchDetails(table, column, value, callback)
    MySQL.Async.fetchAll('SELECT * FROM ' .. table .. ' WHERE ' .. column .. ' = @value', { ['@value'] = value }, function(result)
        if result and #result > 0 then
            devPrint("Fetched details: " .. json.encode(result[1]))
            callback(result[1])
        else
            devPrint(column .. " not found: " .. value)
            callback(nil)
        end
    end)
end

function getLevelFromXP(xp)
    return math.floor(xp / 1000)
end

function getPlayerXP(source)
    return VORPcore.getUser(source).getUsedCharacter.xp
end

function getSellPrice(type, name)
    for _, shop in pairs(Config.shops) do
        for _, item in pairs(shop[type]) do
            if item[type == "items" and "itemName" or "weaponName"] == name and item.sellprice then
                return item.sellprice
            end
        end
    end
    return 0
end

-- Function to handle NPC store inventory
local function handleNPCInventory(src, shopName)
    local inventory = exports.vorp_inventory:getUserInventoryItems(src)
    TriggerClientEvent('npcstore:receiveInventory', src, inventory, shopName)
end

-- Function to handle Player store inventory
local function handlePlayerInventory(src, shopName)
    exports.vorp_inventory:getUserInventoryItems(src, function(inventory)
        -- Ensure the inventory items have the correct key names
        for _, item in ipairs(inventory) do
            item.item_name = item.name  -- Normalize the key name
        end
        TriggerClientEvent('playerstore:receiveInventory', src, inventory, shopName)
    end)
end

-- Registering Events
RegisterServerEvent('npcstore:fetchInventory', function(shopName)
    handleNPCInventory(source, shopName)
end)

RegisterServerEvent('playerstore:fetchInventory', function(shopName)
    handlePlayerInventory(source, shopName)
end)

local function removeItemFromShop(shopId, itemName, ownerId, callback)
    MySQL.Async.fetchScalar('SELECT owner_id FROM unified_shops WHERE shop_id = @shopId', {
        ['@shopId'] = shopId
    }, function(result)
        if result == ownerId then
            MySQL.Async.execute('DELETE FROM unified_items WHERE shop_id = @shopId AND item_name = @itemName', {
                ['@shopId'] = shopId,
                ['@itemName'] = itemName
            }, function(rowsChanged)
                callback(rowsChanged > 0)
            end)
        else
            callback(false)
        end
    end)
end

RegisterServerEvent('playerstore:addItem')
AddEventHandler('playerstore:addItem', function(shopId, itemName, itemLabel, quantity, buyPrice, sellPrice, category, levelRequired)
    local src = source
    local user = VORPcore.getUser(src)
    local character = user.getUsedCharacter
    local ownerId = character.charIdentifier

    devPrint("AddItem event received for shopId: " .. tostring(shopId) .. ", itemName: " .. tostring(itemName) .. ", ownerId: " .. tostring(ownerId))

    AddItemToStore(shopId, itemName, itemLabel, quantity, buyPrice, sellPrice, category, levelRequired, ownerId, function(success)
        if success then
            VORPcore.NotifyTip(src, "Item added successfully", 4000)
            TriggerClientEvent('playerstore:fetchPlayerInventory', src, shopId)
        else
            VORPcore.NotifyTip(src, "Failed to add item. You may not be the owner of the shop.", 4000)
        end
    end)
end)

RegisterServerEvent('playerstore:checkInventoryLimit')
AddEventHandler('playerstore:checkInventoryLimit', function(shopName, item, inputQuantity, inputBuyPrice, inputSellPrice, inputCategory, inputLevelRequired)
    local src = source
    MySQL.Async.fetchAll('SELECT shop_id, inv_limit FROM unified_shops WHERE shop_name = @shopName', {
        ['@shopName'] = shopName
    }, function(result)
        if result[1] then
            local shopId = result[1].shop_id
            local invLimit = result[1].inv_limit

            MySQL.Async.fetchScalar('SELECT SUM(item_quantity) FROM unified_items WHERE shop_id = @shopId', {
                ['@shopId'] = shopId
            }, function(currentInventory)
                currentInventory = currentInventory or 0
                if (currentInventory + inputQuantity) > invLimit then
                    TriggerClientEvent('playerstore:inventoryLimitExceeded', src)
                else
                    AddItemToStore(shopId, item.label, item.name, inputQuantity, inputBuyPrice, inputSellPrice, inputCategory, inputLevelRequired, item.is_weapon or 0, item.currency_type or 'cash', src)
                end
            end)
        else
            VORPcore.NotifyObjective(src, 'Store not found', 4000)
        end
    end)
end)

function AddItemToStore(shopId, itemLabel, itemName, inputQuantity, inputBuyPrice, inputSellPrice, inputCategory, inputLevelRequired, isWeapon, currencyType, src, buyOrSell)
    exports.vorp_inventory:getItem(src, itemName, function(playerItem)
        if playerItem and playerItem.count >= inputQuantity then
            MySQL.Async.fetchAll('SELECT buy_quantity, sell_quantity FROM unified_items WHERE shop_id = @shopId AND item_name = @itemName', {
                ['@shopId'] = shopId,
                ['@itemName'] = itemName
            }, function(existingItems)
                if existingItems[1] then
                    local newBuyQuantity = (existingItems[1].buy_quantity or 0)
                    local newSellQuantity = (existingItems[1].sell_quantity or 0)
                    
                    if buyOrSell == 'buy' then
                        newBuyQuantity = newBuyQuantity + inputQuantity
                    else
                        newSellQuantity = newSellQuantity + inputQuantity
                    end

                    local updateQuery = 'UPDATE unified_items SET buy_quantity = @newBuyQuantity, sell_quantity = @newSellQuantity WHERE shop_id = @shopId AND item_name = @itemName'
                    
                    MySQL.Async.execute(updateQuery, {
                        ['@newBuyQuantity'] = newBuyQuantity,
                        ['@newSellQuantity'] = newSellQuantity,
                        ['@shopId'] = shopId,
                        ['@itemName'] = itemName
                    }, function(rowsChanged)
                        if rowsChanged > 0 then
                            exports.vorp_inventory:subItem(src, itemName, inputQuantity, {}, function(success)
                                if success then
                                    TriggerClientEvent('vorp:TipBottom', src, "Item added successfully", 4000)
                                else
                                    TriggerClientEvent('vorp:TipBottom', src, "Failed to remove item from your inventory", 4000)
                                end
                            end)
                        else
                            TriggerClientEvent('vorp:TipBottom', src, "Failed to update item quantity in the database", 4000)
                        end
                    end)
                else
                    local buyQuantity = (buyOrSell == 'buy' and inputQuantity or 0)
                    local sellQuantity = (buyOrSell == 'sell' and inputQuantity or 0)

                    MySQL.Async.execute('INSERT INTO unified_items (shop_id, item_label, item_name, buy_price, sell_price, category, level_required, is_weapon, buy_quantity, sell_quantity, currency_type) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
                        shopId, itemLabel, itemName, inputBuyPrice, inputSellPrice, inputCategory, inputLevelRequired, isWeapon, buyQuantity, sellQuantity, currencyType
                    }, function(rowsChanged)
                        if rowsChanged > 0 then
                            exports.vorp_inventory:subItem(src, itemName, inputQuantity, {}, function(success)
                                if success then
                                    TriggerClientEvent('vorp:TipBottom', src, "Item added successfully", 4000)
                                else
                                    TriggerClientEvent('vorp:TipBottom', src, "Failed to remove item from your inventory", 4000)
                                end
                            end)
                        else
                            TriggerClientEvent('vorp:TipBottom', src, "Failed to add item to the database", 4000)
                        end
                    end)
                end
            end)
        else
            TriggerClientEvent('vorp:TipBottom', src, "You don't have enough of this item", 4000)
        end
    end)
end

RegisterNetEvent('playerstore:fetchStoreInfo')
AddEventHandler('playerstore:fetchStoreInfo', function(shopName)
    local src = source
    local user = VORPcore.getUser(src)
    local character = user.getUsedCharacter
    MySQL.Async.fetchAll('SELECT inv_limit, ledger, owner_id FROM unified_shops WHERE shop_name = @shopName', {
        ['@shopName'] = shopName
    }, function(results)
        if results and #results > 0 then
            local storeInfo = results[1]
            local isOwner = storeInfo.owner_id == character.charIdentifier
            devPrint("Store info fetched: " .. json.encode(storeInfo))
            devPrint("Is player owner: " .. tostring(isOwner))
            TriggerClientEvent('playerstore:receiveStoreInfo', src, shopName, storeInfo.inv_limit, storeInfo.ledger, isOwner)
        else
            TriggerClientEvent('vorp:TipBottom', src, 'Shop not found', 4000)
        end
    end)
end)

RegisterServerEvent('playerstore:removeItem')
AddEventHandler('playerstore:removeItem', function(shopId, itemName)
    local src = source
    local user = VORPcore.getUser(src)
    local character = user.getUsedCharacter
    local ownerId = character.charIdentifier

    removeItemFromShop(shopId, itemName, ownerId, function(success)
        if success then
            VORPcore.NotifyTip(src, "Item removed successfully", 4000)
            TriggerClientEvent('playerstore:fetchPlayerInventory', src, shopId)
        else
            VORPcore.NotifyTip(src, "Failed to remove item. You may not be the owner of the shop.", 4000)
        end
    end)
end)

function getPlayerStoreId(shopName, ownerId)
    return MySQL.Sync.fetchScalar('SELECT shop_id FROM unified_shops WHERE shop_name = @shopName AND owner_id = @ownerId', {
        ['@shopName'] = shopName,
        ['@ownerId'] = ownerId
    })
end

function getNPCStoreId(shopName)
    return MySQL.Sync.fetchScalar('SELECT shop_id FROM unified_shops WHERE shop_name = @shopName AND is_npc_shop = 1', {
        ['@shopName'] = shopName
    })
end

RegisterNetEvent('npcstore:addItem')
AddEventHandler('npcstore:addItem', function(shopName, itemLabel, itemName, quantity, buyPrice, sellPrice, category, levelRequired)
    local src = source
    MySQL.Async.fetchScalar('SELECT shop_id FROM unified_shops WHERE shop_name = ?', { shopName }, function(shop_id)
        if shop_id then
            local itemDescription = "No description"  -- Default description, update as needed
            MySQL.Async.fetchScalar('SELECT item_id FROM unified_items WHERE shop_id = ? AND item_name = ?', { shop_id, itemName }, function(existingItemId)
                if existingItemId then
                    -- Update quantity of existing item
                    MySQL.Async.execute('UPDATE unified_items SET buy_quantity = buy_quantity + ?, sell_quantity = sell_quantity + ? WHERE item_id = ?', { quantity, quantity, existingItemId }, function(rowsChanged)
                        if rowsChanged > 0 then
                            TriggerClientEvent('vorp:TipBottom', src, "Item quantity updated successfully", 4000)
                        else
                            TriggerClientEvent('vorp:TipBottom', src, "Failed to update item quantity in database", 4000)
                        end
                    end)
                else
                    -- Insert new item
                    MySQL.Async.execute('INSERT INTO unified_items (shop_id, item_label, item_name, currency_type, buy_price, sell_price, category, level_required, is_weapon, buy_quantity, sell_quantity) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    { shop_id, itemLabel, itemName, 'cash', buyPrice, sellPrice, category, levelRequired, 0, quantity, quantity }, function(rowsChanged)
                        if rowsChanged > 0 then
                            TriggerClientEvent('vorp:TipBottom', src, "Item added successfully", 4000)
                        else
                            TriggerClientEvent('vorp:TipBottom', src, "Failed to add item to NPC shop database", 4000)
                        end
                    end)
                end
            end)
        else
            TriggerClientEvent('vorp:TipBottom', src, "NPC Shop not found", 4000)
        end
    end)
end)

function removeItemFromShop(shopName, itemName, quantity, metadata, src, callback)
    local inventoryId = "shop_inventory_" .. shopName
    devPrint("Attempting to remove item from shop: " .. shopName .. ", Item: " .. itemName .. ", Quantity: " .. quantity)
    exports.vorp_inventory:subItem(inventoryId, itemName, quantity, metadata, function(success)
        callback(success, src)
    end)
end

RegisterNetEvent('playerstore:fetchShopItems')
AddEventHandler('playerstore:fetchShopItems', function(shopName)
    local src = source
    MySQL.Async.fetchAll('SELECT * FROM unified_items WHERE shop_id = (SELECT shop_id FROM unified_shops WHERE shop_name = @shopName)', {
        ['@shopName'] = shopName
    }, function(items)
        if items then
            TriggerClientEvent('playerstore:receiveShopItems', src, items, shopName)
        else
            TriggerClientEvent('vorp:TipBottom', src, "No items found in the shop", 4000)
        end
    end)
end)

RegisterNetEvent('playerstore:removeShopItem')
AddEventHandler('playerstore:removeShopItem', function(shopName, itemName, quantity, isBuy)
    local src = source
    MySQL.Async.fetchScalar('SELECT shop_id FROM unified_shops WHERE shop_name = @shopName', { ['@shopName'] = shopName }, function(shop_id)
        if shop_id then
            local quantityColumn = isBuy and 'buy_quantity' or 'sell_quantity'
            MySQL.Async.fetchScalar('SELECT ' .. quantityColumn .. ' FROM unified_items WHERE shop_id = @shopId AND item_name = @itemName', {
                ['@shopId'] = shop_id,
                ['@itemName'] = itemName
            }, function(itemQuantity)
                if itemQuantity and itemQuantity >= quantity then
                    MySQL.Async.execute('UPDATE unified_items SET ' .. quantityColumn .. ' = ' .. quantityColumn .. ' - @quantity WHERE shop_id = @shopId AND item_name = @itemName', {
                        ['@quantity'] = quantity,
                        ['@shopId'] = shop_id,
                        ['@itemName'] = itemName
                    }, function(rowsChanged)
                        if rowsChanged > 0 then
                            exports.vorp_inventory:addItem(src, itemName, quantity)
                            TriggerClientEvent('vorp:TipBottom', src, "Item removed successfully", 4000)
                        else
                            TriggerClientEvent('vorp:TipBottom', src, "Failed to update item quantity in the shop", 4000)
                        end
                    end)
                else
                    TriggerClientEvent('vorp:TipBottom', src, "Not enough items in the shop", 4000)
                end
            end)
        else
            TriggerClientEvent('vorp:TipBottom', src, "Shop not found", 4000)
        end
    end)
end)

RegisterNetEvent('playerstore:fetchPlayers')
AddEventHandler('playerstore:fetchPlayers', function()
    local src = source
    local players = {}
    
    -- Retrieve player list (example code, adjust to your actual player retrieval logic)
    for _, playerId in ipairs(GetPlayers()) do
        local playerName = GetPlayerName(playerId)
        table.insert(players, { id = playerId, name = playerName })
    end

    -- Send the players back to the client
    TriggerClientEvent('playerstore:receivePlayers', src, players)
end)

function manageStores(source, isAdmin)
    if isAdmin then
        devPrint("Admin " .. source .. " is managing shops.")
        local players = GetPlayers()
        local playerList = {}
        for _, playerId in ipairs(players) do
            local player = VORPcore.getUser(playerId)
            local character = player.getUsedCharacter
            table.insert(playerList, { id = playerId, name = character.firstname .. ' ' .. character.lastname })
        end
        MySQL.query('SELECT * FROM unified_shops', {}, function(shops)
            TriggerClientEvent('playerstore:openManageStoresMenu', source, shops, playerList)
        end)
    else
        VORPcore.NotifyObjective(source, 'You do not have permission to use this command!', 3000)
    end
end

RegisterCommand('managestores', function(source, args, rawCommand)
    local User = VORPcore.getUser(source)
    manageStores(source, User.getGroup == 'admin')
end, false)

function handleStoreCreation(type, shopData, callback)
    MySQL.insert('INSERT INTO unified_shops (shop_name, prompt_name, blip_name, blip_sprite, blip_color_open, blip_color_closed, blip_color_job, is_npc_shop, npc_model, pos_x, pos_y, pos_z, pos_heading, owner_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', 
    shopData, function(result)
        callback(result)
    end)
end

RegisterServerEvent('playerstore:create')
AddEventHandler('playerstore:create', function(storeDetails)
    local src = source
    local ownerId = storeDetails.ownerId
    devPrint("Owner ID received: " .. tostring(ownerId))
    if ownerId then
        local User = VORPcore.getUser(ownerId)
        local Character = User.getUsedCharacter
        if Character and Character.charIdentifier then
            local charidentifier = Character.charIdentifier
            devPrint("Character ID: " .. tostring(charidentifier))
            local shopLocation = storeDetails.storeType
            local pos_x, pos_y, pos_z, storeHeading = storeDetails.pos_x, storeDetails.pos_y, storeDetails.pos_z, storeDetails.storeHeading
            if storeDetails.npcShopId then
                MySQL.Async.fetchAll('SELECT pos_x, pos_y, pos_z, pos_heading FROM unified_shops WHERE shop_id = @shopId AND is_npc_shop = 1', { ['@shopId'] = storeDetails.npcShopId }, function(result)
                    if result and #result > 0 then
                        pos_x, pos_y, pos_z, storeHeading = result[1].pos_x, result[1].pos_y, result[1].pos_z, result[1].pos_heading
                    end
                    MySQL.insert('INSERT INTO unified_shops (owner_id, shop_name, pos_x, pos_y, pos_z, pos_heading, shop_type, blip_hash, ledger, inv_limit, is_npc_shop, shop_location) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    { charidentifier, storeDetails.shopName, pos_x, pos_y, pos_z, storeHeading, storeDetails.storeType, storeDetails.blipHash, storeDetails.ledger, storeDetails.invLimit, 0, shopLocation }, function(result)
                        if result then
                            devPrint("Shop created successfully.")
                            VORPcore.NotifyObjective(src, 'Shop created successfully!', 3000)
                            TriggerEvent('playerstore:fetchShops')
                        else
                            devPrint("Failed to create shop.")
                            VORPcore.NotifyObjective(src, 'Failed to create shop!', 3000)
                        end
                    end)
                end)
            else
                MySQL.insert('INSERT INTO unified_shops (owner_id, shop_name, pos_x, pos_y, pos_z, pos_heading, shop_type, blip_hash, ledger, inv_limit, is_npc_shop, shop_location) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                { charidentifier, storeDetails.shopName, pos_x, pos_y, pos_z, storeHeading, storeDetails.storeType, storeDetails.blipHash, storeDetails.ledger, storeDetails.invLimit, 0, shopLocation }, function(result)
                    if result then
                        devPrint("Shop created successfully.")
                        VORPcore.NotifyObjective(src, 'Shop created successfully!', 3000)
                        TriggerEvent('playerstore:fetchShops')
                    else
                        devPrint("Failed to create shop.")
                        VORPcore.NotifyObjective(src, 'Failed to create shop!', 3000)
                    end
                end)
            end
        else
            devPrint("Character not found or missing charidentifier for owner ID: " .. tostring(ownerId))
            VORPcore.NotifyObjective(src, 'Character not found or missing charidentifier for owner ID', 3000)
        end
    else
        devPrint("Invalid owner ID received.")
        VORPcore.NotifyObjective(src, 'Invalid owner ID received', 3000)
    end
end)

RegisterServerEvent('playerstore:fetchStores')
AddEventHandler('playerstore:fetchStores', function()
    local src = source
    MySQL.Async.fetchAll('SELECT * FROM unified_shops', {}, function(result)
        if result then
            TriggerClientEvent('playerstore:receiveStores', src, result)
            local prettyJSON = json.encode(result, { indent = true })
            devPrint("['DEBUG'] - Fetched store data: " .. prettyJSON)  -- Debug print
        else
            devPrint("Error: No player stores found in database.")
            TriggerClientEvent('playerstore:receiveStores', src, {})
        end
    end)
end)

function updateStore(shopId, storeData, src, callback)
    MySQL.update('UPDATE unified_shops SET shop_name = ?, shop_location = ?, shop_type = ?, blip_hash = ?, ledger = ?, inv_limit = ? WHERE shop_id = ?',
    storeData, function(result)
        callback(result, src)
    end)
end

RegisterServerEvent('playerstore:update', function(shopId, shopName, storeType, storeLocation, blipHash, ledger, invLimit)
    updateStore(shopId, { shopName, storeLocation, storeType, blipHash, ledger, invLimit, shopId }, source, function(result, src)
        if result then
            devPrint("Shop updated successfully.")
            VORPcore.NotifyObjective(src, 'Shop updated successfully!', 3000)
            TriggerEvent('playerstore:fetchShops')
        else
            devPrint("Failed to update shop.")
            VORPcore.NotifyObjective(src, 'Failed to update shop!', 3000)
        end
    end)
end)

RegisterServerEvent('shop:deleteNPCStore')
AddEventHandler('shop:deleteNPCStore', function(shopId)
    local src = source
    MySQL.Async.execute('DELETE FROM unified_items WHERE shop_id = @shopId', { ['@shopId'] = shopId }, function(affectedRows)
        if affectedRows > 0 then
            MySQL.Async.execute('DELETE FROM unified_shops WHERE shop_id = @shopId AND is_npc_shop = 1', { ['@shopId'] = shopId }, function(affectedRows)
                if affectedRows > 0 then
                    TriggerClientEvent('shop:clientCleanup', -1)  -- Notify all clients to clean up blips and NPCs
                    TriggerClientEvent('vorp:TipBottom', src, "NPC Shop deleted successfully", 4000)
                else
                    TriggerClientEvent('vorp:TipBottom', src, "Failed to delete NPC Shop", 4000)
                end
                TriggerEvent('shop:refreshStoreData')
            end)
        else
            TriggerClientEvent('vorp:TipBottom', src, "Failed to delete items associated with the NPC Shop", 4000)
        end
    end)
end)

RegisterServerEvent('playerstore:delete')
AddEventHandler('playerstore:delete', function(shopId)
    local src = source
    MySQL.Async.execute('DELETE FROM unified_items WHERE shop_id = @shopId', { ['@shopId'] = shopId }, function(affectedRows)
        if affectedRows > 0 then
            MySQL.Async.execute('DELETE FROM unified_shops WHERE shop_id = @shopId AND owner_id IS NOT NULL', { ['@shopId'] = shopId }, function(affectedRows)
                if affectedRows > 0 then
                    TriggerClientEvent('shop:clientCleanup', -1)  -- Notify all clients to clean up blips and NPCs
                    TriggerClientEvent('vorp:TipBottom', src, "Player Shop deleted successfully", 4000)
                else
                    TriggerClientEvent('vorp:TipBottom', src, "Failed to delete Player Shop", 4000)
                end
                TriggerEvent('shop:refreshStoreData')
            end)
        else
            TriggerClientEvent('vorp:TipBottom', src, "Failed to delete items associated with the Player Shop", 4000)
        end
    end)
end)

function handleStoreTransaction(src, shopName, itemName, quantity, totalMoney, isWeapon, buyOrSell)
    local Character = VORPcore.getUser(src).getUsedCharacter
    local getDetails = isWeapon and getWeaponDetails or getItemDetails
    getDetails(itemName, function(itemDetails)
        if itemDetails then
            local level = getLevelFromXP(Character.xp)
            if level >= (itemDetails.level_required or 0) then
                local query = [[
                    SELECT buy_quantity, sell_quantity, shop_id, 'npc' as shop_type FROM unified_items WHERE shop_id = (SELECT shop_id FROM unified_shops WHERE shop_name = @shopName AND is_npc_shop = 1) AND item_name = @itemName
                    UNION
                    SELECT buy_quantity, sell_quantity, shop_id, 'player' as shop_type FROM unified_items WHERE shop_id = (SELECT shop_id FROM unified_shops WHERE shop_name = @shopName AND owner_id IS NOT NULL) AND item_name = @itemName
                ]]
                
                MySQL.Async.fetchAll(query, { ['@shopName'] = shopName, ['@itemName'] = itemName }, function(results)
                    if results and #results > 0 then
                        local buyQuantity = results[1].buy_quantity or 0
                        local sellQuantity = results[1].sell_quantity or 0
                        local shopId = results[1].shop_id
                        local shopType = results[1].shop_type

                        if buyOrSell == 'buy' then
                            if buyQuantity >= quantity then
                                if Character.money >= totalMoney then
                                    exports.vorp_inventory:canCarryItem(src, itemName, quantity, function(canCarry)
                                        if canCarry then
                                            Character.removeCurrency(0, totalMoney)
                                            exports.vorp_inventory:addItem(src, itemName, quantity)
                                            
                                            local updateQuery = 'UPDATE unified_items SET buy_quantity = buy_quantity - ? WHERE shop_id = ? AND item_name = ?'
                                            MySQL.Async.execute(updateQuery, { quantity, shopId, itemName })
                                            MySQL.Async.execute('UPDATE unified_shops SET ledger = ledger + ? WHERE shop_id = ?', { totalMoney, shopId })
                                            VORPcore.NotifyObjective(src, "You bought " .. quantity .. "x " .. itemDetails.item_label .. " for " .. totalMoney .. "$", 4000)
                                            discord:sendMessage("Name: " .. Character.firstname .. " " .. Character.lastname .. "\nBought: " .. itemDetails.item_label .. " " .. itemName .. "\nQuantity: " .. quantity .. "\nMoney: $" .. totalMoney .. "\nShop: " .. shopName)
                                        else
                                            VORPcore.NotifyObjective(src, "Cannot carry that much", 4000)
                                        end
                                    end)
                                else
                                    VORPcore.NotifyObjective(src, "You don't have enough money", 4000)
                                end
                            else
                                VORPcore.NotifyObjective(src, "Not enough stock available", 4000)
                            end
                        elseif buyOrSell == 'sell' then
                            if sellQuantity >= quantity then
                                exports.vorp_inventory:subItem(src, itemName, quantity, {}, function(success)
                                    if success then
                                        if shopType == 'player' then
                                            MySQL.Async.fetchScalar('SELECT ledger FROM unified_shops WHERE shop_id = ?', { shopId }, function(ledger)
                                                if ledger and ledger >= totalMoney then
                                                    Character.addCurrency(0, totalMoney)
                                                    local updateQuery = 'UPDATE unified_items SET sell_quantity = sell_quantity - ? WHERE shop_id = ? AND item_name = ?'
                                                    MySQL.Async.execute(updateQuery, { quantity, shopId, itemName })
                                                    MySQL.Async.execute('UPDATE unified_shops SET ledger = ledger - ? WHERE shop_id = ?', { totalMoney, shopId })
                                                    VORPcore.NotifyObjective(src, "You sold " .. quantity .. "x " .. itemDetails.item_label .. " for $" .. totalMoney, 4000)
                                                    discord:sendMessage("Name: " .. Character.firstname .. " " .. Character.lastname .. "\nSold: " .. itemDetails.item_label .. " " .. itemName .. "\nQuantity: " .. quantity .. "\nEarned: $" .. totalMoney .. "\nShop: " .. shopName)
                                                else
                                                    VORPcore.NotifyObjective(src, "The store does not have enough money in the ledger", 4000)
                                                end
                                            end)
                                        else
                                            Character.addCurrency(0, totalMoney)
                                            local updateQuery = 'UPDATE unified_items SET sell_quantity = sell_quantity - ? WHERE shop_id = ? AND item_name = ?'
                                            MySQL.Async.execute(updateQuery, { quantity, shopId, itemName })
                                            VORPcore.NotifyObjective(src, "You sold " .. quantity .. "x " .. itemDetails.item_label .. " for $" .. totalMoney, 4000)
                                            discord:sendMessage("Name: " .. Character.firstname .. " " .. Character.lastname .. "\nSold: " .. itemDetails.item_label .. " " .. itemName .. "\nQuantity: " .. quantity .. "\nEarned: $" .. totalMoney .. "\nShop: " .. shopName)
                                        end
                                    else
                                        VORPcore.NotifyObjective(src, "Failed to remove item from your inventory", 4000)
                                    end
                                end)
                            else
                                VORPcore.NotifyObjective(src, "Not enough stock available to sell", 4000)
                            end
                        end
                    else
                        VORPcore.NotifyObjective(src, "Item not found in the store", 4000)
                    end
                end)
            else
                VORPcore.NotifyObjective(src, "You need to be level " .. itemDetails.level_required .. " to " .. buyOrSell .. " this item.", 4000)
            end
        else
            VORPcore.NotifyObjective(src, "Item not found", 4000)
        end
    end)
end

RegisterServerEvent('isee-shops:purchaseItem')
AddEventHandler('isee-shops:purchaseItem', function(shopName, itemName, quantity, totalMoney, isWeapon)
    handleStoreTransaction(source, shopName, itemName, quantity, totalMoney, isWeapon, 'buy')
end)

RegisterServerEvent('isee-shops:sellItem')
AddEventHandler('isee-shops:sellItem', function(shopName, itemName, quantity, totalMoney, isWeapon)
    handleStoreTransaction(source, shopName, itemName, quantity, totalMoney, isWeapon, 'sell')
end)

function fetchShopInventory(src, tableName, shop_id, shopName)
    MySQL.query('SELECT * FROM ' .. tableName .. ' WHERE shop_id = @shopId', { ['@shopId'] = shop_id }, function(result)
        if result then
            for _, item in ipairs(result) do
                item.quantity = item.item_stock or 0
                item.price = item.item_price or 0
            end
            TriggerClientEvent('playerstore:receiveShopInventory', src, shopName, result)
        else
            devPrint("No inventory found for shop:", shopName, "with shop ID:", shop_id)
            TriggerClientEvent('playerstore:receiveShopInventory', src, shopName, {})
        end
    end)
end

RegisterServerEvent('playerstore:fetchShopInventory', function(shopName)
    local src = source
    local Character = VORPcore.getUser(src).getUsedCharacter
    if Character then
        local shop_id = getPlayerStoreId(shopName, Character.charIdentifier)
        if shop_id then
            fetchShopInventory(src, 'unified_items', shop_id, shopName)
        else
            devPrint("Shop ID not found for shop name:", shopName, "with owner ID:", Character.charIdentifier)
            TriggerClientEvent('playerstore:receiveShopInventory', src, shopName, {})
        end
    else
        devPrint("Character not found for source:", src)
    end
end)

RegisterServerEvent('isee-shops:requestPlayerXP', function()
    local src = source
    local xp = getPlayerXP(src)
    devPrint("Sending player XP: " .. xp)
    TriggerClientEvent('isee-shops:receivePlayerXP', src, xp)
end)

RegisterServerEvent('isee-shops:requestPlayerLevel')
AddEventHandler('isee-shops:requestPlayerLevel', function(callbackId)
    local src = source
    local Character = VORPcore.getUser(src).getUsedCharacter
    local level = getLevelFromXP(Character.xp)
    devPrint("Sending player level: " .. level)
    TriggerClientEvent('isee-shops:receivePlayerLevel', src, level, callbackId)
end)

function GenerateWeaponSerial()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local serial = "HOINARII-"
    for i = 1, 10 do
        local rand = math.random(1, #chars)
        serial = serial .. chars:sub(rand, rand)
    end
    return serial
end

-- Server-side event handler for creating a new NPC shop
RegisterNetEvent('shop:create')
AddEventHandler('shop:create', function(storeType, shopName, blipName, blipSprite, blipColorOpen, blipColorClosed, blipColorJob, isNpcShop, npcModel, posX, posY, posZ, posHeading, shopLocation)
    print("Received create shop request: ", storeType, shopName, blipName, blipSprite, blipColorOpen, blipColorClosed, blipColorJob, isNpcShop, npcModel, posX, posY, posZ, posHeading, shopLocation)
    
    -- Assuming 'unified_shops' is the name of your table and it has the necessary columns
    exports.oxmysql:execute('INSERT INTO unified_shops (shop_type, shop_name, blip_name, blip_sprite, blip_color_open, blip_color_closed, blip_color_job, is_npc_shop, npc_model, pos_x, pos_y, pos_z, pos_heading, shop_location) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', 
    {storeType, shopName, blipName, blipSprite, blipColorOpen, blipColorClosed, blipColorJob, isNpcShop, npcModel, posX, posY, posZ, posHeading, shopLocation}, function(affectedRows)
        if affectedRows > 0 then
            print("Shop created successfully!")
            TriggerClientEvent('vorp:showNotification', source, "NPC Store created successfully!")
        else
            print("Failed to create shop")
            TriggerClientEvent('vorp:showNotification', source, "Failed to create NPC Store")
        end
    end)
end)

function fetchStoreData(query, params, clientEvent)
    local src = source
    MySQL.Async.fetchAll(query, params, function(result)
        if result then
            for _, store in ipairs(result) do
                local prettyJSON = json.encode(store, { indent = true })
                devPrint("['DEBUG'] - Fetched store data: " .. prettyJSON)  -- Debug print
            end
            TriggerClientEvent(clientEvent, src, result)
        else
            devPrint("No stores found in database")
        end
    end)
end

RegisterServerEvent('playerstore:fetchPlayerShops')
AddEventHandler('playerstore:fetchPlayerShops', function()
    local query = 'SELECT * FROM unified_shops WHERE owner_id IS NOT NULL'
    fetchStoreData(query, {}, 'playerstore:receivePlayerShops')
end)

RegisterServerEvent('shop:fetchNPCStoreCoords')
AddEventHandler('shop:fetchNPCStoreCoords', function(npcShopId, callback)
    local query = 'SELECT * FROM unified_shops WHERE shop_id = @shopId AND is_npc_shop = 1'
    fetchStoreData(query, { ['@shopId'] = npcShopId }, function(result)
        callback(result[1] or nil)
    end)
end)

RegisterServerEvent('shop:fetchNPCShops')
AddEventHandler('shop:fetchNPCShops', function()
    local query = 'SELECT * FROM unified_shops WHERE is_npc_shop = 1'
    fetchStoreData(query, {}, 'shop:receiveNPCShops')
end)

-- Fetch categories for buying
RegisterServerEvent('shop:fetchCategories')
AddEventHandler('shop:fetchCategories', function(shopName)
    local src = source
    MySQL.Async.fetchAll([[
        SELECT DISTINCT category FROM unified_items WHERE shop_id = (SELECT shop_id FROM unified_shops WHERE shop_name = @shopName)
    ]], { ['@shopName'] = shopName }, function(categories)
        TriggerClientEvent('shop:receiveCategories', src, shopName, categories or {})
    end)
end)

-- Fetch categories for selling
RegisterServerEvent('shop:fetchSellCategories')
AddEventHandler('shop:fetchSellCategories', function(shopName)
    local src = source
    MySQL.Async.fetchAll([[
        SELECT DISTINCT category FROM unified_items WHERE shop_id = (SELECT shop_id FROM unified_shops WHERE shop_name = @shopName)
    ]], { ['@shopName'] = shopName }, function(categories)
        TriggerClientEvent('shop:receiveSellCategories', src, shopName, categories or {})
    end)
end)

function fetchItemsForShop(shopName, category, event)
    local src = source
    local itemsQuery = 'SELECT *, 0 AS is_weapon FROM unified_items WHERE shop_id = (SELECT shop_id FROM unified_shops WHERE shop_name = @shopName) AND category = @category'

    devPrint("Fetching items for shop:", shopName, "category:", category)

    MySQL.Async.fetchAll(itemsQuery, { ['@shopName'] = shopName, ['@category'] = category }, function(items)
        devPrint("Fetched items:", json.encode(items))

        TriggerClientEvent(event, src, shopName, category, items)
    end)
end

RegisterServerEvent('shop:fetchItems', function(shopName, category)
    fetchItemsForShop(shopName, category, 'shop:receiveItems')
end)

RegisterServerEvent('shop:fetchSellItems', function(shopName, category)
    fetchItemsForShop(shopName, category, 'shop:receiveSellItems')
end)

RegisterServerEvent("store:AdminCheck")
AddEventHandler("store:AdminCheck", function(shopName)
    local _source = source
    local admin = false
    local user = VORPcore.getUser(_source)
    
    if not user then
        print("Error: User not found for source: " .. tostring(_source))
        TriggerClientEvent("store:AdminClientCatch", _source, false, shopName)
        return
    end
    
    local character = user.getUsedCharacter

    if not character then
        print("Error: Character not found for user: " .. tostring(user))
        TriggerClientEvent("store:AdminClientCatch", _source, false, shopName)
        return
    end

    if character.group == Config.adminGroup then
        admin = true
        TriggerClientEvent("store:AdminClientCatch", _source, true, shopName)
        return
    end

    if character.job == Config.AllowedJobs then
        admin = true
        TriggerClientEvent('store:AdminClientCatch', _source, true, shopName)
        return
    end

    TriggerClientEvent("store:AdminClientCatch", _source, false, shopName)
end)

RegisterNetEvent('store:CheckOwnership')
AddEventHandler('store:CheckOwnership', function(storeName)
    local src = source
    if not storeName then
        devPrint("Error: storeName is nil")
        TriggerClientEvent('store:ownershipConfirmed', src, false, storeName)
        return
    end

    local user = VORPcore.getUser(src)
    local character = user.getUsedCharacter
    local characterId = character.charIdentifier

    devPrint("Checking ownership for store: " .. storeName .. ", Character ID: " .. tostring(characterId))

    MySQL.Async.fetchAll('SELECT owner_id FROM unified_shops WHERE shop_name = @shopName', {
        ['@shopName'] = storeName
    }, function(results)
        if results and #results > 0 then
            local ownerId = results[1].owner_id
            devPrint("Store owner ID: " .. tostring(ownerId) .. ", Character ID: " .. tostring(characterId))

            if ownerId == characterId then
                devPrint("Player is the owner of the store: " .. storeName)
                TriggerClientEvent('store:ownershipConfirmed', src, true, storeName)
            else
                devPrint("Player is not the owner of the store: " .. storeName)
                TriggerClientEvent('store:ownershipConfirmed', src, false, storeName)
            end
        else
            devPrint("Store not found: " .. storeName)
            TriggerClientEvent('store:ownershipConfirmed', src, false, storeName)
        end
    end)
end)

RegisterNetEvent('playerstore:addBuyItem')
AddEventHandler('playerstore:addBuyItem', function(storeName, itemLabel, itemName, quantity, buyPrice, category, levelRequired)
    local src = source
    local currencyType = "cash"
    local sellPrice = 0
    local isWeapon = 0

    devPrint("Received request to add buy item to player store: " .. storeName)
    devPrint("Item details - Label: " .. itemLabel .. ", Name: " .. tostring(itemName) .. ", Quantity: " .. tostring(quantity) .. ", Buy Price: " .. tostring(buyPrice) .. ", Category: " .. category .. ", Level Required: " .. tostring(levelRequired))

    if not itemName or itemName == "" then
        devPrint("Error: itemName is nil or empty")
        TriggerClientEvent('vorp:TipBottom', src, "Invalid item name", 4000)
        return
    end

    MySQL.Async.fetchScalar('SELECT shop_id FROM unified_shops WHERE shop_name = @shopName AND owner_id IS NOT NULL', { ['@shopName'] = storeName }, function(shop_id)
        if shop_id then
            devPrint("Shop ID for store " .. storeName .. ": " .. shop_id)

            exports.vorp_inventory:getItem(src, itemName, function(playerItem)
                if playerItem and playerItem.count >= quantity then
                    devPrint("Player has enough of item: " .. itemName)

                    local itemDescription = playerItem.description or "No description"
                    isWeapon = playerItem.is_weapon or 0
                    MySQL.Async.fetchScalar('SELECT item_id FROM unified_items WHERE shop_id = ? AND item_name = ?', { shop_id, itemName }, function(existingItemId)
                        if existingItemId then
                            -- Update quantity of existing item
                            devPrint("Existing item found in shop. Updating quantity.")
                            MySQL.Async.execute('UPDATE unified_items SET buy_quantity = buy_quantity + ? WHERE item_id = ?', { quantity, existingItemId }, function(rowsChanged)
                                if rowsChanged > 0 then
                                    exports.vorp_inventory:subItem(src, itemName, quantity, {}, function(success)
                                        if success then
                                            devPrint("Item quantity updated successfully in database and inventory.")
                                            TriggerClientEvent('vorp:TipBottom', src, "Item quantity updated successfully", 4000)
                                        else
                                            devPrint("Failed to remove item from player's inventory.")
                                            TriggerClientEvent('vorp:TipBottom', src, "Failed to remove item from your inventory", 4000)
                                        end
                                    end)
                                else
                                    devPrint("Failed to update item quantity in database.")
                                    TriggerClientEvent('vorp:TipBottom', src, "Failed to update item quantity in database", 4000)
                                end
                            end)
                        else
                            -- Insert new item
                            devPrint("Item not found in shop. Adding new item.")
                            MySQL.Async.execute('INSERT INTO unified_items (shop_id, item_label, item_name, buy_price, sell_price, currency_type, category, level_required, is_weapon, buy_quantity, sell_quantity) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                            { shop_id, itemLabel, itemName, buyPrice, sellPrice, currencyType, category, levelRequired, isWeapon, quantity, 0 }, function(rowsChanged)
                                if rowsChanged > 0 then
                                    exports.vorp_inventory:subItem(src, itemName, quantity, {}, function(success)
                                        if success then
                                            devPrint("New item added successfully to shop and removed from player's inventory.")
                                            TriggerClientEvent('vorp:TipBottom', src, "Item added successfully", 4000)
                                        else
                                            devPrint("Failed to remove item from player's inventory after adding to shop.")
                                            MySQL.Async.execute('DELETE FROM unified_items WHERE shop_id = ? AND item_name = ? LIMIT 1', { shop_id, itemName })
                                            TriggerClientEvent('vorp:TipBottom', src, "Failed to remove item from your inventory", 4000)
                                        end
                                    end)
                                else
                                    devPrint("Failed to add new item to player shop database.")
                                    TriggerClientEvent('vorp:TipBottom', src, "Failed to add item to player shop database", 4000)
                                end
                            end)
                        end
                    end)
                else
                    devPrint("Player does not have enough of item: " .. itemName)
                    TriggerClientEvent('vorp:TipBottom', src, "You don't have enough of this item", 4000)
                end
            end)
        else
            devPrint("Player shop not found: " .. storeName)
            TriggerClientEvent('vorp:TipBottom', src, "Player Shop not found", 4000)
        end
    end)
end)

RegisterNetEvent('playerstore:addSellItem')
AddEventHandler('playerstore:addSellItem', function(storeName, itemLabel, itemName, quantity, sellPrice, category, levelRequired)
    local src = source
    local currencyType = "cash"
    local buyPrice = 0
    local isWeapon = 0

    devPrint("Received request to add sell item to player store: " .. storeName)
    devPrint("Item details - Label: " .. itemLabel .. ", Name: " .. tostring(itemName) .. ", Quantity: " .. tostring(quantity) .. ", Sell Price: " .. tostring(sellPrice) .. ", Category: " .. category .. ", Level Required: " .. tostring(levelRequired))

    if not itemName or itemName == "" then
        devPrint("Error: itemName is nil or empty")
        TriggerClientEvent('vorp:TipBottom', src, "Invalid item name", 4000)
        return
    end

    MySQL.Async.fetchScalar('SELECT shop_id FROM unified_shops WHERE shop_name = @shopName AND owner_id IS NOT NULL', { ['@shopName'] = storeName }, function(shop_id)
        if shop_id then
            devPrint("Shop ID for store " .. storeName .. ": " .. shop_id)

            -- Fetch item details from the player's inventory
            exports.vorp_inventory:getItem(src, itemName, function(playerItem)
                if playerItem then
                    devPrint("Player has item: " .. itemName)
                    
                    local itemDescription = playerItem.description or "No description"
                    isWeapon = playerItem.is_weapon or 0
                    MySQL.Async.fetchScalar('SELECT item_id FROM unified_items WHERE shop_id = ? AND item_name = ?', { shop_id, itemName }, function(existingItemId)
                        if existingItemId then
                            -- Update quantity of existing item
                            devPrint("Existing item found in shop. Updating quantity.")
                            MySQL.Async.execute('UPDATE unified_items SET sell_quantity = sell_quantity + ?, sell_price = ?, category = ?, level_required = ? WHERE item_id = ?', { quantity, sellPrice, category, levelRequired, existingItemId }, function(rowsChanged)
                                if rowsChanged > 0 then
                                    devPrint("Item quantity updated successfully in database.")
                                    TriggerClientEvent('vorp:TipBottom', src, "Item quantity updated successfully", 4000)
                                else
                                    devPrint("Failed to update item quantity in database.")
                                    TriggerClientEvent('vorp:TipBottom', src, "Failed to update item quantity in database", 4000)
                                end
                            end)
                        else
                            -- Insert new item
                            devPrint("Item not found in shop. Adding new item.")
                            MySQL.Async.execute('INSERT INTO unified_items (shop_id, item_label, item_name, buy_price, sell_price, currency_type, category, level_required, is_weapon, buy_quantity, sell_quantity) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                            { shop_id, itemLabel, itemName, buyPrice, sellPrice, currencyType, category, levelRequired, isWeapon, 0, quantity }, function(rowsChanged)
                                if rowsChanged > 0 then
                                    devPrint("New item added successfully to shop.")
                                    TriggerClientEvent('vorp:TipBottom', src, "Item added successfully", 4000)
                                else
                                    devPrint("Failed to add new item to player shop database.")
                                    TriggerClientEvent('vorp:TipBottom', src, "Failed to add item to player shop database", 4000)
                                end
                            end)
                        end
                    end)
                else
                    devPrint("Player does not have the item: " .. itemName)
                    TriggerClientEvent('vorp:TipBottom', src, "Item not found in your inventory", 4000)
                end
            end)
        else
            devPrint("Player shop not found: " .. storeName)
            TriggerClientEvent('vorp:TipBottom', src, "Player Shop not found", 4000)
        end
    end)
end)

RegisterNetEvent('playerstore:fetchPlayersForOwnerSelection')
AddEventHandler('playerstore:fetchPlayersForOwnerSelection', function()
    local src = source
    local players = {}
    
    -- Retrieve player list (example code, adjust to your actual player retrieval logic)
    for _, playerId in ipairs(GetPlayers()) do
        local playerName = GetPlayerName(playerId)
        table.insert(players, { id = playerId, name = playerName })
    end

    -- Send the players back to the client
    TriggerClientEvent('playerstore:receivePlayersForOwnerSelection', src, players)
end)
