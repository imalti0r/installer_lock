#!/system/bin/sh
# post-fs-data.sh - 早期bind mount MIUI安装器
# 仅覆盖MIUI版，不碰AOSP版

MODDIR=${0%/*}
APK="$MODDIR/custom_installer.apk"
PKG="com.miui.packageinstaller"
LOGFILE="$MODDIR/module.log"
VERSION="v2.0.0"

# ====== 日志函数 ======
log() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    echo "[$ts] [$level] $msg" >> "$LOGFILE" 2>/dev/null
}

log_info()  { log "INFO"  "$1"; }
log_warn()  { log "WARN"  "$1"; }
log_error() { log "ERROR" "$1"; }
log_step()  { log "STEP"  "$1"; }

# ====== 日志清理 ======
if [ -f "$LOGFILE" ]; then
    LOG_SIZE=$(wc -c < "$LOGFILE" 2>/dev/null)
    if [ "$LOG_SIZE" -gt 262144 ] 2>/dev/null; then
        tail -n 100 "$LOGFILE" > "${LOGFILE}.tmp" 2>/dev/null
        mv "${LOGFILE}.tmp" "$LOGFILE" 2>/dev/null
        echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] [INFO] 日志已自动清理" >> "$LOGFILE"
    fi
fi

log_info "========== post-fs-data.sh ${VERSION} 开始执行 =========="

if [ ! -f "$APK" ]; then
    log_error "自定义APK不存在: $APK，退出"
    exit 0
fi

SRC_SIZE=$(wc -c < "$APK" 2>/dev/null)
log_info "APK大小: ${SRC_SIZE}字节"

# MIUI安装器路径
MIUI_PATHS="
/product/priv-app/MIUIPackageInstaller/MIUIPackageInstaller.apk
/product/priv-app/MIUIPackageInstaller/base.apk
/system/product/priv-app/MIUIPackageInstaller/MIUIPackageInstaller.apk
/system/product/priv-app/MIUIPackageInstaller/base.apk
/system/system_ext/priv-app/MiuiPackageInstaller/MiuiPackageInstaller.apk
/system/priv-app/MiuiPackageInstaller/MiuiPackageInstaller.apk
"

log_step "bind mount MIUI安装器路径"

MOUNT_SUCCESS=0
for p in $MIUI_PATHS; do
    if [ ! -f "$p" ]; then continue; fi

    # 已mount则跳过
    if mount 2>/dev/null | grep -q "$p"; then
        log_info "已mount，跳过: $p"
        continue
    fi

    # 大小已一致则跳过
    BEFORE_SIZE=$(wc -c < "$p" 2>/dev/null)
    if [ "$BEFORE_SIZE" = "$SRC_SIZE" ]; then
        log_info "大小已一致，跳过: $p"
        continue
    fi

    log_info "bind mount: $APK -> $p"
    mount --bind "$APK" "$p" 2>/dev/null
    rc=$?

    if [ $rc -eq 0 ]; then
        AFTER_SIZE=$(wc -c < "$p" 2>/dev/null)
        if [ "$AFTER_SIZE" = "$SRC_SIZE" ]; then
            log_info "成功: $p (${AFTER_SIZE}字节)"
            MOUNT_SUCCESS=$((MOUNT_SUCCESS + 1))
        else
            log_warn "mount成功但大小不一致: $p"
        fi
    else
        log_warn "mount失败(rc=$rc): $p"
    fi
done

log_info "post-fs-data统计: 成功=$MOUNT_SUCCESS"
log_info "========== post-fs-data.sh 执行完成 =========="
