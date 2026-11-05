import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

DankOverlayDialog {
    id: root

    property var calendar: null

    property bool ovrEnabled: false
    property bool valEnabled: true
    property bool ovrPersist: false
    property bool valPersist: true
    property bool ovrAllDay: false
    property bool valAllDay: false
    property bool ovrAllDayDays: false
    property int valAllDayDays: 0
    property bool ovrAllDayTime: false
    property string valAllDayTime: "09:00"
    property bool ovrDefault: false
    property int valDefault: 10
    property bool ovrSnooze: false
    property int valSnooze: 5

    readonly property var reminderOptions: [
        {
            label: I18n.tr("None", "default reminder dropdown option"),
            value: -1
        },
        {
            label: I18n.tr("At start", "default reminder dropdown option"),
            value: 0
        },
        {
            label: I18n.tr("5 minutes before", "default reminder dropdown option"),
            value: 5
        },
        {
            label: I18n.tr("10 minutes before", "default reminder dropdown option"),
            value: 10
        },
        {
            label: I18n.tr("15 minutes before", "default reminder dropdown option"),
            value: 15
        },
        {
            label: I18n.tr("30 minutes before", "default reminder dropdown option"),
            value: 30
        },
        {
            label: I18n.tr("1 hour before", "default reminder dropdown option"),
            value: 60
        }
    ]
    readonly property var snoozeOptions: [
        {
            label: I18n.tr("5 minutes", "snooze duration dropdown option"),
            value: 5
        },
        {
            label: I18n.tr("10 minutes", "snooze duration dropdown option"),
            value: 10
        },
        {
            label: I18n.tr("15 minutes", "snooze duration dropdown option"),
            value: 15
        },
        {
            label: I18n.tr("30 minutes", "snooze duration dropdown option"),
            value: 30
        }
    ]
    readonly property var allDayDayOptions: [
        {
            label: I18n.tr("On the day", "all-day reminder day dropdown option"),
            value: 0
        },
        {
            label: I18n.tr("1 day before", "all-day reminder day dropdown option"),
            value: 1
        },
        {
            label: I18n.tr("2 days before", "all-day reminder day dropdown option"),
            value: 2
        },
        {
            label: I18n.tr("1 week before", "all-day reminder day dropdown option"),
            value: 7
        }
    ]

    function optionLabels(options) {
        return options.map(o => o.label);
    }
    function labelForValue(options, value) {
        for (let i = 0; i < options.length; i++) {
            if (options[i].value === value)
                return options[i].label;
        }
        return options[0].label;
    }
    function valueForLabel(options, label) {
        for (let i = 0; i < options.length; i++) {
            if (options[i].label === label)
                return options[i].value;
        }
        return options[0].value;
    }
    function minutesFromClock(text) {
        const parts = (text || "").split(":");
        if (parts.length !== 2)
            return 540;
        const total = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
        return isNaN(total) ? 540 : total;
    }
    function clockFromMinutes(minutes) {
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }

    function show(cal) {
        calendar = cal;
        const o = (cal && cal.reminders) || {};
        ovrEnabled = o.enabled !== undefined;
        valEnabled = ovrEnabled ? o.enabled : SettingsData.remindersEnabled;
        ovrPersist = o.persist !== undefined;
        valPersist = ovrPersist ? o.persist : SettingsData.reminderPersist;
        ovrAllDay = o.allDay !== undefined;
        valAllDay = ovrAllDay ? o.allDay : SettingsData.allDayReminders;
        ovrAllDayDays = o.allDayDaysBefore !== undefined;
        valAllDayDays = ovrAllDayDays ? o.allDayDaysBefore : SettingsData.allDayReminderDaysBefore;
        ovrAllDayTime = o.allDayTime !== undefined;
        valAllDayTime = ovrAllDayTime ? o.allDayTime : SettingsData.allDayReminderTime;
        ovrDefault = o.defaultReminderMinutes !== undefined;
        valDefault = ovrDefault ? o.defaultReminderMinutes : SettingsData.defaultReminderMinutes;
        ovrSnooze = o.snoozeMinutes !== undefined;
        valSnooze = ovrSnooze ? o.snoozeMinutes : SettingsData.snoozeMinutes;
        open();
    }

    function resetToGlobal() {
        if (calendar)
            DankCalService.setCalendarReminders(calendar.id, {});
        close();
    }

    function buildOverrides() {
        const o = {};
        if (ovrEnabled)
            o.enabled = valEnabled;
        if (ovrPersist)
            o.persist = valPersist;
        if (ovrAllDay)
            o.allDay = valAllDay;
        if (ovrAllDayTime)
            o.allDayTime = valAllDayTime;
        if (ovrAllDayDays)
            o.allDayDaysBefore = valAllDayDays;
        if (ovrDefault)
            o.defaultReminderMinutes = valDefault;
        if (ovrSnooze)
            o.snoozeMinutes = valSnooze;
        return o;
    }

    function submit() {
        if (!calendar)
            return;
        DankCalService.setCalendarReminders(calendar.id, buildOverrides());
        close();
    }

    title: I18n.tr("Reminders for \"%1\"", "per-calendar reminders dialog header").arg(calendar ? calendar.name : "")
    supportingText: I18n.tr("Override the global reminder settings for this calendar. Unchanged options follow the global defaults.", "per-calendar reminders dialog subtitle")
    onAccepted: submit()

    component OverrideRow: Column {
        id: orow
        property string label: ""
        property bool overridden: false
        signal overrideChanged(bool on)
        default property alias content: holder.data

        width: parent.width
        spacing: Theme.spacingXS

        Item {
            width: parent.width
            height: Theme.buttonHeightXS

            StyledText {
                anchors.left: parent.left
                anchors.right: overrideRow.left
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                text: orow.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            Row {
                id: overrideRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Override", "per-calendar reminder override toggle label")
                    font.pixelSize: Theme.fontSizeSmall
                    color: orow.overridden ? Theme.primary : Theme.surfaceVariantText
                }

                DToggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: orow.overridden
                    onToggled: checked => orow.overrideChanged(checked)
                }
            }
        }

        Item {
            id: holder
            width: parent.width
            height: childrenRect.height
            enabled: orow.overridden
            opacity: orow.overridden ? 1 : Theme.pendingOpacity
        }
    }

    StyledText {
        visible: !SettingsData.remindersEnabled
        text: I18n.tr("Reminders are disabled globally, so nothing fires until you re-enable them.", "per-calendar reminders dialog note when global reminders are off")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.error
        width: parent.width
        wrapMode: Text.WordWrap
    }

    OverrideRow {
        label: I18n.tr("Enable reminders", "per-calendar enable reminders override label")
        overridden: root.ovrEnabled
        onOverrideChanged: on => root.ovrEnabled = on

        DToggle {
            checked: root.ovrEnabled ? root.valEnabled : SettingsData.remindersEnabled
            enabled: root.ovrEnabled
            onToggled: checked => root.valEnabled = checked
        }
    }

    OverrideRow {
        label: I18n.tr("Keep until dismissed", "per-calendar persist override label")
        overridden: root.ovrPersist
        onOverrideChanged: on => root.ovrPersist = on

        DToggle {
            checked: root.ovrPersist ? root.valPersist : SettingsData.reminderPersist
            enabled: root.ovrPersist
            onToggled: checked => root.valPersist = checked
        }
    }

    OverrideRow {
        label: I18n.tr("Default reminder", "per-calendar default reminder override label")
        overridden: root.ovrDefault
        onOverrideChanged: on => root.ovrDefault = on

        DDropdown {
            dropdownWidth: Theme.fieldDefaultWidth
            options: root.optionLabels(root.reminderOptions)
            currentValue: root.labelForValue(root.reminderOptions, root.ovrDefault ? root.valDefault : SettingsData.defaultReminderMinutes)
            onValueChanged: value => root.valDefault = root.valueForLabel(root.reminderOptions, value)
        }
    }

    OverrideRow {
        label: I18n.tr("Snooze duration", "per-calendar snooze override label")
        overridden: root.ovrSnooze
        onOverrideChanged: on => root.ovrSnooze = on

        DDropdown {
            dropdownWidth: Theme.fieldDefaultWidth
            options: root.optionLabels(root.snoozeOptions)
            currentValue: root.labelForValue(root.snoozeOptions, root.ovrSnooze ? root.valSnooze : SettingsData.snoozeMinutes)
            onValueChanged: value => root.valSnooze = root.valueForLabel(root.snoozeOptions, value)
        }
    }

    OverrideRow {
        label: I18n.tr("Show all-day reminders", "per-calendar all-day reminders override label")
        overridden: root.ovrAllDay
        onOverrideChanged: on => root.ovrAllDay = on

        DToggle {
            checked: root.ovrAllDay ? root.valAllDay : SettingsData.allDayReminders
            enabled: root.ovrAllDay
            onToggled: checked => root.valAllDay = checked
        }
    }

    OverrideRow {
        label: I18n.tr("All-day reminder timing", "per-calendar all-day timing override label")
        overridden: root.ovrAllDayDays || root.ovrAllDayTime
        onOverrideChanged: on => {
            root.ovrAllDayDays = on;
            root.ovrAllDayTime = on;
        }

        Row {
            id: timingRow
            width: parent.width
            spacing: Theme.spacingS

            DDropdown {
                id: allDayDaysDropdown
                dropdownWidth: Theme.fieldDefaultWidth
                options: root.optionLabels(root.allDayDayOptions)
                currentValue: root.labelForValue(root.allDayDayOptions, root.ovrAllDayDays ? root.valAllDayDays : SettingsData.allDayReminderDaysBefore)
                onValueChanged: value => root.valAllDayDays = root.valueForLabel(root.allDayDayOptions, value)
            }

            DankTimeField {
                width: Math.min(Theme.fieldDefaultWidth, timingRow.width - allDayDaysDropdown.width - timingRow.spacing)
                use24Hour: SettingsData.use24HourTime
                minutes: root.minutesFromClock(root.ovrAllDayTime ? root.valAllDayTime : SettingsData.allDayReminderTime)
                onTimeSelected: value => root.valAllDayTime = root.clockFromMinutes(value)
            }
        }
    }

    actions: [
        DButton {
            text: I18n.tr("Reset to global", "per-calendar reminders dialog button to clear overrides")
            variant: "text"
            onClicked: root.resetToGlobal()
        },
        DButton {
            text: I18n.tr("Cancel", "per-calendar reminders dialog button to cancel")
            variant: "tonal"
            onClicked: root.close()
        },
        DButton {
            text: I18n.tr("Save", "per-calendar reminders dialog button to save")
            onClicked: root.submit()
        }
    ]
}
