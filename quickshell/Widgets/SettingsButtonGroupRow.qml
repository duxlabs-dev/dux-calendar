import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsRow {
    id: root

    property string text: ""
    property string description: ""
    property alias model: buttonGroup.model
    property alias currentIndex: buttonGroup.currentIndex
    property alias minButtonWidth: buttonGroup.minButtonWidth
    property alias checkEnabled: buttonGroup.checkEnabled

    readonly property bool compact: width - buttonGroup.naturalWidth - SettingsMetrics.rowPaddingH * 2 - SettingsMetrics.rowContentSpacing < SettingsMetrics.buttonGroupCompactThreshold

    signal selectionChanged(int index, bool selected)

    title: text
    subtitle: description
    spacing: Theme.groupedListGap

    Item {
        id: trailingHost
        width: root.compact ? 0 : buttonGroup.width
        height: root.compact ? 0 : buttonGroup.height
        visible: !root.compact
        anchors.verticalCenter: parent.verticalCenter
    }

    body: Item {
        id: bodyHost
        width: parent.width
        height: buttonGroup.height
        visible: root.compact
    }

    DButtonGroup {
        id: buttonGroup
        parent: root.compact ? bodyHost : trailingHost
        x: root.compact ? (parent.width - width) / 2 : 0
        selectionMode: "single"
        size: "small"
        spacing: root.spacing
        enabled: root.enabled
        maximumWidth: root.compact ? root.width - SettingsMetrics.rowPaddingH * 2 : -1
        onSelectionChanged: (index, selected) => root.selectionChanged(index, selected)
    }
}
