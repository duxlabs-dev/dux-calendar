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
    property string selectedEventKey: ""
    property var selectedEventKeys: []
    property int eventsVersion: 0
    readonly property int daysAhead: 14

    signal eventClicked(var event, int modifiers)
    signal eventContextRequested(var event, var anchorItem, real x, real y)
    signal dayContextRequested(date day, var anchorItem, real x, real y)

    function isEventSelected(event) {
        const key = DankCalService.eventKey(event);
        return selectedEventKey === key || selectedEventKeys.indexOf(key) !== -1;
    }

    function revealItem(item) {
        const y = item.mapToItem(agendaColumn, 0, 0).y;
        if (y < agendaFlickable.contentY) {
            agendaFlickable.contentY = Math.max(0, y - Theme.spacingM);
            return;
        }
        const bottom = y + item.height;
        if (bottom > agendaFlickable.contentY + agendaFlickable.height)
            agendaFlickable.contentY = Math.max(0, Math.min(agendaFlickable.contentHeight - agendaFlickable.height, bottom - agendaFlickable.height + Theme.spacingM));
    }

    Connections {
        target: DankCalService
        function onEventsUpdated() {
            root.eventsVersion++;
        }
    }

    function dayLabel(d) {
        const todayStart = new Date(root.today.getFullYear(), root.today.getMonth(), root.today.getDate());
        const diff = Math.round((d.getTime() - todayStart.getTime()) / 86400000);
        switch (diff) {
        case 0:
            return I18n.tr("Today", "agenda section header for the current day");
        case 1:
            return I18n.tr("Tomorrow", "agenda section header for the next day");
        default:
            return SettingsData.formatDate(d, "dddd, MMM d");
        }
    }

    function durationLabel(ev) {
        if (ev.allDay)
            return "";
        const mins = Math.round((ev.end.getTime() - ev.start.getTime()) / 60000);
        if (mins <= 0)
            return "";
        const h = Math.floor(mins / 60);
        const m = mins % 60;
        if (h === 0)
            return I18n.tr("%1m", "event duration in minutes on agenda card, %1 is minutes").arg(m);
        return m === 0 ? I18n.tr("%1h", "event duration in hours on agenda card, %1 is hours").arg(h) : I18n.tr("%1h%2m", "event duration on agenda card, %1 is hours and %2 is minutes").arg(h).arg(m);
    }

    readonly property var sections: {
        eventsVersion;
        const out = [];
        for (let i = 0; i < daysAhead; i++) {
            const d = new Date(displayDate.getFullYear(), displayDate.getMonth(), displayDate.getDate() + i);
            const evs = DankCalService.eventsForDay(d);
            if (evs.length === 0)
                continue;
            const cards = evs.map(ev => {
                const card = Object.assign({}, ev);
                card.time = ev.allDay ? I18n.tr("All day", "time column label for all-day events on agenda card") : SettingsData.formatTime(ev.start);
                card.duration = durationLabel(ev);
                card.preview = DankCalService.descriptionPreview(ev);
                return card;
            });
            out.push({
                "label": dayLabel(d),
                "day": d,
                "events": cards
            });
        }
        return out;
    }

    DFlickable {
        id: agendaFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: agendaColumn.implicitHeight
        clip: true

        Column {
            id: agendaColumn
            width: root.width
            spacing: Theme.spacingM
            padding: 0

            StyledText {
                visible: root.sections.length === 0
                text: DankCalService.connected ? I18n.tr("Nothing scheduled in the next %1 days", "agenda empty state, %1 is the number of days ahead").arg(root.daysAhead) : I18n.tr("Waiting for the %1 daemon...", "agenda placeholder while the daemon is not connected, %1 is the daemon name").arg("dankcalendar")
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
                        text: parent.modelData.label
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                        width: parent.width

                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: eventPoint => root.dayContextRequested(section.modelData.day, parent, eventPoint.position.x, eventPoint.position.y)
                        }
                    }

                    Repeater {
                        model: ScriptModel {
                            values: section.modelData.events
                        }

                        StyledRect {
                            id: card
                            required property var modelData
                            readonly property bool isSelected: root.isEventSelected(modelData)
                            onIsSelectedChanged: {
                                if (!isSelected)
                                    return;
                                Qt.callLater(() => {
                                    if (card && card.isSelected)
                                        root.revealItem(card);
                                });
                            }
                            readonly property bool awaitingReply: modelData.myResponse === "needs-action"
                            readonly property bool tentativeReply: modelData.myResponse === "tentative"
                            readonly property bool declined: modelData.myResponse === "declined"
                            width: root.width
                            opacity: declined && !isSelected ? Theme.pendingOpacity : 1
                            height: Math.max(76, contentRow.implicitHeight + Theme.spacingM * 2)
                            color: isSelected ? Theme.selectedContainer : (cardArea.containsMouse ? Theme.surfaceContainer : Theme.surfaceContainerLow)
                            radius: Theme.cornerRadiusM
                            border.color: isSelected ? Theme.primary : (awaitingReply ? modelData.color : "transparent")
                            border.width: isSelected ? 2 : (awaitingReply ? 1 : 0)
                            clip: tentativeReply

                            TentativeHatch {
                                visible: card.tentativeReply
                                stripeColor: card.modelData.color
                                opacity: 0.15
                            }

                            MergedEventDots {
                                event: card.modelData
                                margin: Theme.spacingS
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
                                    width: 4
                                    height: 44
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: Theme.fullRadius(width, height)
                                    color: card.modelData.color
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 84
                                    spacing: 2

                                    StyledText {
                                        text: card.modelData.time
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Theme.fontWeightMedium
                                        color: Theme.surfaceText
                                        isMonospace: true
                                        width: parent.width
                                    }

                                    StyledText {
                                        text: card.modelData.duration
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        visible: text !== ""
                                        width: parent.width
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 4 - 84 - Theme.spacingM * 2
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: card.modelData.title
                                        font.pixelSize: Theme.fontSizeLarge
                                        font.weight: Theme.fontWeightMedium
                                        font.strikeout: card.declined
                                        color: card.declined ? Theme.surfaceVariantText : Theme.surfaceText
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: Theme.spacingXS
                                        visible: card.modelData.location !== ""

                                        DIcon {
                                            id: locationIcon
                                            name: "place"
                                            size: Theme.iconSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: card.modelData.location
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - locationIcon.width - Theme.spacingXS
                                            wrapMode: Text.NoWrap
                                            maximumLineCount: 1
                                            elide: Text.ElideRight
                                        }
                                    }

                                    StyledText {
                                        text: card.modelData.preview
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        visible: text !== ""
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }

                                    Row {
                                        spacing: Theme.spacingS

                                        Rectangle {
                                            width: 8
                                            height: 8
                                            radius: Theme.fullRadius(width, height)
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: card.modelData.color
                                        }

                                        StyledText {
                                            text: card.modelData.calendar
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }

                            EventMouseArea {
                                id: cardArea
                                anchors.fill: parent
                                eventData: card.modelData
                                onActivated: (event, modifiers) => root.eventClicked(event, modifiers)
                                onContextRequested: (event, anchorItem, x, y) => root.eventContextRequested(event, anchorItem, x, y)
                            }
                        }
                    }
                }
            }
        }
    }
}
