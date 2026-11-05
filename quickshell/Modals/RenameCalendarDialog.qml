import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

DankOverlayDialog {
    id: root

    property var calendar: null
    readonly property bool hasOverride: !!(calendar && calendar.providerName && calendar.name !== calendar.providerName)

    function show(cal) {
        calendar = cal;
        nameField.text = cal.name || "";
        open();
        nameField.forceActiveFocus();
    }

    function useSyncedName() {
        DankCalService.renameCalendar(calendar.id, "");
        close();
    }

    function submit() {
        if (!calendar)
            return;
        const trimmed = nameField.text.trim();
        if (trimmed === "")
            return;
        const next = trimmed === calendar.providerName ? "" : trimmed;
        DankCalService.renameCalendar(calendar.id, next);
        close();
    }

    title: I18n.tr("Rename calendar", "rename calendar dialog header")
    supportingText: hasOverride ? I18n.tr("Synced as \"%1\". The name only changes in Dux Calendar.", "rename calendar dialog note showing provider name").arg(calendar.providerName) : ""
    onAccepted: submit()

    DTextField {
        id: nameField
        width: parent.width
        outlined: true
        labelText: I18n.tr("Calendar name", "rename calendar dialog placeholder for name input")
        onAccepted: root.submit()
        Keys.onReturnPressed: event => event.accepted = true
        Keys.onEnterPressed: event => event.accepted = true
    }

    actions: [
        DButton {
            visible: root.hasOverride
            text: I18n.tr("Use synced name", "rename calendar dialog button to revert to provider name")
            variant: "text"
            onClicked: root.useSyncedName()
        },
        DButton {
            text: I18n.tr("Cancel", "rename calendar dialog button to cancel")
            variant: "tonal"
            onClicked: root.close()
        },
        DButton {
            text: I18n.tr("Save", "rename calendar dialog button to save name")
            onClicked: root.submit()
        }
    ]
}
