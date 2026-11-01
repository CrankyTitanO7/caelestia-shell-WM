import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n

Item {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET") ?? ""
    readonly property bool available: socketPath.length > 0
    readonly property bool usingLua: false
    readonly property var options: ({})
    readonly property var extras: null
    readonly property var devices: null
    readonly property var keyboard: null

    readonly property var toplevels: _toplevels
    readonly property var workspaces: _workspaces
    readonly property var monitors: _monitors
    readonly property var activeToplevel: _activeToplevel
    readonly property var focusedWorkspace: _focusedWorkspace
    readonly property var focusedMonitor: _focusedMonitor
    readonly property int activeWsId: _focusedWorkspace?.id ?? 1
    readonly property int activeWsIndex: _focusedWorkspace?.index ?? activeWsId

    readonly property string defaultKbLayout: _kbNames[0] ?? "??"
    readonly property string kbLayoutFull: _kbNames[_kbIndex] ?? Tr.trCtx("Unknown", "keyboard layout")
    readonly property var keyboardLayouts: _kbNames
    readonly property int activeKeyboardLayoutIndex: _kbIndex
    readonly property real borderWidth: 2
    readonly property real borderRounding: 0

    property bool capsLock: false
    property bool numLock: false
    property bool inOverview: false

    property var _toplevels: []
    property var _workspaces: []
    property var _monitors: []
    property var _activeToplevel: null
    property var _focusedWorkspace: null
    property var _focusedMonitor: null
    property var _rawWorkspaces: []
    property var _rawWindows: []
    property var _outputs: []
    property var _kbNames: []
    property int _kbIndex: 0

    signal configReloaded

    function action(name: string, args = []): void {
        if (!available)
            return;

        Quickshell.execDetached(["niri", "msg", "action", name, ...args.map(arg => String(arg))]);
        refreshTimer.restart();
    }

    function workspaceReference(ws: var): var {
        if (ws && typeof ws === "object")
            return ws.name && ws.name !== String(ws.index) ? ws.name : ws.index;
        return ws;
    }

    function focusWorkspace(ws: var): void {
        if (ws === undefined || ws === null)
            return;
        action("focus-workspace", [workspaceReference(ws)]);
    }

    function focusRelativeWorkspace(direction: string): void {
        action(direction === "up" || direction === "prev" || direction === -1 ? "focus-workspace-up" : "focus-workspace-down");
    }

    function toggleSpecialWorkspace(name: string): void {
        // Niri has no special workspaces.
    }

    function cycleSpecialWorkspace(direction: string): void {
        // Niri has no special workspaces.
    }

    function moveWindowToWorkspace(window: var, ws: var, follow = true): void {
        if (!window)
            return;
        action("move-window-to-workspace", ["--window-id", window.id, "--focus", follow ? "true" : "false", workspaceReference(ws)]);
    }

    function toggleFloating(window: var): void {
        if (!window)
            return;
        action("toggle-window-floating", ["--id", window.id]);
    }

    function togglePinned(window: var): void {
        // Niri has no window pinning.
    }

    function closeWindow(window: var): void {
        if (!window)
            return;
        action("close-window", ["--id", window.id]);
    }

    function focusWindow(window: var): void {
        if (!window)
            return;
        action("focus-window", ["--id", window.id]);
    }

    function setDpms(enabled: bool): void {
        action(enabled ? "power-on-monitors" : "power-off-monitors");
    }

    function switchKeyboardLayout(index: int): void {
        action("switch-layout", [index]);
        refreshKeyboard();
    }

    function reloadConfig(): void {
        action("load-config-file");
        configReloaded();
        refreshAll();
    }

    function refreshDevices(): void {
        refreshAll();
        refreshKeyboard();
        refreshLeds();
    }

    function queryCursorPosition(callback: var): void {
        callback(null);
    }

    // Niri-only actions. These are only reachable through Wm.niri while Niri is active.
    function toggleOverview(): void {
        action("toggle-overview");
    }

    function focusColumn(direction: string): void {
        action(`focus-column-${direction}`);
    }

    function moveColumn(direction: string): void {
        action(`move-column-${direction}`);
    }

    function maximizeColumn(): void {
        action("maximize-column");
    }

    function centerWindow(): void {
        action("center-window");
    }

    function screenshotWindow(): void {
        action("screenshot-window");
    }

    function toggleFullscreen(): void {
        action("fullscreen-window");
    }

    function toggleWindowedFullscreen(): void {
        action("toggle-windowed-fullscreen");
    }

    function closeFocusedWindow(): void {
        action("close-window");
    }

    function switchLayout(name: string): void {
        action("switch-layout", [name]);
        refreshKeyboard();
    }

    function doScreenTransition(delayMs = 500): void {
        action("do-screen-transition", ["-d", delayMs]);
    }

    function monitorNames(): var {
        return _monitors.map(monitor => monitor.name);
    }

    function monitorFor(screen: var): var {
        return _monitors.find(monitor => monitor.name === screen?.name) ?? null;
    }

    function trimWsName(name: string): string {
        return name;
    }

    function toplevelsForWs(ws: var, ignoredTags = []): var {
        const workspace = typeof ws === "object" ? ws : (workspaceForIndex(ws) ?? workspaceForId(ws));
        return (workspace?.toplevels ?? []).filter(toplevel => !isToplevelIgnored(toplevel, ignoredTags));
    }

    function isToplevelIgnored(toplevel: var, ignoredTags = []): bool {
        if (!toplevel?.appId || !toplevel?.mapped)
            return true;
        return toplevel.tags?.some(tag => ignoredTags.includes(tag.replace(/\*$/, ""))) ?? false;
    }

    function workspaceForId(id: int, monitor = null): var {
        return _workspaces.find(workspace => workspace.id === id && (!monitor || workspace.monitorId === monitor.id)) ?? null;
    }

    function workspaceForIndex(index: int, monitor = null): var {
        return _workspaces.find(workspace => workspace.index === index && (!monitor || workspace.monitorId === monitor.id)) ?? null;
    }

    function hasFullscreen(monitor = null): bool {
        return false;
    }

    function refreshAll(): void {
        if (!available)
            return;

        if (!workspacesProc.running)
            workspacesProc.running = true;
        if (!windowsProc.running)
            windowsProc.running = true;
        if (!outputsProc.running)
            outputsProc.running = true;
        if (!kbLayoutsProc.running)
            kbLayoutsProc.running = true;
        if (!overviewProc.running)
            overviewProc.running = true;
    }

    function refreshKeyboard(): void {
        if (available && !kbLayoutsProc.running)
            kbLayoutsProc.running = true;
    }

    function refreshLeds(): void {
        if (available && !ledProc.running)
            ledProc.running = true;
    }

    function handleEventLine(line: string): void {
        if (!line)
            return;

        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            return;
        }

        if (event.Ok !== undefined)
            return;

        if (event.OverviewOpenedOrClosed !== undefined) {
            inOverview = !!event.OverviewOpenedOrClosed.is_open;
            return;
        }

        if (event.KeyboardLayoutsChanged !== undefined) {
            const layouts = event.KeyboardLayoutsChanged.keyboard_layouts;
            if (layouts) {
                _kbNames = layouts.names ?? _kbNames;
                _kbIndex = layouts.current_idx ?? _kbIndex;
            }
            return;
        }

        if (event.KeyboardLayoutSwitched !== undefined) {
            refreshKeyboard();
            return;
        }

        if (event.ConfigLoaded !== undefined) {
            configReloaded();
            refreshAll();
            return;
        }

        refreshTimer.restart();
    }

    function rebuild(): void {
        const rawWorkspaces = _rawWorkspaces;
        const rawWindows = _rawWindows;
        const rawOutputs = _outputs;

        const focusedRawWorkspace = rawWorkspaces.find(workspace => workspace.is_focused) ?? null;
        const focusedOutputName = focusedRawWorkspace?.output ?? rawOutputs[0]?.name ?? "";

        const monitors = rawOutputs.map((output, index) => ({
            id: index,
            name: output.name,
            description: `${output.make ?? ""} ${output.model ?? ""}`.trim(),
            focused: output.name === focusedOutputName,
            x: output.logical?.x ?? 0,
            y: output.logical?.y ?? 0,
            width: output.logical?.width ?? 0,
            height: output.logical?.height ?? 0,
            scale: output.logical?.scale ?? 1,
            activeWorkspace: null,
            specialWorkspace: null,
            toplevels: [],
            windowCount: 0,
            raw: output
        }));
        const monitorsByName = new Map(monitors.map(monitor => [monitor.name, monitor]));

        const workspaces = rawWorkspaces.map(workspace => {
            const monitor = monitorsByName.get(workspace.output) ?? null;
            return {
                id: workspace.id,
                index: workspace.idx,
                name: workspace.name ?? String(workspace.idx),
                monitor: monitor,
                monitorId: monitor?.id ?? -1,
                active: !!workspace.is_active,
                focused: !!workspace.is_focused,
                urgent: !!workspace.is_urgent,
                special: false,
                toplevels: [],
                windowCount: 0,
                raw: workspace
            };
        });
        const workspacesById = new Map(workspaces.map(workspace => [workspace.id, workspace]));

        const focusedRawWindow = rawWindows.find(window => window.is_focused) ?? null;

        const toplevels = rawWindows.map(window => {
            const workspace = workspacesById.get(window.workspace_id) ?? null;
            const monitor = workspace?.monitor ?? null;
            const layout = window.layout ?? {};
            const client = {
                id: window.id,
                address: String(window.id),
                title: window.title ?? "",
                appId: window.app_id ?? "",
                initialAppId: window.app_id ?? "",
                initialTitle: window.title ?? "",
                pid: window.pid ?? -1,
                floating: !!window.is_floating,
                pinned: false,
                fullscreenState: 0,
                xwayland: false,
                mapped: true,
                tags: [],
                position: [0, 0],
                size: layout.window_size ?? [0, 0],
                layout: layout,
                workspace: workspace,
                monitor: monitor,
                wayland: null,
                raw: window
            };
            if (workspace)
                workspace.toplevels.push(client);
            return client;
        });

        for (const workspace of workspaces)
            workspace.windowCount = workspace.toplevels.length;

        for (const toplevel of toplevels) {
            const layout = toplevel.layout;
            if (Array.isArray(layout.tile_pos_in_workspace_view)) {
                toplevel.position = layout.tile_pos_in_workspace_view;
                continue;
            }

            if (!focusedRawWindow || toplevel.workspace !== workspacesById.get(focusedRawWindow.workspace_id) || !Array.isArray(layout.pos_in_scrolling_layout) || !Array.isArray(focusedRawWindow.layout?.pos_in_scrolling_layout) || !Array.isArray(layout.window_size))
                continue;

            const focusedSize = focusedRawWindow.layout.window_size ?? [0, 0];
            const columnOffset = layout.pos_in_scrolling_layout[0] - focusedRawWindow.layout.pos_in_scrolling_layout[0];
            const rowOffset = layout.pos_in_scrolling_layout[1] - focusedRawWindow.layout.pos_in_scrolling_layout[1];
            const screenWidth = toplevel.monitor?.width ?? 0;
            const focusedX = focusedSize[0] < screenWidth ? Math.max(0, screenWidth - focusedSize[0]) : 0;
            toplevel.position = [focusedX + columnOffset * layout.window_size[0], rowOffset * layout.window_size[1]];
        }

        for (const monitor of monitors) {
            monitor.activeWorkspace = workspaces.find(workspace => workspace.monitorId === monitor.id && workspace.active) ?? workspaces.find(workspace => workspace.monitorId === monitor.id) ?? null;
            monitor.toplevels = monitor.activeWorkspace?.toplevels ?? [];
            monitor.windowCount = workspaces.filter(workspace => workspace.monitorId === monitor.id).reduce((count, workspace) => count + workspace.windowCount, 0);
        }

        _focusedWorkspace = workspaces.find(workspace => workspace.focused) ?? workspaces.find(workspace => workspace.monitor?.focused) ?? workspaces[0] ?? null;
        _focusedMonitor = _focusedWorkspace?.monitor ?? monitors.find(monitor => monitor.focused) ?? monitors[0] ?? null;
        _activeToplevel = focusedRawWindow ? (toplevels.find(toplevel => toplevel.id === focusedRawWindow.id && toplevel.workspace === _focusedWorkspace) ?? null) : null;
        _monitors = monitors;
        _workspaces = workspaces;
        _toplevels = toplevels;
    }

    Component.onCompleted: {
        refreshAll();
        refreshLeds();
    }

    onAvailableChanged: {
        if (available)
            refreshAll();
    }

    Timer {
        id: refreshTimer

        interval: 50
        onTriggered: root.refreshAll()
    }

    Timer {
        id: reconnectTimer

        interval: 1000
        onTriggered: eventSocket.connected = true
    }

    Timer {
        interval: 750
        running: root.available
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshLeds()
    }

    Socket {
        id: eventSocket

        path: root.socketPath
        connected: root.available
        parser: SplitParser {
            onRead: data => root.handleEventLine(data)
        }

        onConnectionStateChanged: {
            if (connected) {
                write("\"EventStream\"\n");
                flush();
            } else if (root.available) {
                reconnectTimer.restart();
            }
        }
    }

    Process {
        id: workspacesProc

        command: ["niri", "msg", "--json", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed))
                        root._rawWorkspaces = parsed;
                } catch (e) {}
                root.rebuild();
            }
        }
    }

    Process {
        id: windowsProc

        command: ["niri", "msg", "--json", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed))
                        root._rawWindows = parsed;
                } catch (e) {}
                root.rebuild();
            }
        }
    }

    Process {
        id: outputsProc

        command: ["niri", "msg", "--json", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root._outputs = Object.values(parsed);
                } catch (e) {}
                root.rebuild();
            }
        }
    }

    Process {
        id: kbLayoutsProc

        command: ["niri", "msg", "--json", "keyboard-layouts"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root._kbNames = parsed.names ?? [];
                    root._kbIndex = parsed.current_idx ?? 0;
                } catch (e) {}
            }
        }
    }

    Process {
        id: overviewProc

        command: ["niri", "msg", "--json", "overview-state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.inOverview = !!parsed.is_open;
                } catch (e) {}
            }
        }
    }

    Process {
        id: ledProc

        command: ["sh", "-c", "c=0; n=0; for f in /sys/class/leds/*capslock*/brightness; do [ -e \"$f\" ] && c=$(cat \"$f\"); done; for f in /sys/class/leds/*numlock*/brightness; do [ -e \"$f\" ] && n=$(cat \"$f\"); done; echo \"$c $n\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                root.capsLock = parts[0] === "1";
                root.numLock = parts[1] === "1";
            }
        }
    }
}
