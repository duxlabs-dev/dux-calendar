pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.DCommon.Common
import qs.Services
import "StockTheme.js" as StockTheme
import "../DCommon/Common/Shape.js" as Shape
import "../DCommon/Common/Surface.js" as Surface
import "../DCommon/Common/Contrast.js" as Contrast
import "../DCommon/Common/Accents.js" as Accents
import "../DCommon/Common/Tonal.js" as Tonal

Singleton {
    id: root

    readonly property string defaultFontFamily: Fonts.sans
    readonly property string defaultMonoFontFamily: Fonts.mono
    readonly property string defaultDisplayFontFamily: Fonts.display

    // "auto" follows the desktop portal color-scheme; no preference falls back to dark
    readonly property bool isLightMode: {
        switch (SettingsData.themeMode) {
        case "light":
            return true;
        case "dark":
            return false;
        default:
            return PortalService.systemPrefersLight;
        }
    }

    // DMS publishes to the host cache. Inside Flatpak, StandardPaths resolve
    // to the sandbox cache while a user-granted xdg-cache override mounts at
    // the host path, which only HOST_XDG_CACHE_HOME (or HOME) locates.
    readonly property string xdgCacheDir: {
        const flatpakId = Quickshell.env("FLATPAK_ID");
        if (!flatpakId || flatpakId === "")
            return Paths.strip(Paths.xdgCache);
        const hostXdg = Quickshell.env("HOST_XDG_CACHE_HOME");
        if (hostXdg && hostXdg !== "")
            return hostXdg;
        return Paths.strip(Paths.home) + "/.cache";
    }

    property bool useLegacyDmsCache: false
    readonly property string dmsColorsPath: xdgCacheDir + (useLegacyDmsCache ? "/DankMaterialShell" : "/dms") + "/dms-colors.json"
    readonly property string dmsTypographyPath: xdgCacheDir + "/dms/dms-typography.json"
    readonly property string matugenThemePath: SettingsData.configDir + "/matugen-theme.json"

    property var matugenColors: ({})
    property bool colorsLoaded: false

    // True when DMS is actively publishing dynamic colors, so "auto" can prefer them.
    readonly property bool dmsColorsAvailable: colorsLoaded

    property var customThemeRaw: null
    property bool customThemeLoaded: false

    function getMatugenColor(path, fallback) {
        const colorMode = isLightMode ? "light" : "dark";
        let cur = matugenColors && matugenColors.colors && matugenColors.colors[colorMode];
        if (!cur)
            return fallback;
        const parts = path.split(".");
        for (let i = 0; i < parts.length; i++) {
            if (!cur || typeof cur !== "object" || !(parts[i] in cur))
                return fallback;
            cur = cur[parts[i]];
        }
        return cur || fallback;
    }

    function presetNames() {
        return StockTheme.presetNames();
    }

    function presetLabel(name) {
        return StockTheme.presetLabel(name);
    }

    function presetColors(name) {
        return StockTheme.getPreset(name, isLightMode);
    }

    function customColorsForMode(isLight) {
        const raw = customThemeRaw;
        if (!raw)
            return null;
        if (raw.dark || raw.light)
            return (isLight ? raw.light : raw.dark) || raw.dark || raw.light;
        return raw;
    }

    function buildDmsTheme(fallback) {
        return {
            "primary": getMatugenColor("primary", fallback.primary),
            "primaryText": getMatugenColor("on_primary", fallback.primaryText),
            "primaryContainer": getMatugenColor("primary_container", fallback.primaryContainer),
            "onPrimaryContainer": getMatugenColor("on_primary_container", fallback.onPrimaryContainer),
            "secondary": getMatugenColor("secondary", fallback.secondary),
            "secondaryContainer": getMatugenColor("secondary_container", fallback.secondaryContainer),
            "onSecondaryContainer": getMatugenColor("on_secondary_container", fallback.onSecondaryContainer),
            "tertiary": getMatugenColor("tertiary", fallback.tertiary),
            "tertiaryContainer": getMatugenColor("tertiary_container", fallback.tertiaryContainer),
            "onTertiaryContainer": getMatugenColor("on_tertiary_container", fallback.onTertiaryContainer),
            "surface": getMatugenColor("surface", fallback.surface),
            "surfaceText": getMatugenColor("on_surface", fallback.surfaceText),
            "surfaceVariant": getMatugenColor("surface_variant", fallback.surfaceVariant),
            "surfaceVariantText": getMatugenColor("on_surface_variant", fallback.surfaceVariantText),
            "surfaceTint": getMatugenColor("surface_tint", fallback.surfaceTint),
            "surfaceBright": getMatugenColor("surface_bright", fallback.surfaceBright),
            "surfaceDim": getMatugenColor("surface_dim", fallback.surfaceDim),
            "background": getMatugenColor("background", fallback.background),
            "backgroundText": getMatugenColor("on_background", fallback.backgroundText),
            "outline": getMatugenColor("outline", fallback.outline),
            "outlineVariant": getMatugenColor("outline_variant", fallback.outlineVariant),
            "surfaceContainerLowest": getMatugenColor("surface_container_lowest", fallback.surfaceContainerLowest),
            "surfaceContainerLow": getMatugenColor("surface_container_low", fallback.surfaceContainerLow),
            "surfaceContainer": getMatugenColor("surface_container", fallback.surfaceContainer),
            "surfaceContainerHigh": getMatugenColor("surface_container_high", fallback.surfaceContainerHigh),
            "surfaceContainerHighest": getMatugenColor("surface_container_highest", fallback.surfaceContainerHighest),
            "inverseSurface": getMatugenColor("inverse_surface", fallback.inverseSurface),
            "inverseOnSurface": getMatugenColor("inverse_on_surface", fallback.inverseOnSurface),
            "scrim": getMatugenColor("scrim", fallback.scrim),
            "error": getMatugenColor("error", fallback.error),
            "errorText": getMatugenColor("on_error", fallback.errorText),
            "errorContainer": getMatugenColor("error_container", fallback.errorContainer),
            "errorContainerText": getMatugenColor("on_error_container", fallback.errorContainerText),
            "warning": fallback.warning,
            "info": fallback.info,
            "success": fallback.success
        };
    }

    function buildCustomTheme(fallback, isLight) {
        const overrides = customColorsForMode(isLight);
        if (!overrides)
            return fallback;
        let merged = Object.assign({}, fallback);
        for (const key in overrides) {
            if (overrides[key])
                merged[key] = overrides[key];
        }
        return merged;
    }

    function validateMatugenTheme(raw) {
        if (!raw || typeof raw !== "object" || Array.isArray(raw))
            throw new Error("Expected a Matugen palette object");
        const palettes = ("dark" in raw || "light" in raw) ? [raw.dark, raw.light].filter(p => p !== undefined) : [raw];
        for (const palette of palettes) {
            if (!palette || typeof palette !== "object" || Array.isArray(palette) || Object.keys(palette).length === 0)
                throw new Error("Expected a non-empty Matugen palette");
            for (const value of Object.values(palette)) {
                if (typeof value !== "string" || !/^#[0-9a-f]{6}$/i.test(value))
                    throw new Error("Expected Matugen colors in #RRGGBB format");
            }
        }
        return raw;
    }

    readonly property var currentThemeData: {
        const isLight = isLightMode;
        const preset = StockTheme.getPreset(SettingsData.presetTheme, isLight);
        switch (SettingsData.colorSource) {
        case "preset":
            return preset;
        case "custom":
        case "matugen":
            return buildCustomTheme(preset, isLight);
        default:
            return colorsLoaded ? buildDmsTheme(preset) : preset;
        }
    }

    property color primary: currentThemeData.primary
    property color primaryText: currentThemeData.primaryText
    readonly property real containerTint: currentThemeData.containerTint ?? Tonal.defaultTint(surfaceContainer)
    property color primaryContainer: currentThemeData.softPrimaryContainer || Tonal.softContainer(primary, surfaceContainer, containerTint)
    property color secondary: currentThemeData.secondary
    property color secondaryContainer: currentThemeData.secondaryContainer || blend(surfaceContainerHigh, secondary, 0.35)
    property color tertiary: currentThemeData.tertiary || currentThemeData.secondary
    property color tertiaryContainer: currentThemeData.tertiaryContainer || blend(surfaceContainerHigh, tertiary, 0.35)
    readonly property real selectedContainerTint: currentThemeData.selectedContainerTint ?? 0.2
    // DMS exports surfaceContainerHigh as secondary_container when the theme sets none
    readonly property bool themedSelectedContainer: !!currentThemeData.secondaryContainer && !Qt.colorEqual(secondaryContainer, surfaceContainerHigh) && Contrast.isTonal(secondaryContainer, onSecondaryContainer) && Contrast.isTonal(secondaryContainer, surfaceText)
    readonly property color selectedContainer: currentThemeData.selectedContainer || (themedSelectedContainer ? secondaryContainer : Contrast.subtleTint(surfaceContainerHigh, primary, surfaceText, selectedContainerTint))
    readonly property color accentOnSelectedContainer: currentThemeData.accentOnSelectedContainer || (Contrast.ratio(primary, selectedContainer) >= 3 ? primary : onSelectedContainer)
    readonly property color accentOnPrimaryContainer: currentThemeData.accentOnPrimaryContainer || (Contrast.ratio(primary, primaryContainer) >= 3 ? primary : onPrimaryContainer)
    readonly property var accents: Accents.derive(primary, isLightMode, currentThemeData.accents ?? null)
    property color surface: currentThemeData.surface
    property color surfaceText: currentThemeData.surfaceText
    property color surfaceVariant: currentThemeData.surfaceVariant
    property color surfaceVariantText: currentThemeData.surfaceVariantText
    property color surfaceTint: currentThemeData.surfaceTint
    property color surfaceBright: currentThemeData.surfaceBright || (isLightMode ? surface : surfaceContainerHighest)
    property color surfaceDim: currentThemeData.surfaceDim || (isLightMode ? surfaceContainer : background)
    property color background: currentThemeData.background
    property color backgroundText: currentThemeData.backgroundText
    property color outline: currentThemeData.outline
    property color outlineVariant: currentThemeData.outlineVariant || withAlpha(outline, 0.6)
    property color surfaceContainerLowest: currentThemeData.surfaceContainerLowest || blend(surfaceContainer, surface, 1.2)
    property color surfaceContainerLow: currentThemeData.surfaceContainerLow || blend(surface, surfaceContainer, 0.667)
    property color surfaceContainer: currentThemeData.surfaceContainer
    property color surfaceContainerHigh: currentThemeData.surfaceContainerHigh
    property color surfaceContainerHighest: currentThemeData.surfaceContainerHighest || surfaceContainerHigh
    readonly property color hostSurface: surface
    readonly property color cardSurface: surfaceContainer
    readonly property color chipSurface: surfaceContainerHigh
    readonly property color chipSurfaceNested: surfaceContainerHighest
    readonly property color tooltipSurface: inverseSurface
    readonly property color tooltipText: Contrast.readableOn(tooltipSurface, [inverseOnSurface].concat(onContainerCandidates))
    property color inverseSurface: currentThemeData.inverseSurface || surfaceText
    property color inverseOnSurface: currentThemeData.inverseOnSurface || surface
    readonly property color contrastDark: "#000000"
    readonly property color contrastLight: "#ffffff"

    property color onSurface
    property color onSurfaceVariant
    property color onPrimary
    property color onPrimaryContainer
    property color onSecondaryContainer
    property color onTertiaryContainer
    property color onSelectedContainer
    property color onError
    property color onErrorContainer
    property color onSurface_12: withAlpha(onSurface, 0.12)
    property color onSurface_38: withAlpha(onSurface, 0.38)
    property color onSurfaceVariant_30: withAlpha(onSurfaceVariant, 0.3)
    property color onSurfaceVariant_40: withAlpha(onSurfaceVariant, 0.4)
    readonly property list<QtObject> roleBindings: [
        Binding {
            target: root
            property: "onSurface"
            value: root.surfaceText
        },
        Binding {
            target: root
            property: "onSurfaceVariant"
            value: root.surfaceVariantText
        },
        Binding {
            target: root
            property: "onPrimary"
            value: root.primaryText
        },
        Binding {
            target: root
            property: "onPrimaryContainer"
            value: {
                const explicit = root.currentThemeData.onPrimaryContainer;
                if (!explicit)
                    return Contrast.readableOn(root.primaryContainer, root.onContainerCandidates);
                if (root.currentThemeData.softPrimaryContainer)
                    return explicit;
                return Contrast.readableOn(root.primaryContainer, [Qt.color(explicit)].concat(root.onContainerCandidates));
            }
        },
        Binding {
            target: root
            property: "onSecondaryContainer"
            value: root.currentThemeData.onSecondaryContainer || Contrast.readableOn(root.secondaryContainer, root.onContainerCandidates)
        },
        Binding {
            target: root
            property: "onTertiaryContainer"
            value: root.currentThemeData.onTertiaryContainer || Contrast.readableOn(root.tertiaryContainer, root.onContainerCandidates)
        },
        Binding {
            target: root
            property: "onError"
            value: root.currentThemeData.errorText || root.surface
        },
        Binding {
            target: root
            property: "onErrorContainer"
            value: root.currentThemeData.errorContainerText || root.onSurface
        },
        Binding {
            target: root
            property: "onSelectedContainer"
            value: root.currentThemeData.onSelectedContainer || (root.currentThemeData.selectedContainer ? Contrast.readableOn(root.selectedContainer, root.onContainerCandidates) : root.themedSelectedContainer ? root.onSecondaryContainer : root.surfaceText)
        }
    ]
    readonly property var onContainerCandidates: [surfaceText, surface, contrastLight, contrastDark]
    readonly property real tonalTintAlpha: 0.16

    property color error: currentThemeData.error
    property color errorContainer: currentThemeData.errorContainer || surfaceContainerHigh
    property color warning: currentThemeData.warning
    property color info: currentThemeData.info
    property color success: currentThemeData.success

    property color primaryHover: Qt.rgba(primary.r, primary.g, primary.b, 0.12)
    property color primaryHoverLight: Qt.rgba(primary.r, primary.g, primary.b, 0.08)
    property color primaryPressed: Qt.rgba(primary.r, primary.g, primary.b, 0.16)
    property color primarySelected: Qt.rgba(primary.r, primary.g, primary.b, 0.3)
    property color primaryBackground: Qt.rgba(primary.r, primary.g, primary.b, 0.04)

    property color secondaryHover: Qt.rgba(secondary.r, secondary.g, secondary.b, 0.08)

    property color surfaceHover: Qt.rgba(surfaceVariant.r, surfaceVariant.g, surfaceVariant.b, 0.08)
    property color surfaceVariantHover: Qt.lighter(surfaceVariant, 1.2)
    property color surfacePressed: Qt.rgba(surfaceVariant.r, surfaceVariant.g, surfaceVariant.b, 0.12)
    property color surfaceSelected: Qt.rgba(surfaceVariant.r, surfaceVariant.g, surfaceVariant.b, 0.15)
    property color surfaceLight: Qt.rgba(surfaceVariant.r, surfaceVariant.g, surfaceVariant.b, 0.1)
    property color surfaceVariantAlpha: Qt.rgba(surfaceVariant.r, surfaceVariant.g, surfaceVariant.b, 0.2)

    property color surfaceTextHover: Qt.rgba(surfaceText.r, surfaceText.g, surfaceText.b, 0.08)
    property color surfaceTextAlpha: Qt.rgba(surfaceText.r, surfaceText.g, surfaceText.b, 0.3)
    property color surfaceTextLight: Qt.rgba(surfaceText.r, surfaceText.g, surfaceText.b, 0.06)
    property color surfaceTextMedium: Qt.rgba(surfaceText.r, surfaceText.g, surfaceText.b, 0.7)

    property color outlineButton: Qt.rgba(outline.r, outline.g, outline.b, 0.5)
    property color outlineLight: Qt.rgba(outline.r, outline.g, outline.b, 0.05)
    property color outlineMedium: Qt.rgba(outline.r, outline.g, outline.b, 0.12)
    property color outlineStrong: Qt.rgba(outline.r, outline.g, outline.b, 0.18)
    property color outlineHeavy: Qt.rgba(outline.r, outline.g, outline.b, 0.2)
    property color gridLine: Qt.rgba(outline.r, outline.g, outline.b, 0.25)

    property color surfaceTextSecondary: Qt.rgba(surfaceText.r, surfaceText.g, surfaceText.b, 0.6)

    property color errorHover: Qt.rgba(error.r, error.g, error.b, 0.12)
    property color errorPressed: Qt.rgba(error.r, error.g, error.b, 0.16)
    property color errorSelected: Qt.rgba(error.r, error.g, error.b, 0.3)

    property color shadowMedium: Qt.rgba(0, 0, 0, 0.08)
    property color shadowStrong: Qt.rgba(0, 0, 0, 0.3)

    property color buttonBg: primary
    property color buttonText: primaryText
    property color buttonHover: primaryHover
    property color buttonPressed: primaryPressed

    property real spacingXXS: 2
    property real spacingXS: 4
    property real spacingS: 8
    property real spacingM: 12
    readonly property real windowInset: spacingM
    property real spacingL: 16
    property real spacingXL: 24

    readonly property FontSource typography: FontSource {
        source: SettingsData.fontSource
        dmsPath: root.dmsTypographyPath
        family: SettingsData.fontFamily
        monoFamily: SettingsData.monoFontFamily
        displayFamily: SettingsData.displayFontFamily
        weight: SettingsData.fontWeight
        scale: SettingsData.fontScale
    }
    readonly property real fontScale: typography.fontScale
    property real fontSizeSmall: Math.round(fontScale * 12)
    property real fontSizeMedium: Math.round(fontScale * 14)
    property real fontSizeLarge: Math.round(fontScale * 16)
    property real fontSizeXLarge: Math.round(fontScale * 20)
    property real fontSizeXXLarge: Math.round(fontScale * 28)
    property real fontSizeDisplay: Math.round(fontScale * 36)
    property real fontSizeDisplayLarge: Math.round(fontScale * 57)

    property real iconSize: 24
    property real iconSizeSmall: 16
    readonly property real iconSizeMedium: 20
    property real iconSizeLarge: 32

    readonly property real radiusStrength: SettingsData.radiusStrength
    readonly property real shapeScale: Shape.scaleForStrength(radiusStrength)
    readonly property real cornerRadius: cornerRadiusM
    readonly property real cornerRadiusXXS: Shape.radius("xxs", shapeScale)
    readonly property real cornerRadiusXS: Shape.radius("xs", shapeScale)
    readonly property real cornerRadiusS: Shape.radius("s", shapeScale)
    readonly property real cornerRadiusM: Shape.radius("m", shapeScale)
    readonly property real cornerRadiusL: Shape.radius("l", shapeScale)
    readonly property real cornerRadiusLIncreased: Shape.radius("lIncreased", shapeScale)
    readonly property real cornerRadiusXL: Shape.radius("xl", shapeScale)
    readonly property real cornerRadiusXLIncreased: Shape.radius("xlIncreased", shapeScale)
    readonly property real cornerRadiusXXL: Shape.radius("xxl", shapeScale)
    readonly property real cornerRadiusFull: shapeScale > 0 ? 9999 : 0
    readonly property real cornerRadiusSmall: cornerRadiusS
    readonly property real cornerRadiusLarge: cornerRadiusL
    readonly property real windowRadius: cornerRadiusL

    function scaledRadius(radius, limit) {
        return Shape.scaledRadius(radius, limit, shapeScale);
    }

    function fullRadius(width, height) {
        return Shape.fullRadius(width, height, shapeScale);
    }

    function buttonRadius(width, height, sizeHeight, pressed, round) {
        return Shape.buttonRadius(width, height, sizeHeight, pressed, round, shapeScale);
    }

    readonly property real groupedListGap: spacingXXS
    readonly property real groupedListInnerRadius: cornerRadiusXS
    readonly property real groupedListOuterRadius: cornerRadiusL
    readonly property int smallBreakpoint: 480
    readonly property int mediumBreakpoint: 768
    readonly property real iconButtonSize: 40
    readonly property real minimumTouchTargetSize: 48
    readonly property real listItemHeight: 56
    readonly property real listItemTwoLineHeight: 72
    readonly property real avatarSize: 36
    readonly property real sliderTrackHeight: 16
    readonly property real sliderHandleWidth: 4
    readonly property real sliderHandleWidthPressed: 2
    readonly property real sliderHandleWidthDesktop: 6
    readonly property real sliderHandleWidthDesktopPressed: 4
    readonly property real sliderHandleHeightDesktop: 32
    readonly property real sliderHandleHeight: 44
    readonly property real sliderHandleGap: 6
    readonly property real sliderTrackHeightS: 24
    readonly property real sliderHandleHeightS: 44
    readonly property real sliderTrackHeightM: 40
    readonly property real sliderHandleHeightM: 44
    readonly property real sliderTrackHeightL: 56
    readonly property real sliderHandleHeightL: 68
    readonly property real sliderTrackHeightXL: 96
    readonly property real sliderHandleHeightXL: 108
    readonly property real switchTrackWidth: 52
    readonly property real switchTrackHeight: 32
    readonly property real switchOutlineWidth: 2
    readonly property real switchThumbUnselected: 16
    readonly property real switchThumbSelected: 24
    readonly property real switchThumbPressed: 28
    readonly property real sliderStopSize: 4
    readonly property real sliderTickSize: 3
    readonly property real menuItemHeight: 40
    readonly property real outlineWidth: 1
    readonly property real outlineWidthFocused: 2
    readonly property real dividerWidth: 1
    readonly property real focusRingWidth: SettingsData.focusRingEnabled ? SettingsData.focusRingWidth : 0
    readonly property real focusRingOffset: 3
    readonly property color focusRingColor: {
        switch (SettingsData.focusRingColor) {
        case "secondary":
            return secondary;
        case "outline":
            return outline;
        case "surfaceText":
            return surfaceText;
        default:
            return primary;
        }
    }
    readonly property real scrimAlpha: 0.55
    readonly property color scrimColor: currentThemeData.scrim || "#000000"
    readonly property real buttonHeightXXS: 28
    readonly property real buttonHeightXS: 32
    readonly property real buttonHeightS: 40
    readonly property real buttonHeightM: 56
    readonly property real buttonMinWidth: 58
    readonly property real pressScale: 0.98
    readonly property real iconEnterScale: 0.6
    readonly property real dialogMaxWidth: 560
    readonly property real popupEnterScale: 0.92
    readonly property real pendingOpacity: 0.6
    readonly property real spinnerStrokeWidth: 2
    readonly property real tabMinWidth: 64
    readonly property real tabIndicatorHeight: 3
    readonly property real tabIndicatorMinWidth: 24
    readonly property real tabIndicatorInset: 2
    readonly property real fieldDefaultWidth: 200
    readonly property real fieldHeight: Math.round(fontSizeMedium * 3)
    readonly property real fieldHeightLarge: 48
    readonly property real outlinedFieldLabelLineHeight: 16
    readonly property real osdHeight: sliderHandleHeight + spacingS * 2
    readonly property real bottomSheetHandleWidth: 36
    readonly property real bottomSheetHandleHeight: 4
    readonly property real launcherTileSize: 120
    readonly property real launcherImageRatio: 0.75
    readonly property int launcherMaxVisibleRows: 8
    readonly property real launcherWidthMicro: 500
    readonly property real launcherWidthDefault: 620
    readonly property real launcherWidthWide: 720
    readonly property real launcherWidthLarge: 860
    readonly property real launcherHeightDefault: 600
    readonly property real launcherScreenMargin: 100
    readonly property color lockScreenContentColor: "#ffffff"
    readonly property real lockScreenScrimAlpha: 0.4
    readonly property real lockScreenBlur: 0.8
    readonly property int lockScreenBlurMax: 32
    readonly property color screenOffColor: "#000000"
    readonly property real textFieldSpatialStiffness: 800
    readonly property real textFieldSpatialDampingRatio: 1
    readonly property real textFieldFastEffectsStiffness: 3800
    readonly property real textFieldSlowEffectsStiffness: 800
    readonly property real textEditHeight: Math.round(fontSizeMedium * 8)
    readonly property real tooltipMaxWidth: 500
    readonly property int tooltipDelay: 400
    readonly property real menuMaxHeight: 400
    readonly property real clockFaceSize: 250
    readonly property real clockOuterRingRatio: 0.34
    readonly property real clockInnerRingRatio: 0.2
    readonly property real clockHandWidth: 2
    readonly property real clockHandleSize: 40
    readonly property real clockCenterSize: 8
    readonly property int clockSwitchDelay: 100
    readonly property real chipIconSize: 18
    readonly property real buttonGroupExpandRatio: 0.15

    readonly property string fontFamily: typography.fontFamily
    readonly property string monoFontFamily: typography.monoFontFamily
    readonly property string displayFontFamily: typography.displayFontFamily
    readonly property int fontWeight: typography.fontWeight
    readonly property int fontWeightMedium: shiftedFontWeight(Font.Medium)
    readonly property int fontWeightBold: shiftedFontWeight(Font.Bold)

    function shiftedFontWeight(weight) {
        return Math.max(Font.Thin, Math.min(Font.Black, weight + fontWeight - Font.Normal));
    }

    readonly property real floatingWindowTransparency: unitClamp(SettingsData.floatingWindowTransparency)
    readonly property bool floatingWindowForegroundLayers: SettingsData.floatingWindowForegroundLayers
    readonly property real floatingWindowForegroundTransparency: unitClamp(SettingsData.floatingWindowForegroundTransparency)
    readonly property real floatingWindowForegroundAlpha: Surface.foregroundAlpha(floatingWindowForegroundLayers, floatingWindowForegroundTransparency)
    readonly property bool translucentWindows: floatingWindowTransparency < 1
    readonly property real popupTransparency: floatingWindowTransparency
    readonly property bool foregroundLayers: floatingWindowForegroundLayers
    readonly property real foregroundLayerTransparency: floatingWindowForegroundTransparency
    readonly property real foregroundAlpha: floatingWindowForegroundAlpha
    readonly property bool blurLayersActive: BlurService.enabled
    readonly property bool connectedSurfaceBlurEnabled: true

    readonly property color windowSurface: withAlpha(surface, floatingWindowTransparency)
    readonly property color floatingSurface: withAlpha(surfaceContainer, popupTransparency)
    readonly property color nestedSurface: withAlpha(surfaceContainerHigh, foregroundAlpha)
    readonly property color floatingWindowSurface: withAlpha(surfaceContainer, floatingWindowTransparency)
    readonly property color floatingWindowNestedSurface: withAlpha(surfaceContainerHigh, floatingWindowForegroundAlpha)
    readonly property color floatingWindowPaneSurface: withAlpha(surfaceContainer, floatingWindowForegroundAlpha)
    readonly property color floatingWindowFieldColor: floatingWindowNestedSurface
    readonly property color floatingWindowFieldBorderColor: withAlpha(outline, 0.16)
    readonly property color floatingWindowFieldFocusedBorderColor: primary
    readonly property color popupFieldColor: nestedSurface
    readonly property color popupFieldBorderColor: withAlpha(outline, 0.16)
    readonly property color popupFieldFocusedBorderColor: primary

    function isFloatingWindow(item) {
        return Surface.isFloatingWindow(item);
    }

    function accent(name) {
        return accents[name] ?? null;
    }

    function unitClamp(value) {
        if (typeof value !== "number" || !isFinite(value))
            return 1;
        return Math.max(0, Math.min(1, value));
    }

    function foregroundColor(baseColor, floatingWindow = false) {
        return blendAlpha(baseColor, floatingWindow ? floatingWindowForegroundAlpha : foregroundAlpha);
    }

    property color widgetBaseHoverColor: {
        const blended = blend(surfaceContainerHigh, primary, 0.1);
        return withAlpha(blended, Math.max(0.3, blended.a));
    }

    readonly property int currentAnimationBaseDuration: SettingsData.animationDuration
    readonly property int currentAnimationSpeed: currentAnimationBaseDuration > 0 ? Style.AnimationSpeed.Custom : Style.AnimationSpeed.None
    readonly property int shorterDuration: Math.round(currentAnimationBaseDuration * 0.2)
    readonly property int shortDuration: Math.round(currentAnimationBaseDuration * 0.3)
    readonly property int mediumDuration: Math.round(currentAnimationBaseDuration * 0.6)
    readonly property int longDuration: currentAnimationBaseDuration
    readonly property int standardEasing: Easing.OutCubic
    readonly property int emphasizedEasing: Easing.OutQuart
    readonly property bool elevationEnabled: true
    readonly property string elevationLightDirection: "top"

    readonly property real stateLayerHover: 0.08
    readonly property real stateLayerFocus: 0.12
    readonly property real stateLayerPressed: 0.12
    readonly property real stateLayerDrag: 0.16

    readonly property var springSpecs: ({
            "expressive": [560, 37],
            "fast": [220, 23],
            "default": [300, 24]
        })
    readonly property var springDampingScales: [1.22, 1.0, 0.82]
    readonly property bool springMotionDisabled: currentAnimationBaseDuration <= 0
    readonly property bool reduceMotion: SettingsData.reduceMotion
    readonly property bool animationsEnabled: !reduceMotion && currentAnimationBaseDuration > 0

    function springPreset(name, baseDuration) {
        const spec = springSpecs[name] ?? springSpecs["default"];
        const f = Math.max(0.05, baseDuration / 500);
        const bounce = springDampingScales[Math.round(SettingsData.springBounce)] ?? 1;
        return {
            "stiffness": spec[0] / (f * f),
            "damping": spec[1] / f * bounce,
            "mass": 1
        };
    }

    readonly property var elevationLevel1: ({
            blurPx: 4,
            offsetX: 0,
            offsetY: 1,
            spreadPx: 0,
            alpha: 0.2
        })

    readonly property var elevationLevel2: ({
            blurPx: 8,
            offsetX: 0,
            offsetY: 4,
            spreadPx: 0,
            alpha: 0.25
        })

    readonly property var elevationLevel3: ({
            blurPx: 12,
            offsetX: 0,
            offsetY: 6,
            spreadPx: 0,
            alpha: 0.3
        })

    readonly property var expressiveCurves: ({
            "emphasized": [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1],
            "emphasizedAccel": [0.3, 0, 0.8, 0.15, 1, 1],
            "emphasizedDecel": [0.05, 0.7, 0.1, 1, 1, 1],
            "standard": [0.2, 0, 0, 1, 1, 1],
            "standardAccel": [0.3, 0, 1, 1, 1, 1],
            "standardDecel": [0, 0, 0, 1, 1, 1],
            "expressiveFastSpatial": [0.42, 1.67, 0.21, 0.9, 1, 1],
            "expressiveDefaultSpatial": [0.38, 1.21, 0.22, 1, 1, 1],
            "expressiveEffects": [0.34, 0.8, 0.34, 1, 1, 1]
        })

    readonly property var expressiveDurations: ({
            "fast": currentAnimationBaseDuration * 0.4,
            "normal": currentAnimationBaseDuration * 0.8,
            "large": currentAnimationBaseDuration * 1.2,
            "extraLarge": currentAnimationBaseDuration * 2.0,
            "expressiveFastSpatial": currentAnimationBaseDuration * 0.7,
            "expressiveDefaultSpatial": currentAnimationBaseDuration,
            "expressiveEffects": currentAnimationBaseDuration * 0.4
        })

    function elevationOffsetXFor(level, direction, fallback) {
        return level?.offsetX ?? 0;
    }

    function elevationOffsetYFor(level, direction, fallback) {
        return level?.offsetY ?? (fallback ?? 0);
    }

    function elevationShadowColor(level) {
        return Qt.rgba(0, 0, 0, level?.alpha ?? 0.3);
    }

    function elevationAmbient(level) {
        return {
            "blurPx": (level?.blurPx ?? 0) * 1.75,
            "spreadPx": 1,
            "alpha": (level?.alpha ?? 0.3) * 0.5
        };
    }

    function withAlpha(c, a) {
        return Style.withAlpha(c, a);
    }

    function blendAlpha(c, a) {
        return Style.blendAlpha(c, a);
    }

    function blend(c1, c2, r) {
        return Qt.rgba(c1.r * (1 - r) + c2.r * r, c1.g * (1 - r) + c2.g * r, c1.b * (1 - r) + c2.b * r, c1.a * (1 - r) + c2.a * r);
    }

    // a tiled parent keeps its on-screen size under zoom, so the cap undoes the zoom
    function modalWidth(parentWin, scr, preferred) {
        const screenCap = scr ? scr.width - 80 : 1200;
        const parentCap = parentWin && parentWin.width > 0 ? parentWin.width * 0.8 * SettingsData.effectiveUiScale : screenCap;
        return Math.round(Math.min(preferred, screenCap, parentCap));
    }

    function modalHeight(parentWin, scr, natural) {
        const screenCap = scr ? scr.height - 80 : 900;
        const parentCap = parentWin && parentWin.height > 0 ? parentWin.height * 0.8 * SettingsData.effectiveUiScale : screenCap;
        return Math.round(Math.min(natural, screenCap, parentCap));
    }

    FileView {
        id: dmsColorsView
        path: root.dmsColorsPath
        blockLoading: false
        watchChanges: true

        onLoaded: {
            try {
                const text = dmsColorsView.text();
                if (!text)
                    return;
                root.matugenColors = JSON.parse(text);
                root.colorsLoaded = true;
            } catch (e) {
                root.colorsLoaded = false;
            }
        }

        onFileChanged: dmsColorsView.reload()

        onLoadFailed: function (error) {
            if (!root.useLegacyDmsCache) {
                root.useLegacyDmsCache = true;
                return;
            }
            root.colorsLoaded = false;
        }
    }

    FileView {
        id: customThemeView
        path: {
            if (SettingsData.colorSource === "matugen")
                return root.matugenThemePath;
            const f = SettingsData.customThemeFile;
            if (!f || f === "")
                return "";
            if (f.startsWith("~/"))
                return Quickshell.env("HOME") + f.substring(1);
            return f;
        }
        blockLoading: false
        watchChanges: true
        printErrors: false

        onPathChanged: {
            root.customThemeRaw = null;
            root.customThemeLoaded = false;
        }

        onLoaded: {
            try {
                const text = customThemeView.text();
                if (!text) {
                    root.customThemeRaw = null;
                    root.customThemeLoaded = false;
                    return;
                }
                const raw = JSON.parse(text);
                root.customThemeRaw = SettingsData.colorSource === "matugen" ? root.validateMatugenTheme(raw) : raw;
                root.customThemeLoaded = true;
            } catch (e) {
                root.customThemeRaw = null;
                root.customThemeLoaded = false;
            }
        }

        onFileChanged: customThemeView.reload()

        onLoadFailed: {
            root.customThemeRaw = null;
            root.customThemeLoaded = false;
        }
    }
}
