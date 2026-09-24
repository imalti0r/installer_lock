#!/system/bin/sh
# customize.sh - 安装时查找MIUI安装器路径并创建systemless覆盖
# 仅覆盖MIUI版安装器，不碰AOSP版

SKIPUNZIP=0

PKG="com.miui.packageinstaller"
APKNAME="custom_installer.apk"
VERSION="v2.0.0"

# ====== 日志函数 ======
LOGFILE="/data/adb/modules/installer_lock/module.log"

log() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    local line="[$ts] [$level] $msg"
    ui_print "$line"
    mkdir -p /data/adb/modules/installer_lock 2>/dev/null
    echo "$line" >> "$LOGFILE"
}

log_info()  { log "INFO"  "$1"; }
log_warn()  { log "WARN"  "$1"; }
log_error() { log "ERROR" "$1"; }
log_step()  { log "STEP"  "$1"; }

# ====== 日志清理 ======
clean_log() {
    if [ -f "$LOGFILE" ]; then
        LOG_SIZE=$(wc -c < "$LOGFILE" 2>/dev/null)
        # 超过256KB则只保留最后100行
        if [ "$LOG_SIZE" -gt 262144 ] 2>/dev/null; then
            tail -n 100 "$LOGFILE" > "${LOGFILE}.tmp" 2>/dev/null
            mv "${LOGFILE}.tmp" "$LOGFILE" 2>/dev/null
            echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] [INFO] 日志已自动清理(超过256KB,保留最后100行)" >> "$LOGFILE"
        fi
    fi
}

clean_log
log_info "========== customize.sh v${VERSION} 开始执行 =========="
log_info "模块路径: $MODPATH"

ui_print " "
ui_print "================================"
ui_print "  Installer Lock (HyperOS) v${VERSION}"
ui_print "  锁定MIUI安装器为自定义版本"
ui_print "================================"
ui_print " "

# ====== MIUI安装器已知路径（仅MIUI版）======
MIUI_PATHS="
/product/priv-app/MIUIPackageInstaller/MIUIPackageInstaller.apk
/product/priv-app/MIUIPackageInstaller/base.apk
/system/product/priv-app/MIUIPackageInstaller/MIUIPackageInstaller.apk
/system/product/priv-app/MIUIPackageInstaller/base.apk
/system/system_ext/priv-app/MiuiPackageInstaller/MiuiPackageInstaller.apk
/system/priv-app/MiuiPackageInstaller/MiuiPackageInstaller.apk
"

# ====== 查找MIUI安装器路径 ======
log_step "查找MIUI安装器APK路径"
ui_print "- 正在查找MIUI安装器APK路径..."

FOUND_PATHS=""

# 方法1: pm path
log_info "尝试pm path"
PM_OUTPUT=$(pm path "$PKG" 2>/dev/null | grep -v "/data/" | sed 's/^package://' | tr -d '\r\n ')
if [ -n "$PM_OUTPUT" ]; then
    echo "$PM_OUTPUT" | while read -r p; do
        if [ -n "$p" ] && [ -f "$p" ]; then
            case "$p" in
                *MIUI*|*Miui*|*miui*)
                    case "$FOUND_PATHS" in
                        *"$p"*) ;;
                        *) FOUND_PATHS="$FOUND_PATHS $p"; log_info "pm path找到MIUI版: $p" ;;
                    esac
                    ;;
            esac
        fi
    done
fi

# 方法2: 遍历已知MIUI路径
log_info "遍历已知MIUI路径"
for p in $MIUI_PATHS; do
    if [ -f "$p" ]; then
        case "$FOUND_PATHS" in
            *"$p"*) ;;
            *) FOUND_PATHS="$FOUND_PATHS $p"; log_info "找到MIUI安装器: $p" ;;
        esac
    fi
done

if [ -z "$FOUND_PATHS" ]; then
    log_error "未找到MIUI安装器APK"
    ui_print "! 错误: 未找到MIUI安装器APK"
    abort "安装中止：未找到MIUI安装器"
fi

# ====== 为每个路径创建systemless覆盖 ======
log_step "创建systemless覆盖"
ui_print "- 正在创建systemless覆盖..."

OVERLAY_COUNT=0
APK_SIZE=$(wc -c < "$MODPATH/$APKNAME" 2>/dev/null)

for p in $FOUND_PATHS; do
    if [ -z "$p" ]; then continue; fi

    log_info "--- 处理: $p ---"

    # 相对路径（去掉/system前缀）
    case "$p" in
        /system/*) REL_PATH="${p#/system}" ;;
        /product/*) REL_PATH="${p#/}" ;;
        *) REL_PATH="${p#/}" ;;
    esac
    OVERLAY_PATH="${MODPATH}/system${REL_PATH}"
    OVERLAY_DIR=$(dirname "$OVERLAY_PATH")

    mkdir -p "$OVERLAY_DIR"
    cp "$MODPATH/$APKNAME" "$OVERLAY_PATH"

    if [ $? -eq 0 ]; then
        set_perm "$OVERLAY_PATH" 0 0 0644
        OVERLAY_SIZE=$(wc -c < "$OVERLAY_PATH" 2>/dev/null)
        if [ "$OVERLAY_SIZE" = "$APK_SIZE" ]; then
            log_info "覆盖成功: $OVERLAY_PATH (${OVERLAY_SIZE}字节)"
            OVERLAY_COUNT=$((OVERLAY_COUNT + 1))
        else
            log_warn "覆盖大小不一致: $OVERLAY_PATH"
        fi
    else
        log_error "复制失败: $OVERLAY_PATH"
    fi
done

log_info "systemless覆盖完成: ${OVERLAY_COUNT}个文件"
ui_print "- 已创建 ${OVERLAY_COUNT} 个覆盖文件"

# ====== 完成提示 ======
log_info "========== customize.sh 执行完成 =========="
ui_print " "
ui_print "================================"
ui_print "  安装完成! v${VERSION}"
ui_print "  重启后MIUI安装器将被锁定"
ui_print "  "
ui_print "  覆盖路径: ${OVERLAY_COUNT}个"
ui_print "  日志: $LOGFILE"
ui_print "  日志自动清理: 超过256KB保留最后100行"
ui_print "================================"
ui_print " "
