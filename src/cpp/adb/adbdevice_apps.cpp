#include "adbdevice.h"
#include "src/cpp/adb/adbtools.h"
#include <QDebug>
#include <QUrl>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDateTime>
#include <QSet>

namespace ADT {

QList<AppDetailInfo> ADBDevice::getSoftListInfo(SoftListType type) const
{
    if (type == SoftListType::UninstalledSystem) {
        QStringList argsAll;
        argsAll << "-s" << code() << "shell" << "pm" << "list" << "packages" << "-s" << "-u";
        QString outAll = m_adbTools->executeCommand(ADBTools::ADB, argsAll, "", INT_MAX);

        QStringList argsInstalled;
        argsInstalled << "-s" << code() << "shell" << "pm" << "list" << "packages" << "-s";
        QString outInstalled = m_adbTools->executeCommand(ADBTools::ADB, argsInstalled, "", INT_MAX);

        QSet<QString> installedPkgs;
        for (const QString &line : outInstalled.split('\n')) {
            QString pkg = line.trimmed();
            if (pkg.startsWith("package:")) {
                pkg = pkg.mid(8).trimmed();
            }
            if (!pkg.isEmpty()) {
                installedPkgs.insert(pkg);
            }
        }

        QSet<QString> seen;
        QList<AppDetailInfo> appList;
        for (const QString &line : outAll.split('\n')) {
            QString pkg = line.trimmed();
            if (pkg.startsWith("package:")) {
                pkg = pkg.mid(8).trimmed();
            }
            if (!pkg.isEmpty() && !installedPkgs.contains(pkg) && !seen.contains(pkg)) {
                seen.insert(pkg);
                AppDetailInfo info;
                info.packageName = pkg;
                info.appName = pkg;
                info.isSystemApp = true;
                info.installedForCurrentUser = false;
                info.isEnabled = false;
                appList.append(info);
            }
        }
        return appList;
    }

    QUrl url("http://localhost:18888/apps");
    if (type == SoftListType::ThirdParty) {
        url.setQuery(QUrlQuery("isUser=true"));
    } else if (type == SoftListType::System) {
        url.setQuery(QUrlQuery("isSystem=true"));
    }

    QSet<QString> disabledPkgs;
    if (type == SoftListType::Disabled) {
        QStringList disabledArgs;
        disabledArgs << "-s" << code() << "shell" << "pm" << "list" << "packages" << "-d";
        QString disabledOut = m_adbTools->executeCommand(ADBTools::ADB, disabledArgs, "", INT_MAX);
        for (const QString &line : disabledOut.split('\n')) {
            QString pkg = line.trimmed();
            if (pkg.startsWith("package:")) {
                pkg = pkg.mid(8).trimmed();
            }
            if (!pkg.isEmpty()) {
                disabledPkgs.insert(pkg);
            }
        }
    }

    auto ret = syncCallNetGetMethod(url);
    QJsonDocument jsonDoc = QJsonDocument::fromJson(ret.data.toUtf8());
    if (!jsonDoc.isArray()) {
        qWarning() << "Invalid JSON response:" << ret.data;
        return {};
    }
    QJsonArray jsonArray = jsonDoc.array();
    QList<AppDetailInfo> appList;
    QSet<QString> processedPkgs;
    for (const QJsonValue &value : jsonArray) {
        if (value.isObject()) {
            QJsonObject obj = value.toObject();
            AppDetailInfo info;
            info.packageName = obj.value("packageName").toString();
            info.appName = obj.value("appName").toString();
            info.versionName = obj.value("versionName").toString();
            info.versionCode = obj.value("versionCode").toVariant().toULongLong();
            info.isSystemApp = obj.value("isSystemApp").toBool();
            info.isEnabled = obj.value("isEnabled").toBool();
            info.installedForCurrentUser = true;
            info.firstInstallTime = QDateTime::fromMSecsSinceEpoch(obj.value("firstInstallTime").toVariant().toLongLong()).toString("yyyy-MM-dd hh:mm:ss");
            info.lastUpdateTime = QDateTime::fromMSecsSinceEpoch(obj.value("lastUpdateTime").toVariant().toLongLong()).toString("yyyy-MM-dd hh:mm:ss");
            info.iconBase64 = "";

            if (disabledPkgs.contains(info.packageName)) {
                info.isEnabled = false;
            }

            // 依據 SoftListType 進行二次過濾
            if (type == SoftListType::ThirdParty) {
                if (info.isSystemApp) {
                    continue;
                }
            } else if (type == SoftListType::System) {
                if (!info.isSystemApp) {
                    continue;
                }
            } else if (type == SoftListType::Disabled) {
                if (info.isEnabled && !disabledPkgs.contains(info.packageName)) {
                    continue;
                }
            }

            processedPkgs.insert(info.packageName);
            appList.append(info);
        }
    }

    if (type == SoftListType::Disabled) {
        for (const QString &pkg : disabledPkgs) {
            if (!processedPkgs.contains(pkg)) {
                AppDetailInfo info;
                info.packageName = pkg;
                info.appName = pkg;
                info.isEnabled = false;
                info.installedForCurrentUser = true;
                appList.append(info);
            }
        }
    }

    return appList;
}

QString ADBDevice::getAppIconBase64(const QString &packageName) const
{
    QUrl url("http://localhost:18888/appIcon");
    url.setQuery(QUrlQuery("packageName=" + packageName));

    auto ret = syncCallNetGetMethod(url);
    if (!ret.success) {
        qWarning() << "Failed to get app icon:" << ret.data;
        return {};
    }

    QJsonDocument jsonDoc = QJsonDocument::fromJson(ret.data.toUtf8());
    if (!jsonDoc.isObject()) {
        qWarning() << "Invalid JSON response for app icon:" << ret.data;
        return {};
    }

    QString iconBase64 = jsonDoc.object().value("iconBase64").toString();
    if (iconBase64.isEmpty() || iconBase64.startsWith("data:")) {
        return iconBase64;
    }

    return "data:image/png;base64," + iconBase64;
}

bool ADBDevice::installApp(const QString &path, bool r, bool s, bool d, bool g)
{
    QStringList args;
    args << "-s" << code() << "install";

    if (r) args << "-r";
    if (s) args << "-s";
    if (d) args << "-d";
    if (g) args << "-g";

    args << path;

    CommandResult result = m_adbTools->executeCommandDetailed(ADBTools::ADB, args, "", INT_MAX);


    return result.isSuccess() && result.output.contains("Success");
}

bool ADBDevice::clearData(const QString &packageName)
{
    QStringList args;
    args << "-s" << code() << "shell" << "pm" << "clear" << packageName;
    CommandResult result = m_adbTools->executeCommandDetailed(ADBTools::ADB, args, "", INT_MAX);


    return result.isSuccess() && result.output.contains("Success");
}

bool ADBDevice::uninstallApp(const QString &packageName)
{
    QStringList args;
    args << "-s" << code() << "uninstall" << packageName;
    CommandResult result = m_adbTools->executeCommandDetailed(ADBTools::ADB, args, "", INT_MAX);


    return result.isSuccess() && result.output.contains("Success");
}

bool ADBDevice::freezeApp(const QString &packageName)
{
    QStringList args;
    args << "-s" << code() << "shell" << "pm" << "disable-user" << packageName;
    QString result = m_adbTools->executeCommand(ADBTools::ADB, args, "", INT_MAX);
    return !result.contains("Error");
}

bool ADBDevice::unfreezeApp(const QString &packageName)
{
    QStringList args;
    args << "-s" << code() << "shell" << "pm" << "enable" << packageName;
    QString result = m_adbTools->executeCommand(ADBTools::ADB, args, "", INT_MAX);
    return !result.contains("Error");
}

bool ADBDevice::enableApp(const QString &packageName)
{
    QString userId = getCurrentUserId();
    QStringList args;
    args << "-s" << code() << "shell" << "pm" << "enable" << "--user" << userId << packageName;
    CommandResult result = m_adbTools->executeCommandDetailed(ADBTools::ADB, args, "", INT_MAX);

    if (!result.isSuccess() || result.getAllOutput().contains("Error", Qt::CaseInsensitive) || result.getAllOutput().contains("Unknown option", Qt::CaseInsensitive)) {
        QStringList fallbackArgs;
        fallbackArgs << "-s" << code() << "shell" << "pm" << "enable" << packageName;
        CommandResult fallbackResult = m_adbTools->executeCommandDetailed(ADBTools::ADB, fallbackArgs, "", INT_MAX);
        return fallbackResult.isSuccess() && !fallbackResult.getAllOutput().contains("Error", Qt::CaseInsensitive);
    }

    return true;
}

bool ADBDevice::restoreApp(const QString &packageName)
{
    QString userId = getCurrentUserId();

    // 1. 优先执行 adb shell cmd package install-existing --user <userId> <pkg>
    QStringList cmdArgs;
    cmdArgs << "-s" << code() << "shell" << "cmd" << "package" << "install-existing" << "--user" << userId << packageName;
    CommandResult cmdRes = m_adbTools->executeCommandDetailed(ADBTools::ADB, cmdArgs, "", INT_MAX);
    if (cmdRes.getAllOutput().contains("installed", Qt::CaseInsensitive)) {
        return true;
    }

    // 2. Fallback 至 pm install-existing --user <userId> <pkg>
    QStringList pmUserArgs;
    pmUserArgs << "-s" << code() << "shell" << "pm" << "install-existing" << "--user" << userId << packageName;
    CommandResult pmUserRes = m_adbTools->executeCommandDetailed(ADBTools::ADB, pmUserArgs, "", INT_MAX);
    if (pmUserRes.getAllOutput().contains("installed", Qt::CaseInsensitive)) {
        return true;
    }

    // 3. Fallback 至 pm install-existing <pkg>
    QStringList pmArgs;
    pmArgs << "-s" << code() << "shell" << "pm" << "install-existing" << packageName;
    CommandResult pmRes = m_adbTools->executeCommandDetailed(ADBTools::ADB, pmArgs, "", INT_MAX);
    if (pmRes.getAllOutput().contains("installed", Qt::CaseInsensitive)) {
        return true;
    }

    return false;
}

QString ADBDevice::getCurrentUserId() const
{
    QStringList args;
    args << "-s" << code() << "shell" << "cmd" << "user" << "get-main-user";
    QString out = m_adbTools->executeCommand(ADBTools::ADB, args).trimmed();
    bool ok = false;
    int uid = out.toInt(&ok);
    if (ok && uid >= 0) {
        return QString::number(uid);
    }

    args.clear();
    args << "-s" << code() << "shell" << "am" << "get-current-user";
    out = m_adbTools->executeCommand(ADBTools::ADB, args).trimmed();
    uid = out.toInt(&ok);
    if (ok && uid >= 0) {
        return QString::number(uid);
    }

    return "0";
}

bool ADBDevice::extractApp(const QString &packageName, const QString &targetPath)
{
    QStringList pathArgs;
    pathArgs << "-s" << code() << "shell" << "pm" << "path" << packageName;
    QString pathResult = m_adbTools->executeCommand(ADBTools::ADB, pathArgs);

    if (pathResult.isEmpty() || !pathResult.contains("package:")) {
        return false;
    }

    QString apkPath = pathResult.simplified().split(':').value(1);
    if (apkPath.isEmpty()) {
        return false;
    }

    QStringList args;
    args << "-s" << code() << "pull" << apkPath << targetPath;
    QString result = m_adbTools->executeCommand(ADBTools::ADB, args, "", INT_MAX);
    return !result.contains("failed");
}

void ADBDevice::startApp(const QString &packageName)
{
    QStringList args;
    args << "-s" << code() << "shell" << "monkey" << "-p" << packageName
         << "-c" << "android.intent.category.LAUNCHER" << "1";
    m_adbTools->executeCommand(ADBTools::ADB, args, "", INT_MAX);
}

bool ADBDevice::stopApp(const QString &packageName)
{
    killActivity(packageName);
    return true;
}

void ADBDevice::killActivity(const QString &packageName)
{
    QStringList args;
    args << "-s" << code() << "shell" << "am" << "force-stop" << packageName;
    m_adbTools->executeCommand(ADBTools::ADB, args);
}

void ADBDevice::startActivity(const QString &activity, const QStringList &args)
{
    QStringList adbArgs;
    adbArgs << "-s" << code() << "shell" << "am" << "start" << "-n" << activity << args;
    m_adbTools->executeCommand(ADBTools::ADB, adbArgs);
}

} // namespace ADT
