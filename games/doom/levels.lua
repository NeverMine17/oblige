--------------------------------------------------------------------
--  DOOM LEVELS
--------------------------------------------------------------------
--
--  Copyright (C) 2006-2014 Andrew Apted
--  Copyright (C)      2011 Chris Pisarczyk
--
--  This program is free software; you can redistribute it and/or
--  modify it under the terms of the GNU General Public License
--  as published by the Free Software Foundation; either version 2
--  of the License, or (at your option) any later version.
--
--------------------------------------------------------------------

DOOM.SECRET_EXITS =
{
  MAP15 = true
  MAP31 = true

  E1M3 = true
  E2M5 = true
  E3M6 = true
  E4M2 = true
}


DOOM.EPISODES =
{
  episode1 =
  {
    ep_index = 1

    theme = "tech"
    sky_patch = "RSKY1"
    dark_prob = 10
  }

  episode2 =
  {
    ep_index = 2

    theme = "urban"
    sky_patch = "RSKY2"
    dark_prob = 40
  }

  episode3 =
  {
    ep_index = 3

    theme = "hell"
    sky_patch = "RSKY3"
    dark_prob = 10
  }
}


DOOM.PREBUILT_LEVELS =
{
  MAP07 =
  {
    { prob=50, file="games/doom/data/boss2/simple1.wad", map="MAP07" }
    { prob=50, file="games/doom/data/boss2/simple2.wad", map="MAP07" }
    { prob=50, file="games/doom/data/boss2/simple3.wad", map="MAP07" }
    { prob=50, file="games/doom/data/boss2/simple4.wad", map="MAP07" }
  }

  MAP30 =
  {
    { prob=50, file="games/doom/data/boss2/icon1.wad", map="MAP30" }
    { prob=50, file="games/doom/data/boss2/icon2.wad", map="MAP30" }
    { prob=50, file="games/doom/data/boss2/icon3.wad", map="MAP01" }
    { prob=50, file="games/doom/data/boss2/icon3.wad", map="MAP02" }
    { prob=50, file="games/doom/data/boss2/icon3.wad", map="MAP03" }
  }

  GOTCHA =
  {
    { prob=50, file="games/doom/data/boss2/gotcha1.wad", map="MAP01" }
    { prob=50, file="games/doom/data/boss2/gotcha2.wad", map="MAP01" }
    { prob=40, file="games/doom/data/boss2/gotcha3.wad", map="MAP01" }
    { prob=20, file="games/doom/data/boss2/gotcha4.wad", map="MAP01" }
  }

  GALLOW =
  {
    { prob=50, file="games/doom/data/boss2/gallow1.wad", map="MAP01" }
    { prob=25, file="games/doom/data/boss2/gallow2.wad", map="MAP01" }
  }
}


--------------------------------------------------------------------


function DOOM.get_levels()
  local MAP_LEN_TAB = { few=4, episode=11, game=32 }

  local MAP_NUM = MAP_LEN_TAB[OB_CONFIG.length] or 1

  gotcha_map = rand.pick({ 17,18,19 })
  gallow_map = rand.pick({ 24,25,26 })

  local EP_NUM = 1
  if MAP_NUM > 11 then EP_NUM = 2 end
  if MAP_NUM > 30 then EP_NUM = 3 end

  -- create episode info...

  for ep_index = 1,3 do
    local ep_info = GAME.EPISODES["episode" .. ep_index]
    assert(ep_info)

    local EPI = table.copy(ep_info)

    EPI.levels = { }

    table.insert(GAME.episodes, EPI)
  end

  -- create level info...

  for map = 1,MAP_NUM do
    -- determine episode from map number
    local ep_index
    local ep_along

    local game_along = map / MAP_NUM

    if map > 30 then
      ep_index = 3 ; ep_along = 0.5 ; game_along = 0.5
    elseif map > 20 then
      ep_index = 3 ; ep_along = (map - 20) / 10
    elseif map > 11 then
      ep_index = 2 ; ep_along = (map - 11) / 9
    else
      ep_index = 1 ; ep_along = map / 11
    end

    if OB_CONFIG.length == "single" then
      game_along = rand.pick({ 0.2, 0.3, 0.4, 0.7 })
      ep_along = game_along

    elseif OB_CONFIG.length == "few" then
      ep_along = game_along
    end

    assert(ep_along <= 1.0)
    assert(game_along <= 1.0)

    local EPI = GAME.episodes[ep_index]
    assert(EPI)

    local LEV =
    {
      episode = EPI

      name  = string.format("MAP%02d", map)
      patch = string.format("CWILV%02d", map-1)

      ep_along = ep_along
      game_along = game_along
    }

    table.insert( EPI.levels, LEV)
    table.insert(GAME.levels, LEV)

    LEV.secret_exit = GAME.SECRET_EXITS[LEV.name]

    -- secret levels
    if map == 31 or map == 32 then
      LEV.theme_name = "wolf"
      LEV.name_class = "URBAN"
      LEV.is_secret = true
    end

    if map == 23 then
      LEV.style_list = { barrels = { heaps=100 } }
    end

    -- the 'dist_to_end' value is used for Boss monster decisions
    if map >= 26 and map <= 29 then
      LEV.dist_to_end = 30 - map
    elseif map == 20 or map == 23 then
      LEV.dist_to_end = 2
    elseif map == 11 or map == 16 then
      LEV.dist_to_end = 3
    end

    -- prebuilt levels
    local pb_name = LEV.name

    if map == gotcha_map then pb_name = "GOTCHA" end
    if map == gallow_map then pb_name = "GALLOW" end
    
    LEV.prebuilt = GAME.PREBUILT_LEVELS[pb_name]

    if LEV.prebuilt then
      LEV.name_class = LEV.prebuilt.name_class or "BOSS"
    end

    if MAP_NUM == 1 or (map % 10) == 3 then
      LEV.demo_lump = string.format("DEMO%d", ep_index)
    end
  end

  -- handle "dist_to_end" for FEW and EPISODE lengths
  if OB_CONFIG.length != "single" and OB_CONFIG.length != "game" then
    GAME.levels[#GAME.levels].dist_to_end = 1

    if OB_CONFIG.length == "episode" then
      GAME.levels[#GAME.levels - 1].dist_to_end = 2
      GAME.levels[#GAME.levels - 2].dist_to_end = 3
    end
  end
end

