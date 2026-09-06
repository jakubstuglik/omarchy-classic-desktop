-- omarchy-classic-desktop 0.7.0
-- Floating, stacking, one-shot open fit, last size/position. Loaded from
-- hyprland.lua via a marked `require("classic")` block. Does not replace
-- OCD's ocd.lua.

local helper = os.getenv("HOME") .. "/.local/bin/ocd-window"
local geom_dir = os.getenv("HOME") .. "/.local/state/ocd-classic"
local geom_path = geom_dir .. "/last-geom.json"
local last_geom = {}

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

local function class_key(w)
  local c = string.lower(tostring((w and (w.class or w.initialClass)) or ""))
  return c
end

local function json_escape(s)
  return (string.gsub(s, '[\\"]', { ["\\"] = "\\\\", ['"'] = '\\"' }))
end

local function load_last_geom()
  local f = io.open(geom_path, "r")
  if f == nil then
    return
  end
  local body = f:read("*a") or ""
  f:close()
  for key, x, y, w, h, maxv in body:gmatch(
    '"([^"]+)":{"x":(-?%d+),"y":(-?%d+),"w":(%d+),"h":(%d+),"max":(%a+)}'
  ) do
    last_geom[key] = {
      x = tonumber(x),
      y = tonumber(y),
      w = tonumber(w),
      h = tonumber(h),
      max = (maxv == "true"),
    }
  end
end

local function persist_last_geom()
  os.execute("mkdir -p " .. geom_dir)
  local f = io.open(geom_path, "w")
  if f == nil then
    return
  end
  local parts = { "{" }
  local first = true
  for key, g in pairs(last_geom) do
    if g ~= nil and g.x ~= nil then
      if not first then
        parts[#parts + 1] = ","
      end
      first = false
      parts[#parts + 1] = string.format(
        '"%s":{"x":%d,"y":%d,"w":%d,"h":%d,"max":%s}',
        json_escape(key),
        g.x, g.y, g.w, g.h,
        g.max and "true" or "false"
      )
    end
  end
  parts[#parts + 1] = "}"
  f:write(table.concat(parts))
  f:close()
end

local function is_workarea_sized(x, y, w, h, wx, wy, ww, wh)
  local function absdiff(a, b)
    if a > b then
      return a - b
    end
    return b - a
  end
  return absdiff(x, wx) <= 24 and absdiff(y, wy) <= 24
    and absdiff(w, ww) <= 48 and absdiff(h, wh) <= 48
end

local function others_of_class(w, key)
  local n = 0
  for _, other in ipairs(hl.get_windows() or {}) do
    if other ~= nil and other.mapped and other.address ~= w.address
        and class_key(other) == key then
      n = n + 1
    end
  end
  return n
end

local function apply_chrome_props(w, ww, wh)
  local cls = class_key(w)
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
end

local function place_window(w, nx, ny, nw, nh)
  force_float(w)
  hl.dispatch(hl.dsp.window.resize({ x = nw, y = nh, window = w }))
  hl.dispatch(hl.dsp.window.move({ x = nx, y = ny, relative = false, window = w }))
end

-- One-shot fit when a window first maps. Prefer the last closed size and
-- position for this app (Windows-style). Extra windows of the same class
-- still get the default fit so they are not stacked on the first.
local function fit_new_window(w)
  if skip_fit(w) then
    return
  end
  local wx, wy, ww, wh = workarea(w.monitor)
  if wx == nil then
    return
  end
  apply_chrome_props(w, ww, wh)

  local key = class_key(w)
  local saved = (key ~= "") and last_geom[key] or nil
  if saved and others_of_class(w, key) == 0 then
    local nx, ny, nw, nh
    if saved.max then
      nx, ny, nw, nh = wx, wy, ww, wh
    else
      nw, nh = saved.w, saved.h
      if nw > ww then nw = ww end
      if nh > wh then nh = wh end
      if nw < 200 then nw = 200 end
      if nh < 120 then nh = 120 end
      nx, ny = saved.x, saved.y
      if ny < wy then ny = wy end
      if nx + nw > wx + ww then nx = wx + ww - nw end
      if nx < wx then nx = wx end
    end
    place_window(w, nx, ny, nw, nh)
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
  if nx ~= cx or ny ~= cy or nw ~= cw or nh ~= ch then
    place_window(w, nx, ny, nw, nh)
  end
end

local function remember_window(w)
  if skip_fit(w) then
    return
  end
  local key = class_key(w)
  if key == "" then
    return
  end
  local cx, cy = vec(w.at)
  local cw, ch = vec(w.size)
  if cw < 120 or ch < 80 then
    return
  end
  local max = false
  local wx, wy, ww, wh = workarea(w.monitor)
  if wx ~= nil then
    max = is_workarea_sized(cx, cy, cw, ch, wx, wy, ww, wh)
  end
  last_geom[key] = { x = cx, y = cy, w = cw, h = ch, max = max }
  persist_last_geom()
end

load_last_geom()

hl.on("window.open", function(w)
  force_float(w)
  fit_new_window(w)
  -- GTK/Chromium often apply their own size just after map; re-apply once.
  local key = class_key(w)
  if key ~= "" and last_geom[key] ~= nil and others_of_class(w, key) == 0 then
    hl.timer(function()
      if w ~= nil and w.mapped then
        fit_new_window(w)
      end
    end, { timeout = 80, type = "oneshot" })
  end
end)
hl.on("window.open_early", force_float)
hl.on("window.close", remember_window)

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
