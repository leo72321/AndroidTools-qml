import QtQuick
import QtQuick.Layouts
import FluentUI

Rectangle {
    id: compact
    property string label: ""
    property string value: ""
    property color accent: FluTheme.primaryColor

    Layout.fillWidth: true
    Layout.preferredHeight: 32
    radius: 7
    color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.040) : Qt.rgba(0, 0, 0, 0.024)
    border.width: 1
    border.color: Qt.rgba(accent.r, accent.g, accent.b, FluTheme.dark ? 0.18 : 0.13)

    RowLayout {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
        spacing: 7
        Rectangle { Layout.preferredWidth: 5; Layout.preferredHeight: 5; radius: 3; color: compact.accent }
        FluText {
            id: labelText
            text: compact.label
            font: FluTextStyle.Caption
            color: FluTheme.fontSecondaryColor
            Layout.preferredWidth: implicitWidth
            Layout.maximumWidth: Math.max(compact.width * 0.4, 64)
            elide: Text.ElideRight

            MouseArea {
                id: labelHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
            FluTooltip {
                visible: labelHover.containsMouse && labelText.text.length > 0
                text: labelText.text
                delay: 500
            }
        }
        FluText {
            id: valueText
            text: compact.value
            font: FluTextStyle.Caption
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight

            MouseArea {
                id: valueHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
            FluTooltip {
                visible: valueHover.containsMouse && valueText.text.length > 0
                text: valueText.text
                delay: 500
            }
        }
    }
}
