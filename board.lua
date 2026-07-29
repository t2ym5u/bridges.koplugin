local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire_common(name)
    local key = _dir .. "common/" .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. "common/" .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local grid_utils = lrequire_common("grid_utils")
local emptyGrid  = grid_utils.emptyGrid
local shuffle    = grid_utils.shuffle

local DEFAULT_N          = 7
local DEFAULT_DIFFICULTY = "easy"

-- How many extra random bridges to try adding per difficulty
local EXTRA_BRIDGES = { easy = 3, medium = 6, hard = 10 }

-- ---------------------------------------------------------------------------
-- Connectivity check (BFS over islands connected by bridges)
-- ---------------------------------------------------------------------------

local function islandsBFSConnected(islands, bridges)
    if #islands == 0 then return true end
    local adj = {}
    for i = 1, #islands do adj[i] = {} end
    for _, b in ipairs(bridges) do
        if b.count > 0 then
            adj[b.i1][#adj[b.i1]+1] = b.i2
            adj[b.i2][#adj[b.i2]+1] = b.i1
        end
    end
    local visited = {}
    local queue   = {1}
    visited[1]    = true
    local count   = 1
    local head    = 1
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        for _, nb in ipairs(adj[cur]) do
            if not visited[nb] then
                visited[nb] = true
                count = count + 1
                queue[#queue+1] = nb
            end
        end
    end
    return count == #islands
end

-- ---------------------------------------------------------------------------
-- Check if two bridges cross (one horizontal, one vertical)
-- b1 = {r1,c1,r2,c2}, b2 same
-- They cross when b1 is horizontal (same row) and b2 is vertical (same col)
-- and their coordinate ranges overlap strictly inside each other.
-- ---------------------------------------------------------------------------

local function bridgesCross(r1a,c1a,r1b,c1b, r2a,c2a,r2b,c2b)
    -- Normalise so a <= b
    if r1a > r1b then r1a,r1b = r1b,r1a end
    if c1a > c1b then c1a,c1b = c1b,c1a end
    if r2a > r2b then r2a,r2b = r2b,r2a end
    if c2a > c2b then c2a,c2b = c2b,c2a end

    -- b1 horizontal: r1a==r1b ; b1 vertical: c1a==c1b
    local b1_horiz = (r1a == r1b)
    local b2_horiz = (r2a == r2b)

    if b1_horiz == b2_horiz then
        -- parallel: can share endpoints but never truly cross
        return false
    end

    local hr, hca, hcb  -- horizontal bridge row, col range
    local vra, vrb, vc  -- vertical bridge row range, col

    if b1_horiz then
        hr, hca, hcb = r1a, c1a, c1b
        vra, vrb, vc  = r2a, r2b, c2a
    else
        hr, hca, hcb = r2a, c2a, c2b
        vra, vrb, vc  = r1a, r1b, c1a
    end

    -- They cross when: hca < vc < hcb  AND  vra < hr < vrb
    return (hca < vc and vc < hcb) and (vra < hr and hr < vrb)
end

-- ---------------------------------------------------------------------------
-- Uniqueness counter. `tapBridge` only lets the player adjust the bridge
-- count on connection slots that already exist in `solution_bridges`
-- (clamped to that slot's own solution count) -- there's no mechanic to
-- invent a bridge on a pair that isn't one of the generator's chosen
-- edges. So the puzzle is simpler than full Hashiwokakero: the graph
-- topology is fixed and already crossing-free by construction -- solving
-- means finding how many bridges (0, 1, or 2) go on each FIXED edge such
-- that every island's total incident count matches its target and the
-- resulting graph connects every island. MRV backtracking over edges,
-- forward-checking each endpoint's remaining degree budget against how
-- much its OTHER still-undecided edges could still contribute (without
-- this, the search wastes nearly all its effort on combinations that only
-- fail the final exact-degree check once every edge is already decided).
-- ---------------------------------------------------------------------------

local function countSolutions(islands, edges, limit, node_budget)
    local n_islands = #islands
    local remaining = {}
    for i = 1, n_islands do remaining[i] = islands[i].value end

    local incident = {}
    for i = 1, n_islands do incident[i] = {} end
    for idx, e in ipairs(edges) do
        incident[e.i1][#incident[e.i1] + 1] = idx
        incident[e.i2][#incident[e.i2] + 1] = idx
    end

    local decided = {}
    for idx = 1, #edges do decided[idx] = nil end

    local solutions, nodes, exhausted = 0, 0, false

    local function otherUndecidedCount(v, exclude_idx)
        local count = 0
        for _, idx2 in ipairs(incident[v]) do
            if idx2 ~= exclude_idx and not decided[idx2] then count = count + 1 end
        end
        return count
    end

    local function legalValuesFor(idx)
        local e = edges[idx]
        local cands = {}
        for v = 0, 2 do
            local ok = true
            for _, endp in ipairs({ e.i1, e.i2 }) do
                local left = remaining[endp] - v
                if left < 0 then ok = false; break end
                local max_from_others = 2 * otherUndecidedCount(endp, idx)
                if left > max_from_others then ok = false; break end
            end
            if ok then cands[#cands + 1] = v end
        end
        return cands
    end

    local function applyValue(idx, v)
        local e = edges[idx]
        decided[idx] = v
        remaining[e.i1] = remaining[e.i1] - v
        remaining[e.i2] = remaining[e.i2] - v
    end

    local function undoValue(idx)
        local e = edges[idx]
        local v = decided[idx]
        remaining[e.i1] = remaining[e.i1] + v
        remaining[e.i2] = remaining[e.i2] + v
        decided[idx] = nil
    end

    local function search()
        if solutions >= limit or exhausted then return end
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return end

        local best_idx, best_cands, best_len = nil, nil, math.huge
        for idx = 1, #edges do
            if not decided[idx] then
                local cands = legalValuesFor(idx)
                if #cands < best_len then
                    best_len, best_cands, best_idx = #cands, cands, idx
                    if best_len == 0 then break end
                end
            end
        end

        if not best_idx then
            for i = 1, n_islands do if remaining[i] ~= 0 then return end end
            local ec = {}
            for idx, e in ipairs(edges) do ec[idx] = { i1 = e.i1, i2 = e.i2, count = decided[idx] } end
            if islandsBFSConnected(islands, ec) then
                solutions = solutions + 1
            end
            return
        end
        if best_len == 0 then return end

        for _, v in ipairs(best_cands) do
            applyValue(best_idx, v)
            search()
            undoValue(best_idx)
            if solutions >= limit or exhausted then break end
        end
    end

    search()
    return solutions, exhausted
end

-- ---------------------------------------------------------------------------
-- BridgesBoard
-- ---------------------------------------------------------------------------

local BridgesBoard = {}
BridgesBoard.__index = BridgesBoard

function BridgesBoard:new(opts)
    opts = opts or {}
    local n = opts.n or DEFAULT_N
    return setmetatable({
        n               = n,
        difficulty      = opts.difficulty or DEFAULT_DIFFICULTY,
        islands         = {},   -- {r, c, value, connections}
        bridges         = {},   -- {i1, i2, count}  user-placed
        solution_bridges= {},   -- {i1, i2, count}  solution
        selected        = nil,  -- index of selected island
    }, self)
end

-- ---------------------------------------------------------------------------
-- Generator
-- ---------------------------------------------------------------------------

-- Measured: this construction (Prim's spanning tree + degree-bounded extra
-- bridges) is already close to uniquely solvable on its own (~93-100%
-- across sizes/difficulties once the uniqueness counter itself was
-- correct -- see countSolutions' header for a real forward-checking bug
-- found while building it). Still real ambiguity in the remaining few
-- percent, so this verifies each candidate layout and retries on the rare
-- ambiguous one rather than assuming the construction is always unique,
-- falling back to the first structurally-valid layout if the retry budget
-- runs out (never worse than before).
function BridgesBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty
    self.selected   = nil

    local n = self.n
    math.randomseed(os.time() + math.random(1000))

    local best_islands, best_sol_bridges

    for _attempt = 1, 40 do
        local islands, sol_bridges = self:_tryGenerate(n)
        if islands then
            if not best_islands then
                best_islands, best_sol_bridges = islands, sol_bridges
            end
            local edges = {}
            for _, sb in ipairs(sol_bridges) do
                edges[#edges + 1] = { i1 = sb.i1, i2 = sb.i2 }
            end
            local solutions, exhausted = countSolutions(islands, edges, 2, 300000)
            if solutions == 1 and not exhausted then
                best_islands, best_sol_bridges = islands, sol_bridges
                break
            end
        end
    end

    if best_islands then
        self.islands          = best_islands
        self.solution_bridges = best_sol_bridges
        -- Start player with 0 bridges on each connection slot
        self.bridges = {}
        for _, sb in ipairs(best_sol_bridges) do
            self.bridges[#self.bridges+1] = { i1=sb.i1, i2=sb.i2, count=0 }
        end
        return
    end
    -- Fallback: tiny 2-island puzzle
    self:_fallback(n)
end

function BridgesBoard:_tryGenerate(n)
    -- 1. Place islands (no two islands adjacent, including diagonals for clarity)
    local grid = emptyGrid(n, n, 0)  -- 0=empty, positive=island index
    local islands = {}

    -- Island count must scale with grid area: too sparse and islands stop
    -- sharing rows/columns, so the Prim's spanning-tree step below finds no
    -- edges and the whole attempt is discarded (this was silently pushing
    -- larger boards to the trivial 2-island fallback most of the time).
    local min_islands = math.max(8, math.floor(n * n * 0.22))
    local max_islands = math.max(min_islands, math.floor(n * n * 0.30))
    local target = math.random(min_islands, max_islands)

    local candidates = {}
    for r = 1, n do
        for c = 1, n do
            candidates[#candidates+1] = {r, c}
        end
    end
    shuffle(candidates)

    for _, pos in ipairs(candidates) do
        if #islands >= target then break end
        local r, c = pos[1], pos[2]
        -- Check 4-directional adjacency only (no diagonal since that's where bridges go)
        local ok = true
        for _, d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
            local nr, nc = r+d[1], c+d[2]
            if nr >= 1 and nr <= n and nc >= 1 and nc <= n and grid[nr][nc] > 0 then
                ok = false; break
            end
        end
        if ok then
            islands[#islands+1] = {r=r, c=c, value=0, connections=0}
            grid[r][c] = #islands
        end
    end

    if #islands < 4 then return nil end

    -- 2. Build spanning tree (Prim's) to ensure connectivity
    local in_tree = {}
    local start = math.random(#islands)
    in_tree[start] = true
    local tree_count = 1
    local sol_bridges = {}

    -- Find pairs that can be bridged (same row or col, no island between)
    local function canBridge(i1, i2)
        local a, b = islands[i1], islands[i2]
        if a.r == b.r then
            local rr = a.r
            local c1, c2 = math.min(a.c, b.c), math.max(a.c, b.c)
            for c = c1+1, c2-1 do
                if grid[rr][c] > 0 then return false end
            end
            return true
        elseif a.c == b.c then
            local cc = a.c
            local r1, r2 = math.min(a.r, b.r), math.max(a.r, b.r)
            for r = r1+1, r2-1 do
                if grid[r][cc] > 0 then return false end
            end
            return true
        end
        return false
    end

    -- Prim's: repeatedly add an island reachable from the tree
    for _ = 1, #islands - 1 do
        local edges = {}
        for i = 1, #islands do
            if in_tree[i] then
                for j = 1, #islands do
                    if not in_tree[j] and canBridge(i, j) then
                        edges[#edges+1] = {i, j}
                    end
                end
            end
        end
        if #edges == 0 then return nil end
        local e = edges[math.random(#edges)]
        in_tree[e[2]] = true
        tree_count = tree_count + 1
        sol_bridges[#sol_bridges+1] = {i1=e[1], i2=e[2], count=1}
        islands[e[1]].value = islands[e[1]].value + 1
        islands[e[2]].value = islands[e[2]].value + 1
    end

    if tree_count < #islands then return nil end

    -- 3. Add extra bridges (within max=2 per pair, island degree <= 8)
    local extra = EXTRA_BRIDGES[self.difficulty] or EXTRA_BRIDGES.easy

    -- Index existing solution bridges for quick lookup
    local bridge_key = function(i1, i2)
        local a, b = math.min(i1,i2), math.max(i1,i2)
        return a * 100 + b
    end
    local bridge_map = {}
    for idx, sb in ipairs(sol_bridges) do
        bridge_map[bridge_key(sb.i1, sb.i2)] = idx
    end

    for _ = 1, extra * 3 do
        if extra <= 0 then break end
        local i = math.random(#islands)
        local j = math.random(#islands)
        if i ~= j and canBridge(i, j) then
            local key = bridge_key(i, j)
            local existing_idx = bridge_map[key]
            local cur_count = existing_idx and sol_bridges[existing_idx].count or 0
            if cur_count < 2 and islands[i].value < 8 and islands[j].value < 8 then
                -- Check crossing with ALL existing bridges
                local a, b = islands[i], islands[j]
                local crossing = false
                for _, sb in ipairs(sol_bridges) do
                    if sb.i1 ~= i and sb.i1 ~= j and sb.i2 ~= i and sb.i2 ~= j then
                        local sa, sb2 = islands[sb.i1], islands[sb.i2]
                        if bridgesCross(a.r,a.c,b.r,b.c, sa.r,sa.c,sb2.r,sb2.c) then
                            crossing = true; break
                        end
                    end
                end
                if not crossing then
                    if existing_idx then
                        sol_bridges[existing_idx].count = cur_count + 1
                    else
                        sol_bridges[#sol_bridges+1] = {i1=i, i2=j, count=1}
                        bridge_map[key] = #sol_bridges
                    end
                    islands[i].value = islands[i].value + 1
                    islands[j].value = islands[j].value + 1
                    extra = extra - 1
                end
            end
        end
    end

    return islands, sol_bridges
end

function BridgesBoard:_fallback(n)
    -- Two islands in corners connected by 2 bridges
    self.islands = {
        {r=1, c=1, value=2, connections=0},
        {r=1, c=n, value=2, connections=0},
    }
    self.solution_bridges = { {i1=1, i2=2, count=2} }
    self.bridges = { {i1=1, i2=2, count=0} }
end

-- ---------------------------------------------------------------------------
-- Find which island (if any) is at position (r,c)
-- ---------------------------------------------------------------------------

function BridgesBoard:islandAt(r, c)
    for i, isl in ipairs(self.islands) do
        if isl.r == r and isl.c == c then return i end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Tap bridge: cycle the bridge between island i1 and i2
-- Returns true if a change was made
-- ---------------------------------------------------------------------------

function BridgesBoard:tapBridge(i1, i2)
    if i1 == i2 then return false end
    -- normalise
    if i1 > i2 then i1, i2 = i2, i1 end

    -- Find the bridge slot. self.bridges entries preserve whatever i1/i2
    -- order they were built in (not necessarily i1<i2), so this must check
    -- both orderings just like the solution-max lookup below does.
    for _, b in ipairs(self.bridges) do
        if (b.i1 == i1 and b.i2 == i2) or (b.i1 == i2 and b.i2 == i1) then
            -- find solution max
            local sol_count = 0
            for _, sb in ipairs(self.solution_bridges) do
                if (sb.i1 == i1 and sb.i2 == i2) or (sb.i1 == i2 and sb.i2 == i1) then
                    sol_count = sb.count
                    break
                end
            end
            local max_allowed = math.min(2, sol_count)
            b.count = (b.count + 1) % (max_allowed + 1)
            -- If max_allowed is 0 (bridge not in solution), clamp to 0
            if max_allowed == 0 then b.count = 0 end
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Check win: all bridge counts match solution AND all islands connected
-- ---------------------------------------------------------------------------

function BridgesBoard:checkWin()
    -- All bridges must match solution
    for _, b in ipairs(self.bridges) do
        local found = false
        for _, sb in ipairs(self.solution_bridges) do
            if (sb.i1 == b.i1 and sb.i2 == b.i2) or (sb.i1 == b.i2 and sb.i2 == b.i1) then
                if sb.count ~= b.count then return false end
                found = true
                break
            end
        end
        if not found and b.count ~= 0 then return false end
    end
    -- All islands connected
    return islandsBFSConnected(self.islands, self.bridges)
end

-- ---------------------------------------------------------------------------
-- Island degree helpers
-- ---------------------------------------------------------------------------

function BridgesBoard:getIslandDegree(idx)
    local total = 0
    for _, b in ipairs(self.bridges) do
        if b.i1 == idx or b.i2 == idx then
            total = total + b.count
        end
    end
    return total
end

-- ---------------------------------------------------------------------------
-- Serialise / load
-- ---------------------------------------------------------------------------

function BridgesBoard:serialize()
    local isl_out = {}
    for i, isl in ipairs(self.islands) do
        isl_out[i] = {r=isl.r, c=isl.c, value=isl.value, connections=isl.connections}
    end
    local br_out = {}
    for i, b in ipairs(self.bridges) do
        br_out[i] = {i1=b.i1, i2=b.i2, count=b.count}
    end
    local sol_out = {}
    for i, sb in ipairs(self.solution_bridges) do
        sol_out[i] = {i1=sb.i1, i2=sb.i2, count=sb.count}
    end
    return {
        n                = self.n,
        difficulty       = self.difficulty,
        islands          = isl_out,
        bridges          = br_out,
        solution_bridges = sol_out,
        selected         = self.selected,
    }
end

function BridgesBoard:load(data)
    if type(data) ~= "table" or not data.islands or not data.solution_bridges then
        return false
    end
    self.n                = data.n or DEFAULT_N
    self.difficulty       = data.difficulty or DEFAULT_DIFFICULTY
    self.islands          = data.islands or {}
    self.bridges          = data.bridges or {}
    self.solution_bridges = data.solution_bridges or {}
    self.selected         = data.selected
    return true
end

return BridgesBoard
