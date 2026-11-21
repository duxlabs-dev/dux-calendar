import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

Item {
    id: root

    property var controller: null

    signal deleteRequested

    readonly property var actions: [
        {
            id: "copy",
            label: I18n.tr("Copy", "multi-event action shelf label"),
            icon: "content_copy"
        },
        {
            id: "cut",
            label: I18n.tr("Cut", "multi-event action shelf label"),
            icon: "content_cut"
        },
        {
            id: "duplicate",
            label: I18n.tr("Duplicate", "multi-event action shelf duplicate label"),
            icon: "file_copy"
        },
        {
            id: "tomorrow",
            label: I18n.tr("+1 day", "multi-event action shelf repeat tomorrow label"),
            icon: "update"
        },
        {
            id: "week",
            label: I18n.tr("+1 week", "multi-event action shelf repeat next week label"),
            icon: "event_repeat"
        },
        {
            id: "delete",
            label: I18n.tr("Delete", "multi-event action shelf label"),
            icon: "delete_outline",
            danger: true
        },
        {
            id: "clear",
            label: I18n.tr("Clear", "multi-event action shelf clear selection label"),
            icon: "close"
        }
    ]

    function run(actionId) {
        switch (actionId) {
        case "copy":
            controller.copy();
            break;
        case "cut":
            controller.cut();
            break;
        case "duplicate":
            controller.duplicate(0);
            break;
        case "tomorrow":
            controller.duplicate(1);
            break;
        case "week":
            controller.duplicate(7);
            break;
        case "delete":
            deleteRequested();
            break;
        case "clear":
            controller.clear();
            break;
        }
    }

    readonly property bool shown: controller !== null && controller.count > 1

    visible: opacity > 0
    implicitWidth: selectionLabel.width + actionRow.width + Theme.spacingL * 2 + Theme.spacingM
    implicitHeight: Theme.buttonHeightM
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.96

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    StyledRect {
        anchors.fill: parent
        color: Theme.chipSurface
        radius: Theme.cornerRadiusXL
        border.color: Theme.outlineVariant
        border.width: Theme.outlineWidth
    }

    Row {
        anchors.centerIn: parent
        spacing: Theme.spacingM

        Row {
            id: selectionLabel
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DIcon {
                name: "select_all"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: I18n.tr("%1 selected", "multi-event action shelf selection count; %1 is event count").arg(root.controller ? root.controller.count : 0)
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            id: actionRow
            spacing: Theme.spacingXXS

            Repeater {
                model: ScriptModel {
                    values: root.actions
                }

                Item {
                    id: action
                    required property var modelData
                    readonly property color contentColor: modelData.danger ? Theme.error : Theme.surfaceVariantText

                    width: Math.max(Theme.minimumTouchTargetSize, actionLabel.implicitWidth + Theme.spacingS * 2)
                    height: Theme.minimumTouchTargetSize

                    Column {
                        anchors.centerIn: parent
                        spacing: 0

                        DIcon {
                            name: action.modelData.icon
                            size: Theme.iconSizeMedium
                            color: action.contentColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            id: actionLabel
                            text: action.modelData.label
                            font.pixelSize: Theme.fontSizeSmall
                            color: action.contentColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    StateLayer {
                        stateColor: action.contentColor
                        cornerRadius: Theme.cornerRadiusS
                        disabled: root.controller ? root.controller.busy : true
                        onClicked: root.run(action.modelData.id)
                    }
                }
            }
        }
    }
}
