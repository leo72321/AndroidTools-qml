import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import FluentUI
import ConnectManager 1.0
import SoftListModel 1.0
import AppDetailControl 1.0
import NotificationController 1.0
import "qrc:/qml2/components"
import "qrc:/qml2/pages/home"

FluContentPage {
    id: page
    title: ""

    property var device: ConnectManager.cutADBDevice

    // Selected package for right-side detail view
    property string selectedPackage: ""
    property string selectedAppName: ""
    property string selectedAppVersion: ""
    property string selectedAppVersionCode: ""
    property string selectedAppIcon: ""
    property bool selectedIsSystem: false
    property bool selectedIsEnabled: true
    property bool selectedInstalledForCurrentUser: true
    property string selectedInstallDate: ""
    property string selectedLastUpdate: ""
    property string selectedMinSdk: ""
    property string selectedTargetSdk: ""
    property string selectedAppPath: ""
    property string selectedAppId: ""

    // Multi-selection state: { [pkg]: { packageName, appName, isSystemApp, isEnabled, installedForCurrentUser } }
    property var selectedMap: ({})
    readonly property int selectedCount: Object.keys(selectedMap).length

    // App registry cache for full enumeration (in addition to model queries)
    property var appRegistry: ({})

    // Search query
    property string searchQuery: ""

    // Batch uninstall state machine
    property var uninstallQueue: []
    property int uninstallTotal: 0
    property int uninstallIndex: 0
    property string uninstallCurrentPkg: ""
    property string uninstallCurrentName: ""
    property var uninstallSuccessList: []
    property var uninstallFailList: []
    property bool uninstallRunning: false
    property string uninstallState: "dispatch" // "dispatch" | "waiting"
    property int uninstallStepTimeout: 0
    property string lastReportedResult: ""
    property string lastReportedReason: ""

    // Batch restore state machine
    property var restoreQueue: []
    property int restoreTotal: 0
    property int restoreIndex: 0
    property string restoreCurrentPkg: ""
    property string restoreCurrentName: ""
    property var restoreSuccessList: []
    property var restoreFailList: []
    property bool restoreRunning: false
    property string restoreState: "dispatch" // "dispatch" | "waiting"
    property int restoreStepTimeout: 0

    // Generic batch action queue
    property var batchQueue: []
    property string batchActionType: ""
    property string batchActionTargetDir: ""
    property int batchIndex: 0
    property bool batchRunning: false

    Connections {
        target: AppDetailControl
        function onIconLoaded(packageName, iconBase64) {
            if (packageName === page.selectedPackage) {
                page.selectedAppIcon = iconBase64
            }
        }
    }

    Connections {
        target: NotificationController
        function onRequestNotification() {
            var title = NotificationController.title || ""
            var content = NotificationController.content || ""

            if (page.uninstallRunning) {
                if (page.uninstallCurrentPkg.length > 0 &&
                    (content.indexOf(page.uninstallCurrentPkg) !== -1 || content === page.uninstallCurrentPkg)) {
                    if (title.indexOf("成功") !== -1) {
                        page.lastReportedResult = "success"
                    } else if (title.indexOf("失敗") !== -1 || title.indexOf("失败") !== -1) {
                        page.lastReportedResult = "fail"
                        page.lastReportedReason = title
                    }
                }
            }

            if (page.restoreRunning) {
                if (page.restoreCurrentPkg.length > 0 &&
                    (content.indexOf(page.restoreCurrentPkg) !== -1 || content === page.restoreCurrentPkg)) {
                    if (title.indexOf("成功") !== -1) {
                        page.lastReportedResult = "success"
                    } else if (title.indexOf("失敗") !== -1 || title.indexOf("失败") !== -1) {
                        page.lastReportedResult = "fail"
                        page.lastReportedReason = title
                    }
                }
            }
        }
    }

    function localPath(url) {
        var path = String(url)
        if (path.indexOf("file:///") === 0)
            return decodeURIComponent(path.substring(8))
        if (path.indexOf("file://") === 0)
            return decodeURIComponent(path.substring(Qt.platform.os === "windows" ? 8 : 7))
        return path
    }

    function registerApp(info) {
        if (!info || !info.packageName) return
        var reg = appRegistry
        reg[info.packageName] = info
        appRegistry = reg
    }

    function selectAppForDetail(pkg, name, ver, icon, isSys, vCode, fTime, lTime, mSdk, tSdk, path, appId, isEnabled, isInstalled) {
        page.selectedPackage = pkg || ""
        page.selectedAppName = name || ""
        page.selectedAppVersion = ver || ""
        page.selectedAppVersionCode = vCode !== undefined && vCode !== null ? String(vCode) : ""
        page.selectedAppIcon = icon || ""
        page.selectedIsSystem = !!isSys
        page.selectedIsEnabled = (isEnabled !== undefined && isEnabled !== null) ? !!isEnabled : true
        page.selectedInstalledForCurrentUser = (isInstalled !== undefined && isInstalled !== null) ? !!isInstalled : true
        page.selectedInstallDate = fTime || ""
        page.selectedLastUpdate = lTime || ""
        page.selectedMinSdk = mSdk !== undefined && mSdk !== null ? String(mSdk) : ""
        page.selectedTargetSdk = tSdk !== undefined && tSdk !== null ? String(tSdk) : ""
        page.selectedAppPath = path || ""
        page.selectedAppId = appId !== undefined && appId !== null ? String(appId) : ""

        if (page.selectedPackage.length > 0) {
            AppDetailControl.updateInfo(page.selectedPackage)
            if (page.selectedAppIcon.length === 0) {
                AppDetailControl.requestLoadIcon(page.selectedPackage)
            }
        }
    }

    function toggleSelect(pkg, name, isSys, isEnabled, isInstalled) {
        if (!pkg) return
        var map = Object.assign({}, page.selectedMap)
        if (map[pkg]) {
            delete map[pkg]
        } else {
            map[pkg] = {
                packageName: pkg,
                appName: name || pkg,
                isSystemApp: !!isSys,
                isEnabled: (isEnabled !== undefined && isEnabled !== null) ? !!isEnabled : true,
                installedForCurrentUser: (isInstalled !== undefined && isInstalled !== null) ? !!isInstalled : true
            }
        }
        page.selectedMap = map
    }

    function isSelected(pkg) {
        return !!page.selectedMap[pkg]
    }

    function getSelectedList() {
        var list = []
        for (var k in page.selectedMap) {
            list.push(page.selectedMap[k])
        }
        return list
    }

    function getAppFromModel(row) {
        try {
            var idx = SoftListModel.index(row, 0)
            var pkg = SoftListModel.data(idx, 257) // AppPackageRole
            var name = SoftListModel.data(idx, 258) // AppNameRole
            var isSys = SoftListModel.data(idx, 261) // AppIsSystemRole
            var isEn = SoftListModel.data(idx, 262) // AppIsEnabledRole
            var isInst = SoftListModel.data(idx, 270) // AppInstalledForCurrentUserRole
            if (pkg && pkg.length > 0) {
                return {
                    packageName: pkg,
                    appName: (name && name.length > 0) ? name : pkg,
                    isSystemApp: !!isSys,
                    isEnabled: isEn !== undefined ? !!isEn : true,
                    installedForCurrentUser: isInst !== undefined ? !!isInst : true
                }
            }
        } catch(e) {}
        return null
    }

    function getAllMatchingApps() {
        var query = page.searchQuery.trim().toLowerCase()
        var list = []
        var total = appListView.count
        var directSuccess = false

        for (var i = 0; i < total; i++) {
            var item = getAppFromModel(i)
            if (item && item.packageName) {
                directSuccess = true
                if (query.length > 0) {
                    var m1 = item.packageName.toLowerCase().indexOf(query) !== -1
                    var m2 = (item.appName || "").toLowerCase().indexOf(query) !== -1
                    if (!m1 && !m2) continue
                }
                list.push(item)
            }
        }

        if (!directSuccess || list.length === 0) {
            for (var k in page.appRegistry) {
                var cached = page.appRegistry[k]
                if (query.length > 0) {
                    var c1 = cached.packageName.toLowerCase().indexOf(query) !== -1
                    var c2 = (cached.appName || "").toLowerCase().indexOf(query) !== -1
                    if (!c1 && !c2) continue
                }
                list.push(cached)
            }
        }
        return list
    }

    function selectAll() {
        var matching = getAllMatchingApps()
        var map = Object.assign({}, page.selectedMap)
        for (var i = 0; i < matching.length; i++) {
            var item = matching[i]
            map[item.packageName] = {
                packageName: item.packageName,
                appName: item.appName || item.packageName,
                isSystemApp: !!item.isSystemApp,
                isEnabled: item.isEnabled !== undefined ? !!item.isEnabled : true,
                installedForCurrentUser: item.installedForCurrentUser !== undefined ? !!item.installedForCurrentUser : true
            }
        }
        page.selectedMap = map
    }

    function deselectAll() {
        page.selectedMap = ({})
    }

    function invertSelection() {
        var matching = getAllMatchingApps()
        var map = Object.assign({}, page.selectedMap)
        for (var i = 0; i < matching.length; i++) {
            var item = matching[i]
            if (map[item.packageName]) {
                delete map[item.packageName]
            } else {
                map[item.packageName] = {
                    packageName: item.packageName,
                    appName: item.appName || item.packageName,
                    isSystemApp: !!item.isSystemApp,
                    isEnabled: item.isEnabled !== undefined ? !!item.isEnabled : true,
                    installedForCurrentUser: item.installedForCurrentUser !== undefined ? !!item.installedForCurrentUser : true
                }
            }
        }
        page.selectedMap = map
    }

    // Generic batch action dispatch
    function startBatchAction(type, extra) {
        var list = getSelectedList()
        if (list.length === 0) return
        page.batchQueue = list
        page.batchActionType = type
        page.batchActionTargetDir = extra || ""
        page.batchIndex = 0
        page.batchRunning = true
        batchTimer.restart()
    }

    Timer {
        id: batchTimer
        interval: 200
        repeat: true
        onTriggered: {
            if (!page.batchRunning) {
                stop()
                return
            }
            if (page.batchIndex >= page.batchQueue.length) {
                page.batchRunning = false
                stop()
                NotificationController.send("批次操作完成", "已完成 " + page.batchQueue.length + " 個應用程式的操作", NotificationController.Info)
                AppDetailControl.requestUpdateSoftList()
                return
            }
            if (AppDetailControl.busy) return

            var item = page.batchQueue[page.batchIndex]
            var pkg = item.packageName
            if (page.batchActionType === "start") {
                AppDetailControl.startApp(pkg)
            } else if (page.batchActionType === "stop") {
                AppDetailControl.stopApp(pkg)
            } else if (page.batchActionType === "enable") {
                AppDetailControl.enableApp(pkg)
            } else if (page.batchActionType === "freeze") {
                AppDetailControl.freezeApp(pkg)
            } else if (page.batchActionType === "clearData") {
                AppDetailControl.clearData(pkg)
            } else if (page.batchActionType === "extract") {
                AppDetailControl.extractApp(pkg, page.batchActionTargetDir)
            }

            page.batchIndex++
        }
    }

    // Batch uninstall state machine
    function startBatchUninstall() {
        var list = getSelectedList()
        if (list.length === 0) return
        batchUninstallConfirmPopup.close()

        page.uninstallQueue = list
        page.uninstallTotal = list.length
        page.uninstallIndex = 0
        page.uninstallCurrentPkg = ""
        page.uninstallCurrentName = ""
        page.uninstallSuccessList = []
        page.uninstallFailList = []
        page.lastReportedResult = ""
        page.lastReportedReason = ""
        page.uninstallStepTimeout = 0
        page.uninstallState = "dispatch"
        page.uninstallRunning = true

        batchUninstallProgressPopup.open()
        uninstallTimer.restart()
    }

    // Batch restore state machine
    function startBatchRestore() {
        var list = getSelectedList()
        if (list.length === 0) return
        batchRestoreConfirmPopup.close()

        page.restoreQueue = list
        page.restoreTotal = list.length
        page.restoreIndex = 0
        page.restoreCurrentPkg = ""
        page.restoreCurrentName = ""
        page.restoreSuccessList = []
        page.restoreFailList = []
        page.lastReportedResult = ""
        page.lastReportedReason = ""
        page.restoreStepTimeout = 0
        page.restoreState = "dispatch"
        page.restoreRunning = true

        batchRestoreProgressPopup.open()
        restoreTimer.restart()
    }

    Timer {
        id: restoreTimer
        interval: 180
        repeat: true
        onTriggered: {
            if (!page.restoreRunning) {
                stop()
                return
            }

            if (page.restoreState === "dispatch") {
                if (page.restoreIndex >= page.restoreQueue.length) {
                    page.restoreRunning = false
                    stop()
                    batchRestoreProgressPopup.close()
                    page.deselectAll()
                    AppDetailControl.requestUpdateSoftList()
                    batchRestoreSummaryPopup.open()
                    return
                }

                if (AppDetailControl.busy) return

                var currentItem = page.restoreQueue[page.restoreIndex]
                page.restoreCurrentPkg = currentItem.packageName
                page.restoreCurrentName = currentItem.appName || currentItem.packageName
                page.lastReportedResult = ""
                page.lastReportedReason = ""
                page.restoreStepTimeout = 0
                page.restoreState = "waiting"

                AppDetailControl.restoreApp(currentItem.packageName)
                return
            }

            if (page.restoreState === "waiting") {
                page.restoreStepTimeout++

                var stepFinished = false
                if (page.lastReportedResult.length > 0 && !AppDetailControl.busy) {
                    stepFinished = true
                } else if (page.restoreStepTimeout > 3 && !AppDetailControl.busy) {
                    stepFinished = true
                } else if (page.restoreStepTimeout > 65) {
                    // Timeout after ~12s
                    stepFinished = true
                    if (page.lastReportedResult.length === 0) {
                        page.lastReportedResult = "fail"
                        page.lastReportedReason = "操作逾時"
                    }
                }

                if (stepFinished) {
                    if (page.lastReportedResult === "fail") {
                        page.restoreFailList.push({
                            packageName: page.restoreCurrentPkg,
                            appName: page.restoreCurrentName,
                            reason: page.lastReportedReason || "復原失敗"
                        })
                    } else {
                        page.restoreSuccessList.push({
                            packageName: page.restoreCurrentPkg,
                            appName: page.restoreCurrentName
                        })
                    }

                    page.restoreIndex++
                    page.restoreState = "dispatch"
                    page.restoreStepTimeout = 0
                }
            }
        }
    }

    function cancelBatchRestore() {
        page.restoreRunning = false
        restoreTimer.stop()
        for (var i = page.restoreIndex; i < page.restoreQueue.length; i++) {
            var item = page.restoreQueue[i]
            page.restoreFailList.push({
                packageName: item.packageName,
                appName: item.appName || item.packageName,
                reason: "使用者取消操作"
            })
        }
        batchRestoreProgressPopup.close()
        page.deselectAll()
        AppDetailControl.requestUpdateSoftList()
        batchRestoreSummaryPopup.open()
    }

    Timer {
        id: uninstallTimer
        interval: 180
        repeat: true
        onTriggered: {
            if (!page.uninstallRunning) {
                stop()
                return
            }

            if (page.uninstallState === "dispatch") {
                if (page.uninstallIndex >= page.uninstallQueue.length) {
                    page.uninstallRunning = false
                    stop()
                    batchUninstallProgressPopup.close()
                    page.deselectAll()
                    AppDetailControl.requestUpdateSoftList()
                    batchUninstallSummaryPopup.open()
                    return
                }

                if (AppDetailControl.busy) return

                var currentItem = page.uninstallQueue[page.uninstallIndex]
                page.uninstallCurrentPkg = currentItem.packageName
                page.uninstallCurrentName = currentItem.appName || currentItem.packageName
                page.lastReportedResult = ""
                page.lastReportedReason = ""
                page.uninstallStepTimeout = 0
                page.uninstallState = "waiting"

                AppDetailControl.uninstallApp(currentItem.packageName)
                return
            }

            if (page.uninstallState === "waiting") {
                page.uninstallStepTimeout++

                var stepFinished = false
                if (page.lastReportedResult.length > 0 && !AppDetailControl.busy) {
                    stepFinished = true
                } else if (page.uninstallStepTimeout > 3 && !AppDetailControl.busy) {
                    stepFinished = true
                } else if (page.uninstallStepTimeout > 65) {
                    // Timeout after ~12s
                    stepFinished = true
                    if (page.lastReportedResult.length === 0) {
                        page.lastReportedResult = "fail"
                        page.lastReportedReason = "操作逾時"
                    }
                }

                if (stepFinished) {
                    if (page.lastReportedResult === "fail") {
                        page.uninstallFailList.push({
                            packageName: page.uninstallCurrentPkg,
                            appName: page.uninstallCurrentName,
                            reason: page.lastReportedReason || "解除安裝失敗"
                        })
                    } else {
                        page.uninstallSuccessList.push({
                            packageName: page.uninstallCurrentPkg,
                            appName: page.uninstallCurrentName
                        })
                    }

                    page.uninstallIndex++
                    page.uninstallState = "dispatch"
                    page.uninstallStepTimeout = 0
                }
            }
        }
    }

    function cancelBatchUninstall() {
        page.uninstallRunning = false
        uninstallTimer.stop()
        for (var i = page.uninstallIndex; i < page.uninstallQueue.length; i++) {
            var item = page.uninstallQueue[i]
            page.uninstallFailList.push({
                packageName: item.packageName,
                appName: item.appName || item.packageName,
                reason: "使用者取消操作"
            })
        }
        batchUninstallProgressPopup.close()
        page.deselectAll()
        AppDetailControl.requestUpdateSoftList()
        batchUninstallSummaryPopup.open()
    }

    // Drag-and-drop support for installing APKs directly onto AppPage
    DropArea {
        anchors.fill: parent
        onEntered: function(drag) {
            if (drag.hasUrls) drag.acceptProposedAction()
        }
        onDropped: function(drop) {
            if (!page.device) {
                NotificationController.send("安裝失敗", "請先連線裝置", NotificationController.Warning)
                return
            }
            if (!drop.hasUrls || drop.urls.length === 0) return
            var path = page.localPath(drop.urls[0])
            if (path && String(path).toLowerCase().endsWith(".apk")) {
                page.installApk(path)
                drop.acceptProposedAction()
            } else {
                NotificationController.send("無法安裝", "請拖入有效 APK 檔案", NotificationController.Warning)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ======================== 1. 頂部工具列 ========================
        Panel {
            Layout.fillWidth: true
            Layout.preferredHeight: 88

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                // 第一行：頁面標題/裝置、搜尋框、分類選取器、重新整理與安裝
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    RowLayout {
                        spacing: 8
                        Layout.preferredWidth: 200

                        Rectangle {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            radius: 8
                            color: Qt.rgba(0.06, 0.48, 0.42, FluTheme.dark ? 0.28 : 0.14)
                            border.width: 1
                            border.color: Qt.rgba(0.06, 0.48, 0.42, 0.35)

                            FluIcon {
                                anchors.centerIn: parent
                                iconSource: FluentIcons.Apps
                                iconSize: 18
                                iconColor: "#0f7b6c"
                            }
                        }

                        ColumnLayout {
                            spacing: 0
                            FluText {
                                text: "應用程式管理"
                                font: FluTextStyle.BodyStrong
                            }
                            FluText {
                                text: page.device ? (page.device.model || page.device.code || "Android 裝置") : "未連線裝置"
                                font: FluTextStyle.Caption
                                color: FluTheme.fontSecondaryColor
                                elide: Text.ElideRight
                                Layout.maximumWidth: 150
                            }
                        }
                    }

                    // 搜尋框
                    FluTextBox {
                        id: searchBox
                        Layout.preferredWidth: 240
                        Layout.preferredHeight: 32
                        placeholderText: "搜尋應用程式名稱或套件名稱……"
                        iconSource: FluentIcons.Search
                        cleanEnabled: true
                        onTextChanged: page.searchQuery = text
                    }

                    // 篩選器：[全部] [第三方] [系統] [已停用] [已解除安裝]
                    Rectangle {
                        Layout.preferredHeight: 32
                        Layout.preferredWidth: 350
                        radius: 7
                        color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)
                        border.width: 1
                        border.color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 2
                            spacing: 2

                            // 2: 全部
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 5
                                color: AppDetailControl.softListType === 2
                                       ? Qt.rgba(0.06, 0.48, 0.42, FluTheme.dark ? 0.45 : 0.25)
                                       : (allMouse.containsMouse ? (FluTheme.dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.05)) : "transparent")
                                border.width: AppDetailControl.softListType === 2 ? 1 : 0
                                border.color: "#0f7b6c"

                                FluText {
                                    anchors.centerIn: parent
                                    text: "全部"
                                    font: FluTextStyle.Caption
                                    color: AppDetailControl.softListType === 2 ? (FluTheme.dark ? "#5eead4" : "#0f7b6c") : FluTheme.fontPrimaryColor
                                }
                                MouseArea {
                                    id: allMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { AppDetailControl.softListType = 2 }
                                }
                            }

                            // 0: 第三方
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 5
                                color: AppDetailControl.softListType === 0
                                       ? Qt.rgba(0.06, 0.48, 0.42, FluTheme.dark ? 0.45 : 0.25)
                                       : (thirdMouse.containsMouse ? (FluTheme.dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.05)) : "transparent")
                                border.width: AppDetailControl.softListType === 0 ? 1 : 0
                                border.color: "#0f7b6c"

                                FluText {
                                    anchors.centerIn: parent
                                    text: "第三方"
                                    font: FluTextStyle.Caption
                                    color: AppDetailControl.softListType === 0 ? (FluTheme.dark ? "#5eead4" : "#0f7b6c") : FluTheme.fontPrimaryColor
                                }
                                MouseArea {
                                    id: thirdMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { AppDetailControl.softListType = 0 }
                                }
                            }

                            // 1: 系統
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 5
                                color: AppDetailControl.softListType === 1
                                       ? Qt.rgba(0.06, 0.48, 0.42, FluTheme.dark ? 0.45 : 0.25)
                                       : (sysMouse.containsMouse ? (FluTheme.dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.05)) : "transparent")
                                border.width: AppDetailControl.softListType === 1 ? 1 : 0
                                border.color: "#0f7b6c"

                                FluText {
                                    anchors.centerIn: parent
                                    text: "系統"
                                    font: FluTextStyle.Caption
                                    color: AppDetailControl.softListType === 1 ? (FluTheme.dark ? "#5eead4" : "#0f7b6c") : FluTheme.fontPrimaryColor
                                }
                                MouseArea {
                                    id: sysMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { AppDetailControl.softListType = 1 }
                                }
                            }

                            // 3: 已停用
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 5
                                color: AppDetailControl.softListType === 3
                                       ? Qt.rgba(0.06, 0.48, 0.42, FluTheme.dark ? 0.45 : 0.25)
                                       : (disabledMouse.containsMouse ? (FluTheme.dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.05)) : "transparent")
                                border.width: AppDetailControl.softListType === 3 ? 1 : 0
                                border.color: "#0f7b6c"

                                FluText {
                                    anchors.centerIn: parent
                                    text: "已停用"
                                    font: FluTextStyle.Caption
                                    color: AppDetailControl.softListType === 3 ? (FluTheme.dark ? "#5eead4" : "#0f7b6c") : FluTheme.fontPrimaryColor
                                }
                                MouseArea {
                                    id: disabledMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { AppDetailControl.softListType = 3 }
                                }
                            }

                            // 4: 已解除安裝
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 5
                                color: AppDetailControl.softListType === 4
                                       ? Qt.rgba(0.06, 0.48, 0.42, FluTheme.dark ? 0.45 : 0.25)
                                       : (uninstalledMouse.containsMouse ? (FluTheme.dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.05)) : "transparent")
                                border.width: AppDetailControl.softListType === 4 ? 1 : 0
                                border.color: "#0f7b6c"

                                FluText {
                                    anchors.centerIn: parent
                                    text: "已解除安裝"
                                    font: FluTextStyle.Caption
                                    color: AppDetailControl.softListType === 4 ? (FluTheme.dark ? "#5eead4" : "#0f7b6c") : FluTheme.fontPrimaryColor
                                }
                                MouseArea {
                                    id: uninstalledMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { AppDetailControl.softListType = 4 }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // [重新整理] 與 [安裝 APK]
                    ActionButton {
                        label: AppDetailControl.busy ? "處理中" : "重新整理"
                        icon: FluentIcons.Sync
                        dense: true
                        Layout.preferredWidth: 80
                        enabled: !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning
                        onPressed: AppDetailControl.requestUpdateSoftList()
                    }

                    ActionButton {
                        label: "安裝 APK"
                        icon: FluentIcons.Add
                        dense: true
                        accent: "#0f7b6c"
                        Layout.preferredWidth: 102
                        enabled: !!page.device && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning
                        onPressed: apkDialog.open()
                    }
                }

                // 第二行：多選控制組與統計提示
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ActionButton {
                        label: "全選"
                        dense: true
                        Layout.preferredWidth: 64
                        enabled: appListView.count > 0 && !page.uninstallRunning && !page.restoreRunning
                        onPressed: page.selectAll()
                    }

                    ActionButton {
                        label: "取消全選"
                        dense: true
                        Layout.preferredWidth: 80
                        enabled: page.selectedCount > 0 && !page.uninstallRunning && !page.restoreRunning
                        onPressed: page.deselectAll()
                    }

                    ActionButton {
                        label: "反向選取"
                        dense: true
                        Layout.preferredWidth: 76
                        enabled: appListView.count > 0 && !page.uninstallRunning && !page.restoreRunning
                        onPressed: page.invertSelection()
                    }

                    Rectangle {
                        Layout.preferredHeight: 18
                        Layout.preferredWidth: 1
                        color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.15)
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                    }

                    FluText {
                        text: "已選取 " + page.selectedCount + " 個應用程式"
                        font: FluTextStyle.Caption
                        color: page.selectedCount > 0 ? FluTheme.primaryColor : FluTheme.fontSecondaryColor
                    }

                    FluText {
                        text: "（清單共 " + appListView.count + " 個）" + (page.searchQuery.length > 0 ? " [篩選中]" : "")
                        font: FluTextStyle.Caption
                        color: FluTheme.fontSecondaryColor
                    }

                    Item { Layout.fillWidth: true }

                    FluText {
                        text: AppDetailControl.busy ? "ADB 任務執行中..." : ""
                        font: FluTextStyle.Caption
                        color: "#ca8a04"
                        visible: AppDetailControl.busy
                    }
                }
            }
        }

        // ======================== 2. 主體區：清單 + 詳情 ========================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // 左側：主應用程式清單 Panel
            Panel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    // 表頭
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 5
                        color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.025)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            FluText {
                                text: "選取"
                                font: FluTextStyle.Caption
                                color: FluTheme.fontSecondaryColor
                                Layout.preferredWidth: 32
                            }
                            FluText {
                                text: "應用程式資訊"
                                font: FluTextStyle.Caption
                                color: FluTheme.fontSecondaryColor
                                Layout.fillWidth: true
                            }
                            FluText {
                                text: "版本"
                                font: FluTextStyle.Caption
                                color: FluTheme.fontSecondaryColor
                                Layout.preferredWidth: 70
                                horizontalAlignment: Text.AlignRight
                            }
                            FluText {
                                text: "類型"
                                font: FluTextStyle.Caption
                                color: FluTheme.fontSecondaryColor
                                Layout.preferredWidth: 54
                                horizontalAlignment: Text.AlignCenter
                            }
                        }
                    }

                    // ListView
                    ListView {
                        id: appListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: SoftListModel
                        spacing: 0

                        ScrollBar.vertical: FluScrollBar {}

                        delegate: Item {
                            id: rowDelegate
                            width: ListView.view ? ListView.view.width : 0

                            readonly property bool isMatched: {
                                var q = page.searchQuery.trim().toLowerCase()
                                if (q.length === 0) return true
                                var nameStr = (model.appName || "").toLowerCase()
                                var pkgStr = (model.packageName || "").toLowerCase()
                                return nameStr.indexOf(q) !== -1 || pkgStr.indexOf(q) !== -1
                            }

                            visible: isMatched
                            height: isMatched ? 50 : 0
                            clip: true

                            Component.onCompleted: {
                                if (model.packageName) {
                                    page.registerApp({
                                        packageName: model.packageName,
                                        appName: model.appName || model.packageName,
                                        isSystemApp: !!model.isSystemApp,
                                        isEnabled: model.isEnabled !== undefined ? !!model.isEnabled : true,
                                        installedForCurrentUser: model.installedForCurrentUser !== undefined ? !!model.installedForCurrentUser : true
                                    })
                                }
                            }

                            // 延遲載入圖示機制
                            Timer {
                                interval: 100 + Math.min(index, 10) * 50
                                running: !model.icon && (model.packageName || "").length > 0
                                repeat: false
                                onTriggered: AppDetailControl.requestLoadIcon(model.packageName || "")
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.bottomMargin: 3
                                radius: 6
                                color: page.selectedPackage === model.packageName
                                       ? Qt.rgba(0.06, 0.48, 0.42, FluTheme.dark ? 0.32 : 0.16)
                                       : (rowMouse.containsMouse ? (FluTheme.dark ? Qt.rgba(1, 1, 1, 0.055) : Qt.rgba(0, 0, 0, 0.035)) : "transparent")
                                border.width: page.selectedPackage === model.packageName ? 1 : 0
                                border.color: "#0f7b6c"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    // 多選 CheckBox
                                    FluCheckBox {
                                        id: rowCheckBox
                                        text: ""
                                        Layout.preferredWidth: 26
                                        checked: page.isSelected(model.packageName)
                                        clickListener: function() {
                                            page.toggleSelect(model.packageName, model.appName || model.packageName, !!model.isSystemApp, model.isEnabled, model.installedForCurrentUser)
                                        }
                                    }

                                    // App 圖示
                                    AppIconBox {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        source: model.icon || ""
                                        title: model.appName || model.packageName || ""
                                        accent: model.installedForCurrentUser === false ? "#d83b01" : (model.isEnabled === false ? "#ca8a04" : (model.isSystemApp ? "#64748b" : "#0f7b6c"))
                                    }

                                    // App 名稱與套件名稱
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 0

                                        FluText {
                                            text: model.appName || model.packageName || "?"
                                            font: FluTextStyle.Body
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            elide: Text.ElideRight
                                        }

                                        FluText {
                                            text: model.packageName || ""
                                            font: FluTextStyle.Caption
                                            color: FluTheme.fontSecondaryColor
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            elide: Text.ElideMiddle
                                        }
                                    }

                                    // 版本
                                    FluText {
                                        text: model.versionName || "--"
                                        font: FluTextStyle.Caption
                                        color: FluTheme.fontSecondaryColor
                                        Layout.preferredWidth: 70
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignRight
                                    }

                                    // 類別膠囊
                                    Rectangle {
                                        Layout.preferredWidth: 54
                                        Layout.preferredHeight: 22
                                        radius: 4
                                        color: {
                                            if (model.installedForCurrentUser === false) {
                                                return FluTheme.dark ? Qt.rgba(0.85, 0.23, 0.0, 0.25) : Qt.rgba(0.85, 0.23, 0.0, 0.14)
                                            } else if (model.isEnabled === false) {
                                                return FluTheme.dark ? Qt.rgba(0.79, 0.54, 0.02, 0.25) : Qt.rgba(0.79, 0.54, 0.02, 0.14)
                                            } else if (model.isSystemApp) {
                                                return FluTheme.dark ? Qt.rgba(0.4, 0.45, 0.55, 0.22) : Qt.rgba(0.4, 0.45, 0.55, 0.14)
                                            } else {
                                                return FluTheme.dark ? Qt.rgba(0.06, 0.48, 0.42, 0.25) : Qt.rgba(0.06, 0.48, 0.42, 0.14)
                                            }
                                        }
                                        border.width: 1
                                        border.color: {
                                            if (model.installedForCurrentUser === false) {
                                                return Qt.rgba(0.85, 0.23, 0.0, 0.4)
                                            } else if (model.isEnabled === false) {
                                                return Qt.rgba(0.79, 0.54, 0.02, 0.4)
                                            } else if (model.isSystemApp) {
                                                return Qt.rgba(0.4, 0.45, 0.55, 0.4)
                                            } else {
                                                return Qt.rgba(0.06, 0.48, 0.42, 0.4)
                                            }
                                        }

                                        FluText {
                                            anchors.centerIn: parent
                                            text: {
                                                if (model.installedForCurrentUser === false) return "已解除安裝"
                                                if (model.isEnabled === false) return "已停用"
                                                return model.isSystemApp ? "系統" : "第三方"
                                            }
                                            font: FluTextStyle.Caption
                                            color: {
                                                if (model.installedForCurrentUser === false) return "#ef4444"
                                                if (model.isEnabled === false) return "#eab308"
                                                return model.isSystemApp ? "#94a3b8" : "#10b981"
                                            }
                                        }
                                    }
                                }

                                // 只有點擊非 Checkbox 區域才觸發個別檢視詳情
                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    anchors.leftMargin: 36 // 避免攔截 CheckBox
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        page.selectAppForDetail(
                                            model.packageName,
                                            model.appName,
                                            model.versionName,
                                            model.icon,
                                            model.isSystemApp,
                                            model.versionCode,
                                            model.firstInstallTime,
                                            model.lastUpdateTime,
                                            model.minSdk,
                                            model.targetSdk,
                                            model.path,
                                            model.appId,
                                            model.isEnabled,
                                            model.installedForCurrentUser
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 右側：應用程式詳細資訊面板 Panel
            Panel {
                Layout.preferredWidth: 330
                Layout.minimumWidth: 300
                Layout.maximumWidth: 360
                Layout.fillHeight: true

                // 空狀態：未選取應用程式
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    visible: page.selectedPackage.length === 0
                    width: parent.width - 40

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 54
                        Layout.preferredHeight: 54
                        radius: 27
                        color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)
                        FluIcon {
                            anchors.centerIn: parent
                            iconSource: FluentIcons.Info
                            iconSize: 26
                            iconColor: FluTheme.fontSecondaryColor
                        }
                    }

                    FluText {
                        Layout.alignment: Qt.AlignHCenter
                        text: "選取應用程式檢視詳細資訊"
                        font: FluTextStyle.BodyStrong
                    }

                    FluText {
                        Layout.fillWidth: true
                        text: "在左側清單中按一下任意應用程式，即可檢視詳細屬性並執行啟動、停止、擷取與解除安裝等個別操作。"
                        font: FluTextStyle.Caption
                        color: FluTheme.fontSecondaryColor
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // 詳細內容
                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 12
                    contentWidth: availableWidth
                    visible: page.selectedPackage.length > 0
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 12

                        // 頂部：圖示 + 標題 + 套件名稱
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            AppIconBox {
                                Layout.preferredWidth: 54
                                Layout.preferredHeight: 54
                                source: page.selectedAppIcon
                                title: page.selectedAppName || page.selectedPackage
                                accent: page.selectedIsSystem ? "#64748b" : "#0f7b6c"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 2

                                FluText {
                                    text: page.selectedAppName || page.selectedPackage
                                    font: FluTextStyle.BodyStrong
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                FluText {
                                    text: page.selectedPackage
                                    font: FluTextStyle.Caption
                                    color: FluTheme.fontSecondaryColor
                                    Layout.fillWidth: true
                                    elide: Text.ElideMiddle
                                }

                                RowLayout {
                                    spacing: 6
                                    Rectangle {
                                        Layout.preferredWidth: {
                                            if (page.selectedInstalledForCurrentUser === false) return 46
                                            if (page.selectedIsEnabled === false) return 46
                                            return page.selectedIsSystem ? 58 : 46
                                        }
                                        Layout.preferredHeight: 18
                                        radius: 4
                                        color: {
                                            if (page.selectedInstalledForCurrentUser === false) {
                                                return FluTheme.dark ? Qt.rgba(0.85, 0.23, 0.0, 0.25) : Qt.rgba(0.85, 0.23, 0.0, 0.14)
                                            } else if (page.selectedIsEnabled === false) {
                                                return FluTheme.dark ? Qt.rgba(0.79, 0.54, 0.02, 0.25) : Qt.rgba(0.79, 0.54, 0.02, 0.14)
                                            } else if (page.selectedIsSystem) {
                                                return FluTheme.dark ? Qt.rgba(0.4, 0.45, 0.55, 0.22) : Qt.rgba(0.4, 0.45, 0.55, 0.14)
                                            } else {
                                                return FluTheme.dark ? Qt.rgba(0.06, 0.48, 0.42, 0.25) : Qt.rgba(0.06, 0.48, 0.42, 0.14)
                                            }
                                        }
                                        border.width: 1
                                        border.color: {
                                            if (page.selectedInstalledForCurrentUser === false) {
                                                return Qt.rgba(0.85, 0.23, 0.0, 0.4)
                                            } else if (page.selectedIsEnabled === false) {
                                                return Qt.rgba(0.79, 0.54, 0.02, 0.4)
                                            } else if (page.selectedIsSystem) {
                                                return Qt.rgba(0.4, 0.45, 0.55, 0.4)
                                            } else {
                                                return Qt.rgba(0.06, 0.48, 0.42, 0.4)
                                            }
                                        }
                                        FluText {
                                            anchors.centerIn: parent
                                            text: {
                                                if (page.selectedInstalledForCurrentUser === false) return "已解除安裝"
                                                if (page.selectedIsEnabled === false) return "已停用"
                                                return page.selectedIsSystem ? "系統應用程式" : "第三方"
                                            }
                                            font: FluTextStyle.Caption
                                            color: {
                                                if (page.selectedInstalledForCurrentUser === false) return "#ef4444"
                                                if (page.selectedIsEnabled === false) return "#eab308"
                                                return page.selectedIsSystem ? "#94a3b8" : "#10b981"
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 個別操作按鈕組 (GridLayout 3x2)
                        FluText {
                            text: "個別操作"
                            font: FluTextStyle.Caption
                            color: FluTheme.fontSecondaryColor
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3
                            columnSpacing: 6
                            rowSpacing: 6

                            // 復原 (僅針對已解除安裝應用程式)
                            ActionButton {
                                label: "復原"
                                icon: FluentIcons.UpdateRestore
                                dense: true
                                Layout.fillWidth: true
                                accent: "#0f7b6c"
                                visible: page.selectedInstalledForCurrentUser === false
                                enabled: !!page.selectedPackage && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning
                                onPressed: AppDetailControl.restoreApp(page.selectedPackage)
                            }

                            // 啟用 (僅針對已停用應用程式)
                            ActionButton {
                                label: "啟用"
                                icon: FluentIcons.Play
                                dense: true
                                Layout.fillWidth: true
                                accent: "#0f7b6c"
                                visible: page.selectedIsEnabled === false && page.selectedInstalledForCurrentUser !== false
                                enabled: !!page.selectedPackage && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning
                                onPressed: AppDetailControl.enableApp(page.selectedPackage)
                            }

                            ActionButton {
                                label: "啟動"
                                icon: FluentIcons.Play
                                dense: true
                                Layout.fillWidth: true
                                enabled: !!page.selectedPackage && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && page.selectedInstalledForCurrentUser !== false && page.selectedIsEnabled !== false
                                onPressed: AppDetailControl.startApp(page.selectedPackage)
                            }

                            ActionButton {
                                label: "停止"
                                icon: FluentIcons.Stop
                                dense: true
                                Layout.fillWidth: true
                                enabled: !!page.selectedPackage && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && page.selectedInstalledForCurrentUser !== false
                                onPressed: AppDetailControl.stopApp(page.selectedPackage)
                            }

                            ActionButton {
                                label: "擷取"
                                icon: FluentIcons.Download
                                dense: true
                                Layout.fillWidth: true
                                enabled: !!page.selectedPackage && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning
                                onPressed: singleExtractDialog.open()
                            }

                            ActionButton {
                                label: "凍結"
                                icon: FluentIcons.Lock
                                dense: true
                                Layout.fillWidth: true
                                enabled: !!page.selectedPackage && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && page.selectedInstalledForCurrentUser !== false
                                onPressed: AppDetailControl.freezeApp(page.selectedPackage)
                            }

                            ActionButton {
                                label: "清除資料"
                                dense: true
                                Layout.fillWidth: true
                                accent: "#ca8a04"
                                enabled: !!page.selectedPackage && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && page.selectedInstalledForCurrentUser !== false
                                onPressed: AppDetailControl.clearData(page.selectedPackage)
                            }

                            ActionButton {
                                label: "解除安裝"
                                icon: FluentIcons.Delete
                                dense: true
                                Layout.fillWidth: true
                                accent: "#d83b01"
                                enabled: !!page.selectedPackage && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && page.selectedInstalledForCurrentUser !== false
                                onPressed: AppDetailControl.uninstallApp(page.selectedPackage)
                            }
                        }

                        // 詳細屬性 Tiles
                        FluText {
                            text: "應用程式詳情"
                            font: FluTextStyle.Caption
                            color: FluTheme.fontSecondaryColor
                            Layout.topMargin: 4
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 1
                            rowSpacing: 6

                            CompactTile {
                                label: "版本名稱"
                                value: page.selectedAppVersion || "--"
                                accent: "#2563eb"
                            }

                            CompactTile {
                                label: "版本代碼 (Code)"
                                value: (AppDetailControl.versionCode > 0 ? String(AppDetailControl.versionCode) : page.selectedAppVersionCode) || "--"
                                accent: "#2563eb"
                            }

                            CompactTile {
                                label: "首次安裝"
                                value: AppDetailControl.installDate || page.selectedInstallDate || "--"
                                accent: "#64748b"
                            }

                            CompactTile {
                                label: "最後更新"
                                value: page.selectedLastUpdate || "--"
                                accent: "#64748b"
                            }

                            CompactTile {
                                label: "SDK 範圍"
                                value: ((AppDetailControl.minSdk || page.selectedMinSdk || "--") + " -> " + (AppDetailControl.targetSdk || page.selectedTargetSdk || "--"))
                                accent: "#7c3aed"
                            }

                            CompactTile {
                                label: "應用程式 UID"
                                value: page.selectedAppId || "--"
                                accent: "#ca8a04"
                            }

                            CompactTile {
                                label: "APK 路徑"
                                value: page.selectedAppPath || "--"
                                accent: "#0f7b6c"
                            }
                        }
                    }
                }
            }
        }

        // ======================== 3. 底部批次操作工具列 ========================
        Panel {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                // 左側選取狀態
                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: 13
                    color: page.selectedCount > 0 ? Qt.rgba(0.06, 0.48, 0.42, 0.25) : (FluTheme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04))
                    FluIcon {
                        anchors.centerIn: parent
                        iconSource: FluentIcons.CheckMark
                        iconSize: 14
                        iconColor: page.selectedCount > 0 ? "#0f7b6c" : FluTheme.fontSecondaryColor
                    }
                }

                FluText {
                    text: page.selectedCount > 0 ? ("已選取 " + page.selectedCount + " 個應用程式") : "未選取應用程式（勾選左側清單以啟用批次操作）"
                    font: FluTextStyle.Body
                    color: page.selectedCount > 0 ? FluTheme.primaryColor : FluTheme.fontSecondaryColor
                }

                ActionButton {
                    label: "清除選取"
                    dense: true
                    Layout.preferredWidth: 76
                    visible: page.selectedCount > 0 && !page.uninstallRunning && !page.restoreRunning
                    onPressed: page.deselectAll()
                }

                Item { Layout.fillWidth: true }

                // 批次操作按鈕
                ActionButton {
                    label: "批次啟動"
                    icon: FluentIcons.Play
                    dense: true
                    Layout.preferredWidth: 88
                    enabled: page.selectedCount > 0 && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && !page.batchRunning
                    onPressed: page.startBatchAction("start")
                }

                ActionButton {
                    label: "批次停止"
                    icon: FluentIcons.Stop
                    dense: true
                    Layout.preferredWidth: 88
                    enabled: page.selectedCount > 0 && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && !page.batchRunning
                    onPressed: page.startBatchAction("stop")
                }

                ActionButton {
                    label: "批次擷取"
                    icon: FluentIcons.Download
                    dense: true
                    Layout.preferredWidth: 92
                    enabled: page.selectedCount > 0 && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && !page.batchRunning
                    onPressed: batchExtractDialog.open()
                }

                ActionButton {
                    label: "批次凍結"
                    icon: FluentIcons.Lock
                    dense: true
                    Layout.preferredWidth: 88
                    enabled: page.selectedCount > 0 && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && !page.batchRunning
                    onPressed: page.startBatchAction("freeze")
                }

                ActionButton {
                    label: "批次啟用"
                    icon: FluentIcons.Play
                    dense: true
                    Layout.preferredWidth: 88
                    enabled: page.selectedCount > 0 && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && !page.batchRunning
                    onPressed: page.startBatchAction("enable")
                }

                ActionButton {
                    label: "批次復原"
                    icon: FluentIcons.UpdateRestore
                    dense: true
                    Layout.preferredWidth: 88
                    accent: "#0f7b6c"
                    enabled: page.selectedCount > 0 && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && !page.batchRunning
                    onPressed: batchRestoreConfirmPopup.open()
                }

                ActionButton {
                    label: "清除資料"
                    dense: true
                    Layout.preferredWidth: 80
                    accent: "#ca8a04"
                    enabled: page.selectedCount > 0 && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && !page.batchRunning
                    onPressed: confirmBatchClearDataPopup.open()
                }

                ActionButton {
                    label: "批次解除安裝"
                    icon: FluentIcons.Delete
                    dense: true
                    Layout.preferredWidth: 104
                    accent: "#d83b01"
                    enabled: page.selectedCount > 0 && !AppDetailControl.busy && !page.uninstallRunning && !page.restoreRunning && !page.batchRunning
                    onPressed: batchUninstallConfirmPopup.open()
                }
            }
        }
    }

    // ======================== 4. 對話框與彈出層 ========================

    // 1. 安裝 APK 彈窗
    FileDialog {
        id: apkDialog
        title: "選取 APK"
        nameFilters: ["APK files (*.apk)"]
        onAccepted: AppDetailControl.installApp(page.localPath(currentFile))
    }

    // 2. 單個擷取目錄彈窗
    FolderDialog {
        id: singleExtractDialog
        title: "選取 APK 擷取儲存目錄"
        onAccepted: AppDetailControl.extractApp(page.selectedPackage, page.localPath(selectedFolder))
    }

    // 3. 批次擷取目錄彈窗
    FolderDialog {
        id: batchExtractDialog
        title: "選取批次 APK 擷取儲存目錄"
        onAccepted: page.startBatchAction("extract", page.localPath(selectedFolder))
    }

    // 4. 批次清除資料確認彈窗
    FluPopup {
        id: confirmBatchClearDataPopup
        width: 420
        height: 200
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                spacing: 10
                FluIcon {
                    iconSource: FluentIcons.Warning
                    iconSize: 22
                    iconColor: "#ca8a04"
                }
                FluText {
                    text: "清除應用程式資料確認"
                    font: FluTextStyle.BodyStrong
                }
            }

            FluText {
                text: "確定要清除選取的 " + page.selectedCount + " 個應用程式的全部資料與快取嗎？此操作無法復原。"
                font: FluTextStyle.Body
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Item { Layout.fillWidth: true }
                FluButton {
                    text: "取消"
                    onClicked: confirmBatchClearDataPopup.close()
                }
                FluFilledButton {
                    text: "確認清除"
                    normalColor: "#ca8a04"
                    onClicked: {
                        confirmBatchClearDataPopup.close()
                        page.startBatchAction("clearData")
                    }
                }
            }
        }
    }

    // 5. 批次解除安裝確認 Dialog (重點功能)
    FluPopup {
        id: batchUninstallConfirmPopup
        width: 480
        height: Math.min(520, page.height - 40)
        modal: true
        closePolicy: Popup.CloseOnEscape

        readonly property var uninstallList: page.getSelectedList()
        readonly property bool hasSystemApp: {
            for (var i = 0; i < uninstallList.length; i++) {
                if (uninstallList[i].isSystemApp) return true
            }
            return false
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                spacing: 10
                FluIcon {
                    iconSource: FluentIcons.Delete
                    iconSize: 24
                    iconColor: "#d83b01"
                }
                FluText {
                    text: "批次解除安裝確認"
                    font: FluTextStyle.Title
                }
            }

            // 包含系統應用程式的警告
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: 6
                visible: batchUninstallConfirmPopup.hasSystemApp
                color: Qt.rgba(0.85, 0.23, 0.0, FluTheme.dark ? 0.25 : 0.12)
                border.width: 1
                border.color: Qt.rgba(0.85, 0.23, 0.0, 0.4)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 8
                    FluIcon {
                        iconSource: FluentIcons.Warning
                        iconSize: 16
                        iconColor: "#d83b01"
                    }
                    FluText {
                        text: "警告：選取的應用程式中包含系統應用程式，解除安裝可能導致系統異常！"
                        font: FluTextStyle.Caption
                        color: "#ef4444"
                        Layout.fillWidth: true
                    }
                }
            }

            FluText {
                text: "確定要解除安裝以下選取的 " + batchUninstallConfirmPopup.uninstallList.length + " 個應用程式嗎？此操作無法復原。"
                font: FluTextStyle.Body
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // 即將解除安裝的應用程式清單
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 6
                color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                border.width: 1
                border.color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)

                ListView {
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    model: batchUninstallConfirmPopup.uninstallList
                    ScrollBar.vertical: FluScrollBar {}

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 38
                        radius: 4
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            FluIcon {
                                iconSource: FluentIcons.AppIconDefault
                                iconSize: 14
                                iconColor: modelData.isSystemApp ? "#ef4444" : "#0f7b6c"
                            }

                            FluText {
                                text: modelData.appName || modelData.packageName
                                font: FluTextStyle.Body
                                elide: Text.ElideRight
                                Layout.preferredWidth: 150
                            }

                            FluText {
                                text: modelData.packageName
                                font: FluTextStyle.Caption
                                color: FluTheme.fontSecondaryColor
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 18
                                radius: 3
                                visible: !!modelData.isSystemApp
                                color: Qt.rgba(0.85, 0.23, 0.0, 0.2)
                                FluText {
                                    anchors.centerIn: parent
                                    text: "系統"
                                    font: FluTextStyle.Caption
                                    color: "#ef4444"
                                }
                            }
                        }
                    }
                }
            }

            // 底部操作按鈕
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item { Layout.fillWidth: true }

                FluButton {
                    text: "取消"
                    onClicked: batchUninstallConfirmPopup.close()
                }

                FluFilledButton {
                    text: "確定解除安裝 (" + batchUninstallConfirmPopup.uninstallList.length + ")"
                    normalColor: "#d83b01"
                    onClicked: page.startBatchUninstall()
                }
            }
        }
    }

    // 6. 批次解除安裝進度 Dialog (重點功能)
    FluPopup {
        id: batchUninstallProgressPopup
        width: 440
        height: 240
        modal: true
        closePolicy: Popup.NoAutoClose

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
                spacing: 12
                FluProgressRing {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    strokeWidth: 3
                }
                ColumnLayout {
                    spacing: 2
                    FluText {
                        text: "正在批次解除安裝應用程式..."
                        font: FluTextStyle.BodyStrong
                    }
                    FluText {
                        text: "請保持裝置連線，ADB 正在依序執行解除安裝任務"
                        font: FluTextStyle.Caption
                        color: FluTheme.fontSecondaryColor
                    }
                }
            }

            // 進度資訊
            RowLayout {
                Layout.fillWidth: true
                FluText {
                    text: "目前進度: " + (page.uninstallIndex + 1) + " / " + Math.max(page.uninstallTotal, 1) + " (" + Math.round((page.uninstallIndex) / Math.max(page.uninstallTotal, 1) * 100) + "%)"
                    font: FluTextStyle.Body
                    Layout.fillWidth: true
                }
            }

            // 進度條
            FluProgressBar {
                Layout.fillWidth: true
                strokeWidth: 6
                indeterminate: false
                value: page.uninstallIndex / Math.max(page.uninstallTotal, 1)
            }

            // 目前正在解除安裝的應用程式
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: 6
                color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    FluText {
                        text: "正在解除安裝: "
                        font: FluTextStyle.Caption
                        color: FluTheme.fontSecondaryColor
                    }
                    FluText {
                        text: (page.uninstallCurrentName || "準備中") + " (" + (page.uninstallCurrentPkg || "-") + ")"
                        font: FluTextStyle.Caption
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                FluButton {
                    text: "中斷剩餘任務"
                    onClicked: page.cancelBatchUninstall()
                }
            }
        }
    }

    // 7. 批次解除安裝完成摘要 Dialog (重點功能)
    FluPopup {
        id: batchUninstallSummaryPopup
        width: 460
        height: Math.min(420, page.height - 40)
        modal: true
        closePolicy: Popup.CloseOnEscape

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            RowLayout {
                spacing: 10
                FluIcon {
                    iconSource: FluentIcons.CheckMark
                    iconSize: 24
                    iconColor: page.uninstallFailList.length === 0 ? "#10b981" : "#ca8a04"
                }
                FluText {
                    text: "批次解除安裝完成"
                    font: FluTextStyle.Title
                }
            }

            // 統計資訊卡片
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: 6
                    color: Qt.rgba(0.06, 0.48, 0.42, FluTheme.dark ? 0.25 : 0.12)
                    border.width: 1
                    border.color: Qt.rgba(0.06, 0.48, 0.42, 0.35)

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        FluText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "成功解除安裝"
                            font: FluTextStyle.Caption
                            color: FluTheme.fontSecondaryColor
                        }
                        FluText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.uninstallSuccessList.length + " 個"
                            font: FluTextStyle.BodyStrong
                            color: "#10b981"
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: 6
                    color: page.uninstallFailList.length > 0
                           ? Qt.rgba(0.85, 0.23, 0.0, FluTheme.dark ? 0.25 : 0.12)
                           : (FluTheme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04))
                    border.width: 1
                    border.color: page.uninstallFailList.length > 0 ? Qt.rgba(0.85, 0.23, 0.0, 0.35) : (FluTheme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10))

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        FluText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "失敗 / 略過"
                            font: FluTextStyle.Caption
                            color: FluTheme.fontSecondaryColor
                        }
                        FluText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.uninstallFailList.length + " 個"
                            font: FluTextStyle.BodyStrong
                            color: page.uninstallFailList.length > 0 ? "#ef4444" : FluTheme.fontSecondaryColor
                        }
                    }
                }
            }

            // 失敗清單（如果有）
            FluText {
                text: "失敗應用程式清單："
                font: FluTextStyle.Caption
                color: FluTheme.fontSecondaryColor
                visible: page.uninstallFailList.length > 0
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 6
                visible: page.uninstallFailList.length > 0
                color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                border.width: 1
                border.color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)

                ListView {
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    model: page.uninstallFailList
                    ScrollBar.vertical: FluScrollBar {}

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 36
                        radius: 4
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            FluText {
                                text: modelData.appName || modelData.packageName
                                font: FluTextStyle.Body
                                elide: Text.ElideRight
                                Layout.preferredWidth: 140
                            }

                            FluText {
                                text: modelData.packageName
                                font: FluTextStyle.Caption
                                color: FluTheme.fontSecondaryColor
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            FluText {
                                text: modelData.reason || "解除安裝失敗"
                                font: FluTextStyle.Caption
                                color: "#ef4444"
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                FluFilledButton {
                    text: "完成"
                    normalColor: "#0f7b6c"
                    onClicked: {
                        batchUninstallSummaryPopup.close()
                    }
                }
            }
        }
    }

    // 8. 批次復原確認 Dialog (重點功能)
    FluPopup {
        id: batchRestoreConfirmPopup
        width: 480
        height: Math.min(520, page.height - 40)
        modal: true
        closePolicy: Popup.CloseOnEscape

        readonly property var restoreList: page.getSelectedList()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                spacing: 10
                FluIcon {
                    iconSource: FluentIcons.UpdateRestore
                    iconSize: 24
                    iconColor: "#0f7b6c"
                }
                FluText {
                    text: "批次復原確認"
                    font: FluTextStyle.Title
                }
            }

            FluText {
                text: "確定要復原以下選取的 " + batchRestoreConfirmPopup.restoreList.length + " 個應用程式嗎？"
                font: FluTextStyle.Body
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // 即將復原的應用程式清單
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 6
                color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                border.width: 1
                border.color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)

                ListView {
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    model: batchRestoreConfirmPopup.restoreList
                    ScrollBar.vertical: FluScrollBar {}

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 38
                        radius: 4
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            FluIcon {
                                iconSource: FluentIcons.AppIconDefault
                                iconSize: 14
                                iconColor: "#0f7b6c"
                            }

                            FluText {
                                text: modelData.appName || modelData.packageName
                                font: FluTextStyle.Body
                                elide: Text.ElideRight
                                Layout.preferredWidth: 150
                            }

                            FluText {
                                text: modelData.packageName
                                font: FluTextStyle.Caption
                                color: FluTheme.fontSecondaryColor
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.preferredWidth: 46
                                Layout.preferredHeight: 18
                                radius: 3
                                color: Qt.rgba(0.06, 0.48, 0.42, 0.2)
                                FluText {
                                    anchors.centerIn: parent
                                    text: "待復原"
                                    font: FluTextStyle.Caption
                                    color: "#0f7b6c"
                                }
                            }
                        }
                    }
                }
            }

            // 底部操作按鈕
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item { Layout.fillWidth: true }

                FluButton {
                    text: "取消"
                    onClicked: batchRestoreConfirmPopup.close()
                }

                FluFilledButton {
                    text: "確定復原 (" + batchRestoreConfirmPopup.restoreList.length + ")"
                    normalColor: "#0f7b6c"
                    onClicked: page.startBatchRestore()
                }
            }
        }
    }

    // 9. 批次復原進度 Dialog (重點功能)
    FluPopup {
        id: batchRestoreProgressPopup
        width: 440
        height: 240
        modal: true
        closePolicy: Popup.NoAutoClose

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
                spacing: 12
                FluProgressRing {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    strokeWidth: 3
                }
                ColumnLayout {
                    spacing: 2
                    FluText {
                        text: "正在批次復原應用程式..."
                        font: FluTextStyle.BodyStrong
                    }
                    FluText {
                        text: "請保持裝置連線，ADB 正在依序執行復原任務"
                        font: FluTextStyle.Caption
                        color: FluTheme.fontSecondaryColor
                    }
                }
            }

            // 進度資訊
            RowLayout {
                Layout.fillWidth: true
                FluText {
                    text: "目前進度: " + (page.restoreIndex + 1) + " / " + Math.max(page.restoreTotal, 1) + " (" + Math.round((page.restoreIndex) / Math.max(page.restoreTotal, 1) * 100) + "%)"
                    font: FluTextStyle.Body
                    Layout.fillWidth: true
                }
            }

            // 進度條
            FluProgressBar {
                Layout.fillWidth: true
                strokeWidth: 6
                indeterminate: false
                value: page.restoreIndex / Math.max(page.restoreTotal, 1)
            }

            // 目前正在復原的應用程式
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: 6
                color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6
                    FluText {
                        text: "正在復原: "
                        font: FluTextStyle.Caption
                        color: FluTheme.fontSecondaryColor
                    }
                    FluText {
                        text: (page.restoreCurrentName || "準備中") + " (" + (page.restoreCurrentPkg || "-") + ")"
                        font: FluTextStyle.Caption
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                FluButton {
                    text: "中斷剩餘任務"
                    onClicked: page.cancelBatchRestore()
                }
            }
        }
    }

    // 10. 批次復原完成摘要 Dialog (重點功能)
    FluPopup {
        id: batchRestoreSummaryPopup
        width: 460
        height: Math.min(420, page.height - 40)
        modal: true
        closePolicy: Popup.CloseOnEscape

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            RowLayout {
                spacing: 10
                FluIcon {
                    iconSource: FluentIcons.CheckMark
                    iconSize: 24
                    iconColor: page.restoreFailList.length === 0 ? "#10b981" : "#ca8a04"
                }
                FluText {
                    text: "批次復原完成"
                    font: FluTextStyle.Title
                }
            }

            // 統計資訊卡片
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: 6
                    color: Qt.rgba(0.06, 0.48, 0.42, FluTheme.dark ? 0.25 : 0.12)
                    border.width: 1
                    border.color: Qt.rgba(0.06, 0.48, 0.42, 0.35)

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        FluText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "成功復原"
                            font: FluTextStyle.Caption
                            color: FluTheme.fontSecondaryColor
                        }
                        FluText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.restoreSuccessList.length + " 個"
                            font: FluTextStyle.BodyStrong
                            color: "#10b981"
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: 6
                    color: page.restoreFailList.length > 0
                           ? Qt.rgba(0.85, 0.23, 0.0, FluTheme.dark ? 0.25 : 0.12)
                           : (FluTheme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04))
                    border.width: 1
                    border.color: page.restoreFailList.length > 0 ? Qt.rgba(0.85, 0.23, 0.0, 0.35) : (FluTheme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10))

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        FluText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "失敗 / 略過"
                            font: FluTextStyle.Caption
                            color: FluTheme.fontSecondaryColor
                        }
                        FluText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.restoreFailList.length + " 個"
                            font: FluTextStyle.BodyStrong
                            color: page.restoreFailList.length > 0 ? "#ef4444" : FluTheme.fontSecondaryColor
                        }
                    }
                }
            }

            // 失敗清單（如果有）
            FluText {
                text: "失敗應用程式清單："
                font: FluTextStyle.Caption
                color: FluTheme.fontSecondaryColor
                visible: page.restoreFailList.length > 0
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 6
                visible: page.restoreFailList.length > 0
                color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                border.width: 1
                border.color: FluTheme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)

                ListView {
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    model: page.restoreFailList
                    ScrollBar.vertical: FluScrollBar {}

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 36
                        radius: 4
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            FluText {
                                text: modelData.appName || modelData.packageName
                                font: FluTextStyle.Body
                                elide: Text.ElideRight
                                Layout.preferredWidth: 140
                            }

                            FluText {
                                text: modelData.packageName
                                font: FluTextStyle.Caption
                                color: FluTheme.fontSecondaryColor
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }

                            FluText {
                                text: modelData.reason || "復原失敗"
                                font: FluTextStyle.Caption
                                color: "#ef4444"
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                FluFilledButton {
                    text: "完成"
                    normalColor: "#0f7b6c"
                    onClicked: {
                        batchRestoreSummaryPopup.close()
                    }
                }
            }
        }
    }
}
