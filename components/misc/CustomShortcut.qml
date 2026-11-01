pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config

QtObject {
    id: root

    property string appid: "caelestia"
    property string name
    property string description

    signal pressed
    signal released

    readonly property bool enabled: GlobalConfig.general.windowManager === WindowManager.Hyprland

    readonly property LazyLoader loader: LazyLoader {
        active: root.enabled

        component: Component {
            GlobalShortcut {
                appid: root.appid
                name: root.name
                description: root.description

                onPressed: root.pressed()
                onReleased: root.released()
            }
        }
    }
}
