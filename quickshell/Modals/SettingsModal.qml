import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

FloatingWindow {
    id: settingsModal

    property int currentTabIndex: 0
    property bool isCompactMode: width < 640
    property bool menuVisible: false

    signal addAccountRequested

    function show() {
        visible = true;
    }

    function hide() {
        visible = false;
    }

    onClosed: hide()

    title: I18n.tr("Calendar Settings", "settings window title")
    minimumSize: Qt.size(520, 420)
    implicitWidth: Math.max(minimumSize.width, Theme.modalWidth(parentWindow, screen, 880))
    implicitHeight: Math.max(minimumSize.height, Theme.modalHeight(parentWindow, screen, 720))
    color: Theme.windowSurface
    surfaceFormat.opaque: false
    visible: false

    WindowBlur {
        targetWindow: settingsModal
        blurEnabled: Theme.translucentWindows
        blurWidth: settingsModal.width
        blurHeight: settingsModal.height
    }

    onIsCompactModeChanged: menuVisible = false

    FocusScope {
        anchors.fill: parent
        focus: true

        LayoutMirroring.enabled: I18n.isRtl
        LayoutMirroring.childrenInherit: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (!sidebar.clearHighlight())
                    settingsModal.hide();
                event.accepted = true;
                return;
            }
            if (contentScope.activeFocus || !sidebar.visible)
                return;
            switch (event.key) {
            case Qt.Key_Down:
            case Qt.Key_J:
                sidebar.moveHighlight(1);
                break;
            case Qt.Key_Up:
            case Qt.Key_K:
                sidebar.moveHighlight(-1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (!sidebar.selectHighlighted())
                    return;
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        Column {
            anchors.fill: parent
            topPadding: header.integrated ? 0 : header.height
            spacing: 0

            Item {
                width: parent.width
                height: parent.height - parent.topPadding
                clip: true

                Rectangle {
                    anchors.fill: sidebar
                    color: SettingsMetrics.sidebarColor
                    visible: sidebar.visible && color.a > 0
                }

                SettingsSidebar {
                    id: sidebar
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: settingsModal.isCompactMode ? parent.width : implicitWidth
                    visible: settingsModal.isCompactMode ? settingsModal.menuVisible : true
                    currentIndex: settingsModal.currentTabIndex
                    onTabSelected: index => {
                        settingsModal.currentTabIndex = index;
                        if (settingsModal.isCompactMode)
                            settingsModal.menuVisible = false;
                    }
                }

                FocusScope {
                    id: contentScope

                    anchors.left: settingsModal.isCompactMode ? (settingsModal.menuVisible ? sidebar.right : parent.left) : sidebar.right
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom

                    Rectangle {
                        anchors.fill: parent
                        color: SettingsMetrics.paneColor

                        Rectangle {
                            anchors.left: parent.left
                            width: Theme.layerOutlineWidth
                            height: parent.height
                            color: Theme.outlineMedium
                            visible: width > 0 && !settingsModal.isCompactMode
                        }
                    }

                    SettingsContent {
                        anchors.fill: parent
                        anchors.leftMargin: SettingsMetrics.panePadding
                        anchors.rightMargin: SettingsMetrics.panePadding
                        currentIndex: settingsModal.currentTabIndex
                        hostWindow: settingsModal
                        windowButtonsReserve: header.ownsPageHeader ? header.buttonsReserve : 0
                        windowDragControls: header.ownsPageHeader ? windowControls : null
                        onAddAccountRequested: settingsModal.addAccountRequested()
                    }
                }
            }
        }

        DWindowHeader {
            id: header

            readonly property bool integrated: !settingsModal.isCompactMode
            readonly property bool ownsPageHeader: integrated && !compositorDecorated

            anchors.right: parent.right
            width: integrated ? buttonsReserve : parent.width
            visible: !integrated || ownsPageHeader
            controls: windowControls
            title: integrated ? "" : I18n.tr("Settings", "settings window header title")
            onCloseRequested: settingsModal.hide()

            DActionButton {
                visible: settingsModal.isCompactMode
                iconName: "menu"
                buttonSize: Theme.buttonHeightXXS
                Accessible.name: I18n.tr("Menu", "settings header button that shows the section list on narrow windows")
                onClicked: settingsModal.menuVisible = !settingsModal.menuVisible
            }
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: settingsModal
    }

    Toast {
        anchors.fill: parent
        z: 102
    }
}
