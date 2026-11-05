import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

Item {
    id: root

    property date displayDate: new Date()
    property date today: new Date()
    property int tasksVersion: 0

    signal taskClicked(var task)
    signal createTaskRequested

    Connections {
        target: DankCalService
        function onTasksUpdated() {
            root.tasksVersion++;
        }
    }

    function dueLabel(task) {
        if (!task.due)
            return "";
        const todayStart = new Date(root.today.getFullYear(), root.today.getMonth(), root.today.getDate());
        const diff = Math.round((task.due.getTime() - todayStart.getTime()) / 86400000);
        switch (diff) {
        case 0:
            return I18n.tr("Today", "due-date label on a task card");
        case 1:
            return I18n.tr("Tomorrow", "due-date label on a task card");
        case -1:
            return I18n.tr("Yesterday", "due-date label on a task card");
        default:
            return SettingsData.formatDate(task.due, "MMM d");
        }
    }

    readonly property var sections: {
        tasksVersion;
        today;
        const buckets = DankCalService.taskBuckets();
        const order = [
            {
                key: "overdue",
                label: I18n.tr("Overdue", "tasks view section header for past-due tasks"),
                overdue: true
            },
            {
                key: "today",
                label: I18n.tr("Today", "tasks view section header for tasks due today"),
                overdue: false
            },
            {
                key: "upcoming",
                label: I18n.tr("Upcoming", "tasks view section header for tasks due later"),
                overdue: false
            },
            {
                key: "someday",
                label: I18n.tr("No due date", "tasks view section header for tasks without a due date"),
                overdue: false
            }
        ];
        const out = [];
        for (let i = 0; i < order.length; i++) {
            const items = buckets[order[i].key];
            if (items.length === 0)
                continue;
            out.push({
                "label": order[i].label,
                "overdue": order[i].overdue,
                "tasks": items
            });
        }
        const completed = DankCalService.visibleTasks(true).filter(t => t.completed);
        if (completed.length > 0)
            out.push({
                "label": I18n.tr("Completed", "tasks view section header for finished tasks"),
                "overdue": false,
                "tasks": completed
            });
        return out;
    }

    DButton {
        id: addButton
        anchors.top: parent.top
        anchors.right: parent.right
        text: I18n.tr("Add task", "tasks view button to create a new task")
        iconName: "add"
        buttonHeight: Theme.buttonHeightS
        focusPolicy: Qt.NoFocus
        enabled: DankCalService.taskListCalendars().length > 0
        onClicked: root.createTaskRequested()
    }

    DFlickable {
        anchors.top: addButton.bottom
        anchors.topMargin: Theme.spacingM
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: tasksColumn.implicitHeight
        clip: true

        Column {
            id: tasksColumn
            width: root.width
            spacing: Theme.spacingM

            StyledText {
                visible: root.sections.length === 0
                text: DankCalService.connected ? I18n.tr("No tasks yet", "tasks view empty state") : I18n.tr("Waiting for the dankcalendar daemon...", "tasks view placeholder while the daemon is not connected")
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                width: parent.width
            }

            Repeater {
                model: ScriptModel {
                    values: root.sections
                }

                Column {
                    id: section
                    required property var modelData
                    width: root.width
                    spacing: Theme.spacingS

                    StyledText {
                        text: section.modelData.label
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Theme.fontWeightMedium
                        color: section.modelData.overdue ? Theme.error : Theme.surfaceText
                        width: parent.width
                    }

                    Repeater {
                        model: ScriptModel {
                            values: section.modelData.tasks
                        }

                        StyledRect {
                            id: card
                            required property var modelData
                            readonly property bool overdue: section.modelData.overdue
                            width: root.width
                            height: Math.max(60, contentRow.implicitHeight + Theme.spacingM * 2)
                            color: Theme.surfaceContainerLow
                            radius: Theme.cornerRadiusM

                            // Declared before contentRow so the checkbox's own
                            // StateLayer, on top, wins clicks in its area while
                            // this one handles the rest of the card.
                            StateLayer {
                                stateColor: Theme.surfaceText
                                onClicked: root.taskClicked(card.modelData)
                            }

                            Row {
                                id: contentRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingM

                                Rectangle {
                                    id: checkbox
                                    width: 22
                                    height: 22
                                    radius: Theme.fullRadius(width, height)
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: card.modelData.completed ? card.modelData.color : "transparent"
                                    border.color: card.modelData.color
                                    border.width: 2

                                    DIcon {
                                        anchors.centerIn: parent
                                        name: "check"
                                        size: Theme.iconSizeSmall
                                        color: Theme.primaryText
                                        visible: card.modelData.completed
                                    }

                                    StateLayer {
                                        stateColor: card.modelData.color
                                        cornerRadius: parent.radius
                                        enabled: !card.modelData.readOnly
                                        onClicked: DankCalService.completeTaskWithUndo(card.modelData)
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 22 - priorityFlag.width - Theme.spacingM * 2
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: card.modelData.title
                                        font.pixelSize: Theme.fontSizeLarge
                                        font.weight: Theme.fontWeightMedium
                                        font.strikeout: card.modelData.completed
                                        color: card.modelData.completed ? Theme.surfaceVariantText : Theme.surfaceText
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }

                                    Row {
                                        spacing: Theme.spacingS

                                        StyledText {
                                            text: root.dueLabel(card.modelData)
                                            visible: text !== ""
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: card.overdue ? Theme.error : Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Rectangle {
                                            width: 8
                                            height: 8
                                            radius: Theme.fullRadius(width, height)
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: card.modelData.color
                                        }

                                        StyledText {
                                            text: card.modelData.accountSummary !== "" ? card.modelData.calendar + "  ·  " + card.modelData.accountSummary : card.modelData.calendar
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        DIcon {
                                            visible: card.modelData.recurring
                                            name: "repeat"
                                            size: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                DIcon {
                                    id: priorityFlag
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "flag"
                                    size: Theme.chipIconSize
                                    color: Theme.error
                                    visible: card.modelData.priority > 0 && card.modelData.priority <= 4
                                    width: visible ? Theme.chipIconSize : 0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
