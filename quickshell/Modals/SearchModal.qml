pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Common as DC
import qs.DCommon.Widgets

FocusScope {
    id: root

    signal eventSelected(var event)
    signal closed

    property bool opened: false
    property Item returnFocus: null

    property var results: []
    property bool loading: false
    property string activeQuery: ""
    property string errorText: ""
    property int selectedIndex: 0

    readonly property bool hasQuery: searchInput.text.trim().length > 0
    readonly property real rowH: Theme.listItemTwoLineHeight
    readonly property real statusH: Theme.listItemTwoLineHeight + Theme.spacingL
    readonly property real maxResultsH: Math.min(Theme.menuMaxHeight, height * 0.55)

    readonly property var rows: {
        const now = new Date();
        const upcoming = [];
        const past = [];
        for (let i = 0; i < results.length; i++) {
            const ev = results[i];
            if (ev.end >= now)
                upcoming.push(ev);
            else
                past.push(ev);
        }
        upcoming.sort((a, b) => a.start - b.start);
        past.sort((a, b) => b.start - a.start);
        return upcoming.concat(past).map(ev => ({
                    "rowId": ev.id + "|" + ev.start.getTime(),
                    "event": ev
                }));
    }

    readonly property real resultsH: {
        if (!hasQuery)
            return 0;
        if (rows.length === 0)
            return statusH;
        return Math.min(rows.length * (rowH + Theme.groupedListGap) + Theme.spacingS, maxResultsH);
    }

    onRowsChanged: selectedIndex = 0

    function show() {
        open();
    }

    function open() {
        const host = Overlay.overlay ?? Window.window?.contentItem ?? null;
        if (host)
            parent = host;
        returnFocus = Window.window?.activeFocusItem ?? null;
        opened = true;
        searchInput.forceActiveFocus();
    }

    function close() {
        if (!opened)
            return;
        opened = false;
        searchDebounce.stop();
        searchInput.text = "";
        activeQuery = "";
        loading = false;
        errorText = "";
        results = [];
        const target = returnFocus;
        returnFocus = null;
        if (target)
            target.forceActiveFocus();
        closed();
    }

    function _dateLabel(ev) {
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const day = new Date(ev.start.getFullYear(), ev.start.getMonth(), ev.start.getDate());
        const diff = Math.round((day.getTime() - today.getTime()) / 86400000);
        switch (diff) {
        case -1:
            return I18n.tr("Yesterday", "search result date label for previous day");
        case 0:
            return I18n.tr("Today", "search result date label for current day");
        case 1:
            return I18n.tr("Tomorrow", "search result date label for next day");
        }
        if (ev.start.getFullYear() === now.getFullYear())
            return SettingsData.formatDate(ev.start, "MMM d");
        return SettingsData.formatDate(ev.start, "MMM d, yyyy");
    }

    function _subtitle(ev) {
        const parts = [];
        parts.push(ev.allDay ? I18n.tr("All day", "search result subtitle for all-day events") : SettingsData.formatTime(ev.start));
        if (ev.calendar)
            parts.push(ev.calendar);
        if (ev.location)
            parts.push(ev.location);
        return parts.join(" · ");
    }

    function _statusTitle() {
        if (loading)
            return I18n.tr("Searching", "search status title while search is running");
        if (errorText !== "")
            return I18n.tr("Search failed", "search status title when search errors");
        if (activeQuery === "")
            return I18n.tr("Keep typing", "search status title when query is too short");
        return I18n.tr("No matching events", "search status title when no results found");
    }

    function _statusSubtitle() {
        if (loading)
            return "";
        if (errorText !== "")
            return errorText;
        if (activeQuery === "")
            return I18n.tr("Type at least 2 characters to search events.", "search status hint when query is too short");
        return I18n.tr("Try a different search.", "search status hint when no results found");
    }

    function _activate(index) {
        if (index < 0 || index >= rows.length)
            return;
        const ev = rows[index].event;
        eventSelected(ev);
        close();
    }

    function _selectDelta(delta) {
        if (rows.length === 0)
            return;
        selectedIndex = Math.max(0, Math.min(rows.length - 1, selectedIndex + delta));
        resultsList.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function _handleKey(event) {
        switch (event.key) {
        case Qt.Key_Down:
            _selectDelta(1);
            event.accepted = true;
            return;
        case Qt.Key_Up:
            _selectDelta(-1);
            event.accepted = true;
            return;
        case Qt.Key_PageDown:
            _selectDelta(6);
            event.accepted = true;
            return;
        case Qt.Key_PageUp:
            _selectDelta(-6);
            event.accepted = true;
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            _submit();
            event.accepted = true;
            return;
        case Qt.Key_Escape:
            close();
            event.accepted = true;
            return;
        }
        event.accepted = false;
    }

    function _submit() {
        if (rows.length > 0) {
            _activate(selectedIndex);
            return;
        }
        _runSearch();
    }

    function _runSearch() {
        searchDebounce.stop();
        const q = searchInput.text.trim();
        if (q.length < 2) {
            activeQuery = "";
            loading = false;
            errorText = "";
            results = [];
            return;
        }

        activeQuery = q;
        loading = true;
        DankCalService.searchEvents(q, response => {
            if (root.activeQuery !== q)
                return;
            root.loading = false;
            root.errorText = response.error || "";
            root.results = response.events || [];
        });
    }

    anchors.fill: parent
    visible: opened || scrim.opacity > 0
    enabled: opened
    focus: false
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Keys.onPressed: event => root._handleKey(event)

    Timer {
        id: searchDebounce
        interval: Timing.debounceLong
        repeat: false
        onTriggered: root._runSearch()
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Theme.scrimColor
        opacity: root.opened ? Theme.scrimAlpha : 0

        Behavior on opacity {
            enabled: Theme.animationsEnabled
            DC.DAnim {
                duration: Theme.expressiveDurations.expressiveEffects
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Item {
        id: surface
        x: Math.round((parent.width - width) / 2)
        y: Math.round(parent.height * 0.12)
        width: Math.max(0, Math.min(Theme.dialogMaxWidth, parent.width - Theme.spacingXL * 2))
        height: Theme.spacingS * 2 + searchInput.height + resultsContainer.height
        scale: root.opened ? 1 : Theme.popupEnterScale
        opacity: root.opened ? 1 : 0

        Behavior on scale {
            enabled: Theme.animationsEnabled
            DC.DAnim {
                duration: Theme.expressiveDurations.expressiveDefaultSpatial
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }

        Behavior on opacity {
            enabled: Theme.animationsEnabled
            DC.DAnim {
                duration: Theme.expressiveDurations.expressiveEffects
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        DC.ElevationShadow {
            anchors.fill: parent
            level: Theme.elevationLevel3
            targetRadius: Theme.windowRadius
            targetColor: card.color
            shadowEnabled: Theme.elevationEnabled
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: Theme.windowRadius
            color: Theme.chipSurface

            MouseArea {
                anchors.fill: parent
            }
        }

        DSearchField {
            id: searchInput
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingS
            height: Theme.buttonHeightM
            font.pixelSize: Theme.fontSizeLarge
            placeholderText: I18n.tr("Search events", "search modal input placeholder")
            onTextChanged: searchDebounce.restart()
            onAccepted: root._submit()
            Keys.onReturnPressed: event => event.accepted = true
            Keys.onEnterPressed: event => event.accepted = true
        }

        Item {
            id: resultsContainer
            anchors.top: searchInput.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spacingS
            anchors.rightMargin: Theme.spacingS
            height: root.resultsH
            clip: true

            Behavior on height {
                enabled: Theme.animationsEnabled
                DC.DAnim {
                    duration: Theme.expressiveDurations.expressiveEffects
                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                }
            }

            DListView {
                id: resultsList
                anchors.fill: parent
                anchors.topMargin: Theme.spacingS
                clip: true
                visible: root.rows.length > 0
                spacing: Theme.groupedListGap

                model: ScriptModel {
                    values: root.rows
                    objectProp: "rowId"
                }

                delegate: StyledRect {
                    id: delegateRoot
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.selectedIndex
                    readonly property color contentColor: selected ? Theme.onSelectedContainer : Theme.surfaceText
                    readonly property color supportingColor: selected ? Theme.onSelectedContainer : Theme.surfaceVariantText

                    width: resultsList.width
                    height: root.rowH
                    radius: Theme.groupedListInnerRadius
                    topLeftRadius: index === 0 ? Theme.groupedListOuterRadius : radius
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: index === root.rows.length - 1 ? Theme.groupedListOuterRadius : radius
                    bottomRightRadius: bottomLeftRadius
                    color: selected ? Theme.selectedContainer : Theme.surfaceContainerLow

                    Behavior on color {
                        enabled: Theme.animationsEnabled
                        DC.DColorAnim {
                            duration: Theme.expressiveDurations.expressiveFastEffects
                            easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
                        }
                    }

                    Rectangle {
                        id: iconWell
                        width: Theme.iconButtonSize
                        height: Theme.iconButtonSize
                        radius: Theme.cornerRadiusM
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.chipSurfaceNested

                        DIcon {
                            anchors.centerIn: parent
                            name: "event"
                            size: Theme.iconSize
                            color: delegateRoot.modelData.event.color
                        }
                    }

                    Column {
                        anchors.left: iconWell.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: datePill.left
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXXS

                        StyledText {
                            width: parent.width
                            text: delegateRoot.modelData.event.title
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            color: delegateRoot.contentColor
                            maximumLineCount: 1
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: root._subtitle(delegateRoot.modelData.event)
                            font.pixelSize: Theme.fontSizeSmall
                            color: delegateRoot.supportingColor
                            maximumLineCount: 1
                            elide: Text.ElideRight
                            visible: text !== ""
                        }
                    }

                    Rectangle {
                        id: datePill
                        width: dateText.implicitWidth + Theme.spacingS * 2
                        height: Theme.spacingXL
                        radius: Theme.fullRadius(width, height)
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        color: delegateRoot.selected ? Theme.withAlpha(Theme.onSelectedContainer, Theme.stateLayerFocus) : Theme.chipSurfaceNested

                        StyledText {
                            id: dateText
                            anchors.centerIn: parent
                            text: root._dateLabel(delegateRoot.modelData.event)
                            font.pixelSize: Theme.fontSizeSmall
                            color: delegateRoot.supportingColor
                        }
                    }

                    StateLayer {
                        stateColor: delegateRoot.contentColor
                        onClicked: root._activate(delegateRoot.index)
                    }
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingM
                visible: root.hasQuery && root.rows.length === 0

                Rectangle {
                    width: Theme.iconButtonSize
                    height: Theme.iconButtonSize
                    radius: Theme.cornerRadiusM
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.chipSurfaceNested

                    DIcon {
                        anchors.centerIn: parent
                        name: root.errorText !== "" ? "error" : root.activeQuery === "" ? "search" : "search_off"
                        size: Theme.iconSize
                        color: Theme.surfaceVariantText
                        visible: !root.loading
                    }

                    DSpinner {
                        anchors.centerIn: parent
                        size: Theme.iconSize
                        visible: root.loading
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(Theme.fieldDefaultWidth * 2, resultsContainer.width - Theme.iconButtonSize - Theme.spacingM * 4)
                    spacing: Theme.spacingXXS

                    StyledText {
                        width: parent.width
                        text: root._statusTitle()
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: root._statusSubtitle()
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        visible: text !== ""
                    }
                }
            }
        }
    }
}
