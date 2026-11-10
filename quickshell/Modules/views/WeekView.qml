import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import "../../Common/EventUtils.js" as EventUtils

Item {
    id: root

    property date displayDate: new Date()
    property date today: new Date()
    property date selectedDate: new Date()
    property string selectedEventKey: ""
    property var selectedEventKeys: []
    property int eventsVersion: 0
    property bool eventPointerDown: false
    property bool eventDragging: false
    property var draggedEvent: null
    property real dragTargetTime: 0
    property point dragPosition: Qt.point(0, 0)
    property real dragSourceTime: 0
    property bool dragOnGrid: false
    property int dragBlockMinutes: 0
    property real dragPointerMinutes: 0
    property int dragMinuteOffset: 0
    readonly property int slotMinutes: 15
    readonly property int dragDayOffset: dragTargetTime > 0 ? Math.round((dragTargetTime - dragSourceTime) / 86400000) : 0
    readonly property real dragPreviewTop: (dragBlockMinutes + dragMinuteOffset) / 60 * hourHeight
    readonly property string dragPreviewLabel: dragOnGrid && draggedEvent ? SettingsData.formatTime(EventUtils.shiftDateTime(draggedEvent.start, dragDayOffset, dragMinuteOffset)) : ""

    signal eventClicked(var event, int modifiers)
    signal eventContextRequested(var event, var anchorItem, real x, real y)
    signal dayContextRequested(date day, var anchorItem, real x, real y)
    signal eventDropRequested(var event, date targetDay)
    signal eventRescheduleRequested(var event, int dayOffset, int minuteOffset)
    signal shiftDaysRequested(int days)
    signal createTimedRequested(date start, date end)
    signal createRangeRequested(date startDay, date endDay)

    function isEventSelected(event) {
        const key = DankCalService.eventKey(event);
        return selectedEventKey === key || selectedEventKeys.indexOf(key) !== -1;
    }

    function dayTimeAt(px) {
        if (px < timeColumnWidth || px >= width)
            return 0;
        const visualIndex = Math.floor((px - timeColumnWidth - slidePx) / dayWidth);
        if (visualIndex < 0 || visualIndex > 6)
            return 0;
        return dayAt(I18n.isRtl ? 6 - visualIndex : visualIndex).getTime();
    }

    function startEventDrag(event, pointerItem, x, y) {
        chipTooltip.hide();
        draggedEvent = event;
        eventDragging = true;
        updateEventDrag(pointerItem, x, y);
    }

    function startTimedDrag(event, sourceDay, pointerItem, x, y) {
        dragSourceTime = sourceDay.getTime();
        dragBlockMinutes = Math.round(event.startHour * 60);
        dragPointerMinutes = pointerItem.mapToItem(timedGrid, x, y).y / hourHeight * 60;
        startEventDrag(event, pointerItem, x, y);
    }

    function updateEventDrag(pointerItem, x, y) {
        const position = pointerItem.mapToItem(root, x, y);
        dragPosition = Qt.point(position.x, position.y);
        dragTargetTime = dayTimeAt(position.x);
        updateGridTarget(pointerItem, x, y);
    }

    function updateGridTarget(pointerItem, x, y) {
        dragOnGrid = false;
        if (!draggedEvent || draggedEvent.allDay || dragTargetTime === 0)
            return;
        const gridY = pointerItem.mapToItem(timedGrid, x, y).y;
        if (gridY < 0 || gridY >= timedGrid.height)
            return;
        const snapped = Math.round((gridY / hourHeight * 60 - dragPointerMinutes) / slotMinutes) * slotMinutes;
        const maxTop = Math.max(0, Math.round(hourCount * 60) - slotMinutes);
        dragMinuteOffset = Math.max(-dragBlockMinutes, Math.min(maxTop - dragBlockMinutes, snapped));
        dragOnGrid = true;
    }

    function finishEventDrag(event) {
        const targetTime = dragTargetTime;
        const onGrid = dragOnGrid;
        const dayOffset = dragDayOffset;
        const minuteOffset = dragMinuteOffset;
        eventPointerDown = false;
        eventDragging = false;
        draggedEvent = null;
        dragTargetTime = 0;
        dragOnGrid = false;
        if (targetTime === 0)
            return;
        if (!onGrid) {
            eventDropRequested(event, new Date(targetTime));
            return;
        }
        eventRescheduleRequested(event, dayOffset, minuteOffset);
    }

    function revealHours(start, duration) {
        const top = start * hourHeight;
        const bottom = top + duration * hourHeight;
        if (top < weekFlickable.contentY) {
            weekFlickable.contentY = Math.max(0, top - hourHeight / 2);
            return;
        }
        if (bottom > weekFlickable.contentY + weekFlickable.height)
            weekFlickable.contentY = Math.max(0, Math.min(weekFlickable.contentHeight - weekFlickable.height, bottom - weekFlickable.height + hourHeight / 2));
    }

    readonly property real startHour: SettingsData.effectiveHourStart
    readonly property real endHour: SettingsData.effectiveHourEnd
    readonly property real hourCount: endHour - startHour
    readonly property var hourTicks: EventUtils.hourTicks(startHour, endHour)
    readonly property real hourHeight: 48
    readonly property real timeColumnWidth: 60
    readonly property real allDayChipHeight: Math.max(18, SettingsData.weekEventTitleLines * 13 + 4)

    readonly property date firstDay: {
        const d = new Date(displayDate);
        d.setHours(0, 0, 0, 0);
        return d;
    }

    readonly property real dayWidth: width > timeColumnWidth ? (width - timeColumnWidth) / 7 : 0
    property real slidePx: 0

    function applySlide(dx) {
        if (dayWidth <= 0)
            return;
        snapAnim.stop();
        slidePx += dx;
        while (slidePx >= dayWidth) {
            slidePx -= dayWidth;
            shiftDaysRequested(I18n.isRtl ? 1 : -1);
        }
        while (slidePx <= -dayWidth) {
            slidePx += dayWidth;
            shiftDaysRequested(I18n.isRtl ? -1 : 1);
        }
    }

    function settleSlide() {
        if (dayWidth <= 0)
            return;
        if (slidePx >= dayWidth / 2) {
            slidePx -= dayWidth;
            shiftDaysRequested(I18n.isRtl ? 1 : -1);
        } else if (slidePx <= -dayWidth / 2) {
            slidePx += dayWidth;
            shiftDaysRequested(I18n.isRtl ? -1 : 1);
        }
        snapAnim.restart();
    }

    function slideDays(days) {
        if (dayWidth <= 0) {
            shiftDaysRequested(days);
            return;
        }
        snapAnim.stop();
        shiftDaysRequested(days);
        slidePx += (I18n.isRtl ? -1 : 1) * days * dayWidth;
        snapAnim.restart();
    }

    readonly property int nowIndex: {
        const nowDay = new Date(today.getFullYear(), today.getMonth(), today.getDate());
        return Math.round((nowDay.getTime() - firstDay.getTime()) / 86400000);
    }
    readonly property real nowHour: today.getHours() + today.getMinutes() / 60

    property bool initialScrollDone: false

    function applyInitialScroll() {
        const viewport = weekFlickable.height;
        const contentSpan = hourHeight * hourCount;
        if (initialScrollDone || viewport <= 0 || contentSpan <= viewport)
            return;
        initialScrollDone = true;
        const coreTop = (SettingsData.coreHoursStart - startHour) * hourHeight;
        const coreSpan = (SettingsData.coreHoursEnd - SettingsData.coreHoursStart) * hourHeight;
        const nowInCore = nowHour >= SettingsData.coreHoursStart && nowHour < SettingsData.coreHoursEnd;
        const center = SettingsData.coreHoursValid && nowInCore && coreSpan <= viewport ? coreTop + coreSpan / 2 : (nowHour - startHour) * hourHeight;
        weekFlickable.contentY = Math.max(0, Math.min(contentSpan - viewport, center - viewport / 2));
    }

    function hourLabel(hour) {
        if (hour === 24)
            return SettingsData.use24HourTime ? "24:00" : SettingsData.formatTime(new Date(2000, 0, 2));
        if (hour % 1 !== 0)
            return SettingsData.formatTime(new Date(2000, 0, 1, 0, Math.round(hour * 60)));
        if (hour === 0)
            return "";
        if (SettingsData.use24HourTime)
            return (hour < 10 ? "0" + hour : hour) + ":00";
        const h = hour % 12 === 0 ? 12 : hour % 12;
        return hour < 12 ? I18n.tr("%1 AM", "morning hour label in time gutter").arg(h) : I18n.tr("%1 PM", "afternoon hour label in time gutter").arg(h);
    }

    Connections {
        target: DankCalService
        function onEventsUpdated() {
            root.eventsVersion++;
        }
    }

    DTooltipV2 {
        id: chipTooltip
    }

    function eventTooltip(ev) {
        const suffix = (ev.location ? " · " + ev.location : "") + (ev.calendar ? " · " + DankCalService.calendarNames(ev) : "");
        if (ev.allDay)
            return ev.title + " · " + I18n.tr("All day", "all-day marker in event tooltip") + suffix;
        return ev.title + " · " + SettingsData.formatTime(ev.start) + " – " + SettingsData.formatTime(ev.end) + suffix;
    }

    function dayAt(index) {
        const d = new Date(firstDay);
        d.setDate(d.getDate() + index);
        return d;
    }

    function isSameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function timedEventsFor(day) {
        const out = [];
        const list = DankCalService.eventsForDay(day);
        for (let i = 0; i < list.length; i++) {
            const ev = list[i];
            if (ev.allDay)
                continue;
            const slot = EventUtils.timedSlot(ev, day, root.startHour, root.endHour);
            if (!slot)
                continue;
            out.push(Object.assign({}, ev, slot));
        }
        return DankCalService.layoutTimedEvents(out);
    }

    function allDayEventsFor(day) {
        return DankCalService.eventsForDay(day).filter(ev => ev.allDay);
    }

    readonly property int allDayMax: {
        eventsVersion;
        let max = 0;
        for (let i = -1; i <= 7; i++)
            max = Math.max(max, allDayEventsFor(dayAt(i)).length);
        return Math.min(max, 2);
    }

    function hiddenInfoFor(day) {
        const list = DankCalService.eventsForDay(day);
        let count = 0;
        let before = false;
        let after = false;
        for (let i = 0; i < list.length; i++) {
            const ev = list[i];
            if (ev.allDay)
                continue;
            const sides = EventUtils.hiddenSides(ev, day, root.startHour, root.endHour);
            if (!sides)
                continue;
            before = before || sides.before;
            after = after || sides.after;
            if (sides.before || sides.after)
                count++;
        }
        return {
            count: count,
            before: before,
            after: after
        };
    }

    readonly property int hiddenEventTotal: {
        eventsVersion;
        let total = 0;
        for (let i = -1; i <= 7; i++)
            total += root.hiddenInfoFor(root.dayAt(i)).count;
        return total;
    }

    readonly property bool anyHiddenBefore: {
        eventsVersion;
        for (let i = -1; i <= 7; i++)
            if (root.hiddenInfoFor(root.dayAt(i)).before)
                return true;
        return false;
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: coreHoursWarning
            width: parent.width
            height: root.hiddenEventTotal > 0 ? 36 : 0
            visible: height > 0
            clip: true
            color: Theme.withAlpha(Theme.warning, 0.18)

            Behavior on height {
                NumberAnimation {
                    duration: Theme.shorterDuration
                    easing.type: Theme.standardEasing
                }
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DIcon {
                    name: "warning"
                    size: Theme.iconSizeSmall
                    color: Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hiddenEventTotal === 1 ? I18n.tr("1 appointment falls outside core hours", "core hours warning banner, singular") : I18n.tr("%1 appointments fall outside core hours", "core hours warning banner, plural").arg(root.hiddenEventTotal)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                }
            }

            DButton {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Disable core hours", "core hours warning banner disable action")
                backgroundColor: "transparent"
                textColor: Theme.warning
                buttonHeight: Theme.buttonHeightXS
                focusPolicy: Qt.NoFocus
                onClicked: SettingsData.coreHoursEnabled = false
            }
        }

        Row {
            width: parent.width
            height: 56

            Item {
                width: root.timeColumnWidth
                height: parent.height
            }

            Item {
                width: parent.width - root.timeColumnWidth
                height: parent.height
                clip: true

                Row {
                    x: root.slidePx - root.dayWidth
                    height: parent.height

                    Repeater {
                        model: 9

                        Item {
                            required property int index
                            readonly property date d: root.dayAt(index - 1)
                            readonly property bool isToday: root.isSameDay(d, root.today)
                            readonly property bool isSelected: root.isSameDay(d, root.selectedDate)

                            width: root.dayWidth
                            height: parent.height

                            Column {
                                anchors.centerIn: parent
                                spacing: 2

                                StyledText {
                                    text: SettingsData.dayName(parent.parent.d.getDay())
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Rectangle {
                                    width: Theme.iconSizeLarge
                                    height: Theme.iconSizeLarge
                                    radius: Theme.fullRadius(width, height)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: parent.parent.isToday ? Theme.primary : "transparent"
                                    border.color: Theme.primary
                                    border.width: parent.parent.isSelected && !parent.parent.isToday ? 2 : 0

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: parent.parent.parent.d.getDate()
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Theme.fontWeightMedium
                                        color: parent.parent.parent.isToday ? Theme.primaryText : Theme.surfaceText
                                    }
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: Theme.gridLine
                            }

                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: eventPoint => root.dayContextRequested(parent.d, parent, eventPoint.position.x, eventPoint.position.y)
                            }
                        }
                    }
                }
            }
        }

        Row {
            id: allDayRow
            width: parent.width
            height: Math.max(1, root.allDayMax) * (root.allDayChipHeight + 4) + 6
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: Theme.shorterDuration
                    easing.type: Theme.standardEasing
                }
            }

            Item {
                width: root.timeColumnWidth
                height: parent.height
            }

            Item {
                width: parent.width - root.timeColumnWidth
                height: parent.height
                clip: true

                MouseArea {
                    id: allDayRangeArea

                    readonly property bool selecting: anchorTime > 0
                    readonly property int dragThreshold: Application.styleHints.startDragDistance
                    property real anchorTime: 0
                    property real rangeStart: 0
                    property real rangeEnd: 0
                    property real pressX: 0

                    function dayTimeAtX(x) {
                        const clamped = Math.max(0, Math.min(width - 1, x));
                        return root.dayTimeAt(mapToItem(root, clamped, 0).x);
                    }

                    function reset() {
                        anchorTime = 0;
                        rangeStart = 0;
                        rangeEnd = 0;
                    }

                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true

                    onPressed: mouse => pressX = mouse.x

                    onPositionChanged: mouse => {
                        if (!selecting) {
                            if (Math.abs(mouse.x - pressX) < dragThreshold)
                                return;
                            const anchor = dayTimeAtX(pressX);
                            if (anchor === 0)
                                return;
                            anchorTime = anchor;
                            rangeStart = anchor;
                            rangeEnd = anchor;
                        }
                        const hover = dayTimeAtX(mouse.x);
                        if (hover === 0)
                            return;
                        rangeStart = Math.min(anchorTime, hover);
                        rangeEnd = Math.max(anchorTime, hover);
                    }

                    onReleased: {
                        if (!selecting)
                            return;
                        const startDay = new Date(rangeStart);
                        const endDay = new Date(rangeEnd);
                        reset();
                        root.createRangeRequested(startDay, endDay);
                    }

                    onCanceled: reset()

                    Shortcut {
                        sequence: "Escape"
                        enabled: allDayRangeArea.selecting
                        onActivated: allDayRangeArea.reset()
                    }
                }

                Row {
                    x: root.slidePx - root.dayWidth
                    height: parent.height

                    Repeater {
                        model: 9

                        Item {
                            id: allDayCell
                            required property int index
                            readonly property date day: root.dayAt(index - 1)
                            readonly property bool isDropTarget: root.eventDragging && day.getTime() === root.dragTargetTime
                            readonly property bool inCreateRange: allDayRangeArea.selecting && day.getTime() >= allDayRangeArea.rangeStart && day.getTime() <= allDayRangeArea.rangeEnd
                            readonly property var dayEvents: {
                                root.eventsVersion;
                                return root.allDayEventsFor(root.dayAt(index - 1));
                            }

                            width: root.dayWidth
                            height: parent.height

                            Rectangle {
                                visible: allDayCell.isDropTarget
                                anchors.fill: parent
                                anchors.margins: 1
                                color: Theme.withAlpha(Theme.primary, 0.12)
                                border.color: Theme.primary
                                border.width: 2
                                radius: Theme.cornerRadiusXXS
                            }

                            Rectangle {
                                visible: allDayCell.inCreateRange
                                anchors.fill: parent
                                anchors.topMargin: 2
                                anchors.bottomMargin: 2
                                color: Theme.withAlpha(Theme.primary, 0.18)
                            }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 2

                                Repeater {
                                    model: ScriptModel {
                                        values: allDayCell.dayEvents.slice(0, 2)
                                    }

                                    Rectangle {
                                        id: allDayChip
                                        required property var modelData
                                        readonly property bool isSelected: root.isEventSelected(modelData)
                                        readonly property bool declined: modelData.myResponse === "declined"
                                        width: parent.width
                                        height: root.allDayChipHeight
                                        radius: Theme.cornerRadiusXS
                                        clip: true
                                        opacity: declined && !isSelected ? Theme.pendingOpacity : 1
                                        color: modelData.myResponse === "needs-action" || declined ? "transparent" : Theme.withAlpha(modelData.color, 0.22)
                                        border.color: isSelected ? Theme.primary : modelData.color
                                        border.width: isSelected ? 2 : 1

                                        TentativeHatch {
                                            visible: parent.modelData.myResponse === "tentative"
                                            stripeColor: parent.modelData.color
                                        }

                                        MergedEventDots {
                                            event: parent.modelData
                                        }

                                        StyledText {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.title
                                            font.pixelSize: 10
                                            font.strikeout: allDayChip.declined
                                            color: allDayChip.declined ? Theme.surfaceVariantText : Theme.surfaceText
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: SettingsData.weekEventTitleLines
                                            elide: Text.ElideRight
                                        }

                                        EventMouseArea {
                                            anchors.fill: parent
                                            eventData: parent.modelData
                                            dragEnabled: !parent.modelData.readOnly
                                            onEntered: chipTooltip.show(root.eventTooltip(parent.modelData), parent)
                                            onExited: chipTooltip.hide()
                                            onActivated: (event, modifiers) => {
                                                chipTooltip.hide();
                                                root.eventClicked(event, modifiers);
                                            }
                                            onContextRequested: (event, anchorItem, x, y) => root.eventContextRequested(event, anchorItem, x, y)
                                            onDragPressed: root.eventPointerDown = true
                                            onDragStarted: (event, pointerItem, x, y) => root.startEventDrag(event, pointerItem, x, y)
                                            onDragMoved: (event, pointerItem, x, y) => root.updateEventDrag(pointerItem, x, y)
                                            onDropped: (event, pointerItem, x, y) => {
                                                root.updateEventDrag(pointerItem, x, y);
                                                root.finishEventDrag(event);
                                            }
                                            onDragReleased: {
                                                root.eventPointerDown = false;
                                                if (root.eventDragging)
                                                    root.finishEventDrag(parent.modelData);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Row {
            id: hiddenBeforeStrip
            width: parent.width
            height: root.anyHiddenBefore ? 16 : 0
            visible: height > 0
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: Theme.shorterDuration
                    easing.type: Theme.standardEasing
                }
            }

            Item {
                width: root.timeColumnWidth
                height: parent.height
            }

            Item {
                width: parent.width - root.timeColumnWidth
                height: parent.height
                clip: true

                Row {
                    x: root.slidePx - root.dayWidth
                    height: parent.height

                    Repeater {
                        model: 9

                        Item {
                            required property int index
                            readonly property date d: root.dayAt(index - 1)
                            width: root.dayWidth
                            height: parent.height

                            DIcon {
                                visible: {
                                    root.eventsVersion;
                                    return root.hiddenInfoFor(parent.d).before;
                                }
                                anchors.centerIn: parent
                                name: "keyboard_arrow_up"
                                size: Theme.iconSizeSmall
                                color: Theme.warning
                            }
                        }
                    }
                }
            }
        }

        DFlickable {
            id: weekFlickable
            width: parent.width
            height: parent.height - 56 - coreHoursWarning.height - hiddenBeforeStrip.height - allDayRow.height
            contentHeight: root.hourHeight * root.hourCount
            clip: true
            onHeightChanged: root.applyInitialScroll()

            DankSlideDragHandler {
                slideArea: slidePager
            }

            Item {
                width: parent.width
                height: root.hourHeight * root.hourCount

                Item {
                    anchors.left: parent.left
                    width: root.timeColumnWidth
                    height: parent.height

                    Repeater {
                        model: root.hourTicks.length

                        StyledText {
                            required property int index
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            readonly property real tickY: (root.hourTicks[index] - root.startHour) * root.hourHeight
                            visible: index === 0 || (tickY >= height + Theme.spacingXS && (index === root.hourTicks.length - 1 || parent.height - tickY >= height + Theme.spacingXS))
                            y: Math.max(0, Math.min(parent.height - height, tickY - height / 2))
                            text: root.hourLabel(root.hourTicks[index])
                            font.pixelSize: 11
                            color: Theme.surfaceVariantText
                            isMonospace: true
                        }
                    }
                }

                Item {
                    anchors.right: parent.right
                    width: parent.width - root.timeColumnWidth
                    height: parent.height

                    Repeater {
                        model: root.hourTicks.length

                        Rectangle {
                            required property int index
                            y: (root.hourTicks[index] - root.startHour) * root.hourHeight
                            width: parent.width
                            height: 1
                            color: Theme.gridLine
                        }
                    }
                }

                Item {
                    id: timedGrid
                    anchors.right: parent.right
                    width: parent.width - root.timeColumnWidth
                    height: parent.height
                    clip: true

                    Row {
                        x: root.slidePx - root.dayWidth
                        height: parent.height

                        Repeater {
                            model: 9

                            Item {
                                id: dayColumn
                                required property int index
                                readonly property date day: root.dayAt(index - 1)
                                readonly property bool isDropTarget: root.eventDragging && day.getTime() === root.dragTargetTime
                                readonly property var timedEvents: {
                                    root.eventsVersion;
                                    return root.timedEventsFor(root.dayAt(index - 1));
                                }

                                width: root.dayWidth
                                height: parent.height

                                Rectangle {
                                    visible: dayColumn.isDropTarget
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    color: Theme.withAlpha(Theme.primary, 0.1)
                                    border.color: Theme.primary
                                    border.width: 2
                                    radius: Theme.cornerRadiusXXS
                                }

                                Rectangle {
                                    visible: dayColumn.isDropTarget && root.dragOnGrid
                                    x: 4
                                    y: root.dragPreviewTop
                                    z: 1
                                    width: parent.width - 8
                                    height: (root.draggedEvent ? root.draggedEvent.durationHours : 0) * root.hourHeight - 2
                                    radius: Theme.cornerRadiusS
                                    color: Theme.withAlpha(Theme.primary, 0.2)
                                    border.color: Theme.primary
                                    border.width: 1
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    width: 1
                                    height: parent.height
                                    color: Theme.gridLine
                                }

                                TimeGridCreateArea {
                                    anchors.fill: parent
                                    day: dayColumn.day
                                    startHour: root.startHour
                                    hourCount: root.hourCount
                                    hourHeight: root.hourHeight
                                    flickable: weekFlickable
                                    onCreateRequested: (start, end) => root.createTimedRequested(start, end)
                                }

                                DIcon {
                                    visible: {
                                        root.eventsVersion;
                                        return root.hiddenInfoFor(root.dayAt(dayColumn.index - 1)).after;
                                    }
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: root.hourCount * root.hourHeight + 2
                                    name: "keyboard_arrow_down"
                                    size: Theme.iconSizeSmall
                                    color: Theme.warning
                                }

                                Repeater {
                                    model: ScriptModel {
                                        values: dayColumn.timedEvents
                                    }

                                    Rectangle {
                                        id: timedChip
                                        required property var modelData
                                        readonly property bool isSelected: root.isEventSelected(modelData)
                                        onIsSelectedChanged: {
                                            if (isSelected)
                                                root.revealHours(modelData.startHour, modelData.durationHours);
                                        }
                                        readonly property bool declined: modelData.myResponse === "declined"
                                        readonly property real laneGap: 2
                                        readonly property real usableWidth: parent.width - 8
                                        readonly property real laneWidth: (usableWidth - (modelData.columns - 1) * laneGap) / modelData.columns
                                        x: 4 + modelData.column * (laneWidth + laneGap)
                                        y: modelData.startHour * root.hourHeight
                                        width: laneWidth
                                        height: modelData.durationHours * root.hourHeight - 2
                                        radius: Theme.cornerRadiusS
                                        clip: true
                                        opacity: declined && !isSelected ? Theme.pendingOpacity : 1
                                        color: modelData.myResponse === "needs-action" || declined ? "transparent" : Theme.withAlpha(modelData.color, 0.22)
                                        border.color: isSelected ? Theme.primary : modelData.color
                                        border.width: isSelected ? 2 : 1

                                        TentativeHatch {
                                            visible: parent.modelData.myResponse === "tentative"
                                            stripeColor: parent.modelData.color
                                        }

                                        MergedEventDots {
                                            event: parent.modelData
                                        }

                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            spacing: 2

                                            StyledText {
                                                text: modelData.title
                                                font.pixelSize: 11
                                                font.weight: Theme.fontWeightMedium
                                                font.strikeout: timedChip.declined
                                                color: timedChip.declined ? Theme.surfaceVariantText : Theme.surfaceText
                                                width: parent.width
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: Math.min(SettingsData.weekEventTitleLines, Math.max(1, Math.floor(parent.height / 14)))
                                                elide: Text.ElideRight
                                            }

                                            StyledText {
                                                visible: text !== "" && modelData.durationHours >= 1
                                                text: modelData.location
                                                font.pixelSize: 10
                                                color: Theme.surfaceVariantText
                                                width: parent.width
                                                wrapMode: Text.NoWrap
                                                maximumLineCount: 1
                                                elide: Text.ElideRight
                                            }
                                        }

                                        EventMouseArea {
                                            anchors.fill: parent
                                            eventData: parent.modelData
                                            dragEnabled: !parent.modelData.readOnly
                                            onEntered: chipTooltip.show(root.eventTooltip(parent.modelData), parent)
                                            onExited: chipTooltip.hide()
                                            onActivated: (event, modifiers) => {
                                                chipTooltip.hide();
                                                root.eventClicked(event, modifiers);
                                            }
                                            onContextRequested: (event, anchorItem, x, y) => root.eventContextRequested(event, anchorItem, x, y)
                                            onDragPressed: root.eventPointerDown = true
                                            onDragStarted: (event, pointerItem, x, y) => root.startTimedDrag(event, dayColumn.day, pointerItem, x, y)
                                            onDragMoved: (event, pointerItem, x, y) => root.updateEventDrag(pointerItem, x, y)
                                            onDropped: (event, pointerItem, x, y) => {
                                                root.updateEventDrag(pointerItem, x, y);
                                                root.finishEventDrag(event);
                                            }
                                            onDragReleased: {
                                                root.eventPointerDown = false;
                                                if (root.eventDragging)
                                                    root.finishEventDrag(parent.modelData);
                                            }
                                        }
                                    }
                                }

                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: eventPoint => root.dayContextRequested(dayColumn.day, dayColumn, eventPoint.position.x, eventPoint.position.y)
                                }
                            }
                        }
                    }
                }

                Item {
                    anchors.right: parent.right
                    width: parent.width - root.timeColumnWidth
                    height: parent.height
                    clip: true
                    visible: root.nowHour >= root.startHour && root.nowHour < root.endHour
                    z: 10

                    Item {
                        y: (root.nowHour - root.startHour) * root.hourHeight
                        width: parent.width

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.top
                            height: 2
                            color: Theme.error
                        }

                        Rectangle {
                            x: root.slidePx + (I18n.isRtl ? 6 - root.nowIndex : root.nowIndex) * root.dayWidth
                            anchors.verticalCenter: parent.top
                            width: Theme.spacingS + Theme.spacingXXS
                            height: width
                            radius: Theme.fullRadius(width, height)
                            color: Theme.error
                        }
                    }
                }
            }
        }
    }

    NumberAnimation {
        id: snapAnim
        target: root
        property: "slidePx"
        to: 0
        duration: Theme.shortDuration
        easing.type: Theme.standardEasing
    }

    DankSlideArea {
        id: slidePager
        anchors.fill: parent
        z: 50
        dragEnabled: !root.eventPointerDown && !root.eventDragging
        onMoved: dx => root.applySlide(dx)
        onStepped: direction => root.slideDays((I18n.isRtl ? 1 : -1) * direction)
        onSettled: root.settleSlide()
    }

    DankSlideDragHandler {
        slideArea: slidePager
    }

    EventDragGhost {
        dragging: root.eventDragging
        draggedEvent: root.draggedEvent
        dragPosition: root.dragPosition
        selectedKeys: root.selectedEventKeys
        detail: root.dragPreviewLabel
    }
}
