import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

Item {
    id: root

    property int currentIndex: 0
    property int highlightIndex: -1

    signal tabSelected(int index)

    function tabOrder() {
        return groups.reduce((all, group) => all.concat(group.map(tab => tab.index)), []);
    }

    function moveHighlight(delta) {
        const order = tabOrder();
        let position = order.indexOf(highlightIndex);
        if (position < 0)
            position = order.indexOf(currentIndex);
        highlightIndex = order[(position + delta + order.length) % order.length];
    }

    function selectHighlighted() {
        if (highlightIndex < 0)
            return false;
        tabSelected(highlightIndex);
        highlightIndex = -1;
        return true;
    }

    function clearHighlight() {
        if (highlightIndex < 0)
            return false;
        highlightIndex = -1;
        return true;
    }

    readonly property var groups: [[
            {
                accent: "blue",
                index: 0,
                label: I18n.tr("General", "settings sidebar tab label"),
                hint: I18n.tr("Locale, views and defaults", "settings sidebar tab hint"),
                icon: "tune"
            },
            {
                accent: "blue",
                index: 1,
                label: I18n.tr("Appearance", "settings sidebar tab label"),
                hint: I18n.tr("Theme, shape and motion", "settings sidebar tab hint"),
                icon: "palette"
            },
            {
                accent: "blue",
                index: 4,
                label: I18n.tr("Notifications", "settings sidebar tab label"),
                hint: I18n.tr("Reminders and alerts", "settings sidebar tab hint"),
                icon: "notifications"
            }
        ], [
            {
                accent: "green",
                index: 2,
                label: I18n.tr("Calendars", "settings sidebar tab label"),
                hint: I18n.tr("Names, visibility, removal", "settings sidebar tab hint"),
                icon: "calendar_month"
            },
            {
                accent: "green",
                index: 3,
                label: I18n.tr("Accounts", "settings sidebar tab label"),
                hint: I18n.tr("Connected providers", "settings sidebar tab hint"),
                icon: "account_circle"
            }
        ], [
            {
                accent: "purple",
                index: 5,
                label: I18n.tr("About", "settings sidebar tab label"),
                hint: I18n.tr("Version and links", "settings sidebar tab hint"),
                icon: "info"
            }
        ]]

    implicitWidth: SettingsMetrics.sidebarWidth

    DFlickable {
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: navColumn.height

        Column {
            id: navColumn
            width: parent.width
            padding: SettingsMetrics.paneMargin
            spacing: SettingsMetrics.sidebarGroupGap

            Repeater {
                model: root.groups

                Column {
                    id: groupColumn
                    required property var modelData
                    width: navColumn.width - navColumn.padding * 2
                    spacing: Theme.groupedListGap

                    Repeater {
                        model: groupColumn.modelData

                        SettingsSidebarItem {
                            required property var modelData
                            required property int index
                            width: groupColumn.width
                            iconName: modelData.icon
                            title: modelData.label
                            hint: modelData.hint
                            accent: modelData.accent
                            active: root.currentIndex === modelData.index
                            highlighted: root.highlightIndex === modelData.index
                            isFirstInGroup: index === 0
                            isLastInGroup: index === groupColumn.modelData.length - 1
                            onActiveFocusChanged: {
                                if (activeFocus)
                                    root.highlightIndex = modelData.index;
                            }
                            Keys.onReturnPressed: event => event.accepted = root.selectHighlighted()
                            Keys.onEnterPressed: event => event.accepted = root.selectHighlighted()
                            Keys.onSpacePressed: event => event.accepted = root.selectHighlighted()
                            onClicked: {
                                root.highlightIndex = -1;
                                root.tabSelected(modelData.index);
                            }
                        }
                    }
                }
            }
        }
    }
}
