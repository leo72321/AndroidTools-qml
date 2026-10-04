#include "appDetailControl.h"
#include "src/cpp/adb/connectmanager.h"
#include "src/cpp/utils/notificationcontroller.h"
#include "src/cpp/utils/utils.hpp"
#include <QVariant>
#include <QFileInfo>
#include <QMetaObject>

namespace ADT {

AppDetailControl::AppDetailControl(QObject *parent)
    : QObject(parent)
    , m_busy(false)
{
    connect(this, &AppDetailControl::updateSoftDetailInfoFinish, this, &AppDetailControl::onUpdateSoftDetailInfoFinish, Qt::QueuedConnection);
}

AppDetailControl::~AppDetailControl()
{

}

bool AppDetailControl::beginOperation(const QSharedPointer<ADBDevice> &device)
{
    if (busy()) {
        NotificationController::instance()->send("操作進行中", "請等待目前任務完成", NotificationController::Warning);
        return false;
    }
    if (!device) {
        NotificationController::instance()->send("執行失敗", "目前無裝置連線", NotificationController::Error);
        return false;
    }
    setbusy(true);
    return true;
}

void AppDetailControl::finishOperation()
{
    QMetaObject::invokeMethod(this, [this]() { setbusy(false); }, Qt::QueuedConnection);
}

void AppDetailControl::updateInfo(const QString &packageName)
{
    const auto device = CONNECTMANAGER->selectedADBDevice();
    asyncOperator([packageName, device, this](){
        AppDetailInfo info;
        if (!device || packageName.isEmpty()) {
            Q_EMIT updateSoftDetailInfoFinish(info);
            return;
        }

        const auto appList = device->getSoftListInfo(SoftListType::All);
        for (const auto &appInfo : appList) {
            if (appInfo.packageName == packageName) {
                info = appInfo;
                break;
            }
        }
        Q_EMIT updateSoftDetailInfoFinish(info);
    });
}

void AppDetailControl::installApp(const QString &path, bool r, bool s, bool d, bool g)
{
    const QFileInfo apk(path);
    if (!apk.isFile() || apk.suffix().compare("apk", Qt::CaseInsensitive) != 0) {
        NotificationController::instance()->send("安裝失敗", "請選擇有效的 APK 檔案", NotificationController::Warning);
        return;
    }
    const auto device = CONNECTMANAGER->selectedADBDevice();
    if (!beginOperation(device)) return;
    asyncOperator([path, r, s, d, g, device, this](){
        NotificationController::instance()->send("安裝中", "正在安裝 " + QFileInfo(path).fileName(), NotificationController::Info);
        if (!device->installApp(path, r, s, d, g)) {
            NotificationController::instance()->send("安裝失敗", "請檢視錯誤紀錄", NotificationController::Error);
        } else {
            NotificationController::instance()->send("安裝成功", QFileInfo(path).fileName(), NotificationController::Info);
            Q_EMIT requestUpdateSoftList();
        }
        finishOperation();
    });
}

void AppDetailControl::clearData(const QString &packageName)
{
    const auto device = CONNECTMANAGER->selectedADBDevice();
    if (!beginOperation(device)) return;
    asyncOperator([packageName, device, this](){
        if (!device->clearData(packageName)) {
            NotificationController::instance()->send("清除資料失敗", packageName, NotificationController::Error);
        }
        finishOperation();
    });
}

void AppDetailControl::uninstallApp(const QString &packageName)
{
    const auto device = CONNECTMANAGER->selectedADBDevice();
    if (!beginOperation(device)) return;
    asyncOperator([packageName, device, this](){
        if (!device->uninstallApp(packageName)) {
            NotificationController::instance()->send("解除安裝失敗", packageName, NotificationController::Error);
        } else {
            NotificationController::instance()->send("解除安裝成功", packageName, NotificationController::Info);
            Q_EMIT requestUpdateSoftList();
        }
        finishOperation();
    });
}

void AppDetailControl::freezeApp(const QString &packageName)
{
    const auto device = CONNECTMANAGER->selectedADBDevice();
    if (!beginOperation(device)) return;
    asyncOperator([packageName, device, this](){
        if (!device->freezeApp(packageName)) {
            NotificationController::instance()->send("凍結失敗", packageName, NotificationController::Error);
        } else {
            NotificationController::instance()->send("凍結成功", packageName, NotificationController::Info);
            Q_EMIT requestUpdateSoftList();
        }
        finishOperation();
    });
}

void AppDetailControl::unfreezeApp(const QString &packageName)
{
    const auto device = CONNECTMANAGER->selectedADBDevice();
    if (!beginOperation(device)) return;
    asyncOperator([packageName, device, this](){
        if (!device->unfreezeApp(packageName)) {
            NotificationController::instance()->send("解凍失敗", packageName, NotificationController::Error);
        } else {
            NotificationController::instance()->send("解凍成功", packageName, NotificationController::Info);
            Q_EMIT requestUpdateSoftList();
        }
        finishOperation();
    });
}

void AppDetailControl::enableApp(const QString &packageName)
{
    const auto device = CONNECTMANAGER->selectedADBDevice();
    if (!beginOperation(device)) return;
    asyncOperator([packageName, device, this](){
        if (!device->enableApp(packageName)) {
            NotificationController::instance()->send("啟用失敗", packageName, NotificationController::Error);
        } else {
            NotificationController::instance()->send("啟用成功", packageName, NotificationController::Info);
            Q_EMIT requestUpdateSoftList();
        }
        finishOperation();
    });
}

void AppDetailControl::restoreApp(const QString &packageName)
{
    const auto device = CONNECTMANAGER->selectedADBDevice();
    if (!beginOperation(device)) return;
    asyncOperator([packageName, device, this](){
        if (!device->restoreApp(packageName)) {
            NotificationController::instance()->send("復原失敗", packageName, NotificationController::Error);
        } else {
            NotificationController::instance()->send("復原成功", packageName, NotificationController::Info);
            Q_EMIT requestUpdateSoftList();
        }
        finishOperation();
    });
}

void AppDetailControl::extractApp(const QString &packageName, const QString &targetPath)
{
    const auto device = CONNECTMANAGER->selectedADBDevice();
    if (!beginOperation(device)) return;
    asyncOperator([packageName, targetPath, device, this](){
        NotificationController::instance()->send("擷取中", packageName, NotificationController::Info);
        if (!device->extractApp(packageName, targetPath)) {
            NotificationController::instance()->send("擷取失敗", packageName, NotificationController::Error);
        } else {
            NotificationController::instance()->send("擷取成功", "儲存在 " + targetPath, NotificationController::Info);
        }
        finishOperation();
    });
}

void AppDetailControl::stopApp(const QString &packageName)
{
    const auto device = CONNECTMANAGER->selectedADBDevice();
    if (!beginOperation(device)) return;
    asyncOperator([packageName, device, this](){
        if (!device->stopApp(packageName)) {
            NotificationController::instance()->send("停止失敗", packageName, NotificationController::Error);
        }
        finishOperation();
    });
}

void AppDetailControl::startApp(const QString &packageName)
{
    const auto device = CONNECTMANAGER->selectedADBDevice();
    if (!beginOperation(device)) return;
    asyncOperator([packageName, device, this](){
        device->startApp(packageName);
        NotificationController::instance()->send("啟動命令已傳送", packageName, NotificationController::Info);
        finishOperation();
    });
}

void AppDetailControl::startActivity(const QString &activity, const QStringList &args)
{
    const auto device = CONNECTMANAGER->selectedADBDevice();
    if (!beginOperation(device)) return;
    asyncOperator([activity, args, device, this](){
        device->startActivity(activity, args);
        NotificationController::instance()->send("Activity 命令已傳送", activity, NotificationController::Info);
        finishOperation();
    });
}

void AppDetailControl::requestLoadIcon(const QString &packageName)
{
    if (packageName.isEmpty()) {
        return;
    }

    const auto device = CONNECTMANAGER->selectedADBDevice();
    asyncOperator([packageName, device, this](){
        if (!device) {
            return;
        }

        auto iconBase64 = device->getAppIconBase64(packageName);
        QMetaObject::invokeMethod(this, [this, packageName, iconBase64]() {
            Q_EMIT iconLoaded(packageName, iconBase64);
        }, Qt::QueuedConnection);
    });
}

void AppDetailControl::onUpdateSoftDetailInfoFinish(const AppDetailInfo &info)
{
    m_info = info;
    emit valueChanged(m_info);
}

void AppDetailControl::setSoftListType(SoftListType type)
{
    m_softListType = type;
    emit softListTypeChanged(m_softListType);
}

} // namespace ADT
