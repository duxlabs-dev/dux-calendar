pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root

    enum AnimationSpeed {
        None,
        Short,
        Medium,
        Long,
        Custom
    }

    enum TextRenderType {
        Qt,
        Native,
        Curve
    }

    enum TextRenderQuality {
        Default,
        Low,
        Normal,
        High,
        VeryHigh
    }

    property bool popoutElevationEnabled: true
    property int textRenderType: SettingsData.TextRenderType.Qt
    property int textRenderQuality: SettingsData.TextRenderQuality.Default
    property int animationSpeed: SettingsData.AnimationSpeed.Short
    property bool blurBorderEnabled: true
    property real blurBorderOpacity: 0.35
    property string blurBorderColor: "outline"
    property string blurBorderCustomColor: "#ffffff"
    property bool powerActionConfirm: true
    property real powerActionHoldDuration: 0.5
    property var powerMenuActions: ["reboot", "logout", "poweroff", "lock", "suspend", "restart"]
    property string powerMenuDefaultAction: "logout"
    property bool powerMenuGridLayout: false

    readonly property string configDir: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const base = (xdg && xdg !== "") ? xdg : Quickshell.env("HOME") + "/.config";
        return base + "/dankcal";
    }
    readonly property string settingsPath: configDir + "/ui-settings.json"

    // "auto" | "light" | "dark"
    property alias themeMode: adapter.themeMode
    // "auto" follows DMS dynamic colors when available, falling back to the
    // chosen preset; "preset" forces a bundled palette; "custom" loads a JSON file;
    // "matugen" loads matugen-theme.json from configDir.
    property alias colorSource: adapter.colorSource
    property alias presetTheme: adapter.presetTheme
    property alias customThemeFile: adapter.customThemeFile
    // 0 (square) … 100; 50 keeps the Material shape scale
    property alias radiusStrength: adapter.radiusStrength
    // base transition length in ms, 0 disables animations
    property alias animationDuration: adapter.animationDuration
    property alias reduceMotion: adapter.reduceMotion
    // 0 smooth, 1 balanced, 2 playful
    property alias springBounce: adapter.springBounce
    property alias enableRippleEffects: adapter.enableRippleEffects
    property alias fontSource: adapter.fontSource
    property alias fontFamily: adapter.fontFamily
    property alias monoFontFamily: adapter.monoFontFamily
    property alias displayFontFamily: adapter.displayFontFamily
    property alias fontWeight: adapter.fontWeight
    property alias fontScale: adapter.fontScale
    property alias uiScale: adapter.uiScale
    readonly property real effectiveUiScale: parseFloat(Quickshell.env("QT_SCALE_FACTOR")) || 1
    // dcal sets DANKCAL_UI_SCALE only when uiScale is in control
    readonly property bool uiScaleFromEnv: !!Quickshell.env("QT_SCALE_FACTOR") && !Quickshell.env("DANKCAL_UI_SCALE")
    property alias focusRingEnabled: adapter.focusRingEnabled
    property alias focusRingWidth: adapter.focusRingWidth
    // "primary" | "secondary" | "outline" | "surfaceText"
    property alias focusRingColor: adapter.focusRingColor
    property alias windowTitleBars: adapter.windowTitleBars
    property alias floatingWindowTransparency: adapter.floatingWindowTransparency
    property alias floatingWindowForegroundLayers: adapter.floatingWindowForegroundLayers
    property alias floatingWindowForegroundTransparency: adapter.floatingWindowForegroundTransparency
    property alias blurEnabled: adapter.blurEnabled
    // "" follows the system language, otherwise a bundled translation code such as "de" or "zh_CN"
    property alias language: adapter.language
    // "" follows the interface language for date and time names, otherwise a locale code
    property alias timeLocale: adapter.timeLocale
    // -1 = locale default, otherwise 0 (Sunday) … 6 (Saturday)
    property alias firstDayOfWeek: adapter.firstDayOfWeek
    // "auto" | "12h" | "24h"
    property alias timeFormat: adapter.timeFormat
    property alias coreHoursEnabled: adapter.coreHoursEnabled
    property alias coreHoursStart: adapter.coreHoursStart
    property alias coreHoursEnd: adapter.coreHoursEnd
    property alias showWeekNumbers: adapter.showWeekNumbers
    property alias showTasks: adapter.showTasks
    property alias monthEventTitleLines: adapter.monthEventTitleLines
    property alias monthShowAllEvents: adapter.monthShowAllEvents
    property alias mergeDuplicateEvents: adapter.mergeDuplicateEvents
    property alias weekEventTitleLines: adapter.weekEventTitleLines
    property alias defaultEventDurationMinutes: adapter.defaultEventDurationMinutes
    // -1 = no reminder
    property alias defaultReminderMinutes: adapter.defaultReminderMinutes
    // "" = first writable calendar
    property alias defaultCalendarId: adapter.defaultCalendarId
    property alias remindersEnabled: adapter.remindersEnabled
    property alias reminderPersist: adapter.reminderPersist
    property alias allDayReminders: adapter.allDayReminders
    // "HH:mm" local wall-clock time the all-day reminder fires
    property alias allDayReminderTime: adapter.allDayReminderTime
    property alias allDayReminderDaysBefore: adapter.allDayReminderDaysBefore
    property alias snoozeMinutes: adapter.snoozeMinutes
    property alias notificationSounds: adapter.notificationSounds
    property alias showTrayIcon: adapter.showTrayIcon
    property alias syncIntervalMinutes: adapter.syncIntervalMinutes
    // "minimize" = hide to tray, "quit" = stop the daemon and child
    property alias closeBehavior: adapter.closeBehavior
    // width of the calendar sidebar in pixels, set by dragging its edge
    property alias sidebarWidth: adapter.sidebarWidth
    // whether the calendar sidebar is hidden in non-compact mode
    property alias sidebarCollapsed: adapter.sidebarCollapsed
    // last active calendar view, restored on open: "month" | "week" | "day" | "agenda"
    property alias lastView: adapter.lastView
    // "accountId:noticeCode" entries the user closed in the accounts list
    property alias dismissedAccountNotices: adapter.dismissedAccountNotices

    function isNoticeDismissed(accountId, code) {
        return dismissedAccountNotices.indexOf(accountId + ":" + code) !== -1;
    }

    function dismissNotice(accountId, code) {
        if (isNoticeDismissed(accountId, code))
            return;
        dismissedAccountNotices = dismissedAccountNotices.concat([accountId + ":" + code]);
    }

    readonly property var locale: {
        if (timeLocale !== "")
            return Qt.locale(timeLocale);
        if (language !== "")
            return Qt.locale(language);
        return Qt.locale();
    }
    // Qt reports Monday=1 … Sunday=7; views use JS getDay() where Sunday=0
    readonly property int localeFirstDayOfWeek: locale.firstDayOfWeek % 7
    readonly property bool localeUses24Hour: {
        // Qt emits AM/PM as AP/ap/Ap/A/a depending on locale data; anything
        // a-ish outside quoted literals means a 12-hour clock.
        const fmt = locale.timeFormat(Locale.ShortFormat).replace(/'[^']*'/g, "");
        return !/[aA]/.test(fmt);
    }

    readonly property int effectiveFirstDayOfWeek: (firstDayOfWeek >= 0 && firstDayOfWeek <= 6) ? firstDayOfWeek : localeFirstDayOfWeek
    readonly property bool coreHoursValid: coreHoursStart >= 0 && coreHoursEnd <= 24 && coreHoursEnd > coreHoursStart
    readonly property real effectiveHourStart: (coreHoursEnabled && coreHoursValid) ? coreHoursStart : 0
    readonly property real effectiveHourEnd: (coreHoursEnabled && coreHoursValid) ? coreHoursEnd : 24
    readonly property bool use24HourTime: {
        switch (timeFormat) {
        case "12h":
            return false;
        case "24h":
            return true;
        default:
            return localeUses24Hour;
        }
    }
    // The daemon formats notification times from ui-settings.json but cannot
    // resolve "auto" against the Qt locale, so persist the resolved value.
    onUse24HourTimeChanged: adapter.use24HourClock = use24HourTime

    function formatTime(d) {
        if (!d)
            return "";
        return d.toLocaleTimeString(locale, use24HourTime ? "HH:mm" : "h:mm AP");
    }

    function formatDate(d, format) {
        if (!d)
            return "";
        return d.toLocaleDateString(locale, format);
    }

    function dayName(jsDay, format) {
        return locale.dayName(jsDay, format !== undefined ? format : Locale.ShortFormat);
    }

    function monthName(jsMonth, format) {
        return locale.monthName(jsMonth, format !== undefined ? format : Locale.LongFormat);
    }

    Component.onCompleted: {
        Paths.mkdir(configDir);
        adapter.use24HourClock = use24HourTime;
    }

    FileView {
        id: settingsFile
        path: root.settingsPath
        // Persistence guards mirror DMS Common/SettingsData.qml: block the
        // initial load so the adapter is populated up front, gate writes on
        // _loaded so the load itself never serializes a half-default adapter
        // back over the saved file, and ignore our own writes via _selfWrite so
        // a write does not trigger a reload storm.
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        printErrors: false

        property bool _loaded: false
        property bool _selfWrite: false

        onLoaded: _loaded = true
        onLoadFailed: _loaded = true
        onFileChanged: {
            if (_selfWrite) {
                _selfWrite = false;
                return;
            }
            reload();
        }
        onAdapterUpdated: {
            if (!_loaded)
                return;
            _selfWrite = true;
            writeAdapter();
        }

        JsonAdapter {
            id: adapter
            property string themeMode: "auto"
            property string colorSource: "auto"
            property string presetTheme: "purple"
            property string customThemeFile: ""
            property int radiusStrength: 50
            property int animationDuration: 250
            property bool reduceMotion: false
            property int springBounce: 1
            property bool enableRippleEffects: true
            property string fontSource: "auto"
            property string fontFamily: ""
            property string monoFontFamily: ""
            property string displayFontFamily: ""
            property int fontWeight: 400
            property real fontScale: 1.0
            property real uiScale: 1.0
            property bool focusRingEnabled: true
            property real focusRingWidth: 1.5
            property string focusRingColor: "primary"
            property bool windowTitleBars: true
            property real floatingWindowTransparency: 1.0
            property bool floatingWindowForegroundLayers: true
            property real floatingWindowForegroundTransparency: 1.0
            property bool blurEnabled: false
            property string language: ""
            property string timeLocale: ""
            property int firstDayOfWeek: -1
            property string timeFormat: "auto"
            property bool use24HourClock: true
            property bool coreHoursEnabled: false
            property real coreHoursStart: 9
            property real coreHoursEnd: 17
            property bool showWeekNumbers: false
            property bool showTasks: true
            property int monthEventTitleLines: 1
            property bool monthShowAllEvents: false
            property bool mergeDuplicateEvents: false
            property int weekEventTitleLines: 1
            property int defaultEventDurationMinutes: 30
            property int defaultReminderMinutes: 10
            property string defaultCalendarId: ""
            property bool remindersEnabled: true
            property bool reminderPersist: true
            property bool allDayReminders: false
            property string allDayReminderTime: "09:00"
            property int allDayReminderDaysBefore: 0
            property int snoozeMinutes: 5
            property bool notificationSounds: false
            property bool showTrayIcon: true
            property int syncIntervalMinutes: 30
            property string closeBehavior: "minimize"
            property int sidebarWidth: 240
            property bool sidebarCollapsed: false
            property string lastView: "month"
            property var dismissedAccountNotices: []
        }
    }
}
