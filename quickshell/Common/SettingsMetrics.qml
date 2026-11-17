pragma Singleton

import QtQuick
import Quickshell
import qs.Common

Singleton {
    readonly property real sidebarWidth: 260
    readonly property real compactBreakpoint: 640
    readonly property real contentMaxWidth: Number.POSITIVE_INFINITY
    readonly property real pagePaddingV: Theme.spacingXL
    // Centers the page title on the first sidebar row
    readonly property real pageHeaderHeight: navItemMinHeight + paneMargin * 2
    readonly property real paneMargin: Theme.windowInset
    readonly property real panePadding: Theme.spacingXL
    readonly property real rowPaddingH: Theme.spacingL + Theme.spacingXS
    readonly property real rowPaddingV: Theme.spacingL
    readonly property real rowContentSpacing: Theme.spacingL
    readonly property real sectionLabelTopGap: Theme.spacingS
    readonly property real sectionLabelBottomGap: Theme.spacingM
    readonly property real navIconSize: Theme.avatarSize
    readonly property real navItemMinHeight: Theme.listItemHeight
    readonly property real sidebarGroupGap: Theme.spacingS
    readonly property real buttonGroupCompactThreshold: 200
    readonly property real disabledOpacity: 0.38
    readonly property real highlightBlend: 0.2
    readonly property color paneColor: Theme.floatingWindowPaneSurface
    readonly property color sidebarRowColor: rowColor
    readonly property color rowColor: Theme.foregroundColor(Theme.chipSurface, true)
    readonly property color controlSurface: Theme.chipSurfaceNested
    readonly property color selectedRowColor: Theme.selectedContainer
    readonly property int transitionDuration: Theme.expressiveDurations.expressiveFastSpatial
    readonly property int fadeDuration: Theme.expressiveDurations.expressiveEffects
}
