------------------------------------------------------------------------
--  FIGHT SIMULATOR
------------------------------------------------------------------------
--
--  Oblige Level Maker
--
--  Copyright (C) 2006-2015 Andrew Apted
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
------------------------------------------------------------------------


--[[

===================
 BATTLE SIMULATION
===================

Input
-----
   monsters : list of monsters that the player must kill
              { info=MONSTER_INFO, is_cage=false }

   weapons : list of weapons that player can use
             { info=WEAPON_INFO, factor=1.0 }

Output
------
   stats : health that player needs to survive the battle +
           ammo quantities required by the player

Notes
-----

*  Health result is stored in the 'stats' table.  All the
   values are >= 0 and can be partial (like 3.62 rockets).

*  Armor is not directly modelled.  Instead you can assume
   that some percentage of the returned 'health' would have
   been saved if the player was wearing armor.

*  Powerups are not modelled.  The assumption here is that
   any powerups on the level are bonuses for the player
   and not a core part of gameplay.  It could be handled
   by being stingy on health/ammo in the room containing
   the powerup (and subsequent rooms).

*  Monsters are "fought" one by one in the given list,
   sorted from most threatening to least threatening
   (which is likely how the real player would tackle them).
   Your weapons can damage other monsters though, including
   such things as rocket splash, shotgun spread, the BFG
   etc...

   All of the monsters are fighting the player.  They are
   assumed to be linearly spread out (first one is closest
   and last one is far away), 2D layouts are not modelled.
   Further away monsters do less damage, we also assume
   that closer monsters get in the way (especially for
   missile attacks), and that melee monsters can only hurt
   you when they are first (at most second) in the list.

*  Infighting between monsters is modelled very simplistically,
   as a small reduction to the health of every monsters.  See
   the comment below regarding the INFIGHT_FACTOR value.


----------------------------------------------------------------]]


function Fight_Simulator(monsters, weapons, stats)

  local active_mons = {}

  local DEFAULT_ACCURACY = 70

  -- in general, 5% to 15% of monster damage is not directly from a
  -- player (from a fired weapon or the fist or chainsaw), but from
  -- other monsters, crushers and being telefragged.
  local INFIGHT_FACTOR = 0.92


  local function remove_dead_mon()
    for i = #active_mons,1,-1 do
      if active_mons[i].health <= 0 then
        table.remove(active_mons, i)
      end
    end
  end


  local function select_weapon()
    local first_mon = active_mons[1].info
    assert(first_mon)

    -- determine probability for each weapon
    local prob_tab = {}

    each W in weapons do
      local prob = W.info.pref

      prob = prob * (W.factor or 1)

      -- handle monster-based weapon preferences
      if first_mon.weap_prefs then
        prob = prob * (first_mon.weap_prefs[W.info.name] or 1)
      end

      -- handle 'weap_needed' and 'min_weapon' fields of a monster
      if first_mon.weap_needed and not first_mon.weap_needed[W.info.name] then
        prob = prob / 200
      elseif first_mon.min_weapon and (W.info.level or 0) < first_mon.min_weapon then
        prob = prob / 10
      end

      table.insert(prob_tab, prob)
    end

    assert(#prob_tab == #weapons)

    local index = rand.index_by_probs(prob_tab)
    local W     = assert(weapons[index])

    return W
  end


  local function hurt_mon(idx, W, damage)
    local M = active_mons[idx]

    if not M then return end

    -- apply the weapon accuracy, or use default
    damage = damage * (W.info.accuracy or DEFAULT_ACCURACY) / 100

    if M.info.immunity and M.info.immunity[W.info.name] then
      damage = damage * (1 - M.info.immunity[W.info.name])
    end

    M.health = M.health - damage
  end


  local function player_shoot(W)
    local info = W.info

    hurt_mon(1, W, info.damage)

    -- simulate splash damage | shotgun spread
    if info.splash then
      for i = 1, #info.splash do
        hurt_mon(i, W, info.splash[i])
      end
    end

    -- update ammo counter
    if info.ammo then
      stats[info.ammo] = (stats[info.ammo] or 0) + (info.per or 1)
    end

    return 1 / info.rate
  end


  local function fixup_hexen_mana()
    if stats.dual_mana then
      stats.blue_mana  = (stats.blue_mana  or 0) + stats.dual_mana
      stats.green_mana = (stats.green_mana or 0) + stats.dual_mana
      stats.dual_mana  = nil
    end
  end


  local function calc_monster_threat(M)
    local threat = M.info.health + M.info.damage * 27

    -- caged monsters pose less of a threat
    if M.is_cage and not M.info.nasty then threat = threat / 3 end

    return threat + gui.random() * 20  -- tie breaker
  end


  ---==| Fight_Simulator |==---

  stats.health = stats.health or 0

  each M in monsters do
    local MON = table.copy(M)

    MON.health = MON.info.health * INFIGHT_FACTOR
    MON.threat = calc_monster_threat(MON)

    table.insert(active_mons, MON)
  end

  -- put toughest monster first, weakest last.
  table.sort(active_mons,
      function(A,B) return A.threat > B.threat end)

  -- compute health needed by player
  each M in active_mons do
    stats.health = stats.health + M.info.damage
  end
 
  -- run simulation until all monsters are dead
  while #active_mons > 0 do
    local W = select_weapon()

    local shots = int(rand.range(2.0, 8.0) * W.info.rate + 0.5)

    if shots < 2  then shots = 2  end
    if shots > 30 then shots = 30 end

    for loop = 1, shots do
      player_shoot(W)

      remove_dead_mon()
    end
  end

  fixup_hexen_mana()
end

