import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

FloatingWindow {
    id: taskModal

    property var task: ({})
    property bool createMode: false
    property bool confirmDelete: false
    property bool saving: false
    property string formError: ""

    signal addCalendarRequested

    property string formTitle: ""
    property string formNotes: ""
    property bool formHasDue: false
    property date formDueDate: new Date()
    property int formPriority: 0
    property bool formCompleted: false
    property int formCalendarIndex: 0
    property string formRepeatFreq: ""
    property int formRepeatInterval: 1

    // The editor models FREQ+INTERVAL only; we keep the original rule so an edit
    // that leaves recurrence alone doesn't strip BYDAY/COUNT/UNTIL on save.
    property var loadedRecurrence: []
    property string loadedRepeatFreq: ""
    property int loadedRepeatInterval: 1

    readonly property var taskLists: DankCalService.taskListCalendars()
    readonly property bool noTaskLists: taskLists.length === 0

    readonly property string selectedCalendarId: createMode ? (taskLists.length > 0 ? taskLists[Math.min(formCalendarIndex, taskLists.length - 1)].id : "") : (task.calendarId || "")
    // Google Tasks has no recurrence API, so hide the editor for Google lists.
    readonly property bool recurrenceSupported: DankCalService.calendarAccountKind(selectedCalendarId) !== "google"

    readonly property var repeatOptions: [
        {
            label: I18n.tr("Does not repeat", "task recurrence dropdown option"),
            value: ""
        },
        {
            label: I18n.tr("Daily", "task recurrence dropdown option"),
            value: "DAILY"
        },
        {
            label: I18n.tr("Weekly", "task recurrence dropdown option"),
            value: "WEEKLY"
        },
        {
            label: I18n.tr("Monthly", "task recurrence dropdown option"),
            value: "MONTHLY"
        },
        {
            label: I18n.tr("Yearly", "task recurrence dropdown option"),
            value: "YEARLY"
        }
    ]

    readonly property var priorityOptions: [
        {
            label: I18n.tr("None", "task priority dropdown option"),
            value: 0
        },
        {
            label: I18n.tr("Low", "task priority dropdown option"),
            value: 9
        },
        {
            label: I18n.tr("Medium", "task priority dropdown option"),
            value: 5
        },
        {
            label: I18n.tr("High", "task priority dropdown option"),
            value: 1
        }
    ]

    function show(taskData) {
        task = taskData || {};
        createMode = false;
        _loadForm();
        visible = true;
        titleField.forceActiveFocus();
    }

    function showCreate() {
        task = {};
        createMode = true;
        _loadForm();
        visible = true;
        titleField.forceActiveFocus();
    }

    function hide() {
        visible = false;
        confirmDelete = false;
    }

    onClosed: hide()

    function _loadForm() {
        formError = "";
        confirmDelete = false;
        formTitle = task.title || "";
        formNotes = task.description || "";
        formHasDue = !!task.due;
        formDueDate = task.due ? new Date(task.due) : new Date();
        formPriority = task.priority || 0;
        formCompleted = task.status === "completed";

        formRepeatFreq = "";
        formRepeatInterval = 1;
        const rules = task.recurrence || [];
        if (rules.length > 0) {
            const parts = rules[0].split(";");
            for (let p = 0; p < parts.length; p++) {
                const kv = parts[p].split("=");
                if (kv[0] === "FREQ")
                    formRepeatFreq = kv[1];
                else if (kv[0] === "INTERVAL")
                    formRepeatInterval = parseInt(kv[1]) || 1;
            }
        }
        loadedRecurrence = rules;
        loadedRepeatFreq = formRepeatFreq;
        loadedRepeatInterval = formRepeatInterval;

        formCalendarIndex = 0;
        if (task.calendarId) {
            for (let i = 0; i < taskLists.length; i++) {
                if (taskLists[i].id === task.calendarId) {
                    formCalendarIndex = i;
                    break;
                }
            }
        }
    }

    // VTODO priority is 1-9 (1-4 high, 5 medium, 6-9 low); collapse to the four
    // buckets the dropdown offers so a priority of 3 reads as High, not None.
    function _priorityBucket(value) {
        if (value <= 0)
            return 0;
        if (value <= 4)
            return 1;
        if (value === 5)
            return 5;
        return 9;
    }

    function _priorityLabel(value) {
        const bucket = _priorityBucket(value);
        for (let i = 0; i < priorityOptions.length; i++) {
            if (priorityOptions[i].value === bucket)
                return priorityOptions[i].label;
        }
        return priorityOptions[0].label;
    }

    // Tag each list with its owning account so it's clear which one a task lands in.
    function _listLabel(cal) {
        const acct = DankCalService.accountSummary(cal.id);
        return acct === "" ? cal.name : cal.name + "  ·  " + acct;
    }

    function _repeatLabel(value) {
        for (let i = 0; i < repeatOptions.length; i++) {
            if (repeatOptions[i].value === value)
                return repeatOptions[i].label;
        }
        return repeatOptions[0].label;
    }

    function _recurrenceRules() {
        if (!recurrenceSupported)
            return loadedRecurrence;
        if (formRepeatFreq === "")
            return [];
        if (formRepeatFreq === loadedRepeatFreq && formRepeatInterval === loadedRepeatInterval)
            return loadedRecurrence;
        let rule = "FREQ=" + formRepeatFreq;
        const n = Math.max(1, formRepeatInterval);
        if (n > 1)
            rule += ";INTERVAL=" + n;
        return [rule];
    }

    function save() {
        if (formTitle.trim() === "") {
            formError = I18n.tr("Title is required", "task form validation error for missing title");
            return;
        }

        let status = "needs_action";
        if (formCompleted)
            status = "completed";
        else if (task.status === "in_process")
            status = "in_process";

        const fields = {
            "summary": formTitle.trim(),
            "description": formNotes,
            "priority": formPriority,
            "status": status,
            "allDay": true,
            "due": formHasDue ? _dueIso() : "",
            "recurrence": _recurrenceRules()
        };

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
            if (noTaskLists) {
                saving = false;
                formError = I18n.tr("No task list available", "task form error when no calendar can hold tasks");
                return;
            }
            fields.calendarId = taskLists[Math.min(formCalendarIndex, taskLists.length - 1)].id;
            DankCalService.createTask(fields, done);
        } else {
            DankCalService.updateTask(task.id, fields, done);
        }
    }

    // _dueIso pins the chosen due date to UTC midnight so an all-day task lands
    // on that calendar day regardless of the local offset.
    function _dueIso() {
        const d = formDueDate;
        return new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())).toISOString();
    }

    function removeTask() {
        if (!confirmDelete) {
            confirmDelete = true;
            return;
        }
        saving = true;
        DankCalService.deleteTask(task.id, response => {
            saving = false;
            confirmDelete = false;
            if (response.error) {
                formError = response.error;
                return;
            }
            hide();
        });
    }

    readonly property real formLabelWidth: Theme.iconButtonSize * 2
    readonly property real contentNaturalHeight: formColumn.implicitHeight + header.height + footer.height + Theme.spacingL * 2

    minimumSize: Qt.size(440, 400)
    implicitWidth: Math.max(minimumSize.width, Theme.modalWidth(parentWindow, screen, 520))
    implicitHeight: Math.max(minimumSize.height, Theme.modalHeight(parentWindow, screen, contentNaturalHeight))
    visible: false
    title: taskModal.createMode ? I18n.tr("New task", "title bar for the create-task dialog") : I18n.tr("Task", "title bar for the edit-task dialog")
    color: Theme.windowSurface
    surfaceFormat.opaque: false

    WindowBlur {
        targetWindow: taskModal
        blurEnabled: Theme.translucentWindows
        blurWidth: taskModal.width
        blurHeight: taskModal.height
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
            title: taskModal.createMode ? I18n.tr("New task", "header in the create-task dialog") : I18n.tr("Edit task", "header in the edit-task dialog")
            onCloseRequested: taskModal.hide()
        }

        Item {
            width: parent.width
            height: parent.height - header.height - footer.height

            DFlickable {
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                clip: true
                contentWidth: width
                contentHeight: formColumn.implicitHeight

                Column {
                    id: formColumn
                    width: parent.width
                    spacing: Theme.spacingM

                    StyledText {
                        visible: taskModal.createMode && taskModal.noTaskLists
                        text: I18n.tr("Add a CalDAV, local, Google, or Microsoft account with a task list to create tasks.", "task dialog hint when no task list is available")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        width: parent.width
                        horizontalAlignment: Text.AlignLeft
                        wrapMode: Text.WordWrap
                    }

                    DTextField {
                        id: titleField
                        width: parent.width
                        outlined: true
                        labelText: I18n.tr("Add title", "task form placeholder for title input")
                        text: taskModal.formTitle
                        isError: taskModal.formError !== "" && taskModal.formTitle.trim() === ""
                        supportingText: isError ? taskModal.formError : ""
                        onTextChanged: taskModal.formTitle = text
                    }

                    DTextField {
                        width: parent.width
                        outlined: true
                        leftIconName: "notes"
                        labelText: I18n.tr("Notes", "task form placeholder for notes input")
                        text: taskModal.formNotes
                        onTextChanged: taskModal.formNotes = text
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        DToggle {
                            id: dueToggle
                            checked: taskModal.formHasDue
                            onToggled: checked => taskModal.formHasDue = checked
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            id: dueLabel
                            text: I18n.tr("Due date", "task form toggle label for the due date")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DankDatePicker {
                            visible: taskModal.formHasDue
                            width: parent.width - dueToggle.width - dueLabel.width - Theme.spacingM * 2
                            firstDayOfWeek: SettingsData.effectiveFirstDayOfWeek
                            selectedDate: taskModal.formDueDate
                            onDateSelected: value => taskModal.formDueDate = value
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        StyledText {
                            text: I18n.tr("Priority", "task form label for the priority dropdown")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            width: taskModal.formLabelWidth
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DDropdown {
                            dropdownWidth: Theme.fieldDefaultWidth
                            options: taskModal.priorityOptions.map(o => o.label)
                            currentValue: taskModal._priorityLabel(taskModal.formPriority)
                            onValueChanged: value => {
                                for (let i = 0; i < taskModal.priorityOptions.length; i++) {
                                    if (taskModal.priorityOptions[i].label === value) {
                                        taskModal.formPriority = taskModal.priorityOptions[i].value;
                                        break;
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM
                        visible: taskModal.recurrenceSupported

                        StyledText {
                            text: I18n.tr("Repeat", "task form label for the recurrence dropdown")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            width: taskModal.formLabelWidth
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DDropdown {
                            dropdownWidth: Theme.fieldDefaultWidth
                            options: taskModal.repeatOptions.map(o => o.label)
                            currentValue: taskModal._repeatLabel(taskModal.formRepeatFreq)
                            onValueChanged: value => {
                                for (let i = 0; i < taskModal.repeatOptions.length; i++) {
                                    if (taskModal.repeatOptions[i].label === value) {
                                        taskModal.formRepeatFreq = taskModal.repeatOptions[i].value;
                                        break;
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM
                        visible: taskModal.recurrenceSupported && taskModal.formRepeatFreq !== ""

                        StyledText {
                            text: I18n.tr("Every", "task form label for the recurrence interval")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            width: taskModal.formLabelWidth
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DTextField {
                            width: taskModal.formLabelWidth
                            text: String(taskModal.formRepeatInterval)
                            onTextChanged: {
                                const n = parseInt(text);
                                taskModal.formRepeatInterval = isNaN(n) || n < 1 ? 1 : n;
                            }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    StyledText {
                        visible: !taskModal.recurrenceSupported
                        text: I18n.tr("Recurring tasks are managed in Google Tasks.", "task form note when recurrence cannot be edited on google")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        width: parent.width
                        horizontalAlignment: Text.AlignLeft
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM
                        visible: taskModal.createMode && !taskModal.noTaskLists

                        StyledText {
                            text: I18n.tr("List", "task form label for the task-list dropdown")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            width: taskModal.formLabelWidth
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DDropdown {
                            dropdownWidth: parent.width - taskModal.formLabelWidth - Theme.spacingM
                            options: taskModal.taskLists.map(c => taskModal._listLabel(c))
                            currentValue: taskModal.taskLists.length > 0 ? taskModal._listLabel(taskModal.taskLists[Math.min(taskModal.formCalendarIndex, taskModal.taskLists.length - 1)]) : ""
                            onValueChanged: value => {
                                for (let i = 0; i < taskModal.taskLists.length; i++) {
                                    if (taskModal._listLabel(taskModal.taskLists[i]) === value) {
                                        taskModal.formCalendarIndex = i;
                                        break;
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM
                        visible: !taskModal.createMode

                        DToggle {
                            checked: taskModal.formCompleted
                            onToggled: checked => taskModal.formCompleted = checked
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: I18n.tr("Completed", "task form toggle label for marking a task done")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
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

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingL
                anchors.right: actions.left
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                visible: taskModal.formError !== "" && !titleField.isError
                text: taskModal.formError
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                elide: Text.ElideRight
            }

            Row {
                id: actions
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DButton {
                    visible: !taskModal.createMode
                    text: taskModal.confirmDelete ? I18n.tr("Confirm delete", "task form button to confirm deletion") : I18n.tr("Delete", "task form button to delete the task")
                    iconName: "delete_outline"
                    backgroundColor: taskModal.confirmDelete ? Theme.errorContainer : "transparent"
                    textColor: taskModal.confirmDelete ? Theme.onErrorContainer : Theme.error
                    enabled: !taskModal.saving
                    onClicked: taskModal.removeTask()
                }

                DButton {
                    text: I18n.tr("Cancel", "task form button to discard changes")
                    backgroundColor: "transparent"
                    textColor: Theme.primary
                    enabled: !taskModal.saving
                    onClicked: taskModal.hide()
                }

                DButton {
                    text: I18n.tr("Save", "task form button to persist the task")
                    busy: taskModal.saving
                    backgroundColor: Theme.primary
                    textColor: Theme.primaryText
                    enabled: !taskModal.saving
                    onClicked: taskModal.save()
                }
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: taskModal.visible
        onActivated: {
            if (taskModal.confirmDelete) {
                taskModal.confirmDelete = false;
                return;
            }
            taskModal.hide();
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: taskModal
    }
}
