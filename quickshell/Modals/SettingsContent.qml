import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.FileBrowser
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.DCommon.Common as DC

Item {
    id: root

    property int currentIndex: 0
    property var hostWindow: null

    readonly property var colorSourceOptions: [
        {
            label: I18n.tr("Auto", "color source button group option following DMS"),
            value: "auto"
        },
        {
            label: I18n.tr("Matugen", "color source button group option for Matugen"),
            value: "matugen"
        },
        {
            label: I18n.tr("Preset", "color source button group option for bundled palettes"),
            value: "preset"
        },
        {
            label: I18n.tr("Custom", "color source button group option for a custom theme file"),
            value: "custom"
        }
    ]

    readonly property var fontSourceOptions: [
        {
            label: I18n.tr("Auto", "font source button group option following DMS"),
            value: "auto"
        },
        {
            label: I18n.tr("System", "font source button group option for the Qt system font"),
            value: "system"
        },
        {
            label: I18n.tr("Custom", "font source button group option for app-chosen fonts"),
            value: "custom"
        }
    ]

    signal addAccountRequested

    // Maps comma-joined backend sync-notice codes to a per-account hint shown when
    // an account partially degrades (e.g. Tasks API disabled, calendars still OK).
    function accountNotice(account) {
        if (!account.notice)
            return "";
        const parts = account.notice.split(",").filter(c => !SettingsData.isNoticeDismissed(account.id, c)).map(c => root._accountNoticeOne(account.kind, c)).filter(s => s !== "");
        return parts.join("<br/>");
    }

    function dismissAccountNotice(account) {
        account.notice.split(",").forEach(c => SettingsData.dismissNotice(account.id, c));
    }

    function _accountNoticeOne(kind, code) {
        switch (code) {
        case "tasks_unavailable":
            if (kind === "google")
                return I18n.tr('Google Tasks is unavailable. <a href="https://console.cloud.google.com/apis/library/tasks.googleapis.com" style="text-decoration:none; color:%1;">Enable its API</a> or reconnect this account, then refresh, to sync tasks.', 'account notice when google tasks is disabled or its permission is missing').arg(Theme.primary);
            if (kind === "microsoft")
                return I18n.tr("Microsoft To Do access wasn't granted. Reconnect this account to sync tasks.", "account notice when microsoft to do permission is missing");
            return I18n.tr("Task lists couldn't be loaded; calendars are still syncing.", "account notice when task lists are unavailable but calendars sync");
        case "calendars_unavailable":
            if (kind === "google")
                return I18n.tr('Google Calendar API is disabled. <a href="https://console.cloud.google.com/apis/library/calendar-json.googleapis.com" style="text-decoration:none; color:%1;">Enable it</a>, then refresh, to sync events.', "account notice when the google calendar api is not enabled").arg(Theme.primary);
            return I18n.tr("Calendars couldn't be loaded; tasks are still syncing.", "account notice when calendars are unavailable but tasks sync");
        case "icloud_reminders_upgraded":
            return I18n.tr('Apple no longer provides upgraded iCloud reminders to third-party apps, so these lists only contain placeholder items. <a href="https://support.apple.com/HT210220" style="text-decoration:none; color:%1;">Learn more</a>', "account notice when apple serves placeholder items instead of upgraded icloud reminders").arg(Theme.primary);
        case "items_skipped":
            return I18n.tr("The server refused to return some events or tasks, so they were skipped; the rest of the calendar is syncing.", "account notice when a caldav server refuses individual calendar objects");
        case "calendar_sync_failed":
            return I18n.tr("Some calendars couldn't be synced; their events may be missing or out of date.", "account notice when at least one calendar failed to sync");
        }
        return "";
    }

    function localeDisplayName(code) {
        const name = I18n.presentLocales[code].nativeLanguageName;
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    readonly property var bundledLocaleOptions: Object.keys(I18n.presentLocales).sort().map(code => ({
                label: root.localeDisplayName(code),
                value: code
            }))

    readonly property var languageOptions: [
        {
            label: I18n.tr("System default", "language dropdown option that follows the system language"),
            value: ""
        }
    ].concat(bundledLocaleOptions)

    readonly property var timeLocaleOptions: [
        {
            label: I18n.tr("Follow language", "date and time locale dropdown option that follows the interface language"),
            value: ""
        }
    ].concat(bundledLocaleOptions)

    readonly property var weekStartOptions: [
        {
            label: I18n.tr("System default (%1)", "week start dropdown option").arg(SettingsData.dayName(SettingsData.localeFirstDayOfWeek, Locale.LongFormat)),
            value: -1
        },
        {
            label: SettingsData.dayName(0, Locale.LongFormat),
            value: 0
        },
        {
            label: SettingsData.dayName(1, Locale.LongFormat),
            value: 1
        },
        {
            label: SettingsData.dayName(6, Locale.LongFormat),
            value: 6
        }
    ]

    readonly property var durationOptions: [
        {
            label: I18n.tr("15 minutes", "default event duration option"),
            value: 15
        },
        {
            label: I18n.tr("30 minutes", "default event duration option"),
            value: 30
        },
        {
            label: I18n.tr("45 minutes", "default event duration option"),
            value: 45
        },
        {
            label: I18n.tr("1 hour", "default event duration option"),
            value: 60
        },
        {
            label: I18n.tr("1.5 hours", "default event duration option"),
            value: 90
        },
        {
            label: I18n.tr("2 hours", "default event duration option"),
            value: 120
        }
    ]

    readonly property var eventTitleLineOptions: [
        {
            label: I18n.tr("1 line", "event title line count dropdown option"),
            value: 1
        },
        {
            label: I18n.tr("2 lines", "event title line count dropdown option"),
            value: 2
        },
        {
            label: I18n.tr("3 lines", "event title line count dropdown option"),
            value: 3
        }
    ]

    readonly property var reminderOptions: [
        {
            label: I18n.tr("None", "default reminder dropdown option"),
            value: -1
        },
        {
            label: I18n.tr("At start", "default reminder dropdown option"),
            value: 0
        },
        {
            label: I18n.tr("5 minutes before", "default reminder dropdown option"),
            value: 5
        },
        {
            label: I18n.tr("10 minutes before", "default reminder dropdown option"),
            value: 10
        },
        {
            label: I18n.tr("15 minutes before", "default reminder dropdown option"),
            value: 15
        },
        {
            label: I18n.tr("30 minutes before", "default reminder dropdown option"),
            value: 30
        },
        {
            label: I18n.tr("1 hour before", "default reminder dropdown option"),
            value: 60
        }
    ]

    readonly property var snoozeOptions: [
        {
            label: I18n.tr("5 minutes", "snooze duration dropdown option"),
            value: 5
        },
        {
            label: I18n.tr("10 minutes", "snooze duration dropdown option"),
            value: 10
        },
        {
            label: I18n.tr("15 minutes", "snooze duration dropdown option"),
            value: 15
        },
        {
            label: I18n.tr("30 minutes", "snooze duration dropdown option"),
            value: 30
        }
    ]

    readonly property var allDayDayOptions: [
        {
            label: I18n.tr("On the day", "all-day reminder day dropdown option"),
            value: 0
        },
        {
            label: I18n.tr("1 day before", "all-day reminder day dropdown option"),
            value: 1
        },
        {
            label: I18n.tr("2 days before", "all-day reminder day dropdown option"),
            value: 2
        },
        {
            label: I18n.tr("1 week before", "all-day reminder day dropdown option"),
            value: 7
        }
    ]

    readonly property var syncIntervalOptions: [
        {
            label: I18n.tr("1 minute", "sync interval dropdown option"),
            value: 1
        },
        {
            label: I18n.tr("5 minutes", "sync interval dropdown option"),
            value: 5
        },
        {
            label: I18n.tr("15 minutes", "sync interval dropdown option"),
            value: 15
        },
        {
            label: I18n.tr("30 minutes", "sync interval dropdown option"),
            value: 30
        },
        {
            label: I18n.tr("1 hour", "sync interval dropdown option"),
            value: 60
        }
    ]

    function minutesFromClock(text) {
        const parts = (text || "").split(":");
        if (parts.length !== 2)
            return 540;
        const total = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
        return isNaN(total) ? 540 : total;
    }

    function clockFromMinutes(minutes) {
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }

    function optionLabels(options) {
        return options.map(o => o.label);
    }

    function labelForValue(options, value) {
        for (let i = 0; i < options.length; i++) {
            if (options[i].value === value)
                return options[i].label;
        }
        return options[0].label;
    }

    function valueForLabel(options, label) {
        for (let i = 0; i < options.length; i++) {
            if (options[i].label === label)
                return options[i].value;
        }
        return options[0].value;
    }

    readonly property var pageTitles: [I18n.tr("General", "general settings section header"), I18n.tr("Appearance", "appearance settings section header"), I18n.tr("Calendars", "calendars settings section header"), I18n.tr("Accounts", "accounts settings section header"), I18n.tr("Notifications", "notifications settings section header"), I18n.tr("About", "settings sidebar tab label")]

    Item {
        id: pageHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(SettingsMetrics.pageHeaderHeight, pageHeading.implicitHeight + Theme.spacingM * 2)

        StyledText {
            id: pageHeading
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.pageTitles[root.currentIndex] ?? ""
            font.pixelSize: Theme.fontSizeXXLarge
            color: Theme.surfaceText
            wrapMode: Text.WordWrap
        }
    }

    Loader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: pageHeader.bottom
        anchors.bottom: parent.bottom
        sourceComponent: {
            switch (root.currentIndex) {
            case 0:
                return generalPage;
            case 1:
                return appearancePage;
            case 2:
                return calendarsPage;
            case 3:
                return accountsPage;
            case 4:
                return notificationsPage;
            case 5:
                return aboutPage;
            default:
                return generalPage;
            }
        }
    }

    component PageHeader: Column {
        property string subtitle: ""

        width: parent.width
        visible: subtitle !== ""

        StyledText {
            text: parent.subtitle
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignLeft
        }
    }

    component FontFamilyRow: SettingsDropdownRow {
        property string family: ""
        property string defaultFamily: Theme.defaultFontFamily
        readonly property string defaultLabel: I18n.tr("Default", "font family dropdown option for the bundled font")

        signal familyPicked(string name)

        enableFuzzySearch: true
        options: [defaultLabel]
        currentValue: family || defaultLabel
        onValueChanged: value => familyPicked(value === defaultLabel ? "" : value)
        Component.onCompleted: Qt.callLater(() => options = [defaultLabel].concat(DC.Fonts.selectableFamilies(defaultFamily)))
    }

    component OptionDropdownRow: SettingsDropdownRow {
        id: optionRow
        property var optionList: []
        property var current: null

        signal picked(var value)

        options: root.optionLabels(optionList)
        currentValue: root.labelForValue(optionList, current)
        onValueChanged: label => picked(root.valueForLabel(optionList, label))
    }

    Component {
        id: generalPage
        SettingsPage {
            PageHeader {
                subtitle: I18n.tr("Defaults follow your locale unless overridden.", "general settings section subtitle")
            }

            SettingsCard {

                title: I18n.tr("App", "general settings section label")
                SettingsToggleRow {
                    text: I18n.tr("Start at login", "autostart setting label")
                    description: I18n.tr("Launch Dux Calendar in the background when you log in.", "autostart setting description")
                    checked: DankCalService.autostartEnabled
                    enabled: DankCalService.connected
                    onToggled: checked => DankCalService.setAutostart(checked)
                }

                SettingsButtonGroupRow {
                    text: I18n.tr("Close behavior", "close behavior setting label")
                    description: I18n.tr("What the window's close button does.", "close behavior setting description")
                    model: [I18n.tr("Minimize", "close behavior button group option to hide to tray"), I18n.tr("Quit", "close behavior button group option to quit the app")]
                    currentIndex: SettingsData.closeBehavior === "quit" ? 1 : 0
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        SettingsData.closeBehavior = index === 1 ? "quit" : "minimize";
                    }
                }

                SettingsToggleRow {
                    text: I18n.tr("Show tray icon", "tray icon toggle label")
                    description: !SettingsData.showTrayIcon && SettingsData.closeBehavior === "minimize" ? I18n.tr("Closing hides the window; reopen it from your app launcher.", "tray icon toggle warning when closing only minimizes") : I18n.tr("Show Dux Calendar in the system tray.", "tray icon toggle description")
                    checked: SettingsData.showTrayIcon
                    onToggled: checked => SettingsData.showTrayIcon = checked
                }

                OptionDropdownRow {
                    text: I18n.tr("Sync interval", "sync interval setting label")
                    description: I18n.tr("How often accounts are polled for changes.", "sync interval setting description")
                    dropdownWidth: 150
                    optionList: root.syncIntervalOptions
                    current: SettingsData.syncIntervalMinutes
                    onPicked: value => SettingsData.syncIntervalMinutes = value
                }
            }

            SettingsCard {

                title: I18n.tr("Language and time", "general settings section label")
                OptionDropdownRow {
                    text: I18n.tr("Language", "interface language setting label")
                    description: I18n.tr("Language of the interface.", "interface language setting description")
                    dropdownWidth: 220
                    optionList: root.languageOptions
                    current: SettingsData.language
                    onPicked: value => SettingsData.language = value
                }

                OptionDropdownRow {
                    text: I18n.tr("Date and time locale", "date and time locale setting label")
                    description: I18n.tr("Locale used for day and month names, time format and week start.", "date and time locale setting description")
                    dropdownWidth: 220
                    optionList: root.timeLocaleOptions
                    current: SettingsData.timeLocale
                    onPicked: value => SettingsData.timeLocale = value
                }

                OptionDropdownRow {
                    text: I18n.tr("Start week on", "week start setting label")
                    description: I18n.tr("First day shown in week and month views.", "week start setting description")
                    dropdownWidth: 220
                    optionList: root.weekStartOptions
                    current: SettingsData.firstDayOfWeek
                    onPicked: value => SettingsData.firstDayOfWeek = value
                }

                SettingsButtonGroupRow {
                    text: I18n.tr("Time format", "time format setting label")
                    description: I18n.tr("Auto follows your locale (%1).", "time format setting description").arg(SettingsData.localeUses24Hour ? I18n.tr("24-hour", "locale time format name in time format description") : I18n.tr("12-hour", "locale time format name in time format description"))
                    model: [I18n.tr("Auto", "time format button group option"), I18n.tr("12h", "time format button group option"), I18n.tr("24h", "time format button group option")]
                    currentIndex: {
                        switch (SettingsData.timeFormat) {
                        case "12h":
                            return 1;
                        case "24h":
                            return 2;
                        default:
                            return 0;
                        }
                    }
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        switch (index) {
                        case 1:
                            SettingsData.timeFormat = "12h";
                            break;
                        case 2:
                            SettingsData.timeFormat = "24h";
                            break;
                        default:
                            SettingsData.timeFormat = "auto";
                            break;
                        }
                    }
                }
            }

            SettingsCard {

                title: I18n.tr("Views", "general settings section label")
                SettingsToggleRow {
                    text: I18n.tr("Enable core hours", "core hours toggle label")
                    description: I18n.tr("Limit the day and week views to a set hour range.", "core hours toggle description")
                    checked: SettingsData.coreHoursEnabled
                    onToggled: checked => SettingsData.coreHoursEnabled = checked
                }

                SettingsRow {
                    title: I18n.tr("Core hours", "core hours range setting label")
                    subtitle: I18n.tr("Hour range shown in day and week views.", "core hours range setting description")
                    enabled: SettingsData.coreHoursEnabled

                    body: Grid {
                        width: parent.width
                        columns: width >= coreHoursStartField.implicitWidth + coreHoursEndField.implicitWidth + coreHoursSeparator.implicitWidth + spacing * 2 ? 3 : 1
                        spacing: Theme.spacingM
                        opacity: enabled ? 1 : SettingsMetrics.disabledOpacity

                        DankTimeField {
                            id: coreHoursStartField
                            width: parent.columns === 1 ? parent.width : (parent.width - coreHoursSeparator.width - parent.spacing * 2) / 2
                            use24Hour: SettingsData.use24HourTime
                            maximumMinutes: Math.round(SettingsData.coreHoursEnd * 60) - 1
                            minutes: SettingsData.coreHoursStart * 60
                            onTimeSelected: value => SettingsData.coreHoursStart = value / 60
                        }

                        StyledText {
                            id: coreHoursSeparator
                            height: parent.columns === 1 ? implicitHeight : Theme.fieldHeightLarge
                            verticalAlignment: Text.AlignVCenter
                            text: I18n.tr("to", "core hours range separator")
                            color: Theme.surfaceVariantText
                        }

                        DankTimeField {
                            id: coreHoursEndField
                            width: parent.columns === 1 ? parent.width : (parent.width - coreHoursSeparator.width - parent.spacing * 2) / 2
                            use24Hour: SettingsData.use24HourTime
                            endOfDay: true
                            minimumMinutes: Math.round(SettingsData.coreHoursStart * 60) + 1
                            maximumMinutes: 1440
                            minutes: SettingsData.coreHoursEnd * 60
                            onTimeSelected: value => SettingsData.coreHoursEnd = value / 60
                        }
                    }
                }

                SettingsToggleRow {
                    text: I18n.tr("Show week numbers", "week numbers setting label")
                    description: I18n.tr("Display ISO week numbers in month view.", "week numbers setting description")
                    checked: SettingsData.showWeekNumbers
                    onToggled: checked => SettingsData.showWeekNumbers = checked
                }

                SettingsToggleRow {
                    text: I18n.tr("Show tasks", "show tasks setting label")
                    description: I18n.tr("Show task lists and the Tasks view when an account provides them.", "show tasks setting description")
                    checked: SettingsData.showTasks
                    onToggled: checked => SettingsData.showTasks = checked
                }

                SettingsToggleRow {
                    text: I18n.tr("Merge duplicate events", "merge duplicate events setting label")
                    description: I18n.tr("Show an event that appears in several calendars once, with dots for the other calendars.", "merge duplicate events setting description")
                    checked: SettingsData.mergeDuplicateEvents
                    onToggled: checked => SettingsData.mergeDuplicateEvents = checked
                }

                OptionDropdownRow {
                    text: I18n.tr("Month event title lines", "month event title line count setting label")
                    description: I18n.tr("Maximum title lines per event in month view.", "month event title line count setting description")
                    dropdownWidth: 120
                    optionList: root.eventTitleLineOptions
                    current: SettingsData.monthEventTitleLines
                    onPicked: value => SettingsData.monthEventTitleLines = value
                }

                SettingsToggleRow {
                    text: I18n.tr("Show all events in month view", "show all month events setting label")
                    description: I18n.tr("Expand day cells to fit every event instead of collapsing extras into \"+N more\".", "show all month events setting description")
                    checked: SettingsData.monthShowAllEvents
                    onToggled: checked => SettingsData.monthShowAllEvents = checked
                }

                OptionDropdownRow {
                    text: I18n.tr("Week event title lines", "week event title line count setting label")
                    description: I18n.tr("Maximum title lines per event in week view.", "week event title line count setting description")
                    dropdownWidth: 120
                    optionList: root.eventTitleLineOptions
                    current: SettingsData.weekEventTitleLines
                    onPicked: value => SettingsData.weekEventTitleLines = value
                }
            }

            SettingsCard {

                title: I18n.tr("New events", "general settings section label")
                OptionDropdownRow {
                    text: I18n.tr("Default event duration", "default event duration setting label")
                    description: I18n.tr("Length used when creating events.", "default event duration setting description")
                    dropdownWidth: 150
                    optionList: root.durationOptions
                    current: SettingsData.defaultEventDurationMinutes
                    onPicked: value => SettingsData.defaultEventDurationMinutes = value
                }

                OptionDropdownRow {
                    text: I18n.tr("Default reminder", "default reminder setting label")
                    description: I18n.tr("Initial reminder set on new events.", "default reminder setting description")
                    dropdownWidth: 180
                    optionList: root.reminderOptions
                    current: SettingsData.defaultReminderMinutes
                    onPicked: value => SettingsData.defaultReminderMinutes = value
                }
            }
        }
    }

    Component {
        id: appearancePage
        SettingsPage {
            id: appearanceFlickable

            Component.onCompleted: BlurService.probe()

            function openThemeFilePicker() {
                themePickerLoader.active = true;
                const picker = themePickerLoader.item;
                picker.browserTitle = I18n.tr("Select theme file", "custom theme file picker title");
                picker.open();
            }

            PageHeader {
                subtitle: I18n.tr("Pick a color source, palette, or your own theme file.", "appearance settings section subtitle")
            }

            SettingsCard {

                title: I18n.tr("Theme", "appearance settings section label")
                SettingsButtonGroupRow {
                    text: I18n.tr("Theme", "theme mode setting label")
                    description: {
                        switch (SettingsData.themeMode) {
                        case "light":
                            return I18n.tr("Always use the light theme.", "theme mode setting description");
                        case "dark":
                            return I18n.tr("Always use the dark theme.", "theme mode setting description");
                        default:
                            return PortalService.available ? I18n.tr("Following the system color scheme (currently %1).", "theme mode setting description").arg(Theme.isLightMode ? I18n.tr("light", "current scheme name in theme mode description") : I18n.tr("dark", "current scheme name in theme mode description")) : I18n.tr("System preference unavailable — using dark.", "theme mode setting description");
                        }
                    }
                    model: [I18n.tr("Auto", "theme mode button group option"), I18n.tr("Light", "theme mode button group option"), I18n.tr("Dark", "theme mode button group option")]
                    currentIndex: {
                        switch (SettingsData.themeMode) {
                        case "light":
                            return 1;
                        case "dark":
                            return 2;
                        default:
                            return 0;
                        }
                    }
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        switch (index) {
                        case 1:
                            SettingsData.themeMode = "light";
                            break;
                        case 2:
                            SettingsData.themeMode = "dark";
                            break;
                        default:
                            SettingsData.themeMode = "auto";
                            break;
                        }
                    }
                }

                SettingsButtonGroupRow {
                    text: I18n.tr("Color source", "color source setting label")
                    description: {
                        switch (SettingsData.colorSource) {
                        case "preset":
                            return I18n.tr("Use a bundled color palette.", "color source description for preset");
                        case "custom":
                            return I18n.tr("Load colors from your own theme file.", "color source description for custom");
                        case "matugen":
                            return I18n.tr("Follow colors generated by Matugen.", "color source description for Matugen");
                        default:
                            return I18n.tr("Follow Dux Shell colors, falling back to a preset.", "color source description for auto");
                        }
                    }
                    model: root.optionLabels(root.colorSourceOptions)
                    currentIndex: {
                        for (let i = 0; i < root.colorSourceOptions.length; i++) {
                            if (root.colorSourceOptions[i].value === SettingsData.colorSource)
                                return i;
                        }
                        return 0;
                    }
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        SettingsData.colorSource = root.colorSourceOptions[index].value;
                    }
                }

                SettingsRow {
                    visible: SettingsData.colorSource === "auto"
                    iconName: Theme.dmsColorsAvailable ? "check_circle" : "info"
                    iconColor: Theme.dmsColorsAvailable ? Theme.success : Theme.surfaceVariantText
                    title: Theme.dmsColorsAvailable ? I18n.tr("Using Dux Shell dynamic colors.", "auto color source status when DMS is active") : I18n.tr("Dux Shell not detected — using the %1 preset.", "auto color source status when DMS is missing").arg(Theme.presetLabel(SettingsData.presetTheme))
                }

                SettingsRow {
                    visible: SettingsData.colorSource === "matugen"
                    iconName: Theme.customThemeLoaded ? "check_circle" : "info"
                    iconColor: Theme.customThemeLoaded ? Theme.success : Theme.surfaceVariantText
                    title: Theme.customThemeLoaded ? I18n.tr("Using Matugen colors.", "Matugen color source status when loaded") : I18n.tr("Matugen theme missing or invalid — using the %1 preset.", "Matugen color source fallback status").arg(Theme.presetLabel(SettingsData.presetTheme))
                    subtitle: Theme.matugenThemePath
                }

                SettingsRow {
                    visible: SettingsData.colorSource === "preset"
                    title: I18n.tr("Palette: %1", "selected preset palette name").arg(Theme.presetLabel(SettingsData.presetTheme))

                    body: Flow {
                        width: parent.width
                        spacing: Theme.spacingS

                        Repeater {
                            model: Theme.presetNames()

                            Rectangle {
                                id: swatch
                                required property string modelData
                                readonly property bool active: SettingsData.presetTheme === modelData

                                width: Theme.avatarSize
                                height: Theme.avatarSize
                                radius: Theme.fullRadius(width, height)
                                color: Theme.presetColors(modelData).primary
                                border.color: active ? Theme.primary : Theme.outlineVariant
                                border.width: active ? Theme.outlineWidthFocused + Theme.outlineWidth : Theme.outlineWidth
                                scale: active ? 1.1 : 1
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: Theme.presetLabel(modelData)
                                Accessible.checked: active

                                Behavior on scale {
                                    enabled: Theme.animationsEnabled
                                    NumberAnimation {
                                        duration: Theme.shortDuration
                                        easing.type: Theme.emphasizedEasing
                                    }
                                }

                                StateLayer {
                                    stateColor: Theme.surfaceText
                                    cornerRadius: parent.radius
                                    onClicked: SettingsData.presetTheme = swatch.modelData
                                }
                            }
                        }
                    }
                }

                SettingsRow {
                    visible: SettingsData.colorSource === "custom"
                    clickable: true
                    iconName: "folder_open"
                    title: SettingsData.customThemeFile ? SettingsData.customThemeFile.split('/').pop() : I18n.tr("No theme file selected", "custom theme empty state title")
                    subtitle: {
                        if (!SettingsData.customThemeFile)
                            return I18n.tr("Choose a JSON color theme file.", "custom theme hint when none selected");
                        if (Theme.customThemeLoaded)
                            return SettingsData.customThemeFile;
                        return I18n.tr("Could not read that file — expected a JSON color theme.", "custom theme error when file is invalid");
                    }
                    subtitleColor: (SettingsData.customThemeFile && !Theme.customThemeLoaded) ? Theme.error : Theme.surfaceVariantText
                    showChevron: true
                    onClicked: appearanceFlickable.openThemeFilePicker()
                }
            }

            SettingsCard {

                title: I18n.tr("Shape", "appearance settings section label")
                SettingsSliderRow {
                    text: I18n.tr("Radius strength", "global component corner rounding")
                    description: I18n.tr("50 uses Material shapes. Lower values reduce rounding; higher values increase it.", "radius strength slider description")
                    minimumLabel: I18n.tr("Square", "radius strength slider label at zero")
                    value: SettingsData.radiusStrength
                    minimum: 0
                    maximum: 100
                    unit: ""
                    onSliderValueChanged: newValue => SettingsData.radiusStrength = newValue
                }
            }

            SettingsCard {

                title: I18n.tr("Zoom", "appearance settings section label")
                SettingsSliderRow {
                    text: I18n.tr("Scale", "interface zoom slider label")
                    description: SettingsData.uiScaleFromEnv ? I18n.tr("Set by QT_SCALE_FACTOR.", "interface zoom slider description when the environment overrides it") : I18n.tr("Scales the whole app. Takes effect after a restart.", "interface zoom slider description")
                    enabled: !SettingsData.uiScaleFromEnv
                    minimum: 75
                    maximum: 200
                    step: 5
                    unit: "%"
                    value: Math.round((SettingsData.uiScaleFromEnv ? SettingsData.effectiveUiScale : SettingsData.uiScale) * 100)
                    onSliderValueChanged: newValue => SettingsData.uiScale = newValue / 100
                }

                SettingsRow {
                    visible: !SettingsData.uiScaleFromEnv && Math.round(SettingsData.uiScale * 100) !== Math.round(SettingsData.effectiveUiScale * 100)
                    title: I18n.tr("Restart required", "interface zoom pending restart label")
                    subtitle: DankCalService.connected ? I18n.tr("Dux Calendar will close and reopen with the new zoom.", "interface zoom pending restart description") : I18n.tr("Backend not connected.", "interface zoom pending restart description when backend is unavailable")

                    DButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Apply and restart", "interface zoom restart button")
                        enabled: DankCalService.connected
                        backgroundColor: Theme.secondaryContainer
                        textColor: Theme.onSecondaryContainer
                        onClicked: DankCalService.restart()
                    }
                }
            }

            SettingsCard {

                title: I18n.tr("Typography", "appearance settings section label")
                SettingsButtonGroupRow {
                    text: I18n.tr("Font source", "font source setting label")
                    model: root.optionLabels(root.fontSourceOptions)
                    currentIndex: Math.max(0, root.fontSourceOptions.findIndex(o => o.value === SettingsData.fontSource))
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        SettingsData.fontSource = root.fontSourceOptions[index].value;
                    }
                }

                SettingsRow {
                    visible: SettingsData.fontSource === "auto" && !Theme.typography.followingDms
                    iconName: "info"
                    iconColor: Theme.surfaceVariantText
                    title: I18n.tr("Dux Shell not detected, using %1.", "auto font source status when DMS is missing").arg(Theme.fontFamily)
                }

                FontFamilyRow {
                    visible: !Theme.typography.followingDms && SettingsData.fontSource !== "system"
                    text: I18n.tr("Family", "font family dropdown label")
                    family: SettingsData.fontFamily
                    onFamilyPicked: name => SettingsData.fontFamily = name
                }

                FontFamilyRow {
                    visible: !Theme.typography.followingDms && SettingsData.fontSource !== "system"
                    text: I18n.tr("Monospace family", "monospace font family dropdown label")
                    defaultFamily: Theme.defaultMonoFontFamily
                    family: SettingsData.monoFontFamily
                    onFamilyPicked: name => SettingsData.monoFontFamily = name
                }

                FontFamilyRow {
                    visible: !Theme.typography.followingDms && SettingsData.fontSource !== "system"
                    text: I18n.tr("Display family", "display font family dropdown label")
                    defaultFamily: Theme.defaultDisplayFontFamily
                    family: SettingsData.displayFontFamily
                    onFamilyPicked: name => SettingsData.displayFontFamily = name
                }

                SettingsSliderRow {
                    visible: !Theme.typography.followingDms
                    text: I18n.tr("Weight", "font weight slider label")
                    minimum: Font.Thin
                    maximum: Font.Black
                    step: 100
                    showStops: true
                    unit: ""
                    value: SettingsData.fontWeight
                    onSliderValueChanged: newValue => SettingsData.fontWeight = newValue
                }

                SettingsSliderRow {
                    visible: !Theme.typography.followingDms
                    text: I18n.tr("Scale", "font scale slider label")
                    minimum: 75
                    maximum: 150
                    unit: "%"
                    value: Math.round(SettingsData.fontScale * 100)
                    onSliderValueChanged: newValue => SettingsData.fontScale = newValue / 100
                }
            }

            SettingsCard {

                title: I18n.tr("Windows", "appearance settings section label")
                SettingsToggleRow {
                    text: I18n.tr("Title bars", "window title bars toggle label")
                    description: I18n.tr("Off lets the compositor decorate windows. Open windows update when reopened.", "window title bars toggle description")
                    checked: SettingsData.windowTitleBars
                    onToggled: checked => SettingsData.windowTitleBars = checked
                }

                SettingsSliderRow {
                    text: I18n.tr("Opacity", "window opacity slider label")
                    description: I18n.tr("Lets the desktop show through the window. Text and controls stay solid.", "window opacity slider description")
                    minimum: 0
                    maximum: 100
                    unit: "%"
                    value: Math.round(SettingsData.floatingWindowTransparency * 100)
                    onSliderValueChanged: newValue => SettingsData.floatingWindowTransparency = newValue / 100
                }

                SettingsToggleRow {
                    text: I18n.tr("Foreground layers", "toggle keeping cards and panes solid over a see-through window")
                    description: I18n.tr("Keeps cards and panes solid when the window is see-through.", "foreground layers toggle description")
                    checked: SettingsData.floatingWindowForegroundLayers
                    onToggled: checked => SettingsData.floatingWindowForegroundLayers = checked
                }

                SettingsSliderRow {
                    text: I18n.tr("Layer opacity", "foreground layer opacity slider label")
                    enabled: SettingsData.floatingWindowForegroundLayers
                    minimum: 0
                    maximum: 100
                    unit: "%"
                    value: Math.round(SettingsData.floatingWindowForegroundTransparency * 100)
                    onSliderValueChanged: newValue => SettingsData.floatingWindowForegroundTransparency = newValue / 100
                }

                SettingsToggleRow {
                    visible: BlurService.available
                    text: I18n.tr("Background blur", "toggle asking the compositor to blur behind see-through windows")
                    description: I18n.tr("Blurs what shows through the window. Needs an opacity below 100%.", "background blur toggle description")
                    checked: SettingsData.blurEnabled
                    onToggled: checked => SettingsData.blurEnabled = checked
                }

                SettingsRow {
                    visible: BlurService.probed && !BlurService.available
                    title: I18n.tr("Background blur", "toggle asking the compositor to blur behind see-through windows")
                    subtitle: I18n.tr("Your compositor does not support background blur.", "hint shown instead of the background blur toggle")
                }
            }

            SettingsCard {

                title: I18n.tr("Motion", "appearance settings section label")
                SettingsSliderRow {
                    text: I18n.tr("Duration", "animation duration slider label")
                    minimumLabel: I18n.tr("Off", "animation duration slider label at zero")
                    minimum: 0
                    maximum: 1000
                    unit: "ms"
                    value: SettingsData.animationDuration
                    onSliderValueChanged: newValue => SettingsData.animationDuration = newValue
                }

                SettingsButtonGroupRow {
                    text: I18n.tr("Spring", "spring bounce setting label")
                    model: [I18n.tr("Smooth", "spring bounce option"), I18n.tr("Balanced", "spring bounce option"), I18n.tr("Playful", "spring bounce option")]
                    currentIndex: SettingsData.springBounce
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        SettingsData.springBounce = index;
                    }
                }

                SettingsToggleRow {
                    text: I18n.tr("Ripple effects", "ripple effects toggle label")
                    checked: SettingsData.enableRippleEffects
                    onToggled: checked => SettingsData.enableRippleEffects = checked
                }

                SettingsToggleRow {
                    text: I18n.tr("Reduce motion", "reduce motion toggle label")
                    checked: SettingsData.reduceMotion
                    onToggled: checked => SettingsData.reduceMotion = checked
                }
            }

            SettingsCard {

                title: I18n.tr("Focus ring", "appearance settings section label")
                SettingsToggleRow {
                    text: I18n.tr("Focus ring", "focus ring toggle label")
                    description: I18n.tr("Outline the control that has keyboard focus.", "focus ring toggle description")
                    checked: SettingsData.focusRingEnabled
                    onToggled: checked => SettingsData.focusRingEnabled = checked
                }

                SettingsSliderRow {
                    text: I18n.tr("Thickness", "focus ring thickness slider label")
                    enabled: SettingsData.focusRingEnabled
                    value: Math.round(SettingsData.focusRingWidth * 10)
                    minimum: 10
                    maximum: 40
                    step: 5
                    decimals: 1
                    unit: "px"
                    onSliderValueChanged: newValue => SettingsData.focusRingWidth = newValue / 10
                }

                SettingsDropdownRow {
                    readonly property var colorOptions: [
                        {
                            label: I18n.tr("Primary", "focus ring color option"),
                            value: "primary",
                            color: Theme.primary
                        },
                        {
                            label: I18n.tr("Secondary", "focus ring color option"),
                            value: "secondary",
                            color: Theme.secondary
                        },
                        {
                            label: I18n.tr("Outline", "focus ring color option"),
                            value: "outline",
                            color: Theme.outline
                        },
                        {
                            label: I18n.tr("Text color", "focus ring color option"),
                            value: "surfaceText",
                            color: Theme.surfaceText
                        }
                    ]

                    text: I18n.tr("Color", "focus ring color setting label")
                    enabled: SettingsData.focusRingEnabled
                    dropdownWidth: 160
                    options: root.optionLabels(colorOptions)
                    optionColorMap: {
                        const map = {};
                        for (const option of colorOptions)
                            map[option.label] = option.color;
                        return map;
                    }
                    currentValue: root.labelForValue(colorOptions, SettingsData.focusRingColor)
                    onValueChanged: value => SettingsData.focusRingColor = root.valueForLabel(colorOptions, value)
                }
            }

            Loader {
                id: themePickerLoader
                active: false
                sourceComponent: FileBrowserModal {
                    parentModal: root.hostWindow
                    bucket: "theme"
                    filters: ["*.json"]
                    onAccepted: paths => SettingsData.customThemeFile = paths[0]
                }
            }
        }
    }

    Component {
        id: calendarsPage
        SettingsPage {
            id: calendarsFlickable

            property var actionCalendar: null

            PageHeader {
                subtitle: I18n.tr("Visibility, names, and removal per calendar.", "calendars settings section subtitle")
            }

            SettingsGroup {
                visible: DankCalService.calendars.length > 0

                SettingsDropdownRow {
                    readonly property string autoLabel: I18n.tr("First calendar", "default calendar dropdown option for no explicit default")
                    readonly property var entries: {
                        const writable = DankCalService.writableCalendars();
                        const counts = {};
                        for (let i = 0; i < writable.length; i++)
                            counts[writable[i].name] = (counts[writable[i].name] || 0) + 1;
                        return writable.map(c => ({
                                    "id": c.id,
                                    "color": c.color,
                                    "label": counts[c.name] > 1 && c.accountName ? c.name + " · " + c.accountName : c.name
                                }));
                    }

                    text: I18n.tr("Default calendar", "default calendar setting label")
                    description: I18n.tr("Calendar preselected when creating events.", "default calendar setting description")
                    dropdownWidth: 220
                    options: [autoLabel].concat(entries.map(e => e.label))
                    optionColorMap: {
                        const map = {};
                        for (let i = 0; i < entries.length; i++)
                            map[entries[i].label] = entries[i].color;
                        return map;
                    }
                    currentValue: {
                        for (let i = 0; i < entries.length; i++) {
                            if (entries[i].id === SettingsData.defaultCalendarId)
                                return entries[i].label;
                        }
                        return autoLabel;
                    }
                    onValueChanged: value => {
                        for (let i = 0; i < entries.length; i++) {
                            if (entries[i].label === value) {
                                SettingsData.defaultCalendarId = entries[i].id;
                                return;
                            }
                        }
                        SettingsData.defaultCalendarId = "";
                    }
                }
            }

            StyledText {
                visible: DankCalService.calendars.length === 0
                text: DankCalService.connected ? I18n.tr("No calendars yet. Add an account first.", "calendars page empty state") : I18n.tr("Backend not connected.", "calendars page empty state")
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                width: parent.width
                horizontalAlignment: Text.AlignLeft
            }

            SettingsCard {

                visible: DankCalService.calendars.length > 0

                title: I18n.tr("Calendars", "calendars settings section header")
                Repeater {
                    model: ScriptModel {
                        values: DankCalService.calendars
                    }

                    SettingsRow {
                        id: calendarRow
                        required property var modelData
                        readonly property bool renamed: !!modelData.providerName && modelData.providerName !== modelData.name

                        title: modelData.name
                        subtitle: {
                            let line = modelData.accountName || modelData.accountId || "";
                            if (renamed)
                                line += " · " + I18n.tr("synced as \"%1\"", "renamed calendar provider name suffix in calendar list").arg(modelData.providerName);
                            if (modelData.readOnly)
                                line += " · " + I18n.tr("read-only", "read-only suffix in calendar list");
                            if (modelData.syncDisabled)
                                line += " · " + I18n.tr("sync off", "sync disabled suffix in calendar list");
                            return line;
                        }

                        leading: Rectangle {
                            width: Theme.chipIconSize
                            height: Theme.chipIconSize
                            radius: Theme.cornerRadiusXS
                            anchors.verticalCenter: parent.verticalCenter
                            color: calendarRow.modelData.color
                            opacity: calendarRow.modelData.syncDisabled ? SettingsMetrics.disabledOpacity : 1
                        }

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "edit"
                            tooltipText: I18n.tr("Rename", "calendar row action tooltip")
                            onClicked: calendarRenameDialog.show(calendarRow.modelData)
                        }

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: !!calendarRow.modelData.reminders ? "notifications_active" : "notifications"
                            iconColor: !!calendarRow.modelData.reminders ? Theme.primary : Theme.onSurfaceVariant
                            tooltipText: I18n.tr("Reminders", "calendar row action tooltip")
                            onClicked: calendarRemindersDialog.show(calendarRow.modelData)
                        }

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: calendarRow.modelData.accountKind !== "local"
                            iconName: calendarRow.modelData.syncDisabled ? "cloud_off" : "cloud"
                            iconColor: calendarRow.modelData.syncDisabled ? Theme.error : Theme.onSurfaceVariant
                            tooltipText: calendarRow.modelData.syncDisabled ? I18n.tr("Sync is off — click to re-enable", "calendar row action tooltip") : I18n.tr("Disable sync", "calendar row action tooltip")
                            onClicked: DankCalService.setCalendarSyncDisabled(calendarRow.modelData.id, !calendarRow.modelData.syncDisabled)
                        }

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "delete_outline"
                            iconColor: Theme.error
                            tooltipText: I18n.tr("Delete", "calendar row action tooltip")
                            onClicked: {
                                calendarsFlickable.actionCalendar = calendarRow.modelData;
                                calendarDeleteConfirm.show({
                                    title: I18n.tr("Delete \"%1\"?", "delete calendar confirmation title").arg(calendarRow.modelData.name),
                                    message: I18n.tr("Removes this calendar and its events from Dux Calendar. If the provider still offers it, it will come back on the next sync.", "delete calendar confirmation message"),
                                    confirmText: I18n.tr("Delete", "delete calendar confirmation button"),
                                    danger: true
                                });
                            }
                        }

                        DToggle {
                            anchors.verticalCenter: parent.verticalCenter
                            Accessible.name: I18n.tr("Show calendar", "calendar row visibility toggle")
                            checked: !calendarRow.modelData.hidden
                            onToggled: checked => DankCalService.setCalendarHidden(calendarRow.modelData.id, !checked)
                        }
                    }
                }
            }

            RenameCalendarDialog {
                id: calendarRenameDialog
            }

            CalendarRemindersDialog {
                id: calendarRemindersDialog
            }

            ConfirmDialog {
                id: calendarDeleteConfirm
                onConfirmed: {
                    if (calendarsFlickable.actionCalendar)
                        DankCalService.deleteCalendar(calendarsFlickable.actionCalendar.id);
                }
            }
        }
    }

    Component {
        id: accountsPage
        SettingsPage {
            id: accountsFlickable

            property var actionAccount: null

            function providerMeta(kind) {
                switch (kind) {
                case "google":
                    return {
                        "label": "Google",
                        "icon": "mail",
                        "color": Theme.primary
                    };
                case "caldav":
                    return {
                        "label": "CalDAV",
                        "icon": "cloud",
                        "color": Theme.secondary
                    };
                case "icloud":
                    return {
                        "label": "iCloud",
                        "icon": "cloud_circle",
                        "color": Theme.info
                    };
                case "microsoft":
                    return {
                        "label": "Microsoft",
                        "icon": "business",
                        "color": Theme.warning
                    };
                case "local":
                    return {
                        "label": I18n.tr("Local", "local provider name in account list"),
                        "icon": "folder",
                        "color": Theme.success
                    };
                }
                return {
                    "label": kind,
                    "icon": "account_circle",
                    "color": Theme.primary
                };
            }

            PageHeader {
                subtitle: DankCalService.connected ? I18n.tr("Connected calendar providers.", "accounts settings section subtitle") : I18n.tr("Backend not connected.", "accounts settings section subtitle")
            }

            StyledText {
                visible: DankCalService.accounts.length === 0
                text: I18n.tr("No accounts yet. Click \"Add account\" to connect one.", "accounts page empty state")
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                width: parent.width
                horizontalAlignment: Text.AlignLeft
            }

            SettingsGroup {
                Repeater {
                    model: ScriptModel {
                        values: DankCalService.accounts
                    }

                    SettingsRow {
                        id: accountRow
                        required property var modelData
                        readonly property var meta: accountsFlickable.providerMeta(DankCalService.accountFlavor(modelData))
                        readonly property bool needsReauth: modelData.needsReauth === true
                        readonly property bool authorized: modelData.authorized !== false
                        readonly property bool keyringLocked: modelData.keyringLocked === true
                        readonly property bool healthy: !needsReauth && !keyringLocked && authorized
                        readonly property string noticeText: root.accountNotice(modelData)

                        title: meta.label
                        subtitle: DankCalService.accountLabel(modelData)

                        leading: Rectangle {
                            width: Theme.iconButtonSize
                            height: Theme.iconButtonSize
                            radius: Theme.fullRadius(width, height)
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.withAlpha(accountRow.meta.color, Theme.tonalTintAlpha)

                            DIcon {
                                anchors.centerIn: parent
                                name: accountRow.meta.icon
                                size: Theme.iconSizeMedium
                                color: accountRow.meta.color
                            }
                        }

                        body: Column {
                            width: parent.width
                            spacing: Theme.spacingXS

                            StyledText {
                                width: parent.width
                                text: {
                                    if (accountRow.keyringLocked)
                                        return I18n.tr("Keyring locked — unlock it to sync", "account status when the system keyring holding the credentials is locked");
                                    if (accountRow.needsReauth)
                                        return I18n.tr("Sign-in expired — reconnect to keep syncing", "account status when oauth needs re-auth");
                                    if (!accountRow.authorized)
                                        return I18n.tr("Not authorized — remove this account and add it again", "account status in account list");
                                    return I18n.tr("Connected", "account status in account list");
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: accountRow.healthy ? Theme.surfaceVariantText : Theme.error
                                horizontalAlignment: Text.AlignLeft
                            }

                            Row {
                                visible: accountRow.noticeText !== "" && accountRow.healthy
                                width: parent.width
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: accountRow.noticeText
                                    textFormat: Text.RichText
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.warning
                                    linkColor: Theme.primary
                                    onLinkActivated: url => Qt.openUrlExternally(url)
                                    width: parent.width - Theme.iconSizeMedium - Theme.spacingXS
                                    wrapMode: Text.WordWrap
                                    horizontalAlignment: Text.AlignLeft

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        acceptedButtons: Qt.NoButton
                                    }
                                }

                                DActionButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    buttonSize: Theme.iconSizeMedium
                                    iconSize: Theme.iconSizeSmall
                                    iconName: "close"
                                    tooltipText: I18n.tr("Dismiss", "account notice dismiss button tooltip")
                                    onClicked: root.dismissAccountNotice(accountRow.modelData)
                                }
                            }
                        }

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: accountRow.needsReauth
                            iconName: "login"
                            iconColor: Theme.primary
                            tooltipText: I18n.tr("Reconnect", "account row action tooltip")
                            onClicked: DankCalService.reconnectAccount(accountRow.modelData)
                        }

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "refresh"
                            tooltipText: I18n.tr("Sync now", "account row action tooltip")
                            onClicked: DankCalService.refreshAccount(accountRow.modelData.id)
                        }

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "delete_outline"
                            iconColor: Theme.error
                            tooltipText: I18n.tr("Remove", "remove account confirmation button")
                            onClicked: {
                                accountsFlickable.actionAccount = accountRow.modelData;
                                accountRemoveConfirm.show({
                                    title: I18n.tr("Remove \"%1\"?", "remove account confirmation title").arg(DankCalService.accountLabel(accountRow.modelData)),
                                    message: I18n.tr("Removes this account and its calendars and events from Dux Calendar. Nothing is deleted from the provider.", "remove account confirmation message"),
                                    confirmText: I18n.tr("Remove", "remove account confirmation button"),
                                    danger: true
                                });
                            }
                        }
                    }
                }
            }

            DButton {
                text: I18n.tr("Add account", "add account button on accounts page")
                iconName: "add"
                onClicked: root.addAccountRequested()
            }

            ConfirmDialog {
                id: accountRemoveConfirm
                onConfirmed: {
                    if (accountsFlickable.actionAccount)
                        DankCalService.removeAccount(accountsFlickable.actionAccount.id);
                }
            }
        }
    }

    Component {
        id: notificationsPage
        SettingsPage {
            PageHeader {
                subtitle: I18n.tr("Reminders and desktop alerts.", "notifications settings section subtitle")
            }

            SettingsGroup {
                SettingsToggleRow {
                    text: I18n.tr("Enable reminders", "reminders toggle label")
                    description: I18n.tr("Desktop notifications for upcoming events.", "reminders toggle description")
                    checked: SettingsData.remindersEnabled
                    onToggled: checked => SettingsData.remindersEnabled = checked
                }

                SettingsToggleRow {
                    text: I18n.tr("Keep until dismissed", "persistent reminders toggle label")
                    description: I18n.tr("Reminders stay on screen until you act on them.", "persistent reminders toggle description")
                    checked: SettingsData.reminderPersist
                    enabled: SettingsData.remindersEnabled
                    onToggled: checked => SettingsData.reminderPersist = checked
                }

                SettingsToggleRow {
                    text: I18n.tr("Notification sound", "notification sound toggle label")
                    description: I18n.tr("Play a sound when a reminder fires.", "notification sound toggle description")
                    checked: SettingsData.notificationSounds
                    enabled: SettingsData.remindersEnabled
                    onToggled: checked => SettingsData.notificationSounds = checked
                }

                OptionDropdownRow {
                    text: I18n.tr("Snooze duration", "snooze duration setting label")
                    description: I18n.tr("How long the snooze button postpones a reminder.", "snooze duration setting description")
                    dropdownWidth: 150
                    enabled: SettingsData.remindersEnabled
                    optionList: root.snoozeOptions
                    current: SettingsData.snoozeMinutes
                    onPicked: value => SettingsData.snoozeMinutes = value
                }
            }

            SettingsCard {

                title: I18n.tr("All-day events", "notifications settings section label")
                SettingsToggleRow {
                    text: I18n.tr("Show all-day reminders", "all-day reminders toggle label")
                    description: I18n.tr("Notify for all-day events without their own reminders.", "all-day reminders toggle description")
                    checked: SettingsData.allDayReminders
                    enabled: SettingsData.remindersEnabled
                    onToggled: checked => SettingsData.allDayReminders = checked
                }

                SettingsRow {
                    title: I18n.tr("All-day reminder time", "all-day reminder time setting label")
                    subtitle: I18n.tr("When all-day event reminders fire.", "all-day reminder time setting description")
                    enabled: SettingsData.remindersEnabled && SettingsData.allDayReminders

                    body: Flow {
                        width: parent.width
                        spacing: Theme.spacingS

                        DDropdown {
                            dropdownWidth: Math.min(Theme.fieldDefaultWidth, parent.width)
                            options: root.optionLabels(root.allDayDayOptions)
                            currentValue: root.labelForValue(root.allDayDayOptions, SettingsData.allDayReminderDaysBefore)
                            onValueChanged: value => SettingsData.allDayReminderDaysBefore = root.valueForLabel(root.allDayDayOptions, value)
                        }

                        DankTimeField {
                            width: Math.min(Theme.fieldDefaultWidth, parent.width)
                            use24Hour: SettingsData.use24HourTime
                            minutes: root.minutesFromClock(SettingsData.allDayReminderTime)
                            onTimeSelected: value => SettingsData.allDayReminderTime = root.clockFromMinutes(value)
                        }
                    }
                }
            }

            SettingsCard {

                title: I18n.tr("Diagnostics", "notifications settings section label")
                SettingsRow {
                    title: I18n.tr("Test notification", "test notification setting label")
                    subtitle: DankCalService.connected ? I18n.tr("Verify desktop notifications are working.", "test notification setting description") : I18n.tr("Backend not connected.", "test notification setting description when backend is unavailable")

                    DButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Send test", "test notification button")
                        enabled: DankCalService.connected
                        backgroundColor: Theme.secondaryContainer
                        textColor: Theme.onSecondaryContainer
                        onClicked: DankCalService.sendTestReminder()
                    }
                }
            }
        }
    }

    Component {
        id: aboutPage
        SettingsAboutPage {}
    }
}
