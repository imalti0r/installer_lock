#!/system/bin/sh
# post-fs-data.sh - 早期bind mount MIUI安装器 + 删除旧编译缓存
# 策略: bind mount APK → 删除dalvik-cache旧缓存 → 删除oat旧缓存

MODDIR=${0%/*}
APK="$MODDIR/custom_installer.apk"
PKG="com.miui.packageinstaller"
LOGFILE="$MODDIR/module.log"
VERSION="v2.2.0"

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

# ====== Step 1: bind mount APK ======
log_step "bind mount MIUI安装器APK"

MOUNT_SUCCESS=0
MOUNTED_DIRS=""

for p in $MIUI_PATHS; do
    if [ ! -f "$p" ]; then continue; fi

    if mount 2>/dev/null | grep -q "$p"; then
        log_info "已mount，跳过: $p"
        APK_DIR=$(dirname "$p")
        case "$MOUNTED_DIRS" in
            *"$APK_DIR"*) ;;
            *) MOUNTED_DIRS="$MOUNTED_DIRS $APK_DIR" ;;
        esac
        continue
    fi

    BEFORE_SIZE=$(wc -c < "$p" 2>/dev/null)
    if [ "$BEFORE_SIZE" = "$SRC_SIZE" ]; then
        log_info "大小已一致，跳过: $p"
        APK_DIR=$(dirname "$p")
        case "$MOUNTED_DIRS" in
            *"$APK_DIR"*) ;;
            *) MOUNTED_DIRS="$MOUNTED_DIRS $APK_DIR" ;;
        esac
        continue
    fi

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
done

log_info "APK bind mount统计: 成功=$MOUNT_SUCCESS"

# ====== Step 2: 删除dalvik-cache中的旧编译缓存 ======
# bind /dev/null只是隐藏文件，系统看到空文件仍可能崩溃
# 直接删除让系统从新APK重新编译
log_step "删除dalvik-cache旧编译缓存"

DALVIK_CACHE="/data/dalvik-cache"
CACHE_DELETED=0

if [ -d "$DALVIK_CACHE" ]; then
    # 搜索所有架构子目录中的相关缓存
    # 缓存文件名格式: product@priv-app@MIUIPackageInstaller@MIUIPackageInstaller.apk@classes.dex
    # 或: data@app@com.miui.packageinstaller-xxx@base.apk@classes.dex
    CACHE_FILES=$(find "$DALVIK_CACHE" -type f \( -name "*MIUIPackageInstaller*" -o -name "*MiuiPackageInstaller*" -o -name "*com.miui.packageinstaller*" \) 2>/dev/null)

    for f in $CACHE_FILES; do
        if [ -f "$f" ]; then
            FSIZE=$(wc -c < "$f" 2>/dev/null)
            log_info "发现缓存: $f (${FSIZE}字节)"
            rm -f "$f" 2>/dev/null
            if [ ! -f "$f" ]; then
                log_info "已删除: $f"
                CACHE_DELETED=$((CACHE_DELETED + 1))
            else
                log_warn "删除失败，尝试bind /dev/null: $f"
                mount --bind /dev/null "$f" 2>/dev/null && log_info "已bind隐藏: $f"
            fi
        fi
    done
else
    log_info "无dalvik-cache目录"
fi

log_info "dalvik-cache清理统计: 删除=$CACHE_DELETED"

# ====== Step 3: 删除oat目录中的旧编译缓存 ======
log_step "清理oat目录"

OAT_CLEANED=0
for d in $MOUNTED_DIRS; do
    if [ -z "$d" ]; then continue; fi

    OAT_DIR="$d/oat"
    if [ ! -d "$OAT_DIR" ]; then
        log_info "无oat目录: $OAT_DIR"
        continue
    fi

    log_info "发现oat目录: $OAT_DIR"
    # 列出oat内容
    find "$OAT_DIR" -type f 2>/dev/null | while read -r f; do
        log_info "  oat文件: $f ($(wc -c < "$f" 2>/dev/null)字节)"
    done

    # 尝试删除整个oat目录内容
    rm -rf "$OAT_DIR"/* 2>/dev/null
    if [ $? -eq 0 ]; then
        log_info "oat目录已清空: $OAT_DIR"
        OAT_CLEANED=$((OAT_CLEANED + 1))
    else
        log_warn "oat删除失败，尝试tmpfs隐藏: $OAT_DIR"
        mount -t tmpfs tmpfs "$OAT_DIR" 2>/dev/null && log_info "tmpfs挂载成功: $OAT_DIR"
    fi
done

log_info "oat清理统计: 清理=$OAT_CLEANED"

# ====== Step 4: 清理/data/app中的旧更新安装（如果有）======
log_step "检查/data/app旧更新"
# 删除/data/app中可能残留的旧安装器更新
# pm path会返回/data/app路径如果有更新安装
DATA_APK=$(pm path "$PKG" 2>/dev/null | grep "/data/" | head -n1 | sed 's/^package://' | tr -d '\r\n ')
if [ -n "$DATA_APK" ]; then
    log_info "发现/data/app旧安装: $DATA_APK"
    # 尝试卸载（保留系统版）
    pm uninstall -k "$PKG" 2>/dev/null
    rc=$?
    log_info "pm uninstall rc=$rc"
else
    log_info "无/data/app旧安装"
fi

log_info "========== post-fs-data.sh 执行完成 =========="
