#!/usr/bin/env bash
# 临时排查脚本：按环境变量开关多次运行桌面端，记录是否崩溃（exit 139）。
# 用法： ./probe.sh <标签> [ENV=1 ...]
EXE=./build/windows/x64/runner/Debug/cyrene_music_reborn.exe
LABEL=$1; shift
LOG=/tmp/probe_$LABEL.log
env "$@" timeout 25 $EXE >"$LOG" 2>&1
CODE=$?
FRAMES=$(grep -c 'frame#' "$LOG")
AX=$(grep -c 'Failed to update ui::AXTree' "$LOG")
SEM=$(grep -m1 'semanticsEnabled=' "$LOG" | tail -c 30)
case $CODE in
  139) VERDICT="CRASH(segv)" ;;
  124) VERDICT="ALIVE(timeout-ok)" ;;
  0)   VERDICT="exited-clean" ;;
  *)   VERDICT="exit=$CODE" ;;
esac
printf '%-16s %-18s frames=%-5s axErrors=%-4s %s\n' "$LABEL" "$VERDICT" "$FRAMES" "$AX" "$SEM"
