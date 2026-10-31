import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

FloatingWindow {
    id: importModal

    property string ics: ""
    property string fileName: ""
    property string method: ""
    property var items: []
    property bool loading: false
    property bool importing: false
    property string errorText: ""
    property int calendarIndex: 0
    property int previewGeneration: 0
    property bool previewReady: false
    readonly property bool schedulingOnly: method === "CANCEL" || method === "REPLY"
    readonly property var calendarLabels: writable.map((c, i) => {
        const account = DankCalService.accountById(c.accountId);
        return c.name + " · " + (account ? account.displayName : c.id) + " (" + (i + 1) + ")";
    })
    onTargetCalendarChanged: {
        if (visible && !importing)
            schedulePreview();
    }

    readonly property var writable: DankCalService.writableCalendars()
    readonly property bool noWritableCalendars: writable.length === 0
    readonly property var pendingItems: items.filter(item => !item.existing)
    readonly property var targetCalendar: writable.length > 0 ? writable[Math.min(calendarIndex, writable.length - 1)] : null

    signal openEventRequested(var event)
    signal addCalendarRequested

    function show(data, name) {
        ics = data;
        fileName = name || "";
        method = "";
        items = [];
        errorText = "";
        importing = false;
        loading = true;
        calendarIndex = _defaultCalendarIndex();
        visible = true;
        refreshPreview();
    }

    function schedulePreview() {
        ++previewGeneration;
        previewReady = false;
        loading = true;
        previewTimer.restart();
    }

    function refreshPreview() {
        if (!visible || importing)
            return;
        const generation = ++previewGeneration;
        loading = true;
        previewReady = false;
        DankCalService.parseIcs(ics, targetCalendar ? targetCalendar.id : "", response => {
            if (generation !== previewGeneration || !visible)
                return;
            loading = false;
            if (response.error) {
                errorText = response.error;
                return;
            }
            const result = response.result || {};
            previewReady = true;
            method = result.method || "";
            items = (result.events || []).map(entry => ({
                        "event": DankCalService.eventFromResult(entry.event),
                        "conflicts": (entry.conflicts || []).map(event => DankCalService.eventFromResult(event)),
                        "previewEnd": entry.previewEnd,
                        "conflictCount": entry.conflictCount || 0,
                        "existing": entry.existing ? DankCalService.eventFromResult(entry.existing) : null
                    }));
        });
    }

    function hide() {
        if (importing)
            return;
        ++previewGeneration;
        visible = false;
    }

    onClosed: hide()

    function _defaultCalendarIndex() {
        const preferred = DankCalService.defaultCalendar();
        if (!preferred)
            return 0;
        for (let i = 0; i < writable.length; i++) {
            if (writable[i].id === preferred.id)
                return i;
        }
        return 0;
    }

    function importPending() {
        if (importing || loading || !previewReady || schedulingOnly || !targetCalendar || pendingItems.length === 0)
            return;
        importing = true;
        errorText = "";
        DankCalService.importIcs(ics, targetCalendar.id, pendingItems.map(item => item.event.uid), response => {
            importing = false;
            if (response.error) {
                errorText = response.error;
                refreshPreview();
                return;
            }
            const imported = ((response.result || {}).events || []).filter(entry => !entry.existing);
            hide();
            if (imported.length === 1)
                openEventRequested(DankCalService.eventFromResult(imported[0].event));
        });
    }

    function openExisting(event) {
        hide();
        openEventRequested(event);
    }

    function kindLabel() {
        switch (method) {
        case "REQUEST":
            return I18n.tr("Meeting invitation", "import dialog subtitle for an iCalendar REQUEST");
        case "CANCEL":
            return I18n.tr("Meeting cancellation", "import dialog subtitle for an iCalendar CANCEL");
        case "REPLY":
            return I18n.tr("Meeting reply", "import dialog subtitle for an iCalendar REPLY");
        default:
            return I18n.tr("Calendar file", "import dialog subtitle for a plain iCalendar file");
        }
    }

    function subtitle() {
        if (fileName === "")
            return kindLabel();
        return kindLabel() + " · " + fileName;
    }

    function timeLabel(ev) {
        if (!ev.start)
            return "";
        const day = SettingsData.formatDate(ev.start, "dddd, MMM d, yyyy");
        if (ev.allDay)
            return I18n.tr("%1 · All day", "event details time label for all-day events").arg(day);
        return day + " · " + SettingsData.formatTime(ev.start) + " – " + (SettingsData.formatDate(ev.start, "yyyy-MM-dd") === SettingsData.formatDate(ev.end, "yyyy-MM-dd") ? SettingsData.formatTime(ev.end) : SettingsData.formatDate(ev.end, "MMM d, yyyy") + " " + SettingsData.formatTime(ev.end));
    }

    function organizerLabel(ev) {
        if (!ev.organizer)
            return "";
        const who = ev.organizer.displayName || ev.organizer.email || "";
        if (who === "")
            return "";
        return I18n.tr("Organized by %1", "import row line naming the meeting organizer").arg(who);
    }

    function importLabel() {
        if (importing)
            return I18n.tr("Importing...", "import dialog button while the import runs");
        if (pendingItems.length > 1)
            return I18n.tr("Import %1 events", "import dialog button naming how many events will be imported").arg(pendingItems.length);
        return I18n.tr("Import", "import dialog button to import the events");
    }

    function statusText() {
        if (loading)
            return I18n.tr("Reading file...", "import dialog status while parsing");
        if (items.length > 0 && pendingItems.length === 0)
            return I18n.tr("Everything in this file is already on your calendar.", "import dialog status when no event is new");
        return "";
    }

    Timer {
        id: previewTimer
        interval: 100
        onTriggered: importModal.refreshPreview()
    }

    Connections {
        target: DankCalService
        function onEventsUpdated() {
            if (importModal.visible && !importModal.importing)
                importModal.schedulePreview();
        }
    }

    readonly property real chromeHeight: header.height + footer.height + Theme.spacingL * 2
    readonly property real contentNaturalHeight: contentColumn.implicitHeight

    title: I18n.tr("Import events", "import modal window title")
    minimumSize: Qt.size(460, 360)
    implicitWidth: Math.max(minimumSize.width, Theme.modalWidth(parentWindow, screen, 560))
    implicitHeight: Math.max(minimumSize.height, Theme.modalHeight(parentWindow, screen, Math.max(420, chromeHeight + contentNaturalHeight)))
    color: Theme.windowSurface
    surfaceFormat.opaque: false
    visible: false

    WindowBlur {
        targetWindow: importModal
        blurEnabled: Theme.translucentWindows
        blurWidth: importModal.width
        blurHeight: importModal.height
    }

    Column {
        anchors.fill: parent
        spacing: 0

        LayoutMirroring.enabled: I18n.isRtl
        LayoutMirroring.childrenInherit: true

        DWindowHeader {
            id: header
            width: parent.width
            z: 10
            controls: windowControls
            title: I18n.tr("Import events", "import modal header")
            onCloseRequested: importModal.hide()
        }

        Item {
            width: parent.width
            height: parent.height - header.height - footer.height

            DFlickable {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                clip: true
                contentWidth: width
                contentHeight: contentColumn.implicitHeight

                Column {
                    id: contentColumn
                    width: parent.width
                    spacing: Theme.spacingM

                    StyledText {
                        width: parent.width
                        text: importModal.subtitle()
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        elide: Text.ElideMiddle
                    }

                    StyledText {
                        width: parent.width
                        text: importModal.statusText()
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        visible: text !== ""
                    }

                    StyledText {
                        text: I18n.tr("Add to calendar", "import destination label")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                    DDropdown {
                        width: parent.width
                        visible: !importModal.noWritableCalendars
                        enabled: !importModal.importing
                        options: importModal.calendarLabels
                        currentValue: importModal.calendarLabels[importModal.calendarIndex] || ""
                        onValueChanged: value => {
                            const index = importModal.calendarLabels.indexOf(value);
                            if (index >= 0) {
                                if (index !== importModal.calendarIndex) {
                                    importModal.previewReady = false;
                                    importModal.calendarIndex = index;
                                }
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: importModal.errorText
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Theme.error
                        visible: text !== ""
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.tr("Open the existing meeting to handle this reply or cancellation.", "scheduling messages cannot be imported as new events")
                        wrapMode: Text.WordWrap
                        visible: importModal.schedulingOnly
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.tr("Conflicts use events currently synced to Dux Calendar. You can still import an overlapping event.", "import preview explains the data and non-blocking conflicts")
                        wrapMode: Text.WordWrap
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Repeater {
                        model: importModal.items

                        StyledRect {
                            id: row
                            required property var modelData

                            readonly property var event: modelData.event
                            readonly property var existing: modelData.existing

                            width: parent.width
                            height: rowColumn.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadiusM
                            color: Theme.surfaceContainerLow

                            Rectangle {
                                width: Theme.spacingXS
                                radius: Theme.cornerRadiusXXS
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingS
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: Theme.spacingM
                                anchors.bottomMargin: Theme.spacingM
                                color: row.existing ? row.existing.color : Theme.primary
                            }

                            Column {
                                id: rowColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: Theme.spacingM + Theme.spacingS + Theme.spacingXS
                                anchors.rightMargin: Theme.spacingM
                                anchors.topMargin: Theme.spacingM
                                spacing: Theme.spacingXS

                                StyledText {
                                    width: parent.width
                                    textFormat: Text.PlainText
                                    text: row.event.title
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    text: importModal.timeLabel(row.event)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    textFormat: Text.PlainText
                                    text: row.event.location
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }

                                StyledText {
                                    width: parent.width
                                    text: importModal.organizerLabel(row.event)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }

                                StyledText {
                                    width: parent.width
                                    text: row.modelData.conflictCount > 0 ? (row.modelData.conflictCount === 1 ? I18n.tr("1 overlapping event", "import single conflict count") : I18n.tr("%1 overlapping events", "import conflict count").arg(row.modelData.conflictCount)) : I18n.tr("No overlapping busy events", "import preview with no time conflicts")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: row.modelData.conflictCount > 0 ? Theme.warning : Theme.surfaceVariantText
                                    visible: !importModal.loading && !row.existing
                                }

                                Repeater {
                                    model: row.modelData.conflicts.slice(0, 20)
                                    StyledText {
                                        required property var modelData
                                        width: parent.width
                                        text: modelData.title + " · " + modelData.calendar + "\n" + importModal.timeLabel(modelData)
                                        textFormat: Text.PlainText
                                        wrapMode: Text.WordWrap
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    text: I18n.tr("Showing the first 20 overlaps.", "import conflict list limit")
                                    visible: row.modelData.conflictCount > 20
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                StyledText {
                                    width: parent.width
                                    text: I18n.tr("Recurring event · conflicts checked through %1", "bounded recurring import preview").arg(SettingsData.formatDate(new Date(row.modelData.previewEnd), "MMM d, yyyy"))
                                    visible: !!row.event.recurrence && row.event.recurrence.length > 0
                                    wrapMode: Text.WordWrap
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingM
                                    visible: !!row.existing

                                    StyledText {
                                        text: row.existing ? I18n.tr("Already in %1", "import row note naming the calendar that holds this event").arg(row.existing.calendar) : ""
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.warning
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    DButton {
                                        text: I18n.tr("Open", "import row button to open the event already on the calendar")
                                        buttonHeight: Theme.buttonHeightXS
                                        backgroundColor: Theme.secondaryContainer
                                        textColor: Theme.onSecondaryContainer
                                        anchors.verticalCenter: parent.verticalCenter
                                        onClicked: importModal.openExisting(row.existing)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: footer
            width: parent.width
            height: Theme.buttonHeightS + Theme.spacingM * 2

            Rectangle {
                anchors.fill: parent
                color: Theme.floatingWindowPaneSurface
            }

            Row {
                id: actions
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DButton {
                    text: I18n.tr("Cancel", "import dialog button to close without importing")
                    backgroundColor: "transparent"
                    textColor: Theme.primary
                    onClicked: importModal.hide()
                }

                DButton {
                    visible: importModal.noWritableCalendars
                    text: I18n.tr("Add a calendar", "import dialog button to add a calendar when none can hold events")
                    iconName: "add"
                    backgroundColor: Theme.primary
                    textColor: Theme.primaryText
                    onClicked: {
                        importModal.addCalendarRequested();
                    }
                }

                DButton {
                    visible: !importModal.noWritableCalendars
                    text: importModal.importLabel()
                    iconName: "check"
                    busy: importModal.importing
                    backgroundColor: Theme.primary
                    textColor: Theme.primaryText
                    enabled: !importModal.importing && !importModal.loading && importModal.previewReady && !importModal.schedulingOnly && importModal.pendingItems.length > 0
                    onClicked: importModal.importPending()
                }
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: importModal.visible
        onActivated: importModal.hide()
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: importModal
    }
}
