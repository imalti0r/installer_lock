#!/system/bin/sh
# service.sh - 开机后pm install覆盖安装自定义安装器
# 策略: 等开机 → pm uninstall旧更新 → pm install -r -d → force-stop → 验证
# 需要核心破解(LSPosed)禁用签名校验才能覆盖系统应用

MODDIR=${0%/*}
APK="$MODDIR/custom_installer.apk"
PKG="com.miui.packageinstaller"
LOGFILE="$MODDIR/module.log"
VERSION="v3.0.0"

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

# ====== Step 1: 等待开机完成 ======
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

sleep 3
log_info "额外等待3秒供包管理器初始化"

if [ ! -f "$APK" ]; then
    log_error "APK不存在: $APK，退出"
    exit 0
fi

APK_SIZE=$(wc -c < "$APK" 2>/dev/null)
log_info "APK大小: ${APK_SIZE}字节"

# ====== Step 2: force-stop ======
log_step "force-stop安装器"
am force-stop "$PKG" 2>/dev/null

# ====== Step 3: 卸载旧的/data/app更新 ======
log_step "检查/data/app旧更新"
DATA_APK=$(pm path "$PKG" 2>/dev/null | grep "/data/" | head -n1 | sed 's/^package://' | tr -d '\r\n ')
if [ -n "$DATA_APK" ]; then
    log_info "发现/data层安装: $DATA_APK，先卸载"
    pm uninstall -k "$PKG" 2>/dev/null
    log_info "pm uninstall完成"
    sleep 1
else
    log_info "无/data/app旧安装"
fi

# ====== Step 4: pm install覆盖安装 ======
log_step "pm install覆盖安装"

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
        log_error "pm install也失败，需要核心破解(LSPosed)支持"
    else
        log_info "pm install -r成功"
    fi
else
    log_info "pm install成功"
fi

# ====== Step 5: force-stop ======
log_step "最终force-stop"
am force-stop "$PKG" 2>/dev/null

# ====== 验证 ======
log_step "验证状态"
CURRENT_APK=$(pm path "$PKG" 2>/dev/null | head -n1 | sed 's/^package://' | tr -d '\r\n ')
if [ -n "$CURRENT_APK" ]; then
    log_info "当前路径: $CURRENT_APK"
    case "$CURRENT_APK" in
        /data/*) log_info "位于/data层(pm install生效) ✓" ;;
        *) log_warn "位于/system/product层(pm install未生效)" ;;
    esac
fi

log_info "========== service.sh 执行完成 =========="
