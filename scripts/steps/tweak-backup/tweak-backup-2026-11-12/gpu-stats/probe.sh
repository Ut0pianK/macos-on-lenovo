#!/bin/sh
OUT=/Users/user/tweak-backup-2026-11-12/gpu-stats/probe.out
/usr/sbin/dtrace -q -n '
fbt:com.apple.driver.AppleIntelTGLGraphics:*updateWithContextUtilizationData*:entry { @calls["updateWithContextUtilizationData calls"] = count(); }
fbt:com.apple.driver.AppleIntelTGLGraphics:*IGHardwareContext18getUtilizationData*:return { @ret["getUtilizationData return (tick delta)"] = quantize(arg1); }
fbt:com.apple.driver.AppleIntelTGLGraphics:*writePerformanceStats*:entry { @calls["writePerformanceStats calls"] = count(); @b["writePerformanceStats bool arg"] = lquantize(arg2 & 0xff, 0, 3, 1); }
fbt:com.apple.driver.AppleIntelTGLGraphics:*getStatisticsGlobalUsage*:entry { @calls["getStatisticsGlobalUsage calls"] = count(); }
fbt:com.apple.driver.AppleIntelTGLGraphics:*IGTelemetryUsage8logUsage*:entry { @calls["logUsage calls"] = count(); @lu["logUsage runtime arg"] = quantize(arg2); }
tick-12s { exit(0); }' > "$OUT" 2>&1
echo "exit $?" >> "$OUT"
