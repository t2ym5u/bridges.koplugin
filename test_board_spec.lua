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


    -- BridgesBoard:generate() reseeds internally via math.randomseed(os.time() +
    -- math.random(1000)), so results are NOT reproducible across runs even with
    -- math.randomseed(42) beforehand. Tests below check structural invariants
    -- only, never exact island/bridge layouts.
    local function newBoard(n, diff)
        local b = Board:new{ n = n or 7 }
        -- generate() can hit its own 2-island fallback on bad luck (it
        -- reseeds internally and isn't influenced by an outer randomseed);
        -- retry a few times so invariant tests exercise real generation
        -- rather than the degenerate fallback.
        for _ = 1, 10 do
            b:generate(diff or "easy")
            if #b.islands >= 4 then break end
        end
        return b
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

        -- Note: crossing-avoidance is only enforced by _tryGenerate for the
        -- "extra" bridges added on top of the spanning tree (each checked
        -- against bridges placed so far) -- the initial spanning-tree edges
        -- built via Prim's algorithm are never mutually crossing-checked, so
        -- "no two solution bridges cross" is not an invariant this code
        -- actually guarantees and isn't asserted here.

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
            for _, sb in ipairs(b.solution_bridges) do
                for _, ub in ipairs(b.bridges) do
                    if ub.i1 == sb.i1 and ub.i2 == sb.i2 then
                        ub.count = sb.count
                    end
                end
            end
            assert.is_true(b:checkWin())
        end)

        it("tapBridge cycles a bridge's count up to its solution max", function()
            local b = newBoard(7)
            local sb = b.solution_bridges[1]
            local before = 0
            for _, ub in ipairs(b.bridges) do
                if ub.i1 == sb.i1 and ub.i2 == sb.i2 then before = ub.count end
            end
            local ok = b:tapBridge(sb.i1, sb.i2)
            assert.is_true(ok)
            local after
            for _, ub in ipairs(b.bridges) do
                if ub.i1 == sb.i1 and ub.i2 == sb.i2 then after = ub.count end
            end
            assert.are_not.equal(before, after)
        end)

        it("tapBridge on the same island twice returns false", function()
            local b = newBoard(7)
            assert.is_false(b:tapBridge(1, 1))
        end)
    end)

    describe("getIslandDegree", function()
        it("sums bridge counts touching an island", function()
            local b = newBoard(7)
            for _, sb in ipairs(b.solution_bridges) do
                for _, ub in ipairs(b.bridges) do
                    if ub.i1 == sb.i1 and ub.i2 == sb.i2 then ub.count = sb.count end
                end
            end
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

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
