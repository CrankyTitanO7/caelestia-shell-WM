pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n

Singleton {
    id: root

    readonly property bool isHyprland: GlobalConfig.general.windowManager === WindowManager.Hyprland
    readonly property bool isNiri: GlobalConfig.general.windowManager === WindowManager.Niri
    readonly property string backendName: isNiri ? "niri" : "hyprland"

    readonly property var hyprland: hyprlandLoader.item
    readonly property var niri: niriLoader.item
    readonly property var backend: isNiri ? niri : hyprland

    readonly property var toplevels: backend?.toplevels ?? []
    readonly property var workspaces: backend?.workspaces ?? []
    readonly property var monitors: backend?.monitors ?? []
    readonly property var activeToplevel: backend?.activeToplevel ?? null
    readonly property var focusedWorkspace: backend?.focusedWorkspace ?? null
    readonly property var focusedMonitor: backend?.focusedMonitor ?? null
    readonly property int activeWsId: backend?.activeWsId ?? 1
    readonly property int activeWsIndex: backend?.activeWsIndex ?? activeWsId

    readonly property bool available: backend?.available ?? false
    readonly property bool capsLock: backend?.capsLock ?? false
    readonly property bool numLock: backend?.numLock ?? false
    readonly property string kbLayoutFull: backend?.kbLayoutFull ?? Tr.trCtx("Unknown", "keyboard layout")
    readonly property var keyboardLayouts: {
        const layouts = backend?.keyboardLayouts ?? [];
        return layouts.map(layout => {
            const label = kbLabelMap.get(layout);
            return label ? `${layout.toUpperCase()} - ${label}` : layout;
        });
    }
    readonly property int activeKeyboardLayoutIndex: backend?.activeKeyboardLayoutIndex ?? -1
    readonly property string defaultKbLayout: {
        const layout = backend?.defaultKbLayout ?? "??";
        return kbMap.get(layout) ?? layout;
    }
    readonly property string kbLayout: {
        const raw = kbLayoutFull;
        if (!raw)
            return "??";
        return kbMap.get(raw) ?? raw;
    }
    property var kbMap: new Map()
    property var kbLabelMap: new Map()

    readonly property real borderWidth: backend?.borderWidth ?? 2
    readonly property real borderRounding: backend?.borderRounding ?? 0

    readonly property bool supportsSpecialWorkspaces: isHyprland
    readonly property bool supportsPinning: isHyprland
    readonly property bool supportsOverview: isNiri
    readonly property bool inOverview: backend?.inOverview ?? false

    signal configReloaded

    function focusWorkspace(ws: var): void {
        backend?.focusWorkspace(ws);
    }

    function focusRelativeWorkspace(direction: string): void {
        backend?.focusRelativeWorkspace(direction);
    }

    function moveWindowToWorkspace(window: var, ws: var, follow = true): void {
        backend?.moveWindowToWorkspace(window, ws, follow);
    }

    function toggleFloating(window: var): void {
        backend?.toggleFloating(window);
    }

    function togglePinned(window: var): void {
        backend?.togglePinned(window);
    }

    function closeWindow(window: var): void {
        backend?.closeWindow(window);
    }

    function focusWindow(window: var): void {
        backend?.focusWindow(window);
    }

    function setDpms(enabled: bool): void {
        backend?.setDpms(enabled);
    }

    function switchKeyboardLayout(index: int): void {
        backend?.switchKeyboardLayout(index);
    }

    function reloadConfig(): void {
        backend?.reloadConfig();
    }

    function refreshDevices(): void {
        backend?.refreshDevices();
    }

    function monitorFor(screen: var): var {
        return backend?.monitorFor(screen) ?? null;
    }

    function monitorNames(): var {
        return backend?.monitorNames() ?? [];
    }

    function trimWsName(name: string): string {
        return backend?.trimWsName(name) ?? name;
    }

    function toplevelsForWs(ws: var, ignoredTags = []): var {
        return backend?.toplevelsForWs(ws, ignoredTags) ?? [];
    }

    function isToplevelIgnored(toplevel: var, ignoredTags = []): bool {
        return backend?.isToplevelIgnored(toplevel, ignoredTags) ?? false;
    }

    function workspaceForId(id: int, monitor = null): var {
        return backend?.workspaceForId(id, monitor) ?? null;
    }

    function workspaceForIndex(index: int, monitor = null): var {
        return backend?.workspaceForIndex(index, monitor) ?? null;
    }

    function hasFullscreen(monitor = null): bool {
        return backend?.hasFullscreen(monitor) ?? false;
    }

    function queryCursorPosition(callback: var): void {
        backend?.queryCursorPosition(callback);
    }

    LazyLoader {
        id: hyprlandLoader

        active: root.isHyprland
        component: hyprlandComponent
    }

    LazyLoader {
        id: niriLoader

        active: root.isNiri
        component: niriComponent
    }

    Component {
        id: hyprlandComponent

        HyprlandBackend {}
    }

    Component {
        id: niriComponent

        NiriBackend {}
    }

    Connections {
        function onConfigReloaded(): void {
            root.configReloaded();
        }

        target: root.backend
    }

    FileView {
        id: kbLayoutFile

        path: Quickshell.env("CAELESTIA_XKB_RULES_PATH") || "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: {
            const map = new Map();
            const labelMap = new Map();
            const layoutMatch = text().match(/! layout\n([\s\S]*?)(?:\n\n|$)/);
            if (layoutMatch) {
                for (const line of layoutMatch[1].split("\n")) {
                    const match = line.match(/^\s*(\S+)\s+(.+)$/);
                    if (match) {
                        const description = match[2].trim();
                        map.set(description, match[1]);
                        labelMap.set(match[1], description);
                    }
                }
            }

            const variantMatch = text().match(/! variant\n([\s\S]*?)(?:\n\n|$)/);
            if (variantMatch) {
                for (const line of variantMatch[1].split("\n")) {
                    const match = line.match(/^\s*([a-zA-Z0-9_-]+)\s+([a-z]{2,}): (.+)$/);
                    if (match)
                        map.set(match[3].trim(), match[2]);
                }
            }
            root.kbMap = map;
            root.kbLabelMap = labelMap;
        }
    }

    IpcHandler {
        function backend(): string {
            return root.backendName;
        }

        function focusWorkspace(ws: string): void {
            root.focusWorkspace(isNaN(Number(ws)) ? ws : Number(ws));
        }

        function focusRelative(direction: string): void {
            root.focusRelativeWorkspace(direction);
        }

        function switchKeyboardLayout(index: string): void {
            root.switchKeyboardLayout(Number(index));
        }

        function reload(): void {
            root.reloadConfig();
        }

        function monitorNames(): string {
            return root.monitorNames().join("\n");
        }

        target: "wm"
    }
}
