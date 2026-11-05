import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import "views"

Item {
    id: root

    property string currentView: "month"
    property date displayDate: new Date()
    property date selectedDate: new Date()
    property string selectedEventKey: ""
    property var selectedEventKeys: []
    property date today: new Date()
    property date todayStart: new Date()
    property real rangeStartTime: 0
    property real rangeEndTime: 0
    property bool menuButtonVisible: false

    signal menuRequested
    signal todayRequested
    signal previousRequested
    signal nextRequested
    signal shiftDaysRequested(int days)
    signal createEventRequested
    signal eventClicked(var event, int modifiers)
    signal eventContextRequested(var event, var anchorItem, real x, real y)
    signal dayContextRequested(date day, var anchorItem, real x, real y)
    signal eventDropRequested(var event, date targetDay)
    signal eventRescheduleRequested(var event, int dayOffset, int minuteOffset)
    signal createTaskRequested
    signal taskClicked(var task)
    signal settingsRequested
    signal searchRequested
    signal goToDateRequested
    signal daySelected(date day)
    signal dayActivated(date day)
    signal viewDayRequested(date day)
    signal createRangeRequested(date startDay, date endDay)
    signal createTimedRequested(date start, date end)

    function headerTitle() {
        switch (currentView) {
        case "day":
            return SettingsData.formatDate(displayDate, "dddd, MMMM d, yyyy");
        case "week":
            return SettingsData.monthName(displayDate.getMonth()) + " " + displayDate.getFullYear();
        case "agenda":
            return I18n.tr("Agenda", "header title when the agenda view is active");
        case "tasks":
            return I18n.tr("Tasks", "header title when the tasks view is active");
        default:
            return SettingsData.monthName(displayDate.getMonth()) + " " + displayDate.getFullYear();
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Item {
            id: toolbar
            readonly property bool stacked: navigationRow.width + titleButton.implicitWidth + actionsRow.width + Theme.spacingL * 2 + Theme.spacingS * 2 > width
            width: parent.width
            height: Theme.buttonHeightM * (stacked ? 2 : 1)

            Row {
                id: navigationRow
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingL
                y: (Theme.buttonHeightM - height) / 2
                spacing: Theme.spacingS

                DActionButton {
                    visible: root.menuButtonVisible
                    iconName: "menu"
                    iconColor: Theme.surfaceText
                    buttonSize: Theme.buttonHeightS
                    focusPolicy: Qt.NoFocus
                    Accessible.name: I18n.tr("Toggle sidebar", "toolbar button that shows or hides the sidebar")
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.menuRequested()
                }

                DButton {
                    text: I18n.tr("Today", "header button that jumps to the current date")
                    iconName: "today"
                    buttonHeight: Theme.buttonHeightS
                    variant: "tonal"
                    focusPolicy: Qt.NoFocus
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.todayRequested()
                }

                DActionButton {
                    iconName: I18n.isRtl ? "chevron_right" : "chevron_left"
                    iconColor: Theme.surfaceText
                    buttonSize: Theme.buttonHeightS
                    focusPolicy: Qt.NoFocus
                    Accessible.name: I18n.tr("Previous", "toolbar button that moves to the previous period")
                    onClicked: root.previousRequested()
                    anchors.verticalCenter: parent.verticalCenter
                }

                DActionButton {
                    iconName: I18n.isRtl ? "chevron_left" : "chevron_right"
                    iconColor: Theme.surfaceText
                    buttonSize: Theme.buttonHeightS
                    focusPolicy: Qt.NoFocus
                    Accessible.name: I18n.tr("Next", "toolbar button that moves to the next period")
                    onClicked: root.nextRequested()
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledRect {
                id: titleButton
                implicitWidth: headerTitleText.implicitWidth + Theme.spacingM * 2
                anchors.left: toolbar.stacked ? parent.left : navigationRow.right
                anchors.leftMargin: toolbar.stacked ? Theme.spacingL : Theme.spacingS
                anchors.right: actionsRow.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: actionsRow.verticalCenter
                height: Theme.buttonHeightS
                radius: Theme.cornerRadiusS

                StyledText {
                    id: headerTitleText
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    text: root.headerTitle()
                    font.pixelSize: Theme.fontSizeXLarge
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }

                StateLayer {
                    stateColor: Theme.surfaceText
                    tooltipText: headerTitleText.truncated ? headerTitleText.text : ""
                    onClicked: root.goToDateRequested()
                }
            }

            Row {
                id: actionsRow
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingL
                anchors.bottom: parent.bottom
                anchors.bottomMargin: (Theme.buttonHeightM - height) / 2
                spacing: Theme.spacingXS

                DActionButton {
                    id: refreshButton

                    property bool loading: DankCalService.eventsLoading
                    readonly property bool syncing: loading || spinnerHold.running

                    iconName: syncing ? "" : "refresh"
                    iconColor: Theme.surfaceText
                    buttonSize: Theme.buttonHeightS
                    focusPolicy: Qt.NoFocus
                    Accessible.name: I18n.tr("Sync now", "account context menu action to sync the account")
                    enabled: DankCalService.connected
                    onClicked: DankCalService.refreshAll()
                    onLoadingChanged: {
                        if (loading)
                            spinnerHold.restart();
                    }

                    Timer {
                        id: spinnerHold
                        interval: 1200
                    }

                    DSpinner {
                        anchors.centerIn: parent
                        size: Theme.iconSizeMedium
                        color: Theme.primary
                        visible: refreshButton.syncing
                    }
                }

                DActionButton {
                    iconName: "search"
                    iconColor: Theme.surfaceText
                    buttonSize: Theme.buttonHeightS
                    focusPolicy: Qt.NoFocus
                    Accessible.name: I18n.tr("Search events", "search modal input placeholder")
                    onClicked: root.searchRequested()
                }

                DActionButton {
                    iconName: "settings"
                    iconColor: Theme.surfaceText
                    buttonSize: Theme.buttonHeightS
                    focusPolicy: Qt.NoFocus
                    Accessible.name: I18n.tr("Settings", "settings window header title")
                    onClicked: root.settingsRequested()
                }
            }
        }

        Item {
            width: parent.width
            height: parent.height - toolbar.height

            Loader {
                id: viewLoader
                anchors.fill: parent
                anchors.margins: Theme.spacingM

                sourceComponent: {
                    switch (root.currentView) {
                    case "day":
                        return dayComponent;
                    case "week":
                        return weekComponent;
                    case "agenda":
                        return agendaComponent;
                    case "tasks":
                        return tasksComponent;
                    default:
                        return monthComponent;
                    }
                }
            }

            Component {
                id: monthComponent
                MonthView {
                    displayDate: root.displayDate
                    today: root.today
                    selectedDate: root.selectedDate
                    selectedEventKeys: root.selectedEventKeys
                    keyRangeStart: root.rangeStartTime
                    keyRangeEnd: root.rangeEndTime
                    onDaySelected: day => root.daySelected(day)
                    onDayActivated: day => root.dayActivated(day)
                    onViewDayRequested: day => root.viewDayRequested(day)
                    onCreateRangeRequested: (startDay, endDay) => root.createRangeRequested(startDay, endDay)
                    onEventClicked: (ev, modifiers) => root.eventClicked(ev, modifiers)
                    onEventContextRequested: (ev, anchorItem, x, y) => root.eventContextRequested(ev, anchorItem, x, y)
                    onDayContextRequested: (day, anchorItem, x, y) => root.dayContextRequested(day, anchorItem, x, y)
                    onEventDropRequested: (ev, targetDay) => root.eventDropRequested(ev, targetDay)
                    onPreviousRequested: root.previousRequested()
                    onNextRequested: root.nextRequested()
                }
            }

            Component {
                id: weekComponent
                WeekView {
                    displayDate: root.displayDate
                    today: root.today
                    selectedDate: root.selectedDate
                    selectedEventKey: root.selectedEventKey
                    selectedEventKeys: root.selectedEventKeys
                    onEventClicked: (ev, modifiers) => root.eventClicked(ev, modifiers)
                    onEventContextRequested: (ev, anchorItem, x, y) => root.eventContextRequested(ev, anchorItem, x, y)
                    onDayContextRequested: (day, anchorItem, x, y) => root.dayContextRequested(day, anchorItem, x, y)
                    onEventDropRequested: (ev, targetDay) => root.eventDropRequested(ev, targetDay)
                    onEventRescheduleRequested: (ev, dayOffset, minuteOffset) => root.eventRescheduleRequested(ev, dayOffset, minuteOffset)
                    onShiftDaysRequested: days => root.shiftDaysRequested(days)
                    onCreateTimedRequested: (start, end) => root.createTimedRequested(start, end)
                }
            }

            Component {
                id: dayComponent
                DayView {
                    displayDate: root.displayDate
                    today: root.today
                    selectedEventKey: root.selectedEventKey
                    selectedEventKeys: root.selectedEventKeys
                    onEventClicked: (ev, modifiers) => root.eventClicked(ev, modifiers)
                    onEventContextRequested: (ev, anchorItem, x, y) => root.eventContextRequested(ev, anchorItem, x, y)
                    onDayContextRequested: (day, anchorItem, x, y) => root.dayContextRequested(day, anchorItem, x, y)
                    onPreviousRequested: root.previousRequested()
                    onNextRequested: root.nextRequested()
                    onCreateTimedRequested: (start, end) => root.createTimedRequested(start, end)
                }
            }

            Component {
                id: agendaComponent
                AgendaView {
                    displayDate: root.displayDate
                    today: root.todayStart
                    selectedEventKey: root.selectedEventKey
                    selectedEventKeys: root.selectedEventKeys
                    onEventClicked: (ev, modifiers) => root.eventClicked(ev, modifiers)
                    onEventContextRequested: (ev, anchorItem, x, y) => root.eventContextRequested(ev, anchorItem, x, y)
                    onDayContextRequested: (day, anchorItem, x, y) => root.dayContextRequested(day, anchorItem, x, y)
                }
            }

            Component {
                id: tasksComponent
                TasksView {
                    today: root.todayStart
                    onTaskClicked: task => root.taskClicked(task)
                    onCreateTaskRequested: root.createTaskRequested()
                }
            }
        }
    }
}
