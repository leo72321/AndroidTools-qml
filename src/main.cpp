#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QThread>
#include <QElapsedTimer>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>

#include "cpp/adb/connectmanager.h"
#include "cpp/adb/adblog.h"
#include "cpp/adb/adbdevice.h"
#include "src/cpp/adb/devicehelper.h"
#include "cpp/components/fpsitem.h"
#include "cpp/components/SystemInfoProvider.h"
#include "cpp/utils/globalsetting.h"
#include "cpp/utils/constants.h"
#include "cpp/utils/notificationcontroller.h"
#include "cpp/utils/serviceregistry.h"
#include "cpp/app/appglobal.h"
#include "cpp/imagePageTool/scrcpy/ui/mirror/imageframeitem.h"
#include "cpp/imagePageTool/scrcpy/core/include/QtScrcpyCore.h"
#include <QFontDatabase>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

bool checkADB()
{
#ifdef Q_OS_WIN
    const QString executable = "adb.exe";
#else
    const QString executable = "adb";
#endif
    const QString appDir = QCoreApplication::applicationDirPath();
    QString adbPath = QStandardPaths::findExecutable(executable);
    const QStringList bundledPaths = {
        appDir + "/" + executable,
        appDir + "/tools/" + executable,
        appDir + "/../Resources/tools/" + executable,
        appDir + "/../lib/android-tools/tools/" + executable,
        appDir + "/lib/" + executable,
        appDir + "/../../../lib/" + executable
    };

    for (const QString &path : bundledPaths) {
        if (adbPath.isEmpty() && QFileInfo::exists(path)) {
            adbPath = QDir::cleanPath(path);
        }
    }

    if (adbPath.isEmpty()) {
        qWarning() << "can not find adb";
        return false;
    }

    const QString path = QFileInfo(adbPath).absolutePath()
        + QDir::listSeparator() + QString::fromLocal8Bit(qgetenv("PATH"));
    qputenv("PATH", path.toLocal8Bit());
    qputenv("QTSCRCPY_ADB_PATH", adbPath.toLocal8Bit());
    return true;
}

void forceOpenGL()
{
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QSurfaceFormat format;
    format.setSwapBehavior(QSurfaceFormat::DoubleBuffer);
    format.setSwapInterval(0);
    QSurfaceFormat::setDefaultFormat(format);
}

int main(int argc, char *argv[])
{
#ifdef Q_OS_WIN
    HANDLE hJob = CreateJobObject(nullptr, nullptr);
    if (hJob) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION jeli = { 0 };
        jeli.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if (SetInformationJobObject(hJob, JobObjectExtendedLimitInformation, &jeli, sizeof(jeli))) {
            AssignProcessToJobObject(hJob, GetCurrentProcess());
        }
    }
#endif

    QApplication app(argc, argv);

    const QStringList fontFamilies = {
        QStringLiteral("Source Han Sans TC"),
        QStringLiteral("Noto Sans TC"),
        QStringLiteral("Noto Sans CJK TC"),
        QStringLiteral("Microsoft JhengHei UI"),
        QStringLiteral("Microsoft JhengHei"),
        QStringLiteral("Segoe UI")
    };

    QFont defaultFont = app.font();
    defaultFont.setFamilies(fontFamilies);
    app.setFont(defaultFont);

#ifdef Q_OS_LINUX
    qunsetenv("http_proxy");
    qunsetenv("https_proxy");
#endif

    if (!checkADB()) {
        return 0;
    }

    QQuickStyle::setStyle("Fusion");
    QElapsedTimer loaderTimer;
    loaderTimer.start();


    ServiceRegistry registry(&app);
    registry.initialize();

    ADT::CONNECTMANAGER->startADBServer([&]() {
        QMetaObject::invokeMethod(ADT::CONNECTMANAGER, "startCheckDevice", Qt::QueuedConnection);
    });

    qmlRegisterSingletonInstance("NotificationController", 1, 0, "NotificationController", NotificationController::instance());
    qmlRegisterType<FpsItem>("FpsItem", 1, 0, "FpsItem");
    qmlRegisterType<ImageFrameItem>("ImageFrameItem", 1, 0, "ImageFrameItem");
    qmlRegisterSingletonInstance("SystemInfo", 1, 0, "SystemInfo", SystemInfoProvider::instance());
    qmlRegisterSingletonInstance("App", 1, 0, "App", App);
    qmlRegisterSingletonInstance("ConnectManager", 1, 0, "ConnectManager", ADT::ConnectManager::instance());
    qmlRegisterSingletonInstance("DeviceHelper", 1, 0, "DeviceHelper", ADT::DeviceHelper::instance());
    qmlRegisterSingletonInstance("ADBLog", 1, 0, "ADBLog", ADBLogModel::instance(&app));

    qmlRegisterUncreatableMetaObject(ADT::staticMetaObject, "ADT", 1, 0, "ADT", "Access to enums & flags only");

    qInfo() << "核心模块加载完成，用时(ms):" << loaderTimer.elapsed();

    AppSettings->checkConfig("other", "useOpenGL", DEFAULT_USE_OPENGL);
    bool useOpenGL = GlobalSetting::instance()->readConfig("other", "useOpenGL").toBool();
    if (useOpenGL) {
        qInfo() << "force use OpenGL";
        forceOpenGL();
    }

    QQmlApplicationEngine engine;
    const QString appDir = QCoreApplication::applicationDirPath();
    engine.addImportPath(appDir + "/qml");
    engine.addImportPath(appDir + "/../Resources/qml");
    engine.addImportPath(appDir + "/../share/android-tools/qml");
    engine.addImportPath(appDir + "/../../../qml");
    const QUrl url("qrc:/qml2/Main.qml");
    engine.load(url);
    qInfo() << "QML界面加载完成，用时(ms):" << loaderTimer.elapsed();

    QObject::connect(&app, &QCoreApplication::aboutToQuit, [&]() {
        // 斷開投屏設備
        qsc::IDeviceManage::getInstance().disconnectAllDevice();
        // 呼叫 ADT::CONNECTMANAGER->cleanup();
        ADT::CONNECTMANAGER->cleanup();
    });

    return app.exec();
}
