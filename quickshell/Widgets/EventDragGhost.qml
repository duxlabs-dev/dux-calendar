import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

Rectangle {
    id: root

    property bool dragging: false
    property var draggedEvent: null
    property point dragPosition: Qt.point(0, 0)
    property var selectedKeys: []
    property string detail: ""

    readonly property int groupCount: draggedEvent && selectedKeys.length > 1 && selectedKeys.indexOf(DankCalService.eventKey(draggedEvent)) !== -1 ? selectedKeys.length : 0

    visible: dragging && draggedEvent !== null
    x: Math.min(parent.width - width - Theme.spacingS, Math.max(Theme.spacingS, dragPosition.x + 12))
    y: Math.min(parent.height - height - Theme.spacingS, Math.max(Theme.spacingS, dragPosition.y + 12))
    width: Math.min(220, dragLabel.implicitWidth + Theme.spacingL * 2)
    height: 34
    radius: Theme.cornerRadiusS
    color: Theme.chipSurface
    border.color: Theme.primary
    border.width: 2
    z: 100

    StyledText {
        id: dragLabel
        anchors.centerIn: parent
        text: {
            if (root.groupCount > 0)
                return I18n.tr("Move %1 events", "event drag preview label; %1 is event count").arg(root.groupCount);
            if (!root.draggedEvent)
                return "";
            return root.detail !== "" ? root.draggedEvent.title + " · " + root.detail : root.draggedEvent.title;
        }
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
        elide: Text.ElideRight
        width: Math.min(196, implicitWidth)
    }
}
