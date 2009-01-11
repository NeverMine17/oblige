----------------------------------------------------------------
--  Room Layouting
----------------------------------------------------------------
--
--  Oblige Level Maker (C) 2006-2008 Andrew Apted
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

--[[

Room Layouting Notes
====================

DESCRIPTION OF PROBLEM:

+ Primary goal is to ensure all exit seeds in a room
  are traversable, i.e. there exists a path from X to Y
  such that each element is either a symbolic height ('0' .. '3')
  or a staircase ('>', '<', 'v', '^', 'F', 'T', 'L', 'J').

  Certain staircases are never usable on certain rows or
  columns (e.g. cannot use 'F' on top row if vertically mirrored).

  In emergencies we can mark certain seeds as "laddering"
  onto an adjacent height-difference seed.  We must try hard
  to (a) avoid this or (b) minimise its use and (c) pick
  the best seed pair to ladder [not an exit seed, low diff, etc]

+ Secondary goal is "niceness" of the room layout:
  (a) staircases are not used in two adjacent seeds

  (b) F/T/L/J staircases only used in corners
      (or "pseudo-corners" i.e. floor seeds at higher heights)

  (c) height diff between staircases is '1' unit
      [any is possible, the lower the better]

  (d) small preference for staircases parallel to main direction
      of room (esp. PC/PR/PX and TY types).

+ Tertiary goal is to assign diagonal corners and solid
  seeds, as well as flood filling floor heights, in a
  pleasing/interesting way.


IDEA:
  Primitive operations:

  1) start at exit A, go (anti)clockwise around the edge of the
     room until hit exit B, use suitable connections
     (especially corner stairwells).

  2) start at exit A, go inward until hit exit B.
     If hit a blank wall instead, assume hit the R.floor_h
     seed [if none: one closer to it] and put stairs
     appropriately for that.

  3) start at exit A, go inward a certain dist then turn left
     or right and run towards exit B.

  3) ?? void up edges [if not empty, replicated exit seeds into inner area]
  4) ?? ledge up edges [need exits all at same height, or use R.floor_h]

  Repeat the primitive operations for random exit seeds
  until full traversibility is reached (or run out of
  usable directions]

  Add emergency "ladders" when no more traversifying can be done.

  Score the final result.  Perform ### fillings for each room
  and pick the one with the best result.

  [Can fill holes and decide solid corners last]


OTHER IDEAS:

- height diffs:
  - basic (if all else fails) algorithm:
    flood fill heights from conn seeds to remaining seeds
    [BUT: floor_h of room]
    add a stair seed at some meeting spots

    if height diff is huge, deserves more seeds

  - patterns:
    (a) L shape is nice
    (b) U shape is possible
    (c) plain side fill (two deep if room is big)

--]]


--[[

class LAYOUT
{
  char  -- single character summary
           '0' '1' '2' '3' : flat fixed height
           '<' '>' 'v' '^' : stair (straight)
           'L' 'F' 'T' 'J' : stair (turning 90 degrees)
           '/' '\'         : diagonal wall

  conn_dirs[DIR]  -- true if sitting on a connection 
                  -- (possibly mirrored) towards DIR
 
  on_path  -- true if seed is part of main path(s) through room

  group_id

  floor_h : number  -- floor height

  assign_stair

  emergs[DIR]   -- true for emergency connections
  windows[DIR]  -- true for windows

  stair_z1, stair_z2  -- stair heights, z1 = source, z2 = dest
                      -- (for L/F/T/J, z1 = top/bottom, z2 = left/right)

  lift_h

  tdir

}

--]]

require 'defs'
require 'util'


function Room_SetupTheme(R)
 
  if R.outdoor == nil then
    --!!! TEMP CRUD to decide Outdoorsiness
    local outdoor_chance = 20
    if R.sx1 <= 2 or R.sx2 >= SEED_W-1 then outdoor_chance = outdoor_chance + 25 end
    if R.sy1 <= 2 or R.sy2 >= SEED_H-1 then outdoor_chance = outdoor_chance + 25 end
    R.outdoor = rand_odds(outdoor_chance)

    R.outdoor = false --!!!! TEMP
    if R.children then R.outdoor = true end

    if R.parent then
      if R.parent.outdoor == nil then Room_SetupTheme(R.parent) end
      R.outdoor = not R.parent.outdoor
    end
  end

  if not PLAN.outdoor_combos then
    PLAN.outdoor_combos = {}

    for num = 1,2 do
      local name = rand_key_by_probs(PLAN.theme.ground)
      PLAN.outdoor_combos[num] = assert(GAME.combos[name]) 
    end
  end

  if not PLAN.indoor_combos then
    PLAN.indoor_combos = {}

    for num = 1,3 do
      local name = rand_key_by_probs(PLAN.theme.building)
      PLAN.indoor_combos[num] = assert(GAME.combos[name]) 
    end
  end


  if R.outdoor then
    R.combo = rand_element(PLAN.outdoor_combos)
  else
    R.combo = rand_element(PLAN.indoor_combos)
  end
end

function Room_SetupTheme_Scenic(R)
  -- find closest
  local mx = int((R.sx1 + R.sx2) / 2)
  local my = int((R.sy1 + R.sy2) / 2)

  for dist = -SEED_W,SEED_W do
    if Seed_valid(mx + dist, my, 1) then
      local S = SEEDS[mx + dist][my][1]
      if S.room and S.room.kind ~= "scenic" and
         (not S.room.outdoor) == (not R.outdoor) and
         S.room.combo
      then
        R.combo = S.room.combo
        return
      end
    end

    if Seed_valid(mx, my + dist, 1) then
      local S = SEEDS[mx][my + dist][1]
      if S.room and S.room.kind ~= "scenic" and
         (not S.room.outdoor) == (not R.outdoor) and
         S.room.combo
      then
        R.combo = S.room.combo
        return
      end
    end
  end

  -- fallback
  local name

  if R.outdoor then
    name = rand_key_by_probs(PLAN.theme.ground)
    R.combo = assert(GAME.combos[name])
  else
    R.combo = PLAN.indoor_combos[rand_irange(1,4)]
  end
end


function calc_conn_area(R)
  local lx, ly = 999,999
  local hx, hy = 0,0

  for _,C in ipairs(R.conns) do
    local S = C:seed(R)
    lx = math.min(lx, S.sx)
    ly = math.min(ly, S.sy)
    hx = math.max(hx, S.sx)
    hy = math.max(hy, S.sy)
  end

  assert(lx <= hx and ly <= hy)

  return lx,ly, hx,hy
end


function calc_height_set(R)
  local list = { }

  local function add_height(new_h)
    for _,h in ipairs(list) do
      if math.abs(h - new_h) < 1 then
        return
      end
    end
    
    table.insert(list, new_h)
  end

  for _,C in ipairs(R.conns) do
    add_height(C.conn_h)
  end
  
  if #list < 3 and math.min(R.sw, R.sh) >= 3 then
    add_height(R.floor_h)
  end

  table.sort(list, function(A,B) return A < B end)

  return list
end


function dump_layout(R)

  local function outside_seed(x, y)
    for dir = 2,8,2 do
      local sx, sy = nudge_coord(x, y, dir)
      if R:valid_T(sx, sy) then
        local T = SEEDS[sx][sy][1]
        if T.conn_dirs and T.conn_dirs[10-dir] then
          return '*'
        end
      end
    end
      
    for _,C in ipairs(R.conns) do
      local S = C:seed(R)
      local ox, oy = nudge_coord(S.sx, S.sy, S.conn_dir)
      if ox == x and oy == y then
        return '+'
      end
    end

    return ' '
  end

  local function inside_seed(x, y)
    local S = SEEDS[x][y][1]
    assert(S and S.room == R)

    if S.layout then
      return S.layout.char
    end

    return '.'
  end


  --| dump_layout |--

  gui.debugf("Room %s @ (%d,%d) Layout:\n", R.kind, R.sx1, R.sy1)

  for y = R.ty2+1, R.ty1-1, -1 do
    line = ""
    for x = R.tx1-1, R.tx2+1 do
      if x < R.tx1 or x > R.tx2 or y < R.ty1 or y > R.ty2 then
        line = line .. outside_seed(x, y)
      else
        line = line .. inside_seed(x, y)
      end
    end
    gui.debugf(" %s\n", line)
  end

  gui.debugf("\n");
end


function Junk_fill_room(R, n_sx1, n_sy1, n_sx2, n_sy2)
  for y = R.sy1,R.sy2 do for x = R.sx1,R.sx2 do
    if not box_contains_point(n_sx1,n_sy1, n_sx2,n_sy2, x,y) then
      SEEDS[x][y][1].layout = { char = "#" }
    end
  end end -- for y, x

  if R.kind ~= "hallway" then
    dump_layout(R)
  end

  R.sx1, R.sy1 = n_sx1, n_sy1
  R.sx2, R.sy2 = n_sx2, n_sy2

  R.sw = R.sx2 - R.sx1 + 1
  R.sh = R.sy2 - R.sy1 + 1

  assert(R.sw >= 1 and R.sh >= 1)
end


function Layout_Hallway(R)
  local lx,ly, hx,hy = calc_conn_area(R)

  Junk_fill_room(R, lx,ly, hx,hy)

  -- sometimes make "O" shape
  if rand_odds(20) then
    if R.sw >= 3 and R.sh >= 3 then
      for x = R.sx1+1,R.sx2-1 do for y = R.sy1+1,R.sy2-1 do
        SEEDS[x][y][1].layout = { char = "#" }
      end end

      return;
    end
  end

  -- TODO: sometimes make "U" shape (for U2, TC, TY)

  -- easy if only one seed wide or tall
  if lx==hx or ly==hy then
    return
  end


  -- block out seeds that don't "trace" from a connection
  local used_x = {}
  local used_y = {}

  for _,C in ipairs(R.conns) do
    local S = C:seed(R)
    if is_vert(S.conn_dir) then
      used_x[S.sx] = 1
    else
      used_y[S.sy] = 1
    end
  end

  for x = R.sx1,R.sx2 do for y = R.sy1,R.sy2 do
    if not (used_x[x] or used_y[y]) then
      SEEDS[x][y][1].layout = { char = "#" }
    end
  end end -- for y,x

  -- handle when all connections are parallel
  if table_empty(used_x) then
    local x = int((R.sx1 + R.sx2) / 2)
    for y = R.sy1,R.sy2 do
      SEEDS[x][y][1].layout = nil
    end

  elseif table_empty(used_y) then
    local y = int((R.sy1 + R.sy2) / 2)
    for x = R.sx1,R.sx2 do
      SEEDS[x][y][1].layout = nil
    end
  end
end


function Layout_Outdoor(R)

  local function try_expand_stair(ST, dir)
    local x1, y1 = ST.x1, ST.y1
    local x2, y2 = ST.x2, ST.y2

        if dir == 2 then y1 = y1 - 1
    elseif dir == 8 then y2 = y2 + 1
    elseif dir == 4 then x1 = x1 - 1
    elseif dir == 6 then x2 = x2 + 1
    else error("WTF dir?")
    end

    -- don't take up too much space
    if (x1 == R.sx1 and x2 == R.sx2 and R.sh <= 4) or
       (y1 == R.sy1 and y2 == R.sy2 and R.sw <= 4)
    then
      return false
    end

    for x = x1,x2 do for y = y1,y2 do
      if not R:contains_seed(x, y) then
        return false
      end

      local N = SEEDS[x][y][1]

      if N.layout and N.layout.char ~= "S" then
        return false
      end

      if N.layout and N.layout.char == "S" and N.layout.assign_stair ~= ST then
        return false
      end
    end end -- for x,y

    -- OK !!
    ST.x1, ST.y1 = x1, y1
    ST.x2, ST.y2 = x2, y2

    for x = x1,x2 do for y = y1,y2 do
      local N = SEEDS[x][y][1]

      if not N.layout then
        N.layout = { char = "S" }
        N.layout.assign_stair = ST
        N.layout.floor_h = assert(ST.S.layout.floor_h)
      end
    end end -- for x,y

    return true
  end


  ---| Layout_Outdoor |---

  -- FIXME: if room has purpose, assign a seed for it now
 
  local stairs = {}
  local lifts  = {}

  for _,C in ipairs(R.conns) do
    local S = C:seed(R)
    assert(not S.layout)

    local diff = math.abs(C.conn_h - R.floor_h)

    if diff <= 4 then
      S.layout = { char = '0', floor_h = R.floor_h }
    elseif diff >= 144 or (diff >= 112 and rand_odds(40)) or
                          (diff >= 80  and rand_odds(25))
    then
      S.layout = { char = '=' }  -- lift
      S.layout.lift_h = math.max(C.conn_h, R.floor_h) + 4
      table.insert(lifts, { S=S })
    else
      S.layout = { char = 'S' }  -- stair

      local STAIR =
      {
        S=S, conn=C,

        x1=S.sx, y1=S.sy,
        x2=S.sx, y2=S.sy,

        inner_h = C.conn_h,
        outer_h = R.floor_h,
      }

      table.insert(stairs, STAIR)

      S.layout.assign_stair = STAIR
      S.layout.floor_h = math.min(C.conn_h, R.floor_h)
    end
  end


  gui.debugf("OUTDOOR LAYOUT:\n")
  dump_layout(R)


  if #stairs == 0 then
    -- nothing else to do
    return
  end


  local sides = { 2,4,6,8 }
  rand_shuffle(sides)


  for loop = 1,4 do
    rand_shuffle(stairs)
    for _,ST in ipairs(stairs) do
      try_expand_stair(ST, sides[loop])
    end
  end

  gui.debugf("EXPANDED:\n")
  dump_layout(R)
end


function Layout_Indoor(R)

  local h_set = calc_height_set(R)

  local function char_for_height(set, h)
    for index,h2 in ipairs(set) do
      if math.abs(h - h2) < 1 then
        assert(index <= 10)
        return string.sub("0123456789", index, index)
      end
    end
    error("Height not found in set!!\n")
  end

  local function height_for_char(set, ch)
    if ch == '0' then return set[1] end
    if ch == '1' then return set[2] end
    if ch == '2' then return set[3] end
    if ch == '3' then return set[4] end
    if ch == '4' then return set[5] end
    if ch == '5' then return set[6] end
    if ch == '6' then return set[7] end
    if ch == '7' then return set[8] end
    if ch == '8' then return set[9] end
    if ch == '9' then return set[10] end

    return nil
  end

  local function size_for_symmetry(kind)
    local w, h = R.sw, R.sh

    if kind == "x" or kind == "xy" then
      w = int((w+1) / 2)
    end

    if kind == "y" or kind == "xy" then
      h = int((h+1) / 2)
    end
    
    return w, h
  end

  local function required_seeds(kind)
    -- one seed for each connection
    local count = #R.conns

    -- one seed for each height difference
    -- (with some redundancy, regions may be non-contiguous)
    count = count + #h_set

    if kind == "xy" then
      count = count * 4  -- exaggeration
    
    elseif kind == "x" or kind == "y" then
      count = count * 2
    end

    -- one seed for purpose (key/switch/etc)
    if R.purpose or #R.conns == 0 then
      count = count + 1
    end

    -- one seed for row/column, space for monsters or pillars
    count = count + math.max(R.sw, R.sh)

    return count
  end

  local function is_symmetry_possible(R, sym)
    if sym == "xy" then
      return is_symmetry_possible(R, "x") and
             is_symmetry_possible(R, "y")
    end

    for _,C in ipairs(R.conns) do
      local S = C:seed(R)
      local tx, ty = S.sx, S.sy

      if sym == "x" then
        tx = R.sx1 + R.sx2 - tx
      else -- sym == "y"
        ty = R.sy1 + R.sy2 - ty
      end


      -- basic test: peer seed must be free or have same height
      local T = SEEDS[tx][ty][1]
      if T.conn and T.conn.layout_char ~= C.layout_char then
        return false
      end

      -- strict test: don't put different heights next to each other
      for side = 2,8,2 do
        local nx, ny = nudge_coord(tx, ty, side)
        if R:contains_seed(nx, ny) then
          local N = SEEDS[nx][ny][1]
          if N.conn and N.conn.layout_char ~= C.layout_char then
            return false
          end
        end
      end -- for side

      -- this connection is OK!
    end

    return true
  end

  local function decide_layout_symmetry()

    local SYM_LIST = { "x", "y", "xy" }

    local syms  = { "none" }
    local probs = { 10 }

    for _,sym in ipairs(SYM_LIST) do
      if required_seeds(sym) <= R.sw * R.sh and
         is_symmetry_possible(R, sym)
      then
        local prob = 0

        -- check if possible
        if sym == R.symmetry then
          prob = sel(sym == "xy", 6000, 400)
        elseif R.symmetry == "xy" then
          -- TODO: take width/height into account
          prob = 100
        elseif sym == "xy" and (R.symmetry ~= "x") and (R.symmetry ~= "y") then
          -- never upgrade to XY symmetry from no symmetry
          -- because is_symmetry_possible() does not fully test
          -- the double folding of connections.
          prob = 0
        else
          -- TODO: take width/height into account
          prob = sel(sym == "xy", 20, 40)
        end

        if prob > 0 then
          table.insert(syms, sym)
          table.insert(probs, prob)
        end
      end
    end

    R.layout_symmetry = syms[rand_index_by_probs(probs)]

-- dump_layout(R)

    gui.debugf("Layout symmetry @ %s (%s) --> %s\n",
               R:tostr(), R.symmetry or "none", R.layout_symmetry);

    --- FIXME: update layouting area
  end

  local function clear_layout()
    for tx = R.tx1, R.tx2 do for ty = R.ty1, R.ty2 do
      local S = SEEDS[tx][ty][1]
      S.layout = nil
    end end
  end

  local function read_layout()
    local L = {}

    L.layouts = array_2D(R.tw, R.th)

    for tx = R.tx1, R.tx2 do for ty = R.ty1, R.ty2 do
      local x = tx - R.tx1 + 1
      local y = ty - R.ty1 + 1

      local S = SEEDS[tx][ty][1]

      L.layouts[x][y] = S.layout
    end end

    return L
  end

  local function write_layout(L)
    for tx = R.tx1, R.tx2 do for ty = R.ty1, R.ty2 do
      local x = tx - R.tx1 + 1
      local y = ty - R.ty1 + 1

      local S = SEEDS[tx][ty][1]

      S.layout = L.layouts[x][y]
    end end
  end


  local function try_add_conn(list, S, flip_x, flip_y)
    assert(S.conn and S.conn.layout_char)

    local tx, ty = S.sx, S.sy

    if flip_x then tx = R.tx1 + R.otx2 - tx end
    if flip_y then ty = R.ty1 + R.oty2 - ty end

    if not R:valid_T(tx, ty) then
      return
    end

    local T = SEEDS[tx][ty][1]

    local tdir = S.conn_dir

    if flip_x and is_horiz(tdir) then tdir = 10 - tdir end
    if flip_y and is_vert(tdir)  then tdir = 10 - tdir end

-- gui.debugf("  try_add_conn: S @ (%d,%d)  T @ (%d,%d)\n", S.sx,S.sy, tx,ty)

    if not T.conn_dirs then T.conn_dirs = {} end

    T.conn_dirs[tdir] = true

--  dump_layout(R)

    local INFO =
    {
      group_id = 1 + #list,
      conn  = S.conn,
      T = T, tx = tx, ty = ty,
      layout_char = T.layout and T.layout.char,
    }

    if T.layout then
      assert(T.layout.char == S.conn.layout_char)
    else
      T.layout = { char = assert(S.conn.layout_char) }
      T.layout.group_id = INFO.group_id

      T.layout.tdir    = tdir
      T.layout.floor_h = INFO.conn.conn_h
    end

    table.insert(list, INFO)
  end

  local function insert_conns()
gui.debugf("LAYOUT AREA: (%d,%d) .. (%d,%d)\n", R.tx1,R.ty1, R.tx2,R.ty2)
    local list = {}

    for _,C in ipairs(R.conns) do
      local S = C:seed(R)
      
      try_add_conn(list, S, false, false)

      if R.layout_symmetry == "x" then
        try_add_conn(list, S, true, false)
      elseif R.layout_symmetry == "y" then
        try_add_conn(list, S, false, true)
      elseif R.layout_symmetry == "xy" then
        try_add_conn(list, S, false, true)
        try_add_conn(list, S, true,  false)
        try_add_conn(list, S, true,  true)
      end
    end

    return list
  end


  local function mirror_x_dirtab(t)
    if not t then return nil end
    local u = {}
    u[2] = t[2] ; u[4] = t[6]
    u[8] = t[8] ; u[6] = t[4]
    return u
  end

  local function mirror_y_dirtab(t)
    if not t then return nil end
    local u = {}
    u[2] = t[8] ; u[4] = t[4]
    u[8] = t[2] ; u[6] = t[6]
    return u
  end


  local function mirror_horizontally(old_w, new_w)
    for y = R.ty1, R.ty2 do
      for x = new_w, old_w-1 do
        local D = SEEDS[R.tx1 + x][y][1]
        local S = SEEDS[R.tx1 + old_w - 1 - x][y][1]

        D.layout = shallow_copy(S.layout)

        if D.layout then
          local L = D.layout

              if L.char == '<' then L.char = '>'
          elseif L.char == '>' then L.char = '<'
          elseif L.char == 'L' then L.char = 'J'
          elseif L.char == 'J' then L.char = 'L'
          elseif L.char == 'F' then L.char = 'T'
          elseif L.char == 'T' then L.char = 'F'
          elseif L.char == '/' then L.char = '\\'
          elseif L.char =='\\' then L.char = '/'
          end

          D.layout.emergs  = mirror_x_dirtab(S.layout.emergs)
          D.layout.windows = mirror_x_dirtab(S.layout.windows)
        end
      end
    end

    -- restore old width
    R.tx2 = R.tx1 + old_w - 1
    R.tw, R.th = box_size(R.tx1, R.ty1, R.tx2, R.ty2)
  end

  local function mirror_vertically(old_h, new_h)
    for x = R.tx1, R.tx2 do
      for y = new_h, old_h-1 do
        local D = SEEDS[x][R.ty1 + y][1]
        local S = SEEDS[x][R.ty1 + old_h - 1 - y][1]

        D.layout = shallow_copy(S.layout)

        if D.layout then
          local L = D.layout

              if L.char == 'v' then L.char = '^'
          elseif L.char == '^' then L.char = 'v'
          elseif L.char == 'L' then L.char = 'F'
          elseif L.char == 'F' then L.char = 'L'
          elseif L.char == 'J' then L.char = 'T'
          elseif L.char == 'T' then L.char = 'J'
          elseif L.char == '/' then L.char = '\\'
          elseif L.char =='\\' then L.char = '/'
          end

          D.layout.emergs  = mirror_y_dirtab(S.layout.emergs)
          D.layout.windows = mirror_y_dirtab(S.layout.windows)
        end
      end
    end

    -- restore old height
    R.ty2 = R.ty1 + old_h - 1
    R.tw, R.th = box_size(R.tx1, R.ty1, R.tx2, R.ty2)
  end
  

  local function is_fully_connected(EX)
    local g

    for _,E in ipairs(EX) do
      if not g then
        g = E.T.layout.group_id

      elseif g ~= E.T.layout.group_id then
        return false
      end
    end

    return true
  end

  local function merge_groups(EX, id1, id2)
    if id1 > id2 then
      id1,id2 = id2,id1
    end

    for _,E in ipairs(EX) do
      if E.group_id == id2 then
         E.group_id = id1
      end
    end

    for x = R.tx1, R.tx2 do for y = R.ty1, R.ty2 do
      local S = SEEDS[x][y][1]
      
      if S.layout and S.layout.group_id == id2 then
        S.layout.group_id = id1
      end
    end end
  end

  local function dist_to_something(x, y, dir)
    local dx, dy = dir_to_delta(dir)
    local dist = 0

    while true do
      x = x + dx
      y = y + dy

      if not R:valid_T(x, y) then
        return nil
      end

      local T = SEEDS[x][y][1]

      if T.layout and T.layout.char then
        return dist, T
      end

      dist = dist + 1
    end
  end

  local function flood_fill_layout(EX)
    local flood_group = rand_element(EX).group_id

    local poss   = {}
    local emergs = {}

    -- find a seed we can "grow" into a vacant spot
    for tx = R.tx1, R.tx2 do for ty = R.ty1, R.ty2 do
      local T = SEEDS[tx][ty][1]
      if is_digit(T.layout and T.layout.char) then 
        for dir = 2,8,2 do
          local nx, ny = nudge_coord(tx, ty, dir)
          if R:valid_T(nx, ny) then
            local N = SEEDS[nx][ny][1]

            if N.layout and N.layout.char == T.layout.char and
               N.layout.group_id ~= T.layout.group_id
            then
              -- direct connection!
              gui.debugf("direction linkage @ (%d,%d) dir:%d\n", tx, ty, dir)
              merge_groups(EX, T.layout.group_id, N.layout.group_id)
              return 0
            end

            if not N.layout then
              table.insert(poss, { tx=tx, ty=ty, dir=dir })
            end

            if is_digit(N.layout and N.layout.char) and N.layout.group_id ~= T.layout.group_id then
              table.insert(emergs, { tx=tx, ty=ty, dir=dir })
            end
          end
        end -- for side
      end
    end end -- for tx, ty


    if #poss > 0 then
      -- FIXME: prefer one with same 'tdir'
      local PM = rand_element(poss)

      local T = SEEDS[PM.tx][PM.ty][1]
      local N = T:neighbor(PM.dir)

      local stairs = {}

      -- check if new connection can link to something
      for dir = 2,8,2 do if dir ~= 10 - PM.dir then
        local ox, oy = nudge_coord(N.sx, N.sy, dir)
        if R:valid_T(ox, oy) then
          local O = SEEDS[ox][oy][1]

          if O.layout and O.layout.char == T.layout.char and
             O.layout.group_id ~= T.layout.group_id
          then
            -- direct connection!
            gui.debugf("New direct linkage @ (%d,%d) dir:%d\n", N.sx, N.sy, dir)
            merge_groups(EX, T.layout.group_id, O.layout.group_id)

            N.layout = { char = assert(T.layout.char) }
            N.layout.floor_h  = assert(T.layout.floor_h)
            N.layout.group_id    = T.layout.group_id

            return 10
          end

          if is_digit(O.layout and O.layout.char) and O.layout.group_id ~= T.layout.group_id and
             not (is_perpendicular(PM.dir, dir) and
                  (N.sx == R.layout_shared_x or N.sy == R.layout_shared_y))
          then
            table.insert(stairs, { O=O, dir=dir })
          end
        end
      end end -- for dir, if

      if #stairs > 0 then
        -- FIXME: choose least h diff, preference for dir == PM.dir
        local ST = rand_element(stairs)

        local O = assert(ST.O)
        local factor = 2.5

        if is_parallel(ST.dir, PM.dir) then
          factor = 1.0

        elseif (O.sx == R.tx1 or O.sx == R.tx2) and
               (O.sy == R.ty1 or O.sy == R.ty2)
        then
          factor = 0.5  -- turn-90-degree stairs are perfect in a corner
        end

        local STAIR_CHARS =
        {
          ["2/2"] = 'v', ["8/8"] = '^',
          ["4/4"] = '<', ["6/6"] = '>',
          ["2/4"] = 'J', ["4/2"] = 'F',
          ["2/6"] = 'L', ["6/2"] = 'T',
          ["8/4"] = 'T', ["4/8"] = 'L',
          ["8/6"] = 'F', ["6/8"] = 'J',
        }

        N.layout = { char = STAIR_CHARS[tostring(PM.dir) .. "/" .. tostring(ST.dir)] }
        assert(N.layout.char)

        N.layout.stair_z1 = T.layout.floor_h
        N.layout.stair_z2 = O.layout.floor_h

        if is_horiz(PM.dir) and is_vert(ST.dir) then
          N.layout.stair_z1, N.layout.stair_z2 = N.layout.stair_z2, N.layout.stair_z1
        end

        gui.debugf("Added stair @ (%d,%d) dir:%d/%d = '%s'\n", N.sx, N.sy, PM.dir, ST.dir, N.layout.char)
        merge_groups(EX, T.layout.group_id, O.layout.group_id)

        N.layout.group_id = T.layout.group_id
        N.layout.floor_h  = math.max(T.layout.floor_h, O.layout.floor_h)

        return factor * (16 + math.abs(T.layout.floor_h - N.layout.floor_h))
      end

      N.layout = { char = assert(T.layout.char) }
      N.layout.group_id = T.layout.group_id
      N.layout.floor_h  = assert(T.layout.floor_h)
      N.layout.tdir     = PM.dir

      return 10
    end


    -- Emergency linkage!

    assert(#emergs > 0)

    -- FIXME: choose one with least height diff
    local EM = rand_element(emergs)

gui.debugf("Emergency linkage (%d,%d) dir:%d\n", EM.tx, EM.ty, EM.dir);

    local T = SEEDS[EM.tx][EM.ty][1]
    local N = T:neighbor(EM.dir)

    if not T.emergs then T.emergs = {} end
    if not N.emergs then N.emergs = {} end

    if T.layout.floor_h < N.layout.floor_h then
      T.emergs[EM.dir] = true
    else
      N.emergs[10 - EM.dir] = true
    end

    merge_groups(EX, T.layout.group_id, N.layout.group_id)

    return 30 * (16 + math.abs(T.layout.floor_h - N.layout.floor_h))
  end

  local function make_basic_layout_2(EX)
    local cost = gui.random()

    for loop = 1, R.tw * R.th * 4 do
      gui.debugf("MAKE BASIC LAYOUT loop=%d:\n", loop);

      if is_fully_connected(EX) then
        break;  -- complete connected now
      end

      cost = cost + flood_fill_layout(EX)
    end

    gui.debugf("make_basic_layout_2: cost = %1.2f  :-\n", cost)
    dump_layout(R)

    return cost
  end

  function ensure_mirror_x_traversible()
    for y = R.ty1, R.ty2 do
      if SEEDS[R.tx2][y][1].layout then
        return; -- OK
      end
    end

    local visit_y = {}
    rand_shuffle(visit_y, R.th)

    for _,dy in ipairs(visit_y) do
      local y = R.ty1 + (dy-1)
      for x = R.tx1+1, R.tx2 do
        local D = SEEDS[x][y][1]
        local S = SEEDS[x-1][y][1]

        if is_digit(S.layout and S.layout.char) and not D.layout then
          D.layout = { char = S.layout.char }
          D.layout.floor_h = S.layout.floor_h
          assert(D.layout.char)
        end
      end

      if SEEDS[R.tx2][y][1].layout then
        return -- did it
      end
    end

   error("ensure_mirror_x_traversible FAILED!!")
  end

  function ensure_mirror_y_traversible()
    for x = R.tx1, R.tx2 do
      if SEEDS[x][R.ty2][1].layout then
       return; -- OK
      end
    end

    local visit_x = {}
    rand_shuffle(visit_x, R.tw)

    for _,dx in ipairs(visit_x) do
      local x = R.tx1 + (dx-1)
      for y = R.ty1+1, R.ty2 do
        local D = SEEDS[x][y][1]
        local S = SEEDS[x][y-1][1]

        if is_digit(S.layout and S.layout.char) and not D.layout then
          D.layout = { char = S.layout.char }
          D.layout.floor_h = S.layout.floor_h
          assert(D.layout.char)
        end
      end

      if SEEDS[x][R.ty2][1].layout then
        return -- did it
      end
    end

   error("ensure_mirror_y_traversible FAILED!!")
  end

  local function try_junk_side(side)
    local x1,y1, x2,y2 = side_coords(side, R.tx1,R.ty1, R.tx2,R.ty2)

    for x = x1,x2 do for y = y1,y2 do
      local S = SEEDS[x][y][1]
      if S.layout then
        if S.layout.char ~= '#' then
          return -- not possible
        end
      end
    end end -- for x,y

    for x = x1,x2 do for y = y1,y2 do
      local S = SEEDS[x][y][1]
      if not S.layout then
        S.layout = { char='%' }  --!!!!
      end
    end end -- for x,y
  end

  local function decide_windows()
    if R.outdoor then
      return
    end

    for x = R.tx1,R.tx2 do for y = R.ty1,R.ty2 do
      local S = SEEDS[x][y][1]
      if (S.layout and S.layout.char) then
--!!! if is_digit(S.layout and S.layout.char) then
        if not S.layout.windows then S.layout.windows = {} end
        for side = 2,8,2 do

          local N = S:neighbor(side)
          if N and N.room.outdoor
             and not ((x==R.tx1 or x==R.tx2) and (y==R.ty1 or y==R.ty2))
             and rand_odds(99)
          then
gui.debugf("DECIDED WINDOW @ (%d,%d) dir:%d\n", x, y, side)
            S.layout.windows[side] = true
          end
        end  
      end
    end end -- for x,y
  end

  local function apply_windows()
    for x = R.sx1,R.sx2 do for y = R.sy1,R.sy2 do
      local S = SEEDS[x][y][1]
      local L = S.layout
      for side = 2,8,2 do
        local N = S:neighbor(side)
        -- TODO: IN/IN WINDOWS: N.border[10-side].kind = "STRADDLE"
        if L and L.windows and L.windows[side] and N
           and S.border[side].kind == "wall"
        then
gui.debugf("APPLIED WINDOW @ (%d,%d) dir:%d N:%s\n", x, y, side, tostring(N))
          S.border[side].kind = "window"
        end
      end
    end end -- for x,y
  end


  ---| Layout_Indoor |---

  for _,C in ipairs(R.conns) do
    C.layout_char = char_for_height(h_set, C.conn_h)
  end

  gui.debugf("Initial unmirrored layout:\n")
  dump_layout(R);

  decide_layout_symmetry()

  -- update layout area
  local old_w, old_h = box_size(R.tx1, R.ty1, R.tx2, R.ty2)
  local new_w, new_h = size_for_symmetry(R.layout_symmetry)

  R.otx2, R.oty2 = R.tx2, R.ty2

  if new_w < old_w then
    R.tx2 = R.tx1 + new_w - 1
    if (old_w % 2) == 1 then
      R.layout_shared_x = R.tx2
    end
  end

  if new_h < old_h then
    R.ty2 = R.ty1 + new_h - 1
    if (old_h % 2) == 1 then
      R.layout_shared_y = R.ty2
    end
  end

  R.tw, R.th = box_size(R.tx1, R.ty1, R.tx2, R.ty2)


  -- TODO: junk sides


  local best_layout
  local best_cost

  local max_loop = R.sw + R.sh + 3

  for loop = 1,max_loop do
    clear_layout()
    local EX = insert_conns()

    local cost = make_basic_layout_2(EX)

    if not best_layout or cost < best_cost then
      best_layout = read_layout()
      best_cost   = cost
    end
  end

  write_layout(best_layout)

  gui.debugf("Best cost was: %1.2f\n", best_cost)


  if R.layout_symmetry == "x" or R.layout_symmetry == "xy" then
    ensure_mirror_x_traversible()
  end

  if R.layout_symmetry == "y" or R.layout_symmetry == "xy" then
    ensure_mirror_y_traversible()
  end


  for x = R.tx1,R.tx2 do for y = R.ty1,R.ty2 do
    local S = SEEDS[x][y][1]
    if S.layout then
      S.layout.on_path = true
    end
  end end -- for x,y


  gui.debugf("BARE LAYOUT:\n")
  dump_layout(R);


  if R.purpose then
    -- TODO !!!!  select seed(s) for purpose
  end


  -- TODO: boundary shape
  local j_sides = { 2,8, 4,6 }
  if R.tw > R.th then j_sides = { 4,6, 2,8 } end

  for _,side in ipairs(j_sides) do
    try_junk_side(side)
  end


  -- TODO: fill holes

  -- TEMP JUNK !!!
  for loop = 1,6 do
  for x = R.tx1,R.tx2 do for y = R.ty1,R.ty2 do
    local S = SEEDS[x][y][1]
---#    if not S.layout then
---#      S.layout = { char = '%' }
---#    end
    if not S.layout then
--    S.layout_char = "%"
      local sides = { 2,4,6,8 }
      rand_shuffle(sides)
      for _,side in ipairs(sides) do
        local nx, ny = nudge_coord(x, y, side)
        if R:valid_T(nx, ny) then
          local N = SEEDS[nx][ny][1]
          if is_digit(N.layout and N.layout.char) then
            S.layout = { char = N.layout.char }
            S.layout.floor_h = assert(N.layout.floor_h) -- -16
            assert(S.layout.char)
            if rand_odds(25) then S.layout.pillar = true end
            break;
          end
        end
      end -- for side
    end
  end end -- for x,y
  end -- for loop


  -- kill the conn_dirs before expanding the layout
  -- (merely to aid debugging)
  for x = R.tx1,R.tx2 do for y = R.ty1,R.ty2 do
    SEEDS[x][y][1].conn_dirs = nil
  end end


  decide_windows()


  if new_w < old_w then
    mirror_horizontally(old_w, new_w)
  end

  if new_h < old_h then
    mirror_vertically(old_h, new_h)
  end


  gui.debugf("FINAL LAYOUT:\n")
  dump_layout(R);


  apply_windows()
end


function Room_LayItOut(R)

  -- set seed range for layouting algorithms to whole room
  R.tx1, R.ty1 = R.sx1, R.sy1
  R.tx2, R.ty2 = R.sx2, R.sy2

  R.tw, R.th = box_size(R.tx1, R.ty1, R.tx2, R.ty2)


  if R.kind == "stairwell" then
    -- nothing to do (handled in builder.lua)
    return

  elseif R.kind == "hallway" then
    Layout_Hallway(R)
    return

  elseif R.outdoor then
    Layout_Outdoor(R)
    return
  end
  
  -- TODO: decide 'special' rooms:
  --       (A) pathway across nukage or lava pit
  --       (B) hallway which surrounds an inner room

  Layout_Indoor(R);


  --[[
  
  -- make rooms with lots of 'junk space' smaller sometimes

  local lx,ly, hx,hy = calc_conn_area(R)

  local jl = lx - R.sx1
  local jr = R.sx2 - hx
  local jb = ly - R.sy1
  local jt = R.sy2 - hy

  local n_sx1 = R.sx1
  local n_sy1 = R.sy1
  local n_sx2 = R.sx2
  local n_sy2 = R.sy2

--!!!  if not R.symmetry or R.symmetry == "y" then
--!!!    while jl >= 2 and rand_odds(99) do jl = jl-1 ; n_sx1 = n_sx1 + 1 end
--!!!    while jl >= 1 and rand_odds( 3) do jl = jl-1 ; n_sx1 = n_sx1 + 1 end
--!!!
--!!!    while jr >= 2 and rand_odds(99) do jr = jr-1 ; n_sx2 = n_sx2 - 1 end
--!!!    while jr >= 1 and rand_odds( 3) do jr = jr-1 ; n_sx2 = n_sx2 - 1 end
--!!!  end
--!!!
--!!!  if not R.symmetry or R.symmetry == "x" then
--!!!    while jb >= 2 and rand_odds(99) do jb = jb-1 ; n_sy1 = n_sy1 + 1 end
--!!!    while jb >= 1 and rand_odds( 3) do jb = jb-1 ; n_sy1 = n_sy1 + 1 end
--!!!
--!!!    while jt >= 2 and rand_odds(99) do jt = jt-1 ; n_sy2 = n_sy2 - 1 end
--!!!    while jt >= 1 and rand_odds( 3) do jt = jt-1 ; n_sy2 = n_sy2 - 1 end
--!!!  end

  Junk_fill_room(R, n_sx1, n_sy1, n_sx2, n_sy2)


  lx,ly, hx,hy = R.sx1,R.sy1, R.sx2,R.sy2


  local function junk_side(side)
    local dx,dy = dir_to_delta(10-side)
    local x1,y1, x2,y2 = side_coords(side, lx,ly, hx,hy)

    for x = x1,x2 do for y = y1,y2 do
      local S = SEEDS[x][y][1]
      if S.layout_char and S.layout_char ~= "%" then
        SEEDS[x+dx][y+dy][1].layout_char = S.layout_char
      end
      if not S.layout_char then
        S.layout_char = "%"
      end
    end end -- for x,y

    if side == 2 then ly = ly + 1 end
    if side == 8 then hy = hy - 1 end
    if side == 4 then lx = lx + 1 end
    if side == 6 then hx = hx - 1 end
  end


  local function try_junk_side(side, opp_sym)

    local long,deep = get_long_deep(side, hx-lx+1, hy-ly+1)

    -- enough room?
    if deep < sel(opp_sym,5,4) then return end

    local dx,dy = dir_to_delta(10-side)
    local x1,y1, x2,y2 = side_coords(side, lx,ly, hx,hy)

    -- side must have connection
    local has_conn = false
    for x = x1,x2 do for y = y1,y2 do
      local S = SEEDS[x][y][1]
      if S.layout_char then
        has_conn = true
        break;
      end
    end end -- for x,y

    if not has_conn then return end

    -- must not be any connections in next row/column
    for x = x1+dx,x2+dx do for y = y1+dy,y2+dy do
      local S = SEEDS[x][y][1]
      if S.layout_char then
        return
      end
    end end -- for x,y

    -- OK !!
    gui.debugf("JUNKED SIDE %d\n", side)

    junk_side(side)

    if opp_sym then
      junk_side(10 - side)
    end

---###    if side == 2 or side == 8 then
---###      if R.symmetry == "y" or R.symmetry == "xy" then
---###        junk_side(10 - side)
---###      end
---###    else -- side == 4 or side == 6
---###      if R.symmetry == "x" or R.symmetry == "xy" then
---###        junk_side(10 - side)
---###      end
---###    end

    if R.symmetry == "tp" then
      local SIDE_MAP = { [2]=4, [4]=2, [6]=8, [8]=6 }
      junk_side(SIDE_MAP[side])
    elseif R.symmetry == "tn" then
      local SIDE_MAP = { [2]=6, [6]=2, [4]=8, [8]=4 }
      junk_side(SIDE_MAP[side])
    end

    dump_layout(R)
  end


  for loop = 1,5 do
    -- TODO: randomise side ordering [make a list]
    
    if not R.symmetry or R.symmetry == "x" or R.symmetry == "y"
                      or R.symmetry == "xy"
    then
      try_junk_side(2, R.symmetry == "y" or R.symmetry == "xy")
      try_junk_side(4, R.symmetry == "x" or R.symmetry == "xy")
    
    elseif R.symmetry == "tn" or R.symmetry == "tp" then
      try_junk_side(2)
      try_junk_side(8)
    end

    if not R.symmetry or R.symmetry == "x" then
      try_junk_side(8)
    end

    if not R.symmetry or R.symmetry == "y" then
      try_junk_side(6)
    end

  end

  --]]

--  gui.debugf("JUNK SPACE W:%d L:%d R:%d  H:%d B:%d T:%d  @ %s\n",
--             R.sw, jl, jr,  R.sh, jb, jt,  R:tostr())

end


function Rooms_lay_out()

  gui.printf("\n--==| Rooms_lay_out |==--\n\n")

  PLAN.theme = GAME.themes["TECH"] -- FIXME

  for _,R in ipairs(PLAN.all_rooms) do
    Room_SetupTheme(R)
  end
  
  for _,R in ipairs(PLAN.scenic_rooms) do
    Room_SetupTheme_Scenic(R)
  end

  for _,R in ipairs(PLAN.all_rooms) do
--!!!!    Room_LayItOut(R)
  end

end

