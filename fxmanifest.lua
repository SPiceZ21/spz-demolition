fx_version 'cerulean'
game 'gta5'

name 'spz-demolition'
description 'SPiceZ Minigame — Demolition. Destruction derby in the iak_demolition bowl: real damage, last car running wins.'
version '1.0.1'
author 'SPiceZ-Core'
lua54 'yes'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
}

client_scripts {
  'client/base.lua',
  'client/game.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/base.lua',
  'server/game.lua',
}

dependencies {
  'ox_lib',
  'spz-minigames',   -- shared in-game HUD
  'oxmysql',
  'spz-core',
  'spz-identity',
  'iak_demolition',     -- the arena map
}
