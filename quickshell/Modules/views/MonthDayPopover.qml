import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

Item {
    id: root

    property var events: []
    property date day: new Date()
    property var selectedEventKeys: []

    signal eventClicked(var event, int modifiers)
    signal eventContextRequested(var event, var anchorItem, real x, real y)

    readonly property int rowHeight: 38
    readonly property int headerHeight: 40
    readonly property int maxBodyHeight: 320
    readonly property int popoverWidth: 300

    function isEventSelected(event) {
        return selectedEventKeys.indexOf(DankCalService.eventKey(event)) !== -1;
    }

    function show(forDay, dayEvents, item) {
        if (!item)
            return;

        let contentItem = item.Window?.window?.contentItem;
        if (!contentItem) {
            let current = item;
            while (current) {
                if (current.Window?.window?.contentItem) {
                    contentItem = current.Window.window.contentItem;
                    break;
                }
                current = current.parent;
            }
        }
        if (!contentItem)
            return;

        root.day = forDay;
        root.events = dayEvents;
        popup.parent = contentItem;

        const bodyHeight = Math.min(maxBodyHeight, Math.max(rowHeight, dayEvents.length * rowHeight));
        const popoverHeight = headerHeight + bodyHeight + popup.topPadding + popup.bottomPadding;

        const itemPos = item.mapToItem(contentItem, 0, 0);
        const parentWidth = contentItem.width;
        const parentHeight = contentItem.height;
        const side = _bestSide(itemPos, item, parentWidth, parentHeight, popoverHeight);

        let targetX = 0;
        let targetY = 0;
        switch (side) {
        case "left":
            targetX = itemPos.x - popoverWidth - 8;
            targetY = itemPos.y;
            break;
        case "right":
            targetX = itemPos.x + item.width + 8;
            targetY = itemPos.y;
            break;
        case "top":
            targetX = itemPos.x + (item.width - popoverWidth) / 2;
            targetY = itemPos.y - popoverHeight - 8;
            break;
        case "bottom":
        default:
            targetX = itemPos.x + (item.width - popoverWidth) / 2;
            targetY = itemPos.y + item.height + 8;
            break;
        }

        popup.width = popoverWidth;
        popup.height = popoverHeight;
        popup.x = Math.max(4, Math.min(parentWidth - popoverWidth - 4, targetX));
        popup.y = Math.max(4, Math.min(parentHeight - popoverHeight - 4, targetY));
        popup.open();
    }

    function _bestSide(itemPos, item, parentWidth, parentHeight, popoverHeight) {
        if (parentWidth - (itemPos.x + item.width) >= popoverWidth + 16)
            return "right";
        if (itemPos.x >= popoverWidth + 16)
            return "left";
        if (parentHeight - (itemPos.y + item.height) >= popoverHeight + 16)
            return "bottom";
        return "top";
    }

    function hide() {
        popup.close();
    }

    Popup {
        id: popup

        padding: Theme.spacingS
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside | Popup.CloseOnReleaseOutside
        modal: false
        dim: false

        background: Rectangle {
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadiusM
        }

        contentItem: Column {
            spacing: Theme.spacingXS

            StyledText {
                width: parent.width
                height: root.headerHeight - Theme.spacingXS
                text: SettingsData.formatDate(root.day, "dddd, MMMM d")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                verticalAlignment: Text.AlignVCenter
            }

            DListView {
                width: parent.width
                height: popup.height - root.headerHeight - popup.topPadding - popup.bottomPadding
                clip: true
                spacing: 2
                model: ScriptModel {
                    values: root.events
                }
                delegate: Rectangle {
                    id: eventRow
                    required property var modelData
                    readonly property bool isSelected: root.isEventSelected(modelData)
                    readonly property bool awaitingReply: modelData.myResponse === "needs-action"
                    readonly property bool declined: modelData.myResponse === "declined"
                    width: ListView.view.width
                    height: root.rowHeight - Theme.groupedListGap
                    radius: Theme.cornerRadiusXS
                    opacity: declined && !isSelected ? Theme.pendingOpacity : 1
                    color: isSelected ? Theme.withAlpha(modelData.color, 0.28) : (rowHover.containsMouse ? Theme.withAlpha(modelData.color, 0.18) : "transparent")
                    border.color: isSelected ? Theme.primary : (awaitingReply ? modelData.color : "transparent")
                    border.width: isSelected ? 2 : (awaitingReply ? 1 : 0)

                    TentativeHatch {
                        visible: eventRow.modelData.myResponse === "tentative"
                        stripeColor: eventRow.modelData.color
                    }

                    MergedEventDots {
                        event: eventRow.modelData
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingXS
                        anchors.rightMargin: Theme.spacingXS
                        spacing: Theme.spacingS

                        Rectangle {
                            width: 3
                            height: 22
                            radius: Theme.fullRadius(width, height)
                            color: eventRow.modelData.color
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64
                            text: eventRow.modelData.allDay ? I18n.tr("All day", "all-day marker in the month day-detail popover") : SettingsData.formatTime(eventRow.modelData.start)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            isMonospace: true
                            elide: Text.ElideRight
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 3 - 64 - Theme.spacingS * 2
                            text: eventRow.modelData.title
                            font.pixelSize: Theme.fontSizeSmall
                            font.strikeout: eventRow.declined
                            color: eventRow.declined ? Theme.surfaceVariantText : Theme.surfaceText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                root.eventContextRequested(eventRow.modelData, eventRow, mouse.x, mouse.y);
                                return;
                            }
                            root.eventClicked(eventRow.modelData, mouse.modifiers);
                            if ((mouse.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier)) === 0)
                                popup.close();
                        }
                    }
                }
            }
        }

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.expressiveDurations.expressiveFastEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
            }
        }

        exit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: Theme.expressiveDurations.expressiveFastEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
            }
        }
    }
}
