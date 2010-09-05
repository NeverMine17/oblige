----------------------------------------------------------------
--  Room Management
----------------------------------------------------------------
--
--  Oblige Level Maker
--
--  Copyright (C) 2006-2010 Andrew Apted
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

--[[ *** CLASS INFORMATION ***

class ROOM
{
  kind : keyword  -- "normal" (layout-able room)
                  -- "scenic" (unvisitable room)
                  -- "hallway", "stairwell", "small_exit"

  shape : keyword -- "rect" (perfect rectangle)
                  -- "L"
                  -- "T"
                  -- "plus"
                  -- "odd"  (anything else)

  outdoor : bool  -- true for outdoor rooms
  natural : bool  -- true for cave/landscape areas
  scenic  : bool  -- true for scenic (unvisitable) areas

  conns : array(CONN)  -- connections with neighbor rooms
  entry_conn : CONN

  branch_kind : keyword

  hallway : HALLWAY_INFO   -- for hallways and stairwells

  symmetry : keyword   -- symmetry of room, or NIL
                       -- keywords are "x", "y", "xy"

  kx1, ky1, kx2, ky2  -- \ Section range
  kw, kh              -- /

  sx1, sy1, sx2, sy2  -- \ Seed range
  sw, sh, svolume     -- /

  quest : QUEST

  purpose : keyword   -- usually NIL, can be "EXIT" etc... (FIXME)

  floor_h, ceil_h : number


  --- plan_sp code only:

  lx1, ly1, lx2, ly2  -- coverage on the Land Map

  group_id : number  -- traversibility group

}


----------------------------------------------------------------


Room Layouting Notes
====================


DIAGONALS:
   How they work:

   1. basic model: seed is a liquid or walk area which has an
      extra piece stuck in it (the diagonal) which is
      either totally solid or same as a neighbouring higher floor.
      We first build the extra bit, then convert the seed to what
      it should be (change S.kind from "diagonal" --> "liquid" or "walk")
      and build the ceiling/floor normally.

   2. The '/' and '%' in patterns go horizontally, whereas
      the 'Z' and 'N' go vertically.  If the pattern is
      transposed then we exchange '/' with 'Z', '%' with 'N'.

   3. once the room is fully laid out, then we can process
      these diagonals and determine the main seed info
      (e.g. liquid) and the Stuckie piece (e.g. void).


--------------------------------------------------------------]]


require 'defs'
require 'util'


ROOM_CLASS = {}

function ROOM_CLASS.new(shape)
  local id = Plan_alloc_room_id()
  local R = { id=id, kind="normal", shape=shape, conns={}, neighbors={} }
  table.set_class(R, ROOM_CLASS)
  table.insert(LEVEL.all_rooms, R)
  return R
end


function ROOM_CLASS.tostr(self)
  return string.format("ROOM_%d", self.id)
end

function ROOM_CLASS.longstr(self)
  return string.format("%s_%s [%d,%d..%d,%d]",
      sel(self.parent, "SUB_ROOM", "ROOM"),
      self.id, self.sx1,self.sy1, self.sx2,self.sy2)
end

function ROOM_CLASS.update_size(self)
  self.sw, self.sh = geom.group_size(self.sx1, self.sy1, self.sx2, self.sy2)
  self.svolume = self.sw * self.sh
end

function ROOM_CLASS.contains_seed(self, x, y)
  if x < self.sx1 or x > self.sx2 then return false end
  if y < self.sy1 or y > self.sy2 then return false end
  return true
end

function ROOM_CLASS.has_lock(self, lock)
  for _,C in ipairs(self.conns) do
    if C.lock == lock then return true end
  end
  return false
end

function ROOM_CLASS.has_any_lock(self)
  for _,C in ipairs(self.conns) do
    if C.lock then return true end
  end
  return false
end

function ROOM_CLASS.has_lock_kind(self, kind)
  for _,C in ipairs(self.conns) do
    if C.lock and C.lock.kind == kind then return true end
  end
  return false
end

function ROOM_CLASS.has_sky_neighbor(self)
  for _,C in ipairs(self.conns) do
    local N = C:neighbor(self)
    if N.outdoor then return true end
  end
  return false
end

function ROOM_CLASS.has_teleporter(self)
  for _,C in ipairs(self.conns) do
    if C.kind == "teleporter" then return true end
  end
  return false
end

function ROOM_CLASS.valid_T(self, x, y)
  if x < self.tx1 or x > self.tx2 then return false end
  if y < self.ty1 or y > self.ty2 then return false end
  return true
end

function ROOM_CLASS.dist_to_closest_conn(self, K, side)
  -- TODO: improve this by calculating side coordinates
  local best

  for _,C in ipairs(self.conns) do 
    local K2 = C:section(self)
    local dist = geom.dist(K.kx, K.ky, K2.kx, K2.ky)

    if not best or dist < best then best = dist end
  end

  return best
end

function ROOM_CLASS.is_near_exit(self)
  if self.purpose == "EXIT" then return true end
  for _,C in ipairs(self.conns) do
    local N = C:neighbor(self)
    if N.purpose == "EXIT" then return true end
  end
  return false
end



function Rooms_setup_theme(R)
  if not R.outdoor then
    R.main_tex = rand.pick(LEVEL.building_walls)
    return
  end

  if not R.quest.courtyard_floor then
    R.quest.courtyard_floor = rand.pick(LEVEL.courtyard_floors)
  end

  R.main_tex = R.quest.courtyard_floor
end

function Rooms_setup_theme_Scenic(R)
  R.outdoor = true  -- ???

  --[[

  -- find closest non-scenic room
  local mx = int((R.sx1 + R.sx2) / 2)
  local my = int((R.sy1 + R.sy2) / 2)

  for dist = -SEED_W,SEED_W do
    if Seed_valid(mx + dist, my) then
      local S = SEEDS[mx + dist][my]
      if S.room and S.room.kind == "scenic" and
         S.room.combo
---      and (not S.room.outdoor) == (not R.outdoor)
      then
        R.combo = S.room.combo
        -- R.outdoor = S.room.outdoor
        return
      end
    end

    if Seed_valid(mx, my + dist) then
      local S = SEEDS[mx][my + dist]
      if S.room and S.room.kind == "scenic" and
         S.room.combo
---      and (not S.room.outdoor) == (not R.outdoor)
      then
        R.combo = S.room.combo
        R.outdoor = S.room.outdoor
        return
      end
    end
  end

  --]]

  -- fallback
  if R.outdoor then
    R.main_tex = rand.pick(LEVEL.courtyard_floors)
  else
    R.main_tex = rand.pick(LEVEL.building_walls)
  end
end

function Rooms_assign_facades()
  for i = 1,#LEVEL.all_rooms,4 do
    local R = LEVEL.all_rooms[i]
    R.facade = rand.pick(LEVEL.building_facades)
  end

  local visits = table.copy(LEVEL.all_rooms)

  for loop = 1,10 do
    local changes = false

    rand.shuffle(visits);

    for _,R in ipairs(visits) do
      if R.facade then
        for _,N in ipairs(R.neighbors) do
          if not N.facade then 
            N.facade = R.facade
            changes = true
          end
        end -- for N
      elseif rand.odds(loop * loop) then
        R.facade = rand.pick(LEVEL.building_facades)
      end
    end -- for R
  end -- for loop

  for _,R in ipairs(LEVEL.all_rooms) do
    assert(R.facade)
  end

  for _,R in ipairs(LEVEL.scenic_rooms) do
    if not R.facade then
      R.facade = rand.pick(LEVEL.building_facades)
    end
  end
end

function Rooms_choose_themes()
  for _,R in ipairs(LEVEL.all_rooms) do
    Rooms_setup_theme(R)
  end
  for _,R in ipairs(LEVEL.scenic_rooms) do
    Rooms_setup_theme_Scenic(R)
  end

  Rooms_assign_facades()
end


function Rooms_decide_hallways()
  -- Marks certain rooms to be hallways, using the following criteria:
  --   - indoor non-leaf room
  --   - prefer small rooms
  --   - prefer all neighbors are indoor
  --   - no purpose (not a start room, exit room, key room)
  --   - no teleporters
  --   - not the destination of a locked door (anti-climactic)

  local HALL_SIZE_PROBS = { 98, 84, 60, 40, 20, 10 }
  local HALL_SIZE_HEAPS = { 98, 95, 90, 70, 50, 30 }
  local REVERT_PROBS    = {  0,  0, 25, 75, 90, 98 }

  local function eval_hallway(R)
    if R.outdoor or R.natural or R.children or R.purpose then
      return false
    end

    if R.shape ~= "rect" then return false end  -- Fixme??

    if #R.teleports > 0 then return false end
    if R.num_branch < 2 then return false end
    if R.num_branch > 4 then return false end

    local outdoor_chance = 5
    local lock_chance    = 50

    if STYLE.hallways == "heaps" then
      outdoor_chance = 50
      lock_chance = 90
    end

    for _,C in ipairs(R.conns) do
      local N = C:neighbor(R)
      if N.outdoor and not rand.odds(outdoor_chance) then
        return false
      end

      if C.dest == R and C.lock and not rand.odds(lock_chance) then
        return false
      end
    end

    local min_d = math.min(R.sw, R.sh)

    if min_d > 6 then return false end

    if STYLE.hallways == "heaps" then
      return rand.odds(HALL_SIZE_HEAPS[min_d])
    end

    if STYLE.hallways == "few" and rand.odds(66) then
      return false end

    return rand.odds(HALL_SIZE_PROBS[min_d])
  end

  local function hallway_neighbors(R)
    local hall_nb = 0
    for _,C in ipairs(R.conns) do
      local N = C:neighbor(R)
      if N.hallway then hall_nb = hall_nb + 1 end
    end

    return hall_nb
  end

  local function surrounded_by_halls(R)
    local hall_nb = hallway_neighbors(R)
    return (hall_nb == #R.conns) or (hall_nb >= 3)
  end

  local function stairwell_neighbors(R)
    local swell_nb = 0
    for _,C in ipairs(R.conns) do
      local N = C:neighbor(R)
      if N.stairwell then swell_nb = swell_nb + 1 end
    end

    return swell_nb
  end

  local function locked_neighbors(R)
    local count = 0
    for _,C in ipairs(R.conns) do
      if C.lock then count = count + 1 end
    end

    return count
  end


  ---| Rooms_decide_hallways |---

  if not THEME.hallway_walls then
    gui.printf("Hallways disabled (no theme info)\n")
    return
  end

  if STYLE.hallways == "none" then
    return
  end

  for _,R in ipairs(LEVEL.all_rooms) do
    if eval_hallway(R) then
gui.debugf("  Made Hallway @ %s\n", R:tostr())
      R.kind = "hallway"
      R.hallway = { }
      R.outdoor = nil
    end
  end

  -- large rooms which are surrounded by hallways are wasted,
  -- hence look for them and revert them back to normal.
  for _,R in ipairs(LEVEL.all_rooms) do
    if R.hallway and surrounded_by_halls(R) then
      local min_d = math.min(R.sw, R.sh)

      assert(min_d <= 6)

      if rand.odds(REVERT_PROBS[min_d]) then
        R.kind = "normal"
        R.hallway = nil
gui.debugf("Reverted HALLWAY @ %s\n", R:tostr())
      end
    end
  end

  -- decide stairwells
  for _,R in ipairs(LEVEL.all_rooms) do
    if R.hallway and R.num_branch == 2 and
       not R.purpose and not R.weapon and
       stairwell_neighbors(R) == 0 and
       locked_neighbors(R) == 0 and
       THEME.stairwell_walls
    then
      local hall_nb = hallway_neighbors(R) 

      local prob = 80
      if hall_nb >= 2 then prob = 2  end
      if hall_nb == 1 then prob = 40 end

      if rand.odds(prob) then
        gui.printf("  Made Stairwell @ %s\n", R:tostr())
        R.kind = "stairwell"
      end
    end
  end -- for R

  -- we don't need archways where two hallways connect
--[[   ???
  for _,C in ipairs(LEVEL.all_conns) do
    if not C.lock and C.src.hallway and C.dest.hallway then
      local S = C.src_S
      local T = C.dest_S
      local dir = S.conn_dir

      if S.border[S.conn_dir].kind == "arch" or
         T.border[T.conn_dir].kind == "arch"
      then
        S.border[S.conn_dir].kind = "nothing"
        T.border[T.conn_dir].kind = "nothing"
      end
    end
  end -- for C
--]]
end


function Rooms_setup_symmetry()
  -- The 'symmetry' field of each room already has a value
  -- (from the big-branch connection system).  Here we choose
  -- whether to keep that, expand it (rare) or discard it.
  --
  -- The new value applies to everything made in the room
  -- (as much as possible) from now on.

  local function prob_for_match(old_sym, new_sym)
    if old_sym == new_sym then
      return sel(old_sym == "xy", 8000, 400)

    elseif new_sym == "xy" then
      -- rarely upgrade from NONE --> XY symmetry
      return sel(old_sym, 30, 3)

    elseif old_sym == "xy" then
      return 150

    else
      -- rarely change from X --> Y or vice versa
      return sel(old_sym, 6, 60)
    end
  end

  local function prob_for_size(R, new_sym)
    local prob = 200

    if new_sym == "x" or new_sym == "xy" then
      if R.sw <= 2 then return 0 end
      if R.sw <= 4 then prob = prob / 2 end

      if R.sw > R.sh * 3.1 then return 0 end
      if R.sw > R.sh * 2.1 then prob = prob / 3 end
    end

    if new_sym == "y" or new_sym == "xy" then
      if R.sh <= 2 then return 0 end
      if R.sh <= 4 then prob = prob / 2 end

      if R.sh > R.sw * 3.1 then return 0 end
      if R.sh > R.sw * 2.1 then prob = prob / 3 end
    end

    return prob
  end

  local function decide_layout_symmetry(R)
    R.conn_symmetry = R.symmetry

    -- We discard 'R' rotate and 'T' transpose symmetry (for now...)
    if not (R.symmetry == "x" or R.symmetry == "y" or R.symmetry == "xy") then
      R.symmetry = nil
    end

    if STYLE.symmetry == "none" then return end

    local SYM_LIST = { "x", "y", "xy" }

    local syms  = { "none" }
    local probs = { 100 }

    if STYLE.symmetry == "few"   then probs[1] = 500 end
    if STYLE.symmetry == "heaps" then probs[1] = 10  end

    for _,sym in ipairs(SYM_LIST) do
      local p1 = prob_for_size(R, sym)
      local p2 = prob_for_match(R.symmetry, sym)

      if p1 > 0 and p2 > 0 then
        table.insert(syms, sym)
        table.insert(probs, p1*p2/100)
      end
    end

    local index = rand.index_by_probs(probs)

    R.symmetry = sel(index > 1, syms[index], nil)
  end

  local function mirror_horizontally(R)
    if R.sw >= 2 then
      for y = R.sy1, R.sy2 do
        for dx = 0, int((R.sw-2) / 2) do
          local LS = SEEDS[R.sx1 + dx][y]
          local RS = SEEDS[R.sx2 - dx][y]

          if LS.room == R and RS.room == R then
            LS.x_peer = RS
            RS.x_peer = LS
          end
        end
      end
    end
  end

  local function mirror_vertically(R)
    if R.sh >= 2 then
      for x = R.sx1, R.sx2 do
        for dy = 0, int((R.sh-2) / 2) do
          local BS = SEEDS[x][R.sy1 + dy]
          local TS = SEEDS[x][R.sy2 - dy]

          if BS.room == R and TS.room == R then
            BS.y_peer = TS
            TS.y_peer = BS
          end
        end
      end
    end
  end


  --| Rooms_setup_symmetry |--

  for _,R in ipairs(LEVEL.all_rooms) do
    decide_layout_symmetry(R)

    gui.debugf("Final symmetry @ %s : %s --> %s\n", R:tostr(),
               tostring(R.conn_symmetry), tostring(R.symmetry))

    if R.symmetry == "x" or R.symmetry == "xy" then
      R.mirror_x = true
    end

    if R.symmetry == "y" or R.symmetry == "xy" then
      R.mirror_y = true
    end

    -- we ALWAYS setup the x_peer / y_peer refs
    mirror_horizontally(R)
    mirror_vertically(R)
  end
end


function Rooms_place_doors()
  local DEFAULT_PROBS = {}

  local function door_chance(R1, R2)
    local door_probs = THEME.door_probs or
                       GAME.door_probs or
                       DEFAULT_PROBS

    if R1.outdoor and R2.outdoor then
      return door_probs.out_both or 0

    elseif R1.outdoor or R2.outdoor then
      return door_probs.out_diff or 80

    elseif R1.kind == "stairwell" or R2.kind == "stairwell" then
      return door_probs.stairwell or 1

    elseif R1.hallway and R2.hallway then
      return door_probs.hall_both or 2

    elseif R1.hallway or R2.hallway then
      return door_probs.hall_diff or 60

    elseif R1.main_tex ~= R2.main_tex then
      return door_probs.combo_diff or 40

    else
      return door_probs.normal or 20
    end
  end

  local function validate_spot(S, N, side)
    if S:has_any_conn() or N:has_any_conn() then
      error("Failure adding door into room!")
    end

    assert(not S.border[side])
    assert(not N.border[10-side])
  end

  local function place_door(R, C)
    local K    = C.K1
    local side = assert(C.dir)

    -- centre the door on the section's side
    local x, y

    if geom.is_vert(C.dir) then
      x = K.sx1 + int((K.sw - 1) / 2)
      y = sel(C.dir == 2, K.sy1, K.sy2)
    else
      y = K.sy1 + int((K.sh - 1) / 2)
      x = sel(C.dir == 4, K.sx1, K.sx2)
    end

    -- NOTE: when rooms become small and the width and/or height is only
    --       two seeds, then placing doors becomes problematic, since we
    --       only want a single door per seed.
    --
    --       The solution is to place the doors in a certain pattern which
    --       is guaranteed to always work.  If you consider the map as a
    --       chess board, then a north-going door is placed on top-left
    --       seed on white squares, but top-right on black squares, and
    --       similarly for the other directions.
    --
    --       Once all the doors are placed, they can be moved to other
    --       locations or made wider where possible.

    local SQ = bit.band(K.kx + K.ky, 1)

    if C.dir == 8 then x = x + SQ end
    if C.dir == 2 then x = x + 1 - SQ end
    if C.dir == 4 then y = y + SQ end
    if C.dir == 6 then y = y + 1 - SQ end


    local nx, ny = geom.nudge(x, y, C.dir)

    local S = SEEDS[x][y]
    local N = SEEDS[nx][ny]

    validate_spot(S, N, side)

    local B1 = S:add_border(side, "arch", 24)
    local B2 = N:add_border(10-side, "straddle", 24)

    B1.conn = C
    B2.conn = C

    if C.lock then
      B1.kind = sel(C.lock.kind == "BARS", "bars", "lock_door")
      B1.lock = C.lock
    end

    C.already_placed = true
  end


  ---| Rooms_place_doors |---

  for _,R in ipairs(LEVEL.all_rooms) do
    for _,C in ipairs(R.conns) do
      if C.kind == "normal" and not C.already_placed then
        place_door(R, C)
      end
    end
  end

  -- !!!! FIXME: code to move or WIDEN doors

--[[  OLD CODE

  for _,C in ipairs(LEVEL.all_conns) do
    for who = 1,2 do
      local S = sel(who == 1, C.src_S, C.dest_S)
      local N = sel(who == 2, C.src_S, C.dest_S)
      assert(S)

      if S.conn_dir then
        assert(N.conn_dir == 10-S.conn_dir)

        local B  = S.border[S.conn_dir]
        local B2 = N.border[N.conn_dir]

        -- ensure when going from outside to inside that the arch/door
        -- is made using the building combo (NOT the outdoor combo)
        if B.kind == "arch" and
           ((S.room.outdoor and not N.room.outdoor) or
            (S.room == N.room.parent))
        then
          -- swap borders
          S, N = N, S

          S.border[S.conn_dir] = B
          N.border[N.conn_dir] = B2
        end

        if B.kind == "arch" and GAME.DOORS and not B.tried_door then
          B.tried_door = true

          local prob = door_chance(C.src, C.dest)

          if S.conn.lock and S.conn.lock.kind ~= "NULL" then
            B.kind = "lock_door"
            B.lock = S.conn.lock

            -- FIXME: smells like a hack!!
            if B.lock.item and string.sub(B.lock.item, 1, 4) == "bar_" then
              B.kind = "bars"
            end

          elseif rand.odds(prob) then
            B.kind = "door"

          elseif (STYLE.fences == "none" or STYLE.fences == "few") and
                 C.src.outdoor and C.dest.outdoor then
            B.kind = "nothing"
          end
        end

      end
    end -- for who
  end -- for C

--]]
end


function Rooms_synchronise_skies()
  -- make sure that any two outdoor rooms which touch have the same sky_h

  for loop = 1,10 do
    local changes = false

    for x = 1,SEED_W do for y = 1,SEED_H do
      local S = SEEDS[x][y]
      if S and S.room and S.room.sky_h then
        for side = 2,8,2 do
          local N = S:neighbor(side)
          if N and N.room and N.room ~= S.room and N.room.sky_h and
             S.room.sky_h ~= N.room.sky_h
          then
            S.room.sky_h = math.max(S.room.sky_h, N.room.sky_h)
            N.room.sky_h = S.room.sky_h
            changes = true
          end
        end -- for side
      end
    end end -- for x, y

    if not changes then break; end
  end -- for loop
end


function Rooms_border_up()

  local function make_map_edge(R, S, side)
    if R.outdoor then
      -- a fence will be created by Layout_edge_of_map()
    else
      S:add_border(side, "wall", 24)

      S.border[side].at_edge = true
    end
  end

  local function make_border(R1, S, R2, N, side)
    if R1 == R2 then
      return -- same room : do nothing
    end

    if R1.outdoor and R2.natural then
      S:add_border(side, "fence", 24)

    elseif R1.natural and R2.outdoor then

      if S:has_any_conn() then
        S:add_border(side, "wall", 24)
      end

      return -- usually nothing

    elseif R1.outdoor then
      if N.kind == "liquid" and R2.outdoor and
        (S.kind == "liquid" or R1.quest == R2.quest)
        --!!! or (N.room.kind == "scenic" and safe_falloff(S, side))
      then
        return -- nothing
      end

      if R2.outdoor or R2.natural then
        S:add_border(side, "fence", 24)
      end

    else -- R1 indoor

      if R2.parent == R1 and not R2.outdoor then
        return -- nothing
      end

      S:add_border(side, "wall", 24)

      -- liquid arches are a kind of window
      if S.kind == "liquid" and N.kind == "liquid" and
         (S.floor_h == N.floor_h)  --- and rand.odds(50)
      then
        S.border[side].kind = "liquid_arch"
---!!!        N.border[10-side].kind = "straddle"
        return
      end
    end
  end


  local function border_up(R)
    for x = R.sx1, R.sx2 do for y = R.sy1, R.sy2 do
      local S = SEEDS[x][y]
      if S.room == R then

        for side = 2,8,2 do
          if not S.border[side] then  -- don't clobber connections
            local N = S:neighbor(side)
  
            if not (N and N.room) then
              make_map_edge(R, S, side)
            else
              make_border(R, S, N.room, N, side)
            end
          end
        end -- for side

      end
    end end -- for x, y
  end


  local function get_border_list(R)
    local list = {}

    for x = R.sx1, R.sx2 do for y = R.sy1, R.sy2 do
      local S = SEEDS[x][y]
      if S.room == R and not
         (S.kind == "void" or S.kind == "diagonal" or
          S.kind == "tall_stair")
      then
        for side = 2,8,2 do
          if S.border[side] and S.border[side].kind == "wall" then
            table.insert(list, { S=S, side=side })
          end
        end -- for side
      end
    end end -- for x, y

    return list
  end

  local function score_window_side(R, side, border_list)
    local min_c1, max_f1 = 999, -999
    local min_c2, max_f2 = 999, -999

    local total   = 0
    local scenics = 0
    local doors   = 0
    local futures = 0
    local entry   = 0

    local info = { side=side, seeds={} }

    for _,C in ipairs(R.conns) do

      if C:what_dir(R) == side then
        -- never any windows near a locked door
        if C.lock then
          return nil
        end

        if C.kind == "normal" then
          doors = doors + 1
        end

        if C == R.entry_conn then
          entry = 1
        end
      end
    end


    for _,bd in ipairs(border_list) do
      local S = bd.S
      local N = S:neighbor(side)

      total = total + 1

      if (bd.side == side) and S.floor_h and
         (N and N.room and N.room.outdoor) and N.floor_h
      -- (N.kind == "walk" or N.kind == "liquid")
      then
        table.insert(info.seeds, S)

        if N.kind == "scenic" then
          scenics = scenics + 1
        end

        if S.room.quest and N.room.quest and (S.room.quest.id < N.room.quest.id) then
          futures = futures + 1
        end
        
        min_c1 = math.min(min_c1, assert(S.ceil_h or R.ceil_h))
        min_c2 = SKY_H

        max_f1 = math.max(max_f1, S.floor_h)
        max_f2 = math.max(max_f2, N.floor_h)

        if N.room.natural then
          max_f2 = math.max(max_f2, N.room.cave_floor_h + 128)
        end
      end 
    end  -- for bd


    -- nothing possible??
    local usable = #info.seeds

    if usable == 0 then return end

    local min_c = math.min(min_c1, min_c2)
    local max_f = math.max(max_f1, max_f2)

    if min_c - max_f < 95 then return end

    local score = 200 + gui.random() * 20

    -- primary score is floor drop off
    score = score + (max_f1 - max_f2)

    score = score + (min_c  - max_f) / 8
    score = score - usable * 22

    if scenics >= 1 then score = score + 120 end
    if entry   == 0 then score = score + 60 end

    if doors   == 0 then score = score + 20 end
    if futures == 0 then score = score + 10 end

    gui.debugf("Window score @ %s ^%d --> %d\n", R:tostr(), side, score)

    info.score = score


    -- implement the window style
    if (STYLE.windows == "few"  and score < 350) or
       (STYLE.windows == "some" and score < 260)
    then
      return nil
    end


    -- determine height of window
    if (min_c - max_f) >= 192 and rand.odds(20) then
      info.z1 = max_f + 64
      info.z2 = min_c - 64
      info.is_tall = true
    elseif (min_c - max_f) >= 160 and rand.odds(60) then
      info.z1 = max_f + 32
      info.z2 = min_c - 24
      info.is_tall = true
    elseif (max_f1 < max_f2) and rand.odds(30) then
      info.z1 = min_c - 80
      info.z2 = min_c - 32
    else
      info.z1 = max_f + 32
      info.z2 = max_f + 80
    end

    -- determine width & doubleness
    local thin_chance = math.min(6, usable) * 20 - 40
    local dbl_chance  = 80 - math.min(3, usable) * 20

    if usable >= 3 and rand.odds(thin_chance) then
      info.width = 64
    elseif usable <= 3 and rand.odds(dbl_chance) then
      info.width = 192
      info.mid_w = 64
    elseif info.is_tall then
      info.width = rand.sel(80, 128, 192)
    else
      info.width = rand.sel(20, 128, 192)
    end

    if info.width > SEED_SIZE-32 then
       info.width = SEED_SIZE-32
    end

    return info
  end

  local function add_windows(R, info, border_list)
    local side = info.side

    for _,S in ipairs(info.seeds) do
      S.border[side].kind = "window"

      S.border[side].win_width = info.width
      S.border[side].win_mid_w = info.mid_w
      S.border[side].win_z1    = info.z1
      S.border[side].win_z2    = info.z2

      local N = S:neighbor(side)
      assert(N and N.room)

---!?!?      N.border[10-side].kind = "nothing"
    end -- for S
  end

  local function pick_best_side(poss)
    local best

    for side = 2,8,2 do
      if poss[side] and (not best or poss[best].score < poss[side].score) then
        best = side
      end
    end

    return best
  end

  local function decide_windows(R, border_list)
    if R.outdoor or R.natural or R.kind ~= "normal" then return end
    if R.semi_outdoor then return end
    if STYLE.windows == "none" then return end

    local poss = {}

    for side = 2,8,2 do
      poss[side] = score_window_side(R, side, border_list)
    end

    for loop = 1,2 do
      local best = pick_best_side(poss)

      if best then
        add_windows(R, poss[best], border_list)

        poss[best] = nil

        -- remove the opposite side too
        poss[10-best] = nil
      end
    end
  end


  local function select_picture(R, v_space, index)
    v_space = v_space - 16
    -- FIXME: needs more v_space checking

    if THEME.logos and rand.odds(sel(LEVEL.has_logo,7,40)) then
      LEVEL.has_logo = true
      return rand.key_by_probs(THEME.logos)
    end

    if R.has_liquid and index == 1 and rand.odds(75) then
      if THEME.liquid_pics then
        return rand.key_by_probs(THEME.liquid_pics)
      end
    end

    local pic_tab = {}

    local pictures = THEME.pictures

    if pictures then
      for name,prob in pairs(pictures) do
        local info = GAME.PICTURES[name]
        if info and info.height <= v_space then
          pic_tab[name] = prob
        end
      end
    end

    if not table.empty(pic_tab) then
      return rand.key_by_probs(pic_tab)
    end

    return nil  -- failed
  end

  local function install_pic(R, bd, pic_name, v_space)
    skin = assert(GAME.PICTURES[pic_name])

    -- handles symmetry

    for dx = 1,sel(R.mirror_x, 2, 1) do
      for dy = 1,sel(R.mirror_y, 2, 1) do
        local S    = bd.S
        local side = bd.side

        if dx == 2 then
          S = S.x_peer
          if not S then break; end
          if geom.is_horiz(side) then side = 10-side end
        end

        if S and dy == 2 then
          S = S.y_peer
          if not S then break; end
          if geom.is_vert(side) then side = 10-side end
        end

        local B = S.border[side]

        if B and B.kind == "wall" and S.floor_h then
          local raise = skin.raise or 32
          if raise + skin.height > v_space-4 then
            raise = int((v_space - skin.height) / 2)
          end
          B.kind = "picture"
          B.pic_skin = skin
          B.pic_z1 = S.floor_h + raise
        end

      end -- for dy
    end -- for dx
  end

  local function decide_pictures(R, border_list)
    if R.outdoor or R.natural or R.kind ~= "normal" then return end
    if R.semi_outdoor then return end
-- do return end --!!!!!!!!!1

    -- filter border list to remove symmetrical peers, seeds
    -- with pillars, etc..  Also determine vertical space.
    local new_list = {}

    local v_space = 999

    for _,bd in ipairs(border_list) do
      local S = bd.S
      local side = bd.side

      if (R.mirror_x and S.x_peer and S.sx > S.x_peer.sx) or
         (R.mirror_y and S.y_peer and S.sy > S.y_peer.sy) or
         (S.usage == "pillar") or (S.kind == "lift")
      then
        -- skip it
      else
        table.insert(new_list, bd)

        local h = (S.ceil_h or R.ceil_h) - S.floor_h
        v_space = math.min(v_space, h)
      end
    end

    if #new_list == 0 then return end


    -- deice how many pictures we want
    local perc = rand.pick { 20,30,40 }

    if STYLE.pictures == "heaps" then perc = 50 end
    if STYLE.pictures == "few"   then perc = 10 end

    -- FIXME: support "none" but also force logos to appear
    if STYLE.pictures == "none"  then perc =  7 end

    local count = int(#border_list * perc / 100)

    gui.debugf("Picture count @ %s --> %d\n", R:tostr(), count)

    if R.mirror_x then count = int(count / 2) + 1 end
    if R.mirror_y then count = int(count / 2) end


    -- select one or two pictures to use
    local pics = {}
    pics[1] = select_picture(R, v_space, 1)

    if not pics[1] then return end

    if #border_list >= 12 then
      -- prefer a different pic for #2
      for loop = 1,3 do
        pics[2] = select_picture(R, v_space, 2)
        if pics[2] and pics[2].pic_w ~= pics[1].pic_w then break; end
      end
    end

    if not pics[2] then pics[2] = pics[1] end

    gui.debugf("Selected pics: %s %s\n", pics[1], pics[2])


    for loop = 1,count do
      if #new_list == 0 then break; end

      -- FIXME !!!! SELECT GOOD SPOT
      local b_index = rand.irange(1, #new_list)

      local bd = table.remove(new_list, b_index)
      
      install_pic(R, bd, pics[1 + (loop-1) % 2], v_space)
    end -- for loop
  end


  ---| Rooms_border_up |---
  
  for _,R in ipairs(LEVEL.all_rooms) do
    border_up(R)
  end
  for _,R in ipairs(LEVEL.scenic_rooms) do
    border_up(R)
  end

  for _,R in ipairs(LEVEL.all_rooms) do
    decide_windows( R, get_border_list(R))
    decide_pictures(R, get_border_list(R))
  end
end


------------------------------------------------------------------------


function Rooms_make_ceiling(R)

  local function outdoor_ceiling()
    if R.floor_max_h then
      R.sky_h = math.max(R.sky or SKY_H, R.floor_max_h + 128)
    end
  end

  local function periph_size(PER)
    if PER[2] then return 3 end
    if PER[1] then return 2 end
    if PER[0] then return 1 end
    return 0
  end

  local function get_max_drop(side, offset)
    local drop_z
    local x1,y1, x2,y2 = geom.side_coords(side, R.tx1,R.ty1, R.tx2,R.ty2, offset)

    for x = x1,x2 do for y = y1,y2 do
      local S = SEEDS[x][y]
      if S.room == R then

        local f_h
        if S.kind == "walk" then
          f_h = S.floor_h
        elseif S.diag_new_kind == "walk" then
          f_h = S.diag_new_z or S.floor_h
        elseif S.kind == "stair" or S.kind == "lift" then
          f_h = math.max(S.stair_z1, S.stair_z2)
        elseif S.kind == "curve_stair" or S.kind == "tall_stair" then
          f_h = math.max(S.x_height, S.y_height)
        end

        if f_h then
          local diff_h = (S.ceil_h or R.ceil_h) - (f_h + 144)

          if diff_h < 1 then return nil end

          if not drop_z or (diff_h < drop_z) then
            drop_z = diff_h
          end
        end
      end
    end end -- for x, y

    return drop_z
  end

  local function add_periph_pillars(side, offset)
-- do return end --!!!!!!!!
    if not THEME.periph_pillar_mat then
      return
    end

    local info = add_pegging(get_mat(THEME.periph_pillar_mat))

    local x1,y1, x2,y2 = geom.side_coords(side, R.tx1,R.ty1, R.tx2,R.ty2, offset)

    if geom.is_vert(side) then x2 = x2-1 else y2 = y2-1 end

    local x_dir = sel(side == 6, -1, 1)
    local y_dir = sel(side == 8, -1, 1)

    for x = x1,x2 do for y = y1,y2 do
      local S = SEEDS[x][y]

      -- check if all neighbors are in same room
      local count = 0

      for dx = 0,1 do for dy = 0,1 do
        local nx = x + dx * x_dir
        local ny = y + dy * y_dir

        if Seed_valid(nx, ny) and SEEDS[nx][ny].room == R then
          count = count + 1
        end
      end end -- for dx,dy

      if count == 4 then
        local w = 12

        local px = sel(x_dir < 0, S.x1, S.x2)
        local py = sel(y_dir < 0, S.y1, S.y2)

        Trans.old_quad(info, px-w, py-w, px+w, py+w, -EXTREME_H, EXTREME_H)
        
        R.has_periph_pillars = true

        -- mark seeds [crude way to prevent stuck masterminds]
        for dx = 0,1 do for dy = 0,1 do
          local nx = x + dx * x_dir
          local ny = y + dy * y_dir

          SEEDS[nx][ny].solid_corner = true
        end end -- for dx,dy
      end
    end end -- for x, y
  end

  local function create_periph_info(side, offset)
    local t_size = sel(geom.is_horiz(side), R.tw, R.th)

    if t_size < (3+offset*2) then return nil end

    local drop_z = get_max_drop(side, offset)

    if not drop_z or drop_z < 30 then return nil end

    local PER = { max_drop=drop_z }

    if t_size == (3+offset*2) then
      PER.tight = true
    end

    if R.pillar_rows then
      for _,row in ipairs(R.pillar_rows) do
        if row.side == side and row.offset == offset then
          PER.pillars = true
        end
      end
    end

    return PER
  end

  local function merge_periphs(side, offset)
    local P1 = R.periphs[side][offset]
    local P2 = R.periphs[10-side][offset]

    if not (P1 and P2) then return nil end

    if P1.tight and rand.odds(90) then return nil end

    return
    {
      max_drop = math.min(P1.max_drop, P2.max_drop),
      pillars  = P1.pillars or P2.pillars
    }
  end

  local function decide_periphs()
    -- a "periph" is a side of the room where we might lower
    -- the ceiling height.  There is a "outer" one (touches the
    -- wall) and an "inner" one (next to the outer one).

    R.periphs = {}

    for side = 2,8,2 do
      R.periphs[side] = {}

      for offset = 0,2 do
        local PER = create_periph_info(side, offset)
        R.periphs[side][offset] = PER
      end
    end


    local SIDES = { 2,4 }
    if (R.th > R.tw) or (R.th == R.tw and rand.odds(50)) then
      SIDES = { 4,2 }
    end
    if rand.odds(10) then  -- swap 'em
      SIDES[1], SIDES[2] = SIDES[2], SIDES[1]
    end

    for idx,side in ipairs(SIDES) do
      if (R.symmetry == "xy" or R.symmetry == sel(side==2, "y", "x")) or
         R.pillar_rows and geom.is_parallel(R.pillar_rows[1].side, side) or
         rand.odds(50)
      then
        --- Symmetrical Mode ---

        local PER_0 = merge_periphs(side, 0)
        local PER_1 = merge_periphs(side, 1)

        if PER_0 and PER_1 and rand.odds(sel(PER_1.pillars, 70, 10)) then
          PER_0 = nil
        end

        if PER_0 then PER_0.drop_z = PER_0.max_drop / idx end
        if PER_1 then PER_1.drop_z = PER_1.max_drop / idx / 2 end

        R.periphs[side][0] = PER_0 ; R.periphs[10-side][0] = PER_0
        R.periphs[side][1] = PER_1 ; R.periphs[10-side][1] = PER_1
        R.periphs[side][2] = nil   ; R.periphs[10-side][2] = nil

        if idx==1 and PER_0 and not R.pillar_rows and rand.odds(50) then
          add_periph_pillars(side)
          add_periph_pillars(10-side)
        end
      else
        --- Funky Mode ---

        -- pick one side to use   [FIXME]
        local keep = rand.sel(50, side, 10-side)

        for n = 0,2 do R.periphs[10-keep][n] = nil end

        local PER_0 = R.periphs[keep][0]
        local PER_1 = R.periphs[keep][1]

        if PER_0 and PER_1 and rand.odds(5) then
          PER_0 = nil
        end

        if PER_0 then PER_0.drop_z = PER_0.max_drop / idx end
        if PER_1 then PER_1.drop_z = PER_1.max_drop / idx / 2 end

        R.periphs[keep][2] = nil

        if idx==1 and PER_0 and not R.pillar_rows and rand.odds(75) then
          add_periph_pillars(keep)

        --??  if PER_1 and rand.odds(10) then
        --??    add_periph_pillars(keep, 1)
        --??  end
        end
      end
    end
  end

  local function calc_central_area()
    R.cx1, R.cy1 = R.tx1, R.ty1
    R.cx2, R.cy2 = R.tx2, R.ty2

    for side = 2,8,2 do
      local w = periph_size(R.periphs[side])

          if side == 4 then R.cx1 = R.cx1 + w
      elseif side == 6 then R.cx2 = R.cx2 - w
      elseif side == 2 then R.cy1 = R.cy1 + w
      elseif side == 8 then R.cy2 = R.cy2 - w
      end
    end

    R.cw, R.ch = geom.group_size(R.cx1, R.cy1, R.cx2, R.cy2)

    assert(R.cw >= 1)
    assert(R.ch >= 1)
  end

  local function install_periphs()
    for x = R.tx1, R.tx2 do for y = R.ty1, R.ty2 do
      local S = SEEDS[x][y]
      if S.room == R then
      
        local PX, PY

            if x == R.tx1   then PX = R.periphs[4][0]
        elseif x == R.tx2   then PX = R.periphs[6][0]
        elseif x == R.tx1+1 then PX = R.periphs[4][1]
        elseif x == R.tx2-1 then PX = R.periphs[6][1]
        elseif x == R.tx1+2 then PX = R.periphs[4][2]
        elseif x == R.tx2-2 then PX = R.periphs[6][2]
        end

            if y == R.ty1   then PY = R.periphs[2][0]
        elseif y == R.ty2   then PY = R.periphs[8][0]
        elseif y == R.ty1+1 then PY = R.periphs[2][1]
        elseif y == R.ty2-1 then PY = R.periphs[8][1]
        elseif y == R.ty1+2 then PY = R.periphs[2][2]
        elseif y == R.ty2-2 then PY = R.periphs[8][2]
        end

        if PX and not PX.drop_z then PX = nil end
        if PY and not PY.drop_z then PY = nil end

        if PX or PY then
          local drop_z = math.max((PX and PX.drop_z) or 0,
                                  (PY and PY.drop_z) or 0)

          S.ceil_h = R.ceil_h - drop_z
        end

      end -- if S.room == R
    end end -- for x, y
  end

  local function fill_xyz(ch, is_sky, c_tex, c_light)
    for x = R.cx1, R.cx2 do for y = R.cy1, R.cy2 do
      local S = SEEDS[x][y]
      if S.room == R then
      
        S.ceil_h  = ch
        S.is_sky  = is_sky
        S.c_tex   = c_tex
        S.c_light = c_light

      end -- if S.room == R
    end end -- for x, y
  end

  local function add_central_pillar()
    -- big rooms only
    if R.cw < 3 or R.ch < 3 then return end

    -- centred only
    if (R.cw % 2) == 0 or (R.ch % 2) == 0 then return end

    local skin_names = THEME.big_pillars or THEME.pillars
    if not skin_names then return end


    local mx = R.cx1 + int(R.cw / 2)
    local my = R.cy1 + int(R.ch / 2)

    local S = SEEDS[mx][my]

    -- seed is usable?
    if S.room ~= R or S.usage then return end
    if not (S.kind == "walk" or S.kind == "liquid") then return end

    -- neighbors the same?
    for side = 2,8,2 do
      local N = S:neighbor(side)
      if not (N and N.room == S.room and N.kind == S.kind) then
        return
      end
    end

    -- OK !!
    local which = rand.key_by_probs(skin_names)

    S.usage = "pillar"
    S.pillar_skin = assert(GAME.PILLARS[which])

    R.has_central_pillar = true

    gui.debugf("Central pillar @ (%d,%d) skin:%s\n", S.sx, S.sy, which)
  end

  local function central_niceness()
    local nice = 2

    for x = R.cx1, R.cx2 do for y = R.cy1, R.cy2 do
      local S = SEEDS[x][y]
      
      if S.room ~= R then return 0 end
      
      if S.kind == "void" or ---#  S.kind == "diagonal" or
         S.kind == "tall_stair" or S.usage == "pillar"
      then
        nice = 1
      end
    end end -- for x, y

    return nice
  end

  local function test_cross_beam(dir, x1,y1, x2,y2, mode)
    -- FIXME: count usable spots, return false for zero

    if R.shape ~= "rect" then return end  -- FIXME

    for x = x1,x2 do for y = y1,y2 do
      local S = SEEDS[x][y]
      assert(S.room == R)

      if S.kind == "lift" or S.kind == "tall_stair" or S.raising_start then
        return false
      end

      if mode == "light" and (S.kind == "diagonal") then
        return false
      end
    end end -- for x, y

    return true
  end

  local function add_cross_beam(dir, x1,y1, x2,y2, mode)
    local skin
    
    if mode == "light" then
      if not R.quest.ceil_light then return end
      skin = { glow=R.quest.ceil_light, trim=THEME.light_trim }
    end

    for x = x1,x2 do for y = y1,y2 do
      local S = SEEDS[x][y]
      local ceil_h = S.ceil_h or R.ceil_h

      if ceil_h and S.kind ~= "void" then
        if mode == "light" then
          if S.usage ~= "pillar" then
            local T = Trans.centre_transform(S, ceil_h, 2)  -- TODO; pick a dir
            if R.lite_w then T.scale_x = R.lite_w  / 64 end
            if R.lite_h then T.scale_y = R.lite_h  / 64 end

            Build.prefab("CEIL_LIGHT", skin, T)
          end
        else
          Build.cross_beam(S, dir, 64, ceil_h - 16, THEME.beam_mat)
        end
      end
    end end -- for x, y
  end

  local function decide_beam_pattern(poss, total, mode)
    if table.empty(poss) then return false end

    -- FIXME !!!
    return true
  end

  local function criss_cross_beams(mode)
    if not THEME.beam_mat then return false end

    if R.children then return false end

    R.lite_w = 64
    R.lite_h = 64

    local poss = {}

    if R.cw > R.ch or (R.cw == R.ch and rand.odds(50)) then
      -- vertical beams

      if rand.odds(20) then R.lite_h = 192 end
      if rand.odds(10) then R.lite_h = 128 end
      if rand.odds(30) then R.lite_h = R.lite_w end

      for x = R.cx1, R.cx2 do
        poss[x - R.cx1 + 1] = test_cross_beam(8, x, R.ty1, x, R.ty2, mode)
      end

      if not decide_beam_pattern(poss, R.cx2 - R.cx1 + 1, mode) then
        return false
      end

      for x = R.cx1, R.cx2 do
        if poss[x - R.cx1 + 1] then
          add_cross_beam(8, x, R.ty1, x, R.ty2)
        end
      end

    else -- horizontal beams

      if rand.odds(20) then R.lite_w = 192 end
      if rand.odds(10) then R.lite_w = 128 end
      if rand.odds(30) then R.lite_w = R.lite_h end

      for y = R.cy1, R.cy2 do
        poss[y - R.cy1 + 1] = test_cross_beam(6, R.tx1, y, R.tx2, y, mode)
      end

      if not decide_beam_pattern(poss, R.cy2 - R.cy1 + 1, mode) then
        return false
      end

      for y = R.cy1, R.cy2 do
        if poss[y - R.cy1 + 1] then
          add_cross_beam(6, R.tx1, y, R.tx2, y, mode)
        end
      end
    end

    return true
  end

  local function corner_supports()
    if not THEME.corner_supports then
      return false
    end

    local mat = rand.key_by_probs(THEME.corner_supports)

    local SIDES = { 1, 7, 3, 9 }

    -- first pass only checks if possible
    for loop = 1,2 do
      local poss = 0

      for where = 1,4 do
        local cx = sel((where <= 2), R.tx1, R.tx2)
        local cy = sel((where % 2) == 1, R.ty1, R.ty2)
        local S = SEEDS[cx][cy]
        if S.room == R and not S:has_any_conn() and
           (S.kind == "walk" or S.kind == "liquid")
        then

          poss = poss + 1

          if loop == 2 then
            local skin = { w=24, beam_w=mat, x_offset=0 }
            ---## if R.has_lift or (R.id % 5) == 4 then
            ---##   skin = { w=24, beam_w="SUPPORT3", x_offset=0 }
            ---## end
            Build.corner_beam(S, SIDES[where], skin)
          end

        end
      end

      if poss < 3 then return false end
    end

    return true
  end

  local function do_central_area()
    calc_central_area()

    local has_sky_nb = R:has_sky_neighbor()

    if R.has_periph_pillars and not has_sky_nb and rand.odds(16) then
      fill_xyz(R.ceil_h, true)
      R.semi_outdoor = true
      return
    end

    
    -- temporary lighting stuff for Quake
    if true then
      local x1 = SEEDS[R.tx1][R.ty1].x1
      local y1 = SEEDS[R.tx1][R.ty1].y1
      local x2 = SEEDS[R.tx2][R.ty2].x2
      local y2 = SEEDS[R.tx2][R.ty2].y2

      local z1 = SEEDS[R.tx1][R.ty1].floor_h or 128
      local z2 = SEEDS[R.tx1][R.ty1].ceil_h  or 512

      Trans.entity("light", (x1+x2)/2, (y1+y2)/2, (z1+z2)/2, { light=160, _radius=720 })
    end


    if (R.tw * R.th) <= 18 and rand.odds(20) then
      if corner_supports() and rand.odds(35) then return end
    end


    if not R.quest.ceil_light and THEME.ceil_lights then
      R.quest.ceil_light = rand.key_by_probs(THEME.ceil_lights)
    end

    local beam_chance = style_sel("beams", 0, 5, 25, 75)

    if rand.odds(beam_chance) then
      if criss_cross_beams("beam") then return end
    end

    if rand.odds(42) then
      if criss_cross_beams("light") then return end
    end


    -- shrink central area until there are nothing which will
    -- get in the way of a ceiling prefab.
    local nice = central_niceness()

gui.debugf("Original @ %s over %dx%d -> %d\n", R:tostr(), R.cw, R.ch, nice)

    while nice < 2 and (R.cw >= 3 or R.ch >= 3) do
      
      if R.cw > R.ch or (R.cw == R.ch and rand.odds(50)) then
        assert(R.cw >= 3)
        R.cx1 = R.cx1 + 1
        R.cx2 = R.cx2 - 1
      else
        assert(R.ch >= 3)
        R.cy1 = R.cy1 + 1
        R.cy2 = R.cy2 - 1
      end

      R.cw, R.ch = geom.group_size(R.cx1, R.cy1, R.cx2, R.cy2)

      nice = central_niceness()
    end
      
gui.debugf("Niceness @ %s over %dx%d -> %d\n", R:tostr(), R.cw, R.ch, nice)


    add_central_pillar()

    if nice ~= 2 or not THEME.big_lights then return end

      local ceil_info  = get_mat(R.main_tex)
      local sky_info   = get_sky()
      local brown_info = get_mat(rand.key_by_probs(THEME.building_ceilings))

      local light_name = rand.key_by_probs(THEME.big_lights)
      local light_info = get_mat(light_name)
      light_info.b_face.light = 0.85

      -- lighting effects
      -- (They can break lifts, hence the check here)
      if not R.has_lift then
            if rand.odds(10) then light_info.sec_kind = 8
        elseif rand.odds(6)  then light_info.sec_kind = 3
        elseif rand.odds(3)  then light_info.sec_kind = 2
        end
      end

    local trim   = THEME.ceiling_trim
    local spokes = THEME.ceiling_spoke

    if STYLE.lt_swapped ~= "none" then
      trim, spokes = spokes, trim
    end

    if STYLE.lt_trim == "none" or (STYLE.lt_trim == "some" and rand.odds(50)) then
      trim = nil
    end
    if STYLE.lt_spokes == "none" or (STYLE.lt_spokes == "some" and rand.odds(70)) then
      spokes = nil
    end

    if R.cw == 1 or R.ch == 1 then
      fill_xyz(R.ceil_h+32, false, light_name, 0.75)
      return
    end

    local shape = rand.sel(30, "square", "round")

    local w = 96 + 140 * (R.cw - 1)
    local h = 96 + 140 * (R.ch - 1)
    local z = (R.cw + R.ch) * 8

    Build.sky_hole(R.cx1,R.cy1, R.cx2,R.cy2, shape, w, h,
                   ceil_info, R.ceil_h,
                   sel(not has_sky_nb and not R.parent and rand.odds(60), sky_info,
                       rand.sel(75, light_info, brown_info)), R.ceil_h + z,
                   trim, spokes)
  end

  local function indoor_ceiling()
    if R.natural or R.kind ~= "normal" then
      return
    end

    assert(R.floor_max_h)

    local avg_h = int((R.floor_min_h + R.floor_max_h) / 2)
    local min_h = R.floor_max_h + 128

    local tw = R.tw or R.sw
    local th = R.th or R.sh

    local approx_size = (2 * math.min(tw, th) + math.max(tw, th)) / 3.0
    local tallness = (approx_size + rand.range(-0.6,1.6)) * 64.0

    if tallness < 128 then tallness = 128 end
    if tallness > 448 then tallness = 448 end

    R.tallness = int(tallness / 32.0) * 32

    gui.debugf("Tallness @ %s --> %d\n", R:tostr(), R.tallness)
 
    R.ceil_h = math.max(min_h, avg_h + R.tallness)

    R.ceil_tex = rand.key_by_probs(THEME.building_ceilings)

-- [[
    decide_periphs()
    install_periphs()

    do_central_area()
--]]

--[[
    if R.tx1 and R.tw >= 7 and R.th >= 7 then

      Build.sky_hole(R.tx1,R.ty1, R.tx2,R.ty2,
                     "round", w, h,
                     outer_info, R.ceil_h,
                     nil, R.ceil_h , ---  + z,
                     metal, nil)

      w = 96 + 110 * (R.tx2 - R.tx1 - 4)
      h = 96 + 110 * (R.ty2 - R.ty1 - 4)

      outer_info.b_face.tex = "F_SKY1"
      outer_info.b_face.light = 0.8

      Build.sky_hole(R.tx1+2,R.ty1+2, R.tx2-2,R.ty2-2,
                     "round", w, h,
                     outer_info, R.ceil_h + 96,
                     inner_info, R.ceil_h + 104,
                     metal, silver)
    end

    if R.tx1 and R.tw == 4 and R.th == 4 then
      local w = 256
      local h = 256

      for dx = 0,1 do for dy = 0,0 do
        local tx1 = R.tx1 + dx * 2
        local ty1 = R.ty1 + dy * 2

        local tx2 = R.tx1 + dx * 2 + 1
        local ty2 = R.ty1 + dy * 2 + 3

        Build.sky_hole(tx1,ty1, tx2,ty2,
                       "square", w, h,
                       outer_info, R.ceil_h,
                       inner_info, R.ceil_h + 36,
                       metal, metal)
      end end -- for dx, dy
    end

    if R.tx1 and (R.tw == 3 or R.tw == 5) and (R.th == 3 or R.th == 5) then
      for x = R.tx1+1, R.tx2-1, 2 do
        for y = R.ty1+1, R.ty2-1, 2 do
          local S = SEEDS[x][y]
          if not (S.kind == "void" or S.kind == "diagonal") then
            Build.sky_hole(x,y, x,y, "square", 160,160,
                           metal,      R.ceil_h+16,
                           inner_info, R.ceil_h+32,
                           nil, silver)
          end
        end -- for y
      end -- for x
    end
--]]
  end


  ---| Rooms_make_ceiling |---

  if R.outdoor then
    outdoor_ceiling()
  else
    indoor_ceiling()
  end
end


function Rooms_add_crates(R)

  -- NOTE: temporary crap!
  -- (might be slightly useful for finding big spots for masterminds)

  local function test_spot(S, x, y)
    for dx = 0,1 do for dy = 0,1 do
      local N = SEEDS[x+dx][y+dy]
      if not N or N.room ~= S.room then return false end

      if N.kind ~= "walk" or not N.floor_h then return false end

      if math.abs(N.floor_h - S.floor_h) > 0.5 then return false end
    end end -- for dx, dy

    return true
  end

  local function find_spots()
    local list = {}

    for x = R.tx1, R.tx2-1 do for y = R.ty1, R.ty2-1 do
      local S = SEEDS[x][y]
      if S.room == R and S.kind == "walk" and S.floor_h then
        if test_spot(S, x, y) then
          table.insert(list, { S=S, x=x, y=y })
        end
      end
    end end -- for x, y

    return list
  end


  --| Rooms_add_crates |--

do return end

  if STYLE.crates == "none" then return end

  if R.natural then return end
  if R.kind ~= "normal" then return end

  local skin
  local skin_names

  if R.outdoor then
    -- FIXME: don't separate them
    skin_names = THEME.out_crates
  else
    skin_names = THEME.crates
  end

  if not skin_names then return end
  skin = assert(GAME.CRATES[rand.key_by_probs(skin_names)])

  local chance

  if STYLE.crates == "heaps" then
    chance = sel(R.outdoor, 25, 40)
    if rand.odds(20) then chance = chance * 2 end
  else
    chance = sel(R.outdoor, 15, 25)
    if rand.odds(10) then chance = chance * 3 end
  end

  for _,spot in ipairs(find_spots()) do
    if rand.odds(chance) then
      spot.S.solid_corner = true

      local T = { add_x=spot.S.x2, add_y = spot.S.y2, add_z = spot.S.floor_h }
      if skin.h then T.scale_z = skin.h / 64 end

      Build.prefab("CRATE", skin, T)

--FIXME  if PARAM.outdoor_shadows and is_outdoor then
--FIXME    Trans.old_brush(get_light(-1), shadowify_brush(coords, 20), -EXTREME_H, z_top-4)
--FIXME  end
    end
  end
end


function Rooms_build_cave(R)

  local cave  = R.cave

  local w_tex  = R.cave_tex
  local w_info = get_mat(w_tex)
  local high_z = EXTREME_H

  local base_x = SEEDS[R.sx1][R.sy1].x1
  local base_y = SEEDS[R.sx1][R.sy1].y1

  local function WALL_brush(data, coords)
    Trans.old_brush(data.info, coords, data.z1 or -EXTREME_H, data.z2 or EXTREME_H)

    if data.shadow_info then
      local sh_coords = shadowify_brush(coords, 40)
      Trans.old_brush(data.shadow_info, sh_coords, -EXTREME_H, (data.z2 or EXTREME_H) - 4)
    end
  end

  local function FC_brush(data, coords)
    if data.f_info then
      Trans.old_brush(data.f_info, coords, -EXTREME_H, data.f_z)
    end
    if data.c_info then
      Trans.old_brush(data.c_info, coords, data.c_z, EXTREME_H)
    end
  end

  local function choose_tex(last, tab)
    local tex = rand.key_by_probs(tab)

    if last then
      for loop = 1,5 do
        if not mat_similar(last, tex) then break; end
        tex = rand.key_by_probs(tab)
      end
    end

    return tex
  end

  -- DO WALLS --

  local data = { info=w_info, ftex=w_tex, ctex=w_tex }

  if R.is_lake then
    data.info = get_liquid()
    data.info.t_face.delta_z = rand.sel(70, -48, -72)
    data.z2 = R.cave_floor_h + 8
  end

  if R.outdoor and not R.is_lake and R.cave_floor_h + 144 < SKY_H and rand.odds(88) then
    data.z2 = R.cave_floor_h + rand.sel(65, 80, 144)
  end

  if PARAM.outdoor_shadows and R.outdoor and not R.is_lake then
    data.shadow_info = get_light(-1)
  end

  -- grab walkway now (before main cave is modified)

  local walkway = cave:copy_island(cave.empty_id)


  -- handle islands first

  for _,island in ipairs(cave.islands) do

    -- FIXME
    if LEVEL.liquid and not R.is_lake and --[[ reg.cells > 4 and --]]
       rand.odds(50)
    then

      -- create a lava/nukage pit
      local pit = get_liquid()

      pit.t_face.delta_z = rand.sel(70, -52, -76)

      island:render(base_x, base_y, WALL_brush,
                    { info=pit, z2=R.cave_floor_h+8 })

      cave:subtract(island)
    end

  end


  cave:render(base_x, base_y, WALL_brush, data, THEME.square_caves)


  if R.is_lake then return end
  if THEME.square_caves then return end
  if PARAM.simple_caves then return end


  local ceil_h = R.cave_floor_h + R.cave_h

  -- TODO: @ pass 3, 4 : come back up (ESP with liquid)

  local last_ftex = R.cave_tex

  for i = 1,rand.index_by_probs({ 10,10,70 })-1 do
    walkway:shrink(false)

---???    if rand.odds(sel(i==1, 20, 50)) then
---???      walkway:shrink(false)
---???    end

    walkway:remove_dots()

    -- DO FLOOR and CEILING --

    data = {}


    if R.outdoor then
      data.ftex = choose_tex(last_ftex, THEME.landscape_trims or THEME.landscape_walls)
    else
      data.ftex = choose_tex(last_ftex, THEME.cave_trims or THEME.cave_walls)
    end

    last_ftex = data.ftex

    data.f_info = get_mat(data.ftex)

    if LEVEL.liquid and i==2 and rand.odds(60) then  -- TODO: theme specific prob
      data.f_info = get_liquid()

      -- FIXME: this bugs up monster/pickup/key spots
      if rand.odds(0) then
        data.f_trim.delta_z = -(i * 10 + 40)
      end
    end

    if true then
      data.f_info.t_face.delta_z = -(i * 10)
    end

    data.f_z = R.cave_floor_h + i

    data.c_info = nil

    if not R.outdoor then
      data.c_info = w_info

      if i==2 and rand.odds(60) then
        data.c_info = get_sky()
      elseif rand.odds(50) then
        data.c_info = get_mat(data.ftex)
      elseif rand.odds(80) then
        data.ctex = choose_tex(data.ctex, THEME.cave_trims or THEME.cave_walls)
        data.c_info = get_mat(data.ctex)
      end

      data.c_info.b_face.delta_z = int((0.6 + (i-1)*0.3) * R.cave_h)

      data.c_z = ceil_h - i
    end


    walkway:render(base_x, base_y, FC_brush, data)
  end
end


function Rooms_do_small_exit()
  local C = R.conns[1]
  local T = C:seed(C:neighbor(R))
  local out_combo = T.room.main_tex
  if T.room.outdoor then out_combo = R.main_tex end

  -- FIXME: use single one over a whole episode
  local skin_name = rand.key_by_probs(THEME.small_exits)
  local skin = assert(GAME.EXITS[skin_name])

  local skin2 =
  {
    wall = out_combo,
    floor = T.f_tex or C.conn_ftex,
    ceil = out_combo,
  }

  assert(THEME.exit.switches)
  -- FIXME: hacky
  skin.switch = rand.key_by_probs(THEME.exit.switches)

--!!!!!!  Build.small_exit(R, THEME.exit, skin, skin2)

  local skin = table.copy(assert(GAME.EXITS["tech_small"]))
  skin.inner = w_tex
  skin.outer = o_tex

  local T = Trans.doorway_transform(S, z1, 8)
  Trans.modify("scale_x", 192 / 256)
  Trans.modify("scale_y", 192 / 256)

  Build.prefab("SMALL_EXIT", skin, T)

  return
end


function Rooms_do_stairwell(R)
  if not LEVEL.well_tex then
    LEVEL.well_tex   = rand.key_by_probs(THEME.stairwell_walls)
    LEVEL.well_floor = rand.key_by_probs(THEME.stairwell_floors)
  end

  local skin = { wall=LEVEL.well_tex, floor=LEVEL.wall_floor }
  Build.stairwell(R, skin)
end


function Rooms_build_seeds(R)

  local function dir_for_wotsit(S)
    local dirs  = {}
    local missing_dir
  
    for dir = 2,8,2 do
      local N = S:neighbor(dir)
      if N and N.room == R and N.kind == "walk" and
         N.floor_h and math.abs(N.floor_h - S.floor_h) < 17
      then
        table.insert(dirs, dir)
      else
        missing_dir = dir
      end
    end

    if #dirs == 1 then return dirs[1] end

    if #dirs == 3 then return 10 - missing_dir end

    if false then --!!!!!!!!! FIXME  S.room.entry_conn then
      local entry_S = S.room.entry_conn:seed(S.room)
      local exit_dir = assert(entry_S.conn_dir)

      if #dirs == 0 then return exit_dir end

      for _,dir in ipairs(dirs) do
        if dir == exit_dir then return exit_dir end
      end
    end

    if #dirs > 0 then
      return rand.pick(dirs)
    end

    return rand.irange(1,4)*2
  end

  local function player_angle(S)
    if R.sh > R.sw then
      if S.sy > (R.sy1 + R.sy2) / 2 then 
        return 270
      else
        return 90
      end
    else
      if S.sx > (R.sx1 + R.sx2) / 2 then 
        return 180
      else
        return 0
      end
    end
  end

  -- FIXME: do KEY and SWITCH same way : via prefabs

  local function do_key(S, lock, z1, z2)
    local mx, my = S:mid_point()

    if rand.odds(15) and THEME.lowering_pedestal_skin then
      local z_top = math.max(z1+128, R.floor_max_h+64)
      if z_top > z2-32 then
         z_top = z2-32
      end

      local skin = table.copy(THEME.lowering_pedestal_skin)
      skin.tag = Plan_alloc_tag()

      local T = Trans.centre_transform(S, z1)
      T.scale_z = (z_top - z1) / 128
      Build.prefab("LOWERING_PEDESTAL", skin, T)

      Trans.entity(lock.item, mx, my, z_top)
    else
      if rand.odds(98) then
        local skin = { top=THEME.pedestal_mat, light=0.7 }
        local T = Trans.centre_transform(S, z1)
        Build.prefab("PEDESTAL", skin, T)
      end
      Trans.entity(lock.item, mx, my, z1)
    end
  end

  local function do_switch(S, lock, z1)
    local INFO = assert(GAME.SWITCHES[lock.item])

    local skin = table.copy(INFO.skin)
    skin.tag = lock.tag

    local T = Trans.centre_transform(S, z1, dir_for_wotsit(S))
    Build.prefab("SMALL_SWITCH", skin, T)
  end

  local function do_purpose(S)
    local sx, sy = S.sx, S.sy

    local z1 = S.floor_h or R.floor_h
    local z2 = S.ceil_h  or R.ceil_h or SKY_H

    local mx, my = S:mid_point()

    if R.purpose == "START" then
      local angle = player_angle(S)
      local dist = 56

      -- TODO: fix this
      if false and PARAM.raising_start and R.svolume >= 20 and not R.natural
         and THEME.raising_start_switch and rand.odds(25)
      then
        gui.debugf("Raising Start made\n")

        local skin =
        {
          f_tex = S.f_tex or R.main_tex,
          switch_w = THEME.raising_start_switch,
        }

        Build.raising_start(S, 6, z1, skin)
        angle = 0

        S.no_floor = true
        S.raising_start = true
        R.has_raising_start = true
      else
        local skin = { top="O_BOLT", x_offset=36, y_offset=-8, peg=1 }
        local T = Trans.centre_transform(S, z1)
        Build.prefab("PEDESTAL", skin, T)
      end

      Trans.entity("player1", mx, my, z1, { angle=angle })

      if GAME.ENTITIES["player2"] then
        Trans.entity("player2", mx - dist, my, z1, { angle=angle })
        Trans.entity("player3", mx + dist, my, z1, { angle=angle })
        Trans.entity("player4", mx, my - dist, z1, { angle=angle })
      end

      -- save position for the demo generator
      LEVEL.player_pos =
      {
        S=S, R=R, x=mx, y=my, z=z1, angle=angle,
      }

      -- never put monsters next to the start spot
      for dir = 2,8,2 do
        local N = S:neighbor(dir)
        if N and N.room == R then
          N.no_monster = true
        end
      end

    elseif R.purpose == "EXIT" and OB_CONFIG.game == "quake" then
      local skin = { floor="SLIP2", wall="SLIPSIDE" }

      Build.quake_exit_pad(S, z1 + 16, skin, LEVEL.next_map)

    elseif R.purpose == "EXIT" then
      local dir = dir_for_wotsit(S)

      if R.outdoor and THEME.out_exits then
        -- FIXME: use single one for a whole episode
        local skin_name = rand.key_by_probs(THEME.out_exits)
        local skin = assert(GAME.EXITS[skin_name])

        local T = Trans.centre_transform(S, z1, dir)
        Build.prefab("OUTDOOR_EXIT_SWITCH", skin, T)

      elseif THEME.exits then
        -- FIXME: use single one for a whole episode
        local skin_name = rand.key_by_probs(THEME.exits)
        local skin = assert(GAME.EXITS[skin_name])

        local T = Trans.centre_transform(S, z1, dir)
        Build.prefab("EXIT_PILLAR", skin, T)
      end

    elseif R.purpose == "SOLUTION" then
      local lock = assert(R.purpose_lock)

      if lock.kind == "KEY" then
        do_key(S, lock, z1, z2)
      elseif lock.kind == "SWITCH" or lock.kind == "BARS" then
        do_switch(S, lock, z1)
      else
        error("unknown lock kind: " .. tostring(lock.kind))
      end

    else
      error("unknown purpose: " .. tostring(R.purpose))
    end
  end


  local function do_weapon(S)
    local sx, sy = S.sx, S.sy

    local z1 = S.floor_h or R.floor_h
    local z2 = S.ceil_h  or R.ceil_h or SKY_H

    local mx, my = S:mid_point()

    local weapon = assert(S.content_weapon)

    if R.hallway or R == LEVEL.start_room then
      Trans.entity(weapon, mx, my, z1)

    elseif rand.odds(40) and THEME.lowering_pedestal_skin2 then
      local z_top = math.max(z1+80, R.floor_max_h+40)
      if z_top > z2-32 then
         z_top = z2-32
      end

      local skin = table.copy(THEME.lowering_pedestal_skin2)
      skin.tag = Plan_alloc_tag()

      local T = Trans.centre_transform(S, z1)
      T.scale_z = (z_top - z1) / 128
      Build.prefab("LOWERING_PEDESTAL", skin, T)

      Trans.entity(weapon, mx, my, z_top)
    else
      local skin = { top=THEME.pedestal_mat, light=0.7 }
      local T = Trans.centre_transform(S, z1)
      Build.prefab("PEDESTAL", skin, T)

      Trans.entity(weapon, mx, my, z1+8)
    end

    gui.debugf("Placed weapon '%s' @ (%d,%d,%d)\n", weapon, mx, my, z1)
  end


  local function do_teleporter(S)
    local conn
    for _,C in ipairs(R.conns) do
      if C.kind == "teleporter" then
        conn = C
        break;
      end
    end
    assert(conn)

    local z1 = S.floor_h or R.floor_h
    local z2 = S.ceil_h  or R.ceil_h or SKY_H

    local skin = table.copy(THEME.teleporter_skin)

    skin.angle = 90  -- FIXME: proper angle

    -- determine correct tag numbers
    skin.in_tag  = conn.tele_tag1
    skin.out_tag = conn.tele_tag2

    if R == conn.R2 then
      skin.in_tag, skin.out_tag = skin.out_tag, skin.in_tag
    end

    local T = Trans.centre_transform(S, z1)

    Build.prefab("TELEPORT_PAD", skin, T)
  end


  local function Split_quad(S, info, x1,y1, x2,y2, z1,z2)
    local prec = GAME.lighting_precision or "medium"

    if OB_CONFIG.game == "quake" then prec = "low" end
    if R.outdoor then prec = "low" end
    if S.usage then prec = "low" end

    if prec == "high" then
      for i = 0,5 do for k = 0,5 do
        local ax = int((x1*i+x2*(6-i)) / 6)
        local ay = int((y1*k+y2*(6-k)) / 6)
        local bx = int((x1*(i+1)+x2*(5-i)) / 6)
        local by = int((y1*(k+1)+y2*(5-k)) / 6)
        
        Trans.old_quad(info, ax,ay, bx,by, z1,z2)
      end end

    elseif prec == "medium" then
      local ax = int((x1*2+x2) / 3)
      local ay = int((y1*2+y2) / 3)
      local bx = int((x1+x2*2) / 3)
      local by = int((y1+y2*2) / 3)

      Trans.old_quad(info, x1,y1, ax,ay, z1,z2)
      Trans.old_quad(info, ax,y1, bx,ay, z1,z2)
      Trans.old_quad(info, bx,y1, x2,ay, z1,z2)

      Trans.old_quad(info, x1,ay, ax,by, z1,z2)
      Trans.old_quad(info, ax,ay, bx,by, z1,z2)
      Trans.old_quad(info, bx,ay, x2,by, z1,z2)

      Trans.old_quad(info, x1,by, ax,y2, z1,z2)
      Trans.old_quad(info, ax,by, bx,y2, z1,z2)
      Trans.old_quad(info, bx,by, x2,y2, z1,z2)

    else
      Trans.old_quad(info, x1,y1, x2,y2, z1,z2)
    end
  end

  local function border_wants_corner(B)
    if not B then return false end

    if B.kind == nil then return false end
    if B.kind == "nothing" then return false end
    if B.kind == "straddle" then return false end  -- FIXME: verify this one

    return true
  end

  local function calc_wall_map(S)
    --
    -- Wall map is a 3x3 grid, same arrangement as numeric keypad.
    --
    -- If an element is nil, then that block is free.
    -- A numeric value represents a border (2 | 4 | 6 | 8).
    -- Otherwise it is a string keyword, e.g. "solid".
    --
    S.wall_map = {}

    -- process sides
    for side = 2,8,2 do
      local B = S.border[side]

      if not B or B.kind == nil or B.kind == "nothing" then
        -- unused
      else
        S.wall_map[side] = side
      end
    end

    -- process corners
    for dir = 1,9,2 do if dir ~= 5 then
      local L_side = geom.ROTATE[7][dir]
      local R_side = geom.ROTATE[1][dir]

      local L1 = border_wants_corner(S.border[L_side])
      local R1 = border_wants_corner(S.border[R_side])

      if L1 and R1 then
        if not (R.outdoor or R.natural) then
          S.wall_map[dir] = "solid"
        end
      elseif L1 then
        S.wall_map[dir] = L_side
      elseif R1 then
        S.wall_map[dir] = R_side
      else
        -- unused
      end
    end end
  end


  local function build_seed(S)
    if S.already_built then
      return
    end

    local x1 = S.x1
    local y1 = S.y1
    local x2 = S.x2
    local y2 = S.y2

    local z1 = S.floor_h or R.floor_h or 0
    local z2 = S.ceil_h  or R.ceil_h or R.sky_h or SKY_H

    assert(z1 and z2)


    local w_tex = S.w_tex or R.main_tex
    local f_tex = S.f_tex or R.main_tex
    local c_tex = S.c_tex or sel(R.outdoor, "_SKY", R.ceil_tex)

    if R.kind == "hallway" then
      w_tex = assert(LEVEL.hall_tex)
    elseif R.kind == "stairwell" then
      w_tex = assert(LEVEL.well_tex)
    end

---???    if S.conn_dir then
---???      local N = S:neighbor(S.conn_dir)
---???
---???      if N.room.hallway then
---???        o_tex = LEVEL.hall_tex
---???      elseif N.room.stairwell then
---???        o_tex = LEVEL.well_tex
---???      elseif not N.room.outdoor and N.room ~= R.parent then
---???        o_tex = N.w_tex or N.room.main_tex
---???      elseif N.room.outdoor and not (R.outdoor or R.natural) then
---???        o_tex = R.facade or w_tex
---???      end
---???    end



    local sec_kind


    -- coords for solid block floor and ceiling
    local fx1, fy1 = x1, y1
    local fx2, fy2 = x2, y2

    local cx1, cy1 = x1, y1
    local cx2, cy2 = x2, y2

    local function shrink_floor(side, len)
      if side == 2 then fy1 = fy1 + len end
      if side == 8 then fy2 = fy2 - len end
      if side == 4 then fx1 = fx1 + len end
      if side == 6 then fx2 = fx2 - len end
    end

    local function shrink_ceiling(side, len)
      if side == 2 then cy1 = cy1 + len end
      if side == 8 then cy2 = cy2 - len end
      if side == 4 then cx1 = cx1 + len end
      if side == 6 then cx2 = cx2 - len end
    end

    local function shrink_both(side, len)
      shrink_floor(side, len)
      shrink_ceiling(side, len)
    end



    -- SIDES

    calc_wall_map(S)

    for side = 2,8,2 do
      local N = S:neighbor(side)

      local border = S.border[side]
      local B_kind = border and S.border[side].kind

      -- determine 'other tex'
      local o_tex = w_tex

      if N and N.room then
        o_tex = N.room.main_tex
        if N.room.outdoor and not R.outdoor and R.facade then
          o_tex = R.facade
        end
      end

      -- shadow hack
      if R.outdoor and N and ((N.room and not N.room.outdoor) or
                              (N.edge_of_map and N.building))
      then
        local dist = 24 + int((z2 - z1) / 4)
        if dist > 160 then dist = 160 end
        Build.shadow(S, side, dist)

      elseif R.outdoor and N and N.edge_of_map and N.fence_h then
        Build.shadow(S, side, 20, N.fence_h - 4)
      end

      -- hallway hack
      if R.hallway and not (S.kind == "void") and
         ( (B_kind == "wall")
          or
           (S:neighbor(side) and S:neighbor(side).room == R and
            S:neighbor(side).kind == "void")
         )
      then
        local skin = { wall=LEVEL.hall_tex, trim1=THEME.hall_trim1, trim2=THEME.hall_trim2 }
        Build.detailed_hall(S, side, z1, z2, skin)

        S.border[side].kind = nil
        B_kind = nil
      end

      if B_kind == "wall" then
      local side_T = Trans.border_transform(S, z1, side)

        local skin = { inner = w_tex, outer = o_tex }

        Build.prefab("WALL", skin, side_T)

        shrink_both(side, 4)
      end

      if B_kind == "facade" then
--!!!!!!!        Build.facade(S, side, S.border[side].facade)
      end

      if B_kind == "window" then
        local B = S.border[side]
        local skin = { inner=w_tex, outer=o_tex, track=THEME.window_side_mat or w_tex }

        local T = Trans.border_transform(S, B.win_z1, side)

        -- FIXME: B.win_width, B.win_z1, B.win_z2
        Build.prefab("WINDOW", skin, T)

        shrink_both(side, 4)
      end

      if B_kind == "picture" then
        local B = S.border[side]

        local skin = table.copy(B.pic_skin)
        skin.inner = w_tex
        skin.outer = o_tex

        local T = Trans.border_transform(S, B.pic_z1, side)

        Build.prefab("PICTURE", skin, T)

        shrink_both(side, 4)
      end

      if B_kind == "fence"  then
        local skin = { h=30, wall=w_tex, floor=f_tex }
        Build.fence(S, side, R.fence_h or ((R.floor_h or z1)+skin.h), skin)
        shrink_floor(side, 4)
      end

      if B_kind == "arch" then
        local C = border.conn
---???        local z = assert(C and C.conn_h)

        local door_T = Trans_straddle_transform(S, z1, side)

        local skin = { inner=w_tex, outer=o_tex, track=THEME.track_mat }

        Build.prefab("ARCH", skin, door_T)

---!!!     shrink_ceiling(side, 4)

        if R.outdoor and N.room.outdoor then
          Build.shadow(S,  side, 96)
          Build.shadow(S, -side, 96)
        end

        assert(not C.already_made_lock)
        C.already_made_lock = true
      end

      if B_kind == "liquid_arch" then
        local side_T = Trans.border_transform(S, z1, side)

        local other_mat = sel(N.room.outdoor, R.facade, N.room.main_tex)
        local skin = { inner=w_tex, floor=f_tex, outer=other_mat, track=THEME.track_mat }
        local z_top = math.max(R.liquid_h + 80, N.room.liquid_h + 48)

        side_T.scale_z = 0.5

        Build.prefab("ARCH", skin, side_T)

---!!!    shrink_ceiling(side, 4)
      end

      if B_kind == "door" then
        local C = border.conn
---???        local z = assert(C and C.conn_h)

        local door_T = Trans_straddle_transform(S, z1, side)

        -- FIXME: better logic for selecting doors
        local doors = THEME.doors
        if not doors then
          error("Game is missing doors table")
        end

        local door_name = rand.key_by_probs(doors)
        local skin = assert(GAME.DOORS[door_name])

        local skin2 = table.copy(skin)

        skin2.inner = w_tex
        skin2.outer = o_tex

        Build.prefab("DOOR", skin2, door_T)

--!!!   shrink_ceiling(side, 4)

        assert(not C.already_made_lock)
        C.already_made_lock = true
      end

      if B_kind == "lock_door" then
        local C = border.conn
---???        local z = assert(C and C.conn_h)

        local door_T = Trans_straddle_transform(S, z1, side)

        local LOCK = assert(S.border[side].lock)
        local skin = assert(GAME.DOORS[LOCK.item])

--if not skin.track then gui.printf("%s", table.tostr(skin,1)); end
        assert(skin.track)

        local skin2 = table.copy(skin)
        
        skin2.inner = w_tex
        skin2.outer = o_tex
        skin2.tag   = LOCK.tag

---???        local reversed = (S == C.dest_S)

        Build.prefab("DOOR", skin2, door_T)

--!!!   shrink_ceiling(side, 4)

        assert(not C.already_made_lock)
        C.already_made_lock = true
      end

      if B_kind == "bars" then
        local C = border.conn
        local LOCK = assert(border.lock)
        local skin = assert(GAME.DOORS[LOCK.item])

        local z_top = math.max(R.floor_max_h, N.room.floor_max_h) + skin.bar_h
        local ceil_min = math.min(R.ceil_h or SKY_H, N.room.ceil_h or SKY_H)

        if z_top > ceil_min-32 then
           z_top = ceil_min-32
        end

        Build.lowering_bars(S, side, z_top, skin, LOCK.tag)

        assert(not C.already_made_lock)
        C.already_made_lock = true
      end
    end -- for side


    -- CORNERS

    for corner = 1,9,2 do if corner ~= 5 then
      if S.wall_map[corner] == "solid" then
        local skin = { inner=w_tex, outer=R.facade or w_tex }

        local T = Trans.corner_transform(S, z1, corner)

        Build.prefab("CORNER", skin, T)
      end
    end end -- for corner


    if R.sides_only then return end


    -- DIAGONALS

    if S.kind == "diagonal" then

      local diag_info = get_mat(w_tex, S.stuckie_ftex) ---### , c_tex)

--!!!!!!      Build.diagonal(S, S.stuckie_side, diag_info, S.stuckie_z)

      S.kind = assert(S.diag_new_kind)

      if S.diag_new_z then
        S.floor_h = S.diag_new_z
        z1 = S.floor_h
      end
      
      if S.diag_new_ftex then
        S.f_tex = S.diag_new_ftex
        f_tex = S.f_tex
      end
    end


    -- CEILING

    if S.kind ~= "void" and not S.no_ceil and 
       (S.is_sky or c_tex == "_SKY")
    then

      Trans.old_quad(get_sky(), x1,y1, x2,y2, z2, EXTREME_H)

    elseif S.kind ~= "void" and not S.no_ceil then
      ---## local info = get_mat(S.u_tex or c_tex or w_tex, c_tex)
      ---## info.b_face.light = S.c_light
      ---## Trans.old_quad(info, cx1,cy1, cx2,cy2, z2, EXTREME_H)

      local kind, w_face, p_face = Mat_normal(S.u_tex or c_tex or w_tex, c_tex)
      p_face.light = S.c_light

      Trans.quad(cx1,cy1, cx2,cy2, z2,nil, { k=kind }, w_face, p_face)

      -- FIXME: this does not belong here
      if R.hallway and LEVEL.hall_lights then
        local x_num, y_num = 0,0

        for side = 2,8,2 do
          local N = S:neighbor(side)
          if N and N.room == R and N.kind ~= "void" then
            if side == 2 or side == 8 then
              y_num = y_num + 1
            else
              x_num = x_num + 1
            end
          end
        end

        if x_num == 1 and y_num == 1 and LEVEL.hall_lite_ftex then
          local skin = { glow=LEVEL.hall_lite_ftex, trim=THEME.light_trim }
          local T = Trans.centre_transform(S, z2, 2)  -- TODO; pick a dir

          Build.prefab("CEIL_LIGHT", skin, T)
        end
      end
    end


    -- FLOOR
    if S.kind == "void" then

      if S.solid_feature and THEME.building_corners then
        if not R.corner_tex then
          R.corner_tex = rand.key_by_probs(THEME.building_corners)
        end
        w_tex = R.corner_tex
      end

      Trans.old_quad(get_mat(w_tex), x1,y1, x2,y2, -EXTREME_H, EXTREME_H);

    elseif S.kind == "stair" then
      local skin2 = { wall=S.room.main_tex, floor=S.f_tex or S.room.main_tex }

      table.merge(skin2, LEVEL.step_skin)

      local z1 = S.stair_z1
      local z2 = S.stair_z2
      local dir = S.stair_dir
      local fab_name

      if z1 < z2 then
        fab_name = "STAIR_6"
      else
        fab_name = "NICHE_STAIR_8"
        z1, z2 = z2, z1
        dir = 10-dir
      end

      local T = Trans.doorway_transform(S, z1, dir)
      T.scale_z = (z2 - z1) / 128

      Build.prefab(fab_name, skin2, T)

---####    Build.niche_stair(S, LEVEL.step_skin, skin2)

    elseif S.kind == "lift" then
      local skin = table.copy(LEVEL.lift_skin)

      skin.tag = Plan_alloc_tag()
      skin.floor = f_tex

      local z1 = S.stair_z1
      local z2 = S.stair_z2
      local dir = S.stair_dir

      if z1 > z2 then
        z1, z2 = z2, z1
        dir = 10 - dir
      end

      local T = Trans.doorway_transform(S, z1, dir)  -- FIXME: whole_transform ??
      T.scale_z = (z2 - z1) / 128
      
      Build.prefab("LIFT", skin, T)

---###      Build.lift(S, LEVEL.lift_skin, skin2, tag)

    elseif S.kind == "curve_stair" then
      Build.low_curved_stair(S, LEVEL.step_skin, S.x_side, S.y_side, S.x_height, S.y_height)

    elseif S.kind == "tall_stair" then
      Build.tall_curved_stair(S, LEVEL.step_skin, S.x_side, S.y_side, S.x_height, S.y_height)

    elseif S.kind == "popup" then
      -- FIXME: monster!!
      local skin = { wall=w_tex, floor=f_tex }
      Build.popup_trap(S, z1, skin, "revenant")

    elseif S.kind == "liquid" then
      assert(LEVEL.liquid)
      local info = get_liquid()

      Trans.old_quad(info, fx1,fy1, fx2,fy2, -EXTREME_H, z1)

    elseif not S.no_floor then
      --!!!  local info = get_mat(S.l_tex or w_tex, f_tex)
      --!!!  info.sec_kind = sec_kind
      --!!!  Split_quad(S, info, fx1,fy1, fx2,fy2, -EXTREME_H, z1)

      local kind, w_face, p_face = Mat_normal(S.l_tex or w_tex, f_tex)
      p_face.kind = sec_kind

      Trans.quad(fx1,fy1, fx2,fy2, nil,z1, { k=kind }, w_face, p_face)
    end


    -- PREFABS

    if S.usage == "pillar" then
      local T = Trans.centre_transform(S, z1, S.pillar_dir or 2)  -- TODO pillar_dir
      T.scale_z = (z2 - z1) / 128

      Build.prefab("PILLAR", assert(S.pillar_skin), T)
    end

    if S.usage == "WEAPON" then
      do_weapon(S)
    elseif S.usage == "SOLUTION" then
      do_purpose(S)
    elseif S.usage == "TELEPORTER" then
      do_teleporter(S)
    end


    -- restore diagonal kind for monster/item code
    if S.diag_new_kind then
      S.kind = "diagonal"
    end

  end -- build_seed()


  ---==| Rooms_build_seeds |==---

  if R.cave then
    Rooms_build_cave(R)
  end

  if R.kind == "smallexit" then
    Rooms_do_small_exit(R)
    return
  end

  if R.kind == "stairwell" then
    Rooms_do_stairwell(R)
    R.sides_only = true
  end

  for x = R.sx1,R.sx2 do for y = R.sy1,R.sy2 do
    local S = SEEDS[x][y]
    if S.room == R then
      build_seed(S)
    end
  end end -- for x, y
end


function Rooms_add_sun()
  local sun_r = 25000
  local sun_h = 40000

  -- nine lights in the sky, one is "the sun" and the rest are
  -- to keep outdoor areas from getting too dark.

  for i = 1,8 do
    local angle = i * 45 - 22.5

    local x = math.sin(angle * math.pi / 180.0) * sun_r
    local y = math.cos(angle * math.pi / 180.0) * sun_r

    local level = sel(i == 1, 32, 6)

    Trans.entity("sun", x, y, sun_h, { light=level })
  end

  Trans.entity("sun", 0, 0, sun_h, { light=8 })
end


function Rooms_build_all()

  gui.printf("\n--==| Build Rooms |==--\n\n")

  Rooms_choose_themes()
---!!!!  Rooms_decide_hallways()

  Rooms_setup_symmetry()

  Rooms_place_doors()

  if PARAM.tiled then
    -- this is as far as we go for TILE based games
    Tiler_layout_all()
    return
  end

---!!  Levels.invoke_hook("layout_rooms", LEVEL.seed)

  for _,R in ipairs(LEVEL.all_rooms) do
    Layout_do_room(R)
    Rooms_make_ceiling(R)
    Rooms_add_crates(R)
  end

  for _,R in ipairs(LEVEL.scenic_rooms) do
    Layout_do_scenic(R)
    Rooms_make_ceiling(R)
  end

  Rooms_synchronise_skies()

  Rooms_border_up()

  for _,R in ipairs(LEVEL.scenic_rooms) do Rooms_build_seeds(R) end
  for _,R in ipairs(LEVEL.all_rooms)    do Rooms_build_seeds(R) end

  Layout_edge_of_map()

  Rooms_add_sun()
end

