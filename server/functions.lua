-- Function to check if a player is the owner of a shop
function isShopOwner(shopName, ownerId, callback)
    MySQL.Async.fetchScalar('SELECT owner_id FROM player_shops WHERE shop_name = @shopName', {
        ['@shopName'] = shopName
    }, function(result)
        if result then
            callback(result == ownerId)
        else
            callback(false)
        end
    end)
end