import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n

Item {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property string socketPath: {
        const explicit = Quickshell.env("UMBRIEL_SOCKET");
        if (explicit)
            return explicit;

        const runtimeDir = Quickshell.env("XDG_RUNTIME_DIR");
        const display = Quickshell.env("WAYLAND_DISPLAY");
        return runtimeDir && display ? `${runtimeDir}/umbriel-${display}.sock` : "";
    }
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
    readonly property real borderWidth: _borderWidth
    readonly property real borderRounding: _borderRounding

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
    property real _borderWidth: 2
    property real _borderRounding: 10

    signal configReloaded

    function action(name: string, args = []): void {
        if (!available)
            return;

        Quickshell.execDetached(["umbriel", "msg", name, ...args.map(arg => String(arg))]);
        refreshTimer.restart();
    }

    function workspaceArgs(ws: var): var {
        let workspace = ws;

        if (typeof workspace === "number")
            workspace = _workspaces.find(candidate => candidate.index === ws && (!_focusedMonitor || candidate.monitorId === _focusedMonitor.id)) ?? _workspaces.find(candidate => candidate.index === ws) ?? ws;

        if (workspace && typeof workspace === "object") {
            const name = workspace.name ?? String(workspace.index);
            const named = workspace.named ?? name !== String(workspace.index);
            const args = named ? ["--name", name] : [String(workspace.index)];
            const output = workspace.monitor?.name ?? workspace.raw?.output;
            if (output)
                args.push("--output", output);
            return args;
        }

        return [String(workspace)];
    }

    function focusWorkspace(ws: var): void {
        if (ws === undefined || ws === null)
            return;
        action("workspace-switch", workspaceArgs(ws));
    }

    function focusRelativeWorkspace(direction: string): void {
        action(direction === "up" || direction === "prev" || direction === -1 ? "workspace-previous" : "workspace-next");
    }

    function toggleSpecialWorkspace(name: string): void {
        // Umbriel has no special workspaces.
    }

    function cycleSpecialWorkspace(direction: string): void {
        // Umbriel has no special workspaces.
    }

    function moveWindowToWorkspace(window: var, ws: var, follow = true): void {
        if (!window || !available)
            return;

        const move = follow ? "window-move-to-workspace" : "window-move-to-workspace-silent";
        const args = workspaceArgs(ws);
        if (window.raw?.active) {
            action(move, args);
            return;
        }

        Quickshell.execDetached(["sh", "-c", `umbriel msg window-focus "$1" && shift && umbriel msg ${move} "$@"`, "sh", String(window.id), ...args.map(arg => String(arg))]);
        refreshTimer.restart();
    }

    function toggleFloating(window: var): void {
        if (!window)
            return;
        action("window-toggle-floating", [window.id]);
    }

    function togglePinned(window: var): void {
        if (!window || !available)
            return;
        Quickshell.execDetached(["sh", "-c", 'umbriel msg window-focus "$1" && umbriel msg window-toggle-pinned', "sh", String(window.id)]);
        refreshTimer.restart();
    }

    function closeWindow(window: var): void {
        if (!window)
            return;
        action("window-close", [window.id]);
    }

    function focusWindow(window: var): void {
        if (!window)
            return;
        action("window-focus", [window.id]);
    }

    function setDpms(enabled: bool): void {
        action(enabled ? "dpms-on" : "dpms-off");
    }

    function switchKeyboardLayout(index: int): void {
        const count = _kbNames.length;
        if (!available || count === 0 || index < 0 || index >= count)
            return;

        const steps = (index - _kbIndex + count) % count;
        if (steps === 0)
            return;

        const commands = Array.from({
            length: steps
        }, () => "umbriel msg keyboard-layout-next").join(" && ");
        Quickshell.execDetached(["sh", "-c", commands]);
        refreshKeyboard();
    }

    function reloadConfig(): void {
        action("config-reload");
        configReloaded();
        refreshAll();
        refreshAppearance();
    }

    function refreshDevices(): void {
        refreshAll();
        refreshKeyboard();
        refreshLeds();
    }

    function queryCursorPosition(callback: var): void {
        callback(null);
    }

    // Umbriel-only actions. These are only reachable through Wm.umbriel while Umbriel is active.
    function toggleOverview(): void {
        action("overview-toggle");
    }

    function maximizeColumn(): void {
        action("window-toggle-maximize");
    }

    function centerWindow(): void {
        action("window-center");
    }

    function toggleFullscreen(): void {
        action("window-toggle-fullscreen");
    }

    function closeFocusedWindow(): void {
        action("window-close");
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
        const targets = monitor ? [monitor] : _monitors;
        return targets.some(target => (target.specialWorkspace ?? target.activeWorkspace)?.toplevels.some(toplevel => toplevel.fullscreenState > 1) ?? false);
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
    }

    function refreshKeyboard(): void {
        if (available && !kbLayoutsProc.running)
            kbLayoutsProc.running = true;
    }

    function refreshAppearance(): void {
        if (!available)
            return;

        if (!borderWidthProc.running)
            borderWidthProc.running = true;
        if (!borderRoundingProc.running)
            borderRoundingProc.running = true;
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

        if (!event?.event)
            return;

        const data = event.data;

        if (event.event === "windows") {
            if (Array.isArray(data)) {
                _rawWindows = data;
                rebuild();
            }
        } else if (event.event === "workspaces") {
            if (Array.isArray(data)) {
                _rawWorkspaces = data;
                rebuild();
            }
        } else if (event.event === "outputs") {
            if (Array.isArray(data)) {
                _outputs = data;
                rebuild();
            }
        } else if (event.event === "keyboard_layout") {
            _kbNames = data?.names ?? _kbNames;
            _kbIndex = data?.current_index ?? _kbIndex;
        } else if (event.event === "overview") {
            inOverview = !!data?.open;
        } else if (event.event === "theme") {
            if (typeof data?.corner_radius === "number")
                _borderRounding = data.corner_radius;
            // The theme event only carries corner_radius; query the rest so an
            // appearance change through `umbriel config` or a reload is picked up.
            refreshAppearance();
        }
    }

    function rebuild(): void {
        const rawWorkspaces = _rawWorkspaces;
        const rawWindows = _rawWindows;
        const rawOutputs = _outputs;

        const focusedRawWorkspace = rawWorkspaces.find(workspace => workspace.focused) ?? rawWorkspaces.find(workspace => workspace.active) ?? null;
        const focusedOutputName = focusedRawWorkspace?.output ?? rawOutputs.find(output => output.focused)?.name ?? rawOutputs[0]?.name ?? "";

        const monitors = rawOutputs.map((output, index) => ({
            id: index,
            name: output.name,
            description: output.description || `${output.make ?? ""} ${output.model ?? ""}`.trim(),
            focused: output.name === focusedOutputName,
            x: output.position?.x ?? 0,
            y: output.position?.y ?? 0,
            width: output.logical_size?.width ?? 0,
            height: output.logical_size?.height ?? 0,
            scale: output.scale ?? 1,
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
                id: workspace.index,
                index: workspace.index,
                name: workspace.name ?? String(workspace.index),
                monitor: monitor,
                monitorId: monitor?.id ?? -1,
                active: !!workspace.active,
                focused: !!workspace.focused,
                urgent: !!workspace.urgent,
                special: false,
                named: !!workspace.named,
                toplevels: [],
                windowCount: 0,
                raw: workspace
            };
        });
        const workspacesByRawId = new Map(workspaces.map(workspace => [String(workspace.raw.id), workspace]));

        const activeRawWindow = rawWindows.find(window => window.active) ?? null;
        // `active` is seat activation, which drops while a shell layer has the
        // keyboard. Fall back to the focused workspace's remembered window.
        const focusedRawWindow = activeRawWindow ?? rawWindows.find(window => window.id === focusedRawWorkspace?.focused_window) ?? null;

        const toplevels = rawWindows.map(window => {
            const workspace = workspacesByRawId.get(String(window.workspace)) ?? null;
            const monitor = monitorsByName.get(window.output) ?? workspace?.monitor ?? null;
            const client = {
                id: window.id,
                address: String(window.id),
                title: window.title ?? "",
                appId: window.app_id ?? "",
                initialAppId: window.app_id ?? "",
                initialTitle: window.title ?? "",
                pid: window.pid ?? -1,
                floating: !!window.floating,
                pinned: !!window.pinned,
                fullscreenState: window.fullscreen ? 2 : 0,
                xwayland: !!window.xwayland,
                mapped: true,
                tags: [],
                position: [window.x ?? 0, window.y ?? 0],
                size: [window.w ?? 0, window.h ?? 0],
                workspace: workspace,
                monitor: monitor,
                wayland: null,
                raw: window
            };
            if (workspace)
                workspace.toplevels.push(client);
            if (monitor)
                monitor.toplevels.push(client);
            return client;
        });

        for (const workspace of workspaces)
            workspace.windowCount = workspace.toplevels.length;

        for (const monitor of monitors) {
            monitor.activeWorkspace = workspaces.find(workspace => String(workspace.raw.id) === String(monitor.raw.active_workspace)) ?? workspaces.find(workspace => workspace.monitorId === monitor.id && workspace.active) ?? workspaces.find(workspace => workspace.monitorId === monitor.id) ?? null;
            monitor.windowCount = monitor.toplevels.length;
        }

        _focusedWorkspace = workspaces.find(workspace => workspace.focused) ?? workspaces.find(workspace => workspace.monitor?.focused && workspace.active) ?? workspaces[0] ?? null;
        _focusedMonitor = _focusedWorkspace?.monitor ?? monitors.find(monitor => monitor.focused) ?? monitors[0] ?? null;
        _activeToplevel = focusedRawWindow ? (toplevels.find(toplevel => toplevel.id === focusedRawWindow.id) ?? null) : null;
        _monitors = monitors;
        _workspaces = workspaces;
        _toplevels = toplevels;
    }

    Component.onCompleted: {
        refreshAll();
        refreshAppearance();
        refreshLeds();
    }

    onAvailableChanged: {
        if (available) {
            refreshAll();
            refreshAppearance();
        }
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
                write('{"cmd":"subscribe","events":["windows","workspaces","outputs","keyboard_layout","overview","theme"]}\n');
                flush();
            } else if (root.available) {
                reconnectTimer.restart();
            }
        }
    }

    Process {
        id: workspacesProc

        command: ["umbriel", "workspaces", "--json"]
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

        command: ["umbriel", "windows", "--json"]
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

        command: ["umbriel", "outputs", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed))
                        root._outputs = parsed;
                } catch (e) {}
                root.rebuild();
            }
        }
    }

    Process {
        id: kbLayoutsProc

        command: ["umbriel", "keyboard-layouts", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root._kbNames = parsed.names ?? [];
                    root._kbIndex = parsed.current_index ?? 0;
                } catch (e) {}
            }
        }
    }

    Process {
        id: borderWidthProc

        command: ["umbriel", "config", "get", "appearance.border_width", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (typeof parsed.value === "number")
                        root._borderWidth = parsed.value;
                } catch (e) {}
            }
        }
    }

    Process {
        id: borderRoundingProc

        command: ["umbriel", "config", "get", "appearance.corner_radius", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (typeof parsed.value === "number")
                        root._borderRounding = parsed.value;
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
