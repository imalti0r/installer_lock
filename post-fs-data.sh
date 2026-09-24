#!/system/bin/sh
# post-fs-data.sh - 早期bind mount MIUI安装器 + 隐藏旧vdex/odex编译缓存
# 不碰AOSP版，仅覆盖MIUI版

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
        continue
    fi

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
            log_info "APK mount成功: $p"
            MOUNT_SUCCESS=$((MOUNT_SUCCESS + 1))
            # 记录APK所在目录，用于后续处理oat
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

# ====== Step 2: 隐藏旧vdex/odex编译缓存 ======
# bind mount替换了APK文件，但系统预编译的vdex/odex还在
# 需要隐藏oat目录，强制系统从新APK重新编译
log_step "隐藏旧vdex/odex编译缓存"

OAT_HIDDEN=0
for d in $MOUNTED_DIRS; do
    if [ -z "$d" ]; then continue; fi

    OAT_DIR="$d/oat"
    if [ ! -d "$OAT_DIR" ]; then
        log_info "无oat目录: $OAT_DIR"
        continue
    fi

    # 列出oat目录内容
    log_info "发现oat目录: $OAT_DIR"
    ls -la "$OAT_DIR" 2>/dev/null | while read -r line; do
        log_info "  oat文件: $line"
    done

    # 挂载tmpfs到oat目录，隐藏所有旧编译缓存
    mount -t tmpfs tmpfs "$OAT_DIR" 2>/dev/null
    rc=$?
    if [ $rc -eq 0 ]; then
        log_info "tmpfs挂载成功: $OAT_DIR (旧vdex/odex已隐藏)"
        OAT_HIDDEN=$((OAT_HIDDEN + 1))
    else
        log_warn "tmpfs挂载失败(rc=$rc): $OAT_DIR"
        # 备用方案: 逐个bind mount空文件覆盖
        for f in "$OAT_DIR"/*/*; do
            if [ -f "$f" ]; then
                log_info "尝试覆盖: $f"
                mount --bind /dev/null "$f" 2>/dev/null && log_info "已覆盖: $f"
            fi
        done
        for f in "$OAT_DIR"/*; do
            if [ -f "$f" ]; then
                mount --bind /dev/null "$f" 2>/dev/null && log_info "已覆盖: $f"
            fi
        done
    fi
done

log_info "oat隐藏统计: 成功=$OAT_HIDDEN"

# ====== Step 3: 隐藏dalvik-cache中的旧缓存 ======
log_step "检查dalvik-cache"
DALVIK_CACHE="/data/dalvik-cache"
if [ -d "$DALVIK_CACHE" ]; then
    # 查找安装器相关的缓存文件
    CACHE_FILES=$(find "$DALVIK_CACHE" -name "*com.miui.packageinstaller*" -o -name "*MIUIPackageInstaller*" 2>/dev/null)
    for f in $CACHE_FILES; do
        if [ -f "$f" ]; then
            log_info "发现dalvik缓存: $f"
            mount --bind /dev/null "$f" 2>/dev/null && log_info "已隐藏: $f"
        fi
    done
fi

log_info "========== post-fs-data.sh 执行完成 =========="
