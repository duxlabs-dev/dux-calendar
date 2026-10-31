import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import "../Common/EventUtils.js" as EventUtils

FloatingWindow {
    id: eventModal

    property var event: ({})
    property bool editMode: false
    property bool createMode: false
    property bool confirmDelete: false
    property bool saving: false
    property string pendingResponse: ""
    property string formError: ""

    readonly property bool noWritableCalendars: DankCalService.writableCalendars().length === 0

    signal addCalendarRequested

    property string formTitle: ""
    property date formStartDate: new Date()
    property date formEndDate: new Date()
    property int formStartMinutes: 600
    property int formEndMinutes: 660
    property string formLocation: ""
    property string formDescription: ""
    property bool formAllDay: false
    property int formCalendarIndex: 0
    property var formReminders: []
    property var recurrencePickerItem: null

    readonly property bool recurrenceEditable: createMode || !(event.recurringId || "")
    readonly property bool isOccurrence: (event.recurringId || "") !== "" && (event.recurrence || []).length > 0
    readonly property bool isRecurring: (event.recurrence || []).length > 0
    readonly property int maxReminders: 5

    readonly property var reminderOptions: [
        {
            label: I18n.tr("None", "event reminder dropdown option"),
            value: -1
        },
        {
            label: I18n.tr("At start", "event reminder dropdown option"),
            value: 0
        },
        {
            label: I18n.tr("5 minutes before", "event reminder dropdown option"),
            value: 5
        },
        {
            label: I18n.tr("10 minutes before", "event reminder dropdown option"),
            value: 10
        },
        {
            label: I18n.tr("15 minutes before", "event reminder dropdown option"),
            value: 15
        },
        {
            label: I18n.tr("30 minutes before", "event reminder dropdown option"),
            value: 30
        },
        {
            label: I18n.tr("1 hour before", "event reminder dropdown option"),
            value: 60
        },
        {
            label: I18n.tr("2 hours before", "event reminder dropdown option"),
            value: 120
        },
        {
            label: I18n.tr("1 day before", "event reminder dropdown option"),
            value: 1440
        },
        {
            label: I18n.tr("2 days before", "event reminder dropdown option"),
            value: 2880
        },
        {
            label: I18n.tr("1 week before", "event reminder dropdown option"),
            value: 10080
        }
    ]
    readonly property bool descriptionIsHtml: /<[a-z][^>]*>/i.test(event.description || "")

    function show(eventData) {
        createMode = false;
        editMode = false;
        confirmDelete = false;
        saving = false;
        pendingResponse = "";
        formError = "";
        event = eventData || {};
        visible = true;
    }

    function _nextHalfHour() {
        const slot = 30 * 60000;
        return new Date(Math.ceil(Date.now() / slot) * slot);
    }

    function _defaultStart(day) {
        if (!day)
            return _nextHalfHour();
        const base = new Date(day);
        if (base.getHours() !== 0 || base.getMinutes() !== 0 || base.getSeconds() !== 0)
            return base;
        const next = _nextHalfHour();
        if (base.getFullYear() === next.getFullYear() && base.getMonth() === next.getMonth() && base.getDate() === next.getDate())
            return next;
        base.setHours(10, 0, 0, 0);
        return base;
    }

    function showCreate(day, endDay) {
        const base = _defaultStart(day);
        if (!endDay) {
            _beginCreate(base, new Date(base.getTime() + SettingsData.defaultEventDurationMinutes * 60000), false);
            return;
        }
        base.setHours(0, 0, 0, 0);
        const end = new Date(endDay);
        end.setHours(0, 0, 0, 0);
        end.setDate(end.getDate() + 1);
        _beginCreate(base, end, true);
    }

    function showCreateTimed(start, end) {
        _beginCreate(new Date(start), new Date(end), false);
    }

    function _beginCreate(start, end, allDay) {
        event = {
            "title": "",
            "description": "",
            "location": "",
            "start": start,
            "end": end,
            "allDay": allDay,
            "attendees": [],
            "reminders": SettingsData.defaultReminderMinutes >= 0 ? [
                {
                    "method": "popup",
                    "minutes": SettingsData.defaultReminderMinutes
                }
            ] : []
        };
        createMode = true;
        confirmDelete = false;
        saving = false;
        pendingResponse = "";
        formError = "";
        _loadForm();
        editMode = true;
        visible = true;
    }

    function hide() {
        editMode = false;
        createMode = false;
        confirmDelete = false;
        saving = false;
        pendingResponse = "";
        visible = false;
    }

    onClosed: hide()

    function beginEdit() {
        _loadForm();
        formError = "";
        editMode = true;
    }

    function _loadForm() {
        formTitle = event.title || "";
        formLocation = event.location || "";
        formDescription = event.description || "";
        formAllDay = !!event.allDay;
        const start = event.start ? new Date(event.start) : new Date();
        const end = event.end ? new Date(event.end) : new Date(start.getTime() + 3600000);
        formStartDate = start;
        formStartMinutes = start.getHours() * 60 + start.getMinutes();
        formEndMinutes = end.getHours() * 60 + end.getMinutes();
        let endDate = new Date(end);
        if (formAllDay)
            endDate.setDate(endDate.getDate() - 1);
        if (endDate.getTime() < start.getTime())
            endDate = new Date(start);
        formEndDate = endDate;
        if (!formAllDay && end.getTime() <= start.getTime())
            formEndMinutes = formStartMinutes + 60;

        const writable = DankCalService.writableCalendars();
        const wanted = event.calendarId || SettingsData.defaultCalendarId;
        formCalendarIndex = 0;
        for (let i = 0; i < writable.length; i++) {
            if (writable[i].id === wanted) {
                formCalendarIndex = i;
                break;
            }
        }

        const popupMinutes = [];
        const reminders = event.reminders || [];
        for (let i = 0; i < reminders.length; i++) {
            if (!_isPopup(reminders[i]))
                continue;
            if (popupMinutes.indexOf(reminders[i].minutes) === -1)
                popupMinutes.push(reminders[i].minutes);
        }
        formReminders = popupMinutes;
    }

    function addReminder() {
        const list = formReminders.slice();
        if (list.length >= maxReminders)
            return;
        let candidate = SettingsData.defaultReminderMinutes >= 0 ? SettingsData.defaultReminderMinutes : 10;
        if (list.indexOf(candidate) !== -1) {
            for (let i = 1; i < reminderOptions.length; i++) {
                if (list.indexOf(reminderOptions[i].value) === -1) {
                    candidate = reminderOptions[i].value;
                    break;
                }
            }
        }
        if (list.indexOf(candidate) !== -1)
            return;
        list.push(candidate);
        formReminders = list;
    }

    function setReminder(index, minutes) {
        const list = formReminders.slice();
        list[index] = minutes;
        formReminders = list;
    }

    function removeReminder(index) {
        const list = formReminders.slice();
        list.splice(index, 1);
        formReminders = list;
    }

    function _isPopup(reminder) {
        const method = reminder.method || "popup";
        return method === "popup" || method === "display";
    }

    function reminderText(minutes) {
        if (minutes < 0)
            return "";
        if (minutes === 0)
            return I18n.tr("At start", "event reminder dropdown option");
        if (minutes % 10080 === 0)
            return I18n.tr("%1w before", "event details short reminder offset in weeks").arg(minutes / 10080);
        if (minutes % 1440 === 0)
            return I18n.tr("%1d before", "event details short reminder offset in days").arg(minutes / 1440);
        if (minutes % 60 === 0)
            return I18n.tr("%1h before", "event details short reminder offset in hours").arg(minutes / 60);
        return I18n.tr("%1m before", "event details short reminder offset in minutes").arg(minutes);
    }

    function reminderSummary() {
        const labels = (event.reminders || []).filter(r => _isPopup(r)).map(r => reminderText(r.minutes));
        return labels.join(" · ");
    }

    function locationUrl() {
        const loc = (event.location || "").trim();
        if (loc === "")
            return "";
        if (/^https?:\/\/\S+$/i.test(loc))
            return loc;
        if (/^www\.\S+$/i.test(loc))
            return "https://" + loc;
        if (event.meetingUrl)
            return event.meetingUrl;
        return "geo:0,0?q=" + encodeURIComponent(loc);
    }

    function recurrenceSummary() {
        const label = DankCalService.recurrenceLabel(event);
        if (label !== "")
            return label;
        return (event.recurringId || "") !== "" ? I18n.tr("Repeats", "generic recurrence label for an unrecognized rule") : "";
    }

    function reminderOptionLabel(minutes) {
        for (let i = 0; i < reminderOptions.length; i++) {
            if (reminderOptions[i].value === minutes)
                return reminderOptions[i].label;
        }
        return reminderText(minutes);
    }

    function setFormStartDate(value) {
        const startMidnight = new Date(formStartDate.getFullYear(), formStartDate.getMonth(), formStartDate.getDate());
        const endMidnight = new Date(formEndDate.getFullYear(), formEndDate.getMonth(), formEndDate.getDate());
        const spanDays = Math.round((endMidnight.getTime() - startMidnight.getTime()) / 86400000);
        formStartDate = value;
        const end = new Date(value);
        end.setDate(end.getDate() + Math.max(spanDays, 0));
        formEndDate = end;
    }

    function _formRange() {
        const y = formStartDate.getFullYear();
        const mo = formStartDate.getMonth();
        const d = formStartDate.getDate();
        const ey = formEndDate.getFullYear();
        const emo = formEndDate.getMonth();
        const ed = formEndDate.getDate();
        if (formAllDay) {
            const start = new Date(Date.UTC(y, mo, d));
            let end = new Date(Date.UTC(ey, emo, ed + 1));
            if (end.getTime() <= start.getTime())
                end = new Date(Date.UTC(y, mo, d + 1));
            return {
                "start": start,
                "end": end
            };
        }

        const start = new Date(y, mo, d, Math.floor(formStartMinutes / 60), formStartMinutes % 60);
        let end = new Date(ey, emo, ed, Math.floor(formEndMinutes / 60), formEndMinutes % 60);
        if (end.getTime() <= start.getTime())
            end = new Date(y, mo, d, Math.floor((formStartMinutes + 60) / 60), (formStartMinutes + 60) % 60);
        return {
            "start": start,
            "end": end
        };
    }

    function save() {
        if (formTitle.trim() === "") {
            formError = I18n.tr("Title is required", "event form validation error for missing title");
            return;
        }
        const range = _formRange();
        const writable = DankCalService.writableCalendars();
        if (writable.length === 0) {
            formError = I18n.tr("No writable calendar available", "event form error when no calendar allows creating events");
            return;
        }
        const cal = writable[Math.min(formCalendarIndex, writable.length - 1)];

        const reminders = (event.reminders || []).filter(r => !_isPopup(r));
        const seen = [];
        for (let i = 0; i < formReminders.length; i++) {
            const minutes = formReminders[i];
            if (minutes < 0 || seen.indexOf(minutes) !== -1)
                continue;
            seen.push(minutes);
            reminders.push({
                "method": "popup",
                "minutes": minutes
            });
        }

        const fields = {
            "summary": formTitle.trim(),
            "description": formDescription,
            "location": formLocation.trim(),
            "start": range.start.toISOString(),
            "end": range.end.toISOString(),
            "allDay": formAllDay,
            "reminders": reminders
        };
        if (recurrenceEditable && recurrencePickerItem)
            fields.recurrence = recurrencePickerItem.currentRules();
        if (!createMode && isOccurrence)
            fields.occurrenceStart = EventUtils.wireTime(event.start, event.allDay);

        saving = true;
        formError = "";
        const done = response => {
            saving = false;
            if (response.error) {
                formError = response.error;
                return;
            }
            hide();
        };

        if (createMode) {
            fields.calendarId = cal.id;
            DankCalService.createEvent(fields, done);
        } else {
            DankCalService.updateEvent(event.id, fields, done);
        }
    }

    function removeEvent(occurrenceOnly) {
        if (!confirmDelete) {
            confirmDelete = true;
            return;
        }
        saving = true;
        DankCalService.deleteEvent(event.id, response => {
            saving = false;
            confirmDelete = false;
            if (response.error) {
                formError = response.error;
                return;
            }
            hide();
        }, occurrenceOnly ? EventUtils.wireTime(event.start, event.allDay) : undefined);
    }

    function respond(action) {
        if (!event.id || saving)
            return;
        if (isRecurring) {
            pendingResponse = action;
            return;
        }
        submitResponse(action, false);
    }

    function submitResponse(action, occurrenceOnly) {
        pendingResponse = "";
        saving = true;
        formError = "";
        DankCalService.rsvpEvent(event.id, action, response => {
            saving = false;
            if (response.error) {
                formError = response.error;
                return;
            }
            if (response.result)
                eventModal.event = DankCalService.eventFromResult(response.result);
        }, occurrenceOnly ? EventUtils.wireTime(event.start, event.allDay) : undefined);
    }

    function _styleAnchors(html) {
        return html.replace(/<a\s([^>]*)>/gi, (m, attrs) => {
            const cleaned = attrs.replace(/style="[^"]*"/gi, "");
            return "<a style=\"text-decoration:none; color:" + Theme.primary + ";\" " + cleaned + ">";
        });
    }

    function _inlineMarkdown(line) {
        let out = line.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        out = out.replace(/\\([\\`*_{}[\]()#+\-.!~>])/g, "$1");
        out = out.replace(/(?:https?:\/\/|www\.)[^\s<>)\]]*[^\s<>)\].,;:!?"']/g, (m, offset, s) => {
            const prev = offset > 0 ? s[offset - 1] : "";
            if (prev === "(" || prev === "[" || prev === "\"" || prev === "'")
                return m;
            const href = m.startsWith("www.") ? "https://" + m : m;
            return "<a href=\"" + href + "\">" + m + "</a>";
        });
        out = out.replace(/\[([^\]]+)\]\(([^()\s]+)\)/g, "<a href=\"$2\">$1</a>");
        out = out.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
        out = out.replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>");
        return out;
    }

    function descriptionRichText() {
        const raw = (event.description || "").trim();
        if (descriptionIsHtml)
            return _styleAnchors(raw);

        const parts = [];
        let list = "";
        const closeList = () => {
            if (list === "")
                return;
            parts.push("</" + list + ">");
            list = "";
        };

        const lines = raw.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const ul = lines[i].match(/^\s*[-*+]\s+(.+)$/);
            const ol = lines[i].match(/^\s*\d+[.)]\s+(.+)$/);
            if (ul || ol) {
                const tag = ul ? "ul" : "ol";
                if (list !== tag) {
                    closeList();
                    parts.push("<" + tag + ">");
                    list = tag;
                }
                parts.push("<li>" + _inlineMarkdown((ul || ol)[1]) + "</li>");
                continue;
            }
            closeList();
            parts.push(_inlineMarkdown(lines[i]) + "<br/>");
        }
        closeList();
        return _styleAnchors(parts.join("").replace(/<br\/>$/, ""));
    }

    function timeLabel() {
        if (!event.start)
            return "";
        const day = SettingsData.formatDate(event.start, "dddd, MMM d, yyyy");
        if (event.allDay)
            return I18n.tr("%1 · All day", "event details time label for all-day events").arg(day);
        return day + " · " + SettingsData.formatTime(event.start) + " – " + SettingsData.formatTime(event.end);
    }

    function attendeeSummary() {
        const list = event.attendees || [];
        if (list.length === 0)
            return "";
        let accepted = 0;
        for (let i = 0; i < list.length; i++) {
            if (list[i].status === "accepted")
                accepted++;
        }
        return I18n.tr("· %1 invited · %2 accepted", "event details attendee count summary").arg(list.length).arg(accepted);
    }

    readonly property real contentNaturalHeight: contentLoader.item ? contentLoader.item.naturalHeight : 0
    readonly property real chromeHeight: header.height + Theme.spacingL * 2 + (editMode ? footer.height : 0)

    title: createMode ? I18n.tr("New event", "event modal window title when creating") : (editMode ? I18n.tr("Edit event", "event modal window title when editing") : I18n.tr("Event", "event modal window title when viewing"))
    minimumSize: Qt.size(460, 560)
    implicitWidth: Math.max(minimumSize.width, Theme.modalWidth(parentWindow, screen, 560))
    implicitHeight: Math.max(minimumSize.height, Theme.modalHeight(parentWindow, screen, Math.max(720, chromeHeight + contentNaturalHeight)))
    color: Theme.windowSurface
    surfaceFormat.opaque: false
    visible: false

    WindowBlur {
        targetWindow: eventModal
        blurEnabled: Theme.translucentWindows
        blurWidth: eventModal.width
        blurHeight: eventModal.height
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
            title: eventModal.createMode ? I18n.tr("New event", "event modal header when creating") : (eventModal.editMode ? I18n.tr("Edit event", "event modal header when editing") : I18n.tr("Event details", "event modal header when viewing"))
            onCloseRequested: eventModal.hide()

            DActionButton {
                visible: !eventModal.editMode && !eventModal.event.readOnly && !!eventModal.event.id
                iconName: "edit"
                buttonSize: Theme.buttonHeightXXS
                Accessible.name: I18n.tr("Edit", "event details button to start editing")
                onClicked: eventModal.beginEdit()
            }

            DButton {
                visible: !eventModal.editMode && !eventModal.event.readOnly && !!eventModal.event.id && eventModal.confirmDelete && eventModal.isRecurring
                text: I18n.tr("Delete occurrence", "event details button to delete only this occurrence of a recurring event")
                buttonHeight: Theme.buttonHeightXXS
                backgroundColor: Theme.errorContainer
                textColor: Theme.onErrorContainer
                onClicked: eventModal.removeEvent(true)
            }

            DButton {
                visible: !eventModal.editMode && !eventModal.event.readOnly && !!eventModal.event.id && eventModal.confirmDelete
                text: eventModal.isRecurring ? I18n.tr("Delete series", "event details button to confirm deleting a whole recurring series") : I18n.tr("Confirm delete", "event details button to confirm deleting the event")
                buttonHeight: Theme.buttonHeightXXS
                backgroundColor: eventModal.isRecurring ? "transparent" : Theme.errorContainer
                textColor: eventModal.isRecurring ? Theme.error : Theme.onErrorContainer
                onClicked: eventModal.removeEvent()
            }

            DActionButton {
                visible: !eventModal.editMode && !eventModal.event.readOnly && !!eventModal.event.id && !eventModal.confirmDelete
                iconName: "delete_outline"
                buttonSize: Theme.buttonHeightXXS
                iconColor: Theme.error
                Accessible.name: I18n.tr("Delete", "event details button to delete the event")
                onClicked: eventModal.removeEvent()
            }
        }

        Item {
            width: parent.width
            height: parent.height - header.height - (footer.visible ? footer.height : 0)

            Loader {
                id: contentLoader
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                sourceComponent: eventModal.editMode ? editComponent : detailComponent
            }
        }

        Item {
            id: footer
            width: parent.width
            height: Theme.buttonHeightS + Theme.spacingM * 2
            visible: eventModal.editMode

            Rectangle {
                anchors.fill: parent
                color: Theme.floatingWindowPaneSurface
            }

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                text: eventModal.formError
                color: Theme.error
                font.pixelSize: Theme.fontSizeSmall
                visible: eventModal.formError !== ""
                elide: Text.ElideRight
                width: parent.width / 2
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DButton {
                    text: I18n.tr("Cancel", "event form button to cancel editing")
                    backgroundColor: "transparent"
                    textColor: Theme.primary
                    onClicked: {
                        if (eventModal.createMode) {
                            eventModal.hide();
                            return;
                        }
                        eventModal.editMode = false;
                    }
                }

                DButton {
                    text: eventModal.saving ? I18n.tr("Saving...", "event details save button while saving") : I18n.tr("Save", "event details button to save changes")
                    iconName: "check"
                    busy: eventModal.saving
                    backgroundColor: Theme.primary
                    textColor: Theme.primaryText
                    onClicked: {
                        if (!eventModal.saving)
                            eventModal.save();
                    }
                }
            }
        }
    }

    Component {
        id: detailComponent

        Item {
            readonly property real naturalHeight: {
                var h = titleBlock.implicitHeight + Theme.spacingL + metaBlock.implicitHeight;
                if (rsvpBlock.visible)
                    h += Theme.spacingL + rsvpBlock.implicitHeight;
                if (attendeesBlock.visible)
                    h += Theme.spacingL + attendeesBlock.implicitHeight;
                if (descBlock.visible)
                    h += Theme.spacingL + descHeader.height + descBlock.spacing + descriptionText.implicitHeight + Theme.spacingM * 2;
                return h;
            }

            Column {
                id: titleBlock
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Theme.spacingXS

                StyledText {
                    text: eventModal.event.title || DankCalService.untitledEventTitle(eventModal.event.visibility)
                    font.pixelSize: Theme.fontSizeXXLarge
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                    width: parent.width
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                StyledText {
                    text: eventModal.timeLabel()
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    width: parent.width
                }
            }

            Column {
                id: metaBlock
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: titleBlock.bottom
                anchors.topMargin: Theme.spacingL
                spacing: Theme.spacingS

                MetaRow {
                    iconName: "calendar_month"
                    primary: eventModal.event.calendar || ""
                    secondary: eventModal.event.account || ""
                    accent: eventModal.event.color || Theme.primary
                    visible: primary !== ""
                }

                MetaRow {
                    iconName: "layers"
                    primary: (eventModal.event.mergedFrom || []).map(other => other.calendar).join(", ")
                    secondary: I18n.tr("Also in these calendars", "event details row listing other calendars a merged duplicate event appears in")
                    visible: primary !== ""
                }

                MetaRow {
                    iconName: "place"
                    primary: eventModal.event.location || ""
                    accent: link ? Theme.primary : Theme.surfaceVariantText
                    link: linkUrl !== ""
                    linkUrl: eventModal.locationUrl()
                    visible: primary !== ""
                }

                MetaRow {
                    iconName: "repeat"
                    primary: eventModal.recurrenceSummary()
                    visible: primary !== ""
                }

                MetaRow {
                    iconName: "videocam"
                    primary: I18n.tr("Join video call", "event details row that opens the meeting link")
                    secondary: eventModal.event.meetingUrl || ""
                    accent: Theme.primary
                    link: true
                    linkUrl: eventModal.event.meetingUrl || ""
                    visible: secondary !== ""
                }

                MetaRow {
                    iconName: "notifications"
                    primary: eventModal.reminderSummary()
                    visible: primary !== ""
                }

                MetaRow {
                    iconName: "link"
                    primary: eventModal.event.url || ""
                    accent: Theme.primary
                    link: true
                    linkUrl: eventModal.event.url || ""
                    visible: primary !== ""
                }
            }

            Column {
                id: rsvpBlock
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: metaBlock.bottom
                anchors.topMargin: Theme.spacingL
                spacing: Theme.spacingS
                visible: !!eventModal.event.canRespond

                Row {
                    spacing: Theme.spacingS

                    DIcon {
                        name: "event_available"
                        size: Theme.iconSizeMedium
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: I18n.tr("Your response", "event details RSVP section label")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingL + Theme.iconSizeMedium
                    spacing: Theme.spacingS
                    visible: eventModal.pendingResponse === ""

                    DButton {
                        text: I18n.tr("Accept", "RSVP accept button")
                        buttonHeight: Theme.buttonHeightXS
                        backgroundColor: eventModal.event.myResponse === "accepted" ? Theme.success : Theme.secondaryContainer
                        textColor: eventModal.event.myResponse === "accepted" ? Theme.contrastDark : Theme.onSecondaryContainer
                        enabled: !eventModal.saving
                        onClicked: eventModal.respond("accept")
                    }

                    DButton {
                        text: I18n.tr("Maybe", "RSVP tentative button")
                        buttonHeight: Theme.buttonHeightXS
                        backgroundColor: eventModal.event.myResponse === "tentative" ? Theme.warning : Theme.secondaryContainer
                        textColor: eventModal.event.myResponse === "tentative" ? Theme.contrastDark : Theme.onSecondaryContainer
                        enabled: !eventModal.saving
                        onClicked: eventModal.respond("tentative")
                    }

                    DButton {
                        text: I18n.tr("Decline", "RSVP decline button")
                        buttonHeight: Theme.buttonHeightXS
                        backgroundColor: eventModal.event.myResponse === "declined" ? Theme.error : Theme.secondaryContainer
                        textColor: eventModal.event.myResponse === "declined" ? Theme.contrastDark : Theme.onSecondaryContainer
                        enabled: !eventModal.saving
                        onClicked: eventModal.respond("decline")
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingL + Theme.iconSizeMedium
                    spacing: Theme.spacingS
                    visible: eventModal.pendingResponse !== ""

                    DButton {
                        text: I18n.tr("This event", "RSVP scope button replying for one occurrence of a recurring event")
                        buttonHeight: Theme.buttonHeightXS
                        backgroundColor: Theme.primary
                        textColor: Theme.primaryText
                        enabled: !eventModal.saving
                        onClicked: eventModal.submitResponse(eventModal.pendingResponse, true)
                    }

                    DButton {
                        text: I18n.tr("All events", "RSVP scope button replying for the whole recurring series")
                        buttonHeight: Theme.buttonHeightXS
                        backgroundColor: Theme.secondaryContainer
                        textColor: Theme.onSecondaryContainer
                        enabled: !eventModal.saving
                        onClicked: eventModal.submitResponse(eventModal.pendingResponse, false)
                    }

                    DActionButton {
                        iconName: "close"
                        Accessible.name: I18n.tr("Cancel", "event form button to cancel editing")
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: eventModal.pendingResponse = ""
                    }
                }
            }

            Column {
                id: attendeesBlock
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: rsvpBlock.visible ? rsvpBlock.bottom : metaBlock.bottom
                anchors.topMargin: Theme.spacingL
                spacing: Theme.spacingS
                visible: (eventModal.event.attendees || []).length > 0

                Row {
                    spacing: Theme.spacingS

                    DIcon {
                        name: "people"
                        size: Theme.iconSizeMedium
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: I18n.tr("Attendees", "event details section label for attendee list")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: eventModal.attendeeSummary()
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Repeater {
                    model: ScriptModel {
                        values: (eventModal.event.attendees || []).slice(0, 8)
                    }

                    Item {
                        id: attendeeItem
                        required property var modelData
                        readonly property string displayName: modelData.displayName || modelData.email || ""
                        readonly property string status: modelData.status || "needsAction"
                        width: parent.width
                        height: Theme.buttonHeightXS + Theme.spacingXS

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingL + Theme.iconSizeMedium
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            Rectangle {
                                width: Theme.iconSize
                                height: Theme.iconSize
                                radius: Theme.fullRadius(width, height)
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.primaryContainer

                                StyledText {
                                    anchors.centerIn: parent
                                    text: attendeeItem.displayName.charAt(0).toUpperCase()
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.onPrimaryContainer
                                }
                            }

                            StyledText {
                                text: attendeeItem.displayName
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: attendeeItem.modelData.email && attendeeItem.modelData.displayName ? attendeeItem.modelData.email : ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Item {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: statusLabel.implicitWidth + Theme.spacingM * 2
                            height: Theme.iconSizeMedium + Theme.spacingXXS

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.fullRadius(width, height)
                                color: {
                                    switch (attendeeItem.status) {
                                    case "accepted":
                                        return Theme.withAlpha(Theme.success, 0.18);
                                    case "declined":
                                        return Theme.withAlpha(Theme.error, 0.18);
                                    default:
                                        return Theme.withAlpha(Theme.warning, 0.18);
                                    }
                                }

                                StyledText {
                                    id: statusLabel
                                    anchors.centerIn: parent
                                    text: attendeeItem.status
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Theme.fontWeightMedium
                                    elide: Text.ElideRight
                                    color: {
                                        switch (attendeeItem.status) {
                                        case "accepted":
                                            return Theme.success;
                                        case "declined":
                                            return Theme.error;
                                        default:
                                            return Theme.warning;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Column {
                id: descBlock
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: attendeesBlock.visible ? attendeesBlock.bottom : (rsvpBlock.visible ? rsvpBlock.bottom : metaBlock.bottom)
                anchors.bottom: parent.bottom
                anchors.topMargin: Theme.spacingL
                spacing: Theme.spacingS
                visible: (eventModal.event.description || "") !== ""

                Row {
                    id: descHeader
                    spacing: Theme.spacingS

                    DIcon {
                        name: "notes"
                        size: Theme.iconSizeMedium
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: I18n.tr("Description", "event details section label for description")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                StyledRect {
                    width: parent.width
                    height: parent.height - parent.spacing - descHeader.height
                    color: Theme.surfaceContainerLow
                    radius: Theme.cornerRadiusM

                    DFlickable {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        clip: true
                        contentWidth: width
                        contentHeight: descriptionText.implicitHeight

                        StyledText {
                            id: descriptionText
                            text: eventModal.descriptionRichText()
                            textFormat: Text.RichText
                            linkColor: Theme.primary
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            width: parent.width
                            wrapMode: Text.WordWrap
                            onLinkActivated: link => Qt.openUrlExternally(link)

                            HoverHandler {
                                enabled: descriptionText.hoveredLink !== ""
                                cursorShape: Qt.PointingHandCursor
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: editComponent

        DFlickable {
            readonly property real naturalHeight: editColumn.implicitHeight

            clip: true
            contentWidth: width
            contentHeight: editColumn.implicitHeight

            Column {
                id: editColumn
                width: parent.width
                spacing: Theme.spacingM

                FormRow {
                    iconName: "title"

                    DTextField {
                        width: parent.width
                        height: Theme.fieldHeightLarge
                        outlined: true
                        labelText: I18n.tr("Add title", "event form placeholder for title input")
                        text: eventModal.formTitle
                        onTextChanged: eventModal.formTitle = text
                        Component.onCompleted: forceActiveFocus()
                    }
                }

                FormRow {
                    iconName: "schedule"
                    iconHeight: allDayToggle.height

                    DToggle {
                        id: allDayToggle
                        width: parent.width
                        text: I18n.tr("All day", "event form toggle label for all-day events")
                        checked: eventModal.formAllDay
                        onToggled: checked => eventModal.formAllDay = checked
                    }

                    Grid {
                        width: parent.width
                        columns: width < Theme.fontSizeMedium * 24 ? 1 : 2
                        spacing: Theme.spacingM

                        Column {
                            width: (parent.width - parent.spacing * (parent.columns - 1)) / parent.columns
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: I18n.tr("Start", "event form start date and time label")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            DankDatePicker {
                                width: parent.width
                                dateFormat: "MMM d, yyyy"
                                firstDayOfWeek: SettingsData.effectiveFirstDayOfWeek
                                selectedDate: eventModal.formStartDate
                                onDateSelected: value => eventModal.setFormStartDate(value)
                            }

                            DankTimeField {
                                width: parent.width
                                visible: !eventModal.formAllDay
                                use24Hour: SettingsData.use24HourTime
                                minutes: eventModal.formStartMinutes
                                onTimeSelected: value => {
                                    const duration = eventModal.formEndMinutes - eventModal.formStartMinutes;
                                    eventModal.formStartMinutes = value;
                                    eventModal.formEndMinutes = value + Math.max(duration, 0);
                                }
                            }
                        }

                        Column {
                            width: (parent.width - parent.spacing * (parent.columns - 1)) / parent.columns
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: I18n.tr("End", "event form end date and time label")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            DankDatePicker {
                                width: parent.width
                                dateFormat: "MMM d, yyyy"
                                firstDayOfWeek: SettingsData.effectiveFirstDayOfWeek
                                selectedDate: eventModal.formEndDate
                                onDateSelected: value => eventModal.formEndDate = value
                            }

                            DankTimeField {
                                width: parent.width
                                visible: !eventModal.formAllDay
                                use24Hour: SettingsData.use24HourTime
                                minutes: eventModal.formEndMinutes
                                onTimeSelected: value => eventModal.formEndMinutes = value
                            }
                        }
                    }
                }

                FormRow {
                    iconName: "place"

                    DTextField {
                        width: parent.width
                        height: Theme.fieldHeightLarge
                        outlined: true
                        labelText: I18n.tr("Location", "event form placeholder for location input")
                        text: eventModal.formLocation
                        onTextChanged: eventModal.formLocation = text
                    }
                }

                FormRow {
                    iconName: "calendar_month"
                    visible: !(eventModal.createMode && eventModal.noWritableCalendars)

                    DDropdown {
                        readonly property var writable: DankCalService.writableCalendars()

                        width: parent.width
                        triggerHeight: Theme.fieldHeightLarge
                        enabled: eventModal.createMode
                        opacity: enabled ? 1 : 0.5
                        options: writable.map(c => c.name)
                        currentValue: writable.length > 0 ? writable[Math.min(eventModal.formCalendarIndex, writable.length - 1)].name : ""
                        onValueChanged: value => {
                            for (let i = 0; i < writable.length; i++) {
                                if (writable[i].name === value) {
                                    eventModal.formCalendarIndex = i;
                                    return;
                                }
                            }
                        }
                    }
                }

                FormRow {
                    iconName: "calendar_add_on"
                    visible: eventModal.createMode && eventModal.noWritableCalendars

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            width: parent.width
                            text: I18n.tr("No calendars yet. Add one to start creating events.", "event form guidance when there are no writable calendars")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                        }

                        DButton {
                            text: I18n.tr("Add a calendar", "event form button to add a calendar when none exist")
                            iconName: "add"
                            backgroundColor: Theme.primary
                            textColor: Theme.primaryText
                            onClicked: {
                                eventModal.addCalendarRequested();
                                eventModal.hide();
                            }
                        }
                    }
                }

                FormRow {
                    iconName: "repeat"
                    visible: eventModal.recurrenceEditable

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS

                        DankRecurrencePicker {
                            id: recurrencePicker
                            width: parent.width
                            rules: eventModal.event.recurrence || []
                            startDate: eventModal.formStartDate
                            allDay: eventModal.formAllDay
                            Component.onCompleted: eventModal.recurrencePickerItem = this
                            Component.onDestruction: {
                                if (eventModal.recurrencePickerItem === this)
                                    eventModal.recurrencePickerItem = null;
                            }
                        }

                        StyledText {
                            visible: !eventModal.createMode && recurrencePicker.isRecurring
                            text: I18n.tr("Changes apply to the whole series", "event form note when editing a recurring event")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            width: parent.width
                            horizontalAlignment: Text.AlignLeft
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                FormRow {
                    iconName: "repeat"
                    iconHeight: Theme.iconButtonSize
                    visible: !eventModal.recurrenceEditable && eventModal.isOccurrence

                    Column {
                        width: parent.width
                        spacing: 0

                        StyledText {
                            text: eventModal.recurrenceSummary()
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            width: parent.width
                            horizontalAlignment: Text.AlignLeft
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            text: I18n.tr("Changes apply to the whole series", "event form note when editing a recurring event")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            width: parent.width
                            horizontalAlignment: Text.AlignLeft
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                FormRow {
                    iconName: "notifications"
                    iconHeight: eventModal.formReminders.length > 0 ? Theme.fieldHeightLarge : Theme.buttonHeightXS

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS

                        Repeater {
                            model: ScriptModel {
                                values: eventModal.formReminders
                            }

                            Row {
                                id: reminderRow

                                required property int index
                                required property var modelData

                                width: parent.width
                                spacing: Theme.spacingS

                                DDropdown {
                                    width: parent.width - removeButton.width - Theme.spacingS
                                    triggerHeight: Theme.fieldHeightLarge
                                    options: eventModal.reminderOptions.slice(1).map(o => o.label)
                                    currentValue: eventModal.reminderOptionLabel(reminderRow.modelData)
                                    onValueChanged: value => {
                                        for (let i = 0; i < eventModal.reminderOptions.length; i++) {
                                            if (eventModal.reminderOptions[i].label === value) {
                                                eventModal.setReminder(reminderRow.index, eventModal.reminderOptions[i].value);
                                                return;
                                            }
                                        }
                                    }
                                }

                                DActionButton {
                                    id: removeButton
                                    iconName: "close"
                                    Accessible.name: I18n.tr("Remove reminder", "event form button that removes one reminder row")
                                    onClicked: eventModal.removeReminder(reminderRow.index)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        DButton {
                            text: I18n.tr("Add reminder", "event form button to add another reminder")
                            iconName: "add"
                            buttonHeight: Theme.buttonHeightXS
                            backgroundColor: Theme.secondaryContainer
                            textColor: Theme.onSecondaryContainer
                            visible: eventModal.formReminders.length < eventModal.maxReminders
                            onClicked: eventModal.addReminder()
                        }
                    }
                }

                FormRow {
                    iconName: "notes"

                    StyledRect {
                        width: parent.width
                        height: Theme.textEditHeight
                        color: Theme.surfaceContainerHigh
                        radius: Theme.cornerRadiusXS
                        border.width: descArea.activeFocus ? Theme.outlineWidthFocused : Theme.outlineWidth
                        border.color: descArea.activeFocus ? Theme.primary : Theme.outlineVariant

                        DFlickable {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            clip: true
                            contentWidth: width

                            TextArea.flickable: TextArea {
                                id: descArea

                                wrapMode: TextEdit.Wrap
                                background: null
                                color: Theme.surfaceText
                                selectionColor: Theme.primarySelected
                                selectedTextColor: Theme.surfaceText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeMedium
                                text: eventModal.formDescription
                                onTextChanged: eventModal.formDescription = text
                                Keys.onTabPressed: nextItemInFocusChain(true).forceActiveFocus()
                                Keys.onBacktabPressed: nextItemInFocusChain(false).forceActiveFocus()

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: descArea.leftPadding
                                    anchors.topMargin: descArea.topPadding
                                    visible: descArea.length === 0 && descArea.preeditText.length === 0
                                    text: I18n.tr("Add description", "event form placeholder for description text area")
                                    color: Theme.surfaceVariantText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMedium
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component FormRow: Item {
        id: formRow

        property string iconName: ""
        property real iconHeight: Theme.fieldHeightLarge
        default property alias content: formContent.data

        width: parent.width
        height: Math.max(iconHeight, formContent.implicitHeight)

        data: [
            DIcon {
                anchors.left: parent.left
                y: (formRow.iconHeight - height) / 2
                name: formRow.iconName
                size: Theme.iconSizeMedium
                color: Theme.surfaceVariantText
            },
            Column {
                id: formContent
                anchors.left: parent.left
                anchors.leftMargin: Theme.iconSizeMedium + Theme.spacingM
                anchors.right: parent.right
                spacing: Theme.spacingM
            }
        ]
    }

    component MetaRow: Item {
        property string iconName: ""
        property string primary: ""
        property string secondary: ""
        property color accent: Theme.surfaceVariantText
        property bool link: false
        property string linkUrl: ""

        width: parent.width
        height: Math.max(Theme.buttonHeightXS, infoColumn.implicitHeight)

        DIcon {
            id: rowIcon
            name: parent.iconName
            size: Theme.iconSizeMedium
            color: parent.accent
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            id: infoColumn
            anchors.left: rowIcon.right
            anchors.leftMargin: Theme.spacingM
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            StyledText {
                text: parent.parent.primary
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: parent.parent.link ? Theme.primary : Theme.surfaceText
                width: parent.width
                elide: Text.ElideRight
            }

            StyledText {
                visible: text !== ""
                text: parent.parent.secondary
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                width: parent.width
                elide: Text.ElideRight
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: parent.link && parent.linkUrl !== ""
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: DankCalService.openUri(parent.linkUrl)
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: eventModal.visible
        onActivated: {
            if (eventModal.confirmDelete) {
                eventModal.confirmDelete = false;
                return;
            }
            if (eventModal.editMode && !eventModal.createMode) {
                eventModal.editMode = false;
                return;
            }
            eventModal.hide();
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: eventModal
    }
}
