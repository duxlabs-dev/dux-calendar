import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property string githubUrl: "https://github.com/duxlabs-dev/dux-calendar"
    readonly property string docsUrl: "https://duxlabs.dev/docs"
    readonly property string discordUrl: "https://discord.gg/ppWTpKmPgT"
    readonly property string kofiUrl: "https://ko-fi.com/duxlabs"
    readonly property string licenseUrl: githubUrl + "/blob/master/LICENSE"
    readonly property string version: DankCalService.daemonVersion.match(/^v?(\d+\.\d+)/)?.[1] ?? ""

    function host(url) {
        return url.replace(/^https?:\/\//, "").replace(/\/$/, "");
    }

    SettingsPage {
        DHeroCard {
            brand: I18n.tr("Calendar", "about page hero, app name")
            caption: root.version ? `dcal ${root.version}` : "dcal"

            DButton {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Support Dux Labs", "about page hero button, opens the Ko-fi donation page")
                iconName: "favorite"
                onClicked: Qt.openUrlExternally(root.kofiUrl)
            }
        }

        SettingsCard {
            SettingsRow {
                body: StyledText {
                    text: I18n.tr('Dux Calendar is a calendar for the modern Linux desktop with a <a href="https://m3.material.io/" style="text-decoration:none; color:%1;">material 3 inspired</a> design, plus a hackable CLI and socket API for integrations.<br /><br/>It is built with <a href="https://quickshell.org" style="text-decoration:none; color:%1;">Quickshell</a>, a QT6 framework for building desktop shells, and <a href="https://go.dev" style="text-decoration:none; color:%1;">Go</a>, a statically typed, compiled programming language.', 'about page project description with embedded links').arg(Theme.primary)
                    textFormat: Text.RichText
                    font.pixelSize: Theme.fontSizeMedium
                    linkColor: Theme.primary
                    onLinkActivated: url => Qt.openUrlExternally(url)
                    color: Theme.surfaceVariantText
                    width: parent.width
                    wrapMode: Text.WordWrap

                    HoverHandler {
                        cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }
        }

        SettingsCard {
            SettingsLinkRow {
                iconName: "menu_book"
                title: I18n.tr("Docs", "about page resource button")
                subtitle: root.host(root.docsUrl)
                url: root.docsUrl
            }

            SettingsLinkRow {
                iconName: "code"
                title: I18n.tr("GitHub", "about page resource button")
                subtitle: root.host(root.githubUrl)
                url: root.githubUrl
            }
        }

        SettingsCard {
            title: I18n.tr("Community", "about page card title, chat and community links")

            SettingsLinkRow {
                title: "niri/dux Discord"
                subtitle: root.host(root.discordUrl)
                url: root.discordUrl
                leading: Image {
                    width: Theme.iconSize
                    height: Theme.iconSize
                    source: Qt.resolvedUrl("../assets/discord.svg")
                    sourceSize: Qt.size(Theme.iconSize, Theme.iconSize)
                    smooth: true
                    fillMode: Image.PreserveAspectFit
                }
            }
        }

        SettingsCard {
            title: I18n.tr("Backend", "about page daemon section header")

            SettingsRow {
                title: I18n.tr("Version", "about page daemon version column label")
                trailingBadge: DankCalService.daemonVersion || "—"
            }

            SettingsRow {
                title: I18n.tr("API", "about page daemon api version column label")
                trailingBadge: DankCalService.apiVersion > 0 ? `v${DankCalService.apiVersion}` : "—"
            }

            SettingsRow {
                title: I18n.tr("Status", "about page daemon status column label")
                trailingBadge: DankCalService.connected ? I18n.tr("Connected", "about page daemon status value") : I18n.tr("Offline", "about page daemon status value")

                DBadge {
                    color: DankCalService.connected ? Theme.success : Theme.error
                }
            }

            SettingsRow {
                visible: DankCalService.capabilities.length > 0
                title: I18n.tr("Capabilities", "about page daemon capabilities label")
                body: Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: DankCalService.capabilities

                        DBadge {
                            required property string modelData
                            text: modelData
                            color: Theme.withAlpha(Theme.primary, Theme.tonalTintAlpha)
                            textColor: Theme.primary
                        }
                    }
                }
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr('<a href="%2" style="text-decoration:none; color:%1;">MIT License</a>', 'about page license footer link, %2 is the license url').arg(Theme.surfaceVariantText).arg(root.licenseUrl)
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            textFormat: Text.RichText
            wrapMode: Text.NoWrap
            onLinkActivated: url => Qt.openUrlExternally(url)

            HoverHandler {
                cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }
    }
}
