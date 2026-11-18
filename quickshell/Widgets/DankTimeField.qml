import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

Item {
    id: root

    property int minutes: 600
    property bool use24Hour: false
    property bool endOfDay: false
    property int minimumMinutes: 0
    property int maximumMinutes: 1439
    property string iconName: "schedule"

    signal timeSelected(int value)

    readonly property bool pickerOpen: pickerLoader.item?.opened ?? false

    function openPicker() {
        _commit();
        pickerLoader.active = true;
        const picker = pickerLoader.item;
        picker.hour = Math.floor(minutes / 60) % 24;
        picker.minute = minutes % 60;
        picker.open();
    }

    function formatMinutes(value) {
        if (endOfDay && use24Hour && value === 1440)
            return "24:00";
        const d = new Date(2000, 0, 1, Math.floor(value / 60), value % 60);
        return d.toLocaleTimeString(SettingsData.locale, use24Hour ? "HH:mm" : "h:mm AP");
    }

    function parseTime(text) {
        const t = text.trim().toLowerCase().replace(/\s+/g, " ");
        if (t === "")
            return -1;

        let m = t.match(/^(\d{3,4})\s*(a|am|p|pm)?$/);
        let hours, mins, suffix;
        if (m) {
            hours = parseInt(m[1].slice(0, -2), 10);
            mins = parseInt(m[1].slice(-2), 10);
            suffix = m[2] || "";
        } else {
            m = t.match(/^(\d{1,2})(?:[:.h](\d{1,2}))?\s*(a|am|p|pm)?$/);
            if (!m)
                return -1;
            hours = parseInt(m[1], 10);
            mins = m[2] !== undefined ? parseInt(m[2], 10) : 0;
            suffix = m[3] || "";
        }

        if (mins > 59)
            return -1;
        if (suffix !== "") {
            if (hours < 1 || hours > 12)
                return -1;
            if (suffix.charAt(0) === "p" && hours !== 12)
                hours += 12;
            if (suffix.charAt(0) === "a" && hours === 12)
                hours = 0;
        }
        if (endOfDay && hours === 24 && mins === 0 && suffix === "")
            return 1440;
        if (hours > 23)
            return -1;
        return hours * 60 + mins;
    }

    function _syncText() {
        input.text = formatMinutes(minutes);
    }

    function _commit() {
        const parsed = parseTime(input.text);
        if (parsed < 0) {
            _syncText();
            return;
        }
        selectTime(parsed);
    }

    function selectTime(value) {
        const normalized = endOfDay && value === 0 ? 1440 : value;
        const bounded = Math.max(minimumMinutes, Math.min(maximumMinutes, normalized));
        if (bounded !== minutes)
            timeSelected(bounded);
        _syncText();
    }

    onMinutesChanged: {
        if (!input.activeFocus)
            _syncText();
    }
    onUse24HourChanged: _syncText()
    onEndOfDayChanged: _syncText()
    Component.onCompleted: _syncText()

    height: Theme.fieldHeightLarge
    implicitWidth: timeMetrics.width + Theme.spacingM + Theme.spacingXS * 2 + pickerButton.width

    TextMetrics {
        id: timeMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
        text: root.formatMinutes(0)
    }

    Rectangle {
        id: field

        anchors.fill: parent
        radius: Theme.cornerRadiusXS
        color: Theme.chipSurface
        border.width: input.activeFocus ? Theme.outlineWidthFocused : Theme.outlineWidth
        border.color: (root.pickerOpen || input.activeFocus) ? Theme.primary : Theme.outlineVariant

        TextInput {
            id: input

            anchors.left: parent.left
            anchors.right: pickerButton.left
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            selectionColor: Theme.primarySelected
            selectedTextColor: Theme.surfaceText
            clip: true
            inputMethodHints: Qt.ImhTime
            activeFocusOnTab: true

            onActiveFocusChanged: {
                if (activeFocus) {
                    selectAll();
                    return;
                }
                root._commit();
            }
            Keys.onDownPressed: root.openPicker()
            onAccepted: {
                root._commit();
                focus = false;
            }
            Keys.onEscapePressed: {
                root._syncText();
                focus = false;
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onPressed: mouse => {
                    input.forceActiveFocus();
                    mouse.accepted = false;
                }
            }
        }

        DActionButton {
            id: pickerButton
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            iconName: root.iconName
            iconColor: (root.pickerOpen || input.activeFocus) ? Theme.primary : Theme.surfaceVariantText
            focusPolicy: Qt.NoFocus
            tooltipText: I18n.tr("Pick time", "time field button that opens the clock picker")
            onClicked: root.openPicker()
        }
    }

    Loader {
        id: pickerLoader
        active: false

        sourceComponent: Popup {
            id: pickerPopup
            property alias hour: timePicker.hour
            property alias minute: timePicker.minute

            parent: root.Overlay.overlay
            width: parent?.width ?? 0
            height: parent?.height ?? 0
            padding: 0
            modal: true
            dim: false
            focus: true
            closePolicy: Popup.NoAutoClose
            background: null
            onAboutToShow: timePicker.open()
            onAboutToHide: timePicker.close()
            onClosed: input.forceActiveFocus()

            exit: Transition {
                PauseAnimation {
                    duration: Theme.animationsEnabled ? Theme.expressiveDurations.expressiveEffects : 0
                }
            }

            contentItem: DTimePicker {
                id: timePicker
                focus: true
                is24Hour: root.use24Hour
                onAccepted: (hour, minute) => {
                    root.selectTime(hour * 60 + minute);
                    pickerPopup.close();
                }
                onRejected: pickerPopup.close()
            }
        }
    }
}
