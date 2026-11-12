#!/bin/bash
#==============================================================================
# MRS Daily Briefing — v2.8 (2026-04-24 최종 확정 양식)
#
# Cron: 30 7 * * 1-5 (평일 07:30 KST)
# 방식: tg_regime_briefing() 직접 호출 (v2.8 — text + 3 charts)
#   Chart 1: Daily Regime Score (12M) — EWMA/Raw 2-line + Category 색띠
#   Chart 2: 3-Layer Signal (Month-end + Latest Daily) — MSM/KTRI/VEA + MRS Deep Purple
#   Chart 3: KTRI 9-Quadrant Map (252d)
#
# 전제: 06:30 regime_data_refresh.sh 선행 (MSM/FRED/KTRI/signal 갱신)
# Log: /tmp/qm_mrs_daily.log  (QVEST_MRS_LOG 로 덮어쓰기 — 검증 실행용 · 운영 = 기본값)
# 발송 없는 검증: QVEST_TG_DRY_RUN=1 (+ QVEST_FRESHNESS_QUIET=1) — 레짐 브리핑 · 스타일 브리핑 모두 본문만 로그에 남긴다.
#==============================================================================

set -u
LOG=${QVEST_MRS_LOG:-/tmp/qm_mrs_daily.log}
TS=$(date -Iseconds)
DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)

if [ -z "$DIR" ]; then
  echo "$TS [mrs_daily] PROJECT_ROOT not found" >> "$LOG"
  exit 1
fi

cd "$DIR"

# [분리 보호 2026-06-17 도훈] 상속된 QM_ROOT/CLAUDE_PROJECT_DIR가 별개 시스템(Qvest_Codex 등)을
#   가리키면 .tg_load_env()(CLAUDE_PROJECT_DIR→QM_ROOT 순)와 config.R가 잘못된 .env/캐시/차트 경로로
#   해석되어 원본 차트 미갱신 + 발송 채널 오염이 발생한다. 글로브로 확정한 원본 DIR로 강제 고정한다.
export QM_ROOT="$DIR"
export CLAUDE_PROJECT_DIR="$DIR"
export PYTHONUTF8=1

# 선행 cache 전제 체크 — 일간 regime signal 우선
REGIME_DAILY="$DIR/.cache/unified_regime_signal_daily.parquet"
REGIME_MONTHLY="$DIR/.cache/unified_regime_signal.parquet"

if [ ! -f "$REGIME_DAILY" ] && [ ! -f "$REGIME_MONTHLY" ]; then
  echo "$TS [mrs_daily] no regime signal cache — skip" >> "$LOG"
  exit 0
fi

# [2026-07-14 Q] 데이터-조건 게이트 — 실사고: 오늘 mrs가 07:12 발사(wake catch-up, 의도 07:30)
#   → DailyRefresh(07:15 완료) 前 vintage(07-10)로 KTRI 전전영업일 차트 발송("Neutral"),
#   07:15 신선 재빌드 실측은 KTRI 32.3 "Defensive Bias" — 국면 메시지가 실질적으로 달랐다.
#   시각-기반 대신 데이터-조건: 렌더 산출물 2개가 전영업일 도달까지 최대 30분(120s×15) 대기
#   → freshness_audit 재실행(as_of 순환성 수리판) → 아래 mrs_regime_send 자체 stale-게이트가
#   교정된 판정을 소비. 타임아웃 시에도 감사 재실행 후 진행(게이트가 보류·알림 판단).
#
# [2026-11-13 도훈 지시 "최신데이터로 계산되서 발송되게"] 기다리기만 하지 않고 따라잡는다.
#   실사고 11-13: RAWDATA 11-12 가 07:45 에 들어왔는데 KTRI v3 · 국면 원장은 아침 [2/5]·[3/5](07:16) 판 = 11-11 그대로였고,
#   이 관문은 30분을 기다리기만 하다 07:49 에 11-11 판 본문 · 차트를 보냈다. 생산자는 대기 중에 다시 불리지 않았다.
#   → 관문이 WAIT 이면 regime_catchup.R 이 '입력(RAWDATA · 벤치) 마지막 날짜 > 산출물 마지막 날짜' 일 때만 아침 체인과
#     같은 함수로 다시 만든다(실행 최대 CATCHUP_MAX 회). 리프레시 배리어(밤 리프레시 · RAWDATA writer 잠금)가 held 면 부르지 않는다
#     — 쓰는 중인 RAWDATA 를 읽지 않고, 진행 중인 리프레시가 같은 산출물을 스스로 다시 만든다(그때는 구판처럼 기다린다).
GATE="INIT"; CATCHUP_N=0; CATCHUP_MAX=2
_gate() { Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/regime_data_gate.R")' 2>/dev/null | tail -1; }
for _i in $(seq 1 15); do
  GATE=$(_gate)
  case "$GATE" in OK*) break ;; esac
  if [ "$CATCHUP_N" -lt "$CATCHUP_MAX" ]; then
    if bash "$DIR/02_Infrastructure/ops/refresh_barrier.sh" status >/dev/null 2>&1; then
      CU_OUT=$(Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/regime_catchup.R")' 2>&1)
      printf '%s\n' "$CU_OUT" >> "$LOG"
      CU=$(printf '%s\n' "$CU_OUT" | grep -a '^CATCHUP' | tail -1)
      echo "$(date -Iseconds) [mrs_daily] catch-up: ${CU:-CATCHUP 판독 불가(출력 없음)}" >> "$LOG"
      case "$CU" in
        "CATCHUP ran"*)
          CATCHUP_N=$((CATCHUP_N + 1))
          GATE=$(_gate)
          case "$GATE" in OK*) break ;; esac ;;
      esac
    else
      echo "$(date -Iseconds) [mrs_daily] catch-up 보류 — 리프레시 배리어 held(진행 중 갱신이 산출물을 다시 만든다)" >> "$LOG"
    fi
  fi
  echo "$(date -Iseconds) [mrs_daily] data-gate: $GATE (retry $_i/15)" >> "$LOG"
  sleep 120
done
echo "$(date -Iseconds) [mrs_daily] data-gate final: $GATE" >> "$LOG"
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/freshness_audit.R")' >> "$LOG" 2>&1

echo "$(date -Iseconds) [mrs_daily] start briefing v2.8 (run started $TS)" >> "$LOG"

# [외부화 2026-06-18 Q] 기존 멀티라인 `Rscript -e '...'` 블록은 Windows Git Bash 에서 첫 줄만
#   실행되는 함정(실증 확인)으로 레짐 브리핑 로직 전체가 no-op 되고 있었다(차트 미재생·발송 부재).
#   morning_steps/mrs_regime_send.R 로 분리 + 단일줄 source 호출로 회피(전 줄 실행 + UTF-8 정상).
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/mrs_regime_send.R")' >> "$LOG" 2>&1

# [2026-07-18 도훈 지시] 스타일 국면 브리핑(FF5+스마트베타+지수민감도) — MRS 뒤 sibling 발송 (v2.8 양식 불변).
#   실패해도 브리핑 본체 무영향. LC_ALL = 텔레그램 한글 PCRE 버그 방어(project-telegram-locale-pcre-korean).
LC_ALL="English_United States.utf8" Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/ff5_brief_send.R")' >> "$LOG" 2>&1

echo "$(date -Iseconds) [mrs_daily] done (run started $TS)" >> "$LOG"
exit 0
