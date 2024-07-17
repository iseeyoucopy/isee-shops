fx_version 'adamant'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

lua54 'yes'
author '@iseeyoucopy'

description 'Advanced NPC and Player Stores'
shared_scripts {
    'config.lua',
	'shared/locale.lua',
	'languages/*.lua'
}

client_scripts {
	'/client/client.lua',
	'lib/dkjson.lua'  -- Include dkjson library for server
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server/dbUpdater.lua',
	'/server/functions.lua',
	'/server/server.lua',
	'/lib/dkjson.lua'  -- Include dkjson library for server
}

dependency {
	'vorp_core',
	'feather-menu',
	'bcc-utils'
}

version '1.0.0'
