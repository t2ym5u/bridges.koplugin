local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("BridgesBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)


    local function newBoard(n, diff, seed)
        math.randomseed(seed or 42)
        local b = Board:new{ n = n or 7 }
        b:generate(diff or "easy")
        return b
    end

    local function solve(b)
        for _, sb in ipairs(b.solution_bridges) do
            for _, ub in ipairs(b.bridges) do
                if ub.i1 == sb.i1 and ub.i2 == sb.i2 then ub.count = sb.count end
            end
        end
    end

    local function slot(b, i1, i2)
        for _, ub in ipairs(b.bridges) do
            if (ub.i1 == i1 and ub.i2 == i2) or (ub.i1 == i2 and ub.i2 == i1) then return ub end
        end
    end

    describe("construction", function()
        it("creates a 7×7 board by default", function()
            local b = Board:new()
            assert.are.equal(7, b.n)
        end)

        it("starts with no islands until generate is called", function()
            local b = Board:new{ n = 7 }
            assert.are.equal(0, #b.islands)
        end)
    end)

    describe("generate", function()
        it("produces at least 4 islands", function()
            local b = newBoard(7)
            assert.is_true(#b.islands >= 4)
        end)

        it("no two islands are orthogonally adjacent", function()
            local b = newBoard(7)
            for i = 1, #b.islands do
                for j = i + 1, #b.islands do
                    local a, bb = b.islands[i], b.islands[j]
                    local dr, dc = math.abs(a.r - bb.r), math.abs(a.c - bb.c)
                    local adjacent = (dr == 1 and dc == 0) or (dr == 0 and dc == 1)
                    assert.is_false(adjacent,
                        ("islands %d,%d and %d,%d are orthogonally adjacent"):format(a.r, a.c, bb.r, bb.c))
                end
            end
        end)

        it("fresh board does not satisfy checkWin (bridges default to 0)", function()
            local b = newBoard(7)
            assert.is_false(b:checkWin())
        end)
    end)

    describe("islandAt", function()
        it("finds the island index at a known position", function()
            local b = newBoard(7)
            local isl = b.islands[1]
            assert.are.equal(1, b:islandAt(isl.r, isl.c))
        end)

        it("returns nil for an empty cell", function()
            local b = newBoard(7)
            local occupied = {}
            for _, isl in ipairs(b.islands) do occupied[isl.r * 100 + isl.c] = true end
            for r = 1, b.n do
                for c = 1, b.n do
                    if not occupied[r * 100 + c] then
                        assert.is_nil(b:islandAt(r, c))
                        return
                    end
                end
            end
        end)
    end)

    describe("tapBridge / checkWin", function()
        it("setting bridges to match the solution wins the puzzle", function()
            local b = newBoard(7)
            solve(b)
            assert.is_true(b:checkWin())
        end)

        it("every pair that can be joined is offered, not only the solution's", function()
            local b = newBoard(9, "hard")
            assert.is_true(#b.bridges > #b.solution_bridges)
            -- a pair the solution leaves empty can still take 1 and 2 bridges
            for _, ub in ipairs(b.bridges) do
                local in_sol = false
                for _, sb in ipairs(b.solution_bridges) do
                    if sb.i1 == ub.i1 and sb.i2 == ub.i2 then in_sol = true end
                end
                if not in_sol then
                    assert.is_true(b:tapBridge(ub.i1, ub.i2))
                    assert.are.equal(1, ub.count)
                    assert.is_true(b:tapBridge(ub.i1, ub.i2))
                    assert.are.equal(2, ub.count)
                    assert.is_true(b:tapBridge(ub.i1, ub.i2))
                    assert.are.equal(0, ub.count)
                    return
                end
            end
            error("no pair outside the solution")
        end)

        it("a bridge cannot cross one already built", function()
            -- + shape: islands left/right on row 3, top/bottom on column 3
            local b = Board:new{ n = 5 }
            b.islands = {
                { r = 3, c = 1, value = 1, connections = 0 },
                { r = 3, c = 5, value = 1, connections = 0 },
                { r = 1, c = 3, value = 1, connections = 0 },
                { r = 5, c = 3, value = 1, connections = 0 },
            }
            b.solution_bridges = {}
            b:_buildSlots()
            assert.is_true(b:tapBridge(1, 2))
            local ok, why = b:tapBridge(3, 4)
            assert.is_false(ok)
            assert.are.equal("cross", why)
            assert.are.equal(0, slot(b, 3, 4).count)
        end)

        it("islands that cannot see each other cannot be joined", function()
            local b = Board:new{ n = 5 }
            b.islands = {
                { r = 1, c = 1, value = 1, connections = 0 },
                { r = 1, c = 3, value = 2, connections = 0 },
                { r = 1, c = 5, value = 1, connections = 0 },
                { r = 3, c = 3, value = 0, connections = 0 },
            }
            b.solution_bridges = {}
            b:_buildSlots()
            assert.is_false(b:tapBridge(1, 3))   -- island 2 is in between
            assert.is_false(b:tapBridge(1, 4))   -- not in line
        end)

        it("wins on any bridges that keep the rules, refuses a split network", function()
            -- 1 - 2 - 1 in a row: one answer; checkWin ignores solution_bridges
            local b = Board:new{ n = 5 }
            b.islands = {
                { r = 1, c = 1, value = 1, connections = 0 },
                { r = 1, c = 3, value = 2, connections = 0 },
                { r = 1, c = 5, value = 1, connections = 0 },
            }
            b.solution_bridges = {}
            b:_buildSlots()
            b:tapBridge(1, 2)
            assert.is_false(b:checkWin())
            b:tapBridge(2, 3)
            assert.is_true(b:checkWin())
            -- two separate pairs, each full: numbers right, network split
            local c = Board:new{ n = 5 }
            c.islands = {
                { r = 1, c = 1, value = 1, connections = 0 },
                { r = 1, c = 3, value = 1, connections = 0 },
                { r = 4, c = 1, value = 1, connections = 0 },
                { r = 4, c = 3, value = 1, connections = 0 },
            }
            c.solution_bridges = {}
            c:_buildSlots()
            c:tapBridge(1, 2)
            c:tapBridge(3, 4)
            assert.is_false(c:checkWin())
        end)

        it("tapBridge on the same island twice returns false", function()
            local b = newBoard(7)
            assert.is_false(b:tapBridge(1, 1))
        end)
    end)

    describe("hints", function()
        it("fixes extra bridges first, then fills, and ends on a win", function()
            local b = newBoard(9, "medium")
            -- a wrong bridge on a pair outside the solution
            for _, ub in ipairs(b.bridges) do
                local want = 0
                for _, sb in ipairs(b.solution_bridges) do
                    if sb.i1 == ub.i1 and sb.i2 == ub.i2 then want = sb.count end
                end
                if want == 0 then ub.count = 1; break end
            end
            local step = b:findHint()
            assert.are.equal("mistake", step.kind)
            for _ = 1, 200 do
                step = b:findHint()
                if not step then break end
                assert.is_true(b:applyHint(step))
            end
            assert.is_true(b:checkWin())
        end)
    end)

    describe("getIslandDegree", function()
        it("sums bridge counts touching an island", function()
            local b = newBoard(7)
            solve(b)
            local isl = b.islands[1]
            assert.are.equal(isl.value, b:getIslandDegree(1))
        end)
    end)

    describe("serialize / load", function()
        it("round-trips islands, bridges and solution", function()
            local b = newBoard(7)
            b:tapBridge(b.solution_bridges[1].i1, b.solution_bridges[1].i2)
            local data = b:serialize()
            local b2 = Board:new{ n = 7 }
            local ok = b2:load(data)
            assert.is_true(ok)
            assert.are.equal(#b.islands, #b2.islands)
            assert.are.equal(#b.solution_bridges, #b2.solution_bridges)
            assert.are.equal(b.bridges[1].count, b2.bridges[1].count)
        end)

        it("a save from 1.4.x (slots only on the solution's pairs) loads and plays", function()
            -- 1.4.x saved `bridges` with the solution's pairs only
            local b = newBoard(7, "medium")
            local data = b:serialize()
            local old = {}
            for i, sb in ipairs(data.solution_bridges) do
                old[i] = { i1 = sb.i2, i2 = sb.i1, count = i == 1 and 1 or 0 }  -- any order
            end
            data.bridges = old
            local b2 = Board:new{ n = 7 }
            assert.is_true(b2:load(data))
            assert.are.equal(#b.bridges, #b2.bridges)
            local first = data.solution_bridges[1]
            assert.are.equal(1, slot(b2, first.i1, first.i2).count)
            solve(b2)
            assert.is_true(b2:checkWin())
        end)

        it("a 1.4.x puzzle whose solution crosses can still be won", function()
            -- 1.4.x did not keep its solution from crossing: A(1,3)-B(5,3)
            -- crosses C(3,1)-D(3,5); A-E(1,5) and E-D join the network.
            local data = {
                n = 5, difficulty = "easy",
                islands = {
                    { r = 1, c = 3, value = 2, connections = 0 },   -- A
                    { r = 5, c = 3, value = 1, connections = 0 },   -- B
                    { r = 3, c = 1, value = 1, connections = 0 },   -- C
                    { r = 3, c = 5, value = 2, connections = 0 },   -- D
                    { r = 1, c = 5, value = 2, connections = 0 },   -- E
                },
                solution_bridges = {
                    { i1 = 1, i2 = 2, count = 1 }, { i1 = 3, i2 = 4, count = 1 },
                    { i1 = 1, i2 = 5, count = 1 }, { i1 = 4, i2 = 5, count = 1 },
                },
            }
            data.bridges = {}
            for i, sb in ipairs(data.solution_bridges) do
                data.bridges[i] = { i1 = sb.i1, i2 = sb.i2, count = 0 }
            end
            local b = Board:new{ n = 5 }
            assert.is_true(b:load(data))
            assert.is_true(b.legacy_cross)
            for _, sb in ipairs(data.solution_bridges) do
                assert.is_true(b:tapBridge(sb.i1, sb.i2))
            end
            assert.is_true(b:checkWin())
            -- a puzzle of this version keeps the no-crossing rule
            local fresh = newBoard(7, "hard")
            local b2 = Board:new{ n = 7 }
            assert.is_true(b2:load(fresh:serialize()))
            assert.is_nil(b2.legacy_cross)
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)

    describe("generator (1.5.0)", function()
        local function grade(b)
            local edges, cross = Board._buildEdges(b.islands, b.n)
            local solved, t2, _, t3 = Board._logicSolve(b.islands, edges, cross, 3)
            return solved, t2, t3, edges, cross
        end

        it("every puzzle: one solution, no trial and error, in its level's window", function()
            for _, n in ipairs({ 7, 9, 11 }) do
                for _, d in ipairs({ "easy", "medium", "hard" }) do
                    local lvl = Board.LEVELS[d](n)
                    for seed = 1, 30 do
                        local b = newBoard(n, d, seed)
                        assert.is_true(#b.islands >= math.floor(n * n * 0.15),
                            ("n=%d %s seed=%d: %d islands"):format(n, d, seed, #b.islands))
                        local solved, t2, t3, edges, cross = grade(b)
                        assert.is_true(solved, ("n=%d %s seed=%d needs trial"):format(n, d, seed))
                        assert.is_true(t2 >= lvl.t2[1] and t2 <= lvl.t2[2]
                            and t3 >= lvl.t3[1] and t3 <= lvl.t3[2],
                            ("n=%d %s seed=%d: tier 2/3 steps %d/%d"):format(n, d, seed, t2, t3))
                        if n <= 9 then
                            local count, exhausted = Board._countSolutions(b.islands, edges, cross, 2, 2e6)
                            assert.is_false(exhausted)
                            assert.are.equal(1, count)
                        end
                        -- the stored solution keeps the rules too
                        solve(b)
                        assert.is_true(b:checkWin())
                    end
                end
            end
        end)

        it("levels really differ: more islands, harder steps", function()
            for _, n in ipairs({ 7, 9, 11 }) do
                local avg = {}
                for _, d in ipairs({ "easy", "medium", "hard" }) do
                    local isl, t2, t3 = 0, 0, 0
                    for seed = 1, 20 do
                        local b = newBoard(n, d, seed)
                        local _, a2, a3 = grade(b)
                        isl, t2, t3 = isl + #b.islands, t2 + a2, t3 + a3
                    end
                    avg[d] = { isl = isl / 20, t2 = t2 / 20, t3 = t3 / 20 }
                end
                assert.is_true(avg.easy.isl < avg.medium.isl and avg.medium.isl < avg.hard.isl)
                assert.are.equal(0, avg.easy.t2 + avg.easy.t3)
                assert.is_true(avg.medium.t2 >= 1 and avg.medium.t3 == 0)
                assert.is_true(avg.hard.t3 >= 2)
            end
        end)

        it("the same seed gives the same puzzle", function()
            for _, n in ipairs({ 7, 9, 11 }) do
                local a = newBoard(n, "hard", 77):serialize()
                local b = newBoard(n, "hard", 77):serialize()
                assert.are.same(a, b)
            end
        end)

        it("reports progress and stays quick (11x11 Hard and Medium)", function()
            local t = os.clock()
            local calls = 0
            for _, d in ipairs({ "medium", "hard" }) do
                for seed = 1, 30 do
                    math.randomseed(seed)
                    local b = Board:new{ n = 11 }
                    b:generate(d, function(f)
                        calls = calls + 1
                        assert.is_true(f >= 0 and f <= 1)
                    end)
                end
            end
            assert.is_true(calls > 0)
            assert.is_true(os.clock() - t < 6, "60 puzzles took " .. (os.clock() - t) .. " s")
        end)

        it("logicSolve never decides against the only solution", function()
            local bad = 0
            for seed = 1, 300 do
                math.randomseed(seed)
                local n = 7 + 2 * (seed % 2)
                local islands, sol, edges, cross = Board._construct(n,
                    { islands = 0.2 + (seed % 4) * 0.03, loops = 0.2, doubles = 0.1 + (seed % 3) * 0.1 })
                if islands then
                    local count, exhausted = Board._countSolutions(islands, edges, cross, 2, 2e6)
                    local want = {}
                    for _, b in ipairs(sol) do want[b.i1 * 1000 + b.i2] = b.count end
                    local solved, _, lo = Board._logicSolve(islands, edges, cross, 3)
                    if solved and (count ~= 1 or exhausted) then bad = bad + 1 end
                    if count == 1 and not exhausted then
                        for k, e in ipairs(edges) do
                            local w = want[e.i1 * 1000 + e.i2] or 0
                            if lo[k] > w or (solved and lo[k] ~= w) then bad = bad + 1 end
                        end
                    end
                end
            end
            assert.are.equal(0, bad)
        end)
    end)
end)
