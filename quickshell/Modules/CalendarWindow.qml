import QtQuick
import Quickshell
import qs.Common
import qs.Modals
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import "../Common/EventUtils.js" as EventUtils

FloatingWindow {
    id: window

    signal hideRequested

    property bool isCompactMode: width < 760
    property bool menuVisible: false
    property string currentView: SettingsData.lastView
    onMaximizedChanged: focusScope.forceActiveFocus()
    onCurrentViewChanged: {
        SettingsData.lastView = currentView;
        rangeAnchorTime = 0;
        displayDate = alignedDisplayDate(displayDate);
        ensureSelectionVisible();
    }
    property date displayDate: new Date()
    property date selectedDate: new Date()
    // Live clock so the today highlight rolls over at midnight and after a
    // suspend/resume that crosses it. todayStart only changes on rollover,
    // so day-granular consumers don't recompute every minute.
    property date today: clock.date
    readonly property date todayStart: new Date(today.getFullYear(), today.getMonth(), today.getDate())
    property int selectedEventIndex: -1
    property int eventsVersion: 0
    property bool sidebarFocused: false
    property real rangeAnchorTime: 0
    property var pendingMove: null

    EventSelectionModel {
        id: eventSelection
    }

    readonly property real selectedDayTime: new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate()).getTime()
    readonly property real rangeStartTime: rangeAnchorTime > 0 ? Math.min(rangeAnchorTime, selectedDayTime) : 0
    readonly property real rangeEndTime: rangeAnchorTime > 0 ? Math.max(rangeAnchorTime, selectedDayTime) : 0

    function setSidebarFocused(focused) {
        sidebarFocused = focused;
        if (isCompactMode)
            menuVisible = focused;
    }

    readonly property bool sidebarVisible: isCompactMode ? menuVisible : !SettingsData.sidebarCollapsed

    function toggleSidebar() {
        if (isCompactMode)
            menuVisible = !menuVisible;
        else
            SettingsData.sidebarCollapsed = !SettingsData.sidebarCollapsed;
    }

    readonly property bool eventNavigation: {
        switch (currentView) {
        case "day":
        case "week":
        case "agenda":
            return true;
        default:
            return false;
        }
    }

    readonly property string selectedEventKey: {
        eventsVersion;
        if (selectedEventIndex < 0)
            return "";
        const evs = DankCalService.eventsForDay(selectedDate);
        if (selectedEventIndex >= evs.length)
            return "";
        return DankCalService.eventKey(evs[selectedEventIndex]);
    }

    onSelectedDateChanged: selectedEventIndex = -1

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Connections {
        target: DankCalService
        function onEventsUpdated() {
            window.eventsVersion++;
        }
        function onAddAccountRequested() {
            window.openAddAccount();
        }
    }

    function shiftDisplayDate(direction) {
        const d = new Date(displayDate);
        switch (currentView) {
        case "day":
            d.setDate(d.getDate() + direction);
            // The shown day is the selection; view switches re-anchor on it.
            selectedDate = d;
            break;
        case "week":
            d.setDate(d.getDate() + direction * 7);
            break;
        case "agenda":
            d.setDate(d.getDate() + direction * 7);
            break;
        default:
            d.setMonth(d.getMonth() + direction);
            break;
        }
        displayDate = d;
    }

    function shiftDisplayDays(days) {
        const d = new Date(displayDate);
        d.setDate(d.getDate() + days);
        displayDate = d;
    }

    function alignedDisplayDate(date) {
        switch (currentView) {
        case "week":
            return weekStart(date);
        default:
            return date;
        }
    }

    function goToToday() {
        rangeAnchorTime = 0;
        const t = new Date();
        displayDate = alignedDisplayDate(t);
        selectedDate = t;
    }

    function weekStart(date) {
        const d = new Date(date);
        d.setDate(d.getDate() - ((d.getDay() - SettingsData.effectiveFirstDayOfWeek + 7) % 7));
        d.setHours(0, 0, 0, 0);
        return d;
    }

    function ensureSelectionVisible() {
        switch (currentView) {
        case "day":
            displayDate = selectedDate;
            return;
        case "week":
            {
                const start = new Date(displayDate.getFullYear(), displayDate.getMonth(), displayDate.getDate());
                const sel = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate());
                const diff = Math.round((sel.getTime() - start.getTime()) / 86400000);
                if (diff < 0 || diff >= 7)
                    displayDate = weekStart(selectedDate);
                return;
            }
        case "agenda":
            {
                const start = new Date(displayDate.getFullYear(), displayDate.getMonth(), displayDate.getDate());
                const diff = Math.round((selectedDate.getTime() - start.getTime()) / 86400000);
                if (diff < 0 || diff >= 14)
                    displayDate = selectedDate;
                return;
            }
        default:
            if (selectedDate.getMonth() !== displayDate.getMonth() || selectedDate.getFullYear() !== displayDate.getFullYear())
                displayDate = selectedDate;
            return;
        }
    }

    function moveSelection(days, extend) {
        if (!extend)
            rangeAnchorTime = 0;
        else if (currentView === "month" && rangeAnchorTime === 0)
            rangeAnchorTime = selectedDayTime;
        const d = new Date(selectedDate);
        d.setDate(d.getDate() + days);
        selectedDate = d;
        ensureSelectionVisible();
    }

    // Walks events chronologically: within the selected day first, then into
    // the nearest day that has events. direction is +1 or -1.
    function moveEventSelection(direction) {
        rangeAnchorTime = 0;
        const evs = DankCalService.eventsForDay(selectedDate);
        const next = selectedEventIndex + direction;
        if (next >= 0 && next < evs.length) {
            selectedEventIndex = next;
            eventSelection.replace([evs[next]]);
            return;
        }
        for (let i = 1; i <= 366; i++) {
            const d = new Date(selectedDate);
            d.setDate(d.getDate() + direction * i);
            const list = DankCalService.eventsForDay(d);
            if (list.length === 0)
                continue;
            selectedDate = d;
            selectedEventIndex = direction > 0 ? 0 : list.length - 1;
            eventSelection.replace([list[selectedEventIndex]]);
            ensureSelectionVisible();
            return;
        }
    }

    function moveYear(direction) {
        rangeAnchorTime = 0;
        const d = new Date(selectedDate);
        d.setFullYear(d.getFullYear() + direction);
        selectedDate = d;
        ensureSelectionVisible();
    }

    function goToDate(date) {
        rangeAnchorTime = 0;
        selectedDate = date;
        displayDate = alignedDisplayDate(date);
    }

    function movePeriod(direction) {
        rangeAnchorTime = 0;
        switch (currentView) {
        case "day":
            moveSelection(direction);
            return;
        case "week":
        case "agenda":
            moveSelection(direction * 7);
            return;
        default:
            {
                const d = new Date(selectedDate);
                d.setMonth(d.getMonth() + direction);
                selectedDate = d;
                ensureSelectionVisible();
                return;
            }
        }
    }

    function jumpToEventDay(direction) {
        rangeAnchorTime = 0;
        for (let i = 1; i <= 366; i++) {
            const d = new Date(selectedDate);
            d.setDate(d.getDate() + direction * i);
            if (DankCalService.eventsForDay(d).length === 0)
                continue;
            selectedDate = d;
            ensureSelectionVisible();
            return;
        }
    }

    function activateSelection() {
        if (rangeAnchorTime > 0) {
            const start = new Date(rangeStartTime);
            const end = new Date(rangeEndTime);
            rangeAnchorTime = 0;
            openCreateEvent(start, end);
            return;
        }
        if (eventSelection.count === 1) {
            const selected = eventSelection.events();
            if (selected.length === 1) {
                openEventDetails(selected[0]);
                return;
            }
        }
        const evs = DankCalService.eventsForDay(selectedDate);
        if (selectedEventIndex >= 0 && selectedEventIndex < evs.length) {
            openEventDetails(evs[selectedEventIndex]);
            return;
        }
        if (evs.length > 0) {
            openEventDetails(evs[0]);
            return;
        }
        openCreateEvent();
    }

    function requestClose() {
        switch (SettingsData.closeBehavior) {
        case "quit":
            DankCalService.quit();
            return;
        default:
            window.hideRequested();
            return;
        }
    }

    function openSettings() {
        settingsLoader.active = true;
        settingsLoader.item.show();
    }

    function openAddAccount() {
        accountLoader.active = true;
        accountLoader.item.show();
    }

    signal calendarOpenFinished

    function openSubscribe(url) {
        accountLoader.active = true;
        accountLoader.item.showIcal(url);
    }

    function openImport(ics, name) {
        importLoader.active = true;
        importLoader.item.show(ics, name);
    }

    function openEventDetails(event) {
        eventLoader.active = true;
        eventLoader.item.show(event);
    }

    function handleEventClick(event, modifiers) {
        const selectionModifiers = modifiers || Qt.NoModifier;
        eventSelection.select(event, selectionModifiers);
        if ((selectionModifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier)) === 0)
            openEventDetails(event);
    }

    function handleEventContext(event, anchorItem, x, y) {
        const position = anchorItem.mapToItem(focusScope, x, y);
        eventMenu.showForEvent(event, focusScope, position.x, position.y);
    }

    function handleDayContext(day, anchorItem, x, y) {
        const position = anchorItem.mapToItem(focusScope, x, y);
        eventMenu.showForDay(day, focusScope, position.x, position.y);
    }

    function requestEventMove(event, targetDay) {
        requestEventShift(event, EventUtils.daysBetween(event.start, targetDay), 0);
    }

    function requestEventShift(event, dayOffset, minuteOffset) {
        eventSelection.ensureSelected(event);
        const movesSeries = eventSelection.events(event).some(ev => (ev.recurringId || "") !== "" || (ev.recurrence || []).length > 0);
        if (!movesSeries || !eventSelection.allWritable(event) || (dayOffset === 0 && minuteOffset === 0)) {
            eventSelection.moveBy(event, dayOffset, minuteOffset);
            return;
        }
        pendingMove = {
            "event": event,
            "dayOffset": dayOffset,
            "minuteOffset": minuteOffset
        };
        moveEventsConfirm.show({
            title: I18n.tr("Move recurring events?", "confirmation title before moving events that repeat"),
            message: I18n.tr("Moving a recurring event moves its entire series.", "confirmation body before moving events that repeat"),
            confirmText: I18n.tr("Move", "confirmation button for moving recurring events")
        });
    }

    function requestEventDelete(event) {
        eventSelection.ensureSelected(event);
        const count = eventSelection.count;
        deleteEventsConfirm.show({
            title: count === 1 ? I18n.tr("Delete event?", "confirmation title for deleting one event") : I18n.tr("Delete %1 events?", "confirmation title for deleting multiple events; %1 is event count").arg(count),
            message: count === 1 ? I18n.tr("This event will be deleted from its calendar.", "confirmation body for deleting one event") : I18n.tr("These events will be deleted from their calendars. Recurring selections delete only the selected occurrences.", "confirmation body for deleting multiple events"),
            confirmText: count === 1 ? I18n.tr("Delete event", "confirmation button for deleting one event") : I18n.tr("Delete %1 events", "confirmation button for deleting multiple events; %1 is event count").arg(count),
            danger: true
        });
    }

    function openCreateEvent(date, endDate) {
        eventLoader.active = true;
        eventLoader.item.showCreate(date || selectedDate, endDate);
    }

    function openCreateTimedEvent(start, end) {
        eventLoader.active = true;
        eventLoader.item.showCreateTimed(start, end);
    }

    function openTaskDetails(task) {
        taskLoader.active = true;
        taskLoader.item.show(task);
    }

    function openCreateTask() {
        taskLoader.active = true;
        taskLoader.item.showCreate();
    }

    function openSearch() {
        searchLoader.active = true;
        searchLoader.item.show();
    }

    function openGoToDate() {
        goToLoader.active = true;
        goToLoader.item.show(selectedDate);
    }

    function goToEvent(event) {
        displayDate = alignedDisplayDate(event.start);
        selectedDate = event.start;
        openEventDetails(event);
    }

    function openEventByUid(uid, start) {
        const loaded = DankCalService.findEvent(uid, start);
        if (loaded) {
            goToEvent(loaded);
            return;
        }
        DankCalService.fetchEvent(uid, start, event => {
            if (event)
                goToEvent(event);
        });
    }

    onDisplayDateChanged: DankCalService.focusDate = displayDate
    Component.onCompleted: {
        displayDate = alignedDisplayDate(displayDate);
        DankCalService.focusDate = displayDate;
    }

    onClosed: window.requestClose()

    title: I18n.tr("Calendar", "main window title")
    minimumSize: Qt.size(560, 400)
    implicitWidth: 1100
    implicitHeight: screen ? Math.min(820, screen.height - 100) : 820
    color: Theme.windowSurface
    surfaceFormat.opaque: false
    visible: true

    WindowBlur {
        targetWindow: window
        blurEnabled: Theme.translucentWindows
        blurWidth: window.width
        blurHeight: window.height
    }

    onIsCompactModeChanged: menuVisible = false

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true

        LayoutMirroring.enabled: I18n.isRtl
        LayoutMirroring.childrenInherit: true

        Component.onCompleted: forceActiveFocus()

        Shortcut {
            sequences: [StandardKey.Find]
            onActivated: window.openSearch()
        }

        Keys.onPressed: event => {
            if (helpOverlay.visible) {
                switch (event.key) {
                case Qt.Key_Escape:
                case Qt.Key_Question:
                case Qt.Key_Slash:
                    helpOverlay.visible = false;
                    break;
                }
                event.accepted = true;
                return;
            }

            if (window.sidebarFocused) {
                switch (event.key) {
                case Qt.Key_Escape:
                case Qt.Key_S:
                    window.setSidebarFocused(false);
                    event.accepted = true;
                    return;
                }
                sidebar.handleKey(event);
                if (event.accepted)
                    return;
            }

            const ctrl = event.modifiers & Qt.ControlModifier;
            const shift = event.modifiers & Qt.ShiftModifier;

            switch (event.key) {
            case Qt.Key_T:
                window.goToToday();
                break;
            case Qt.Key_G:
                window.openGoToDate();
                break;
            case Qt.Key_H:
            case Qt.Key_Left:
                window.moveSelection(I18n.isRtl ? 1 : -1, shift);
                break;
            case Qt.Key_L:
            case Qt.Key_Right:
                window.moveSelection(I18n.isRtl ? -1 : 1, shift);
                break;
            case Qt.Key_J:
            case Qt.Key_Down:
                if (window.eventNavigation)
                    window.moveEventSelection(1);
                else
                    window.moveSelection(7, shift);
                break;
            case Qt.Key_K:
            case Qt.Key_Up:
                if (window.eventNavigation)
                    window.moveEventSelection(-1);
                else
                    window.moveSelection(-7, shift);
                break;
            case Qt.Key_BracketLeft:
            case Qt.Key_PageUp:
                window.movePeriod(-1);
                break;
            case Qt.Key_BracketRight:
            case Qt.Key_PageDown:
                window.movePeriod(1);
                break;
            case Qt.Key_BraceLeft:
                window.moveYear(-1);
                break;
            case Qt.Key_BraceRight:
                window.moveYear(1);
                break;
            case Qt.Key_Escape:
                if (window.rangeAnchorTime > 0) {
                    window.rangeAnchorTime = 0;
                    break;
                }
                if (eventSelection.hasSelection) {
                    eventSelection.clear();
                    window.selectedEventIndex = -1;
                    break;
                }
                if (window.selectedEventIndex < 0) {
                    event.accepted = false;
                    return;
                }
                window.selectedEventIndex = -1;
                break;
            case Qt.Key_Tab:
                window.jumpToEventDay(1);
                break;
            case Qt.Key_Backtab:
                window.jumpToEventDay(-1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                window.activateSelection();
                break;
            case Qt.Key_M:
                window.currentView = "month";
                break;
            case Qt.Key_W:
                window.currentView = "week";
                break;
            case Qt.Key_D:
                if (ctrl) {
                    if (!eventSelection.hasSelection) {
                        event.accepted = false;
                        return;
                    }
                    eventSelection.duplicate(shift ? 1 : 0);
                    break;
                }
                window.currentView = "day";
                break;
            case Qt.Key_A:
                if (ctrl) {
                    eventSelection.selectDay(window.selectedDate);
                    break;
                }
                window.currentView = "agenda";
                break;
            case Qt.Key_S:
                window.setSidebarFocused(true);
                break;
            case Qt.Key_1:
                if (!ctrl) {
                    event.accepted = false;
                    return;
                }
                window.currentView = "day";
                break;
            case Qt.Key_2:
                if (!ctrl) {
                    event.accepted = false;
                    return;
                }
                window.currentView = "week";
                break;
            case Qt.Key_3:
                if (!ctrl) {
                    event.accepted = false;
                    return;
                }
                window.currentView = "month";
                break;
            case Qt.Key_4:
                if (!ctrl) {
                    event.accepted = false;
                    return;
                }
                window.currentView = "agenda";
                break;
            case Qt.Key_5:
                if (!ctrl || !SettingsData.showTasks || !DankCalService.hasTaskLists()) {
                    event.accepted = false;
                    return;
                }
                window.currentView = "tasks";
                break;
            case Qt.Key_C:
                if (ctrl) {
                    if (!eventSelection.hasSelection) {
                        event.accepted = false;
                        return;
                    }
                    eventSelection.copy();
                    break;
                }
                window.openCreateEvent();
                break;
            case Qt.Key_N:
                if (!ctrl) {
                    event.accepted = false;
                    return;
                }
                window.openCreateEvent();
                break;
            case Qt.Key_V:
                if (!ctrl || eventSelection.clipboardCount === 0) {
                    event.accepted = false;
                    return;
                }
                eventSelection.paste(window.selectedDate);
                break;
            case Qt.Key_X:
                if (!ctrl || !eventSelection.hasSelection || !eventSelection.allWritable()) {
                    event.accepted = false;
                    return;
                }
                eventSelection.cut();
                break;
            case Qt.Key_Delete:
            case Qt.Key_Backspace:
                if (!eventSelection.hasSelection || !eventSelection.allWritable()) {
                    event.accepted = false;
                    return;
                }
                window.requestEventDelete(eventSelection.events()[0]);
                break;
            case Qt.Key_Menu:
                if (!eventSelection.hasSelection) {
                    event.accepted = false;
                    return;
                }
                {
                    const selected = eventSelection.events();
                    if (selected.length > 0)
                        eventMenu.showForEvent(selected[0], focusScope, focusScope.width / 2, focusScope.height / 2);
                }
                break;
            case Qt.Key_Slash:
                if (shift) {
                    helpOverlay.visible = true;
                    break;
                }
                window.openSearch();
                break;
            case Qt.Key_Question:
                helpOverlay.visible = true;
                break;
            case Qt.Key_P:
                if (!ctrl) {
                    event.accepted = false;
                    return;
                }
                window.openSearch();
                break;
            case Qt.Key_Comma:
                if (!ctrl) {
                    event.accepted = false;
                    return;
                }
                window.openSettings();
                break;
            default:
                event.accepted = false;
                return;
            }
            event.accepted = true;
        }

        Column {
            anchors.fill: parent
            spacing: 0

            DWindowHeader {
                id: header
                width: parent.width
                z: 10
                controls: windowControls
                title: I18n.tr("Calendar", "main window title bar text")
                onCloseRequested: window.requestClose()
            }

            Item {
                id: bodyArea
                width: parent.width
                height: parent.height - header.height
                clip: true

                readonly property real minSidebarWidth: 200
                readonly property real maxSidebarWidth: Math.max(minSidebarWidth, width - 360)
                property real liveSidebarWidth: SettingsData.sidebarWidth

                Connections {
                    target: SettingsData
                    function onSidebarWidthChanged() {
                        if (!sidebarResizer.dragging)
                            bodyArea.liveSidebarWidth = SettingsData.sidebarWidth;
                    }
                }

                CalendarSidebar {
                    id: sidebar
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: window.isCompactMode ? parent.width : Math.max(bodyArea.minSidebarWidth, Math.min(bodyArea.maxSidebarWidth, bodyArea.liveSidebarWidth))
                    visible: window.sidebarVisible
                    currentView: window.currentView
                    selectedDate: window.selectedDate
                    today: window.todayStart
                    keyboardActive: window.sidebarFocused
                    onViewChanged: view => {
                        window.currentView = view;
                        window.sidebarFocused = false;
                        if (window.isCompactMode)
                            window.menuVisible = false;
                    }
                    onTodayRequested: window.goToToday()
                    onCreateEventRequested: window.openCreateEvent()
                    onCreateTaskRequested: window.openCreateTask()
                    onTaskClicked: task => window.openTaskDetails(task)
                    onAddAccountRequested: window.openAddAccount()
                }

                Item {
                    id: sidebarResizer
                    anchors.left: sidebar.right
                    anchors.leftMargin: -width / 2
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Theme.spacingS
                    z: 10
                    visible: !window.isCompactMode && window.sidebarVisible

                    property bool dragging: false
                    property real pressX: 0
                    property real startWidth: 0

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Theme.outlineWidthFocused
                        height: parent.height
                        radius: Theme.fullRadius(width, height)
                        color: Theme.primary
                        visible: resizeArea.containsMouse || sidebarResizer.dragging
                    }

                    MouseArea {
                        id: resizeArea
                        anchors.fill: parent
                        anchors.leftMargin: -Theme.spacingXS
                        anchors.rightMargin: -Theme.spacingXS
                        hoverEnabled: true
                        cursorShape: Qt.SizeHorCursor
                        onPressed: mouse => {
                            sidebarResizer.dragging = true;
                            sidebarResizer.pressX = mapToItem(bodyArea, mouse.x, 0).x;
                            sidebarResizer.startWidth = sidebar.width;
                        }
                        onPositionChanged: mouse => {
                            if (!sidebarResizer.dragging)
                                return;
                            const px = mapToItem(bodyArea, mouse.x, 0).x;
                            const dir = I18n.isRtl ? -1 : 1;
                            const w = sidebarResizer.startWidth + dir * (px - sidebarResizer.pressX);
                            bodyArea.liveSidebarWidth = Math.max(bodyArea.minSidebarWidth, Math.min(bodyArea.maxSidebarWidth, w));
                        }
                        onReleased: {
                            sidebarResizer.dragging = false;
                            SettingsData.sidebarWidth = Math.round(bodyArea.liveSidebarWidth);
                        }
                        onCanceled: {
                            sidebarResizer.dragging = false;
                            SettingsData.sidebarWidth = Math.round(bodyArea.liveSidebarWidth);
                        }
                    }
                }

                Rectangle {
                    anchors.left: window.sidebarVisible ? sidebar.right : parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: window.sidebarVisible ? 0 : Theme.windowInset
                    anchors.rightMargin: Theme.windowInset
                    anchors.bottomMargin: Theme.windowInset
                    radius: Theme.cornerRadiusL
                    color: Theme.floatingWindowPaneSurface
                    clip: true

                    CalendarContent {
                        anchors.fill: parent
                        menuButtonVisible: true
                        currentView: window.currentView
                        displayDate: window.displayDate
                        selectedDate: window.selectedDate
                        selectedEventKey: window.selectedEventKey
                        selectedEventKeys: eventSelection.selectedKeys
                        today: window.today
                        todayStart: window.todayStart
                        rangeStartTime: window.rangeStartTime
                        rangeEndTime: window.rangeEndTime
                        onMenuRequested: window.toggleSidebar()
                        onTodayRequested: window.goToToday()
                        onPreviousRequested: window.shiftDisplayDate(-1)
                        onNextRequested: window.shiftDisplayDate(1)
                        onShiftDaysRequested: days => window.shiftDisplayDays(days)
                        onSettingsRequested: window.openSettings()
                        onSearchRequested: window.openSearch()
                        onGoToDateRequested: window.openGoToDate()
                        onDaySelected: day => {
                            window.rangeAnchorTime = 0;
                            window.selectedDate = day;
                        }
                        onDayActivated: day => {
                            window.rangeAnchorTime = 0;
                            window.selectedDate = day;
                            window.openCreateEvent(day);
                        }
                        onCreateRangeRequested: (startDay, endDay) => {
                            window.selectedDate = startDay;
                            window.openCreateEvent(startDay, endDay);
                        }
                        onCreateTimedRequested: (start, end) => {
                            window.rangeAnchorTime = 0;
                            window.selectedDate = start;
                            window.openCreateTimedEvent(start, end);
                        }
                        onViewDayRequested: day => {
                            window.selectedDate = day;
                            window.displayDate = day;
                            window.currentView = "day";
                        }
                        onEventClicked: (ev, modifiers) => window.handleEventClick(ev, modifiers)
                        onEventContextRequested: (ev, anchorItem, x, y) => window.handleEventContext(ev, anchorItem, x, y)
                        onDayContextRequested: (day, anchorItem, x, y) => window.handleDayContext(day, anchorItem, x, y)
                        onEventDropRequested: (ev, targetDay) => window.requestEventMove(ev, targetDay)
                        onEventRescheduleRequested: (ev, dayOffset, minuteOffset) => window.requestEventShift(ev, dayOffset, minuteOffset)
                        onTaskClicked: task => window.openTaskDetails(task)
                        onCreateTaskRequested: window.openCreateTask()
                    }
                }
            }
        }

        KeyboardShortcutsOverlay {
            id: helpOverlay
            visible: false
            z: 100
            onDismissed: visible = false
        }

        EventSelectionBar {
            id: selectionBar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spacingL
            width: Math.min(implicitWidth, parent.width - Theme.spacingL * 2)
            z: 90
            controller: eventSelection
            onDeleteRequested: {
                const selected = eventSelection.events();
                if (selected.length > 0)
                    window.requestEventDelete(selected[0]);
            }
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: window
    }

    Loader {
        id: settingsLoader
        active: false
        sourceComponent: Component {
            SettingsModal {
                parentWindow: window
                onAddAccountRequested: window.openAddAccount()
            }
        }
    }

    Loader {
        id: accountLoader
        active: false
        sourceComponent: Component {
            AccountAddModal {
                parentWindow: window
                onVisibleChanged: {
                    if (!visible && (!importLoader.item || !importLoader.item.visible))
                        window.calendarOpenFinished();
                }
            }
        }
    }

    Loader {
        id: importLoader
        active: false
        sourceComponent: Component {
            ImportIcsModal {
                parentWindow: window
                onVisibleChanged: {
                    if (!visible)
                        window.calendarOpenFinished();
                }
                onOpenEventRequested: event => window.openEventDetails(event)
                onAddCalendarRequested: window.openAddAccount()
            }
        }
    }

    Loader {
        id: eventLoader
        active: false
        sourceComponent: Component {
            EventDetailsModal {
                parentWindow: window
                onAddCalendarRequested: window.openAddAccount()
            }
        }
    }

    Loader {
        id: taskLoader
        active: false
        sourceComponent: Component {
            TaskDetailsModal {
                parentWindow: window
                onAddCalendarRequested: window.openAddAccount()
            }
        }
    }

    Loader {
        id: searchLoader
        active: false
        sourceComponent: Component {
            SearchModal {
                onEventSelected: ev => window.goToEvent(ev)
            }
        }
    }

    Loader {
        id: goToLoader
        active: false
        sourceComponent: Component {
            GoToDateDialog {
                onDateSelected: date => window.goToDate(date)
            }
        }
    }

    EventContextMenu {
        id: eventMenu
        controller: eventSelection
        selectedDay: window.selectedDate
        onOpenRequested: event => window.openEventDetails(event)
        onCreateRequested: day => window.openCreateEvent(day)
        onDeleteRequested: event => window.requestEventDelete(event)
        onMoveRequested: (event, day) => window.requestEventMove(event, day)
    }

    ConfirmDialog {
        id: deleteEventsConfirm
        onConfirmed: eventSelection.remove()
    }

    ConfirmDialog {
        id: moveEventsConfirm
        onConfirmed: {
            if (!window.pendingMove)
                return;
            eventSelection.moveBy(window.pendingMove.event, window.pendingMove.dayOffset, window.pendingMove.minuteOffset);
            window.pendingMove = null;
        }
    }

    Toast {
        anchors.fill: parent
    }
}
