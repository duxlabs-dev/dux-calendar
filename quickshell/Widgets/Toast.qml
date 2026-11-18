import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

Item {
    id: root

    z: 1000
    visible: bar.opacity > 0

    Rectangle {
        id: bar

        readonly property bool showing: ToastService.active

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacingL + (showing ? 0 : Theme.spacingS)
        height: Theme.fieldHeightLarge
        width: Math.min(parent.width - Theme.spacingL * 2, contentRow.implicitWidth + Theme.spacingL * 2)
        radius: Theme.cornerRadiusXS
        color: Theme.inverseSurface
        opacity: showing ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveFastEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
            }
        }
        Behavior on anchors.bottomMargin {
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
            }
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: Theme.spacingM

            StyledText {
                text: ToastService.message
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.inverseOnSurface
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }

            DButton {
                visible: ToastService.actionLabel !== ""
                text: ToastService.actionLabel
                buttonHeight: Theme.buttonHeightXS
                backgroundColor: "transparent"
                textColor: Theme.inverseOnSurface
                focusPolicy: Qt.NoFocus
                anchors.verticalCenter: parent.verticalCenter
                onClicked: ToastService.runAction()
            }
        }
    }
}
