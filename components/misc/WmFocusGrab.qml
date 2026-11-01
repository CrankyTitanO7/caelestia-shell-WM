pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

Item {
    id: root

    property bool active
    property var windows: []
    signal cleared

    LazyLoader {
        active: Wm.isHyprland

        component: Component {
            HyprlandFocusGrab {
                active: root.active
                windows: root.windows

                onCleared: root.cleared()
            }
        }
    }
}
