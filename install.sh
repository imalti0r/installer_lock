# Flags
SKIPUNZIP=0
SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=false
REPLACE=""

##########################################################################################
# Installation
##########################################################################################

on_install() {
  if [ "$SKIPUNZIP" = "0" ]; then
    ui_print "- Extracting module files..."
    unzip -o "$ZIPFILE" -x "META-INF/*" "install.sh" -d "$MODPATH" >/dev/null 2>&1
  fi

  if [ -f "$MODPATH/customize.sh" ]; then
    ui_print "- Running customize.sh..."
    . "$MODPATH/customize.sh"
  fi
}

set_permissions() {
  set_perm_recursive "$MODPATH" 0 0 0755 0644

  # Ensure scripts are executable
  [ -f "$MODPATH/post-fs-data.sh" ] && set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
  [ -f "$MODPATH/service.sh" ] && set_perm "$MODPATH/service.sh" 0 0 0755
  [ -f "$MODPATH/customize.sh" ] && set_perm "$MODPATH/customize.sh" 0 0 0755

  # Ensure APK is readable
  [ -f "$MODPATH/custom_installer.apk" ] && set_perm "$MODPATH/custom_installer.apk" 0 0 0644

  # Ensure overlay files are readable
  if [ -d "$MODPATH/system" ]; then
    set_perm_recursive "$MODPATH/system" 0 0 0755 0644
  fi
}
