-- Difficulty guarantees for Bridges (see docs/dev/TESTING.md, "Difficulty
-- specs"). Levels are graded by the board's human-style solver
-- (Board._logicSolve): tier 1 = island numbers alone, tier 2 = "two islands
-- must not close themselves off", tier 3 = whole-network steps. Never trial.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("Bridges difficulty", function()
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

        it("the level table is ordered: more islands and loops, harder steps", function()
            for _, n in ipairs({ 7, 9, 11 }) do
                local e, m, h = Board.LEVELS.easy(n), Board.LEVELS.medium(n), Board.LEVELS.hard(n)
                assert.is_true(e.islands < m.islands and m.islands < h.islands)
                assert.is_true(e.loops < m.loops and m.loops < h.loops)
                assert.are.same({ 0, 0 }, e.t2)
                assert.are.same({ 0, 0 }, e.t3)
                assert.is_true(m.t2[1] >= 1 and m.t3[2] == 0)
                assert.is_true(h.t3[1] > m.t3[2])
            end
        end)

        -- Generation is bounded by attempt counts, never by time: with a
        -- clock that jumps 1000 s at every read, a seed still gives the
        -- same puzzle.
        it("generation never reads the clock", function()
            local oc, ot = os.clock, os.time
            for _, d in ipairs({ "easy", "medium", "hard" }) do
                local a = newBoard(9, d, 31):serialize()
                local t = 0
                os.clock = function() t = t + 1000; return t end
                os.time = function(x) if x then return ot(x) end; t = t + 1000; return t end
                local ok, b = pcall(function() return newBoard(9, d, 31):serialize() end)
                os.clock, os.time = oc, ot
                assert.is_true(ok, tostring(b))
                assert.are.same(a, b)
            end
            local src = assert(io.open(DIR .. "board.lua")):read("*a")
            assert.is_nil(src:find("os%.clock"))
            assert.is_nil(src:find("os%.time"))
        end)
    end)
end)
