VORPcore = exports.vorp_core:GetCore()
local BccUtils = exports['bcc-utils'].initiate()
local FeatherMenu = exports['feather-menu'].initiate()

local CreatedBlip = {}
local CreatedNPC = {}
local playerStores = {}
local npcStores = {}
local globalNearbyShops = {}
local isPlayerNearStore = false  -- Flag to track player's proximity to stores
local PromptGroup = GetRandomIntInRange(0, 0xffffff)
local storesFetched = false
local AdminAllowed = nil
local OwnerAllowed = nil
local playerLevel = 0 -- Initialize player level with a default value
local currentAction = nil
local currentPlayers = {}
local ownedShops = {}

function devPrint(...)
    if Config.devMode then
        local message = "[DEBUG] "
        for i, v in ipairs({...}) do
            message = message .. tostring(v) .. " "
        end
        print(message)
    end
end

-- Register and configure the ISEEStoresMainMenu with FeatherMenu
ISEEStoresMainMenu = FeatherMenu:RegisterMenu('isee-shops:mainmenu', {
    top = '5%',
    left = '5%',
    ['720width'] = '500px',
    ['1080width'] = '600px',
    ['2kwidth'] = '700px',
    ['4kwidth'] = '900px',
    style = {},
    contentslot = {
      style = {
        ['height'] = '350px',
        ['min-height'] = '250px'
      }
    },
    draggable = true
  }, {
    opened = function()
        DisplayRadar(false)
    end,
    closed = function()
        DisplayRadar(true)
    end,
})

RegisterNetEvent('shop:receiveNPCShops')
AddEventHandler('shop:receiveNPCShops', function(shops)
    npcStores = shops
    CreateNPCBlips()
    if currentAction == "deleteNPCStores" then
        OpenDeleteNPCStoresMenu()
    end
end)

RegisterNetEvent('playerstore:receiveStores')
AddEventHandler('playerstore:receiveStores', function(stores)
    if stores then
        local prettyJSON = json.encode(stores, { indent = true })
        devPrint("['DEBUG'] - Fetched store data: " .. prettyJSON)  -- Debug print
        playerStores = stores
        devPrint("Assigned player stores to global variable.")  -- Additional Debug Print
        CreatePlayerBlips()
        storesFetched = true
        if currentAction == "deletePlayerStores" then
            OpenDeletePlayerStoresMenu()
        end
    else
        devPrint("Error: Received nil stores in playerstore:receiveStores")
    end
end)

RegisterNetEvent('store:AdminClientCatch')
AddEventHandler('store:AdminClientCatch', function(isAdmin)
    AdminAllowed = isAdmin
end)

RegisterNetEvent('store:OwnerClientCatch')
AddEventHandler('store:OwnerClientCatch', function(isOwner)
    OwnerAllowed = isOwner
end)

-- Function to check if the player is an admin
function IsPlayerAdmin()
    return AdminAllowed
end

function IsPlayerOwner(shopName)
    devPrint("Checking if player is owner of shop: " .. tostring(shopName))
    -- Check if the shop name is in the ownedShops table
    if ownedShops and ownedShops[shopName] then
        return true
    else
        return false
    end
end

CreateThread(function()
    StartPrompts()
    devPrint("Prompts initialized")
    TriggerServerEvent("store:AdminCheck")
    TriggerServerEvent('shop:fetchNPCShops')
    TriggerServerEvent('playerstore:fetchStores')

    while true do
        Wait(0)
        local playerCoords = GetEntityCoords(PlayerPedId())
        local nearbyShops = {}
        local addedShopIds = {}

        -- Check NPC stores
        for _, shop in ipairs(npcStores) do
            local dist = #(playerCoords - vector3(shop.pos_x, shop.pos_y, shop.pos_z))
            if dist < Config.ShopSDistance and shop.is_npc_shop then
                if not addedShopIds[shop.shop_id] then
                    --devPrint("Found NPC store nearby: " .. shop.shop_name)
                    table.insert(nearbyShops, {type = "npc", name = shop.shop_name, details = shop})
                    addedShopIds[shop.shop_id] = true
                end
            end
        end

        -- Check player stores
        if playerStores and storesFetched then
            for _, store in ipairs(playerStores) do
                if store.pos_x and store.pos_y and store.pos_z and not store.is_npc_shop then
                    local dist = #(playerCoords - vector3(store.pos_x, store.pos_y, store.pos_z))
                    if dist < 3.0 then
                        if not addedShopIds[store.shop_id] then
                            if store.shop_name then
                                --devPrint("Found Player store nearby: " .. store.shop_name)
                                table.insert(nearbyShops, {type = "player", name = store.shop_name, details = store})
                            else
                                --devPrint("Player near store with missing name")
                                table.insert(nearbyShops, {type = "player", name = "Unnamed Store", details = store})
                            end
                            addedShopIds[store.shop_id] = true
                        end
                    end
                end
            end
        end

        if #nearbyShops > 0 then
            if not isPlayerNearStore then
                isPlayerNearStore = true
            end
            globalNearbyShops = nearbyShops

            local promptText = _U('PromptName')
            for _, shop in ipairs(nearbyShops) do
                if shop.type == "player" then
                    promptText = shop.name
                    break
                elseif shop.type == "npc" then
                    promptText = shop.name
                end
            end

            PromptSetActiveGroupThisFrame(PromptGroup, CreateVarString(10, 'LITERAL_STRING', promptText))
            --devPrint("Displaying store prompt: " .. promptText)

            if PromptHasStandardModeCompleted(OpenStoreMenuPrompt) then
                --devPrint("Store prompt activated")

                local playerShops = {}
                local npcShops = {}
                for _, shop in ipairs(globalNearbyShops) do
                    if shop.type == "player" then
                        table.insert(playerShops, shop)
                    elseif shop.type == "npc" then
                        table.insert(npcShops, shop)
                    end
                end

                if #playerShops > 0 then
                    OpenStoreMenu(playerShops, "player")
                elseif #npcShops > 0 then
                    OpenStoreMenu(npcShops, "npc")
                end
            end
        else
            if isPlayerNearStore then
                isPlayerNearStore = false
            end
        end
    end
end)

function CreateNPCBlips()
    for _, shop in ipairs(npcStores) do
        local shopBlip = BccUtils.Blips:SetBlip(shop.shop_name, 1475879922, 1, shop.pos_x, shop.pos_y, shop.pos_z)
        CreatedBlip[#CreatedBlip + 1] = shopBlip
    end
end

function CreatePlayerBlips()
    for _, store in ipairs(playerStores) do
        local storeBlip = BccUtils.Blips:SetBlip(store.shop_name, 1475879922, 1, store.pos_x, store.pos_y, store.pos_z)
        CreatedBlip[#CreatedBlip + 1] = storeBlip
    end
end

function StartPrompts()
    OpenStoreMenuPrompt = PromptRegisterBegin()
    PromptSetControlAction(OpenStoreMenuPrompt, Config.keys.access)
    PromptSetText(OpenStoreMenuPrompt, CreateVarString(10, 'LITERAL_STRING', _U('PromptName')))
    PromptSetVisible(OpenStoreMenuPrompt, true)
    PromptSetStandardMode(OpenStoreMenuPrompt, true)
    PromptSetGroup(OpenStoreMenuPrompt, PromptGroup)
    PromptRegisterEnd(OpenStoreMenuPrompt)
end

function OpenStoreMenu(nearbyShops, filterType)
    if not nearbyShops then
        devPrint("Error: nearbyShops is nil")
        VORPcore.NotifyObjective("No nearby shops found.", 4000)
        return
    end

    devPrint("Opening store menu with shops: " .. json.encode(nearbyShops))

    local storePage = ISEEStoresMainMenu:RegisterPage('store:main')
    storePage:RegisterElement('header', { value = 'Store Menu', slot = "header" })

    for _, shop in ipairs(nearbyShops) do
        if not filterType or shop.type == filterType then
            storePage:RegisterElement('button', { label = shop.name, slot = "content" }, function()
                if shop.type == "npc" then
                    OpenNPCBuySellMenu(shop.name)
                else
                    OpenPlayerBuySellMenu(shop.name)
                end
            end)
        end
    end

    storePage:RegisterElement('line', { slot = "footer", style = {} })
    storePage:RegisterElement('button', { label = _U('storeClose'), slot = "footer" }, function()
        ISEEStoresMainMenu:Close()
    end)
    storePage:RegisterElement('bottomline', { slot = "footer", style = {} })

    ISEEStoresMainMenu:Open({ startupPage = storePage })
end

-- Function to fetch player list from the server
function FetchPlayers()
    TriggerServerEvent('playerstore:fetchPlayers')
end

-- Function to handle fetched players from the server
RegisterNetEvent('playerstore:receivePlayers')
AddEventHandler('playerstore:receivePlayers', function(players)
    currentPlayers = players
    OpenCreateStoreMenu(players)
end)

-- Function to open Buy/Sell Menu for NPC Stores
function OpenNPCBuySellMenu(shopName)
    devPrint("Opening Buy/Sell Menu for NPC store: " .. shopName)
    local NPCbuySellPage = ISEEStoresMainMenu:RegisterPage('npcstore:buysell')

    NPCbuySellPage:RegisterElement('header', { value = shopName, slot = "header" })

    NPCbuySellPage:RegisterElement('button', { label = _U('storeBuyItems'), slot = "content" }, function()
        OpenBuyMenu(shopName, "npc")
    end)

    NPCbuySellPage:RegisterElement('button', { label = _U('storeSellItems'), slot = "content" }, function()
        OpenSellMenu(shopName, "npc")
    end)

    if IsPlayerAdmin() then
        devPrint("Player is an admin, showing admin options for store: " .. shopName)
        NPCbuySellPage:RegisterElement('button', { label = _U('storeAddItems'), slot = "content" }, function()
            devPrint("Opening Add Items Menu for NPC store: " .. shopName)
            OpenAddNPCItemMenu(shopName)
        end)

        NPCbuySellPage:RegisterElement('button', { label = _U('storeEditItems'), slot = "content" }, function()
            devPrint("Opening Edit Items Menu for NPC store: " .. shopName)
            OpenEditItemMenu(shopName, "npc")
        end)
    else
        devPrint("Player is not an admin, hiding admin options for store: " .. shopName)
    end

    ISEEStoresMainMenu:Open({
        startupPage = NPCbuySellPage
    })
end

function OpenPlayerBuySellMenu(shopName)
    devPrint("Opening Buy/Sell Menu for Player store: " .. shopName)
    TriggerServerEvent('playerstore:fetchStoreInfo', shopName)
end

-- Internal function to actually open the NPC Add Item Menu after admin check
function OpenAddNPCItemMenuInternal(shopName)
    devPrint("Opening Add Item Menu for NPC store: " .. shopName)
    local addItemPage = ISEEStoresMainMenu:RegisterPage('addnpcitem:page')

    addItemPage:RegisterElement('header', { value = 'Add Item to ' .. shopName, slot = "header" })

    local itemName = ""
    local itemPrice = 0
    local itemStock = 0
    local itemDescription = ""

    addItemPage:RegisterElement('input', { label = 'Item Name', slot = "content", type = "text", placeholder = "Enter item name", default = itemName }, function(data)
        itemName = data.value or ""
    end)

    addItemPage:RegisterElement('input', { label = 'Item Price: $', slot = "content", type = "number", default = itemPrice, min = 0 }, function(data)
        itemPrice = tonumber(data.value) or 0
    end)

    addItemPage:RegisterElement('input', { label = 'Item Stock', slot = "content", type = "number", default = itemStock, min = 0 }, function(data)
        itemStock = tonumber(data.value) or 0
    end)

    addItemPage:RegisterElement('input', { label = 'Item Description', slot = "content", type = "text", placeholder = "Enter item description", default = itemDescription }, function(data)
        itemDescription = data.value or ""
    end)

    addItemPage:RegisterElement('button', { label = 'Submit', slot = "footer" }, function()
        if itemName ~= "" and itemPrice > 0 and itemStock > 0 then
            TriggerServerEvent('npcstore:addItem', shopName, itemName, itemPrice, itemStock, itemDescription)
            ISEEStoresMainMenu:Close()
        else
            VORPcore.NotifyObjective('Please fill in all fields correctly', 4000)
            devPrint("Invalid input for adding item: " .. itemName .. ", " .. itemPrice .. ", " .. itemStock)
        end
    end)

    addItemPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenNPCBuySellMenu(shopName)
    end)

    ISEEStoresMainMenu:Open({
        startupPage = addItemPage
    })
end

-- Function to open the Add Item Menu for Player Stores
function OpenAddPlayerItemMenu(storeName)
    devPrint("Checking ownership for Player store: " .. storeName)
    TriggerServerEvent("store:CheckOwnership", storeName)
end

RegisterNetEvent("store:ownershipConfirmed")
AddEventHandler("store:ownershipConfirmed", function(isOwner, storeName, inventory)
    devPrint("Received ownership confirmation for store: " .. storeName .. ", Is owner: " .. tostring(isOwner))
    if isOwner then
        devPrint("Ownership verified for store: " .. storeName)
        -- Trigger fetching the inventory from the server
        TriggerServerEvent('playerstore:fetchInventory', storeName)
    else
        devPrint("Player is not the owner of the store: " .. storeName)
        VORPcore.NotifyObjective('You do not have permission to add items.', 4000)
    end
end)

function OpenRemovePlayerItemMenu(shopName)
    TriggerServerEvent('playerstore:fetchShopItems', shopName)
end

-- Functions for opening Edit Item Menu based on store type
function OpenEditItemMenu(shopName, storeType)
    devPrint("Opening Edit Item Menu for " .. storeType .. " store: " .. shopName)
    if storeType == "npc" then
        -- Logic for editing items in NPC store
    elseif storeType == "player" then
        -- Logic for editing items in Player store
    end
end

function OpenBuyMenu(shopName, storeType)
    devPrint("Opening Buy Menu for " .. storeType .. " store: " .. shopName)
    BuyCategoriesMenu(shopName)
end

function OpenSellMenu(shopName, storeType)
    devPrint("Opening Sell Menu for " .. storeType .. " store: " .. shopName)
    -- Fetch the categories for selling
    TriggerServerEvent('shop:fetchSellCategories', shopName)
end

function BuyCategoriesMenu(shopName)
    devPrint("Attempting to open BuyCategoriesMenu for shop:", shopName)
    TriggerServerEvent('shop:fetchCategories', shopName)
end

RegisterNetEvent('shop:receiveCategories')
AddEventHandler('shop:receiveCategories', function(shopName, categories)
    devPrint("Received buy categories for shop: " .. shopName .. ", Categories: " .. json.encode(categories))
    if not categories or #categories == 0 then
        VORPcore.NotifyObjective("No categories found for the shop.", 4000)
        return
    end

    local categoriesPage = ISEEStoresMainMenu:RegisterPage('buy:categories:page')
    categoriesPage:RegisterElement('header', { value = _U('storeCategory'), slot = "header" })
    categoriesPage:RegisterElement('line', { value = "", slot = "header" })

    for _, category in ipairs(categories) do
        categoriesPage:RegisterElement('button', { label = category.category, slot = "content", sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" }}, function() 
            BuyMenu(shopName, category.category) 
        end)
    end
    categoriesPage:RegisterElement('line', { slot = "footer", style = {} })
    categoriesPage:RegisterElement('button', { label = _U('BackToStores'), slot = "footer"}, function()
        OpenStoreMenu(globalNearbyShops)
    end)
    categoriesPage:RegisterElement('bottomline', { slot = "footer", style = {} })
    ISEEStoresMainMenu:Open({ startupPage = categoriesPage })
end)

function BuyMenu(shopName, category)
    devPrint("Attempting to open BuyMenu for shop:", shopName, "category:", category)
    TriggerServerEvent('shop:fetchItems', shopName, category)
end

-- Function to generate HTML content
function generateHtmlContent(item, imgPath, levelText, price, isAvailable, isWeapon, quantityText, buyOrSell)
    local color = isAvailable and "black" or "red"
    local priceText = isAvailable and "$" .. tostring(price) or "Unavailable"
    local label = isWeapon and (item.item_label or "Unknown Weapon") or (item.item_label or "Unknown Item")
    quantityText = quantityText or "Quantity not available"  -- Provide a default value

    return '<div style="display: flex; align-items: center; width: 100%; color: ' .. color .. ';">' ..
           '<img src="' .. imgPath .. '" style="width: 32px; height: 32px; margin-right: 10px;">' ..
           '<div style="text-align: center; flex-grow: 1;">' .. label .. " - " .. priceText .. 
           '<br><span style="font-size: smaller; color: gray;">' .. levelText .. '</span>' ..
           '<br><span style="font-size: smaller; color: gray;">' .. quantityText .. '</span></div>' ..
           '</div>'
end

-- Handler for receiving buy items
RegisterNetEvent('shop:receiveItems')
AddEventHandler('shop:receiveItems', function(shopName, category, items)
    devPrint("Received items for shop: " .. shopName .. ", category: " .. category)

    if not items or #items == 0 then
        VORPcore.NotifyObjective("No items found for the category.", 4000)
        devPrint("No items found for the category: " .. category)
        return
    end

    local itemsPage = ISEEStoresMainMenu:RegisterPage('buyitems:page')
    itemsPage:RegisterElement('header', { value = category, slot = "header" })
    itemsPage:RegisterElement('line', { slot = "header", style = {} })

    for _, item in ipairs(items) do
        local isWeapon = item.is_weapon == 1
        local imgPath = 'nui://vorp_inventory/html/img/items/' .. (isWeapon and item.weaponasitem or item.item_name) .. '.png'
        local levelText = "Level: " .. (item.level_required or 0)  -- Always display level
        local isAvailable = item.buy_price ~= nil and item.buy_price > 0
        local quantityText = _U('storeQty') .. (item.buy_quantity or 0)
        
        -- Only show available items
        if isAvailable then
            local htmlContent = generateHtmlContent(item, imgPath, levelText, item.buy_price, isAvailable, isWeapon, quantityText, 'buy')

            itemsPage:RegisterElement('button', { html = htmlContent, slot = "content" }, function()
                devPrint("Item button clicked: " .. item.item_name .. ", Available: " .. tostring(isAvailable))
                devPrint("Requesting quantity for item: " .. item.item_name)
                RequestBuyQuantity(item, category, shopName, isWeapon)
            end)
        else
            devPrint("Product unavailable for purchase: " .. item.item_name)
        end
    end

    itemsPage:RegisterElement('line', { slot = "footer", style = {} })
    itemsPage:RegisterElement('button', { label = _U('storeBackCategory'), slot = "footer" }, function()
        devPrint("Back to Categories button clicked for shop: " .. shopName)
        BuyCategoriesMenu(shopName)
    end)
    itemsPage:RegisterElement('bottomline', { slot = "footer", style = {} })
    ISEEStoresMainMenu:Open({ startupPage = itemsPage })
end)

local playerLevelCallbacks = {}

RegisterNetEvent('isee-shops:receivePlayerLevel')
AddEventHandler('isee-shops:receivePlayerLevel', function(level, callbackId)
    if playerLevelCallbacks[callbackId] then
        playerLevelCallbacks[callbackId](level)
        playerLevelCallbacks[callbackId] = nil
    end
end)

function SellCategoriesMenu(shopName)
    devPrint("Attempting to open SellCategoriesMenu for shop:", shopName)
    TriggerServerEvent('shop:fetchSellCategories', shopName)
end

RegisterNetEvent('shop:receiveSellCategories')
AddEventHandler('shop:receiveSellCategories', function(shopName, categories)
    devPrint("Received sell categories for shop:", shopName, "Categories:", json.encode(categories))
    if not categories or #categories == 0 then
        VORPcore.NotifyObjective("No categories found for the shop.", 4000)
        return
    end

    local sellCategoriesPage = ISEEStoresMainMenu:RegisterPage('sell:categories:page')
    sellCategoriesPage:RegisterElement('header', { value = _U('storeCategory'), slot = "header" })
    sellCategoriesPage:RegisterElement('line', { value = "", slot = "header" })

    for _, category in ipairs(categories) do
        sellCategoriesPage:RegisterElement('button', { label = category.category, slot = "content", sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" }}, function() 
            SellMenu(shopName, category.category) 
        end)
    end

    sellCategoriesPage:RegisterElement('line', { slot = "footer", style = {} })
    sellCategoriesPage:RegisterElement('button', { label = _U('BackToStores'), slot = "footer"}, function()
        OpenStoreMenu(globalNearbyShops)
    end)
    sellCategoriesPage:RegisterElement('bottomline', { slot = "footer", style = {} })
    ISEEStoresMainMenu:Open({ startupPage = sellCategoriesPage })
end)

function SellMenu(shopName, category)
    TriggerServerEvent('shop:fetchSellItems', shopName, category)
end

-- Handler for receiving sell items
RegisterNetEvent('shop:receiveSellItems')
AddEventHandler('shop:receiveSellItems', function(shopName, category, items)
    devPrint("Received sell items for shop: " .. shopName .. ", category: " .. category)

    if not items or #items == 0 then
        VORPcore.NotifyObjective("No items found for the category.", 4000)
        devPrint("No items found for the category: " .. category)
        return
    end

    local itemsPage = ISEEStoresMainMenu:RegisterPage('sellitems:page')
    itemsPage:RegisterElement('header', { value = category, slot = "header" })
    itemsPage:RegisterElement('line', { slot = "header", style = {} })

    for _, item in ipairs(items) do
        local isWeapon = item.is_weapon == 1
        local imgPath = 'nui://vorp_inventory/html/img/items/' .. (isWeapon and item.weaponasitem or item.item_name) .. '.png'
        local levelText = "Level: " .. (item.level_required or 0)  -- Always display level
        local isAvailable = item.sell_price ~= nil and item.sell_price > 0
        local quantityText = _U('storeQty') .. (item.sell_quantity or 0)
        
        -- Only show available items
        if isAvailable then
            local htmlContent = generateHtmlContent(item, imgPath, levelText, item.sell_price, isAvailable, isWeapon, quantityText, 'sell')
            
            itemsPage:RegisterElement('button', { html = htmlContent, slot = "content" }, function()
                devPrint("Item button clicked: " .. item.item_name .. ", Available: " .. tostring(isAvailable))
                RequestSellQuantity(item, category, shopName, isWeapon)
            end)
        else
            devPrint("Product unavailable for sale: " .. item.item_name)
        end
    end

    itemsPage:RegisterElement('line', { slot = "footer", style = {} })
    itemsPage:RegisterElement('button', { label = _U('storeBackCategory'), slot = "footer" }, function() 
        devPrint("Back to Categories button clicked for shop: " .. shopName)
        SellCategoriesMenu(shopName) 
    end)
    itemsPage:RegisterElement('bottomline', { slot = "footer", style = {} })
    ISEEStoresMainMenu:Open({ startupPage = itemsPage })
end)

function RequestBuyQuantity(item, category, shopName, isWeapon)
    devPrint("RequestBuyQuantity called for item: " .. item.item_name)
    local callbackId = tostring(math.random(100000, 999999))
    
    playerLevelCallbacks[callbackId] = function(level)
        playerLevel = level
        devPrint("Received player level inside RequestBuyQuantity: " .. playerLevel)

        if item.level_required > playerLevel then
            VORPcore.NotifyObjective("You need to be level " .. item.level_required .. " to purchase this " .. (isWeapon and "weapon" or "item") .. ".", 4000)
            devPrint("Player level too low to purchase item")
            return
        end

        local inputPage = ISEEStoresMainMenu:RegisterPage('entry:quantity')
        local quantity = 1

        inputPage:RegisterElement('header', { value = _U('storeQtyToSell'), slot = "header" })
        inputPage:RegisterElement('line', { slot = "header", style = {} })
        inputPage:RegisterElement('input', { label = _U('storeQty'), slot = "content", type = "number", default = 1, min = 1, max = item.count }, function(data)
            local inputQty = tonumber(data.value)
            if inputQty and inputQty > 0 then
                quantity = inputQty
                devPrint("Quantity updated: " .. quantity)
            else
                VORPcore.NotifyObjective("Invalid quantity", 4000)
                devPrint("Invalid quantity entered: " .. tostring(inputQty))
                quantity = nil
            end
        end)
        inputPage:RegisterElement('button', { label = _U('storeBuy'), style = {}, sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" } }, function()
            if quantity then
                ProcessPurchase(shopName, item, quantity, isWeapon)
                BuyMenu(shopName, category)
            else
                VORPcore.NotifyObjective("Enter a valid quantity", 4000)
                devPrint("Invalid quantity submission")
            end
        end)
        inputPage:RegisterElement('line', { slot = "footer", style = {} })
        inputPage:RegisterElement('button', { label = _U('BackToItems'), slot = "footer", style = {}, sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" } }, function()
            BuyMenu(shopName, category)
        end)
        inputPage:RegisterElement('bottomline', { slot = "footer", style = {} })
        ISEEStoresMainMenu:Open({ startupPage = inputPage })
    end

    TriggerServerEvent('isee-shops:requestPlayerLevel', callbackId) -- Pass a unique callback ID
end

function RequestSellQuantity(item, category, shopName, isWeapon)
    devPrint("RequestSellQuantity called for item: " .. item.item_name)
    local callbackId = tostring(math.random(100000, 999999))
    
    playerLevelCallbacks[callbackId] = function(level)
        playerLevel = level
        devPrint("Received player level inside RequestSellQuantity: " .. playerLevel)

        if item.level_required > playerLevel then
            VORPcore.NotifyObjective("You need to be level " .. item.level_required .. " to sell this " .. (isWeapon and "weapon" or "item") .. ".", 4000)
            devPrint("Player level too low to sell item")
            return
        end

        local inputPage = ISEEStoresMainMenu:RegisterPage('entry:quantity')
        local quantity = 1

        inputPage:RegisterElement('header', { value = _U('storeQtyToSell'), slot = "header" })
        inputPage:RegisterElement('line', { slot = "header", style = {} })
        inputPage:RegisterElement('input', { label = _U('storeQty'), slot = "content", type = "number", default = 1, min = 1, max = item.count }, function(data)
            local inputQty = tonumber(data.value)
            if inputQty and inputQty > 0 then
                quantity = inputQty
                devPrint("Quantity updated: " .. quantity)
            else
                VORPcore.NotifyObjective("Invalid quantity", 4000)
                devPrint("Invalid quantity entered: " .. tostring(inputQty))
                quantity = nil
            end
        end)
        inputPage:RegisterElement('button', { label = "Sell", style = {}, sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" } }, function()
            if quantity then
                ProcessSale(shopName, item, quantity, isWeapon)
                SellMenu(shopName, category)
            else
                VORPcore.NotifyObjective("Enter a valid quantity", 4000)
                devPrint("Invalid quantity submission")
            end
        end)
        inputPage:RegisterElement('line', { slot = "footer", style = {} })
        inputPage:RegisterElement('button', { label = _U('BackToItems'), slot = "footer", style = {}, sound = { action = "SELECT", soundset = "RDRO_Character_Creator_Sounds" } }, function()
            SellMenu(shopName, category)
        end)
        inputPage:RegisterElement('bottomline', { slot = "footer", style = {} })
        ISEEStoresMainMenu:Open({ startupPage = inputPage })
    end

    TriggerServerEvent('isee-shops:requestPlayerLevel', callbackId) -- Pass a unique callback ID
end

function ProcessPurchase(shopName, item, quantity, isWeapon)
    devPrint("Processing purchase for item: " .. item.item_name .. ", Quantity: " .. quantity)
    local totalCost = item.buy_price * quantity
    if quantity and quantity > 0 then
        TriggerServerEvent('isee-shops:purchaseItem', shopName, isWeapon and item.weapon_name or item.item_name, quantity, totalCost, isWeapon)
    else
        VORPcore.NotifyObjective("Invalid quantity. Purchase request not sent.")
        devPrint("Invalid quantity for purchase: " .. quantity)
    end
end

function ProcessSale(shopName, item, quantity, isWeapon)
    devPrint("Processing sale for item: " .. item.item_name .. ", Quantity: " .. quantity)
    local totalCost = item.sell_price * quantity
    if quantity and quantity > 0 then
        TriggerServerEvent('isee-shops:sellItem', shopName, isWeapon and item.weapon_name or item.item_name, quantity, totalCost, isWeapon)
    else
        VORPcore.NotifyObjective("Invalid quantity. Sale request not sent.", 4000)
        devPrint("Invalid quantity for sale: " .. quantity)
    end
end

RegisterNetEvent('playerstore:receiveInventory')
AddEventHandler('playerstore:receiveInventory', function(inventory, shopName)
    devPrint("Received inventory for shop: " .. shopName)

    local addItemPage = ISEEStoresMainMenu:RegisterPage('playerstore:additems')
    addItemPage:RegisterElement('header', { value = 'Inventory', slot = "header" })
    addItemPage:RegisterElement('line', { slot = "header", style = {} })

    -- Create buttons for each item
    for _, item in ipairs(inventory) do
        local itemName = item.item_name or "unknown_item"
        local imgPath = 'nui://vorp_inventory/html/img/items/' .. itemName .. '.png'
        devPrint("Adding item to menu: " .. item.label .. " (x" .. item.count .. ")" .. imgPath)
        addItemPage:RegisterElement('button', { label = item.label .. ' (x' .. item.count .. ')', slot = "content" },
            function()
                devPrint("Button clicked for item: " .. item.label)
                OpenAddPlayerItemDetailMenu(shopName, item)
            end)
    end

    addItemPage:RegisterElement('line', { slot = "footer", style = {} })

    -- Add a back button
    addItemPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        devPrint("Back button clicked, returning to store menu")
        OpenStoreMenu(globalNearbyShops)
    end)
    addItemPage:RegisterElement('bottomline', { slot = "footer", style = {} })

    devPrint("Opening addItemPage")
    ISEEStoresMainMenu:Open({ startupPage = addItemPage })
end)

function OpenAddPlayerItemDetailMenuWithDetails(shopName, item, actionType)
    devPrint("Opening item detail menu for item: " .. (item.label or "Unknown Item") .. ", Action Type: " .. actionType)
    local itemDetailPage = ISEEStoresMainMenu:RegisterPage('playerstore:itemdetails')
    
    itemDetailPage:RegisterElement('header', { value = 'Item Details: ' .. (item.label or "Unknown Item"), slot = "header" })
    itemDetailPage:RegisterElement('line', { slot = "header", style = {} })
    
    local itemName = item.item_name or "unknown_item"
    local inputPrice = actionType == 'buy' and item.buy_price or item.sell_price
    local inputQuantity = 1
    local inputCategory = item.category or "Unknown Category"
    local inputLevelRequired = item.level_required or 0

    itemDetailPage:RegisterElement('input', { label = (actionType == 'buy' and 'Buy Price: $' or 'Sell Price: $'), slot = "content", type = "number", default = inputPrice, min = 0 }, function(data)
        inputPrice = tonumber(data.value) or inputPrice
        devPrint("Updated Price: " .. inputPrice)
    end)
    itemDetailPage:RegisterElement('input', { label = _U('storeQty'), slot = "content", type = "number", default = 1, min = 1 }, function(data)
        inputQuantity = tonumber(data.value) or 1
        devPrint("Updated Quantity: " .. inputQuantity)
    end)
    itemDetailPage:RegisterElement('input', { label = 'Category', slot = "content", type = "text", default = inputCategory }, function(data)
        inputCategory = data.value or "Unknown Category"
        devPrint("Updated Category: " .. inputCategory)
    end)
    itemDetailPage:RegisterElement('input', { label = 'Level Required', slot = "content", type = "number", default = inputLevelRequired, min = 0 }, function(data)
        inputLevelRequired = tonumber(data.value) or 0
        devPrint("Updated Level Required: " .. inputLevelRequired)
    end)
    
    itemDetailPage:RegisterElement('button', { label = 'Submit', slot = "footer" }, function()
        if inputQuantity > 0 then
            if actionType == 'buy' then
                devPrint("Submitting buy item - Name: " .. itemName .. ", Quantity: " .. inputQuantity .. ", Buy Price: " .. inputPrice .. ", Category: " .. inputCategory .. ", Level Required: " .. inputLevelRequired)
                TriggerServerEvent('playerstore:addBuyItem', shopName, item.label, itemName, inputQuantity, inputPrice, inputCategory, inputLevelRequired)
            else
                devPrint("Submitting sell item - Name: " .. itemName .. ", Quantity: " .. inputQuantity .. ", Sell Price: " .. inputPrice .. ", Category: " .. inputCategory .. ", Level Required: " .. inputLevelRequired)
                TriggerServerEvent('playerstore:addSellItem', shopName, item.label, itemName, inputQuantity, inputPrice, inputCategory, inputLevelRequired)
            end
            ISEEStoresMainMenu:Close()
        else
            devPrint("Invalid quantity: " .. inputQuantity)
            VORPcore.NotifyObjective('Invalid quantity', 4000)
        end
    end)
    
    itemDetailPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        devPrint("Back button pressed. Returning to previous menu.")
        OpenAddPlayerItemDetailMenu(shopName, item)
    end)

    ISEEStoresMainMenu:Open({ startupPage = itemDetailPage })
end

function OpenAddItemSelectionMenuWithDetails(shopName, item)
    devPrint("Opening selection menu for item: " .. item.label)
    local selectionPage = ISEEStoresMainMenu:RegisterPage('playerstore:selectaction')

    selectionPage:RegisterElement('header', { value = 'Select Action', slot = "header" })
    selectionPage:RegisterElement('line', { slot = "header", style = {} })

    selectionPage:RegisterElement('button', { label = 'Add to Buy Inventory', slot = "content" }, function()
        devPrint("Add to Buy Inventory selected for item: " .. item.label)
        OpenAddPlayerItemDetailMenu(shopName, item, 'buy')
    end)

    selectionPage:RegisterElement('button', { label = 'Add to Sell Inventory', slot = "content" }, function()
        devPrint("Add to Sell Inventory selected for item: " .. item.label)
        OpenAddPlayerItemDetailMenu(shopName, item, 'sell')
    end)

    selectionPage:RegisterElement('line', { slot = "footer", style = {} })

    selectionPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        devPrint("Back button clicked, returning to inventory")
        TriggerServerEvent('playerstore:fetchInventory', shopName)
    end)
    selectionPage:RegisterElement('bottomline', { slot = "footer", style = {} })

    devPrint("Opening selectionPage")
    ISEEStoresMainMenu:Open({ startupPage = selectionPage })
end

-- Function to open the selection menu for adding items to buy or sell
function OpenAddItemSelectionMenu(storeName)
    local addItemPage = ISEEStoresMainMenu:RegisterPage('playerstore:additemsmenu')
    addItemPage:RegisterElement('header', { value = 'Add Items to ' .. storeName, slot = "header" })
    addItemPage:RegisterElement('line', { slot = "header", style = {} })

    -- Button for adding items to buy
    addItemPage:RegisterElement('button', { label = 'Add Items to Buy', slot = "content" }, function()
        OpenAddPlayerItemDetailMenu(storeName, "buy")
    end)

    -- Button for adding items to sell
    addItemPage:RegisterElement('button', { label = 'Add Items to Sell', slot = "content" }, function()
        OpenAddPlayerItemDetailMenu(storeName, "sell")
    end)

    addItemPage:RegisterElement('line', { slot = "footer", style = {} })

    -- Add a back button
    addItemPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenStoreMenu(globalNearbyShops)
    end)
    addItemPage:RegisterElement('bottomline', { slot = "footer", style = {} })

    ISEEStoresMainMenu:Open({ startupPage = addItemPage })
end

function OpenAddItemMenu(shopName, item, inventoryType)
    local addItemPage = ISEEStoresMainMenu:RegisterPage('playerstore:additem')
    addItemPage:RegisterElement('header', { value = 'Add Item - ' .. item.label, slot = "header" })
    addItemPage:RegisterElement('line', { slot = "header", style = {} })

    local quantity = 0
    addItemPage:RegisterElement('input', { label = _U('storeQty'), slot = "content", type = "number", placeholder = "Enter quantity" }, function(data)
        quantity = tonumber(data.value)
    end)

    local price = 0
    addItemPage:RegisterElement('input', { label = 'Price', slot = "content", type = "number", placeholder = "Enter price" }, function(data)
        price = tonumber(data.value)
    end)

    addItemPage:RegisterElement('button', { label = 'Add Item', slot = "footer" }, function()
        if inventoryType == "buy" then
            devPrint("Triggering addBuyItem with itemName: " .. tostring(item.item_name))
            TriggerServerEvent('playerstore:addBuyItem', shopName, item.label, item.item_name, quantity, price, item.category, item.level_required)
        else
            devPrint("Triggering addSellItem with itemName: " .. tostring(item.item_name))
            TriggerServerEvent('playerstore:addSellItem', shopName, item.label, item.item_name, quantity, price, item.category, item.level_required)
        end
        ISEEStoresMainMenu:Close()
    end)

    addItemPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenAddPlayerItemDetailMenu(shopName, item)
    end)

    ISEEStoresMainMenu:Open({ startupPage = addItemPage })
end

function OpenAddPlayerItemDetailMenu(shopName, item)
    local addItemMenu = ISEEStoresMainMenu:RegisterPage('playerstore:addItemDetail')
    addItemMenu:RegisterElement('header', { value = item.label, slot = "header" })
    addItemMenu:RegisterElement('line', { slot = "header", style = {} })

    -- Add to Buy Inventory Button
    addItemMenu:RegisterElement('button', { label = 'Add to Buy Inventory', slot = "content" }, function()
        OpenAddPlayerItemDetailMenuWithDetails(shopName, item, 'buy')
    end)

    -- Add to Sell Inventory Button
    addItemMenu:RegisterElement('button', { label = 'Add to Sell Inventory', slot = "content" }, function()
        OpenAddPlayerItemDetailMenuWithDetails(shopName, item, 'sell')
    end)

    -- Add a back button
    addItemMenu:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenAddPlayerItemMenu(shopName)
    end)
    addItemMenu:RegisterElement('bottomline', { slot = "footer", style = {} })

    ISEEStoresMainMenu:Open({ startupPage = addItemMenu })
end

RegisterNetEvent('playerstore:receiveStoreInfo')
AddEventHandler('playerstore:receiveStoreInfo', function(shopName, invLimit, ledger, isOwner)
    devPrint("Received store info for shop: " .. shopName)
    devPrint("Is player owner: " .. tostring(isOwner))

    local playerbuySellPage = ISEEStoresMainMenu:RegisterPage('playerstore:buysell:page')
    playerbuySellPage:RegisterElement('header', { value = shopName, slot = "header" })

    -- Determine what options to show based on whether the player is the owner and/or admin
    if not isOwner then
        devPrint("Player is not the owner of the shop: " .. shopName)
        playerbuySellPage:RegisterElement('button', { label = "Buy Items", slot = "content" }, function()
            OpenBuyMenu(shopName, "player")
        end)

        playerbuySellPage:RegisterElement('button', { label = "Sell Items", slot = "content" }, function()
            OpenSellMenu(shopName, "player")
        end)
    end

    if isOwner then
        devPrint("Player is the owner of the shop: " .. shopName)
        playerbuySellPage:RegisterElement('button', { label = "Add Items", slot = "content" }, function()
            OpenAddPlayerItemMenu(shopName)
        end)

        playerbuySellPage:RegisterElement('button', { label = "Remove Items", slot = "content" }, function()
            OpenRemovePlayerItemMenu(shopName)
        end)

        playerbuySellPage:RegisterElement('button', { label = "Edit Items", slot = "content" }, function()
            OpenEditItemMenu(shopName, "player")
        end)
        
        playerbuySellPage:RegisterElement('line', { slot = "footer", style = {} })
        
        playerbuySellPage:RegisterElement('textdisplay', {
            value = "Inventory Limit: " .. invLimit,
            slot = "footer",
            style = {}
        })
        
        playerbuySellPage:RegisterElement('line', { slot = "footer", style = {} })
        
        playerbuySellPage:RegisterElement('textdisplay', {
            value = "Ledger: $" .. ledger,
            slot = "footer",
            style = {}
        })
        
        playerbuySellPage:RegisterElement('line', { slot = "footer", style = {} })
    end

    -- Admin options (only if not already shown due to ownership)
    if IsPlayerAdmin() and not isOwner then
        devPrint("Player is an admin, showing admin options for store: " .. shopName)
        playerbuySellPage:RegisterElement('button', { label = "Add Items", slot = "content" }, function()
            devPrint("Opening Add Items Menu for player store: " .. shopName)
            OpenAddPlayerItemMenu(shopName)
        end)

        playerbuySellPage:RegisterElement('button', { label = "Edit Items", slot = "content" }, function()
            devPrint("Opening Edit Items Menu for player store: " .. shopName)
            OpenEditItemMenu(shopName, "player")
        end)
    else
        devPrint("Player is not an admin or options already shown, hiding admin options for store: " .. shopName)
    end

    devPrint("Opening player buy/sell page for shop: " .. shopName)
    ISEEStoresMainMenu:Open({ startupPage = playerbuySellPage })
end)

-- Update ownedShops table on the client side
RegisterNetEvent('playerstore:updateOwnedShops')
AddEventHandler('playerstore:updateOwnedShops', function(shopName, isOwner)
    devPrint("Updating ownedShops for shop: " .. shopName .. ", isOwner: " .. tostring(isOwner))
    if isOwner then
        ownedShops[shopName] = true
    else
        ownedShops[shopName] = nil
    end
end)
function OpenAddNPCItemMenu(shopName)
    -- Fetch NPC store inventory
    TriggerServerEvent('npcstore:fetchInventory', shopName)
end

RegisterNetEvent('npcstore:receiveInventory')
AddEventHandler('npcstore:receiveInventory', function(inventory, shopName)
    local addItemPage = ISEEStoresMainMenu:RegisterPage('npcstore:additems')
    addItemPage:RegisterElement('header', { value = 'Inventory:', slot = "header" })
    -- Create buttons for each item
    for _, item in ipairs(inventory) do
        addItemPage:RegisterElement('button', { label = item.label .. ' (x' .. item.count .. ')', slot = "content" },
            function()
                OpenNPCItemDetailMenu(shopName, item)
            end)
    end
    -- Add a back button
    addItemPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenStoreMenu(globalNearbyShops)
    end)

    ISEEStoresMainMenu:Open({ startupPage = addItemPage })
end)

RegisterNetEvent('playerstore:receiveShopItems')
AddEventHandler('playerstore:receiveShopItems', function(items, shopName)
    local removeItemPage = ISEEStoresMainMenu:RegisterPage('removeplayeritem:page')
    removeItemPage:RegisterElement('header', { value = 'Remove Item from ' .. shopName, slot = "header" })
    removeItemPage:RegisterElement('line', { slot = "header", style = {} })

    for _, item in ipairs(items) do
        local label = item.item_label or "Unknown Item"
        local buyQuantity = item.buy_quantity or 0
        local sellQuantity = item.sell_quantity or 0
        removeItemPage:RegisterElement('button', { label = label .. ' (Buy: ' .. buyQuantity .. ', Sell: ' .. sellQuantity .. ')', slot = "content" }, function()
            RequestRemoveQuantity(shopName, item.item_name, buyQuantity, sellQuantity)
        end)
    end

    removeItemPage:RegisterElement('line', { slot = "footer", style = {} })
    removeItemPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenStoreMenu(globalNearbyShops)
    end)
    removeItemPage:RegisterElement('bottomline', { slot = "footer", style = {} })
    ISEEStoresMainMenu:Open({ startupPage = removeItemPage })
end)

function RequestRemoveQuantity(shopName, itemName, maxBuyQuantity, maxSellQuantity)
    local inputPage = ISEEStoresMainMenu:RegisterPage('entry:quantity')
    local quantity = 1
    local removeForBuy = true

    inputPage:RegisterElement('header', { value = "Enter Quantity to Remove", slot = "header" })
    inputPage:RegisterElement('line', { slot = "header", style = {} })
    inputPage:RegisterElement('input', { label = _U('storeQty'), slot = "content", type = "number", default = 1, min = 1 }, function(data)
        local inputQty = tonumber(data.value)
        if inputQty and inputQty > 0 then
            quantity = inputQty
        else
            VORPcore.NotifyObjective("Invalid quantity", 4000)
        end
    end)
    inputPage:RegisterElement('line', { slot = "footer", style = {} })
    inputPage:RegisterElement('button', { label = "Remove for Buy", slot = "footer" }, function()
        if quantity <= maxBuyQuantity then
            TriggerServerEvent('playerstore:removeShopItem', shopName, itemName, quantity, true)
            OpenStoreMenu(globalNearbyShops)
        else
            VORPcore.NotifyObjective("Quantity exceeds available buy stock", 4000)
        end
    end)
    inputPage:RegisterElement('button', { label = "Remove for Sell", slot = "footer" }, function()
        if quantity <= maxSellQuantity then
            TriggerServerEvent('playerstore:removeShopItem', shopName, itemName, quantity, false)
            OpenStoreMenu(globalNearbyShops)
        else
            VORPcore.NotifyObjective("Quantity exceeds available sell stock", 4000)
        end
    end)
    
    inputPage:RegisterElement('button', { label = "Back", slot = "footer" }, function()
        TriggerServerEvent('playerstore:fetchShopItems', shopName)
    end)
    inputPage:RegisterElement('bottomline', { slot = "footer", style = {} })
    ISEEStoresMainMenu:Open({ startupPage = inputPage })
end

function OpenNPCItemDetailMenu(shopName, item)
    local itemDetailPage = ISEEStoresMainMenu:RegisterPage('NPC:itemdetail:page')
    itemDetailPage:RegisterElement('header', { value = 'Item Details: ' .. (item.label or "Unknown Item"), slot = "header" })
    itemDetailPage:RegisterElement('line', { slot = "header", style = {} })

    -- Safeguard against nil values
    local buyprice = item.buyprice or 0
    local sellprice = item.sellprice or 0
    local category = item.category or "Unknown Category"
    local levelRequired = item.level_required or 0 -- Ensure the field name matches your database schema

    -- Variables to hold input data
    local inputBuyPrice = buyprice
    local inputSellPrice = sellprice
    local inputCategory = category
    local inputLevelRequired = levelRequired
    local inputQuantity = 1

    -- Add item details inputs
    itemDetailPage:RegisterElement('input', { label = 'Buy Price: $', slot = "content", type = "number", default = buyprice, min = 0 }, function(data)
        inputBuyPrice = tonumber(data.value) or 0
    end)
    itemDetailPage:RegisterElement('input', { label = 'Sell Price: $', slot = "content", type = "number", default = sellprice, min = 0 }, function(data)
        inputSellPrice = tonumber(data.value) or 0
    end)
    itemDetailPage:RegisterElement('input', { label = 'Category', slot = "content", type = "text", default = category }, function(data)
        inputCategory = data.value or "Unknown Category"
    end)
    itemDetailPage:RegisterElement('input', { label = 'Level Required', slot = "content", type = "number", default = levelRequired, min = 0 }, function(data)
        inputLevelRequired = tonumber(data.value) or 0
    end)
    itemDetailPage:RegisterElement('input', { label = _U('storeQty'), slot = "content", type = "number", default = 1, min = 1 }, function(data)
        inputQuantity = tonumber(data.value) or 1
    end)

    -- Add submit button
    itemDetailPage:RegisterElement('button', { label = 'Submit', slot = "footer" }, function()
        if inputQuantity > 0 then
            TriggerServerEvent('npcstore:addItem', shopName, item.label, item.name, inputQuantity, inputBuyPrice, inputSellPrice, inputCategory, inputLevelRequired)
            OpenAddNPCItemMenu(shopName)
        else
            VORPcore.NotifyObjective('Invalid quantity', 4000)
        end
    end)

    -- Add back button
    itemDetailPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenAddNPCItemMenu(shopName)
    end)

    ISEEStoresMainMenu:Open({ startupPage = itemDetailPage })
end

function OpenManageStoreInventory(shopName, inventory)
    local inventoryPage = ISEEStoresMainMenu:RegisterPage('playerstore:inventory')

    inventoryPage:RegisterElement('header', { value = 'Store Inventory', slot = "header" })

    if inventory and #inventory > 0 then
        for _, item in ipairs(inventory) do
            local htmlContent = generateInventoryHtmlContent(item)

            inventoryPage:RegisterElement('button', { html = htmlContent, slot = "content" }, function()
                -- Optionally, you can add actions for each item button here
            end)
        end
    else
        inventoryPage:RegisterElement('text', { value = 'No items in inventory', slot = "content" })
    end

    inventoryPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenStoreMenu(globalNearbyShops)
    end)

    ISEEStoresMainMenu:Open({ startupPage = inventoryPage })
end

function generateInventoryHtmlContent(item)
    local color = "black"
    local label = item.item_name
    local quantity = item.item_stock
    local price = item.item_price
    local imgPath = 'nui://vorp_inventory/html/img/items/' .. item.item_db_name .. '.png'
    local description = item.item_description or "No description"

    return '<div style="display: flex; align-items: center; width: 100%; color: ' .. color .. ';">' ..
           '<img src="' .. imgPath .. '" style="width: 64px; height: 64px; margin-right: 10px;">' ..
           '<div style="text-align: left; flex-grow: 1;">' ..
           '<strong>' .. label .. '</strong><br>' ..
           '<span>'.. _U('storeQty') .. quantity .. '</span><br>' ..
           '<span>Price: $' .. price .. '</span><br>' ..
           '<span style="font-size: smaller; color: gray;">' .. description .. '</span></div>' ..
           '</div>'
end

RegisterNetEvent('playerstore:receiveStoreInventory')
AddEventHandler('playerstore:receiveStoreInventory', function(shopName, inventory)
    OpenManageStoreInventory(shopName, inventory)
end)

function OpenGiveAccessMenu(shopName)
    local giveAccessPage = ISEEStoresMainMenu:RegisterPage('playerstore:giveaccess')
    giveAccessPage:RegisterElement('header', { value = 'Give Access to ' .. shopName, slot = "header" })
    giveAccessPage:RegisterElement('input', { label = 'Player ID', slot = "content", type = "number", placeholder = "Enter player ID" }, function(data) playerId = tonumber(data.value) end)
    giveAccessPage:RegisterElement('button', { label = 'Give Access', slot = "content" }, function()
        if playerId then
            TriggerServerEvent('playerstore:giveAccess', shopName, playerId)
        else
            VORPcore.NotifyObjective("Please provide a valid player ID", 4000)
        end
    end)
    giveAccessPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function() OpenStoreMenu(globalNearbyShops) end)
    ISEEStoresMainMenu:Open({ startupPage = giveAccessPage })
end

function OpenRemoveAccessMenu(shopName)
    local removeAccessPage = ISEEStoresMainMenu:RegisterPage('playerstore:removeaccess')
    removeAccessPage:RegisterElement('header', { value = 'Remove Access from ' .. shopName, slot = "header" })
    removeAccessPage:RegisterElement('input', { label = 'Player ID', slot = "content", type = "number", placeholder = "Enter player ID" }, function(data) playerId = tonumber(data.value) end)
    removeAccessPage:RegisterElement('button', { label = 'Remove Access', slot = "content" }, function()
        if playerId then
            TriggerServerEvent('playerstore:removeAccess', shopName, playerId)
        else
            VORPcore.NotifyObjective("Please provide a valid player ID", 4000)
        end
    end)
    removeAccessPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function() OpenStoreMenu(globalNearbyShops) end)
    ISEEStoresMainMenu:Open({ startupPage = removeAccessPage })
end

-- Function to select the owner
function SelectOwner(players)
    if not players or #players == 0 then
        devPrint("No players available for selection.")
        return
    end

    local playerListPage = ISEEStoresMainMenu:RegisterPage('playerstore:selectowner')
    playerListPage:RegisterElement('header', { value = 'Select Store Owner', slot = "header" })

    for _, player in ipairs(players) do
        playerListPage:RegisterElement('button', { label = player.name, slot = "content" }, function()
            local ownerId = player.id
            VORPcore.NotifyObjective("Owner selected: " .. player.name, 4000)
            devPrint("Owner selected: " .. player.name .. ", ID: " .. ownerId)
            OpenCreatePlayerStoreMenu(players, { ownerId = ownerId })
        end)
    end

    playerListPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenCreateStoreMenu(players)
    end)

    ISEEStoresMainMenu:Open({ startupPage = playerListPage })
end

RegisterNetEvent('playerstore:openManageStoresMenu')
AddEventHandler('playerstore:openManageStoresMenu', function(stores, players)
    OpenInitialManageMenu(stores, players)
end)

function OpenInitialManageMenu(stores, players)
    local initialManagePage = ISEEStoresMainMenu:RegisterPage('playerstore:initialmanage')
    initialManagePage:RegisterElement('header', { value = 'Manage Stores', slot = "header" })

    initialManagePage:RegisterElement('button', { label = 'Create New Store', slot = "content" }, function()
        OpenCreateStoreMenu()
    end)

    initialManagePage:RegisterElement('button', { label = 'Manage Stores', slot = "content" }, function()
        TriggerServerEvent('playerstore:fetchShops')
    end)

    initialManagePage:RegisterElement('button', { label = 'Delete Stores', slot = "content" }, function()
        OpenDeleteStoresMenu(stores)
    end)

    initialManagePage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        ISEEStoresMainMenu:Close()
    end)

    ISEEStoresMainMenu:Open({ startupPage = initialManagePage })
end

-- Function to open the main store creation menu
function OpenCreateStoreMenu()
    local createStorePage = ISEEStoresMainMenu:RegisterPage('player:store:createstore')
    createStorePage:RegisterElement('header', { value = 'Create Store', slot = "header" })

    createStorePage:RegisterElement('button', { label = 'Create NPC Store', slot = "content" }, function()
        OpenCreateNPCStoreMenu()
    end)

    createStorePage:RegisterElement('button', { label = 'Create Player Store', slot = "content" }, function()
        FetchPlayersForOwnerSelection()
    end)

    createStorePage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenInitialManageMenu()
    end)

    ISEEStoresMainMenu:Open({ startupPage = createStorePage })
end

function FetchPlayersForOwnerSelection()
    TriggerServerEvent('playerstore:fetchPlayersForOwnerSelection')
end

RegisterNetEvent('playerstore:receivePlayersForOwnerSelection')
AddEventHandler('playerstore:receivePlayersForOwnerSelection', function(players)
    SelectOwner(players)
end)

function OpenCreateNPCStoreMenu(players)
    local npcStorePage = ISEEStoresMainMenu:RegisterPage('playerstore:createnpcstore')
    npcStorePage:RegisterElement('header', { value = 'Create NPC Store', slot = "header" })

    local storeDetails = {
        shopName = '',
        storeType = 'npc',
        blipHash = 1879260108,
        blipColorOpen = '',
        blipColorClosed = '',
        blipColorJob = '',
        npcModel = '',
        shopLocation = '',
        npcPos = nil,
        npcHeading = nil
    }

    npcStorePage:RegisterElement('input', { label = 'Store Name', slot = "content", type = "text", placeholder = "Enter store name" }, function(data)
        storeDetails.shopName = data.value
    end)

    npcStorePage:RegisterElement('input', { label = 'Blip Name', slot = "content", type = "text", placeholder = "Enter blip name" }, function(data)
        storeDetails.blipName = data.value
    end)

    npcStorePage:RegisterElement('input', { label = 'Blip Sprite', slot = "content", type = "number", placeholder = "Enter blip sprite" }, function(data)
        storeDetails.blipHash = tonumber(data.value)
    end)

    npcStorePage:RegisterElement('input', { label = 'Blip Color Open', slot = "content", type = "text", placeholder = "Enter blip color (open)" }, function(data)
        storeDetails.blipColorOpen = data.value
    end)

    npcStorePage:RegisterElement('input', { label = 'Blip Color Closed', slot = "content", type = "text", placeholder = "Enter blip color (closed)" }, function(data)
        storeDetails.blipColorClosed = data.value
    end)

    npcStorePage:RegisterElement('input', { label = 'Blip Color Job', slot = "content", type = "text", placeholder = "Enter blip color (job)" }, function(data)
        storeDetails.blipColorJob = data.value
    end)

    npcStorePage:RegisterElement('input', { label = 'NPC Model', slot = "content", type = "text", placeholder = "Enter NPC model" }, function(data)
        storeDetails.npcModel = data.value
    end)

    npcStorePage:RegisterElement('input', { label = 'Shop Location', slot = "content", type = "text", placeholder = "Enter shop location" }, function(data)
        storeDetails.shopLocation = data.value
    end)

    npcStorePage:RegisterElement('button', { label = 'Set Coordinates', slot = "content" }, function()
        local playerCoords = GetEntityCoords(PlayerPedId())
        storeDetails.npcPos = playerCoords
        VORPcore.NotifyObjective("Coordinates set: " .. tostring(storeDetails.npcPos), 4000)
    end)

    npcStorePage:RegisterElement('button', { label = 'Set Heading', slot = "content" }, function()
        local playerHeading = GetEntityHeading(PlayerPedId())
        storeDetails.npcHeading = playerHeading
        VORPcore.NotifyObjective("Heading set: " .. tostring(storeDetails.npcHeading), 4000)
    end)

    npcStorePage:RegisterElement('button', { label = 'Create NPC Store', slot = "footer" }, function()
        if storeDetails.shopName == '' then
            VORPcore.NotifyObjective("Please provide a store name", 4000)
        elseif storeDetails.blipName == '' then
            VORPcore.NotifyObjective("Please provide a blip name", 4000)
        elseif not storeDetails.blipHash then
            VORPcore.NotifyObjective("Please provide a blip sprite", 4000)
        elseif storeDetails.blipColorOpen == '' then
            VORPcore.NotifyObjective("Please provide a blip color (open)", 4000)
        elseif storeDetails.blipColorClosed == '' then
            VORPcore.NotifyObjective("Please provide a blip color (closed)", 4000)
        elseif storeDetails.blipColorJob == '' then
            VORPcore.NotifyObjective("Please provide a blip color (job)", 4000)
        elseif storeDetails.npcModel == '' then
            VORPcore.NotifyObjective("Please provide an NPC model", 4000)
        elseif storeDetails.shopLocation == '' then
            VORPcore.NotifyObjective("Please provide a shop location", 4000)
        elseif not storeDetails.npcPos then
            VORPcore.NotifyObjective("Please set the coordinates", 4000)
        elseif not storeDetails.npcHeading then
            VORPcore.NotifyObjective("Please set the heading", 4000)
        else
            TriggerServerEvent('shop:create', storeDetails.storeType, storeDetails.shopName, storeDetails.blipName, storeDetails.blipHash, storeDetails.blipColorOpen, storeDetails.blipColorClosed, storeDetails.blipColorJob, true, storeDetails.npcModel, storeDetails.npcPos.x, storeDetails.npcPos.y, storeDetails.npcPos.z, storeDetails.npcHeading, storeDetails.shopLocation)
            TriggerEvent('shop:refreshStoreData')
            ISEEStoresMainMenu:Close()
        end
    end)

    npcStorePage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenCreateStoreMenu(players)
    end)

    ISEEStoresMainMenu:Open({ startupPage = npcStorePage })
end

function OpenCreatePlayerStoreMenu(players, storeDetails)
    storeDetails = storeDetails or {
        shopName = '',
        storeType = 'player',
        blipHash = 1879260108,
        ledger = 0,
        invLimit = 0,
        ownerId = storeDetails and storeDetails.ownerId or '',
        insideNpcStore = false,
        npcShopId = nil,
        pos_x = nil,
        pos_y = nil,
        pos_z = nil,
        storeHeading = nil
    }

    local createPlayerStorePage = ISEEStoresMainMenu:RegisterPage('playerstore:createplayerstore')
    createPlayerStorePage:RegisterElement('header', { value = 'Create Player Store', slot = "header" })

    -- Add input elements for player store creation here...
    local shopName = ''

    createPlayerStorePage:RegisterElement('input', { label = 'Store Name', slot = "content", type = "text", placeholder = "Enter store name" }, function(data)
        shopName = data.value
    end)

    createPlayerStorePage:RegisterElement('input', { label = 'Store Type', slot = "content", type = "text", placeholder = "Enter store type", value = storeDetails.storeType }, function(data)
        storeDetails.storeType = data.value
    end)

    createPlayerStorePage:RegisterElement('input', { label = 'Blip Hash', slot = "content", type = "text", placeholder = "Enter blip hash", value = storeDetails.blipHash }, function(data)
        storeDetails.blipHash = data.value
    end)

    createPlayerStorePage:RegisterElement('input', { label = 'Ledger', slot = "content", type = "number", placeholder = "Enter ledger amount", value = storeDetails.ledger }, function(data)
        storeDetails.ledger = tonumber(data.value)
    end)

    createPlayerStorePage:RegisterElement('input', { label = 'Inventory Limit', slot = "content", type = "number", placeholder = "Enter inventory limit", value = storeDetails.invLimit }, function(data)
        storeDetails.invLimit = tonumber(data.value)
    end)

    -- Checkbox for insideNpcStore
    --[[createPlayerStorePage:RegisterElement('checkbox', { label = 'Inside NPC Store', slot = "content" }, function(data)
        storeDetails.insideNpcStore = data.checked
    end)]]--

    -- Select Coordinates
    createPlayerStorePage:RegisterElement('button', { label = 'Set Coordinates', slot = "content" }, function()
        local playerCoords = GetEntityCoords(PlayerPedId())
        storeDetails.pos_x = playerCoords.x
        storeDetails.pos_y = playerCoords.y
        storeDetails.pos_z = playerCoords.z
        VORPcore.NotifyObjective("Coordinates set: " .. tostring(playerCoords), 4000)
        devPrint("Coordinates set: " .. tostring(playerCoords))
    end)

    -- Select Heading
    createPlayerStorePage:RegisterElement('button', { label = 'Set Heading', slot = "content" }, function()
        local playerHeading = GetEntityHeading(PlayerPedId())
        storeDetails.storeHeading = playerHeading
        VORPcore.NotifyObjective("Heading set: " .. tostring(playerHeading), 4000)
        devPrint("Heading set: " .. tostring(playerHeading))
    end)

    createPlayerStorePage:RegisterElement('button', { label = 'Create', slot = "footer" }, function()
        if shopName ~= '' and storeDetails.ownerId ~= '' then
            storeDetails.shopName = shopName
            if storeDetails.pos_x and storeDetails.pos_y and storeDetails.pos_z then
                devPrint("Creating store with details: " .. json.encode(storeDetails))
                TriggerServerEvent('playerstore:create', storeDetails)
                TriggerEvent('shop:refreshStoreData')
                ISEEStoresMainMenu:Close()
            else
                VORPcore.NotifyObjective("Please set the location", 4000)
                devPrint("Location not set")
            end
        else
            VORPcore.NotifyObjective("Please provide all store details", 4000)
            devPrint("Store details incomplete: shopName=" .. shopName .. ", ownerId=" .. storeDetails.ownerId)
        end
    end)

    createPlayerStorePage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenCreateStoreMenu(players)
    end)

    ISEEStoresMainMenu:Open({ startupPage = createPlayerStorePage })
end

function OpenDeleteStoresMenu()
    local deleteStoresPage = ISEEStoresMainMenu:RegisterPage('playerstore:deletestores')
    deleteStoresPage:RegisterElement('header', { value = 'Delete Stores', slot = "header" })

    deleteStoresPage:RegisterElement('button', { label = 'NPC Stores', slot = "content" }, function()
        currentAction = "deleteNPCStores"
        TriggerServerEvent('shop:fetchNPCShops')
    end)

    deleteStoresPage:RegisterElement('button', { label = 'Player Stores', slot = "content" }, function()
        currentAction = "deletePlayerStores"
        TriggerServerEvent('playerstore:fetchStores')
    end)

    deleteStoresPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenInitialManageMenu()
    end)

    ISEEStoresMainMenu:Open({ startupPage = deleteStoresPage })
end

function OpenDeleteNPCStoresMenu()
    local deleteNPCStoresPage = ISEEStoresMainMenu:RegisterPage('playerstore:deletenpcstores')
    deleteNPCStoresPage:RegisterElement('header', { value = 'Delete NPC Stores', slot = "header" })

    for _, store in ipairs(npcStores) do
        deleteNPCStoresPage:RegisterElement('button', { label = store.shop_name, slot = "content" }, function()
            OpenDeleteConfirmationMenu(store.shop_id, store.shop_name, "npc")
        end)
    end

    deleteNPCStoresPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenDeleteStoresMenu()
    end)

    ISEEStoresMainMenu:Open({ startupPage = deleteNPCStoresPage })
end

function OpenDeletePlayerStoresMenu()
    local deletePlayerStoresPage = ISEEStoresMainMenu:RegisterPage('playerstore:deleteplayerstores')
    deletePlayerStoresPage:RegisterElement('header', { value = 'Delete Player Stores', slot = "header" })

    for _, store in ipairs(playerStores) do
        deletePlayerStoresPage:RegisterElement('button', { label = store.shop_name, slot = "content" }, function()
            OpenDeleteConfirmationMenu(store.shop_id, store.shop_name, "player")
        end)
    end

    deletePlayerStoresPage:RegisterElement('button', { label = _U('backButton'), slot = "footer" }, function()
        OpenDeleteStoresMenu()
    end)

    ISEEStoresMainMenu:Open({ startupPage = deletePlayerStoresPage })
end

function OpenDeleteConfirmationMenu(storeId, shopName, storeType)
    local confirmationPage = ISEEStoresMainMenu:RegisterPage('playerstore:confirmdelete')
    confirmationPage:RegisterElement('header', { value = 'Confirm Deletion', slot = "header" })
    confirmationPage:RegisterElement('text', { value = 'Are you sure you want to delete store: ' .. shopName .. '?', slot = "content" })

    confirmationPage:RegisterElement('button', { label = 'Yes', slot = "content" }, function()
        if storeType == "npc" then
            TriggerServerEvent('shop:deleteNPCStore', storeId)
        else
            TriggerServerEvent('playerstore:delete', storeId)
        end
        ISEEStoresMainMenu:Close()
    end)

    confirmationPage:RegisterElement('button', { label = 'No', slot = "content" }, function()
        if storeType == "npc" then
            OpenDeleteNPCStoresMenu()
        else
            OpenDeletePlayerStoresMenu()
        end
    end)

    ISEEStoresMainMenu:Open({ startupPage = confirmationPage })
end

RegisterNetEvent('store:receivePlayerList')
AddEventHandler('store:receivePlayerList', function(players)
    OpenCreatePlayerStoreMenu(players)
end)

RegisterNetEvent('playerstore:inventoryLimitExceeded')
AddEventHandler('playerstore:inventoryLimitExceeded', function()
    VORPcore.NotifyObjective('Inventory limit exceeded', 4000)
end)

RegisterNetEvent('playerstore:storeItemAdded')
AddEventHandler('playerstore:storeItemAdded', function(shopName)
    OpenAddPlayerItemMenu(shopName)
end)

RegisterNetEvent('shop:clientCleanup')
AddEventHandler('shop:clientCleanup', function()
    for _, blip in ipairs(CreatedBlip) do
        RemoveBlip(blip)
    end
    CreatedBlip = {}

    for _, npc in ipairs(CreatedNPC) do
        DeleteEntity(npc)
    end
    CreatedNPC = {}

    devPrint("Cleaned up all blips and NPCs.")
end)

RegisterNetEvent('shop:refreshStoreData')
AddEventHandler('shop:refreshStoreData', function()
    TriggerServerEvent('shop:fetchNPCShops')
    TriggerServerEvent('playerstore:fetchStores')
    TriggerServerEvent('playerstore:fetchPlayerShops')
end)

-- CleanUp on Resource Restart
RegisterNetEvent('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, npcs in ipairs(CreatedNPC) do
            npcs:Remove()
        end
        for _, blips in ipairs(CreatedBlip) do
            blips:Remove()
        end
    end
end)
