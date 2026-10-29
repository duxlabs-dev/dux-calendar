pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Common
import qs.Services
import "../Common/EventUtils.js" as EventUtils

Singleton {
    id: root

    readonly property var log: Log.scoped("DankCalService")

    readonly property string socketPath: Quickshell.env("DANKCAL_SOCKET")

    property bool socketReady: false
    property bool connected: false
    property bool connecting: false
    property bool subscribed: false
    property int apiVersion: 0
    property string daemonVersion: ""
    property var capabilities: []

    property var accounts: []
    property var providers: []
    property var googleSetupSteps: []
    property var microsoftSetupSteps: []
    property string lastError: ""

    property bool autostartEnabled: false

    property var calendars: []
    property var events: []
    property var tasks: []
    property var _pendingTaskState: ({})
    property bool eventsLoading: false
    property date focusDate: new Date()
    property var _loadedFrom: null
    property var _loadedTo: null

    readonly property var fallbackPalette: ["#7287fd", "#f38ba8", "#a6e3a1", "#fab387", "#cba6f7", "#94e2d5", "#f9e2af", "#89dceb"]

    property var pendingRequests: ({})
    property int requestCounter: 0

    signal connectionStateChanged
    signal googleFlowStarted(string state, string authUrl)
    signal googleFlowCompleted(string accountId, string email)
    signal googleFlowFailed(string state, string error)
    signal microsoftFlowStarted(string state, string authUrl)
    signal microsoftFlowCompleted(string accountId, string email)
    signal microsoftFlowFailed(string state, string error)
    signal accountAdded(string accountId)
    signal accountRemoved(string accountId)
    signal addAccountRequested
    signal eventsUpdated
    signal tasksUpdated
    signal windowActionRequested(string action, string view)
    signal subscribeRequested(string url)
    signal importIcsRequested(string ics, string name)
    signal openEventRequested(string uid, string start)
    signal newEventRequested(string start)
    signal colorSchemeUpdate(var data)
    signal filesEvent(var data)

    onFocusDateChanged: _ensureWindow()

    Connections {
        target: SettingsData
        function onMergeDuplicateEventsChanged() {
            root.eventsUpdated();
        }
    }

    Component.onCompleted: {
        if (socketPath && socketPath.length > 0) {
            socketProbe.running = true;
        }
    }

    Process {
        id: socketProbe
        command: ["test", "-S", root.socketPath]
        running: false
        onExited: code => {
            if (code === 0) {
                root.socketReady = true;
                root.connectSocket();
            } else {
                root.socketReady = false;
            }
        }
    }

    function connectSocket() {
        if (!socketReady || connected || connecting)
            return;

        connecting = true;
        requestSocket.connected = true;
    }

    DSocket {
        id: requestSocket
        path: root.socketPath
        connected: false

        onConnectionStateChanged: {
            if (connected) {
                root.connected = true;
                root.connecting = false;
                root.connectionStateChanged();
                subscribeSocket.connected = true;
                root.refreshVersion();
                root.refreshAccounts();
                root.refreshProviders();
                root.refreshGoogleSetupSteps();
                root.refreshMicrosoftSetupSteps();
                root.refreshCalendars();
                root.reloadEvents();
                root.reloadTasks();
                root.refreshAutostart();
            } else {
                root.connected = false;
                root.connecting = false;
                root.connectionStateChanged();
                root._failPendingRequests("disconnected from dankcalendar socket");
            }
        }

        parser: SplitParser {
            onRead: line => {
                if (!line || line.length === 0)
                    return;

                let response;
                try {
                    response = JSON.parse(line);
                } catch (e) {
                    log.warn("bad response", line.substring(0, 200));
                    return;
                }
                root._handleResponse(response);
            }
        }
    }

    DSocket {
        id: subscribeSocket
        path: root.socketPath
        connected: false

        onConnectionStateChanged: {
            root.subscribed = connected;
            if (connected)
                root._sendSubscribe();
        }

        parser: SplitParser {
            onRead: line => {
                if (!line || line.length === 0)
                    return;

                let event;
                try {
                    event = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root._handleEvent(event);
            }
        }
    }

    function _sendSubscribe() {
        const req = {
            "id": _nextId(),
            "method": "subscribe",
            "params": {
                "topics": ["accounts", "calendars", "events", "tasks", "sync", "ui", "colorScheme"]
            }
        };
        subscribeSocket.send(req);
    }

    function subscribeTopics(topics) {
        if (!subscribed || topics.length === 0)
            return;
        subscribeSocket.send({
            "id": _nextId(),
            "method": "subscribe",
            "params": {
                "topics": topics
            }
        });
    }

    function unsubscribeTopics(topics) {
        if (!subscribed || topics.length === 0)
            return;
        subscribeSocket.send({
            "id": _nextId(),
            "method": "unsubscribe",
            "params": {
                "topics": topics
            }
        });
    }

    function _nextId() {
        requestCounter++;
        return Date.now() + requestCounter;
    }

    function _handleResponse(response) {
        if (response.event) {
            _handleEvent(response);
            return;
        }

        const id = response.id;
        if (!id) {
            if (response.apiVersion !== undefined) {
                apiVersion = response.apiVersion;
                capabilities = response.capabilities || [];
            }
            return;
        }

        const cb = pendingRequests[id];
        if (cb) {
            delete pendingRequests[id];
            cb(response);
        }
    }

    function _handleEvent(event) {
        const topic = event.event;

        switch (topic) {
        case "accounts":
            refreshAccounts();
            refreshCalendars();
            break;
        case "calendars":
            refreshCalendars();
            break;
        case "events":
            refreshDebounce.restart();
            break;
        case "tasks":
            tasksDebounce.restart();
            break;
        case "sync":
            refreshDebounce.restart();
            tasksDebounce.restart();
            break;
        case "ui":
            {
                const data = event.data || {};
                switch (data.action) {
                case "subscribe":
                    subscribeRequested(data.url || "");
                    break;
                case "importIcs":
                    importIcsRequested(data.ics || "", data.name || "");
                    break;
                case "openEvent":
                    openEventRequested(data.uid || "", data.start || "");
                    break;
                case "newEvent":
                    newEventRequested(data.start || "");
                    break;
                default:
                    windowActionRequested(data.action || "", data.view || "");
                    break;
                }
                break;
            }
        case "colorScheme":
            colorSchemeUpdate(event.data || {});
            break;
        default:
            if (topic?.startsWith("files:"))
                filesEvent(event.data || {});
            break;
        }
    }

    Timer {
        id: refreshDebounce
        interval: 400
        repeat: false
        onTriggered: {
            root.refreshCalendars();
            root.reloadEvents();
        }
    }

    Timer {
        id: tasksDebounce
        interval: 400
        repeat: false
        onTriggered: root.reloadTasks()
    }

    function _failPendingRequests(reason) {
        const callbacks = pendingRequests;
        pendingRequests = ({});
        for (const id in callbacks) {
            callbacks[id]({
                "error": reason
            });
        }
    }

    function sendRequest(method, params, callback) {
        if (!connected) {
            if (callback)
                callback({
                    "error": "not connected to dankcalendar socket"
                });
            return;
        }

        const id = _nextId();
        const req = {
            "id": id,
            "method": method
        };
        if (params)
            req.params = params;
        if (callback)
            pendingRequests[id] = callback;
        requestSocket.send(req);
    }

    // Timestamps churn on every sync; ignore them so unchanged lists don't
    // get reassigned, which would recreate delegates and close their popups.
    function _stableStringify(list) {
        return JSON.stringify(list, (key, value) => (key === "updatedAt" || key === "createdAt") ? undefined : value);
    }

    // Keep the old object for unchanged entries so ScriptModel preserves
    // their delegates and only changed rows are recreated.
    function _mergeStable(next, prev) {
        const prevById = {};
        for (let i = 0; i < prev.length; i++)
            prevById[prev[i].id] = prev[i];
        return next.map(entry => {
            const old = prevById[entry.id];
            return (old && _stableStringify(old) === _stableStringify(entry)) ? old : entry;
        });
    }

    function refreshAccounts() {
        sendRequest("accounts.list", null, response => {
            if (response.error) {
                lastError = response.error;
                return;
            }
            const list = response.result || [];
            if (_stableStringify(list) === _stableStringify(accounts))
                return;
            accounts = _mergeStable(list, accounts);
        });
    }

    function refreshVersion() {
        sendRequest("version", null, response => {
            if (response.error)
                return;
            const info = response.result || {};
            daemonVersion = info.version || "";
            if (info.apiVersion)
                apiVersion = info.apiVersion;
        });
    }

    function refreshProviders() {
        sendRequest("accounts.providers", null, response => {
            if (!response.error)
                providers = response.result || [];
        });
    }

    function refreshGoogleSetupSteps() {
        sendRequest("accounts.google.setupGuide", null, response => {
            if (!response.error)
                googleSetupSteps = response.result || [];
        });
    }

    function refreshMicrosoftSetupSteps() {
        sendRequest("accounts.microsoft.setupGuide", null, response => {
            if (!response.error)
                microsoftSetupSteps = response.result || [];
        });
    }

    function refreshCalendars() {
        sendRequest("calendars.list", null, response => {
            if (response.error) {
                lastError = response.error;
                return;
            }
            const list = response.result || [];
            for (let i = 0; i < list.length; i++) {
                if (!list[i].color)
                    list[i].color = fallbackPalette[i % fallbackPalette.length];
            }
            if (_stableStringify(list) === _stableStringify(calendars))
                return;
            calendars = _mergeStable(list, calendars);
            eventsUpdated();
            tasksUpdated();
        });
    }

    function findEvent(uid, start) {
        if (!uid)
            return null;
        const want = start ? new Date(start).getTime() : NaN;
        let fallback = null;
        for (let i = 0; i < events.length; i++) {
            const ev = events[i];
            if (ev.uid !== uid)
                continue;
            if (isNaN(want))
                return decorateEvent(ev);
            if (ev.start.getTime() === want)
                return decorateEvent(ev);
            fallback = ev;
        }
        return fallback ? decorateEvent(fallback) : null;
    }

    function fetchEvent(uid, start, callback) {
        if (!uid) {
            callback(null);
            return;
        }
        const params = {
            "uid": uid
        };
        if (start)
            params.start = start;
        sendRequest("events.get", params, response => {
            if (response.error) {
                lastError = response.error;
                callback(null);
                return;
            }
            callback(eventFromResult(response.result));
        });
    }

    function calendarById(id) {
        for (let i = 0; i < calendars.length; i++) {
            if (calendars[i].id === id)
                return calendars[i];
        }
        return null;
    }

    function accountById(id) {
        for (let i = 0; i < accounts.length; i++) {
            if (accounts[i].id === id)
                return accounts[i];
        }
        return null;
    }

    // Pure task lists (VTODO only, e.g. Google Tasks) are writable but can't
    // hold events; creating one there 404s at the provider.
    function writableCalendars() {
        return calendars.filter(c => !c.readOnly && !c.syncDisabled && _holdsEvents(c));
    }

    // Qt.openUrlExternally doesn't work with geo: URIs for some reason, so
    // the daemon has its own opener.
    function openUri(url) {
        sendRequest("system.openUri", {
            "uri": url
        }, response => {
            if (response.error)
                Qt.openUrlExternally(url);
        });
    }

    // _holdsEvents treats an empty component set as an event calendar for
    // back-compat; a pure task list (VTODO only) is excluded from "My calendars".
    function _holdsEvents(c) {
        const comps = c.supportedComponents;
        if (!comps || comps.length === 0)
            return true;
        return comps.indexOf("VEVENT") !== -1;
    }

    function eventCalendars() {
        return calendars.filter(c => !c.syncDisabled && _holdsEvents(c));
    }

    function eventCalendarGroups() {
        const groups = [];
        const byAccount = {};
        const groupFor = accountId => {
            if (byAccount[accountId])
                return byAccount[accountId];
            const group = {
                "account": accountById(accountId),
                "calendars": []
            };
            byAccount[accountId] = group;
            groups.push(group);
            return group;
        };
        for (let i = 0; i < accounts.length; i++)
            groupFor(accounts[i].id);
        const cals = eventCalendars();
        for (let i = 0; i < cals.length; i++)
            groupFor(cals[i].accountId || "").calendars.push(cals[i]);
        for (let g = 0; g < groups.length; g++)
            groups[g].calendars = _shownFirst(groups[g].calendars);
        return groups.filter(group => group.calendars.length > 0);
    }

    function _shownFirst(cals) {
        return cals.filter(c => !c.hidden).concat(cals.filter(c => c.hidden));
    }

    function defaultCalendar() {
        const writable = writableCalendars().filter(c => !c.hidden);
        return writable.length > 0 ? writable[0] : null;
    }

    function setCalendarHidden(calendarId, hidden, callback) {
        sendRequest("calendars.setHidden", {
            "calendarId": calendarId,
            "hidden": hidden
        }, response => {
            if (!response.error)
                refreshCalendars();
            if (callback)
                callback(response);
        });
    }

    function setCalendarSyncDisabled(calendarId, disabled, callback) {
        sendRequest("calendars.setSyncDisabled", {
            "calendarId": calendarId,
            "disabled": disabled
        }, response => {
            if (response.error) {
                lastError = response.error;
            } else {
                refreshCalendars();
                reloadEvents();
                reloadTasks();
            }
            if (callback)
                callback(response);
        });
    }

    function renameCalendar(calendarId, name, callback) {
        sendRequest("calendars.rename", {
            "calendarId": calendarId,
            "name": name
        }, response => {
            if (response.error)
                lastError = response.error;
            else
                refreshCalendars();
            if (callback)
                callback(response);
        });
    }

    function setCalendarReminders(calendarId, overrides, callback) {
        sendRequest("calendars.setReminders", {
            "calendarId": calendarId,
            "overrides": overrides || {}
        }, response => {
            if (response.error)
                lastError = response.error;
            else
                refreshCalendars();
            if (callback)
                callback(response);
        });
    }

    function deleteCalendar(calendarId, callback) {
        sendRequest("calendars.delete", {
            "calendarId": calendarId
        }, response => {
            if (response.error) {
                lastError = response.error;
            } else {
                refreshCalendars();
                reloadEvents();
            }
            if (callback)
                callback(response);
        });
    }

    function _ensureWindow() {
        if (!_loadedFrom || !_loadedTo) {
            reloadEvents();
            return;
        }
        const margin = 14 * 86400000;
        const t = focusDate.getTime();
        if (t < _loadedFrom.getTime() + margin || t > _loadedTo.getTime() - margin)
            reloadEvents();
    }

    function reloadEvents() {
        if (!connected)
            return;

        const from = new Date(focusDate.getTime() - 60 * 86400000);
        const to = new Date(focusDate.getTime() + 90 * 86400000);
        eventsLoading = true;
        sendRequest("events.list", {
            "from": from.toISOString(),
            "to": to.toISOString()
        }, response => {
            eventsLoading = false;
            if (response.error) {
                lastError = response.error;
                return;
            }
            _loadedFrom = from;
            _loadedTo = to;
            const raw = (response.result || {}).events || [];
            events = raw.map(e => _normalizeEvent(e));
            eventsUpdated();
        });
    }

    // All-day events are calendar dates stored at UTC midnight; pin them to
    // local midnights so they don't bleed into the previous day in negative
    // UTC offsets.
    function _dayBoundary(iso) {
        const d = new Date(iso);
        return new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
    }

    // Google withholds the summary of private events on calendars shared
    // with free/busy access; show them as busy like Google Calendar does.
    function untitledEventTitle(visibility) {
        if (visibility === "private" || visibility === "confidential")
            return I18n.tr("Busy", "fallback title for a private event whose details are hidden");
        return I18n.tr("(untitled)", "event details fallback title when event has no title");
    }

    function _normalizeEvent(e) {
        const allDay = !!e.allDay;
        const start = allDay ? _dayBoundary(e.start) : new Date(e.start);
        let end = allDay ? _dayBoundary(e.end) : new Date(e.end);
        // A degenerate end (before the start, or an exclusive all-day end on
        // the start date) would exclude the event from every range (#77).
        if (allDay && end <= start)
            end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 1);
        else if (end < start)
            end = start;
        return {
            "id": e.id,
            "uid": e.uid || "",
            "calendarId": e.calendarId || "",
            "title": e.summary || untitledEventTitle(e.visibility),
            "description": e.description || "",
            "location": e.location || "",
            "url": e.url || "",
            "meetingUrl": e.meetingUrl || "",
            "start": start,
            "end": end,
            "allDay": allDay,
            "status": e.status || "confirmed",
            "recurrence": (e.recurrence || {}).rrule || [],
            "recurringId": e.recurringId || "",
            "attendees": e.attendees || [],
            "organizer": e.organizer || null,
            "reminders": e.reminders || [],
            "visibility": e.visibility || ""
        };
    }

    function eventFromResult(raw) {
        return decorateEvent(_normalizeEvent(raw || {}));
    }

    // Card previews need plain text: descriptions arrive as HTML (Google web
    // UI) or markdown/plain text (Microsoft, CalDAV, local).
    function descriptionPreview(ev) {
        const raw = (ev.description || "").trim();
        if (raw === "")
            return "";
        let plain = raw;
        if (/<[a-z][^>]*>/i.test(raw))
            plain = raw.replace(/<(style|script)[\s\S]*?<\/\1>/gi, " ").replace(/<(br|\/p|\/div|\/li|\/tr)[^>]*>/gi, "\n").replace(/<[^>]+>/g, " ");
        plain = plain.replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&").replace(/&lt;/gi, "<").replace(/&gt;/gi, ">").replace(/&quot;/gi, "\"").replace(/&#39;/g, "'");
        // Separator-only lines ("---" footers) would waste the short preview.
        return plain.split("\n").map(line => line.replace(/[ \t]+/g, " ").trim()).filter(line => line !== "" && !/^[-_=*~—–·•.]{2,}$/.test(line)).join("\n");
    }

    function decorateEvent(ev) {
        const cal = calendarById(ev.calendarId);
        const out = Object.assign({}, ev);
        out.color = cal ? cal.color : fallbackPalette[0];
        out.calendar = cal ? cal.name : "";
        out.account = cal ? (cal.accountName || cal.accountId || "") : "";
        out.readOnly = cal ? !!cal.readOnly : false;
        const resp = selfResponse(out);
        out.myResponse = resp.status;
        out.canRespond = resp.canRespond;
        return out;
    }

    function calendarNames(ev) {
        return [ev.calendar].concat((ev.mergedFrom || []).map(other => other.calendar)).filter(name => name).join(", ");
    }

    function _hiddenCalendarIds() {
        const hidden = {};
        for (let i = 0; i < calendars.length; i++) {
            if (calendars[i].hidden)
                hidden[calendars[i].id] = true;
        }
        return hidden;
    }

    function eventsForRange(rangeStart, rangeEnd) {
        const hidden = _hiddenCalendarIds();
        const out = [];
        for (let i = 0; i < events.length; i++) {
            const ev = events[i];
            if (hidden[ev.calendarId])
                continue;
            if (ev.end <= rangeStart || ev.start >= rangeEnd)
                continue;
            out.push(decorateEvent(ev));
        }
        out.sort((a, b) => {
            if (a.allDay !== b.allDay)
                return a.allDay ? -1 : 1;
            return a.start - b.start;
        });
        return _mergeDuplicateEvents(out);
    }

    function eventsForDay(day) {
        const dayStart = new Date(day.getFullYear(), day.getMonth(), day.getDate());
        const dayEnd = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
        return eventsForRange(dayStart, dayEnd);
    }

    // Occurrence identity for selection: recurring occurrences share a uid and
    // may have an empty id, so both plus the start instant are needed.
    function eventKey(ev) {
        return EventUtils.eventKey(ev);
    }

    function visibleEvents() {
        const hidden = _hiddenCalendarIds();
        return _mergeDuplicateEvents(events.filter(ev => !hidden[ev.calendarId] && ev.status !== "cancelled").map(ev => decorateEvent(ev)).sort((left, right) => {
            const startDelta = left.start.getTime() - right.start.getTime();
            if (startDelta !== 0)
                return startDelta;
            if (left.allDay !== right.allDay)
                return left.allDay ? -1 : 1;
            return eventKey(left).localeCompare(eventKey(right));
        }));
    }

    // Google reuses the event id across attendee calendars, but invitations
    // from other providers get a per-calendar id, so title and time serve as
    // a fallback key.
    function _duplicateKeys(ev) {
        const start = ev.start.getTime();
        const keys = ["title|" + ev.title + "|" + start + "|" + ev.end.getTime() + "|" + ev.allDay];
        if (ev.uid)
            keys.unshift("uid|" + ev.uid + "|" + start);
        return keys;
    }

    function _duplicateRank(ev, calendarOrder) {
        return [ev.readOnly ? 1 : 0, ev.canRespond ? 0 : 1, -_detailScore(ev), calendarOrder[ev.calendarId] ?? calendars.length];
    }

    // Copies from private calendars arrive stripped of everything but the
    // time; the merged card must not pick one over a colleague's full copy.
    function _detailScore(ev) {
        return [(ev.attendees || []).length > 0, ev.description !== "", ev.location !== "", ev.meetingUrl !== ""].filter(Boolean).length;
    }

    function _mergeDuplicateEvents(list) {
        if (!SettingsData.mergeDuplicateEvents)
            return list;
        const groups = [];
        const byKey = {};
        for (const ev of list) {
            const keys = _duplicateKeys(ev);
            let group = null;
            for (const key of keys) {
                const candidate = byKey[key];
                if (candidate && !candidate.calendarIds[ev.calendarId]) {
                    group = candidate;
                    break;
                }
            }
            if (!group) {
                group = {
                    "members": [],
                    "calendarIds": {}
                };
                groups.push(group);
            }
            group.members.push(ev);
            group.calendarIds[ev.calendarId] = true;
            for (const key of keys) {
                if (!byKey[key])
                    byKey[key] = group;
            }
        }
        const calendarOrder = {};
        for (let i = 0; i < calendars.length; i++)
            calendarOrder[calendars[i].id] = i;
        return groups.map(group => {
            if (group.members.length === 1)
                return group.members[0];
            const ranked = group.members.slice().sort((left, right) => {
                const l = _duplicateRank(left, calendarOrder);
                const r = _duplicateRank(right, calendarOrder);
                for (let i = 0; i < l.length; i++) {
                    if (l[i] !== r[i])
                        return l[i] - r[i];
                }
                return 0;
            });
            const primary = Object.assign({}, ranked[0]);
            primary.mergedFrom = ranked.slice(1).map(ev => ({
                        "calendarId": ev.calendarId,
                        "calendar": ev.calendar,
                        "color": ev.color
                    }));
            return primary;
        });
    }

    function eventsByKeys(keys) {
        if (!keys || keys.length === 0)
            return [];
        const wanted = {};
        for (let i = 0; i < keys.length; i++)
            wanted[keys[i]] = true;
        return visibleEvents().filter(ev => wanted[eventKey(ev)]);
    }

    function layoutTimedEvents(events) {
        const sorted = events.slice().sort((a, b) => {
            if (a.startHour !== b.startHour)
                return a.startHour - b.startHour;
            return b.durationHours - a.durationHours;
        });

        let cluster = [];
        let clusterEnd = -1;
        const columnEnds = [];

        const flushCluster = () => {
            let columns = 0;
            for (const ev of cluster)
                columns = Math.max(columns, ev.column + 1);
            for (const ev of cluster)
                ev.columns = columns;
            cluster = [];
            columnEnds.length = 0;
            clusterEnd = -1;
        };

        for (const ev of sorted) {
            const start = ev.startHour;
            const end = ev.startHour + ev.durationHours;

            if (cluster.length > 0 && start >= clusterEnd)
                flushCluster();

            let column = columnEnds.findIndex(slotEnd => start >= slotEnd);
            if (column === -1) {
                column = columnEnds.length;
                columnEnds.push(end);
            } else {
                columnEnds[column] = end;
            }

            ev.column = column;
            cluster.push(ev);
            clusterEnd = Math.max(clusterEnd, end);
        }

        if (cluster.length > 0)
            flushCluster();

        return sorted;
    }

    function searchEvents(query, callback) {
        sendRequest("events.list", {
            "query": query
        }, response => {
            if (response.error) {
                lastError = response.error;
                callback({
                    "error": response.error,
                    "events": []
                });
                return;
            }
            const hidden = _hiddenCalendarIds();
            const raw = (response.result || {}).events || [];
            const out = [];
            for (let i = 0; i < raw.length; i++) {
                const ev = _normalizeEvent(raw[i]);
                if (hidden[ev.calendarId])
                    continue;
                if (ev.status === "cancelled")
                    continue;
                out.push(decorateEvent(ev));
            }
            callback({
                "events": _mergeDuplicateEvents(out)
            });
        });
    }

    function createEvent(fields, callback) {
        sendRequest("events.create", fields, response => {
            if (response.error)
                lastError = response.error;
            else
                reloadEvents();
            if (callback)
                callback(response);
        });
    }

    function updateEvent(id, fields, callback) {
        const params = Object.assign({
            "id": id
        }, fields);
        sendRequest("events.update", params, response => {
            if (response.error)
                lastError = response.error;
            else
                reloadEvents();
            if (callback)
                callback(response);
        });
    }

    function deleteEvent(id, callback, occurrenceStart) {
        const params = {
            "id": id
        };
        if (occurrenceStart)
            params.occurrenceStart = occurrenceStart;
        sendRequest("events.delete", params, response => {
            if (response.error)
                lastError = response.error;
            else
                reloadEvents();
            if (callback)
                callback(response);
        });
    }

    function mutateEvents(method, paramsList, callback) {
        const queue = paramsList || [];
        const results = [];
        const errors = [];
        let index = 0;

        const finish = () => {
            reloadEvents();
            const response = {
                "results": results,
                "errors": errors
            };
            if (errors.length > 0) {
                response.error = errors[0];
                lastError = errors[0];
            }
            if (callback)
                callback(response);
        };

        const sendNext = () => {
            if (index >= queue.length) {
                finish();
                return;
            }
            sendRequest(method, queue[index], response => {
                if (response.error)
                    errors.push(response.error);
                else
                    results.push(response.result);
                index++;
                sendNext();
            });
        };

        if (queue.length === 0) {
            if (callback)
                callback({
                    "results": [],
                    "errors": []
                });
            return;
        }
        sendNext();
    }

    function createEvents(fields, callback) {
        mutateEvents("events.create", fields, callback);
    }

    function moveEvents(eventsToMove, dayOffset, minuteOffset, callback) {
        const params = eventsToMove.map(event => Object.assign({
                "id": event.id
            }, EventUtils.moveFields(event, dayOffset, minuteOffset)));
        mutateEvents("events.update", params, callback);
    }

    function deleteEvents(eventsToDelete, callback) {
        const params = eventsToDelete.map(event => {
            const fields = {
                "id": event.id
            };
            if ((event.recurringId || "") !== "" || (event.recurrence || []).length > 0)
                fields.occurrenceStart = EventUtils.wireTime(event.start, event.allDay);
            return fields;
        });
        mutateEvents("events.delete", params, callback);
    }

    function reloadTasks() {
        if (!connected)
            return;

        sendRequest("tasks.list", {
            "includeCompleted": true,
            "limit": 5000
        }, response => {
            if (response.error) {
                lastError = response.error;
                return;
            }
            const raw = (response.result || {}).tasks || [];
            const next = raw.map(t => _applyPendingState(_normalizeTask(t)));
            if (JSON.stringify(next) !== JSON.stringify(tasks))
                tasks = next;
            tasksUpdated();
        });
    }

    // A completion toggle is applied optimistically; slow providers can serve a
    // reload that predates the write, so the desired state wins over a
    // disagreeing reload until the daemon confirms it or the hold expires.
    function _applyPendingState(t) {
        const pending = _pendingTaskState[t.id];
        if (!pending)
            return t;
        if (t.completed === pending.completed || Date.now() > pending.expires) {
            delete _pendingTaskState[t.id];
            return t;
        }
        return Object.assign({}, t, {
            "completed": pending.completed,
            "status": pending.completed ? "completed" : "needs_action"
        });
    }

    function _normalizeTask(t) {
        const allDay = !!t.allDay;
        let due = null;
        if (t.due)
            due = allDay ? _dayBoundary(t.due) : new Date(t.due);
        return {
            "id": t.id,
            "uid": t.uid || "",
            "calendarId": t.calendarId || "",
            "title": t.summary || "(untitled)",
            "description": t.description || "",
            "location": t.location || "",
            "status": t.status || "needs_action",
            "completed": t.status === "completed",
            "priority": t.priority || 0,
            "percentComplete": t.percentComplete || 0,
            "due": due,
            "allDay": allDay,
            "parentUid": t.parentUid || "",
            "recurrence": t.recurrence || [],
            "recurring": (t.recurrence || []).length > 0
        };
    }

    // calendarAccountKind resolves a calendar's provider kind (e.g. "google",
    // "caldav", "local"), used to gate features a provider can't support such as
    // editing recurrence on Google task lists.
    function calendarAccountKind(calendarId) {
        const cal = calendarById(calendarId);
        if (!cal)
            return "";
        const acc = accountById(cal.accountId);
        return acc ? (acc.kind || "") : "";
    }

    // recurrenceLabel summarizes an event's or task's RRULE for display. It
    // understands the FREQ/INTERVAL/BYDAY/COUNT/UNTIL subset the editors
    // produce; anything else falls back to a generic "Repeats" so unknown
    // rules still read sensibly.
    function recurrenceLabel(item) {
        const rules = item.recurrence || [];
        if (rules.length === 0)
            return "";
        let freq = "";
        let interval = 1;
        let byDay = [];
        let count = 0;
        let until = null;
        const parts = rules[0].split(";");
        for (let i = 0; i < parts.length; i++) {
            const kv = parts[i].split("=");
            switch (kv[0]) {
            case "FREQ":
                freq = kv[1];
                break;
            case "INTERVAL":
                interval = parseInt(kv[1]) || 1;
                break;
            case "BYDAY":
                byDay = kv[1].split(",");
                break;
            case "COUNT":
                count = parseInt(kv[1]) || 0;
                break;
            case "UNTIL":
                until = rruleUntilDate(kv[1]);
                break;
            }
        }
        const unit = {
            "DAILY": [I18n.tr("day", "recurrence unit singular"), I18n.tr("days", "recurrence unit plural")],
            "WEEKLY": [I18n.tr("week", "recurrence unit singular"), I18n.tr("weeks", "recurrence unit plural")],
            "MONTHLY": [I18n.tr("month", "recurrence unit singular"), I18n.tr("months", "recurrence unit plural")],
            "YEARLY": [I18n.tr("year", "recurrence unit singular"), I18n.tr("years", "recurrence unit plural")]
        }[freq];
        if (!unit)
            return I18n.tr("Repeats", "generic recurrence label for an unrecognized rule");

        let label = interval <= 1 ? I18n.tr("Repeats every %1", "recurrence label, %1 is a unit like 'day'").arg(unit[0]) : I18n.tr("Repeats every %1 %2", "recurrence label, %1 is a count and %2 a unit like 'weeks'").arg(interval).arg(unit[1]);

        if (freq === "WEEKLY" && byDay.length > 0) {
            const codes = {
                "SU": 0,
                "MO": 1,
                "TU": 2,
                "WE": 3,
                "TH": 4,
                "FR": 5,
                "SA": 6
            };
            const names = byDay.filter(c => codes[c] !== undefined).map(c => SettingsData.dayName(codes[c]));
            if (names.length > 0)
                label += " " + I18n.tr("on %1", "recurrence label suffix listing weekdays, %1 like 'Mon, Wed'").arg(names.join(", "));
        }
        if (count > 0)
            label += ", " + I18n.tr("%1 times", "recurrence label suffix for a fixed number of occurrences").arg(count);
        else if (until)
            label += ", " + I18n.tr("until %1", "recurrence label suffix with an end date").arg(SettingsData.formatDate(until, "MMM d, yyyy"));
        return label;
    }

    // rruleUntilDate parses an RRULE UNTIL value (YYYYMMDD or
    // YYYYMMDDTHHMMSSZ) into a local date, null when unrecognized.
    function rruleUntilDate(value) {
        if (!/^\d{8}(T\d{6}Z?)?$/.test(value || ""))
            return null;
        return new Date(parseInt(value.slice(0, 4)), parseInt(value.slice(4, 6)) - 1, parseInt(value.slice(6, 8)));
    }

    function decorateTask(t) {
        const cal = calendarById(t.calendarId);
        const out = Object.assign({}, t);
        out.color = cal ? cal.color : fallbackPalette[0];
        out.calendar = cal ? cal.name : "";
        out.account = cal ? (cal.accountName || cal.accountId || "") : "";
        out.accountSummary = accountSummary(t.calendarId);
        out.readOnly = cal ? !!cal.readOnly : false;
        return out;
    }

    function taskListCalendars() {
        return calendars.filter(c => c.holdsTasks && !c.readOnly && !c.syncDisabled);
    }

    function hasTaskLists() {
        return calendars.some(c => c.holdsTasks && !c.syncDisabled);
    }

    function visibleTasks(includeCompleted) {
        const hidden = _hiddenCalendarIds();
        const out = [];
        for (let i = 0; i < tasks.length; i++) {
            const t = tasks[i];
            if (hidden[t.calendarId])
                continue;
            if (!includeCompleted && t.completed)
                continue;
            out.push(decorateTask(t));
        }
        out.sort(_compareTasks);
        return out;
    }

    // _compareTasks orders by due date (undated last), then by priority with 1
    // highest and 0 (unset) last, then title.
    function _compareTasks(a, b) {
        if (!!a.due !== !!b.due)
            return a.due ? -1 : 1;
        if (a.due && b.due && a.due.getTime() !== b.due.getTime())
            return a.due - b.due;
        const pa = a.priority || 10;
        const pb = b.priority || 10;
        if (pa !== pb)
            return pa - pb;
        return a.title.localeCompare(b.title);
    }

    function taskBuckets() {
        const now = new Date();
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const todayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
        const buckets = {
            "overdue": [],
            "today": [],
            "upcoming": [],
            "someday": []
        };
        const open = visibleTasks(false);
        for (let i = 0; i < open.length; i++) {
            const t = open[i];
            if (!t.due)
                buckets.someday.push(t);
            else if (t.due < todayStart)
                buckets.overdue.push(t);
            else if (t.due < todayEnd)
                buckets.today.push(t);
            else
                buckets.upcoming.push(t);
        }
        return buckets;
    }

    function createTask(fields, callback) {
        sendRequest("tasks.create", fields, response => {
            if (response.error)
                lastError = response.error;
            else
                reloadTasks();
            if (callback)
                callback(response);
        });
    }

    function updateTask(id, fields, callback) {
        const params = Object.assign({
            "id": id
        }, fields);
        sendRequest("tasks.update", params, response => {
            if (response.error)
                lastError = response.error;
            else
                reloadTasks();
            if (callback)
                callback(response);
        });
    }

    function completeTask(id, completed, callback) {
        _pendingTaskState[id] = {
            "completed": completed,
            "expires": Date.now() + 15000
        };
        sendRequest("tasks.complete", {
            "id": id,
            "completed": completed
        }, response => {
            if (response.error) {
                lastError = response.error;
                delete _pendingTaskState[id];
                reloadTasks();
            }
            if (callback)
                callback(response);
        });
    }

    // _patchTaskLocally optimistically updates an in-memory task so the UI
    // reflects a change instantly while the (possibly remote, slow) request is in
    // flight. The next reloadTasks reconciles against the server's truth.
    function _patchTaskLocally(id, changes) {
        const next = tasks.slice();
        for (let i = 0; i < next.length; i++) {
            if (next[i].id === id) {
                next[i] = Object.assign({}, next[i], changes);
                break;
            }
        }
        tasks = next;
        tasksUpdated();
    }

    // Optimistic toggle (providers like Google take a second to ack) with an Undo
    // toast so an accidental tap is one click to reverse.
    function completeTaskWithUndo(task) {
        const id = task.id;
        const wasDone = task.completed === true || task.status === "completed";
        const apply = done => _patchTaskLocally(id, {
                "completed": done,
                "status": done ? "completed" : "needs_action"
            });
        apply(!wasDone);
        completeTask(id, !wasDone, response => {
            if (response.error) {
                reloadTasks();
                ToastService.show(I18n.tr("Couldn't update task", "toast when a task update fails"), {});
                return;
            }
            ToastService.show(wasDone ? I18n.tr("Marked as not done", "toast after un-completing a task") : I18n.tr("Task completed", "toast after completing a task"), {
                "actionLabel": I18n.tr("Undo", "toast undo action"),
                "action": () => {
                    apply(wasDone);
                    completeTask(id, wasDone);
                }
            });
        });
    }

    function deleteTask(id, callback) {
        sendRequest("tasks.delete", {
            "id": id
        }, response => {
            if (response.error)
                lastError = response.error;
            else
                reloadTasks();
            if (callback)
                callback(response);
        });
    }

    function parseIcs(ics, calendarId, callback) {
        sendRequest("events.parseIcs", {
            "calendarId": calendarId,
            "ics": ics
        }, callback);
    }

    function importIcs(ics, calendarId, uids, callback) {
        const params = {
            "ics": ics,
            "calendarId": calendarId
        };
        if (uids && uids.length > 0)
            params.uids = uids;
        sendRequest("events.importIcs", params, response => {
            if (response.error)
                lastError = response.error;
            else
                reloadEvents();
            if (callback)
                callback(response);
        });
    }

    function rsvpEvent(id, response, callback, occurrenceStart) {
        const params = {
            "id": id,
            "response": response
        };
        if (occurrenceStart)
            params.occurrenceStart = occurrenceStart;
        sendRequest("events.rsvp", params, resp => {
            if (resp.error)
                lastError = resp.error;
            else
                reloadEvents();
            if (callback)
                callback(resp);
        });
    }

    function _rsvpNormalizeEmail(s) {
        if (!s)
            return "";
        s = String(s).trim();
        if (s.toLowerCase().indexOf("mailto:") === 0)
            s = s.substring(7);
        return s.toLowerCase();
    }

    function _rsvpNormalizeStatus(s) {
        switch (String(s || "").toLowerCase()) {
        case "accepted":
        case "accept":
            return "accepted";
        case "declined":
        case "decline":
            return "declined";
        case "tentative":
        case "tentativelyaccepted":
        case "maybe":
            return "tentative";
        case "organizer":
            return "accepted";
        default:
            return "needs-action";
        }
    }

    // selfEmailForCalendar resolves the current user's email for an account, used
    // to find them among an event's attendees. Google and Microsoft store the
    // email as the account id; CalDAV keeps the login in settings. Other kinds
    // have no personal identity.
    function selfEmailForCalendar(calendarId) {
        const cal = calendarById(calendarId);
        if (!cal)
            return "";
        const acc = accountById(cal.accountId);
        if (!acc)
            return "";
        if (acc.kind === "google" || acc.kind === "microsoft")
            return _rsvpNormalizeEmail(acc.id);
        if (acc.kind === "caldav" && acc.settings && acc.settings.username)
            return _rsvpNormalizeEmail(acc.settings.username);
        return "";
    }

    // selfResponse reports the current user's RSVP status for an event and
    // whether they may respond (a non-organizer attendee on a writable calendar).
    function selfResponse(ev) {
        const cal = calendarById(ev.calendarId);
        if (!cal || cal.readOnly)
            return {
                "status": "",
                "canRespond": false
            };
        const self = selfEmailForCalendar(ev.calendarId);
        if (!self)
            return {
                "status": "",
                "canRespond": false
            };
        if (ev.organizer && _rsvpNormalizeEmail(ev.organizer.email) === self)
            return {
                "status": "accepted",
                "canRespond": false
            };
        const attendees = ev.attendees || [];
        for (let i = 0; i < attendees.length; i++) {
            if (_rsvpNormalizeEmail(attendees[i].email) !== self)
                continue;
            if (attendees[i].organizer)
                return {
                    "status": "accepted",
                    "canRespond": false
                };
            return {
                "status": _rsvpNormalizeStatus(attendees[i].status),
                "canRespond": true
            };
        }
        return {
            "status": "",
            "canRespond": false
        };
    }

    function startGoogleFlow(displayName, clientId, clientSecret, callback) {
        const params = {
            "displayName": displayName || "",
            "clientId": clientId,
            "clientSecret": clientSecret
        };
        sendRequest("accounts.google.start", params, response => {
            if (response.error) {
                lastError = response.error;
                if (callback)
                    callback(response);
                return;
            }
            const result = response.result || {};
            googleFlowStarted(result.state, result.authUrl);
            if (callback)
                callback(response);
        });
    }

    function completeGoogleFlow(state, callback) {
        sendRequest("accounts.google.complete", {
            "state": state
        }, response => {
            if (response.error) {
                lastError = response.error;
                googleFlowFailed(state, response.error);
                if (callback)
                    callback(response);
                return;
            }
            const result = response.result || {};
            googleFlowCompleted(result.accountId, result.email);
            accountAdded(result.accountId);
            refreshAccounts();
            if (callback)
                callback(response);
        });
    }

    function cancelGoogleFlow(state, callback) {
        sendRequest("accounts.google.cancel", {
            "state": state
        }, callback);
    }

    function startMicrosoftFlow(clientId, callback) {
        sendRequest("accounts.microsoft.start", {
            "clientId": clientId
        }, response => {
            if (response.error) {
                lastError = response.error;
                if (callback)
                    callback(response);
                return;
            }
            const result = response.result || {};
            microsoftFlowStarted(result.state, result.authUrl);
            if (callback)
                callback(response);
        });
    }

    function completeMicrosoftFlow(state, callback) {
        sendRequest("accounts.microsoft.complete", {
            "state": state
        }, response => {
            if (response.error) {
                lastError = response.error;
                microsoftFlowFailed(state, response.error);
                if (callback)
                    callback(response);
                return;
            }
            const result = response.result || {};
            microsoftFlowCompleted(result.accountId, result.email);
            accountAdded(result.accountId);
            refreshAccounts();
            if (callback)
                callback(response);
        });
    }

    function cancelMicrosoftFlow(state, callback) {
        sendRequest("accounts.microsoft.cancel", {
            "state": state
        }, callback);
    }

    function offerAccountReAdd(msg) {
        ToastService.show(msg, {
            "actionLabel": I18n.tr("Add account", "toast action to re-add an account that failed to reconnect"),
            "action": () => addAccountRequested()
        });
    }

    function reconnectAccount(acc, callback) {
        if (!acc)
            return;

        let startMethod = "";
        let completeMethod = "";
        switch (acc.kind) {
        case "google":
            startMethod = "accounts.google.reauth";
            completeMethod = "accounts.google.complete";
            break;
        case "microsoft":
            startMethod = "accounts.microsoft.reauth";
            completeMethod = "accounts.microsoft.complete";
            break;
        default:
            lastError = I18n.tr("This account cannot be reconnected — remove it and add it again.", "error when reconnect is unavailable for a provider");
            offerAccountReAdd(lastError);
            if (callback)
                callback({
                    "error": lastError
                });
            return;
        }

        const reconnectFailed = I18n.tr("Couldn't reconnect. Add the account again to sign in.", "toast when reconnecting an account fails");
        sendRequest(startMethod, {
            "accountId": acc.id
        }, response => {
            if (response.error) {
                lastError = response.error;
                offerAccountReAdd(reconnectFailed);
                if (callback)
                    callback(response);
                return;
            }
            const result = response.result || {};
            Qt.openUrlExternally(result.authUrl);
            sendRequest(completeMethod, {
                "state": result.state
            }, done => {
                if (done.error) {
                    lastError = done.error;
                    offerAccountReAdd(reconnectFailed);
                } else {
                    refreshAccounts();
                }
                if (callback)
                    callback(done);
            });
        });
    }

    function addCalDAVAccount(url, username, password, displayName, insecureSkipVerify, callback) {
        sendRequest("accounts.caldav.add", {
            "url": url,
            "username": username,
            "password": password,
            "displayName": displayName || "",
            "insecureSkipVerify": insecureSkipVerify || false
        }, response => {
            if (response.error) {
                lastError = response.error;
            } else {
                const result = response.result || {};
                accountAdded(result.accountId);
                refreshAccounts();
            }
            if (callback)
                callback(response);
        });
    }

    function addICalAccount(url, name, username, password, callback) {
        sendRequest("accounts.ical.add", {
            "url": url,
            "username": username || "",
            "password": password || "",
            "displayName": name || ""
        }, response => {
            if (response.error) {
                lastError = response.error;
            } else {
                const result = response.result || {};
                accountAdded(result.accountId);
                refreshAccounts();
            }
            if (callback)
                callback(response);
        });
    }

    function addLocalAccount(rootPath, displayName, callback) {
        sendRequest("accounts.local.add", {
            "root": rootPath,
            "displayName": displayName || ""
        }, response => {
            if (response.error) {
                lastError = response.error;
            } else {
                const result = response.result || {};
                accountAdded(result.accountId);
                refreshAccounts();
            }
            if (callback)
                callback(response);
        });
    }

    function addEvolutionAccount(displayName, callback) {
        sendRequest("accounts.evolution.add", {
            "displayName": displayName || ""
        }, response => {
            if (response.error) {
                lastError = response.error;
            } else {
                const result = response.result || {};
                accountAdded(result.accountId);
                refreshAccounts();
            }
            if (callback)
                callback(response);
        });
    }

    function createCalendar(accountId, name, callback) {
        sendRequest("calendars.create", {
            "accountId": accountId,
            "name": name
        }, response => {
            if (response.error)
                lastError = response.error;
            else
                refreshCalendars();
            if (callback)
                callback(response);
        });
    }

    function removeAccount(accountId, callback) {
        sendRequest("accounts.delete", {
            "accountId": accountId
        }, response => {
            if (!response.error) {
                accountRemoved(accountId);
                refreshAccounts();
                refreshCalendars();
                reloadEvents();
            }
            if (callback)
                callback(response);
        });
    }

    function sendTestReminder(callback) {
        sendRequest("reminders.test", null, response => {
            if (response.error)
                lastError = response.error;
            if (callback)
                callback(response);
        });
    }

    function refreshAutostart() {
        sendRequest("system.autostart.get", null, response => {
            if (!response.error)
                autostartEnabled = !!(response.result || {}).enabled;
        });
    }

    function setAutostart(enabled, callback) {
        sendRequest("system.autostart.set", {
            "enabled": enabled
        }, response => {
            if (response.error)
                lastError = response.error;
            else
                autostartEnabled = !!(response.result || {}).enabled;
            if (callback)
                callback(response);
        });
    }

    function restart() {
        sendRequest("ui.restart", null, response => {
            if (response.error)
                lastError = response.error;
        });
    }

    function quit() {
        if (connected) {
            sendRequest("ui.quit", null, null);
            return;
        }
        Qt.quit();
    }

    function refreshAccount(accountId, callback) {
        sendRequest("accounts.refresh", {
            "accountId": accountId
        }, callback);
    }

    function refreshAll(callback) {
        eventsLoading = true;
        sendRequest("accounts.refresh", {}, callback);
    }

    function accountFlavor(acc) {
        if (!acc)
            return "";
        const settings = acc.settings || {};
        if (acc.kind === "caldav" && (settings.preset === "icloud" || (settings.url || "").indexOf("icloud.com") !== -1))
            return "icloud";
        return acc.kind;
    }

    function accountLabel(acc) {
        if (!acc)
            return "";
        if (acc.displayName && acc.displayName !== acc.id)
            return acc.displayName;
        const settings = acc.settings || {};
        return settings.username || acc.displayName || acc.id;
    }

    function providerLabel(flavor) {
        switch (flavor) {
        case "google":
            return "Google";
        case "microsoft":
            return "Microsoft";
        case "icloud":
            return "iCloud";
        case "caldav":
            return "CalDAV";
        case "local":
            return I18n.tr("Local", "provider label for a local account");
        default:
            return flavor;
        }
    }

    // accountSummary renders a calendar's owning account as "Provider · label"
    // (e.g. "Google · me@gmail.com"), or just the provider when there's no label.
    function accountSummary(calendarId) {
        const cal = calendarById(calendarId);
        if (!cal)
            return "";
        const acc = accountById(cal.accountId);
        if (!acc)
            return cal.accountName || "";
        const provider = providerLabel(accountFlavor(acc));
        const label = accountLabel(acc);
        if (!label || label === provider)
            return provider;
        return provider + " · " + label;
    }
}
