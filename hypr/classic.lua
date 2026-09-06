-- omarchy-classic-desktop 0.2.1
-- Floating, stacking, one-shot open fit. Loaded from hyprland.lua via a
-- marked `require("classic")` block. Does not replace OCD's ocd.lua.

local helper = os.getenv("HOME") .. "/.local/bin/ocd-window"

-- Classic desktop: every window floats. Tiling is not used.
o.window(".*", {
  float = true,
  center = true,
})

-- GTK apps should not draw a second titlebar; hyprbars is the frame.
hl.env("GTK_CSD", "0")

local function vec(v)
  if type(v) ~= "table" then
    return 0, 0
  end
  if v.x ~= nil then
    return tonumber(v.x) or 0, tonumber(v.y) or 0
  end
  return tonumber(v[1]) or 0, tonumber(v[2]) or 0
end

local function reserved_ltrb(mon)
  local r = mon and mon.reserved
  if type(r) == "number" then
    return r, r, r, r
  end
  if type(r) == "table" then
    if r.top ~= nil then
      return tonumber(r.left) or 0, tonumber(r.top) or 0, tonumber(r.right) or 0, tonumber(r.bottom) or 0
    end
    return tonumber(r[1]) or 0, tonumber(r[2]) or 0, tonumber(r[3]) or 0, tonumber(r[4]) or 0
  end
  return 0, 0, 0, 0
end

local function cfg_num(key, fallback)
  local v = hl.get_config(key)
  local n = tonumber(v)
  if n == nil then
    return fallback
  end
  return n
end

-- Work area is the exclusive zone (Omarchy bar + taskbar) minus the
-- window border and the hyprbars titlebar. Titlebars sit *above* the
-- client (`bar_part_of_window = false`) so they must be reserved here;
-- otherwise they land under the Omarchy bar.
local function workarea(mon)
  if mon == nil then
    return nil
  end
  local rl, rt, rr, rb = reserved_ltrb(mon)
  local border = cfg_num("general.border_size", 2)
  local bar = cfg_num("plugin:hyprbars:bar_height", 30)
  local wx = mon.x + rl + border
  local wy = mon.y + rt + border + bar
  local ww = mon.width - rl - rr - (2 * border)
  local wh = mon.height - rt - rb - (2 * border) - bar
  if ww < 200 then
    ww = 200
  end
  if wh < 120 then
    wh = 120
  end
  return wx, wy, ww, wh
end

local function force_float(w)
  if w ~= nil and w.mapped and not w.floating then
    hl.dispatch(hl.dsp.window.float({ action = "on", window = w }))
  end
end

local function skip_fit(w)
  if w == nil or not w.mapped or w.hidden then
    return true
  end
  if w.class == "org.omarchy.screensaver" then
    return true
  end
  local ws = w.workspace
  if ws ~= nil and ws.special and w.visible ~= true then
    return true
  end
  if ws ~= nil and ws.name == "special:minimized" and w.visible ~= true then
    return true
  end
  return false
end

-- One-shot fit when a window first maps. Do not run on a timer or on
-- title changes: Chromium retitles constantly, and a 250ms clamp of a
-- near-full-height window always forces y back to the work-area top,
-- which makes titlebar-drag feel like the window is glued there.
local function fit_new_window(w)
  if skip_fit(w) then
    return
  end
  local wx, wy, ww, wh = workarea(w.monitor)
  if wx == nil then
    return
  end
  local cx, cy = vec(w.at)
  local cw, ch = vec(w.size)
  local nw, nh, nx, ny = cw, ch, cx, cy
  if nw > ww then
    nw = ww
  end
  if nh > wh then
    nh = wh
  end
  -- Keep the hyprbars titlebar out from under the Omarchy bar. Do not
  -- pull a window back to the top just because its bottom would clip;
  -- Windows lets you drag a large window into the middle of the screen.
  if ny < wy then
    ny = wy
  end
  if nx + nw > wx + ww then
    nx = wx + ww - nw
  end
  if nx < wx then
    nx = wx
  end
  force_float(w)
  local cls = string.lower(tostring(w.class or ""))
  if cls:find("chromium", 1, true) or cls:find("chrome", 1, true)
      or cls:find("brave", 1, true) or cls == "spotify" or cls == "code"
      or cls:find("discord", 1, true) then
    hl.dispatch(hl.dsp.window.set_prop({
      window = w,
      prop = "no_xdg_drags",
      value = "1",
    }))
  end
  hl.dispatch(hl.dsp.window.set_prop({
    window = w,
    prop = "max_size",
    value = string.format("%d %d", ww, wh),
  }))
  if nx ~= cx or ny ~= cy or nw ~= cw or nh ~= ch then
    hl.dispatch(hl.dsp.window.resize({ x = nw, y = nh, window = w }))
    hl.dispatch(hl.dsp.window.move({ x = nx, y = ny, relative = false, window = w }))
  end
end

hl.on("window.open", function(w)
  force_float(w)
  fit_new_window(w)
end)
hl.on("window.open_early", force_float)

-- Snap floating windows to each other and to screen edges.
hl.config({
  general = {
    snap = {
      enabled = true,
    },
  },
})

-- Titlebar sits outside the client so app CSDs (JetBrains) cannot cover it.
-- Double-click the bar (not a button) toggles work-area maximize, same as
-- the yellow titlebar button. hyprbars on_double_click is a shell command.
if hl.plugin and hl.plugin.hyprbars then
  hl.config({
    plugin = {
      hyprbars = {
        bar_part_of_window = false,
        on_double_click = helper .. " maximize",
      },
    },
  })
end

-- Windows-style stacking: a focused window comes to the front.
-- Skip hover-only focus (FOCUS_REASON_FFM = 1) so the cursor moving over
-- an overlapped window does not shuffle z-order.
-- Exclusive Hyprland maximize is converted to a normal full-size float so
-- the maximized window keeps its size when you switch away and back.
hl.on("window.active", function(w, reason)
  if w == nil then
    return
  end
  force_float(w)
  if reason == 1 then
    return
  end
  for _, other in ipairs(hl.get_windows() or {}) do
    if other ~= nil and other.address ~= w.address and other.fullscreen ~= 0 then
      hl.exec_cmd(helper .. " keep-max " .. other.address)
    end
  end
  hl.dispatch(hl.dsp.window.bring_to_top({ window = w }))
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = w }))
end)
