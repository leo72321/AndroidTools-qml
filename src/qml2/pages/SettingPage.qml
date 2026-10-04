import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FluentUI
import WallPaperModel 1.0
import WallpaperHelper 1.0
import OtherSettingsHandler 1.0
import App 1.0
import ConnectManager 1.0

FluContentPage {
    title: "設定"


    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 12

            // ---- Wallpaper ----
            FluFrame {
                Layout.fillWidth: true
                Layout.preferredHeight: wallpaperLayout.implicitHeight + 32
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 12

                ColumnLayout {
                    id: wallpaperLayout
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    FluText { text: "桌布"; font: FluTextStyle.Subtitle }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 85
                        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                        ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                        RowLayout {
                            height: 75
                            spacing: 8
                            Repeater {
                                model: WallPaperModel
                                delegate: Rectangle {
                                    required property int index
                                    required property string url
                                    width: 110; height: 75; radius: 8; color: "transparent"; clip: true
                                    border { color: index === WallPaperModel.currentIndex ? FluTheme.primaryColor : Qt.rgba(0,0,0,0.1); width: 2 }
                                    Image {
                                        anchors { fill: parent; margins: 4 }
                                        source: url; fillMode: Image.PreserveAspectCrop; asynchronous: true
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: WallPaperModel.setCurrentIndex(index) }
                                }
                            }
                            FluButton { text: "+ 新增"; Layout.preferredWidth: 80; Layout.preferredHeight: 75; onClicked: WallpaperHelper.requestAddCustomWallpaper() }
                        }
                    }

                    RowLayout {
                        FluText { text: "不透明度"; Layout.preferredWidth: 140 }
                        FluSlider {
                            id: opacitySlide; Layout.fillWidth: true
                            from: 0.1; to: 1.0; stepSize: 0.05; value: WallpaperHelper.opacity
                            onMoved: WallpaperHelper.opacity = value
                        }
                        FluText { text: Math.round(opacitySlide.value*100)+"%"; Layout.preferredWidth: 40 }
                    }

                    RowLayout {
                        FluText { text: "模糊"; Layout.preferredWidth: 140 }
                        FluSlider {
                            id: blurSlide; Layout.fillWidth: true
                            from: 0; to: 64; stepSize: 1; value: WallpaperHelper.blurRadius
                            onMoved: WallpaperHelper.blurRadius = value
                        }
                        FluText { text: Math.round(blurSlide.value); Layout.preferredWidth: 40 }
                    }
                }
            }

            // ---- Appearance ----
            FluFrame {
                Layout.fillWidth: true
                Layout.preferredHeight: appearanceLayout.implicitHeight + 32
                Layout.leftMargin: 20
                Layout.rightMargin: 20

                ColumnLayout {
                    id: appearanceLayout
                    anchors { left: parent.left; top: parent.top; right: parent.right; margins: 16 }
                    spacing: 12

                    FluText { text: "外觀"; font: FluTextStyle.Subtitle }

                    RowLayout {
                        FluText { text: "深色模式"; Layout.preferredWidth: 140 }
                        FluToggleSwitch {
                            checked: App.themeType === App.Dark
                            clickListener: function() { App.setThemeType(checked ? App.Light : App.Dark) }
                        }
                    }

                    RowLayout {
                        FluText { text: "面板不透明度"; Layout.preferredWidth: 140 }
                        FluSlider {
                            id: panelSlide; Layout.fillWidth: true
                            from: 0.1; to: 1.0; stepSize: 0.05; value: OtherSettingsHandler.wrapperOpacity
                            onMoved: OtherSettingsHandler.wrapperOpacity = value
                        }
                        FluText { text: Math.round(panelSlide.value*100)+"%"; Layout.preferredWidth: 40 }
                    }
                }
            }

            // ---- Advanced ----
            FluFrame {
                Layout.fillWidth: true
                Layout.preferredHeight: advancedLayout.implicitHeight + 32
                Layout.leftMargin: 20
                Layout.rightMargin: 20

                ColumnLayout {
                    id: advancedLayout
                    anchors { left: parent.left; top: parent.top; right: parent.right; margins: 16 }
                    spacing: 12

                    FluText { text: "進階"; font: FluTextStyle.Subtitle }

                    RowLayout {
                        FluText { text: "OpenGL"; Layout.preferredWidth: 140 }
                        FluToggleSwitch {
                            checked: OtherSettingsHandler.useOpenGL
                            clickListener: function() { OtherSettingsHandler.useOpenGL = !checked }
                        }
                        FluText { text: "(重新啟動後生效)"; font: FluTextStyle.Caption; color: FluTheme.fontSecondaryColor }
                    }

                    RowLayout {
                        FluText { text: "重新整理間隔"; Layout.preferredWidth: 140 }
                        FluSlider {
                            id: refSlide; Layout.fillWidth: true
                            from: 1000; to: 30000; stepSize: 1000
                            value: OtherSettingsHandler.deviceRefreshInterval
                            onMoved: OtherSettingsHandler.deviceRefreshInterval = value
                        }
                        FluText { text: Math.round(refSlide.value/1000)+"s"; Layout.preferredWidth: 36 }
                    }

                    RowLayout {
                        FluText { text: "ADB 服務"; Layout.preferredWidth: 140 }
                        FluButton {
                            text: ConnectManager.adbServerStarting ? "重新啟動中..." : "重新啟動"
                            enabled: !ConnectManager.adbServerStarting
                            onClicked: ConnectManager.restartADBServer()
                        }
                    }
                }
            }

            // ---- About ----
            FluFrame {
                Layout.fillWidth: true
                Layout.preferredHeight: aboutLayout.implicitHeight + 32
                Layout.leftMargin: 20
                Layout.rightMargin: 20

                ColumnLayout {
                    id: aboutLayout
                    anchors { left: parent.left; top: parent.top; right: parent.right; margins: 16 }
                    spacing: 4

                    FluText { text: "關於"; font: FluTextStyle.Subtitle }
                    FluText { text: "AndroidTools v0.1.0"; font: FluTextStyle.Body }
                    FluText { text: "Qt 6.x  ·  MIT License"; font: FluTextStyle.Caption; color: FluTheme.fontSecondaryColor }
                }
            }
        }
    }
}
