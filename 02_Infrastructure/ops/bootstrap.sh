#!/bin/bash
#==============================================================================
# bootstrap.sh — Qvest v53 부트스트랩
# 새 Claude Code 세션에서 1회 실행. 단일 Q-Lead 세션 전제.
#
# v53 아키텍처:
#   - tmux 4-pane / supervisor 구조 폐기 (qvest.md 참조)
#   - Q-Lead 세션 내 TeamCreate + Hook 자동 발동으로 운영
#   - tmux "rc" (persistent remote control)만 유지
#
# Usage: bash 02_Infrastructure/ops/bootstrap.sh
#==============================================================================

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
# (v8.1.2) 자기 파일 절대경로 — cd 이전에 확정 (worktree/사본 테스트 시 utf8 가드 재실행이 canonical 본으로 새는 것 방지)
SELF_BOOTSTRAP="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"
cd "$PROJECT"

# Windows-native (2026-06-04): R/python이 인식하는 경로로 CLAUDE_PROJECT_DIR/QM_ROOT export.
# cygpath -m → G:/Quant_Module_Moltbot (Windows mixed). R file.exists + python open 둘 다 OK.
# (POSIX /g/는 python open() 실패. WSL/Linux엔 cygpath 없어 $PROJECT fallback = /mnt/g 정상.)
export CLAUDE_PROJECT_DIR="$(cygpath -m "$PROJECT" 2>/dev/null || echo "$PROJECT")"
export QM_ROOT="${QM_ROOT:-$CLAUDE_PROJECT_DIR}"
export PYTHONUTF8=1   # Windows python 기본 cp949 → UTF-8 강제 (PG2/readiness UnicodeDecodeError 방지, 2026-06-04)

# (v8.1.1 2026-06-10) 도구 체인 가드 — Rscript/python3 PATH 보정 + 부재 시 명시 카운트 (침묵 실패 금지)
BOOT_FAILS=0
if ! command -v Rscript >/dev/null 2>&1; then
  [ -d "/c/Program Files/R/R-4.5.2/bin" ] && export PATH="/c/Program Files/R/R-4.5.2/bin:$PATH"
fi
if ! python3 -c 'import sys' >/dev/null 2>&1; then
  [ -d "/c/Users/99922/AppData/Local/Programs/Python/Python312" ] && export PATH="/c/Users/99922/AppData/Local/Programs/Python/Python312:$PATH"
fi

# (v8.1.2 2026-06-11) UTF-8 출력 가드 — Claude Code API 400 'invalid high surrogate' 차단.
#   부트 전체 출력(자식 R/Python/백그라운드 포함)을 utf8_output_guard.py로 정제하는 1회 재실행 래퍼:
#   invalid UTF-8 byte + non-BMP 문자(U+10000+, Claude Code 30k자 절단 시 surrogate pair가 갈라져
#   lone surrogate -> RFC 8259 위반 -> API 400)를 '?'로 치환. 근거: anthropics/claude-code#44230 + #16294.
#   python3 부재 시 무가드 진행 (아래 INACTIVE WARN 표시). 임의 커맨드용 래퍼는 ops/safe_run.sh.
UTF8_GUARD="$PROJECT/02_Infrastructure/ops/utf8_output_guard.py"
if [ -z "${QVEST_BOOT_SANITIZED:-}" ]; then
  if [ -f "$UTF8_GUARD" ] && python3 -c 'import sys' >/dev/null 2>&1; then
    # "pipe:$$" — 외부에서 임의로 1을 export해 가드를 우회하고도 ACTIVE로 오표시되는 것 방지
    export QVEST_BOOT_SANITIZED="pipe:$$"
    bash "${SELF_BOOTSTRAP:-$PROJECT/02_Infrastructure/ops/bootstrap.sh}" "$@" 2>&1 \
      | python3 -u "$(cygpath -m "$UTF8_GUARD" 2>/dev/null || echo "$UTF8_GUARD")"
    exit "${PIPESTATUS[0]}"
  fi
  export QVEST_BOOT_SANITIZED=skip
fi

export QVEST_PY="${QVEST_PY:-$(command -v python3 2>/dev/null || echo python3)}"
command -v Rscript >/dev/null 2>&1 && RS_OK="OK" || { RS_OK="MISSING"; BOOT_FAILS=$((BOOT_FAILS+1)); }
python3 -c 'import sys' >/dev/null 2>&1 && PY_OK="OK" || { PY_OK="MISSING_OR_STUB"; BOOT_FAILS=$((BOOT_FAILS+1)); }
echo "[boot] 도구 체인: Rscript=$RS_OK python3=$PY_OK (QVEST_PY=$QVEST_PY)"
case "${QVEST_BOOT_SANITIZED:-}" in
  pipe:*) echo "[boot] utf8_output_guard: ACTIVE (non-BMP/invalid-byte 출력 정제 — API 400 surrogate 방지)" ;;
  *)      echo "[boot] WARN: utf8_output_guard INACTIVE (python3/guard 부재 또는 외부 QVEST_BOOT_SANITIZED 선점) — 이모지 포함 출력 시 API 400 위험" ;;
esac

echo "=== Qvest v8.1 부트스트랩 (Opus 4.8 Native · 4-Mode +RAMP) ==="

# 1. (제거됨 v8.0 2026-05-29) tmux rc telegram inbound listener — outbound tg_agent_brief()는
#    영향 없음. inbound 명령 listener 불필요 판단(도훈). 필요 시 persistent_remote_control.sh 수동 기동.

# 2. Legacy tmux 세션 정리 (v50/v52 잔재 — research/supervisor)
#    삭제는 QVEST_KEEP_LEGACY_TMUX=1 환경변수로 억제 가능
if [ "${QVEST_KEEP_LEGACY_TMUX:-0}" != "1" ]; then
  for legacy in research supervisor; do
    if tmux has-session -t "$legacy" 2>/dev/null; then
      tmux kill-session -t "$legacy" 2>/dev/null
      echo "[boot] legacy tmux 세션 종료: $legacy"
    fi
  done
fi

# 3. Cleanup (위생 관리, 백그라운드)
#    (v8.1.2) stdout도 로그로 — 미리다이렉트 시 비동기 출력이 부트 출력에 끼어들고
#    utf8 guard 파이프를 cleanup 종료까지 물고 있는 문제(du -sh 수 분 소요 가능) 방지.
bash "$PROJECT/02_Infrastructure/ops/cleanup.sh" --execute >/tmp/qm_cleanup_boot.log 2>&1 &
echo "[boot] Cleanup 백그라운드 (log=/tmp/qm_cleanup_boot.log)"

# 3b. Alpha Search 논문풀 일일 적재 (첫 실행 1회, 백그라운드)
#     고정 시각 의존 대신 bootstrap/morning_run 양쪽에서 동일 daily stamp를 공유한다.
PAPER_RECHARGE_SH="$PROJECT/02_Infrastructure/ops/paper_recharge_daily.sh"
if [ "${QVEST_PAPER_RECHARGE_SKIP:-0}" != "1" ] && [ -f "$PAPER_RECHARGE_SH" ]; then
  bash "$PAPER_RECHARGE_SH" >/tmp/qm_paper_recharge_boot.log 2>&1 &
  echo "[boot] paper_recharge_daily 백그라운드 (log=/tmp/qm_paper_recharge_boot.log)"
fi

# 4. Memory Knowledge Health Gate (v7.2.1 — hard 6 + warning 6)
#    Foreground: hard fail 즉시 표시. axiom SOT 3축 cross-check (sot_map↔active JSON↔.claude/rules/axioms.md)
#    + promote helper selftest + cache_core STALE 감지를 한 번에 처리.
MKH_R="$PROJECT/02_Infrastructure/memory/memory_knowledge_health.R"
if [ -f "$MKH_R" ]; then
  MKH_OUT=$(cd "$PROJECT" && Rscript "$MKH_R" 2>&1 || true)
  MKH_HARD=$(echo "$MKH_OUT" | grep -oE 'Hard fails: [0-9]+' | awk '{print $3}')
  MKH_WARN=$(echo "$MKH_OUT" | grep -oE 'Warnings: +[0-9]+' | awk '{print $2}')
  MKH_INFO=$(echo "$MKH_OUT" | grep -oE 'Infos: +[0-9]+' | awk '{print $2}')
  echo "[boot] Memory health: hard=${MKH_HARD:-?} warn=${MKH_WARN:-?} info=${MKH_INFO:-?}"
  if [ "${MKH_HARD:-99}" != "0" ]; then
    echo "[boot] ERROR: memory_knowledge_health HARD FAIL — Q-Lead 즉시 수정 (qepm/observability/memory_health_latest.json 참조)"
    echo "$MKH_OUT" | grep -E '\[HARD FAIL\]' | head -10
    BOOT_FAILS=$((BOOT_FAILS+1))
  fi
else
  echo "[boot] Memory health: SKIP (memory_knowledge_health.R 부재)"
fi

# 4b. memory_metadata_normalize selftest (v7.2.1 — fallback chain hard fail)
MMN_R="$PROJECT/02_Infrastructure/memory/memory_metadata_normalize.R"
if [ -f "$MMN_R" ]; then
  MMN_OUT=$(cd "$PROJECT" && Rscript "$MMN_R" selftest 2>&1 || true)
  if echo "$MMN_OUT" | grep -q 'selftest 2/2 PASS'; then
    echo "[boot] memory_metadata_normalize selftest 2/2 PASS"
  else
    echo "[boot] WARN: memory_metadata_normalize selftest FAIL — promote helper 호환 위반 가능"
  fi
fi

# 4c. lcode_corpus rebuild (v7.2.1 — 4 source 통합, 백그라운드)
LCR_R="$PROJECT/02_Infrastructure/memory/lcode_corpus_rebuild.R"
if [ -f "$LCR_R" ]; then
  # (v8.1.2) redirect를 subshell 전체에 — 내부 커맨드에만 붙이면 subshell이 utf8 guard 파이프
  # write-end를 물고 있어 부트가 백그라운드 job 종료까지 블로킹됨 (아래 5/6b 동일)
  (cd "$PROJECT" && Rscript "$LCR_R") >/tmp/lcode_corpus_boot.log 2>&1 &
  echo "[boot] lcode_corpus_rebuild 백그라운드 (log=/tmp/lcode_corpus_boot.log)"
fi

# 4d. Bear date audit (Cycle 51 — forward label semantics regression detector)
#     data.table::shift(-H, lead) backward bug 회귀 방지. 4 known bear dates
#     (Lehman / Euro / COVID / Stagflation) forward label match + backward mismatch 검증.
#     Hard fail (status=1) 시 bearish forecast model 영역 차단 (V10 / V1aV3 monitor).
#     bear_date_audit_latest.json은 qepm/observability/sanity_checks/ 저장.
BEAR_AUDIT_R="$PROJECT/02_Infrastructure/sanity_checks/bear_date_audit.R"
TARGET_PARQUET="$PROJECT/04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/02_targets/targets_full.parquet"
if [ -f "$BEAR_AUDIT_R" ] && [ -f "$TARGET_PARQUET" ]; then
  BEAR_OUT=$(cd "$PROJECT" && Rscript "$BEAR_AUDIT_R" 2>&1)
  BEAR_SUMMARY=$(echo "$BEAR_OUT" | grep -E "Audit Summary:" | head -1)
  echo "[boot] $BEAR_SUMMARY"
  if echo "$BEAR_OUT" | grep -q "ALL PASS"; then
    echo "[boot] bear_date_audit: ALL PASS (forward label semantics CLEAN)"
  else
    echo "[boot] WARN: bear_date_audit FAIL — backward label bug suspected"
    echo "[boot] Refer to: 04_Research/decision_framework/bearish_forecast_v2_alt_data/STATUS_BUGGY_ERA.md"
    echo "$BEAR_OUT" | grep -E "FAIL$" | head -5
  fi
else
  echo "[boot] bear_date_audit: SKIP (script or target parquet 미존재)"
fi

# 4e. (v8.1) 데이터 캐시 + 유니버스 멤버십 검증 — alpha-search universe=K200_KQ150 런타임 stop 방지.
#      schema만 읽어 빠름(전체 load X). Foreground (Critical 부팅 게이트, Agent3 분석).
RAWDATA_PARQUET="$PROJECT/.cache/rawdata.parquet"
if [ -f "$RAWDATA_PARQUET" ]; then
  RD_CHECK=$(cd "$PROJECT" && Rscript -e 'suppressMessages(library(arrow)); d<-tryCatch(read_parquet(".cache/rawdata.parquet", col_select=c("K200","KQ150")), error=function(e) NULL); cat(if(!is.null(d)) "K200_KQ150_OK" else "K200_KQ150_MISSING")' 2>/dev/null | grep -oE 'K200_KQ150_(OK|MISSING)')
  if [ "$RD_CHECK" = "K200_KQ150_OK" ]; then
    echo "[boot] 데이터 캐시: rawdata.parquet OK + K200/KQ150 멤버십 OK (alpha-search universe=K200_KQ150 가용)"
  else
    echo "[boot] WARN: rawdata.parquet K200/KQ150 컬럼 부재 — alpha-search universe=K200_KQ150 런타임 stop 위험 (daily_refresh apply_universe_mapping Layer2 활성화 필요)"
  fi
else
  echo "[boot] WARN: rawdata.parquet 부재 — alpha-search/backtest stop 위험 (build_cache.R 또는 daily_refresh 선행)"
fi
# kr_factor_returns_v2 신선도 (FF3 회귀 의존 — value 2002-08~)
KRF_V2="$PROJECT/.cache/kr_factor_returns_v2.parquet"
if [ -f "$KRF_V2" ]; then
  KRF_AGE=$(( ($(date +%s) - $(stat -c %Y "$KRF_V2" 2>/dev/null || echo 0)) / 86400 ))
  echo "[boot] kr_factor_returns_v2: OK (age ${KRF_AGE}d · MKT/SMB 2001-04~ · HML/RMW/CMA 2002-08~)"
else
  echo "[boot] WARN: kr_factor_returns_v2 부재 — FF 알파/residual momentum 전략 불가"
fi

# 4f. (감사 SC-01/SC-06, 2026-07-03) Gap vector 신선도 — WARN-only (블록 아님).
#     stale = 부재 / mtime 30일+ / n_strategies=0 (콜드스타트 잔재).
#     재생성: Rscript로 02_Infrastructure/portfolio/gap_vector_steering.R source 후 steer_gap_vector()
GAPV="$PROJECT/.cache/portfolio_gap_vector.json"
if [ ! -f "$GAPV" ]; then
  echo "[boot] WARN: portfolio_gap_vector.json 부재 — 탐색 조향 신호 없음 (gap_vector_steering.R::steer_gap_vector() 재생성 권장)"
else
  GAPV_AGE=$(( ($(date +%s) - $(stat -c %Y "$GAPV" 2>/dev/null || echo 0)) / 86400 ))
  GAPV_N0=$(grep -c '"n_strategies"[[:space:]]*:[[:space:]]*0' "$GAPV" 2>/dev/null || true)
  if [ "$GAPV_AGE" -gt 30 ] || [ "${GAPV_N0:-0}" -gt 0 ]; then
    echo "[boot] WARN: portfolio_gap_vector.json STALE (age ${GAPV_AGE}d$([ "${GAPV_N0:-0}" -gt 0 ] && echo ' + n_strategies=0')) — gap_vector_steering.R::steer_gap_vector() 재생성 권장"
  else
    echo "[boot] Gap vector: OK (age ${GAPV_AGE}d)"
  fi
fi

# 4g. (2026-07-04 Cleaner) 주간 증류 대기 마커 — weekly_cleaner_sweep(토 09:00 무인 기계 스윕)가
#     남긴 cleaner_pending.json(awaiting_distill) 감지 시 /cleaner 증류 안내. WARN-only.
CLEANER_PENDING="$PROJECT/.cache/cleaner_pending.json"
if [ -f "$CLEANER_PENDING" ] && grep -q '"status"[[:space:]]*:[[:space:]]*"awaiting_distill"' "$CLEANER_PENDING"; then
  echo "[boot] WARN: [cleaner] 주간 증류 대기 (cleaner_pending.json awaiting_distill) — /cleaner 실행 (기계 스윕 완료·엑기스 증류/L-code 적립/잔재 삭제 미완)"
fi

# 5. 데이터 리프레시 (백그라운드 — xlsx 증분 + KRX/FRED/ECOS)
REFRESH_LOG="/tmp/qm_boot_refresh_$(date +%Y%m%d_%H%M).log"
(cd "$PROJECT/02_Infrastructure" && bash "$PROJECT/02_Infrastructure/data/daily_refresh.sh") > "$REFRESH_LOG" 2>&1 &
REFRESH_PID=$!
echo "[boot] 데이터 리프레시 백그라운드 (PID=$REFRESH_PID, log=$REFRESH_LOG)"

# 6. v53 Axiom 엔진 주간 갱신 (백그라운드, 빠른 실행)
QVEST_PROJECT_DIR="$PROJECT" \
  python3 "$PROJECT/02_Infrastructure/axiom/lcode_harvester.py" >/tmp/axiom_boot.log 2>&1 &
echo "[boot] L-code harvester 백그라운드"

# 6b. v8.0 axiom weekly pipeline (지난 weekly_report 7일+ 경과 시 — Windows cron 대체)
LAST_W=$(ls -t "$PROJECT"/qepm/memory/axioms/review_log/weekly_report_*.json 2>/dev/null | head -1)
LASTW_T=0; [ -n "$LAST_W" ] && LASTW_T=$(stat -c %Y "$LAST_W" 2>/dev/null || echo 0)
if [ $(( ($(date +%s) - LASTW_T) / 86400 )) -ge 7 ]; then
  (cd "$PROJECT" && bash "$PROJECT/02_Infrastructure/ops/axiom_weekly.sh") >/tmp/axiom_weekly_boot.log 2>&1 &
  echo "[boot] axiom_weekly 파이프라인 백그라운드 (7일+ 경과)"
fi

# 7. Hook health check (v8.1.1 — 침묵 삼킴 금지: 빈 결과 = ERROR)
HH_OUT=$(bash "$PROJECT/02_Infrastructure/hooks/harness_health.sh" 2>&1)
HH_SUMMARY=$(echo "$HH_OUT" | grep -E "Result:" | head -1)
if [ -z "$HH_SUMMARY" ]; then
  echo "[boot] ERROR: harness_health 실행 불가 — hook 전수 점검 필요 (첫 줄: $(echo "$HH_OUT" | head -1))"
  BOOT_FAILS=$((BOOT_FAILS+1))
else
  echo "[boot] $HH_SUMMARY"
fi

# 7a. (v8.1.1 2026-06-10) Hook 카나리아 — 보호선 실작동 실증 (46-hook 전수 침묵사망 사건 재발 방지)
#     인터프리터+스크립트 레이어 검증. settings.json dispatch 레이어는 앱 재시작 후 /tmp 로그로 별도 확인.
CANARY_OUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/05_Production/_canary_test.R","content":"x"}}' "$CLAUDE_PROJECT_DIR" | bash "$PROJECT/02_Infrastructure/hooks/safety_guard.sh" 2>/dev/null)
if echo "$CANARY_OUT" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
  echo "[boot] Hook 카나리아: safety_guard BLOCK 정상 (보호선 실작동)"
else
  echo "[boot] ERROR: Hook 카나리아 FAIL — safety_guard가 05_Production Write를 차단 못 함 (출력: ${CANARY_OUT:-empty}). python3/_shared_parse 점검!"
  BOOT_FAILS=$((BOOT_FAILS+1))
fi

# 7b. v1.2 Charter §10 Measurement Coherence Health Score (Component D)
BS_PATH="$PROJECT/qepm/mailbox/governor/book_state.json"
MBA_R="$PROJECT/02_Infrastructure/portfolio/measurement_basis_audit.R"
MBA_TIER=""
if [ -f "$BS_PATH" ] && [ -f "$MBA_R" ]; then
  MBA_OUT=$(Rscript "$MBA_R" "$BS_PATH" "$PROJECT/qepm/mailbox/worktask" 2>/dev/null \
            | grep -E "(Book score:|Tier:)" | head -2 | tr '\n' ' ')
  if [ -n "$MBA_OUT" ]; then
    echo "[boot] Measurement coherence: $MBA_OUT"
    MBA_TIER=$(echo "$MBA_OUT" | grep -oE 'Tier: [A-Z]+' | awk '{print $2}' | head -1)
  else
    echo "[boot] Measurement coherence: SKIP (no admitted_ids or audit error)"
  fi
fi

# 7c. Layer 2 — DRIFTED/WARNING 감지 시 cert backfill audit auto 호출
CERT_BACKFILL_R="$PROJECT/02_Infrastructure/ops/cert_backfill_audit.R"
if [[ "$MBA_TIER" == "DRIFTED" || "$MBA_TIER" == "WARNING" ]] && [ -f "$CERT_BACKFILL_R" ]; then
  echo "[boot] Coherence $MBA_TIER detected — cert_backfill_audit.R --auto 호출"
  BACKFILL_OUT=$(cd "$PROJECT" && Rscript "$CERT_BACKFILL_R" --auto 2>&1)
  ISSUED_COUNT=$(echo "$BACKFILL_OUT" | grep -c '\[ISSUED\]' || true)
  PASS_AUTO_COUNT=$(echo "$BACKFILL_OUT" | grep -c '\[PASS_AUTO\]' || true)
  POST_TIER=$(echo "$BACKFILL_OUT" | grep -oE 'Tier: [A-Z]+' | tail -1 | awk '{print $2}')
  echo "[boot] Backfill: $ISSUED_COUNT cert(s) issued | $PASS_AUTO_COUNT pass_auto | post-tier: ${POST_TIER:-unknown}"
  if [[ "$POST_TIER" != "HEALTHY" ]]; then
    echo "[boot] WARN: tier still $POST_TIER after auto backfill — Q-Lead 수동 검토 필요 (--manual 또는 --target=)"
  fi
fi

# 7e. v7.0 Sprint 6 — Active book WT timeline rebuild (observability ledger)
WT_TIMELINE_R="$PROJECT/02_Infrastructure/observability/wt_timeline.R"
if [ -f "$WT_TIMELINE_R" ]; then
  TIMELINE_OUT=$(cd "$PROJECT" && Rscript "$WT_TIMELINE_R" --rebuild-active-book 2>&1 || true)
  TIMELINE_COUNT=$(echo "$TIMELINE_OUT" | grep -oE 'rebuilt [0-9]+' | tail -1 | awk '{print $2}')
  echo "[boot] WT timeline rebuild: ${TIMELINE_COUNT:-0} active book WTs (qepm/observability/timelines/)"
fi

# 7d. v7.2.1 — v8 Readiness Gate (read-only, --no-write production 무손상)
#     15 check 중 e2e_kernel + timeline_generation은 no-write 시 SKIP 정상 (13 PASS + 2 SKIP 기대값)
#     memory_health check은 cached memory_health_latest.json read
QV8_CLI="$PROJECT/02_Infrastructure/tools/qvest_v8_ready"
if [ -f "$QV8_CLI" ]; then
  # L-314 follow-up: temp file 1회 parse로 4값 동시 추출.
  # (v8.1.1 2026-06-10 fix) python에는 stdin 리다이렉트로 전달 — Git Bash mktemp의 MSYS 경로(/tmp/...)를
  # native Windows python이 open() 못 하는 함정 (FileNotFoundError → 영구 '?' 표시) 해소.
  V8_TMP=$(mktemp)
  # qvest_v8_ready CLI exit code 0=PASS / 1=FAIL / 2=WARN — 모두 정상 JSON 반환. 'true'로 exit code 무시.
  bash "$QV8_CLI" --no-write --json > "$V8_TMP" 2>/dev/null || true
  [ -s "$V8_TMP" ] || echo "{}" > "$V8_TMP"
  V8_PARSED=$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    s = d.get('summary', {})
    print(f\"{d.get('overall','?')}|{s.get('pass','?')}|{s.get('fail','?')}|{s.get('skip','?')}\")
except Exception:
    print('?|?|?|?')
" < "$V8_TMP" 2>/dev/null || echo "?|?|?|?")
  rm -f "$V8_TMP"
  IFS='|' read -r V8_OVERALL V8_PASS V8_FAIL V8_SKIP <<< "$V8_PARSED"
  echo "[boot] v8 readiness (--no-write, 16 check incl v8_architecture): $V8_OVERALL — pass=$V8_PASS fail=$V8_FAIL skip=$V8_SKIP (e2e+timeline SKIP 정상, memory_health cached)"
  if [ "${V8_FAIL:-99}" != "0" ] && [ "${V8_FAIL:-99}" != "?" ]; then
    echo "[boot] WARN: v8_readiness FAIL — bash 02_Infrastructure/tools/qvest_v8_ready --strict 직접 실행 권장"
  fi
  # (v8.1.1 2026-06-10) readiness CLI 자체 고장('?')도 침묵 금지 — 게이트 실패로 계상
  if [ "${V8_OVERALL:-?}" = "?" ]; then
    echo "[boot] ERROR: v8 readiness CLI 자체 실행 실패 ('?') — /tmp/qvest_v8_ready_stderr.log 확인"
    BOOT_FAILS=$((BOOT_FAILS+1))
  fi
fi

# 8. 상태 보고 (v6 — 3-agent Work Task)
ALPHA_T=$(ls "$PROJECT"/qepm/mailbox/alpha/inbox/TODO_*.json 2>/dev/null | wc -l)
RISK_T=$(ls "$PROJECT"/qepm/mailbox/risk/inbox/TODO_*.json 2>/dev/null | wc -l)
OPT_T=$(ls "$PROJECT"/qepm/mailbox/optimizer/inbox/TODO_*.json 2>/dev/null | wc -l)
FORGE_T=$(ls "$PROJECT"/qepm/mailbox/forge/inbox/TODO_*.json 2>/dev/null | wc -l)
JUDGE_T=$(ls "$PROJECT"/qepm/mailbox/judge/inbox/TODO_*.json 2>/dev/null | wc -l)
GOV_T=$(ls "$PROJECT"/qepm/mailbox/governor/inbox/TODO_*.json 2>/dev/null | wc -l)

# Work Task 상태
WT_ACTIVE=$(ls -d "$PROJECT"/qepm/mailbox/worktask/WT*_*/ 2>/dev/null | wc -l)

# AX 상태 (v7.2.1 — sot_map 기반 documented_active count + enforcement_mode 분류)
AX_ACTIVE=$(ls "$PROJECT"/qepm/memory/axioms/active/AX-*.json 2>/dev/null | wc -l)
AX_CAND=$(ls "$PROJECT"/qepm/memory/axioms/candidates/CAND_*.json 2>/dev/null | wc -l)
AX_SOT_MAP="$PROJECT/qepm/memory/axioms/axiom_sot_map.json"
AX_DOC_ACTIVE="?"
AX_DOCUMENTED_MODE="?"
AX_BLOCK_MODE="?"
AX_ADVISORY_MODE="?"
if [ -f "$AX_SOT_MAP" ]; then
  # (v8.1.3 fix) 경로를 env-var로 전달 — 백슬래시 Windows $PROJECT를 python3 -c 문자열에 직접 박으면
  #  open('C:\Users\...')의 \U가 unicodeescape SyntaxError → 침묵 '?'. DataFresh와 동일한 env 패턴.
  AX_COUNTS=$(AX_SOT_MAP="$AX_SOT_MAP" python3 -c 'import json,os; d=json.load(open(os.environ["AX_SOT_MAP"],encoding="utf-8")); ax=[a for a in (d.get("axioms",[]) or []) if a.get("documented_active")]; m=lambda mode: sum(1 for a in ax if a.get("enforcement_mode")==mode); print(len(ax), m("documented"), m("block"), m("advisory"))' 2>/dev/null || echo "")
  if [ -n "$AX_COUNTS" ]; then
    read -r AX_DOC_ACTIVE AX_DOCUMENTED_MODE AX_BLOCK_MODE AX_ADVISORY_MODE <<< "$AX_COUNTS"
  fi
fi
# .cache/axiom_core.json STALE 표시 (derived cache, NOT SOT)
AX_CACHE_PATH="$PROJECT/.cache/axiom_core.json"
AX_CACHE_STATUS="MISSING"
if [ -f "$AX_CACHE_PATH" ]; then
  # (v8.1.3 fix) env-var 전달 — 백슬래시 경로 unicodeescape SyntaxError 회피 (위 AX_SOT_MAP 동일 사유)
  AX_CACHE_COUNT=$(AX_CACHE_PATH="$AX_CACHE_PATH" python3 -c 'import json,os; print(len(json.load(open(os.environ["AX_CACHE_PATH"],encoding="utf-8")).get("axioms",[])))' 2>/dev/null || echo "?")
  if [ "$AX_CACHE_COUNT" = "$AX_DOC_ACTIVE" ]; then
    AX_CACHE_STATUS="FULL ($AX_CACHE_COUNT)"
  else
    AX_CACHE_STATUS="STALE ($AX_CACHE_COUNT vs $AX_DOC_ACTIVE — derived cache, WARN only)"
  fi
fi

# PG2 status (L-314 follow-up: 현 PG2 동적 표시 — book_state.json 자동 읽기)
PG2_INFO=""
if [ -f "$BS_PATH" ]; then
  PG2_INFO=$(BS_PATH="$BS_PATH" python3 <<'PYEOF' 2>/dev/null
import json, os
bs_path = os.environ.get('BS_PATH', '')
try:
    with open(bs_path) as f:
        d = json.load(f)
    admitted = d.get('admitted_ids') or []
    weights = d.get('book_weights') or {}
    updated = (d.get('updated_at') or '')[:10]
    # Layer detection
    layers = ['Iter31']
    sched = d.get('schedule_logic_version') or ''
    if 'M4' in sched:
        layers.append('M4 BOCPD')
    if (d.get('ar_overlay_active') or {}).get('active') is True:
        layers.append('AR')
    # R05 admit log: search any r05_layer5_admit_log_* key
    r05_log = {}
    for k, v in d.items():
        if k.startswith('r05_layer5_admit_log_') and isinstance(v, dict):
            r05_log = v
            break
    r05_state = r05_log.get('r05_layer5_active') or {}
    if r05_state.get('active') is True:
        layers.append('R05 Tail-Risk')
    n_layer = len(layers) + 1  # +1 for STR_1715 alpha base
    # Beta values (admit baseline: NORMAL regime, middle β_AR rule q70~q90)
    beta_ar = 0.7
    beta_r05 = float((r05_state.get('beta_r05_params') or {}).get('NORMAL', 1.0))
    risk_pct = round(1.0 * beta_ar * beta_r05 * 100)
    cash_pct = 100 - risk_pct
    # Admit metrics
    m = r05_log.get('admit_basis_metrics') or {}
    sr = m.get('SR_admit_255m')
    mdd = m.get('MDD_pct_255m')
    cagr = m.get('CAGR_pct_255m')
    lines = []
    if admitted:
        aid = admitted[0]
        w_pct = round(float(weights.get(aid, 0)) * 100)
        lines.append(f'PG2 admit:  {aid} ({w_pct}%, {updated}~)')
        lines.append(f'PG2 layer:  {n_layer}-Layer ({" + ".join(layers)})')
        if sr is not None and mdd is not None and cagr is not None:
            lines.append(f'PG2 regime: m4=NORMAL × β_AR={beta_ar:.2f} × β_R05={beta_r05:.2f} = {risk_pct}% risk + {cash_pct}% cash (admit baseline)')
            lines.append(f'PG2 admit:  SR {sr:.4f} / MDD {mdd:.2f}% / CAGR {cagr:.2f}% (255m PerfA)')
    else:
        lines.append('PG2 admit:  NONE (book_state.admitted_ids empty)')
    print('\n'.join(lines))
except Exception as e:
    print(f'PG2:        parse_failed ({type(e).__name__})')
PYEOF
)
fi

# 8f. (v8.1.3) 페이퍼 적재 리서치풀 인지 — paper_recharge→router→dispatch 산출물 요약.
#      Step 3b paper_recharge가 적재한 *신규 리서치풀*(라우팅 분포 / alpha-search 대기 testable /
#      optimizer·risk·regime QEPM 연료 / dispatch 소비여부 / 수집>라우팅 미반영)을 부팅 상태에
#      노출. --mark로 직전 부팅 대비 NEW 여부 판정 후 인지 마커 갱신. fail-soft(부팅 무중단).
RP_READER="$PROJECT/02_Infrastructure/ops/research_pool_status.py"
RESEARCH_POOL=""
if [ -f "$RP_READER" ] && python3 -c 'import sys' >/dev/null 2>&1; then
  RESEARCH_POOL=$(QM_ROOT="$CLAUDE_PROJECT_DIR" python3 "$RP_READER" --mark 2>/dev/null || true)
fi

# 8g. (v8.1.3) 데이터 freshness 인지 — cache_freshness_audit(daily_refresh Step 5 백그라운드)가
#      산출한 qepm/observability/cache_freshness_latest.json(mtime+내부 max(Date) lag, OK/WARN/CRITICAL)을
#      부팅에 노출. boot이 지금까지 audit을 돌리기만 하고 결과를 안 읽던 갭. advisory(부팅 무중단) —
#      핵심 연구캐시(rawdata/benchmark/regime) stale은 별도 강조(성과수치 산출 전 갱신 의무).
FRESH_JSON="$PROJECT/qepm/observability/cache_freshness_latest.json"
DATA_FRESH=""
if [ -f "$FRESH_JSON" ] && python3 -c 'import sys' >/dev/null 2>&1; then
  DATA_FRESH=$(FRESH_JSON="$FRESH_JSON" python3 <<'PYEOF' 2>/dev/null
import json, os
try:
    d = json.load(open(os.environ.get('FRESH_JSON',''), encoding='utf-8'))
    s = d.get('summary', {}) or {}
    res = d.get('results', []) or []
    ran = (d.get('ran_at') or '')[:16].replace('T', ' ')
    crit = [r.get('path') for r in res if r.get('severity') == 'CRITICAL']
    KEY = {'.cache/rawdata.parquet', '.cache/RAWDATA.parquet', '.cache/benchmark.parquet',
           '.cache/regime_daily_v2.parquet', '.cache/unified_regime_signal.parquet'}
    key_stale = [r.get('path') for r in res
                 if r.get('path') in KEY and r.get('severity') in ('WARN', 'CRITICAL')]
    line = "DataFresh:  %s · OK %s / WARN %s / CRITICAL %s" % (
        ran or '?', s.get('OK', '?'), s.get('WARN', '?'), s.get('CRITICAL', '?'))
    if crit:
        line += " — crit: " + ", ".join((os.path.basename(c.rstrip('/')) or c) for c in crit[:4])
    print(line)
    if key_stale:
        print("  WARN: 핵심 연구캐시 stale — " + ", ".join(os.path.basename(c) for c in key_stale)
              + " (성과수치 산출 전 갱신 의무 — performance-real-code-only)")
    else:
        print("  핵심 연구캐시(rawdata/benchmark/regime): FRESH")
except Exception as e:
    print("DataFresh:  SKIP (parse %s)" % type(e).__name__)
PYEOF
)
fi

# 8h. (v8.1.3) 모닝 파이프라인 ran-today 인지 — morning_run.sh once-per-day 락 확인.
#      스케줄러 silent 무발화(예: mrs_daily 멀티라인 -e 트랩) 조기감지. advisory.
MR_LOCK="/tmp/qm_morning_run_$(date +%Y%m%d).lock"
if [ -f "$MR_LOCK" ]; then
  MR_T=$(stat -c %y "$MR_LOCK" 2>/dev/null | cut -d'.' -f1 | cut -d' ' -f2)
  MORNING_STATUS="MorningRun:  $(date +%Y-%m-%d) 실행됨 (${MR_T:-?}) — paper/router/dispatch + 평일 brief/regime"
else
  MORNING_STATUS="MorningRun:  $(date +%Y-%m-%d) 미실행 (오늘 lock 부재 — 스케줄러 미발화/미도래. 수동: bash 02_Infrastructure/ops/morning_run.sh manual)"
fi

# 8i. (v8.1.4) 부팅 상태-라인 스모크 가드 — 하단 상태 라인을 산출하는 모든 리더를 실행 +
#      inline-path( python3 -c "...$PROJECT..." ) 정적 린트. 새 상태 라인이 이 머신에서 검증 없이
#      출고돼 사용자가 부팅 때 발견하던 회귀(class A 백슬래시 -c unicodeescape '?' / class B JSON
#      스키마드리프트 SKIP)를 *추가 시점*에 차단. advisory(loud, BOOT_FAILS 비계상 — 상태 표시는
#      시스템 게이트가 아님). 스크립트는 pre-commit/CI 게이트로도 사용 가능(exit=FAIL 개수).
SMOKE_STATUS=""
SMOKE_SCRIPT="$PROJECT/02_Infrastructure/ops/boot_status_smoke.py"
if [ -f "$SMOKE_SCRIPT" ] && python3 -c 'import sys' >/dev/null 2>&1; then
  SMOKE_STATUS=$(QM_ROOT="$CLAUDE_PROJECT_DIR" python3 "$(cygpath -m "$SMOKE_SCRIPT" 2>/dev/null || echo "$SMOKE_SCRIPT")" "$CLAUDE_PROJECT_DIR" 2>&1 | tail -1 || true)
fi

# hypothesis_index 재빌드 (2026-07-05) — 검색면 자동 정합. bootstrap이 lcode_corpus는 매 세션
#   무조건 regen하나 hypothesis_index는 안 해 다음 세션 첫 조회부터 stale 배너 상시 발화하던 갭 수리.
#   .R 파일 경유 CLI(한글 -e 아님). lcode_corpus 백그라운드 job 이후 실행되도록 부트 말미 배치. fail-soft.
HI_R="$PROJECT/02_Infrastructure/tools/hypothesis_index.R"
if [ -f "$HI_R" ]; then
  HI_OUT=$(cd "$PROJECT" && Rscript "$HI_R" build 2>&1 | grep -oE '\[hypothesis_index\].*entries.*' | tail -1 || true)
  [ -n "$HI_OUT" ] && echo "[boot] hypothesis_index rebuilt: $HI_OUT"
fi

# 지식 순차 인덱스 재생성 (2026-07-05 도훈 — 안정 ID 불변, 활성 집합 1..N 뷰). fail-soft.
#   lcode_corpus 백그라운드 regen 이후 실행되도록 부트 말미 배치. 산출: 06_Registry/knowledge_index.{md,json}
KI_R="$PROJECT/02_Infrastructure/ops/build_knowledge_index.R"
if [ -f "$KI_R" ]; then
  KI_OUT=$(cd "$PROJECT" && Rscript "$KI_R" 2>&1 | grep -oE '\[knowledge-index\].*' | tail -1 || true)
  [ -n "$KI_OUT" ] && echo "[boot] $KI_OUT"
fi

echo ""
if [ "${BOOT_FAILS:-0}" -gt 0 ]; then
  echo "=== 부트스트랩 DEGRADED — ${BOOT_FAILS}개 게이트 실패 (위 ERROR 라인 확인, '완료' 아님) ==="
else
  echo "=== 부트스트랩 완료 (Qvest v8.1 — Opus 4.8 Native · 4-Mode +RAMP · 실측 거버넌스) ==="
fi
if [ -n "$PG2_INFO" ]; then
  echo "$PG2_INFO"
fi
echo "v8.1:       4-Mode 헌법(alpha-search 논문복제·K200∪KQ150·2005 / factor-rotation Lane3 / RAMP 팩터배분 Gate0~11 / Axiom r7 복원) / 실측 거버넌스(measurement-graduation) / register_module 자동흐름"
echo "v8.0 base:  R+Python 1급 / SR목표 2.5 / agent effort(judge·gov xhigh) / axiom_context_inject / qvest-*-style skill"
echo "Modes:      ① QEPM(/worktask) ② alpha-search ③ factor-rotation ④ RAMP(/ramp · Gate0~11·CCS 13-score · governor 정지/자본 수동) — CLAUDE.md 4-Mode 헌법(RAMP 2026-06-17)"
echo "Skills:     $(ls "$PROJECT"/.claude/skills/*/SKILL.md 2>/dev/null | wc -l)개 (worktask/alpha/risk/optimizer + qvest-*-style 4종)"
echo "Hooks:      settings.json 등록 (harness_health 결과 위 참조)"
echo "WT Active:  $WT_ACTIVE건"
echo "Inbox:      alpha=$ALPHA_T risk=$RISK_T optimizer=$OPT_T forge=$FORGE_T judge=$JUDGE_T governor=$GOV_T"
echo "Axioms:     active=$AX_ACTIVE candidates=$AX_CAND (sot_map documented=$AX_DOC_ACTIVE: documented=$AX_DOCUMENTED_MODE / block=$AX_BLOCK_MODE / advisory=$AX_ADVISORY_MODE)"
echo "Cache_core: $AX_CACHE_STATUS"
if [ -n "$RESEARCH_POOL" ]; then
  echo "$RESEARCH_POOL"
else
  echo "ResearchPool: SKIP (research_pool_status.py 부재 또는 python3 미가용)"
fi
if [ -n "$DATA_FRESH" ]; then
  echo "$DATA_FRESH"
else
  echo "DataFresh:  SKIP (cache_freshness_latest.json 부재 — daily_refresh 후 표시)"
fi
[ -n "$MORNING_STATUS" ] && echo "$MORNING_STATUS"
[ -n "$SMOKE_STATUS" ] && echo "$SMOKE_STATUS"
command -v free >/dev/null 2>&1 && free -m | awk '/Mem:/ {printf "RAM:        %.0f%%\n", $3/$2*100}' || true
# (Remote tmux rc 라인 제거 v8.0 — inbound listener 폐지)
echo ""
echo "다음: /qvest 5-B 절차 따라 Work Task 생성 + 3-agent 순차 spawn"
echo "  wt_create('{hypothesis}') -> alpha-research -> risk-research -> optimizer-research"
echo "===================================="
