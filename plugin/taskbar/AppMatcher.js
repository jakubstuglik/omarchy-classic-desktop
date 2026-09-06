// /**
//  * @version   0.1.0
//  * @package   omarchy-classic-desktop
//  * Derived from Omarchy Classic Desktop (OCD) by Fotis Evangelou
//  * @url       https://github.com/fevangelou/ocd
//  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
//  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
//  */

// AppMatcher.js — appId -> {name, icon} resolution for ocd's dock/Exposé.
//
// Chromium web apps launched by Omarchy report WM_CLASS/appId as
// chrome-<host>_<path>-<Profile>. That string is not a desktop-file id.
// clients.sh remaps it to the matching omarchy-launch-webapp desktop id
// (by URL host, ignoring Chromium profile). This file does the same
// lookup against DesktopEntries so an unmapped chrome-* id still gets
// the desktop file's name/icon instead of a generic executable.
//
// Per-machine overrides stay at ~/.config/omarchy/ocd/appid-overrides.json
// and are merged on top of the built-in seed. Keys are matched
// case-insensitively.
//
// appid-overrides.json schema — a flat object keyed by appId:
//   {
//     "chrome-mail.google.com_mail_u_0-Default": { "name": "Gmail", "icon": "gmail" },
//     "some-other-appid": { "desktopId": "org.some.App" }
//   }
// Either "desktopId" (resolved via DesktopEntries.byId, preferred — picks
// up the entry's real name/icon) or an explicit "name"/"icon" pair works;
// "desktopId" wins if both are present. Missing "icon" degrades to a
// generic icon, never to a missing/blank entry.
.pragma library

var DEFAULT_OVERRIDES = {
  "chrome-mail.google.com_mail_u_0-Default": { name: "Gmail", icon: "gmail" },
  "chrome-app.slack.com_-Default": { name: "Slack", icon: "slack" },
  "chrome-calendar.google.com_calendar_u_0_r-Default": { name: "Calendar", icon: "google-calendar" },
  "chrome-www.youtube.com_-Default": { name: "YouTube", icon: "youtube" },
  "herdr": { name: "Herdr", icon: "herdr", desktopId: "Herdr" },
  "foot": { name: "Terminal", icon: "foot", desktopId: "foot" },
  "spotify": { name: "Spotify", icon: "spotify", desktopId: "Spotify" },
  "idea": { name: "IntelliJ IDEA", icon: "/usr/share/idea/bin/idea.png", desktopId: "idea" },
  "jetbrains-idea": { name: "IntelliJ IDEA", icon: "/usr/share/idea/bin/idea.png", desktopId: "idea" }
}

var _overrides = null

function loadOverrides(rawJson) {
  var parsed = {}
  try {
    if (rawJson && rawJson.trim().length > 0) parsed = JSON.parse(rawJson)
  } catch (e) {
    parsed = {}
  }
  var merged = {}
  for (var k in DEFAULT_OVERRIDES) merged[k] = DEFAULT_OVERRIDES[k]
  for (var k2 in parsed) merged[k2] = parsed[k2]
  _overrides = merged
  return merged
}

function overrideFor(appId, overrides) {
  if (!appId || !overrides) return undefined
  if (overrides[appId]) return overrides[appId]
  var lower = String(appId).toLowerCase()
  if (overrides[lower]) return overrides[lower]
  for (var k in overrides) {
    if (String(k).toLowerCase() === lower) return overrides[k]
  }
  return undefined
}

function entryExec(entry) {
  if (!entry) return ""
  try {
    if (entry.execString) return String(entry.execString)
    if (entry.command && entry.command.length) {
      var parts = []
      for (var i = 0; i < entry.command.length; i++) parts.push(String(entry.command[i]))
      return parts.join(" ")
    }
  } catch (e) { /* ignore */ }
  return ""
}

function fromEntry(entry, fallbackName, fallbackIcon, fallbackId) {
  return {
    name: (entry && entry.name) || fallbackName,
    icon: (entry && entry.icon) || fallbackIcon || "",
    desktopId: (entry && entry.id) || fallbackId || "",
    exec: entryExec(entry)
  }
}

function normHost(netloc) {
  var host = String(netloc || "").toLowerCase()
  if (host.indexOf("www.") === 0) host = host.substring(4)
  return host
}

function hostFromExec(exec) {
  var s = String(exec || "")
  var m = s.match(/https?:\/\/([^\/\s]+)/i)
  if (m) return normHost(m[1])
  m = s.match(/--app=(\S+)/)
  if (!m) return ""
  var url = m[1].replace(/^['"]|['"]$/g, "")
  if (url.indexOf("://") < 0) url = "https://" + url
  m = url.match(/https?:\/\/([^\/\s]+)/i)
  return m ? normHost(m[1]) : ""
}

function chromeHost(appId) {
  var s = String(appId || "")
  if (s.toLowerCase().indexOf("chrome-") !== 0) return ""
  s = s.substring(7)
  s = s.replace(/-(?:Default|Profile_\d+)$/i, "")
  var cut = s.indexOf("_")
  var host = cut < 0 ? s : s.substring(0, cut)
  return normHost(host)
}

function isWebappExec(exec) {
  var s = String(exec || "")
  return s.indexOf("omarchy-launch-webapp") >= 0
    || s.indexOf("--app=") >= 0
    || s.indexOf("omarchy-webapp-handler-") >= 0
}

function findWebappEntry(desktopEntriesApi, host) {
  if (!desktopEntriesApi || !host) return null
  try {
    var model = desktopEntriesApi.applications
    var values = model && model.values
    if (!values || !values.length) return null
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      var exec = entryExec(entry)
      if (!isWebappExec(exec)) continue
      if (hostFromExec(exec) === host) return entry
    }
  } catch (e) { /* ignore */ }
  return null
}

function lookupEntry(desktopEntriesApi, appId) {
  if (!desktopEntriesApi || !appId) return null
  try {
    var direct = desktopEntriesApi.byId(appId)
    if (direct) return direct
  } catch (e) { /* ignore */ }
  try {
    if (desktopEntriesApi.heuristicLookup) {
      var heuristic = desktopEntriesApi.heuristicLookup(appId)
      if (heuristic) return heuristic
    }
  } catch (e) { /* ignore */ }
  var host = chromeHost(appId)
  if (host) return findWebappEntry(desktopEntriesApi, host)
  return null
}

// resolve(appId, title, desktopEntriesApi) -> { name, icon, desktopId, exec }
// desktopEntriesApi is the Quickshell.DesktopEntries singleton (or null).
// Never returns an empty name: falls back to the window title, then the
// raw appId, so a window never "vanishes" for lack of a match.
function resolve(appId, title, desktopEntriesApi) {
  var overrides = _overrides || DEFAULT_OVERRIDES
  var override = overrideFor(appId, overrides)
  var fallbackName = (title && title.length > 0) ? title : (appId || "Unknown")

  if (override) {
    if (override.desktopId && desktopEntriesApi) {
      try {
        var entry = desktopEntriesApi.byId(override.desktopId)
        if (entry) return fromEntry(entry, override.name || fallbackName, override.icon, override.desktopId)
      } catch (e) { /* fall through */ }
    }
    if (override.name || override.icon) {
      return { name: override.name || fallbackName, icon: override.icon || "", desktopId: override.desktopId || "", exec: "" }
    }
  }

  if (desktopEntriesApi && appId) {
    var found = lookupEntry(desktopEntriesApi, appId)
    if (found) return fromEntry(found, fallbackName, "", found.id || appId)
  }

  return { name: fallbackName, icon: "", desktopId: appId || "", exec: "" }
}

function shQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'"
}
