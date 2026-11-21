pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtCore
import qs.DCommon.Common as DC

Singleton {
    id: root

    readonly property url home: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
    readonly property url xdgCache: StandardPaths.standardLocations(StandardPaths.GenericCacheLocation)[0]
    readonly property url cache: `${xdgCache}/dankcal`
    readonly property url imagecache: `${cache}/imagecache`

    // False on a dux-qt-base without iconThemeRevision, whose icon provider fails on "?rev=".
    readonly property bool iconThemeLive: "iconThemeRevision" in Quickshell
    readonly property int iconThemeRevision: iconThemeLive ? Quickshell.iconThemeRevision : 0

    function stringify(path: url): string {
        return path.toString().replace(/%20/g, " ");
    }

    function expandTilde(path: string): string {
        if (!path.startsWith("~"))
            return path;
        return strip(root.home) + path.substring(1);
    }

    function shortenHome(path: string): string {
        return path.replace(strip(root.home), "~");
    }

    function strip(path: url): string {
        return stringify(path).replace("file://", "");
    }

    function toFileUrl(path: string): string {
        return path.startsWith("file://") ? path : "file://" + path;
    }

    function mkdir(path: url): void {
        Quickshell.execDetached(["mkdir", "-p", strip(path)]);
    }

    function resolveIconPath(iconName: string): string {
        if (!iconName)
            return "";
        return themeIconUrl(iconName);
    }

    // The inline half serves a DCommon that predates themeIconUrl.
    function themeIconUrl(iconName: string): string {
        if (typeof DC.Paths.themeIconUrl === "function")
            return DC.Paths.themeIconUrl(iconName);
        const url = Quickshell.iconPath(iconName, true) || "";
        return url && iconThemeLive ? url + "?rev=" + iconThemeRevision : url;
    }

    function copyPathToClipboard(path: string): void {
        Quickshell.clipboardText = path;
    }

    Component.onCompleted: mkdir(imagecache)
}
