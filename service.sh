#!/system/bin/sh
# service.sh - 开机后确保MIUI安装器为自定义版本
# 策略: force-stop → bind mount MIUI路径 → pm install → force-stop

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

log_info "========== service.sh ${VERSION} 开始执行 =========="

# 等待开机完成
log_step "等待sys.boot_completed=1"
WAIT_COUNT=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $((WAIT_COUNT % 15)) -eq 0 ]; then
        log_info "仍在等待... (${WAIT_COUNT}次=$((WAIT_COUNT * 2))秒)"
    fi
done
log_info "开机完成，耗时约$((WAIT_COUNT * 2))秒"

sleep 2
log_info "额外等待2秒"

if [ ! -f "$APK" ]; then
    log_error "APK不存在: $APK，退出"
    exit 0
fi

SRC_SIZE=$(wc -c < "$APK" 2>/dev/null)

# ====== Step 1: force-stop ======
log_step "force-stop安装器"
am force-stop "$PKG" 2>/dev/null

# ====== Step 2: bind mount MIUI路径 ======
log_step "开机后bind mount MIUI路径"

# pm path获取（过滤出MIUI版）
PM_PATHS=$(pm path "$PKG" 2>/dev/null | grep -v "/data/" | sed 's/^package://' | tr -d '\r\n ')

MIUI_PATHS="$PM_PATHS
/product/priv-app/MIUIPackageInstaller/MIUIPackageInstaller.apk
/product/priv-app/MIUIPackageInstaller/base.apk
/system/product/priv-app/MIUIPackageInstaller/MIUIPackageInstaller.apk
/system/product/priv-app/MIUIPackageInstaller/base.apk
/system/system_ext/priv-app/MiuiPackageInstaller/MiuiPackageInstaller.apk
/system/priv-app/MiuiPackageInstaller/MiuiPackageInstaller.apk
"

MOUNT_SUCCESS=0
for p in $MIUI_PATHS; do
    if [ -z "$p" ] || [ ! -f "$p" ]; then continue; fi

    # 只处理MIUI版路径
    case "$p" in
        *MIUI*|*Miui*|*miui*) ;;
        *) continue ;;
    esac

    if mount 2>/dev/null | grep -q "$p"; then
        log_info "已mount，跳过: $p"
        continue
    fi

    CURRENT_SIZE=$(wc -c < "$p" 2>/dev/null)
    if [ "$CURRENT_SIZE" = "$SRC_SIZE" ]; then
        log_info "大小已一致，跳过: $p"
        continue
    fi

    log_info "bind mount: $APK -> $p"
    mount --bind "$APK" "$p" 2>/dev/null
    rc=$?
    if [ $rc -eq 0 ]; then
        AFTER_SIZE=$(wc -c < "$p" 2>/dev/null)
        if [ "$AFTER_SIZE" = "$SRC_SIZE" ]; then
            log_info "成功: $p"
            MOUNT_SUCCESS=$((MOUNT_SUCCESS + 1))
        else
            log_warn "mount成功但大小不一致: $p"
        fi
    else
        log_warn "mount失败(rc=$rc): $p"
    fi
done

log_info "bind mount统计: 成功=$MOUNT_SUCCESS"

# ====== Step 3: pm install兜底 ======
log_step "pm install兜底"

log_info "尝试 pm install -r -d"
INSTALL_OUTPUT=$(pm install -r -d "$APK" 2>&1)
INSTALL_RC=$?
log_info "输出: $INSTALL_OUTPUT | rc=$INSTALL_RC"

if [ $INSTALL_RC -ne 0 ]; then
    log_warn "pm install -r -d失败，尝试不带-d"
    INSTALL_OUTPUT2=$(pm install -r "$APK" 2>&1)
    INSTALL_RC2=$?
    log_info "输出: $INSTALL_OUTPUT2 | rc=$INSTALL_RC2"
    [ $INSTALL_RC2 -eq 0 ] && log_info "pm install -r成功" || log_error "pm install也失败"
else
    log_info "pm install成功"
fi

# ====== Step 4: force-stop ======
log_step "最终force-stop"
am force-stop "$PKG" 2>/dev/null

# ====== 验证 ======
log_step "验证状态"
CURRENT_APK=$(pm path "$PKG" 2>/dev/null | head -n1 | sed 's/^package://' | tr -d '\r\n ')
if [ -n "$CURRENT_APK" ]; then
    log_info "当前路径: $CURRENT_APK"
    case "$CURRENT_APK" in
        /data/*) log_info "位于/data层(pm install生效)" ;;
        *) log_info "位于/system或/product层(bind mount生效)" ;;
    esac
fi

log_info "========== service.sh 执行完成 =========="
