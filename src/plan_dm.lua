----------------------------------------------------------------
-- PLANNER : DeathMatch
----------------------------------------------------------------
--
--  Oblige Level Maker (C) 2006 Andrew Apted
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


function show_dm_links(p)

  local function show_cell(c,ky)

    local function chk(kx)
      if not c then return " " end

      local side = (ky-1)*3 + kx
      local link = c.link[side]

      if not link then return " " end

      local dx, dy = dir_to_delta(side)

      if dx < 0 then return "<" end
      if dx > 0 then return ">" end

      if dy < 0 then return "v" end
      if dy > 0 then return "^" end

      return "?"
    end

    for kx = 1,3 do
      io.stderr:write(chk(kx))
    end
    io.stderr:write("|")
  end

  local function divider(len)
    for i = len,1,-1 do
      io.stderr:write("---+")
    end
    io.stderr:write("\n")
  end

  -- BEGIN show_dm_links --

  divider(p.w)

	local x, y
	for y = p.h,1,-1 do
    for row = 3,1,-1 do
      for x = 1,p.w do
        show_cell(p.cells[x][y], row)
      end
      io.stderr:write("\n")
	  end
    divider(p.w)
	end
end


function choose_dm_thing(p, LIST, adjusted)
  local wp_names = {}
  local wp_probs = {}

  for name,prob in pairs(LIST) do
    local used_count = p.used_items[name] or 0

    table.insert(wp_names, name)
    table.insert(wp_probs, prob / (1.5 + sel(adjusted,used_count,0)))
  end

  local idx = rand_index_by_probs(wp_probs)
  local name = wp_names[idx]

  -- increase usage count
  p.used_items[name] = (p.used_items[name] or 0) + 1
  return name
end


function plan_dm_arena()

	local p = get_base_plan(PL_W, PL_H)

  p.deathmatch = true


  local function insert_link(c, dir)
    local dx, dy = dir_to_delta(dir)
    local other = p.cells[c.x+dx][c.y+dy]

    create_link(p, c, other, dir)
  end

  local function initial_links()
    for x = 1,p.w do
      for y = 1,p.h do
        if x < p.w then insert_link(p.cells[x][y], 6) end
        if y < p.h then insert_link(p.cells[x][y], 8) end
      end
    end
  end

  local function test_coverage(sx, sy)
    local visited = array_2D(p.w, p.h)
    local count

    visited[sx][sy] = true  -- seed point
    
    for loop = 1,(p.w + p.h + 10) do
      count = 0

      -- flood-fill type algorithm
      for x = 1,p.w do for y = 1,p.h do
        local c = p.cells[x][y]
        if visited[x][y] then
          count = count + 1
          for dir = 2,8,2 do
            if c.link[dir] then
              local other = link_other(c.link[dir], c)
              visited[other.x][other.y] = true
              assert(other.link[10 - dir] == c.link[dir])
            end
          end
        end
      end end
    end
print("COVERAGE", count)
    return count == (p.w * p.h)
  end

  local function remove_dm_links(num)

    local coords = {}
    local index = 1

    rand_shuffle(coords, p.w * p.h * 2)

    local x, y, dir

    local function decode_next()
      if index > #coords then return false end

      x = coords[index] - 1
      index = index + 1

      dir = ((x % 2) == 0) and 6 or 8
      x = math.floor(x / 2)
      
      y = 1 + math.floor(x / p.w)
      x = 1 + (x % p.w)

      return true
    end

    local function remove_one_link()
      while decode_next() do
        if (x == p.w and dir == 6) or
           (y == p.h and dir == 8) then
          -- ignore the invalid links
        else
          local c = p.cells[x][y]

          if c.link[dir] then
            other = link_other(c.link[dir], c)

            if links_in_cell(c) > 2 and links_in_cell(other) > 2 then
              c.link[dir] = nil
              other.link[10 - dir] = nil
              return
            end
          end
        end
      end
    end

    for idx = 1,num do
      remove_one_link()
    end
  end

  local function liquid_for_seed(theme)
    if rand_odds(64) then
      return nil
    end

    if theme.bad_liquid == p.liquid.name then
      return find_liquid(theme.good_liquid)
    end

    if theme.good_liquid and rand_odds(40) then
      return find_liquid(theme.good_liquid)
    end

    return p.liquid
  end

  local function unused_theme_pos()
    for loop = 1,999 do
      local x,y = random_cell(p)
      if not p.cells[x][y].theme then return x, y end
    end
  end

  local function grow_dm_themes()
    local x_order = {}
    local y_order = {}
    local dir_order = { 2,4,6,8 }

    rand_shuffle(x_order, p.w)
    rand_shuffle(y_order, p.h)
    rand_shuffle(dir_order)

    for zz1,cx in ipairs(x_order) do
      for zz2,cy in ipairs(y_order) do
        for zz3,dir in ipairs(dir_order) do
          local dx, dy = dir_to_delta(dir)
          local c = p.cells[cx][cy]
          assert(c)

          if c.theme and valid_cell(p, cx+dx,cy+dy) then
            local other = p.cells[cx+dx][cy+dy]
            if not other.theme then
              other.theme = c.theme
              other.liquid = c.liquid
            end
          end
        end
        rand_shuffle(dir_order)
      end
      rand_shuffle(y_order)
    end
  end

  local function choose_dm_themes()
    -- how many themes?
    local min_t = 1
    if p.h >= 4 then min_t = 2 end
    if p.w >= 6 then min_t = 3 end

    local num_themes = rand_irange(min_t, p.h)
    assert(num_themes <= #ALL_THEMES)
print("NUMBER of THEMES:", num_themes)

    local theme_list = {}
    rand_shuffle(theme_list, #ALL_THEMES)

    -- place themes at random spots on the plan,
    -- then "grow" them until all cells are themed.
    for i =1,num_themes do
      local cx, cy = unused_theme_pos()
      if cx then
        local c = p.cells[cx][cy]
        c.theme = ALL_THEMES[theme_list[i]]
        c.liquid = liquid_for_seed(c.theme)
      end
    end

    for pass = 1,(p.w+p.h+4) do
      grow_dm_themes()
      con.ticker();
    end

  end

  local function create_dm_links(min_links, max_links)
    local min_links = p.w * p.h
    local max_links = p.w * (p.h-1) + p.h * (p.w-1)

    if min_links < max_links then
      min_links = min_links + 1
    end

    for tries = 1,50 do
      local num_links = rand_irange(min_links, max_links)

      for tries = 1,5 do
        print(string.format("TRYING: %d <= %d <= %d", min_links, num_links, max_links))

        initial_links()

        remove_dm_links(max_links - num_links)
        
        if test_coverage(1,1) then return end  -- Yay, success!
      end
    end
    error("FAILED TRYING TO CREATING LINKS")
  end

  local function select_heights()
    -- FIXME: TEMP JUNK
    for zzz,c in ipairs(p.all_cells) do
      c.floor_h = rand_index_by_probs{ 1,2,4,2,1 } * 32 - 32
    end
  end

  local function add_doors()
    for zzz,link in ipairs(p.all_links) do
      -- FIXME: theme based (more doors in bases)
      local c = link.src
      local d = link.dest
      local door_chance = 10

      if c.theme.outdoor and d.theme.outdoor then door_chance = 3
      elseif c.theme ~= d.theme then door_chance = 30
      end

      if rand_odds(door_chance) then link.kind = "door" end
    end
  end

  local function add_falloffs()

    -- converts an existing two-way link into a falloff.
    -- checks if map still playable by finding a path back up.

    local function can_make_falloff(a, b)

      if not (a.floor_h >= b.f_max + 48)  then return false end
      if not (a.floor_h + 64 <= b.ceil_h) then return false end

      return true
    end

    local function verify_scorer(arr, cx,cy, nx,ny)
      local c = arr[cx][cy]
      local n = arr[nx][ny]

          if ny > cy then dir = 8
      elseif ny < cy then dir = 2
      elseif nx < cx then dir = 4
      elseif nx > cx then dir = 6
      else
        error("verify_scorer: weird direction!")
      end

      local L = c.link[dir]

      if not L then return -1 end  -- blocked

--print(string.format("*** VERIFY (%d,%d) %d --> (%d,%d) %d  L=%s", cx, cy, c.floor_h, nx, ny, n.floor_h, L.kind))

      if L.kind == "falloff" then
        if c.floor_h < n.floor_h then return -1 end  -- cannot go up
      end

      return 0.2
    end

    local function verify_falloff(L)
      local low  = L.src
      local high = L.dest

      if low.floor_h > high.floor_h then
        low, high = high, low
      end
--print(string.format("Low (%d,%d) %d -> High (%d,%d) %d", low.x,low.y, low.floor_h,  high.x, high.y, high.floor_h))

      -- use A* to find a path
      local path = astar_find_path(p.cells, low.x,low.y, high.x,high.y, verify_scorer)

--print("ASTAR_FIND_PATH: path_len", path and #path)

      return path
    end

    --- add_falloffs ---

    local locs = {}

    for zzz,c in ipairs(p.all_cells) do
      for dir = 2,8,2 do
        if c.link[dir] then
          local other = link_other(c.link[dir], c)

          if can_make_falloff(c, other) then
-- print("FALL-OFF POSSIBLE AT", c.x, c.y, dir)
            table.insert(locs, {c=c, dir=dir, other=other })
          end
        end
      end
    end

    rand_shuffle(locs)

    local num_f = int((p.w + p.h) / 4)

    while #locs > 0 and num_f > 0 do

      local cur = table.remove(locs)

      local c = cur.c
      local other = cur.other

      local L = c.link[cur.dir]
      local old_kind = L.kind

      L.kind = "falloff"

      if verify_falloff(L) then
        print("FALL-OFF @", c.x, c.y, cur.dir)
        num_f = num_f - 1
      else
        print("IMPOSSIBLE FALL-OFF @", c.x, c.y, cur.dir)
        L.kind = old_kind
      end
    end
  end

  local function add_windows()

    local function can_make_window(a, b)
      
      local cc = math.min(a.ceil_h, b.ceil_h) - 32
      local ff = math.max(a.f_max,  b.f_max)  + 32

      if (cc - ff) < 32 then return false end

      if a.theme.outdoor and b.theme.outdoor and a.ceil_h ~= b.ceil_h then return false end
--!!      if a.theme.outdoor and not b.theme.outdoor and b.ceil_h > b.ceil_h + 32 then return false end
--!!      if b.theme.outdoor and not a.theme.outdoor and a.ceil_h > a.ceil_h + 32 then return false end

      return true
    end

    for zzz,c in ipairs(p.all_cells) do
      for dir = 6,8,2 do
        local dx, dy = dir_to_delta(dir)
        local other = valid_cell(p, c.x+dx, c.y+dy) and p.cells[c.x+dx][c.y+dy]

        if other and
           can_make_window(c, other) and
           rand_odds(64)
        then
          c.window[dir] = "window"
          other.window[10-dir] = "dest"
        end
      end
    end
  end

  ---=== plan_dm_arena ===---

  local W = rand_index_by_probs { 0,22,90,55,15,4 }
  local H = rand_index_by_probs { 0,22,90,55,15,4 }

  if W < H then W,H = H,W end

  --print(string.format("%dx%d", math.min(W,H), math.max(W,H)))

  assert(W <= p.w and H <= p.h)

  p.w, p.h = W, H

  -- dummy quest
  p.quests[1] =
  {
    level = 1, kind = "frag_fest", path = {}
  }

  for y = 1,H do
    for x = 1,W do
      -- note: dummy along and theme values
      create_cell(p, x, y, p.quests[1], 1, nil)
    end
  end

  p.liquid = choose_liquid()

  choose_dm_themes()
  create_dm_links()

  select_heights()
  shuffle_build_sites(p)
  compute_height_minmax(p);

  add_doors()
  add_falloffs()
  add_windows()

  con.ticker();

  return p
end

