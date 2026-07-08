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

local ButtonTable     = require("ui/widget/buttontable")
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

Tap between two islands to draw a bridge. Tap again for a double bridge. Tap a third time to remove it.
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

Appuyez entre deux îles pour tracer un pont. Appuyez à nouveau pour un double pont. Un troisième appui le supprime.
]]

local BridgesScreen = ScreenBase:extend{}

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
    local sw           = DeviceScreen:getWidth()
    local is_landscape = self:isLandscape()

    self.board_widget = BridgesBoardWidget:new{
        board       = self.board,
        onTapAction = function(r, c) self:onTapCell(r, c) end,
    }

    local board_frame = FrameContainer:new{
        padding = Size.padding.large,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local board_frame_size  = self.board_widget.size + (Size.padding.large + Size.margin.default) * 2
    local right_panel_width = sw - board_frame_size - Size.span.horizontal_default
    local button_width = is_landscape
        and math.max(right_panel_width - Size.span.horizontal_default, 100)
        or  math.floor(sw * 0.9)

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {
            {
                { text = _("New"),  callback = function() self:onNewGame() end },
                { id = "grid_button", text = self:getGridButtonText(),
                  callback = function() self:openGridMenu() end },
                { id = "diff_button", text = self:getDiffButtonText(),
                  callback = function() self:openDifficultyMenu() end },
                { text = _("Check"), callback = function() self:onCheck() end },
                self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
                self:makeCloseButtonConfig(),
            },
        },
    }
    self.grid_button = top_buttons:getButtonById("grid_button")
    self.diff_button = top_buttons:getButtonById("diff_button")

    local bottom_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {
            {
                { text = _("Reset"), callback = function() self:onReset() end },
                { text = _("Rules"), callback = function() self:showRulesHint() end },
            },
        },
    }

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
        }
        self.layout = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
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

function BridgesScreen:showRulesHint()
    if _.lang() == "fr" then
        self:showMessage(
            "Ponts (Hashiwokakero) :\n" ..
            "Reliez les îles par des ponts horizontaux/verticaux.\n" ..
            "Le chiffre d'une île = nombre de ponts qui s'y connectent.\n" ..
            "Maximum 2 ponts entre deux îles. Les ponts ne se croisent pas.\n" ..
            "Toutes les îles doivent former un seul groupe connecté.\n\n" ..
            "Appuyez sur une île pour la sélectionner, puis sur une autre île\n" ..
            "dans la même ligne ou colonne pour alterner les ponts (0\xE2\x86\x921\xE2\x86\x922\xE2\x86\x920)."
        , 12)
    else
        self:showMessage(_(
            "Bridges (Hashiwokakero) rules:\n" ..
            "Connect islands with horizontal/vertical bridges.\n" ..
            "Each island's number = total bridges connected to it.\n" ..
            "At most 2 bridges between any pair. Bridges cannot cross.\n" ..
            "All islands must form one connected group.\n\n" ..
            "Tap an island to select, then tap another island\n" ..
            "in the same row or column to toggle bridges (0\xE2\x86\x921\xE2\x86\x922\xE2\x86\x920)."
        ), 12)
    end
end

function BridgesScreen:openGridMenu()
    local sizes = {}
    for _, sz in ipairs(GRID_SIZES) do
        sizes[#sizes+1] = { id = sz, text = sz .. "\xC3\x97" .. sz }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select grid size"),
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
        status = T(_("%1\xC3\x97%2 \xC2\xB7 %3 \xC2\xB7 %4/%5 islands done"),
            self.board.n, self.board.n, label, sat, total)
    end
    ScreenBase.updateStatus(self, status)
end

function BridgesScreen:getGridButtonText()
    return T(_("Grid: %1"), self.board.n .. "\xC3\x97" .. self.board.n)
end

function BridgesScreen:getDiffButtonText()
    local diff  = self.plugin:getSetting("difficulty", "easy")
    local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
    return T(_("Diff: %1"), label)
end

return BridgesScreen
