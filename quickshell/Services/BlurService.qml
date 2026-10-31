pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Singleton {
    id: root

    readonly property var log: Log.scoped("BlurService")

    property bool available: false
    property bool probed: false

    readonly property bool requested: SettingsData.blurEnabled
    readonly property bool enabled: available && requested

    onRequestedChanged: {
        if (requested)
            probe();
    }

    Component.onCompleted: {
        if (requested)
            probe();
    }

    function probe() {
        if (probed || probeProcess.running)
            return;
        probeProcess.running = true;
    }

    function applyVerdict(text) {
        available = text.trim() === "supported";
        probed = true;
    }

    Process {
        id: probeProcess

        command: ["dcal", "blur", "check"]

        stdout: StdioCollector {
            onStreamFinished: root.applyVerdict(text)
        }

        onExited: exitCode => {
            if (exitCode === 0)
                return;
            root.log.warn(`blur probe exited with ${exitCode}`);
            root.applyVerdict("");
        }
    }
}
