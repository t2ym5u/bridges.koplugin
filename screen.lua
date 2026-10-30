local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end
local function lrequire_common(name)
    local key = _dir .. "common/" .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. "common/" .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase     = lrequire_common("screen_base")
local MenuHelper     = lrequire_common("menu_helper")
local BridgesBoard   = lrequire("board")
local BridgesBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

local GRID_SIZES = { 7, 9, 11 }

local GAME_RULES_EN = _([[
Bridges (Hashi) — Rules

Connect all islands with bridges so the entire network is linked.

Rules:
• Each island shows a number — exactly that many bridge segments must connect to it.
• Bridges run horizontally or vertically between islands.
• Up to two bridges may connect any pair of islands.
• Bridges cannot cross each other.
• All islands must form one connected network.

Tap an island to select it, then tap another island in the same row or column to toggle bridges between them (0→1→2→0).
]])

local GAME_RULES_FR = [[
Ponts (Hashi) — Règles

Reliez toutes les îles avec des ponts de façon à ce que le réseau entier soit connecté.

Règles :
• Chaque île affiche un chiffre — exactement ce nombre de segments de ponts doit s'y connecter.
• Les ponts sont horizontaux ou verticaux entre deux îles.
• Jusqu'à deux ponts peuvent relier une même paire d'îles.
• Les ponts ne peuvent pas se croiser.
• Toutes les îles doivent former un réseau connecté unique.

Appuyez sur une île pour la sélectionner, puis sur une autre île de la même ligne ou colonne pour alterner les ponts entre elles (0→1→2→0).
]]

local BridgesScreen = ScreenBase:extend{}

-- The unit is a bridge between two islands, so a hint names both ends rather
-- than one cell. A wrong bridge cannot exist here -- tapBridge clamps each
-- connection to the solution's count -- so there is no "mistake" wording.
function BridgesScreen:describeHintStep(step, level)
    if level == 1 then
        return T(_("A bridge is missing between R%1C%2 and R%3C%4. Tap Hint again to build it."),
                 step.r, step.c, step.r2, step.c2)
    end
    return T(_("Built the bridge between R%1C%2 and R%3C%4."), step.r, step.c, step.r2, step.c2)
end

function BridgesScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n", 7)
    self.board  = BridgesBoard:new{ n = n }
    if not self.board:load(state) then
        self.board:generate(self.plugin:getSetting("difficulty", "easy"))
    end
    ScreenBase.init(self)
end

function BridgesScreen:serializeState()
    return self.board:serialize()
end

function BridgesScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Bridges"), function()
        return {
            { text = _("New game"),            callback = function() self:onNewGame() end },
            { text = self:getGridButtonText(), callback = function() self:openGridMenu() end },
            { text = self:getDiffButtonText(), callback = function() self:openDifficultyMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar({
            { text = _("Check"), callback = function() self:onCheck() end },
            { text = _("Hint"),  callback = function() self:onHint() end },
            { text = _("Reset"), callback = function() self:onReset() end },
        }),
    }

    local frame_pad   = Size.padding.large
    local frame_extra = 2 * (frame_pad + Size.border.window)
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = BridgesBoardWidget:new{
        board       = self.board,
        max_size    = math.min(budget_w, budget_h) - frame_extra,
        onTapAction = function(r, c) self:onTapCell(r, c) end,
    }
    local board_frame = FrameContainer:new{
        padding = frame_pad,
        margin  = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Tap handling — two-tap select-then-bridge
-- ---------------------------------------------------------------------------

function BridgesScreen:onTapCell(r, c)
    local board = self.board

    -- Find if an island is near this cell
    local tapped_idx = nil
    local best_dist  = math.huge
    for i, isl in ipairs(board.islands) do
        local dr = isl.r - r
        local dc = isl.c - c
        local d  = dr*dr + dc*dc
        if d < best_dist then
            best_dist = d
            tapped_idx = i
        end
    end

    if not tapped_idx then return end

    if board.selected == nil then
        -- First tap: select this island
        board.selected = tapped_idx
        self.plugin:saveState(board:serialize())
        self.board_widget:refresh()
        self:updateStatus()
        return
    end

    if board.selected == tapped_idx then
        -- Deselect
        board.selected = nil
        self.plugin:saveState(board:serialize())
        self.board_widget:refresh()
        self:updateStatus()
        return
    end

    -- Second tap: attempt to toggle bridge between selected and tapped
    local sel = board.selected
    board.selected = nil

    local changed = board:tapBridge(sel, tapped_idx)
    if changed then
        self.plugin:saveState(board:serialize())
        self.board_widget:refresh()
        if board:checkWin() then
            self:updateStatus(_("Solved! All islands connected!"))
        else
            self:updateStatus()
        end
    else
        -- Not a valid pair — just select the new island
        board.selected = tapped_idx
        self.board_widget:refresh()
        self:updateStatus()
    end
end

function BridgesScreen:onNewGame()
    local diff = self.plugin:getSetting("difficulty", "easy")
    local n    = self.plugin:getSetting("grid_n", 7)
    self.board = BridgesBoard:new{ n = n }
    self.board:generate(diff)
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function BridgesScreen:onReset()
    for _, b in ipairs(self.board.bridges) do
        b.count = 0
    end
    self.board.selected = nil
    self.plugin:saveState(self.board:serialize())
    self.board_widget:refresh()
    self:updateStatus()
end

function BridgesScreen:onCheck()
    if self.board:checkWin() then
        self:updateStatus(_("Solved! All islands connected!"))
    else
        -- Count satisfied islands
        local ok = 0
        local total = #self.board.islands
        for i, isl in ipairs(self.board.islands) do
            if self.board:getIslandDegree(i) == isl.value then
                ok = ok + 1
            end
        end
        self:updateStatus(T(_("Islands satisfied: %1/%2"), ok, total))
    end
    self.board_widget:refresh()
end

function BridgesScreen:openGridMenu()
    local sizes = {}
    for _, sz in ipairs(GRID_SIZES) do
        sizes[#sizes+1] = { id = sz, text = sz .. "\xC3\x97" .. sz }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select size"),
        sizes     = sizes,
        current   = self.plugin:getSetting("grid_n", 7),
        parent    = self,
        on_select = function(sz)
            if sz ~= self.board.n then
                self.plugin:saveSetting("grid_n", sz)
                self:onNewGame()
            end
        end,
    }
end

function BridgesScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "easy"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            if self.diff_button then
                self.diff_button:setText(self:getDiffButtonText(), self.diff_button.width)
            end
            self:onNewGame()
        end,
    }
end

function BridgesScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board:checkWin() then
        status = _("Solved! All islands connected!")
    elseif self.board.selected then
        local isl = self.board.islands[self.board.selected]
        status = T(_("Island selected: needs %1 bridges"), isl.value)
    else
        local total = #self.board.islands
        local sat = 0
        for i, isl in ipairs(self.board.islands) do
            if self.board:getIslandDegree(i) == isl.value then sat = sat + 1 end
        end
        local diff  = self.plugin:getSetting("difficulty", "easy")
        local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
        status = self:joinStatus(
            T("%1×%1", self.board.n),
            label,
            T(_("Islands: %1/%2"), sat, total))
    end
    ScreenBase.updateStatus(self, status)
    -- Every move, hint, undo and reveal ends here, so the bar follows the board.
    self:refreshActionBar()
end

function BridgesScreen:isRoundOver()
    return self.board:checkWin()
end

function BridgesScreen:getGridButtonText()
    return T(_("Size: %1"), self.board.n .. "\xC3\x97" .. self.board.n)
end

function BridgesScreen:getDiffButtonText()
    local diff  = self.plugin:getSetting("difficulty", "easy")
    local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
    return T(_("Difficulty: %1"), label)
end

return BridgesScreen
