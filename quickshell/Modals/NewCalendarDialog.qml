import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

DankOverlayDialog {
    id: root

    property var account: null
    property string errorText: ""

    function show(acc) {
        account = acc;
        errorText = "";
        nameField.text = "";
        open();
        nameField.forceActiveFocus();
    }

    function submit() {
        if (!account)
            return;
        const trimmed = nameField.text.trim();
        if (trimmed === "") {
            errorText = I18n.tr("Enter a name for the calendar.", "new calendar dialog validation when the name is empty");
            return;
        }
        DankCalService.createCalendar(account.id, trimmed, response => {
            if (response.error) {
                errorText = response.error;
                return;
            }
            root.close();
        });
    }

    title: I18n.tr("New calendar", "new calendar dialog header")
    supportingText: account ? I18n.tr("Adds a calendar to \"%1\".", "new calendar dialog subtitle naming the local account").arg(DankCalService.accountLabel(account)) : ""
    onAccepted: submit()

    DTextField {
        id: nameField
        width: parent.width
        outlined: true
        labelText: I18n.tr("Calendar name", "new calendar dialog placeholder for name input")
        isError: root.errorText !== ""
        supportingText: root.errorText
        onTextChanged: root.errorText = ""
        onAccepted: root.submit()
        Keys.onReturnPressed: event => event.accepted = true
        Keys.onEnterPressed: event => event.accepted = true
    }

    actions: [
        DButton {
            text: I18n.tr("Cancel", "new calendar dialog button to cancel")
            variant: "tonal"
            onClicked: root.close()
        },
        DButton {
            text: I18n.tr("Create", "new calendar dialog button to create the calendar")
            onClicked: root.submit()
        }
    ]
}
