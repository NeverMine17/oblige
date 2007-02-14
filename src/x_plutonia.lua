----------------------------------------------------------------
-- THEMES : Plutonia Experiment (Final DOOM)
----------------------------------------------------------------
--
--  Oblige Level Maker (C) 2006,2007 Andrew Apted
--
--  This program is free software; you can redistribute it and/or
--  modify it under the terms of the GNU General Public License
--  as published by the Free Software Foundation; either version 2
--  of the License, or (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
----------------------------------------------------------------


THEME_FACTORIES["plutonia"] = function()

  local T = THEME_FACTORIES.doom2()

  --[[
  T.themes   = copy_and_merge(T.themes,   PL_THEMES)
  T.exits    = copy_and_merge(T.exits,    PL_EXITS)
  T.hallways = copy_and_merge(T.hallways, PL_HALLWAYS)

  T.rails = copy_and_merge(T.rails, PL_RAILS)

  T.hangs   = copy_and_merge(T.hangs,   PL_OVERHANGS)
  T.mats    = copy_and_merge(T.mats,    PL_MATS)
  T.crates  = copy_and_merge(T.crates,  PL_CRATES)
  T.liquids = copy_and_merge(T.liquids, PL_LIQUIDS)
  --]]

  return T
end

