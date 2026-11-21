import QtQuick

MouseArea {
    id: root

    property var eventData: null
    property bool dragEnabled: false
    property real dragThreshold: 8
    property real pressX: 0
    property real pressY: 0
    property bool eventDragging: false
    property bool suppressActivation: false

    signal activated(var event, int modifiers)
    signal contextRequested(var event, var anchorItem, real x, real y)
    signal dragPressed
    signal dragStarted(var event, var pointerItem, real x, real y)
    signal dragMoved(var event, var pointerItem, real x, real y)
    signal dropped(var event, var pointerItem, real x, real y)
    signal dragReleased

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: dragEnabled
    hoverEnabled: true
    cursorShape: eventDragging ? Qt.DragMoveCursor : Qt.PointingHandCursor

    onPressed: mouse => {
        if (mouse.button !== Qt.LeftButton || !dragEnabled)
            return;
        pressX = mouse.x;
        pressY = mouse.y;
        suppressActivation = false;
        dragPressed();
    }

    onPositionChanged: mouse => {
        if (!dragEnabled || !(mouse.buttons & Qt.LeftButton))
            return;
        if (!eventDragging) {
            const dx = mouse.x - pressX;
            const dy = mouse.y - pressY;
            if (Math.sqrt(dx * dx + dy * dy) < dragThreshold)
                return;
            eventDragging = true;
            suppressActivation = true;
            dragStarted(eventData, root, mouse.x, mouse.y);
        }
        dragMoved(eventData, root, mouse.x, mouse.y);
    }

    onReleased: mouse => {
        if (eventDragging)
            dropped(eventData, root, mouse.x, mouse.y);
        eventDragging = false;
        dragReleased();
    }

    onCanceled: {
        eventDragging = false;
        suppressActivation = false;
        dragReleased();
    }

    onClicked: mouse => {
        mouse.accepted = true;
        if (suppressActivation) {
            suppressActivation = false;
            return;
        }
        if (mouse.button === Qt.RightButton) {
            contextRequested(eventData, parent, mouse.x, mouse.y);
            return;
        }
        activated(eventData, mouse.modifiers);
    }
}
