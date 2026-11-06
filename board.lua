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

local DEFAULT_N          = 7
local DEFAULT_DIFFICULTY = "easy"

-- What each level asks for (1.5.0). Before, the island count did not
-- depend on the level and the extra bridges meant to make Medium/Hard
-- harder were random draws that almost never fit, so every level was a
-- spanning tree that the island numbers alone gave away.
--   islands        island count, as a share of the n*n cells
--   loops          extra bridges closing loops, per island
--   doubles        chance that a bridge is a double one
--   t2, t3         { min, max } deductions of tier 2 / tier 3 (see
--                  logicSolve) the solution needs
-- Easy: island numbers alone. Medium: also "two islands must not close
-- themselves off". Hard: at least two steps about the whole network.
-- Never trial and error, at any level.
local HUGE = math.huge
local LEVELS = {
    easy   = function(n) return { islands = 0.20, loops = 0.10, doubles = 0.35,
                                  t2 = { 0, 0 }, t3 = { 0, 0 } } end,
    medium = function(n) return { islands = 0.25, loops = 0.20, doubles = 0.30,
                                  t2 = { 1, HUGE }, t3 = { 0, 0 } } end,
    hard   = function(n) return { islands = 0.30, loops = 0.30, doubles = 0.12,
                                  t2 = { 0, HUGE }, t3 = { 2, HUGE } } end,
}

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
-- They cross when b1 is horizontal (same row) and b2 is vertical (same col)
-- and their coordinate ranges overlap strictly inside each other.
-- ---------------------------------------------------------------------------

local function bridgesCross(r1a,c1a,r1b,c1b, r2a,c2a,r2b,c2b)
    if r1a > r1b then r1a,r1b = r1b,r1a end
    if c1a > c1b then c1a,c1b = c1b,c1a end
    if r2a > r2b then r2a,r2b = r2b,r2a end
    if c2a > c2b then c2a,c2b = c2b,c2a end

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
    return (hca < vc and vc < hcb) and (vra < hr and hr < vrb)
end

-- ---------------------------------------------------------------------------
-- Every pair of islands a bridge can join: same row or column, nothing in
-- between (so each island looks at most one island per direction).
-- Returns the edges { i1, i2 } (i1 < i2) and, per edge, the edges it
-- crosses.
-- ---------------------------------------------------------------------------

local function buildEdges(islands, n)
    local at = {}
    for i, isl in ipairs(islands) do at[(isl.r - 1) * n + isl.c] = i end
    local edges = {}
    for i, isl in ipairs(islands) do
        for c = isl.c + 1, n do
            local j = at[(isl.r - 1) * n + c]
            if j then
                edges[#edges + 1] = { i1 = math.min(i, j), i2 = math.max(i, j) }
                break
            end
        end
        for r = isl.r + 1, n do
            local j = at[(r - 1) * n + isl.c]
            if j then
                edges[#edges + 1] = { i1 = math.min(i, j), i2 = math.max(i, j) }
                break
            end
        end
    end
    local cross = {}
    for k = 1, #edges do cross[k] = {} end
    for k = 1, #edges do
        local a, b = islands[edges[k].i1], islands[edges[k].i2]
        for k2 = k + 1, #edges do
            local c, d = islands[edges[k2].i1], islands[edges[k2].i2]
            if bridgesCross(a.r, a.c, b.r, b.c, c.r, c.c, d.r, d.c) then
                cross[k][#cross[k] + 1] = k2
                cross[k2][#cross[k2] + 1] = k
            end
        end
    end
    return edges, cross
end

-- ---------------------------------------------------------------------------
-- Human-style solver, no trial and error. Each possible bridge (edge)
-- keeps a range lo..hi of how many bridges it can still carry (0 to 2).
--   tier 1  island numbers: an island's bridges add up to its number, so
--           each edge carries at least what the others cannot, and at most
--           what the others leave; a bridge that is sure to be there
--           closes every edge that would cross it.
--   tier 2  two islands must not close themselves off: two 1s are never
--           joined, a 2 never takes a double bridge to a 2.
--   tier 3  the network must stay in one piece: a bridge that would close
--           off a bigger group of islands (all of them already full) is
--           impossible, and an edge the network cannot do without (no
--           other way round between its two sides) carries at least one
--           bridge.
-- Each tier-2/3 step goes back to tier 1 (tier 3 only once tier 2 is
-- stuck too), so the counts are the steps a player could not take with the
-- lower tiers. Every rule is sound, so a full solve proves the solution is
-- the only one.
-- Returns solved, tier2, lo (bridges per edge once solved), tier3.
-- ---------------------------------------------------------------------------

local function logicSolve(islands, edges, cross, max_tier)
    max_tier = max_tier or 3
    local m, ni = #edges, #islands
    local lo, hi = {}, {}
    local inc = {}
    for i = 1, ni do inc[i] = {} end
    for k, e in ipairs(edges) do
        lo[k] = 0
        hi[k] = math.min(2, islands[e.i1].value, islands[e.i2].value)
        inc[e.i1][#inc[e.i1] + 1] = k
        inc[e.i2][#inc[e.i2] + 1] = k
    end

    local function tier1()
        local progress = false
        for i = 1, ni do
            local v = islands[i].value
            local slo, shi = 0, 0
            for _, k in ipairs(inc[i]) do slo, shi = slo + lo[k], shi + hi[k] end
            for _, k in ipairs(inc[i]) do
                local nlo = math.max(lo[k], v - (shi - hi[k]))
                local nhi = math.min(hi[k], v - (slo - lo[k]))
                if nlo ~= lo[k] or nhi ~= hi[k] then
                    if nlo > nhi then return false end   -- not a valid puzzle
                    slo, shi = slo - lo[k] + nlo, shi - hi[k] + nhi
                    lo[k], hi[k] = nlo, nhi
                    progress = true
                end
            end
        end
        for k = 1, m do
            if lo[k] > 0 then
                for _, k2 in ipairs(cross[k]) do
                    if hi[k2] > 0 then hi[k2] = 0; progress = true end
                end
            end
        end
        return progress
    end

    -- islands reachable from `from` over edges with at least lo2 bridges
    local function component(from, lo2)
        local seen, queue, head = { [from] = true }, { from }, 1
        while head <= #queue do
            local cur = queue[head]; head = head + 1
            for _, k in ipairs(inc[cur]) do
                if lo2[k] > 0 then
                    local e = edges[k]
                    local nb = e.i1 == cur and e.i2 or e.i1
                    if not seen[nb] then seen[nb] = true; queue[#queue + 1] = nb end
                end
            end
        end
        return queue
    end

    local function full(i)
        local s = 0
        for _, kk in ipairs(inc[i]) do s = s + lo[kk] end
        return s >= islands[i].value
    end

    -- Would edge k carrying x bridges close off a group short of all islands?
    local function closesGroup(k, x)
        local old = lo[k]
        lo[k] = x
        -- both ends belong to the group, so both must be full
        if not (full(edges[k].i1) and full(edges[k].i2)) then
            lo[k] = old
            return false, 0
        end
        local group = component(edges[k].i1, lo)
        local closed = #group < ni
        if closed then
            for _, i in ipairs(group) do
                local s = 0
                for _, kk in ipairs(inc[i]) do s = s + lo[kk] end
                if s < islands[i].value then closed = false; break end
            end
        end
        lo[k] = old
        return closed, #group
    end

    -- Edges the network cannot do without: the bridges (in the graph
    -- sense) of the graph of edges that can still carry a bridge, found
    -- with Tarjan's low-link walk.
    local function cutEdges()
        local order, low, counter, cut = {}, {}, 0, {}
        local function walk(v, via)
            counter = counter + 1
            order[v], low[v] = counter, counter
            for _, k in ipairs(inc[v]) do
                if k ~= via and hi[k] > 0 then
                    local e = edges[k]
                    local w = e.i1 == v and e.i2 or e.i1
                    if not order[w] then
                        walk(w, k)
                        if low[w] < low[v] then low[v] = low[w] end
                        if low[w] > order[v] then cut[k] = true end
                    elseif order[w] < low[v] then
                        low[v] = order[w]
                    end
                end
            end
        end
        walk(1, nil)
        return cut
    end

    -- tier 2: two islands that would only have each other (a 1 next to a
    -- 1, a 2 doubled to a 2); tier 3: a bigger group closed off, or an
    -- edge the network cannot do without
    local function tier2(big)
        for k = 1, m do
            if lo[k] < hi[k] then
                for _, end_hi in ipairs({ true, false }) do
                    local x = end_hi and hi[k] or lo[k]
                    if x > 0 then
                        local closed, size = closesGroup(k, x)
                        if closed and (big or size == 2) then
                            if end_hi then hi[k] = x - 1 else lo[k] = x + 1 end
                            return true
                        end
                    end
                end
            end
        end
        if big and ni > 1 then
            local cut = cutEdges()
            for k = 1, m do
                if lo[k] == 0 and hi[k] > 0 and cut[k] then
                    lo[k] = 1
                    return true
                end
            end
        end
        return false
    end

    local t2, t3 = 0, 0
    while true do
        if not tier1() then
            if max_tier >= 2 and tier2(false) then
                t2 = t2 + 1
            elseif max_tier >= 3 and tier2(true) then
                t3 = t3 + 1
            else
                break
            end
        end
    end
    for k = 1, m do
        if lo[k] ~= hi[k] then return false, t2, lo, t3 end
    end
    return true, t2, lo, t3
end

-- ---------------------------------------------------------------------------
-- Exact solution counter (the specs cross-check logicSolve with it): how
-- many ways to put 0, 1 or 2 bridges on every edge so that each island
-- gets its number, no bridges cross and the network is in one piece.
-- MRV backtracking over edges with each island's remaining budget checked
-- against what its other open edges can still bring.
-- ---------------------------------------------------------------------------

local function countSolutions(islands, edges, cross, limit, node_budget)
    local ni, m = #islands, #edges
    local remaining = {}
    for i = 1, ni do remaining[i] = islands[i].value end
    local inc = {}
    for i = 1, ni do inc[i] = {} end
    for k, e in ipairs(edges) do
        inc[e.i1][#inc[e.i1] + 1] = k
        inc[e.i2][#inc[e.i2] + 1] = k
    end
    local decided = {}
    local solutions, nodes, exhausted = 0, 0, false

    local function openCapacity(v, skip)
        local cap = 0
        for _, k in ipairs(inc[v]) do
            if k ~= skip and decided[k] == nil then
                local blocked = false
                for _, k2 in ipairs(cross[k]) do
                    if (decided[k2] or 0) > 0 then blocked = true; break end
                end
                if not blocked then cap = cap + 2 end
            end
        end
        return cap
    end

    local function legalValues(k)
        local e = edges[k]
        local maxv = 2
        for _, k2 in ipairs(cross[k]) do
            if (decided[k2] or 0) > 0 then maxv = 0; break end
        end
        local out = {}
        for v = 0, maxv do
            local ok = true
            for _, endp in ipairs({ e.i1, e.i2 }) do
                local left = remaining[endp] - v
                if left < 0 or left > openCapacity(endp, k) then ok = false; break end
            end
            if ok then out[#out + 1] = v end
        end
        return out
    end

    local function search()
        if solutions >= limit or exhausted then return end
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return end
        local best_k, best_vals, best_len = nil, nil, math.huge
        for k = 1, m do
            if decided[k] == nil then
                local vals = legalValues(k)
                if #vals < best_len then
                    best_k, best_vals, best_len = k, vals, #vals
                    if best_len == 0 then break end
                end
            end
        end
        if not best_k then
            for i = 1, ni do if remaining[i] ~= 0 then return end end
            local ec = {}
            for k, e in ipairs(edges) do ec[k] = { i1 = e.i1, i2 = e.i2, count = decided[k] } end
            if islandsBFSConnected(islands, ec) then solutions = solutions + 1 end
            return
        end
        if best_len == 0 then return end
        local e = edges[best_k]
        for _, v in ipairs(best_vals) do
            decided[best_k] = v
            remaining[e.i1], remaining[e.i2] = remaining[e.i1] - v, remaining[e.i2] - v
            search()
            remaining[e.i1], remaining[e.i2] = remaining[e.i1] + v, remaining[e.i2] + v
            decided[best_k] = nil
            if solutions >= limit or exhausted then break end
        end
    end

    search()
    return solutions, exhausted
end

-- ---------------------------------------------------------------------------
-- Construction: one random solution. Islands grow out of the first one:
-- from a random island, in a random direction, at least two cells away
-- over empty water, a new island is placed and joined by one or two
-- bridges (so the network is connected and crossing-free by
-- construction). Then extra bridges close loops between islands that can
-- see each other. Returns islands (with their numbers), the solution
-- bridges { i1, i2, count } and buildEdges' edges and crossings, or nil.
-- ---------------------------------------------------------------------------

local DIR4 = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

local function construct(n, level)
    local target = math.max(4, math.floor(n * n * level.islands + 0.5))
    local cell = {}          -- (r-1)*n+c -> island index, or "b" under a bridge
    local islands, sol = {}, {}
    local function key(r, c) return (r - 1) * n + c end
    local function inside(r, c) return r >= 1 and r <= n and c >= 1 and c <= n end
    local function nearIsland(r, c)
        for _, d in ipairs(DIR4) do
            local rr, cc = r + d[1], c + d[2]
            if inside(rr, cc) and type(cell[key(rr, cc)]) == "number" then return true end
        end
        return false
    end
    local function addIsland(r, c)
        islands[#islands + 1] = { r = r, c = c, value = 0, connections = 0 }
        cell[key(r, c)] = #islands
        return #islands
    end
    local function addBridge(i, j, count)
        local a, b = islands[i], islands[j]
        local dr = (b.r > a.r and 1) or (b.r < a.r and -1) or 0
        local dc = (b.c > a.c and 1) or (b.c < a.c and -1) or 0
        local r, c = a.r + dr, a.c + dc
        while r ~= b.r or c ~= b.c do
            cell[key(r, c)] = "b"
            r, c = r + dr, c + dc
        end
        sol[#sol + 1] = { i1 = math.min(i, j), i2 = math.max(i, j), count = count }
        a.value, b.value = a.value + count, b.value + count
    end
    local function bridgeCount()
        return math.random() < level.doubles and 2 or 1
    end

    addIsland(math.random(n), math.random(n))
    local active = { 1 }     -- islands that may still grow a new one
    local maxlen = math.max(2, math.floor(n / 2))
    while #islands < target and #active > 0 do
        local ai = math.random(#active)
        local i = active[ai]
        local a = islands[i]
        local opts = {}
        for _, d in ipairs(DIR4) do
            for len = 1, maxlen do
                local r, c = a.r + d[1] * len, a.c + d[2] * len
                if not inside(r, c) or cell[key(r, c)] ~= nil then break end
                if len >= 2 and not nearIsland(r, c) then opts[#opts + 1] = { r, c } end
            end
        end
        if #opts == 0 then
            table.remove(active, ai)
        else
            local o = opts[math.random(#opts)]
            local j = addIsland(o[1], o[2])
            addBridge(i, j, bridgeCount())
            active[#active + 1] = j
        end
    end
    if #islands < 4 then return nil end

    -- loops: islands that see each other over empty water (more bridges
    -- never change which islands see each other, so these edges and
    -- crossings are the puzzle's too)
    local edges, cross = buildEdges(islands, n)
    local joined = {}
    for _, b in ipairs(sol) do joined[b.i1 * 1000 + b.i2] = true end
    local open = {}
    for _, e in ipairs(edges) do
        if not joined[e.i1 * 1000 + e.i2] then open[#open + 1] = e end
    end
    grid_utils.shuffle(open)
    local loops = math.floor(#islands * level.loops + 0.5)
    for _, e in ipairs(open) do
        if loops <= 0 then break end
        local a, b = islands[e.i1], islands[e.i2]
        local dr = (b.r > a.r and 1) or (b.r < a.r and -1) or 0
        local dc = (b.c > a.c and 1) or (b.c < a.c and -1) or 0
        local r, c = a.r + dr, a.c + dc
        local clear = true
        while r ~= b.r or c ~= b.c do
            if cell[key(r, c)] ~= nil then clear = false; break end
            r, c = r + dr, c + dc
        end
        if clear then
            addBridge(e.i1, e.i2, bridgeCount())
            loops = loops - 1
        end
    end
    return islands, sol, edges, cross
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
        bridges         = {},   -- {i1, i2, count}: every pair a bridge can join
        solution_bridges= {},   -- {i1, i2, count}  solution
        selected        = nil,  -- index of selected island
    }, self)
end

-- Every pair of islands a bridge can join gets a slot, so the player
-- chooses where bridges go (before 1.5.0 only the solution's pairs could
-- be tapped, which gave the answer away). Keeps the counts already placed.
function BridgesBoard:_buildSlots(placed)
    local edges, cross = buildEdges(self.islands, self.n)
    local have = {}
    for _, b in ipairs(placed or {}) do
        have[math.min(b.i1, b.i2) * 1000 + math.max(b.i1, b.i2)] = b.count or 0
    end
    self.bridges = {}
    for k, e in ipairs(edges) do
        self.bridges[k] = { i1 = e.i1, i2 = e.i2, count = have[e.i1 * 1000 + e.i2] or 0 }
    end
    self._cross = cross
end

BridgesBoard.LEVELS = LEVELS
BridgesBoard.ATTEMPTS = 200

-- Whole candidates are generated and graded: a random construction, then
-- the human-style solver (logicSolve) on every pair a bridge can join. A
-- candidate is kept when the solver finishes it (so it has exactly one
-- solution and needs no trial and error) with tier-2/3 counts in the
-- level's ranges. All work is bounded by attempt counts, never the clock
-- (same seed, same puzzle on every device).
-- on_progress(fraction), optional: called after every candidate.
function BridgesBoard:generate(difficulty, on_progress)
    self.difficulty = difficulty or self.difficulty
    self.selected   = nil
    self.legacy_cross = nil
    local n = self.n
    local level = (LEVELS[self.difficulty] or LEVELS.easy)(n)
    local attempts = BridgesBoard.ATTEMPTS

    -- Fallback if the budget runs out (rare, see the specs): the solvable
    -- candidate whose tier-2/3 counts came closest to the ranges.
    local best, best_dist
    for attempt = 1, attempts * 5 do
        local islands, sol, edges, cross = construct(n, level)
        if islands then
            local solved, t2, lo, t3 = logicSolve(islands, edges, cross, 3)
            if solved then
                local want = {}
                for _, b in ipairs(sol) do want[b.i1 * 1000 + b.i2] = b.count end
                for k, e in ipairs(edges) do
                    if lo[k] ~= (want[e.i1 * 1000 + e.i2] or 0) then solved = false; break end
                end
            end
            if solved then
                local function off(v, w)
                    return v < w[1] and w[1] - v or (v > w[2] and v - w[2] or 0)
                end
                local dist = off(t2, level.t2) + off(t3, level.t3)
                if not best or dist < best_dist then
                    best, best_dist = { islands, sol }, dist
                end
                if dist == 0 then break end
            end
        end
        if on_progress then on_progress(math.min(1, attempt / attempts)) end
        if attempt >= attempts and best then break end
    end

    if best then
        self.islands          = best[1]
        self.solution_bridges = best[2]
        self:_buildSlots()
        return
    end
    -- Never seen in the specs; still a checked puzzle (one answer).
    self:_fallback(n)
end

function BridgesBoard:_fallback(n)
    -- Two islands in corners connected by 2 bridges
    self.islands = {
        {r=1, c=1, value=2, connections=0},
        {r=1, c=n, value=2, connections=0},
    }
    self.solution_bridges = { {i1=1, i2=2, count=2} }
    self:_buildSlots()
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
-- Tap bridge: cycle the bridges between islands i1 and i2, 0 -> 1 -> 2 -> 0.
-- Returns true if a change was made; false, "cross" when a bridge already
-- in place would be crossed; false when the two islands cannot be joined.
-- ---------------------------------------------------------------------------

function BridgesBoard:_slotIndex(i1, i2)
    for k, b in ipairs(self.bridges) do
        if (b.i1 == i1 and b.i2 == i2) or (b.i1 == i2 and b.i2 == i1) then return k end
    end
    return nil
end

function BridgesBoard:tapBridge(i1, i2)
    if i1 == i2 then return false end
    local k = self:_slotIndex(i1, i2)
    if not k then return false end
    local b = self.bridges[k]
    if b.count == 0 and not self.legacy_cross then
        if not self._cross then self:_buildSlots(self.bridges) end
        for _, k2 in ipairs(self._cross[k] or {}) do
            if self.bridges[k2].count > 0 then return false, "cross" end
        end
    end
    b.count = (b.count + 1) % 3
    return true
end

-- ---------------------------------------------------------------------------
-- Check win: the bridges keep every rule, whatever the stored solution says
-- (1.5.0; it compared with the solution before): each island has its number
-- of bridges, no two bridges cross, all islands form one network. A
-- puzzle saved before 1.5.0 whose solution crosses (see load) may cross.
-- ---------------------------------------------------------------------------

function BridgesBoard:checkWin()
    if #self.islands == 0 then return false end
    for i, isl in ipairs(self.islands) do
        if self:getIslandDegree(i) ~= isl.value then return false end
    end
    if not self._cross then self:_buildSlots(self.bridges) end
    for k, b in ipairs(self.bridges) do
        if b.count > 0 and not self.legacy_cross then
            for _, k2 in ipairs(self._cross[k] or {}) do
                if self.bridges[k2].count > 0 then return false end
            end
        end
    end
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
-- Hints
--
-- The unit is a bridge between two islands, not a cell. A pair carrying
-- more bridges than the solution is a mistake (it is fixed first, which
-- also clears any bridge in the way of a missing one); then a pair short
-- of bridges is filled.
-- ---------------------------------------------------------------------------

local function bridgeSolutionCount(board, i1, i2)
    for _, sb in ipairs(board.solution_bridges) do
        if (sb.i1 == i1 and sb.i2 == i2) or (sb.i1 == i2 and sb.i2 == i1) then
            return sb.count
        end
    end
    return 0
end

function BridgesBoard:findHint()
    for pass = 1, 2 do
        for _, b in ipairs(self.bridges or {}) do
            local want = bridgeSolutionCount(self, b.i1, b.i2)
            if (pass == 1 and b.count > want) or (pass == 2 and b.count < want) then
                local a, z = self.islands[b.i1], self.islands[b.i2]
                if a and z then
                    return {
                        kind = pass == 1 and "mistake" or "fill",
                        i1 = b.i1, i2 = b.i2, want = want,
                        r = a.r, c = a.c, tag = b.i1 .. "-" .. b.i2,
                        r2 = z.r, c2 = z.c,
                    }
                end
            end
        end
    end
    return nil, "complete"
end

function BridgesBoard:applyHint(step)
    if not step then return false end
    local k = self:_slotIndex(step.i1, step.i2)
    if not k then return false end
    -- tapBridge cycles 0 -> 1 -> 2 -> 0, so three taps reach any count
    for _ = 1, 3 do
        if self.bridges[k].count == step.want then return true end
        if not self:tapBridge(step.i1, step.i2) then return false end
    end
    return self.bridges[k].count == step.want
end

function BridgesBoard:getHintsUsed()
    return self.hints_used or 0
end

function BridgesBoard:noteHintUsed()
    self.hints_used = (self.hints_used or 0) + 1
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

-- Saves from before 1.5.0 only hold the solution's pairs in `bridges`:
-- the slots are rebuilt for every pair, keeping the counts placed.
function BridgesBoard:load(data)
    if type(data) ~= "table" or not data.islands or not data.solution_bridges then
        return false
    end
    self.n                = data.n or DEFAULT_N
    self.difficulty       = data.difficulty or DEFAULT_DIFFICULTY
    self.islands          = data.islands or {}
    self.solution_bridges = data.solution_bridges or {}
    self.selected         = data.selected
    self:_buildSlots(data.bridges)
    -- Before 1.5.0 the generator did not keep its solution's bridges from
    -- crossing. Such a puzzle can only be finished with crossing bridges,
    -- so it keeps the old rule (crossings allowed) instead of becoming
    -- unwinnable.
    local sol = {}
    for _, sb in ipairs(self.solution_bridges) do
        if (sb.count or 0) > 0 then
            sol[math.min(sb.i1, sb.i2) * 1000 + math.max(sb.i1, sb.i2)] = true
        end
    end
    self.legacy_cross = nil
    for k, b in ipairs(self.bridges) do
        if sol[b.i1 * 1000 + b.i2] then
            for _, k2 in ipairs(self._cross[k]) do
                local o = self.bridges[k2]
                if sol[o.i1 * 1000 + o.i2] then self.legacy_cross = true end
            end
        end
    end
    return true
end

BridgesBoard._logicSolve     = logicSolve      -- for the specs
BridgesBoard._countSolutions = countSolutions
BridgesBoard._buildEdges     = buildEdges
BridgesBoard._construct      = construct

return BridgesBoard
