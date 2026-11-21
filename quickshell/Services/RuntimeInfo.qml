pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property string library: value("LIBRARY")
    readonly property string name: library ? "dux-qt-base" : "Quickshell"
    readonly property string version: value("VERSION") || Qt.application.version
    readonly property string revision: value("REVISION")

    function value(field) {
        if (Quickshell.env("QTBASE_RUNTIME_PID") !== String(Quickshell.processId))
            return "";
        return Quickshell.env("QTBASE_RUNTIME_" + field) || "";
    }
}
