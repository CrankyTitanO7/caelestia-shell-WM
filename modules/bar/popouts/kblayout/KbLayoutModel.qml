pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services

Item {
    id: model

    property alias visibleModel: visibleModel
    property string activeLabel: ""
    property int activeIndex: -1
    property bool _notifiedLimit: false

    function start() {
        _sync();
    }

    function refresh() {
        _notifiedLimit = false;
        _sync();
    }

    function switchTo(idx) {
        Wm.switchKeyboardLayout(idx);
    }

    function _setLayouts(raw) {
        const parts = (Array.isArray(raw) ? raw : String(raw).split(",")).map(s => String(s).trim()).filter(Boolean);
        layoutsModel.clear();

        const seen = new Set();
        let idx = 0;

        for (const p of parts) {
            if (seen.has(p))
                continue;
            seen.add(p);
            layoutsModel.append({
                layoutIndex: idx,
                token: p,
                label: p
            });
            idx++;
        }
    }

    function _sync() {
        _setLayouts(Wm.keyboardLayouts);

        const idx = Wm.activeKeyboardLayoutIndex;
        activeIndex = idx >= 0 && idx < layoutsModel.count ? idx : -1;
        activeLabel = activeIndex >= 0 ? layoutsModel.get(activeIndex).label : "";

        _rebuildVisible();
    }

    function _rebuildVisible() {
        visibleModel.clear();

        let arr = [];
        for (let i = 0; i < layoutsModel.count; i++)
            arr.push(layoutsModel.get(i));

        arr = arr.filter(i => i.layoutIndex !== activeIndex);
        arr.forEach(i => visibleModel.append(i));

        if (!GlobalConfig.utilities.toasts.kbLimit)
            return;

        if (layoutsModel.count > 4)
            Toaster.toast(Tr.tr("Keyboard layout limit"), Tr.tr("XKB supports only 4 layouts at a time"), "warning");
    }

    visible: false

    ListModel {
        id: visibleModel
    }

    ListModel {
        id: layoutsModel
    }

    Connections {
        function onActiveKeyboardLayoutIndexChanged(): void {
            model._sync();
        }

        function onKeyboardLayoutsChanged(): void {
            model._sync();
        }

        target: Wm
    }
}
