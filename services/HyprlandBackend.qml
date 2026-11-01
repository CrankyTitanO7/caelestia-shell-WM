import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components.misc

Item {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property bool available: Hyprland.requestSocketPath.length > 0
    readonly property bool usingLua: Hyprland.usingLua
    readonly property alias extras: extras
    readonly property alias options: extras.options

    readonly property var toplevels: _toplevels
    readonly property var workspaces: _workspaces
    readonly property var monitors: _monitors
    readonly property var activeToplevel: _activeToplevel
    readonly property var focusedWorkspace: _focusedWorkspace
    readonly property var focusedMonitor: _focusedMonitor
    readonly property int activeWsId: _focusedWorkspace?.id ?? 1
    readonly property int activeWsIndex: _focusedWorkspace?.index ?? activeWsId

    readonly property var keyboard: extras.devices.keyboards.find(kb => kb.main) ?? null
    readonly property bool capsLock: keyboard?.capsLock ?? false
    readonly property bool numLock: keyboard?.numLock ?? false
    readonly property string defaultKbLayout: keyboard?.layout.split(",")[0] ?? "??"
    readonly property string kbLayoutFull: keyboard?.activeKeymap ?? Tr.trCtx("Unknown", "keyboard layout")
    readonly property var keyboardLayouts: (keyboard?.layout ?? "").split(",").map(layout => layout.trim()).filter(Boolean)
    readonly property int activeKeyboardLayoutIndex: keyboard?.lastIpcObject?.active_layout_index ?? -1

    readonly property real borderWidth: extras.options["general:border_size"] ?? 1
    readonly property real borderRounding: extras.options["decoration:rounding"] ?? 0

    property string lastSpecialWorkspace: ""
    property bool inOverview: false

    property var _toplevels: []
    property var _workspaces: []
    property var _monitors: []
    property var _activeToplevel: null
    property var _focusedWorkspace: null
    property var _focusedMonitor: null
    property var _cursorCallback: null

    signal configReloaded

    function dispatch(request: string): void {
        Hyprland.dispatch(request);
    }

    function focusWorkspace(ws: var): void {
        if (ws === undefined || ws === null)
            return;

        const reference = typeof ws === "object" ? (ws.special || ws.name?.startsWith("special:") ? ws.name : ws.id) : ws;
        dispatch(usingLua ? `hl.dsp.focus({ workspace = "${reference}" })` : `workspace ${reference}`);
    }

    function focusRelativeWorkspace(direction: string): void {
        const relative = direction === "up" || direction === "prev" || direction === -1 ? "-" : "+";
        dispatch(usingLua ? `hl.dsp.focus({ workspace = "r${relative}1" })` : `workspace r${relative}1`);
    }

    function toggleSpecialWorkspace(name: string): void {
        dispatch(usingLua ? `hl.dsp.workspace.toggle_special("${name}")` : `togglespecialworkspace ${name}`);
    }

    function cycleSpecialWorkspace(direction: string): void {
        const openSpecials = _workspaces.filter(workspace => workspace.special && workspace.windowCount > 0);
        if (openSpecials.length === 0)
            return;

        const activeSpecial = _focusedMonitor?.specialWorkspace?.name ?? "";
        if (!activeSpecial) {
            if (lastSpecialWorkspace) {
                const workspace = _workspaces.find(workspace => workspace.name === lastSpecialWorkspace);
                if (workspace && workspace.windowCount > 0) {
                    focusWorkspace(workspace);
                    return;
                }
            }
            focusWorkspace(openSpecials[0]);
            return;
        }

        const currentIndex = openSpecials.findIndex(workspace => workspace.name === activeSpecial);
        let nextIndex = 0;
        if (currentIndex !== -1)
            nextIndex = direction === "next" ? (currentIndex + 1) % openSpecials.length : (currentIndex - 1 + openSpecials.length) % openSpecials.length;

        focusWorkspace(openSpecials[nextIndex]);
    }

    function moveWindowToWorkspace(window: var, ws: var, follow = true): void {
        if (!window)
            return;

        const reference = typeof ws === "object" ? (ws.special ? ws.name : ws.id) : ws;
        const address = `address:0x${window.id}`;
        dispatch(usingLua ? `hl.dsp.window.move({ window = "${address}", workspace = "${reference}", follow = ${follow} })` : `movetoworkspace ${reference},${address}`);
    }

    function toggleFloating(window: var): void {
        if (!window)
            return;
        dispatch(usingLua ? `hl.dsp.window.float({ window = "address:0x${window.id}" })` : `togglefloating address:0x${window.id}`);
    }

    function togglePinned(window: var): void {
        if (!window)
            return;
        dispatch(usingLua ? `hl.dsp.window.pin({ window = "address:0x${window.id}" })` : `pin address:0x${window.id}`);
    }

    function closeWindow(window: var): void {
        if (!window)
            return;
        dispatch(usingLua ? `hl.dsp.window.kill({ window = "address:0x${window.id}" })` : `killwindow address:0x${window.id}`);
    }

    function focusWindow(window: var): void {
        if (!window)
            return;
        dispatch(usingLua ? `hl.dsp.window.focus({ window = "address:0x${window.id}" })` : `focuswindow address:0x${window.id}`);
    }

    function setDpms(enabled: bool): void {
        dispatch(usingLua ? `hl.dsp.dpms({ action = "${enabled ? "enable" : "disable"}" })` : (enabled ? "dpms on" : "dpms off"));
    }

    function switchKeyboardLayout(index: int): void {
        switchProc.command = ["hyprctl", "switchxkblayout", "all", String(index)];
        switchProc.running = true;
    }

    function reloadConfig(): void {
        extras.message("reload");
    }

    function refreshDevices(): void {
        extras.refreshDevices();
    }

    function queryCursorPosition(callback: var): void {
        _cursorCallback = callback;
        cursorProc.running = true;
    }

    function monitorNames(): var {
        return _monitors.map(monitor => monitor.name);
    }

    function monitorFor(screen: var): var {
        const raw = Hyprland.monitorFor(screen);
        return _monitors.find(monitor => monitor.raw === raw) ?? _monitors.find(monitor => monitor.name === screen?.name) ?? null;
    }

    function trimWsName(name: string): string {
        return name.startsWith("special:") ? name.slice("special:".length) : name;
    }

    function toplevelsForWs(ws: var, ignoredTags = []): var {
        const workspace = typeof ws === "object" ? ws : (workspaceForId(ws) ?? workspaceForIndex(ws));
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

    function rebuild(): void {
        const rawToplevels = Hyprland.toplevels.values;
        const rawWorkspaces = Hyprland.workspaces.values;
        const rawMonitors = Hyprland.monitors.values;

        const monitors = rawMonitors.map(monitor => ({
            id: monitor.id,
            name: monitor.name,
            description: monitor.description,
            x: monitor.x,
            y: monitor.y,
            width: monitor.width,
            height: monitor.height,
            scale: monitor.scale,
            focused: monitor.focused,
            activeWorkspace: null,
            specialWorkspace: null,
            toplevels: [],
            windowCount: 0,
            raw: monitor
        }));
        const monitorsById = new Map(monitors.map(monitor => [monitor.id, monitor]));

        const workspaces = rawWorkspaces.map(workspace => {
            const monitor = monitorsById.get(workspace.monitor?.id) ?? null;
            return {
                id: workspace.id,
                index: workspace.id,
                name: workspace.name,
                monitor: monitor,
                monitorId: monitor?.id ?? -1,
                active: workspace.active,
                focused: workspace.focused,
                urgent: workspace.urgent,
                special: workspace.name.startsWith("special:"),
                toplevels: [],
                windowCount: workspace.lastIpcObject?.windows ?? 0,
                raw: workspace
            };
        });
        const workspacesById = new Map(workspaces.map(workspace => [workspace.id, workspace]));

        const toplevels = rawToplevels.map(toplevel => {
            const workspace = workspacesById.get(toplevel.workspace?.id) ?? null;
            const monitor = monitorsById.get(toplevel.monitor?.id) ?? null;
            const ipc = toplevel.lastIpcObject ?? {};
            const client = {
                id: toplevel.address,
                address: toplevel.address ? `0x${toplevel.address}` : "",
                title: toplevel.title,
                appId: ipc.class ?? "",
                initialAppId: ipc.initialClass ?? "",
                initialTitle: ipc.initialTitle ?? "",
                pid: ipc.pid ?? -1,
                floating: !!ipc.floating,
                pinned: !!ipc.pinned,
                fullscreenState: ipc.fullscreen ?? 0,
                xwayland: !!ipc.xwayland,
                mapped: ipc.mapped ?? true,
                tags: ipc.tags ?? [],
                position: ipc.at ?? [0, 0],
                size: ipc.size ?? [0, 0],
                workspace: workspace,
                monitor: monitor,
                wayland: toplevel.wayland,
                raw: toplevel
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
            monitor.activeWorkspace = workspacesById.get(monitor.raw.activeWorkspace?.id) ?? null;
            const special = monitor.raw.lastIpcObject?.specialWorkspace;
            monitor.specialWorkspace = special?.name ? (workspacesById.get(special.id) ?? null) : null;
            monitor.windowCount = monitor.toplevels.length;
        }

        const rawFocusedWorkspace = Hyprland.focusedWorkspace;
        const rawFocusedMonitor = Hyprland.focusedMonitor;
        const rawActiveToplevel = Hyprland.activeToplevel;

        _focusedWorkspace = workspacesById.get(rawFocusedWorkspace?.id) ?? null;
        _focusedMonitor = monitorsById.get(rawFocusedMonitor?.id) ?? null;
        _activeToplevel = rawActiveToplevel ? (toplevels.find(toplevel => toplevel.id === rawActiveToplevel.address) ?? null) : null;
        if (_activeToplevel && !_activeToplevel.workspace?.special && (_focusedWorkspace?.toplevels.length ?? 0) === 0)
            _activeToplevel = null;

        _monitors = monitors;
        _workspaces = workspaces;
        _toplevels = toplevels;

        const specialName = _focusedMonitor?.specialWorkspace?.name;
        if (specialName?.startsWith("special:"))
            lastSpecialWorkspace = specialName;
    }

    function reloadDynamicConfs(): void {
        if (usingLua) {
            extras.batchMessage(['eval hl.bind("Caps_Lock", hl.dsp.global("caelestia:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })', 'eval hl.bind("Num_Lock", hl.dsp.global("caelestia:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })', 'eval hl.bind("code:66", hl.dsp.global("caelestia:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })']);
        } else {
            extras.batchMessage(["keyword bindlni ,Caps_Lock,global,caelestia:refreshDevices", "keyword bindlni ,Num_Lock,global,caelestia:refreshDevices", "keyword bindlni ,code:66,global,caelestia:refreshDevices"]);
        }
    }

    Component.onCompleted: {
        rebuild();
        reloadDynamicConfs();
    }

    onUsingLuaChanged: reloadDynamicConfs()

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            const name = event.name;
            if (name.endsWith("v2"))
                return;

            if (name === "configreloaded") {
                root.configReloaded();
                root.reloadDynamicConfs();
            } else if (["workspace", "moveworkspace", "activespecial", "focusedmon"].includes(name)) {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            } else if (["openwindow", "closewindow", "movewindow"].includes(name)) {
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
            } else if (name.includes("mon")) {
                Hyprland.refreshMonitors();
            } else if (name.includes("workspace")) {
                Hyprland.refreshWorkspaces();
            } else if (name.includes("window") || name.includes("group") || ["pin", "fullscreen", "changefloatingmode", "minimize"].includes(name)) {
                Hyprland.refreshToplevels();
            }

            root.rebuild();
        }

        target: Hyprland
    }

    Connections {
        function onValuesChanged(): void {
            root.rebuild();
        }

        target: Hyprland.toplevels
    }

    Connections {
        function onValuesChanged(): void {
            root.rebuild();
        }

        target: Hyprland.workspaces
    }

    Connections {
        function onValuesChanged(): void {
            root.rebuild();
        }

        target: Hyprland.monitors
    }

    Connections {
        function onLastIpcObjectChanged(): void {
            const name = Hyprland.focusedMonitor?.lastIpcObject?.specialWorkspace?.name;
            if (name?.startsWith("special:"))
                root.lastSpecialWorkspace = name;
        }

        target: Hyprland.focusedMonitor
    }

    Process {
        id: switchProc

        command: ["hyprctl", "switchxkblayout", "all", "0"]
    }

    Process {
        id: cursorProc

        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let position = null;
                try {
                    const parsed = JSON.parse(text);
                    if (typeof parsed.x === "number" && typeof parsed.y === "number")
                        position = {
                            x: parsed.x,
                            y: parsed.y
                        };
                } catch (e) {}

                const callback = root._cursorCallback;
                root._cursorCallback = null;
                if (callback)
                    callback(position);
            }
        }
    }

    IpcHandler {
        function refreshDevices(): void {
            root.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return root.workspaces.filter(workspace => workspace.special && workspace.windowCount > 0).map(workspace => workspace.name).join("\n");
        }

        target: "hypr"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "refreshDevices"
        description: "Reload devices"
        onPressed: root.refreshDevices()
        onReleased: root.refreshDevices()
    }

    HyprExtras {
        id: extras

        usingLua: Hyprland.usingLua
    }
}
