#!/bin/bash
# morning_run.sh — Consolidated boot-resilient morning runner (도훈 mandate 2026-06-01, 일원화 ②③)
#
# 목적: 머신이 07:10 cron 시각에 꺼져 있어도(늦게 부팅) 그날 1회 모닝 파이프라인을 실행한다.
#   - once-per-day 락: @reboot 트리거 + 정시 cron 둘 다 등록해도 하루 1회만 실행.
#   - 머신이 07:10 이후 부팅 → @reboot가 catch (정시 cron은 이미 지나 미발화) → 그래도 실행됨.
#   - 순서: morning_briefing.sh (데이터 refresh + P3 brief, B-게이트 적용) → mrs_daily_briefing.sh (레짐 brief).
#   - 기존 3개 morning cron(07:10 P3 / 07:30 레짐 / 00:03 refresh)을 본 러너 하나로 통합.
#
# crontab (morning_run.sh 단일 진입):
#   @reboot      sleep 150 && bash .../02_Infrastructure/ops/morning_run.sh reboot
#   10 7 * * 1-5 bash .../02_Infrastructure/ops/morning_run.sh cron

BASE=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
LOG="/tmp/qm_morning_run.log"
TRIGGER="${1:-manual}"
TODAY=$(date +%Y%m%d)
LOCK="/tmp/qm_morning_run_${TODAY}.lock"
DOW=$(date +%u)   # 1=Mon .. 7=Sun

{
  echo "================ morning_run @ $(date) (trigger=${TRIGGER}) ================"

  # 1) 주말 skip (KR 영업일만)
  if [ "$DOW" -ge 6 ]; then
    echo "weekend (dow=$DOW) — skip"
    exit 0
  fi

  # 2) once-per-day 락 (atomic). 이미 오늘 실행됐으면 skip → @reboot+cron 중복 방지
  if ! ( set -o noclobber; echo "$$ @ $(date) trigger=$TRIGGER" > "$LOCK" ) 2>/dev/null; then
    echo "already ran today ($LOCK exists) — skip"
    exit 0
  fi
  # 오래된 락 정리 (7일+)
  find /tmp -maxdepth 1 -name "qm_morning_run_*.lock" -mtime +7 -delete 2>/dev/null || true

  cd "$BASE" || { echo "BASE not found: $BASE"; exit 1; }

  echo "[1/2] morning_briefing.sh (데이터 refresh + P3 brief)"
  bash "$BASE/02_Infrastructure/ops/morning_briefing.sh" >> /tmp/qm_morning.log 2>&1
  echo "      morning_briefing exit=$?"

  echo "[2/2] mrs_daily_briefing.sh (레짐 brief)"
  bash "$BASE/02_Infrastructure/ops/mrs_daily_briefing.sh" >> /tmp/qm_mrs_daily.log 2>&1
  echo "      mrs_daily exit=$?"

  echo "================ morning_run done @ $(date) ================"
} >> "$LOG" 2>&1
