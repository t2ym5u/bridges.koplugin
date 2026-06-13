local Blitbuffer   = require("ffi/blitbuffer")
local Font         = require("ui/font")
local Geom         = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText   = require("ui/rendertext")
local UIManager    = require("ui/uimanager")

local C_BG         = Blitbuffer.COLOR_WHITE
local C_ISLAND     = Blitbuffer.COLOR_BLACK
local C_ISLAND_SEL = Blitbuffer.COLOR_GRAY_4
local C_ISLAND_NUM = Blitbuffer.COLOR_WHITE
local C_BRIDGE     = Blitbuffer.COLOR_BLACK
local C_GRID       = Blitbuffer.COLOR_GRAY_E

-- ---------------------------------------------------------------------------
-- BridgesBoardWidget
-- A custom (non-GridWidgetBase) widget — islands at arbitrary cells, bridges
-- drawn as horizontal/vertical lines.
-- ---------------------------------------------------------------------------

local BridgesBoardWidget = InputContainer:extend{
    board      = nil,
    size_ratio = 0.82,
    onTapAction = nil,  -- function(r, c)
}

function BridgesBoardWidget:init()
    local n   = self.board and self.board.n or 7
    self.n    = n

    local Screen = require("device").screen
    local min_dim = math.min(Screen:getWidth(), Screen:getHeight())
    self.size     = math.floor(min_dim * (self.size_ratio or 0.82))
    self.cell     = self.size / n

    -- Island radius ≈ 38% of cell, bridgeline width ≈ 6% of cell
    self.island_r  = math.max(4, math.floor(self.cell * 0.38))
    self.line_w    = math.max(2, math.floor(self.cell * 0.06))

    -- Font for island numbers
    local fsize = math.max(10, math.floor(self.cell * 0.38))
    self.num_face = Font:getFace("cfont", fsize)

    self.dimen      = Geom:new{ w = self.size, h = self.size }
    self.paint_rect = Geom:new{ x=0, y=0, w=self.size, h=self.size }

    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges   = "tap",
                range = function() return self.paint_rect end,
            }
        },
    }
end

-- Convert pixel (px, py) relative to widget origin to nearest grid cell (r, c)
function BridgesBoardWidget:getCellFromPoint(px, py)
    local c = math.min(self.n, math.max(1, math.floor(px / self.cell) + 1))
    local r = math.min(self.n, math.max(1, math.floor(py / self.cell) + 1))
    return r, c
end

-- Centre pixel of cell (r, c) relative to widget origin
function BridgesBoardWidget:cellCenter(r, c)
    return math.floor((c - 0.5) * self.cell),
           math.floor((r - 0.5) * self.cell)
end

function BridgesBoardWidget:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local rect = self.paint_rect
    local px   = ges.pos.x - rect.x
    local py   = ges.pos.y - rect.y
    if px < 0 or py < 0 or px > rect.w or py > rect.h then return false end
    local r, c = self:getCellFromPoint(px, py)
    if self.onTapAction then self.onTapAction(r, c) end
    return true
end

function BridgesBoardWidget:refresh()
    local rect = self.paint_rect
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x=rect.x, y=rect.y, w=rect.w, h=rect.h }
    end)
end

function BridgesBoardWidget:paintTo(bb, x, y)
    if not self.board then return end
    self.paint_rect = Geom:new{ x=x, y=y, w=self.dimen.w, h=self.dimen.h }

    local n    = self.n
    local cell = self.cell
    local lw   = self.line_w
    local ir   = self.island_r
    local board = self.board

    -- Background
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BG)

    -- Light grid dots / guidelines
    for r = 1, n do
        for c = 1, n do
            local cx, cy = self:cellCenter(r, c)
            bb:paintRect(x + cx, y + cy, 1, 1, C_GRID)
        end
    end

    -- Draw bridges
    for _, b in ipairs(board.bridges) do
        if b.count > 0 then
            local a = board.islands[b.i1]
            local bx = board.islands[b.i2]
            local ax, ay = self:cellCenter(a.r, a.c)
            local bxx, by = self:cellCenter(bx.r, bx.c)
            ax, ay = x + ax, y + ay
            bxx, by = x + bxx, y + by

            if b.count == 1 then
                -- Single line
                if a.r == bx.r then
                    -- Horizontal
                    local x1 = math.min(ax, bxx) + ir
                    local x2 = math.max(ax, bxx) - ir
                    if x2 > x1 then
                        bb:paintRect(x1, ay - math.floor(lw/2), x2 - x1, lw, C_BRIDGE)
                    end
                else
                    -- Vertical
                    local y1 = math.min(ay, by) + ir
                    local y2 = math.max(ay, by) - ir
                    if y2 > y1 then
                        bb:paintRect(ax - math.floor(lw/2), y1, lw, y2 - y1, C_BRIDGE)
                    end
                end
            else
                -- Double line (two parallel lines, offset ± gap)
                local gap = math.max(2, math.floor(lw * 1.5))
                if a.r == bx.r then
                    -- Horizontal double
                    local x1 = math.min(ax, bxx) + ir
                    local x2 = math.max(ax, bxx) - ir
                    if x2 > x1 then
                        bb:paintRect(x1, ay - gap - math.floor(lw/2), x2 - x1, lw, C_BRIDGE)
                        bb:paintRect(x1, ay + gap - math.floor(lw/2), x2 - x1, lw, C_BRIDGE)
                    end
                else
                    -- Vertical double
                    local y1 = math.min(ay, by) + ir
                    local y2 = math.max(ay, by) - ir
                    if y2 > y1 then
                        bb:paintRect(ax - gap - math.floor(lw/2), y1, lw, y2 - y1, C_BRIDGE)
                        bb:paintRect(ax + gap - math.floor(lw/2), y1, lw, y2 - y1, C_BRIDGE)
                    end
                end
            end
        end
    end

    -- Draw islands
    for i, isl in ipairs(board.islands) do
        local cx, cy = self:cellCenter(isl.r, isl.c)
        cx, cy = x + cx, y + cy

        local is_sel = (board.selected == i)
        local bg_col = is_sel and C_ISLAND_SEL or C_ISLAND
        bb:paintCircle(cx, cy, ir, bg_col)

        -- Show remaining needed connections
        local placed = board:getIslandDegree(i)
        local remaining = isl.value - placed
        local label = tostring(isl.value)
        if remaining ~= 0 then
            label = tostring(isl.value)
        end

        local m = RenderText:sizeUtf8Text(0, ir * 2, self.num_face, label, true, false)
        local tx = cx - math.floor(m.x / 2)
        local ty = cy + math.floor((m.y_top - m.y_bottom) / 2) - m.y_top
        RenderText:renderUtf8Text(bb, tx, ty, self.num_face, label, true, false, C_ISLAND_NUM)
    end
end

return BridgesBoardWidget
