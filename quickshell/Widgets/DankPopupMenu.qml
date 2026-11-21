import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

Popup {
    id: root

    // items: [{ id, label, icon, shortcut?, danger?, enabled? }]
    // Non-action rows use { type: "header", label, subtitle? } or
    // { type: "separator" }.
    property var items: []
    property real preferredWidth: 228
    property int currentIndex: -1
    // Context menus dismiss on any outside press; opener-anchored menus keep
    // presses on their anchor item inert so the opener can toggle them.
    property bool dismissOnOutsidePress: false

    signal triggered(string itemId)

    function show(anchorItem, x, y) {
        parent = anchorItem;
        root.x = x;
        root.y = y;
        open();
    }

    function isAction(index) {
        if (index < 0 || index >= items.length)
            return false;
        const item = items[index];
        return (!item.type || item.type === "action") && item.enabled !== false;
    }

    function moveCurrent(direction) {
        if (items.length === 0)
            return;
        let next = currentIndex;
        for (let i = 0; i < items.length; i++) {
            next = (next + direction + items.length) % items.length;
            if (isAction(next)) {
                currentIndex = next;
                return;
            }
        }
    }

    function triggerCurrent() {
        if (!isAction(currentIndex))
            return;
        const itemId = items[currentIndex].id;
        close();
        triggered(itemId);
    }

    width: preferredWidth
    padding: Theme.spacingS
    margins: Theme.spacingS
    // Outside-press dismissal is armed shortly after opening, otherwise the
    // click that opened the menu can immediately close it. Presses inside the
    // anchor item never auto-close, so the opener can toggle deterministically.
    closePolicy: Popup.CloseOnEscape

    focus: true
    onOpened: {
        currentIndex = -1;
        moveCurrent(1);
        menuFocus.forceActiveFocus();
        armCloseTimer.start();
    }
    onClosed: {
        armCloseTimer.stop();
        closePolicy = Popup.CloseOnEscape;
        currentIndex = -1;
    }

    Timer {
        id: armCloseTimer
        interval: Timing.settleShort
        onTriggered: root.closePolicy = Popup.CloseOnEscape | (root.dismissOnOutsidePress ? Popup.CloseOnPressOutside : Popup.CloseOnPressOutsideParent)
    }

    background: Rectangle {
        color: Theme.chipSurface
        radius: Theme.cornerRadiusM
    }

    contentItem: FocusScope {
        id: menuFocus
        implicitWidth: menuColumn.implicitWidth
        implicitHeight: menuColumn.implicitHeight

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Up:
                root.moveCurrent(-1);
                break;
            case Qt.Key_Down:
                root.moveCurrent(1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                root.triggerCurrent();
                break;
            default:
                event.accepted = false;
                return;
            }
            event.accepted = true;
        }

        Column {
            id: menuColumn
            anchors.fill: parent
            spacing: Theme.groupedListGap

            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true

            Repeater {
                model: ScriptModel {
                    values: root.items
                }

                Rectangle {
                    id: menuRow
                    required property var modelData
                    required property int index
                    readonly property string itemType: modelData.type || "action"
                    readonly property bool isAction: itemType === "action"
                    readonly property bool itemEnabled: isAction && modelData.enabled !== false

                    readonly property color contentColor: modelData.danger ? Theme.error : Theme.surfaceText
                    readonly property color supportingColor: modelData.danger ? Theme.error : Theme.surfaceVariantText
                    readonly property bool highlighted: isAction && root.currentIndex === index

                    width: parent.width
                    height: {
                        switch (itemType) {
                        case "separator":
                            return Theme.spacingM + Theme.dividerWidth;
                        case "header":
                            return Theme.listItemHeight;
                        default:
                            return Theme.menuItemHeight;
                        }
                    }
                    radius: Theme.cornerRadiusXS
                    color: highlighted ? Theme.withAlpha(contentColor, Theme.stateLayerFocus) : "transparent"
                    opacity: !isAction || itemEnabled ? 1 : Theme.pendingOpacity

                    Rectangle {
                        visible: menuRow.itemType === "separator"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        height: Theme.dividerWidth
                        color: Theme.outlineVariant
                    }

                    Column {
                        visible: menuRow.itemType === "header"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        spacing: Theme.spacingXXS

                        StyledText {
                            text: menuRow.modelData.label || ""
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                            width: parent.width
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: text !== ""
                            text: menuRow.modelData.subtitle || ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            width: parent.width
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        visible: menuRow.isAction
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingM

                        DIcon {
                            visible: !!menuRow.modelData.icon
                            name: menuRow.modelData.icon || ""
                            size: Theme.iconSizeMedium
                            color: menuRow.supportingColor
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: menuRow.modelData.label
                            font.pixelSize: Theme.fontSizeMedium
                            color: menuRow.contentColor
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - (menuRow.modelData.icon ? Theme.iconSizeMedium + Theme.spacingM : 0) - (shortcutText.visible ? shortcutText.width + Theme.spacingM : 0)
                            elide: Text.ElideRight
                        }

                        StyledText {
                            id: shortcutText
                            visible: text !== ""
                            text: menuRow.modelData.shortcut || ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    StateLayer {
                        visible: menuRow.isAction
                        stateColor: menuRow.contentColor
                        enabled: menuRow.itemEnabled
                        disabled: !menuRow.itemEnabled
                        onClicked: {
                            root.currentIndex = menuRow.index;
                            root.close();
                            root.triggered(menuRow.modelData.id);
                        }
                    }
                }
            }
        }
    }
}
