CreateThread(function()
    -- Create unified_shops table
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS unified_shops (
            `shop_id` int(11) NOT NULL AUTO_INCREMENT,
            `owner_id` int(30) DEFAULT NULL,
            `shop_name` varchar(255) NOT NULL,
            `shop_location` varchar(255) NOT NULL,
            `shop_type` varchar(20) NOT NULL,
            `webhook_link` varchar(255) NOT NULL DEFAULT 'none',
            `inv_limit` int(30) NOT NULL DEFAULT 0,
            `ledger` double(11,2) NOT NULL DEFAULT 0.00,
            `blip_hash` varchar(255) NOT NULL DEFAULT 'none',
            `is_npc_shop` tinyint(1) NOT NULL DEFAULT 0,
            `pos_x` double NOT NULL,
            `pos_y` double NOT NULL,
            `pos_z` double NOT NULL,
            `pos_heading` double NOT NULL,
            `prompt_name` varchar(255) DEFAULT NULL,
            `blip_name` varchar(255) DEFAULT NULL,
            `blip_sprite` int(11) DEFAULT NULL,
            `blip_color_open` varchar(255) DEFAULT NULL,
            `blip_color_closed` varchar(255) DEFAULT NULL,
            `blip_color_job` varchar(255) DEFAULT NULL,
            `npc_model` varchar(255) DEFAULT NULL,
            PRIMARY KEY (`shop_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
    ]])

    -- Create unified_items table
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS unified_items (
            `item_id` int(11) NOT NULL AUTO_INCREMENT,
            `shop_id` int(11) NOT NULL,
            `item_label` varchar(255) NOT NULL,
            `item_name` varchar(255) NOT NULL,
            `currency_type` varchar(50) NOT NULL,
            `buy_price` double NOT NULL,
            `sell_price` double NOT NULL,
            `category` varchar(255) NOT NULL,
            `level_required` int(11) NOT NULL,
            `is_weapon` tinyint(1) NOT NULL DEFAULT 0,
            `item_quantity` int(11) DEFAULT 0,
            `buy_quantity` int(11) DEFAULT 0,
            `sell_quantity` int(11) DEFAULT 0,
            PRIMARY KEY (`item_id`),
            KEY `shop_id` (`shop_id`),
            CONSTRAINT `unified_items_ibfk_1` FOREIGN KEY (`shop_id`) REFERENCES `unified_shops` (`shop_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
    ]])

    -- Commit any pending transactions to ensure changes are saved
    MySQL.query.await("COMMIT;")
    print("\n\x1b[32mDatabase tables for:\x1b[0m\n" ..
    "    \x1b[34m* [`unified_shops`]\x1b[0m\n" ..
    "    \x1b[34m* [`unified_items`]\x1b[0m\n" ..
    "\x1b[32mcreated or updated successfully.\x1b[0m\n")
end)
