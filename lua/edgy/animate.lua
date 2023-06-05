local Layout = require("edgy.layout")
local Util = require("edgy.util")
local Config = require("edgy.config")

local M = {}

---@class Edgy.Animate
---@field height number
---@field width number
---@field steps number

---@type table<Edgy.Window, Edgy.Animate>
M.state = setmetatable({}, { __mode = "k" })

---@param win Edgy.Window
function M.get_state(win)
  if not M.state[win] then
    local sidebar = win.view.sidebar
    local long = sidebar.vertical and "height" or "width"
    local short = sidebar.vertical and "width" or "height"
    local bounds = {
      width = vim.api.nvim_win_get_width(win.win),
      height = vim.api.nvim_win_get_height(win.win),
    }
    M.state[win] = {
      [long] = #sidebar.wins == 1 and bounds[long] or 1,
      [short] = #sidebar.wins == 1 and 1 or sidebar.size,
    }
    for _, w in ipairs(sidebar.wins) do
      M.state[win][short] = math.max(M.state[win][short], M.state[w] and M.state[w][short] or 0)
    end
  end
  return M.state[win]
end

---@param win Edgy.Window
function M.step(win, step)
  step = step or (Config.animate.cps / Config.animate.fps)
  local state = M.get_state(win)
  local updated = false
  for _, key in ipairs({ "width", "height" }) do
    local current = vim.api["nvim_win_get_" .. key](win.win)
    if win[key] and state[key] ~= win[key] then
      if state[key] > win[key] then
        state[key] = math.max(state[key] - step, win[key])
      else
        state[key] = math.min(state[key] + step, win[key])
      end
    end
    if current ~= state[key] then
      vim.api["nvim_win_set_" .. key](win.win, math.floor(state[key] + 0.5))
    end
    updated = updated or current ~= win[key]
  end
  return updated
end

function M.animate(step)
  local wins = {} ---@type Edgy.Window[]
  Layout.foreach({ "bottom", "top", "left", "right" }, function(sidebar)
    for _, win in ipairs(sidebar.wins) do
      if win:is_valid() then
        wins[#wins + 1] = win
      end
    end
  end)

  local views = {}
  for _, win in ipairs(wins) do
    vim.api.nvim_win_call(win.win, function()
      views[win.win] = vim.fn.winsaveview()
    end)
  end
  local updated = false
  for _, win in ipairs(wins) do
    if M.step(win, step) then
      updated = true
    end
  end
  for win, view in ipairs(views) do
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview(view)
    end)
  end
  return updated
end

M.animate = Util.noautocmd(M.animate)

function M.update()
  if M.animate(0) then
    M.schedule()
  end
end

---@type uv_timer_t
local timer
function M.schedule()
  if not (timer and timer:is_active()) then
    Config.animate.on_begin()
    timer = vim.defer_fn(function()
      if M.animate() then
        M.schedule()
      else
        Config.animate.on_end()
      end
    end, 1000 / Config.animate.fps)
  end
end

return M