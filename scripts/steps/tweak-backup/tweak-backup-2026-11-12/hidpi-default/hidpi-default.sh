#!/bin/sh
W=/Users/user/tweak-backup-2026-11-12/hidpi-default
DST=/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-9e5/DisplayProductID-931
case "$1" in
  apply)  cp "$W/DisplayProductID-931.new" "$DST" ;;
  apply2) cp "$W/DisplayProductID-931.new2" "$DST" ;;
  undo)   cp "$W/DisplayProductID-931.orig" "$DST" ;;
  *) echo "usage: $0 apply|apply2|undo"; exit 1 ;;
esac
chown root:wheel "$DST"; chmod 644 "$DST"
plutil -lint "$DST"
