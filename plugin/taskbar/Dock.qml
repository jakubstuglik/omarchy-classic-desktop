// /**
//  * @version   0.1.0
//  * @package   omarchy-classic-desktop
//  * Derived from Omarchy Classic Desktop (OCD) by Fotis Evangelou
//  * @url       https://github.com/fevangelou/ocd
//  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
//  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
//  */

// ocd Dock — a `service`-kind plugin owning its own layer-shell surface
// (confirmed pattern: shell/plugins/background/Background.qml does the
// same thing). A service is loaded at startup regardless of the "dock"
// feature flag; ocd apply toggles it in shell.json via setPluginEnabled,
// but this file also re-checks features.json itself on load/refresh so it
// never shows stale UI between a features.json edit and the next apply.
//
// Persistent taskbar, not a floating auto-hide dock: a full-width bar at
// the bottom, always visible, reserving screen space (exclusionMode.Auto —
// same convention Omarchy's own bar uses at the top, confirmed by reading
// shell/plugins/bar/Bar.qml). Windows 11-style: centered icon buttons with
// a short label, one button per app (pins stay visible while running).
// Herdr runs inside foot, so clients.sh maps those windows to identity
// "herdr" instead of "foot".
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "AppMatcher.js" as AppMatcher

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/omarchy/ocd"
  readonly property string overridesPath: configDir + "/appid-overrides.json"
  // dock-pins.json: a plain JSON array of pinned-app entries, each
  // { "desktopId": "<desktop entry id, without .desktop>", "exec": "<Exec= line, used verbatim if desktopId can't be resolved>" }.
  // ocd's own file (not inline on a shell.json entry): the inline-settings
  // convention documented for shell.json is specific to bar-widget kind
  // entries, and the dock is a service kind here, with no confirmed
  // equivalent — see AGENTS.md.
  readonly property string pinsPath: configDir + "/dock-pins.json"
  readonly property string ocdBin: home + "/.local/share/ocd/bin/ocd"
  readonly property string pluginDir: home + "/.config/omarchy/plugins/io.github.jstuglik.taskbar"

  property bool dockFeatureEnabled: true
  property var pins: []
  property var clients: []
  // Unified, ordered list of taskbar buttons: pinned apps first (always
  // visible), then any running apps that are not pinned. One button per
  // app, not per window.
  property var tabs: []
  // Address (normalized, "0x...") of the currently-focused window, so its
  // tab can be visually distinguished from other running-but-unfocused
  // ones. Kept as plain hyprctl JSON rather than a Quickshell/Hyprland
  // "active toplevel" property, since none was confirmed to exist.
  property string activeAddress: ""
  // Last *client* window that had focus. Clicking the taskbar unfocuses the
  // app (the layer-shell surface takes the click), so we must not treat
  // "no active window" as "this app is not in front".
  property string lastRealAddress: ""
  property string lastRealIdentity: ""
  property string lastRealDesktopId: ""
  property var contextItem: null
  property real contextX: 0

  readonly property int barHeight: Style.space(48)
  readonly property int itemWidth: Style.space(68)

  function refreshFeatureFlag() { featureReadProc.running = true }
  function refreshOverrides() { overridesReadProc.running = true }
  function refreshPins() { pinsReadProc.running = true }
  function refreshWindows() {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    clientsProc.running = true
    activeWindowProc.running = true
  }

  Process {
    id: activeWindowProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "").trim())
          var addr = (parsed && parsed.address) ? root.ocdNormalizeAddress(parsed.address) : ""
          if (!addr || addr === "0x0" || addr === "0x") {
            root.activeAddress = ""
          } else {
            root.activeAddress = addr
            root.lastRealAddress = addr
            var ident = ""
            var list = root.clients || []
            for (var i = 0; i < list.length; i++) {
              if (list[i].address === addr) {
                ident = list[i].identity || ""
                break
              }
            }
            if (!ident && parsed.class) ident = String(parsed.class)
            if (ident) {
              root.lastRealIdentity = ident
              root.lastRealDesktopId = root.desktopIdForIdentity(ident)
            }
          }
        } catch (e) { root.activeAddress = "" }
      }
    }
  }

  // Quickshell's Hyprland.toplevels reports each window's address WITHOUT
  // the "0x" prefix that hyprctl's own JSON (and its window selectors,
  // "address:0x...") use — confirmed live: restore silently failed every
  // time until this was added, because the selector matched no window.
  function ocdNormalizeAddress(addr) {
    var s = String(addr || "")
    return s.indexOf("0x") === 0 ? s : "0x" + s
  }

  function pinMatches(pin, identity) {
    var id = String(identity || "").toLowerCase()
    if (!id) return false
    if (String(pin.desktopId || "").toLowerCase() === id) return true
    var matches = pin.match || []
    for (var i = 0; i < matches.length; i++) {
      if (String(matches[i] || "").toLowerCase() === id) return true
    }
    return false
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (!value) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    if (themed && String(themed).length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  function makeButton(pin, windows, fallbackId, fallbackTitle) {
    var desktopId = pin ? pin.desktopId : (fallbackId || "")
    var resolved = AppMatcher.resolve(desktopId, fallbackTitle || "", typeof DesktopEntries !== "undefined" ? DesktopEntries : null)
    var label = (pin && pin.label) || resolved.name || desktopId || "App"
    var icon = (pin && pin.icon) || resolved.icon || desktopId
    var active = false
    var allMin = windows.length > 0
    var address = ""
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      if (!w.minimized) allMin = false
      if (w.address === root.activeAddress) active = true
      if (!address) address = w.address
    }
    return {
      kind: pin ? "pinned" : "window",
      label: label,
      icon: iconSource(icon),
      exec: (pin && pin.exec) || resolved.exec || "",
      desktopId: desktopId,
      windows: windows,
      running: windows.length > 0,
      isMinimized: allMin,
      isActive: active,
      address: address
    }
  }

  // recomputeTabs: pinned apps stay visible even while running (Win11).
  // Unpinned running apps appear after the pins. Herdr-in-foot is already
  // remapped to identity "herdr" by clients.sh.
  function recomputeTabs() {
    var list = []
    var used = ({})
    var raw = root.clients || []

    for (var i = 0; i < root.pins.length; i++) {
      var p = root.pins[i]
      var windows = []
      for (var j = 0; j < raw.length; j++) {
        var c = raw[j]
        if (pinMatches(p, c.identity)) {
          windows.push(c)
          used[c.address] = true
        }
      }
      list.push(makeButton(p, windows, p.desktopId, p.label || ""))
    }

    for (var k = 0; k < raw.length; k++) {
      var extra = raw[k]
      if (used[extra.address]) continue
      var grouped = [extra]
      used[extra.address] = true
      for (var n = k + 1; n < raw.length; n++) {
        var sib = raw[n]
        if (used[sib.address]) continue
        if (String(sib.identity || "") === String(extra.identity || "") && extra.identity) {
          grouped.push(sib)
          used[sib.address] = true
        }
      }
      var resolvedExtra = AppMatcher.resolve(extra.identity, extra.title, typeof DesktopEntries !== "undefined" ? DesktopEntries : null)
      list.push(makeButton(null, grouped, resolvedExtra.desktopId || extra.identity, extra.title))
    }
    root.tabs = list
  }

  Process {
    id: featureReadProc
    command: ["jq", "-r", ".features.dock // true", root.configDir + "/features.json"]
    stdout: StdioCollector {
      onStreamFinished: root.dockFeatureEnabled = (String(text || "").trim() !== "false")
    }
  }

  Process {
    id: overridesReadProc
    command: ["cat", root.overridesPath]
    stdout: StdioCollector {
      onStreamFinished: { AppMatcher.loadOverrides(String(text || "")); root.recomputeTabs() }
    }
  }

  Process {
    id: pinsReadProc
    command: ["jq", "-c", ".", root.pinsPath]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = String(text || "").trim()
        try { root.pins = t.length > 0 ? JSON.parse(t) : [] }
        catch (e) { root.pins = [] }
        root.recomputeTabs()
      }
    }
  }

  Process {
    id: clientsProc
    command: [root.pluginDir + "/clients.sh"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.clients = JSON.parse(String(text || "").trim() || "[]") }
        catch (e) { root.clients = [] }
        root.recomputeTabs()
      }
    }
  }

  Process { id: writePinsProc }
  function persistPins() {
    var json = JSON.stringify(root.pins)
    var script = "mkdir -p " + AppMatcher.shQuote(root.configDir) +
      " && printf '%s' " + AppMatcher.shQuote(json) + " > " + AppMatcher.shQuote(root.pinsPath)
    writePinsProc.command = ["bash", "-c", script]
    writePinsProc.running = true
  }

  function addPin(desktopId, exec) {
    for (var i = 0; i < pins.length; i++) if (pins[i].desktopId === desktopId) return
    var next = pins.slice()
    next.push({ desktopId: desktopId, exec: exec || "" })
    pins = next
    persistPins()
    recomputeTabs()
  }

  function removePin(desktopId) {
    pins = pins.filter(function (p) { return p.desktopId !== desktopId })
    persistPins()
    recomputeTabs()
  }

  function isPinned(desktopId) {
    for (var i = 0; i < pins.length; i++) if (pins[i].desktopId === desktopId) return true
    return false
  }

  Process { id: launchProc }
  function launchPinned(desktopId, execString) {
    if (execString) {
      launchExec(execString)
      return
    }
    if (desktopId) {
      launchProc.command = ["uwsm-app", "--", "gtk-launch", String(desktopId) + ".desktop"]
      launchProc.running = true
    }
  }

  Process { id: actionProc }
  function windowAction(action, address) {
    if (!address) return
    actionProc.command = [root.home + "/.local/bin/ocd-window", action, address]
    actionProc.running = true
  }

  function forEachWindow(item, fn) {
    var windows = (item && item.windows) || []
    for (var i = 0; i < windows.length; i++) fn(windows[i])
  }

  function desktopIdForIdentity(ident) {
    var id = String(ident || "")
    if (!id) return ""
    for (var i = 0; i < root.pins.length; i++) {
      if (root.pinMatches(root.pins[i], id)) return root.pins[i].desktopId
    }
    var tabs = root.tabs || []
    for (var t = 0; t < tabs.length; t++) {
      var ws = tabs[t].windows || []
      for (var w = 0; w < ws.length; w++) {
        if (String(ws[w].identity || "").toLowerCase() === id.toLowerCase())
          return tabs[t].desktopId
      }
    }
    return id
  }

  function liveTab(item) {
    if (!item) return null
    var tabs = root.tabs || []
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].desktopId === item.desktopId) return tabs[i]
    }
    return item
  }

  function windowsForItem(item) {
    if (!item) return []
    var live = root.liveTab(item) || item
    if (live.windows && live.windows.length) return live.windows
    var out = []
    var list = root.clients || []
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (root.pinMatches({ desktopId: item.desktopId, match: item.match }, c.identity))
        out.push(c)
      else if (String(c.identity || "").toLowerCase() === String(item.desktopId || "").toLowerCase())
        out.push(c)
    }
    return out
  }

  function rememberItem(item, address, identity) {
    if (address) root.lastRealAddress = address
    if (identity) root.lastRealIdentity = identity
    if (item && item.desktopId) root.lastRealDesktopId = item.desktopId
    else if (identity) root.lastRealDesktopId = root.desktopIdForIdentity(identity)
  }

  function itemIsInFront(item) {
    if (!item) return false
    if (item.isActive) return true
    if (root.lastRealDesktopId && item.desktopId
        && String(item.desktopId) === String(root.lastRealDesktopId))
      return true
    var windows = root.windowsForItem(item)
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      if (root.lastRealAddress && w.address === root.lastRealAddress) return true
      if (root.lastRealIdentity && w.identity
          && String(w.identity).toLowerCase() === String(root.lastRealIdentity).toLowerCase())
        return true
    }
    return false
  }

  function activateItem(item) {
    item = root.liveTab(item)
    if (!item) return
    var windows = root.windowsForItem(item)
    console.log("[ocd-dock] activate " + item.desktopId
      + " windows=" + windows.length
      + " inFront=" + root.itemIsInFront(item)
      + " lastDesk=" + root.lastRealDesktopId
      + " lastAddr=" + root.lastRealAddress)
    if (windows.length === 0) {
      root.launchPinned(item.desktopId, item.exec)
      return
    }
    var firstMapped = null
    var firstMin = null
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      if (w.minimized) {
        if (!firstMin) firstMin = w
        continue
      }
      if (!firstMapped) firstMapped = w
    }
    if (!firstMapped && firstMin) {
      root.restoreMinimized(firstMin.address)
      root.rememberItem(item, firstMin.address, firstMin.identity)
      return
    }
    if (firstMapped && root.itemIsInFront(item)) {
      var minAddrs = []
      for (var j = 0; j < windows.length; j++) {
        if (!windows[j].minimized) minAddrs.push(windows[j].address)
      }
      console.log("[ocd-dock] minimize " + minAddrs.join(","))
      root.runWindowActions("minimize", minAddrs)
      root.lastRealAddress = ""
      root.lastRealIdentity = ""
      root.lastRealDesktopId = ""
      root.activeAddress = ""
      return
    }
    if (firstMapped) {
      root.focusWindow(firstMapped.address)
      root.rememberItem(item, firstMapped.address, firstMapped.identity)
    }
  }

  function openContextMenu(item, x) {
    item = root.liveTab(item)
    if (!item) return
    console.log("[ocd-dock] context menu for " + item.desktopId)
    root.contextItem = item
    root.contextX = x
  }

  function closeContextMenu() {
    root.contextItem = null
  }

  function contextMenuModel(item) {
    var items = []
    if (!item) return items
    if (item.running && item.isMinimized)
      items.push({ id: "restore", label: "Restore", danger: false, sep: false })
    if (item.running && !item.isMinimized)
      items.push({ id: "minimize", label: "Minimize", danger: false, sep: false })
    if (item.running)
      items.push({ id: "maximize", label: "Maximize", danger: false, sep: false })
    if (items.length > 0)
      items.push({ id: "sep-1", label: "", danger: false, sep: true })
    if (item.desktopId && root.isPinned(item.desktopId))
      items.push({ id: "unpin", label: "Unpin from taskbar", danger: false, sep: false })
    else if (item.desktopId)
      items.push({ id: "pin", label: "Pin to taskbar", danger: false, sep: false })
    if (item.running) {
      items.push({ id: "sep-2", label: "", danger: false, sep: true })
      items.push({ id: "close", label: "Close window", danger: true, sep: false })
    }
    return items
  }

  function runContextAction(id) {
    var item = root.contextItem
    root.closeContextMenu()
    if (!item) return
    if (id === "restore") root.restoreItem(item)
    else if (id === "minimize") root.minimizeItem(item)
    else if (id === "maximize") root.maximizeItem(item)
    else if (id === "pin") root.addPin(item.desktopId, item.exec)
    else if (id === "unpin") root.removePin(item.desktopId)
    else if (id === "close") root.closeItem(item)
  }

  function runWindowActions(action, addresses) {
    var addrs = []
    for (var i = 0; i < addresses.length; i++) if (addresses[i]) addrs.push(addresses[i])
    if (addrs.length === 0) return
    var parts = []
    for (var j = 0; j < addrs.length; j++) {
      parts.push(AppMatcher.shQuote(root.home + "/.local/bin/ocd-window") + " " + action + " " + AppMatcher.shQuote(addrs[j]))
    }
    actionProc.command = ["bash", "-c", parts.join("; ")]
    actionProc.running = true
  }

  function closeItem(item) {
    var addrs = []
    forEachWindow(item, function (w) { addrs.push(w.address) })
    root.runWindowActions("close", addrs)
  }

  function minimizeItem(item) {
    var addrs = []
    forEachWindow(item, function (w) {
      if (!w.minimized) addrs.push(w.address)
    })
    root.runWindowActions("minimize", addrs)
  }

  function maximizeItem(item) {
    var target = null
    var windows = item.windows || []
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].address === root.activeAddress) { target = windows[i]; break }
      if (!target && !windows[i].minimized) target = windows[i]
      if (!target) target = windows[i]
    }
    if (target) {
      if (target.minimized) root.restoreMinimized(target.address)
      root.windowAction("maximize", target.address)
    }
  }

  function restoreItem(item) {
    forEachWindow(item, function (w) {
      if (w.minimized) root.restoreMinimized(w.address)
    })
  }
  function launchExec(execString) {
    if (!execString) return
    // Strip desktop-entry field codes (%f %u %U etc.) — we're launching
    // with no file/URL argument context.
    var cleaned = String(execString).replace(/%[fFuUdDnNickvm]/g, "").trim()
    launchProc.command = ["bash", "-c", cleaned + " >/dev/null 2>&1 & disown"]
    launchProc.running = true
  }

  Process { id: focusProc }
  function focusWindow(address) {
    // Was toplevel.wayland.activate() (Quickshell's own protocol-level
    // activate) — confirmed live to be the wrong choice, same bug as
    // Exposé's identically-named issue: if another window was
    // maximized/fullscreened, activate() left it fullscreen and visually
    // on top even after focus moved to the clicked tab. hl.dsp.focus()
    // via hyprctl eval (same mechanism restoreMinimized() below uses) was
    // confirmed to correctly clear the outgoing window's fullscreen state
    // as a side effect of a normal Hyprland-native focus change.
    // Hyprland maximized/fullscreen windows sit on an exclusive layer.
    // Focus alone cannot bring another window in front of them — drop that
    // layer on everyone else, then focus and raise the clicked tab.
    focusProc.command = [root.home + "/.local/bin/ocd-raise-window", address]
    focusProc.running = true
  }

  Process {
    id: restoreProc
    stdout: SplitParser { onRead: line => console.log("[ocd-dock restore stdout] " + line) }
    stderr: SplitParser { onRead: line => console.log("[ocd-dock restore stderr] " + line) }
    onExited: (exitCode, exitStatus) => console.log("[ocd-dock restore] exited code=" + exitCode + " status=" + exitStatus)
  }
  function restoreMinimized(address) {
    console.log("[ocd-dock] restoreMinimized() called, address=" + address)
    // Same mechanism as lib/minimize.sh's ocd_sweep_minimized: move out of
    // special:minimized to the active workspace, then focus. Quattro's
    // `hyprctl dispatch <name> <args>` CLI form no longer works (it's
    // parsed as Lua and expects an hl.dsp.* dispatcher object, not a raw
    // comma-joined string — confirmed live), so this goes through
    // `hyprctl eval` calling hl.dsp.window.move()/hl.dsp.focus() with a
    // `window` selector ("address:0x...") instead. Shelled out rather than
    // using Hyprland.dispatch() directly since that Quickshell API's exact
    // argument form isn't confirmed, while this hyprctl eval form is.
    var script = "t=$(hyprctl activeworkspace -j | jq -r '.id // 1'); " +
      "hyprctl eval \"hl.dispatch(hl.dsp.window.move({workspace = '$t', window = 'address:" + address + "'}))\"; " +
      root.home + "/.local/bin/ocd-raise-window " + address
    console.log("[ocd-dock] restore script=" + script)
    restoreProc.command = ["bash", "-c", script]
    restoreProc.running = true
  }

  IpcHandler {
    target: "ocd-classic"
    function ping(): string { return "ok" }
    function activate(desktopId: string): string {
      var tabs = root.tabs || []
      for (var i = 0; i < tabs.length; i++) {
        if (String(tabs[i].desktopId) === String(desktopId) || String(tabs[i].label) === String(desktopId)) {
          root.activateItem(tabs[i])
          return "activated:" + tabs[i].desktopId
        }
      }
      return "missing:" + desktopId
    }
    function contextMenu(desktopId: string): string {
      var tabs = root.tabs || []
      for (var i = 0; i < tabs.length; i++) {
        if (String(tabs[i].desktopId) === String(desktopId) || String(tabs[i].label) === String(desktopId)) {
          root.openContextMenu(tabs[i], 600)
          return "menu:" + tabs[i].desktopId
        }
      }
      return "missing:" + desktopId
    }
    function dump(): string {
      return JSON.stringify({
        lastRealDesktopId: root.lastRealDesktopId,
        lastRealAddress: root.lastRealAddress,
        lastRealIdentity: root.lastRealIdentity,
        activeAddress: root.activeAddress,
        tabs: root.tabs
      })
    }
  }

  Component.onCompleted: {
    refreshFeatureFlag()
    refreshOverrides()
    refreshPins()
    refreshWindows()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = (event && event.name) ? String(event.name) : ""
      if (!name) return
      if (name.indexOf("window") !== -1 || name === "workspace" || name === "focusedmon"
          || name === "fullscreen" || name === "minimize" || name === "changefloatingmode")
        root.refreshWindows()
    }
  }

  // Polling fallback: the Quickshell docs note many Hyprland actions don't
  // send change events, so a modest poll keeps the dock honest even if a
  // specific event class isn't covered by onRawEvent above.
  Timer {
    interval: 4000
    running: true
    repeat: true
    onTriggered: {
      root.refreshWindows()
      root.refreshPins()
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.dockFeatureEnabled
      color: Util.alpha(Color.background, 0.97)

      WlrLayershell.namespace: "ocd-classic-taskbar"
      WlrLayershell.layer: WlrLayer.Top
      // Persistent, reserved-space bar — same convention Omarchy's own
      // bar uses (confirmed: shell/plugins/bar/Bar.qml sets
      // ExclusionMode.Auto for its normal, non-hidden state). This is a
      // deliberate change from an earlier auto-hide design: a always-on
      // taskbar is the explicit request, so it costs the same tiling-area
      // shrink the top bar already costs.
      exclusionMode: ExclusionMode.Auto

      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.barHeight

      Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: Math.max(1, Style.space(1))
        color: Util.alpha(Color.foreground, 0.18)
      }

      Row {
        id: tabsRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: Style.space(2)

        Repeater {
          model: root.tabs
          delegate: DockItem {
            required property var modelData
            required property int index
            tabIndex: index
            width: root.itemWidth
            height: tabsRow.height
            label: modelData.label
            icon: modelData.icon
            pinned: modelData.kind === "pinned"
            running: modelData.running
            isMinimized: modelData.isMinimized
            isActive: modelData.isActive
            onActivated: root.activateItem(modelData)
            onContextMenuRequested: root.openContextMenu(modelData, tabsRow.x + x + width / 2 - Style.space(94))
          }
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: menuLayer
      required property var modelData
      screen: modelData
      visible: root.contextItem !== null
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "ocd-classic-taskbar-menu"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      anchors { top: true; bottom: true; left: true; right: true }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.closeContextMenu()
      }

      Rectangle {
        id: menuCard
        width: Style.space(188)
        implicitHeight: menuCol.implicitHeight + Style.space(8)
        x: Math.max(8, Math.min(root.contextX, parent.width - width - 8))
        y: parent.height - root.barHeight - implicitHeight - 6
        color: Color.background
        border.width: 1
        border.color: Util.alpha(Color.foreground, 0.22)
        radius: Math.max(6, Style.space(6))

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: mouse.accepted = true
        }

        Column {
          id: menuCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(4)
          spacing: 0

          Repeater {
            model: root.contextMenuModel(root.contextItem)
            delegate: Item {
              required property var modelData
              width: menuCol.width
              height: modelData.sep ? Style.space(9) : Style.space(28)

              Rectangle {
                visible: modelData.sep
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                height: 1
                color: Util.alpha(Color.foreground, 0.16)
              }

              Rectangle {
                visible: !modelData.sep
                anchors.fill: parent
                radius: Math.max(4, Style.space(4))
                color: menuRowMouse.containsMouse
                  ? Util.alpha(Color.foreground, 0.12)
                  : "transparent"
              }

              Text {
                visible: !modelData.sep
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                verticalAlignment: Text.AlignVCenter
                text: modelData.label
                font.family: Style.font.family
                font.pixelSize: Math.max(10, Style.font.title - 3)
                color: modelData.danger ? Color.urgent : Color.foreground
              }

              MouseArea {
                id: menuRowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !modelData.sep
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.runContextAction(modelData.id)
              }
            }
          }
        }
      }
    }
  }
}
