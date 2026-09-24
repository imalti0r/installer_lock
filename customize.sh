#!/system/bin/sh
# customize.sh - Magisk安装时执行
# v3.0.0: 精简版，仅复制APK + 设置权限，不做systemless覆盖

VERSION="v3.0.0"
APKNAME="custom_installer.apk"
LOGFILE="$MODPATH/module.log"

ui_print " "
ui_print "================================"
ui_print "  Installer Lock (HyperOS) ${VERSION}"
ui_print "  开机后pm install覆盖安装"
ui_print "  需要核心破解(LSPosed)支持"
ui_print "================================"
ui_print " "

# 设置权限
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755

ui_print "- APK: $APKNAME"
APK_SIZE=$(wc -c < "$MODPATH/$APKNAME" 2>/dev/null)
ui_print "- APK大小: ${APK_SIZE}字节"
ui_print "- 安装完成，重启后生效"
ui_print "- 日志: $LOGFILE"
