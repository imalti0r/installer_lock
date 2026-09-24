#!/system/bin/sh
# service.sh - 开机后确保MIUI安装器为自定义版本
# 策略: force-stop → bind mount APK + 隐藏oat → pm uninstall旧更新 → pm install → force-stop

MODDIR=${0%/*}
APK="$MODDIR/custom_installer.apk"
PKG="com.miui.packageinstaller"
LOGFILE="$MODDIR/module.log"
VERSION="v2.1.0"

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

# ====== Step 2: bind mount APK + 隐藏oat（开机后重试）======
log_step "开机后bind mount APK + 隐藏oat"

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
MOUNTED_DIRS=""

for p in $MIUI_PATHS; do
    if [ -z "$p" ] || [ ! -f "$p" ]; then continue; fi

    case "$p" in
        *MIUI*|*Miui*|*miui*) ;;
        *) continue ;;
    esac

    # APK bind mount
    if ! mount 2>/dev/null | grep -q "$p"; then
        CURRENT_SIZE=$(wc -c < "$p" 2>/dev/null)
        if [ "$CURRENT_SIZE" != "$SRC_SIZE" ]; then
            log_info "bind mount: $APK -> $p"
            mount --bind "$APK" "$p" 2>/dev/null
            rc=$?
            if [ $rc -eq 0 ]; then
                AFTER_SIZE=$(wc -c < "$p" 2>/dev/null)
                if [ "$AFTER_SIZE" = "$SRC_SIZE" ]; then
                    log_info "APK mount成功: $p"
                    MOUNT_SUCCESS=$((MOUNT_SUCCESS + 1))
                    APK_DIR=$(dirname "$p")
                    case "$MOUNTED_DIRS" in
                        *"$APK_DIR"*) ;;
                        *) MOUNTED_DIRS="$MOUNTED_DIRS $APK_DIR" ;;
                    esac
                else
                    log_warn "mount成功但大小不一致: $p"
                fi
            else
                log_warn "mount失败(rc=$rc): $p"
            fi
        else
            log_info "大小已一致，跳过: $p"
            APK_DIR=$(dirname "$p")
            case "$MOUNTED_DIRS" in
                *"$APK_DIR"*) ;;
                *) MOUNTED_DIRS="$MOUNTED_DIRS $APK_DIR" ;;
            esac
        fi
    else
        log_info "已mount，跳过: $p"
        APK_DIR=$(dirname "$p")
        case "$MOUNTED_DIRS" in
            *"$APK_DIR"*) ;;
            *) MOUNTED_DIRS="$MOUNTED_DIRS $APK_DIR" ;;
        esac
    fi
done

log_info "APK bind mount统计: 成功=$MOUNT_SUCCESS"

# 隐藏oat/vdex（开机后重试）
log_step "开机后隐藏oat/vdex缓存"
for d in $MOUNTED_DIRS; do
    if [ -z "$d" ]; then continue; fi
    OAT_DIR="$d/oat"
    if [ -d "$OAT_DIR" ]; then
        if ! mount 2>/dev/null | grep -q "$OAT_DIR"; then
            mount -t tmpfs tmpfs "$OAT_DIR" 2>/dev/null
            rc=$?
            if [ $rc -eq 0 ]; then
                log_info "tmpfs挂载成功: $OAT_DIR"
            else
                log_warn "tmpfs失败(rc=$rc): $OAT_DIR，尝试逐文件覆盖"
                for f in "$OAT_DIR"/*/* "$OAT_DIR"/*; do
                    if [ -f "$f" ]; then
                        mount --bind /dev/null "$f" 2>/dev/null && log_info "已覆盖: $f"
                    fi
                done
            fi
        else
            log_info "oat已挂载tmpfs: $OAT_DIR"
        fi
    fi
done

# ====== Step 3: 卸载旧的/data/app更新 + 重新安装 ======
log_step "pm install兜底"

# 先卸载/data层的旧安装（如果是更新安装的）
DATA_APK=$(pm path "$PKG" 2>/dev/null | grep "/data/" | head -n1 | sed 's/^package://' | tr -d '\r\n ')
if [ -n "$DATA_APK" ]; then
    log_info "发现/data层安装: $DATA_APK"
    log_info "先卸载旧更新..."
    pm uninstall -k "$PKG" 2>/dev/null
    rc=$?
    log_info "pm uninstall rc=$rc"
    sleep 1
fi

# 尝试安装
log_info "尝试 pm install -r -d"
INSTALL_OUTPUT=$(pm install -r -d "$APK" 2>&1)
INSTALL_RC=$?
log_info "输出: $INSTALL_OUTPUT | rc=$INSTALL_RC"

if [ $INSTALL_RC -ne 0 ]; then
    log_warn "pm install -r -d失败，尝试不带-d"
    INSTALL_OUTPUT2=$(pm install -r "$APK" 2>&1)
    INSTALL_RC2=$?
    log_info "输出: $INSTALL_OUTPUT2 | rc=$INSTALL_RC2"

    if [ $INSTALL_RC2 -ne 0 ]; then
        log_warn "pm install也失败(预期行为: 无核心破解时versionCode过低)"
        log_info "bind mount + oat隐藏应已生效，pm install非必需"
    else
        log_info "pm install -r成功"
    fi
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
        *) log_info "位于/product层(bind mount生效)" ;;
    esac
fi

log_info "========== service.sh 执行完成 =========="
