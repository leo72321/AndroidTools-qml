import QtQuick
import QtQuick.Layouts
import FluentUI

Rectangle {
    id: tile
    property string label: ""
    property string value: ""
    property string sub: ""
    property color accent: FluTheme.primaryColor

    Layout.fillWidth: true
    Layout.preferredHeight: 50
    radius: 7
    color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.045) : Qt.rgba(0, 0, 0, 0.028)
    border.width: 1
    border.color: Qt.rgba(accent.r, accent.g, accent.b, FluTheme.dark ? 0.24 : 0.18)

    ColumnLayout {
        anchors { fill: parent; leftMargin: 10; rightMargin: 10; topMargin: 6; bottomMargin: 6 }
        spacing: 1
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 6
            Rectangle { Layout.preferredWidth: 5; Layout.preferredHeight: 5; radius: 3; color: tile.accent }
            FluText {
                text: tile.label
                font: FluTextStyle.Caption
                color: FluTheme.fontSecondaryColor
                Layout.preferredWidth: implicitWidth
                elide: Text.ElideRight
            }
            FluText {
                id: subText
                text: tile.sub
                font: FluTextStyle.Caption
                color: FluTheme.fontSecondaryColor
                visible: tile.sub.length > 0
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight

                MouseArea {
                    id: subHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
                FluTooltip {
                    visible: subHover.containsMouse && subText.text.length > 0
                    text: subText.text
                    delay: 500
                }
            }
        }
        FluText {
            id: valueText
            text: tile.value
            font: FluTextStyle.BodyStrong
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight

            MouseArea {
                id: valHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
            FluTooltip {
                visible: valHover.containsMouse && valueText.text.length > 0
                text: valueText.text
                delay: 500
            }
        }
    }
}
