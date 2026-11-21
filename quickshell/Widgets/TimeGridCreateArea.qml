import QtQuick
import qs.Common
import qs.DCommon.Widgets

MouseArea {
    id: root

    required property date day
    required property real startHour
    required property real hourCount
    required property real hourHeight
    property Item flickable: null
    property int slotMinutes: 15
    property real autoScrollEdge: 24
    property real autoScrollStep: 6

    readonly property real slotHeight: hourHeight * slotMinutes / 60
    readonly property int slotCount: Math.ceil(Math.round(hourCount * 60) / slotMinutes)
    readonly property bool selecting: anchorSlot >= 0
    property bool armed: false
    property int anchorSlot: -1
    property int fromSlot: 0
    property int toSlot: 0
    property real pressX: 0
    property real pressY: 0
    property bool panIntent: false
    readonly property int panThreshold: Application.styleHints.startDragDistance
    property real pointerViewportY: 0
    property int autoScrollDirection: 0

    signal createRequested(date start, date end)

    acceptedButtons: Qt.LeftButton
    preventStealing: !panIntent

    function slotAt(y) {
        return Math.max(0, Math.min(slotCount - 1, Math.floor(y / slotHeight)));
    }

    function slotTime(slot) {
        const d = new Date(day);
        const minutes = Math.round(startHour * 60 + Math.min(slot * slotMinutes, hourCount * 60));
        d.setHours(0, minutes, 0, 0);
        return d;
    }

    function updateSelection(y) {
        const slot = slotAt(y);
        fromSlot = Math.min(anchorSlot, slot);
        toSlot = Math.max(anchorSlot, slot) + 1;
    }

    function updateAutoScroll(y) {
        if (!flickable)
            return;
        pointerViewportY = mapToItem(flickable, 0, y).y;
        if (pointerViewportY < autoScrollEdge) {
            autoScrollDirection = -1;
            return;
        }
        if (pointerViewportY > flickable.height - autoScrollEdge) {
            autoScrollDirection = 1;
            return;
        }
        autoScrollDirection = 0;
    }

    function reset() {
        armed = false;
        anchorSlot = -1;
        autoScrollDirection = 0;
        panIntent = false;
    }

    onPressed: mouse => {
        pressX = mouse.x;
        pressY = mouse.y;
        armed = true;
    }

    onPositionChanged: mouse => {
        if (!armed || !(mouse.buttons & Qt.LeftButton))
            return;
        if (!selecting) {
            const dx = Math.abs(mouse.x - pressX);
            const dy = Math.abs(mouse.y - pressY);
            panIntent = dx > dy && dx > panThreshold;
            if (panIntent || dy < slotHeight)
                return;
            anchorSlot = slotAt(pressY);
        }
        updateSelection(mouse.y);
        updateAutoScroll(mouse.y);
    }

    onReleased: {
        if (!selecting) {
            reset();
            return;
        }
        const start = slotTime(fromSlot);
        const end = slotTime(toSlot);
        reset();
        createRequested(start, end);
    }

    onCanceled: reset()

    Shortcut {
        sequence: "Escape"
        enabled: root.selecting
        onActivated: root.reset()
    }

    Timer {
        interval: Timing.cappedTick
        repeat: true
        running: root.selecting && root.autoScrollDirection !== 0 && root.flickable !== null
        onTriggered: {
            const f = root.flickable;
            f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY + root.autoScrollDirection * root.autoScrollStep));
            root.updateSelection(root.mapFromItem(f, 0, root.pointerViewportY).y);
        }
    }

    Rectangle {
        visible: root.selecting
        x: 2
        width: parent.width - 4
        y: root.fromSlot * root.slotHeight
        height: Math.max(0, Math.min(root.toSlot * root.slotHeight, root.height) - y - 2)
        radius: Theme.cornerRadiusS
        color: Theme.withAlpha(Theme.primary, 0.18)
        border.color: Theme.primary
        border.width: 1

        StyledText {
            visible: parent.height >= 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            text: SettingsData.formatTime(root.slotTime(root.fromSlot)) + " – " + SettingsData.formatTime(root.slotTime(root.toSlot))
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.primary
            elide: Text.ElideRight
        }
    }
}
