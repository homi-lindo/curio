#!/usr/bin/env bash
# Polls the Android emulator running inside WSL for boot_completed=1.
ADB="$HOME/Android/Sdk/platform-tools/adb"
for i in $(seq 1 60); do
  state=$("$ADB" -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
  if [ "$state" = "1" ]; then
    echo "boot ok after $((i * 10))s"
    "$ADB" devices -l
    "$ADB" -s emulator-5554 shell getprop ro.build.version.sdk
    exit 0
  fi
  sleep 10
done
echo "timeout waiting for boot_completed"
tail -20 /tmp/emu.log 2>/dev/null
exit 1
