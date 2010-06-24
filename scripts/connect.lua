------------------------------------------------------------------------
--  CONNECTIONS
------------------------------------------------------------------------
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
------------------------------------------------------------------------

--[[ *** CLASS INFORMATION ***

class CONN
{
  kind   : keyword  -- "normal", "teleport", "intrusion"
  lock   : QUEST

  K1, K2 : sections
  R1, R2 : rooms

  dir    : direction 2/4/6/8 (from K1 to K2)
           nil for teleporters.

  conn_h : floor height for connection
}

--------------------------------------------------------------]]

require 'defs'
require 'util'


CONN_CLASS = {}

function CONN_CLASS.new(K1, K2, kind, dir)
  local C = { K1=K1, K2=K2, R1=K1.room, R2=K2.room, kind=kind, dir=dir }
  table.set_class(C, CONN_CLASS)
  return C
end

function CONN_CLASS.neighbor(self, R)
  return sel(R == self.R1, self.R2, self.R1)
end

function CONN_CLASS.section(self, R)
  return sel(R == self.R1, self.K1, self.K2)
end

function CONN_CLASS.what_dir(self, R)
  if self.dir then
    return sel(R == self.R1, self.dir, 10 - self.dir)
  end
  return nil
end

function CONN_CLASS.tostr(self)
  return string.format("CONN [%d,%d -> %d,%d]",
         self.K1.kx, self.K1.ky,
         self.K2.kx, self.K2.ky)
end

function CONN_CLASS.swap(self)
  self.K1, self.K2 = self.K2, self.K1
  self.R1, self.R2 = self.R2, self.R1

  if self.dir then self.dir = 10 - self.dir end
end



BIG_CONNECTIONS =
{
  ---==== TWO EXITS ====---

  -- pass through, directly centered
  P1 = { w=3, h=2, prob=22, exits={ 22, 58 }, symmetry="x" },
  P2 = { w=3, h=3, prob=22, exits={ 22, 88 }, symmetry="x" },

  -- pass through, opposite edges
  O1 = { w=2, h=1, prob=27, exits={ 12, 28 } },
  O2 = { w=2, h=2, prob=20, exits={ 12, 58 } },
  O3 = { w=2, h=3, prob=10, exits={ 12, 88 } },

  O4 = { w=3, h=1, prob=27, exits={ 12, 38 } },
  O5 = { w=3, h=2, prob=20, exits={ 12, 68 } },
  O6 = { w=3, h=3, prob=10, exits={ 12, 98 } },

  -- L shape
  L1 = { w=2, h=1, prob=50, exits={ 14, 28 } },
  L2 = { w=2, h=2, prob=40, exits={ 14, 58 } },
  L3 = { w=2, h=3, prob=30, exits={ 14, 88 } },

  L4 = { w=3, h=1, prob=50, exits={ 14, 38 } },
  L5 = { w=3, h=3, prob=20, exits={ 14, 98 } },

  ---==== THREE EXITS ====---
  
  -- T shape, turning left and right
  T1 = { w=1, h=2, prob=50, exits={ 12, 44, 46 }, symmetry="x" },
  T2 = { w=1, h=3, prob=50, exits={ 12, 74, 76 }, symmetry="x" },

  T4 = { w=3, h=1, prob=70, exits={ 22, 14, 36 }, symmetry="x" },
  T5 = { w=3, h=2, prob=70, exits={ 22, 44, 66 }, symmetry="x" },
  T6 = { w=3, h=3, prob=70, exits={ 22, 74, 96 }, symmetry="x" },

  -- Y shape
  Y1 = { w=3, h=1, prob=45, exits={ 22, 18, 38 }, symmetry="x" },
  Y2 = { w=3, h=2, prob=45, exits={ 22, 48, 68 }, symmetry="x" },
  Y3 = { w=3, h=3, prob=45, exits={ 22, 78, 98 }, symmetry="x" },

  -- F shapes
  F1 = { w=2, h=1, prob=21, exits={ 14, 12, 22 } },
  F2 = { w=2, h=2, prob=21, exits={ 44, 12, 22 } },
  F3 = { w=2, h=3, prob=21, exits={ 74, 12, 22 } },

  F4 = { w=3, h=1, prob=15, exits={ 14, 12, 32 } },
  F5 = { w=3, h=2, prob=24, exits={ 44, 12, 32 } },
  F6 = { w=3, h=3, prob=15, exits={ 74, 12, 32 } },

  F7 = { w=3, h=1, prob=13, exits={ 14, 22, 32 } },
  F8 = { w=3, h=2, prob=13, exits={ 44, 22, 32 } },

  ---==== FOUR EXITS ====---

  -- cross shape, all stems perfectly centered
  XP = { w=3, h=3, prob=400, exits={ 22, 44, 66, 88 }, symmetry="xy" },

  -- cross shape, stems at other places
  X1 = { w=3, h=1, prob=90, exits={ 22, 28, 14, 36 }, symmetry="xy" },
  X2 = { w=3, h=2, prob=90, exits={ 22, 58, 44, 66 }, symmetry="xy" },
  X3 = { w=3, h=3, prob=90, exits={ 22, 88, 74, 96 }, symmetry="xy" },

  -- H shape
  H1 = { w=2, h=2, prob=12, exits={ 12,22, 48,58 }, symmetry="xy" },
  H2 = { w=2, h=3, prob=12, exits={ 12,22, 78,88 }, symmetry="xy" },
  H3 = { w=3, h=2, prob=18, exits={ 12,32, 48,68 }, symmetry="xy" },
  H4 = { w=3, h=3, prob=18, exits={ 12,32, 78,98 }, symmetry="xy" },

  -- double-stem T shape
  TT1 = { w=2, h=2, prob=13, exits={ 12,22, 44,56 }, symmetry="x" },
  TT2 = { w=2, h=3, prob=13, exits={ 12,22, 74,86 }, symmetry="x" },
  TT3 = { w=3, h=2, prob=24, exits={ 12,32, 44,66 }, symmetry="x" },
  TT4 = { w=3, h=3, prob=24, exits={ 12,32, 74,96 }, symmetry="x" },

  -- swastika shape
  SWA1 = { w=2, h=2, prob=16, exits={ 12, 26, 44, 58 } },
  SWA2 = { w=3, h=2, prob=16, exits={ 12, 36, 44, 68 } },
  SWA3 = { w=3, h=3, prob=16, exits={ 12, 36, 74, 98 } },

  -- double F shape
  FF1 = { w=3, h=2, prob=15, exits={ 14,44, 22,32 } },
  FF2 = { w=3, h=2, prob=17, exits={ 14,44, 12,32 } },
  FF3 = { w=3, h=3, prob=15, exits={ 44,74, 22,32 } },
  FF4 = { w=3, h=3, prob=31, exits={ 14,74, 12,32 } },
}


CONN_POSITION_X = { 1,2,3, 1,2,3, 1,2,3 }
CONN_POSITION_Y = { 1,1,1, 2,2,2, 3,3,3 }



function Connect_test_big_conns()
  local require_volume -- = 6

  local function dump_exits(name, info)
    local W = assert(info.w)
    local H = assert(info.h)

    -- option to only show rooms of a certain size
    if require_volume and (W*H) ~= require_volume then
      return
    end

    name = name .. ":" .. "      "

    local DIR_CHARS = { [2]="|", [8]="|", [4]=">", [6]="<" }

    local P = table.array_2D(W+2, H+2)

    for y = 0,H+1 do for x = 0,W+1 do
      P[x+1][y+1] = sel(geom.inside_box(x,y, 1,1, W,H), "#", " ")
    end end

    for _,exit in ipairs(info.exits) do
      local pos = int(exit / 10)
      local dir =     exit % 10

      local x = CONN_POSITION_X[pos]
      local y = CONN_POSITION_Y[pos]

      assert(x and y)
      assert(geom.inside_box(x,y, 1,1, W,H))

      local nx, ny = geom.nudge(x, y, dir)
      assert(nx==0 or nx==W+1 or ny==0 or ny==H+1)

      if P[nx+1][ny+1] ~= " " then
        gui.printf("spot: (%d,%d):%d to (%d,%d)\n", x,y,dir, nx,ny)
        error("Bad branch!")
      end

      P[nx+1][ny+1] = DIR_CHARS[dir] or "?"
    end

    for y = H+1,0,-1 do
      local line = "      "
      
      if y == H then
        line = string.sub(name, 1, 6)
      end

      for x = 0,W+1 do
        line = line .. P[x+1][y+1]
      end

      gui.printf("%s\n", line)
    end

    gui.printf("\n")
  end

  gui.printf("\n============ BIG CONNECTIONS ==============\n\n")

  local name_list = {}

  for name,_ in pairs(BIG_CONNECTIONS) do
    table.insert(name_list, name)
  end

  table.sort(name_list)

  for _,name in ipairs(name_list) do
    dump_exits(name, BIG_CONNECTIONS[name])
  end

  gui.printf("\n===========================================\n\n")

  error("Connect_test_big_conns finished.")
end


------------------------------------------------------------------------


function Connect_decide_start_room()

  local function eval_room(R)
    local cost = R.sw * R.sh

    cost = cost + 10 * (gui.random() ^ 2)

    gui.debugf("Start cost @ %s (seeds:%d) --> %1.3f\n", R:tostr(), R.sw * R.sh, cost)

    return cost
  end

  ---| Connect_decide_start_room |---

  for _,R in ipairs(LEVEL.all_rooms) do
    R.start_cost = eval_room(R)
  end

  local start, index = table.pick_best(LEVEL.all_rooms,
    function(A, B) return A.start_cost < B.start_cost end)

  gui.printf("Start room: %s\n", start:tostr())

  -- move it to the front of the list
  table.remove(LEVEL.all_rooms, index)
  table.insert(LEVEL.all_rooms, 1, start)

  LEVEL.start_room = start

  start.purpose = "START"
end


function Connect_rooms()

  -- a "branch" is a room with 3 or more connections.
  -- a "stalk"  is a room with two connections.

  local function initial_groups()
    for index,R in ipairs(LEVEL.all_rooms) do
      R.conn_group = index
      R.conn_rand  = gui.random()
    end
  end

  local function merge_groups(id1, id2)
    if id1 > id2 then id1,id2 = id2,id1 end

    for _,R in ipairs(LEVEL.all_rooms) do
      if R.conn_group == id2 then
        R.conn_group = id1
      end
    end
  end


  local function already_connected(K1, K2)
    if not (K1 and K2 and K1.room) then return false end
    
    for _,C in ipairs(K1.room.conns) do
      if (C.K1 == K1 and C.K2 == K2) or
         (C.K1 == K2 and C.K2 == K1)
      then
        return true
      end
    end
  end


  local function can_connect(K1, K2)
    if not (K1 and K2) then return false end

    local R = K1.room
    local N = K2.room

    if not (R and N) then return false end

    if R.conn_group == N.conn_group then return false end

    if R.kind == "scenic" then return false end
    if N.kind == "scenic" then return false end

    -- only one way out of the starting room
    if R.purpose == "START" and #R.conns >= 1 then return false end
    if N.purpose == "START" and #N.conns >= 1 then return false end

    return true
  end

  local function good_connect(K1, K2)
    if not can_connect(K1, K2) then
      return false
    end

    local R = K1.room
    local N = K2.room

    -- more than 4 connections is usually too many
    if R.full or (#R.conns >= 4 and not R.natural) then return false end
    if N.full or (#N.conns >= 4 and not N.natural) then return false end

    -- don't fill small rooms with lots of connections
    if R.sw <= 4 and R.sh <= 4 and #R.conns >= 3 then return false end
    if N.sw <= 4 and N.sh <= 4 and #N.conns >= 3 then return false end

    return true
  end


  local function add_connection(K1, K2, kind, dir)
    local R = assert(K1.room)
    local N = assert(K2.room)

--stderrf("add_connection: K%d,%d --> K%d,%d  %s --> %s  %d,%d\n",
--      K1.kx, K1.ky, K2.kx, K2.ky, R:tostr(), N:tostr(), R.conn_group, N.conn_group);

    merge_groups(R.conn_group, N.conn_group)

    local C = CONN_CLASS.new(K1, K2, kind, dir)

    table.insert(LEVEL.all_conns, C)

    table.insert(R.conns, C)
    table.insert(N.conns, C)

    K1.num_conn = K1.num_conn + 1
    K2.num_conn = K2.num_conn + 1
  end


  local function handle_shaped_room(R)
    local mid_K = LEVEL.section_map[R.shape_kx][R.shape_ky]
    assert(mid_K and mid_K.room == R)

    -- determine optimal locations, which are at the extremities of
    -- the shape and going the same way (e.g. for "plus" shape, they
    -- are the North end going North, East end going East etc...)
    local optimal_locs = {}

    for dir = 2,8,2 do
      local N = mid_K:neighbor(dir)

      if N and N.room == R then
        local N2 = N:neighbor(dir)
        if N2 and N2.room == R then
          N = N2
        end
        table.insert(optimal_locs, { K=N, dir=dir })
      end
    end

    -- for T shapes, sometimes try to go out the middle section
    if R.shape == "T" and rand.odds(25) then
      for dir = 2,8,2 do
        local N = mid_K:neighbor(dir)
        if N and N.room ~= R then
          table.insert(optimal_locs, { K=mid_K, dir=dir })
          break;
        end
      end
    end

    -- actually try the connections

--stderrf("ADDING CONNS TO %s SHAPED %s\n", R.shape, R:tostr())

    for _,loc in ipairs(optimal_locs) do
      local K = loc.K
      local N = loc.K:neighbor(loc.dir)
--stderrf("  optimal loc: K(%d,%d) dir=%d\n", K.kx, K.ky, loc.dir)

      if K.num_conn > 0 then
        -- OK
      elseif good_connect(K, N) then
        add_connection(K, N, "normal", loc.dir)
      else
        -- try the other sides
        for dir = 2,8,2 do
          local N = loc.K:neighbor(dir)
          if good_connect(K, N) then
            add_connection(K, N, "normal", dir)
            break;
          end
        end
      end
    end

--stderrf("DONE\n")

    -- mark room as full (prevent further connections) if all the
    -- optimal locations worked.  For "plus" shaped rooms, three out
    -- of four ain't bad.
    if #R.conns >= sel(R.shape == "L", 2, 3) then
      R.full = true
    end
  end


  local function test_or_set_pattern(do_it, R, info, MORPH)
    local transpose = bit.btest(MORPH, 1)
    local mirror_x  = bit.btest(MORPH, 2)
    local mirror_y  = bit.btest(MORPH, 4)

    -- size check
    if R.kw ~= sel(transpose, info.h, info.w) or
       R.kh ~= sel(transpose, info.w, info.h)
    then
      return false
    end

    local num_already = 0

    for _,exit in ipairs(info.exits) do
      local pos = int(exit / 10)
      local dir =     exit % 10

      local x = CONN_POSITION_X[pos] - 1
      local y = CONN_POSITION_Y[pos] - 1

      if transpose then
        x,y = y,x
        dir = geom.TRANSPOSE[dir]
      end

      if mirror_x then
        x = R.kw - 1 - x
        if geom.is_horiz(dir) then dir = 10-dir end
      end

      if mirror_y then
        y = R.kh - 1 - y
        if geom.is_vert(dir) then dir = 10-dir end
      end

      assert(0 <= x and x < R.kw)
      assert(0 <= y and y < R.kh)

      local K = LEVEL.section_map[R.kx1 + x][R.ky1 + y]
      assert(K.room == R)

      local N = K:neighbor(dir)

      if already_connected(K, N) then
        num_already = num_already + 1

      elseif not can_connect(K, N) then
        return false
      
      elseif do_it then
        add_connection(K, N, "normal", dir)
      end
    end

    if not do_it and num_already < #R.conns then
      return false
    end

    return true
  end

  local function try_big_pattern(R, info)
    --
    -- MORPH VALUES
    --   bit 0 : transpose the pattern or not
    --   bit 1 : mirror horizontally or not
    --   bit 2 : mirror vertically or not
    --
    -- (transpose is done before mirroring)
    --
    local morphs = { 0,1,2,3,4,5,6,7 }

    rand.shuffle(morphs)

    for _,MORPH in ipairs(morphs) do
      if test_or_set_pattern(false, R, info, MORPH) then
stderrf("BIG PATTERN %s morph:%d in %s\n", info.name, MORPH, R:tostr())
         test_or_set_pattern(true,  R, info, MORPH)
         return true
      end
    end
  end


  local function visit_big_room(R)
    if R.shape ~= "rect" and R.shape ~= "odd" then
      handle_shaped_room(R)
      return
    end

    if R.shape == "odd" then
      -- handle_natural_room(R)
      return
    end

    -- find all BIG-CONN patterns which match this room
    local patterns = {}

    for name,info in pairs(BIG_CONNECTIONS) do
      if (R.kw == info.w and R.kh == info.h) or
         (R.kw == info.h and R.kh == info.w)
      then
        patterns[name] = info.prob
      end
    end

    while not table.empty(patterns) do
      local name = rand.key_by_probs(patterns)

      patterns[name] = nil  -- don't try it again

      if try_big_pattern(R, BIG_CONNECTIONS[name]) then
        -- SUCCESS
        R.full = true
        return
      end
    end
  end


  local function big_room_score(R)
    local score = 0

    if R.shape == "plus" then
      score = 5
    elseif R.shape == "L" and (R.shape_kx == 1 or R.shape_kx == LEVEL.W)
                          and (R.shape_ky == 1 or R.shape_ky == LEVEL.H)
    then
      -- L shape at optimal position (map corner)
      score = 4
    elseif R.shape ~= "rect" or R.kw >= 3 or R.kh >= 3 then
      score = 3
    elseif R.kw >= 2 and R.kh >= 2 then
      score = 2
    elseif R.kw >= 2 or R.kh >= 2 then
      score = 1
    end

    return score + 2.1 * (R.conn_rand ^ 0.5)
  end


  local function branch_big_rooms()
    local visits = table.copy(LEVEL.all_rooms)

    for _,R in ipairs(visits) do
      R.big_score = big_room_score(R)
    end

    table.sort(visits, function(A, B) return A.big_score > B.big_score end)

    for _,R in ipairs(visits) do
      visit_big_room(R)
    end
  end


  local function visit_small_room(R)
    if #R.conns >= 2 then return end

    local list = {}

    for x = R.kx1,R.kx2 do for y = R.ky1,R.ky2 do
      local K = LEVEL.section_map[x][y]
      if K.room == R then

        for dir = 2,8,2 do
          local N = K:neighbor(dir)

          if good_connect(K, N) and #N.room.conns < 2 then
            table.insert(list, { K=K, N=N, dir=dir })
          end
        end

      end
    end end -- x, y

    if #list == 0 then return end

    local loc = table.pick_best(list,
        function(A, B) return A.K.room.small_score < B.K.room.small_score end)

    add_connection(loc.K, loc.N, "normal", loc.dir)
  end


  local function branch_small_rooms()

    -- Goal here is to make stalks

    local visits = table.copy(LEVEL.all_rooms)

    for _,R in ipairs(visits) do
      R.small_score = R.svolume + R.conn_rand*5
    end

    table.sort(visits, function(A, B) return A.small_score < B.small_score end)

    for _,R in ipairs(visits) do
      if R.kw * R.kh <= 2 then
        visit_small_room(R)
      end
    end
  end


  local function emergency_branches()
    
    -- TODO: teleporters

    local visits = { }
    local SIDES = { 2,4,6,8 }

    for kx = 1,LEVEL.W do for ky = 1,LEVEL.H do
      rand.shuffle(SIDES)
      table.insert(visits, { x=kx, y=ky, sides=table.copy(SIDES) })
    end end

    rand.shuffle(visits)

    for side_idx = 1,4 do
      for _,V in ipairs(visits) do

        local dir = V.sides[side_idx]
        local K = LEVEL.section_map[V.x][V.y]
        local N = K:neighbor(dir)

        if can_connect(K, N) then
          add_connection(K, N, "normal", dir)
        end

      end -- for V
    end -- for side_idx
  end


  local function natural_flow(R, visited)
    assert(R.kind ~= "scenic")

    if R.conn_group ~= 1 then
      error("Connecting rooms failed: separate groups exist")
    end

--stderrf("%s : conn_group=%d\n", R:tostr(), R.conn_group or -1)
    visited[R] = true

    for _,C in ipairs(R.conns) do
      if R == C.R2 and not visited[C.R1] then
        C:swap()
      end
      if R == C.R1 and not visited[C.R2] then
        -- recursively handle adjacent room
        natural_flow(C.R2, visited)
        C.R2.entry_conn = C
      end
    end
  end


  --==| Connect_rooms |==--

  gui.printf("\n--==| Connecting Rooms |==--\n\n")

  table.name_up(BIG_CONNECTIONS)

  Connect_decide_start_room()

  -- give each room a 'conn_group' value, starting at one.
  -- connecting two rooms will merge the groups together.
  -- at the end, only a single group will remain (#1).
  initial_groups()

  Levels.invoke_hook("connect_rooms", LEVEL.seed)

  branch_big_rooms()
  branch_small_rooms()

  emergency_branches()

  -- update connections so that 'src' and 'dest' follow the natural
  -- flow of the level, i.e. player always walks src -> dest (except
  -- when backtracking).
  natural_flow(LEVEL.start_room, {})
end

