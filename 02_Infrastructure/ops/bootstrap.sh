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

echo "=== Qvest v8.3 부트스트랩 (Fable 5-Native · 4-Mode +RAMP) ==="

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
  # (2026-07-26 MKH-02 수리) 구 `|| true` 가 exit code 를 전량 폐기했다. R 은 summary 를
  #   먼저 출력(:553-556)하고 report 를 나중에 쓰므로(:575), write_json 실패(권한/디스크/
  #   OneDrive 락)는 stdout 에 이미 "Hard fails: 0" 이 있어 **초록으로 위장**되고
  #   memory_health_latest.json 은 이전 실행분으로 stale 잔존한다(그걸 readiness 가 재소비).
  #   ${MKH_HARD:-99} fail-closed 는 summary 출력 *전* 크래시만 막는다.
  MKH_OUT=$(cd "$PROJECT" && Rscript "$MKH_R" 2>&1); MKH_RC=$?
  MKH_HARD=$(echo "$MKH_OUT" | grep -oE 'Hard fails: [0-9]+' | awk '{print $3}')
  MKH_WARN=$(echo "$MKH_OUT" | grep -oE 'Warnings: +[0-9]+' | awk '{print $2}')
  MKH_INFO=$(echo "$MKH_OUT" | grep -oE 'Infos: +[0-9]+' | awk '{print $2}')
  echo "[boot] Memory health: hard=${MKH_HARD:-?} warn=${MKH_WARN:-?} info=${MKH_INFO:-?}"
  if [ "${MKH_RC:-0}" != "0" ]; then
    echo "[boot] WARN: memory health rc=${MKH_RC} — summary 는 나왔으나 스크립트가 비-0 종료 (report write 실패 의심: memory_health_latest.json 이 stale 일 수 있음)"
  fi
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
    echo "[boot] WARN: bear_date_audit FAIL — 실패 축 확인 필요 (기지 4/4 = check_fwd_match vintage 완전일치 드리프트·backward 오염 아님. STATUS_BUGGY_ERA 외 신규 날짜/축이면 label 방향 회귀 의심)"
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
# 4e2. (2026-07-11) 월별 거래일 수 연속성 체크 — rawdata 내부 공백(interior gap) 감지.
#      기준 = benchmark.parquet (chart-API 실세션 — trading calendar와 독립이라 캘린더
#      결손에 눈멀지 않음). 실사고: 2026-03-30~04-29 한 달이 QuantiWise 수출 이음매
#      구멍 + 07-02 리빌드로 소실됐는데 캘린더도 같은 구멍이라 모든 가드 침묵 통과
#      (2026-04 거래일 = 1일). trailing 13개월에서 rawdata 월별 거래일 < benchmark
#      월별 거래일이면 WARN (블록 아님 — 성과수치 산출 전 복구 의무).
#      ⚠ Windows Rscript 멀티라인 -e는 첫 줄만 실행되는 함정 (daily_refresh run_r 참조) — 반드시 단일 라인 유지.
if [ -f "$RAWDATA_PARQUET" ] && [ -f "$PROJECT/.cache/benchmark.parquet" ]; then
  #      [2026-07-25 계단 분리] 구판은 '월별 거래일 카운트 차이'만 봐서 말단-지연(벤더가
  #      아직 어제치를 안 준 정상 상태)과 월중 내부-결손(2026-04형 소실 사고)을 같은
  #      ⛔WARN 문구로 경보 → 오탐 피로. 이제 결손일이 max(rawdata)보다 앞이면 내부 공백
  #      (FAIL, KRX 백필 지시), 뒤면 말단 지연(LAG)으로 분리. LAG는 2거래일까지 INFO,
  #      3거래일 이상이면 벤더 파이프라인 정지 의심 WARN. 판정 근거 = close_round
  #      BOOT-20260725_data_hygiene (live_trigger 3종).
  CONT_CHECK=$(cd "$PROJECT" && Rscript -e 'suppressMessages({library(arrow); library(data.table)}); rd <- unique(as.Date(as.data.table(read_parquet(".cache/rawdata.parquet", col_select="Date"))$Date)); bm <- unique(as.Date(as.data.table(read_parquet(".cache/benchmark.parquet", col_select="Date"))$Date)); lo <- Sys.Date() - 400; rdmax <- max(rd); miss <- as.Date(setdiff(bm[bm >= lo], rd), origin = "1970-01-01"); inner <- miss[miss < rdmax]; lag <- miss[miss > rdmax]; if (length(inner) > 0) cat("CONTINUITY_FAIL:", paste(format(inner), collapse = " "), "\n") else if (length(lag) > 0) cat("CONTINUITY_LAG:", length(lag), format(rdmax), format(max(bm)), "\n") else cat("CONTINUITY_OK\n")' 2>/dev/null | grep -E 'CONTINUITY_(OK|LAG|FAIL)')
  if echo "$CONT_CHECK" | grep -q "CONTINUITY_OK"; then
    echo "[boot] 거래일 연속성 (rawdata vs benchmark, 13개월): OK"
  elif echo "$CONT_CHECK" | grep -q "CONTINUITY_LAG"; then
    LAG_N=$(echo "$CONT_CHECK" | awk '{print $2}')
    LAG_RD=$(echo "$CONT_CHECK" | awk '{print $3}')
    LAG_BM=$(echo "$CONT_CHECK" | awk '{print $4}')
    if [ "${LAG_N:-0}" -le 2 ]; then
      echo "[boot] 거래일 연속성: OK (내부 공백 0 · 말단 지연 ${LAG_N}거래일 — rawdata=$LAG_RD / bm=$LAG_BM, daily_refresh가 병합 예정)"
    else
      echo "[boot] ⛔ WARN: rawdata 말단 지연 ${LAG_N}거래일 (rawdata=$LAG_RD / bm=$LAG_BM) — 내부 공백은 아니나 벤더 파이프라인 정지 의심"
      echo "[boot]    → bash 02_Infrastructure/data/daily_refresh.sh 수동 재기동 후 재확인"
    fi
  elif [ -n "$CONT_CHECK" ]; then
    echo "[boot] ⛔ WARN: rawdata 월중 내부 결손 감지 — $CONT_CHECK"
    echo "[boot]    → 2026-04형 소실 사고 신호. build_trading_calendar(force=TRUE) 후 KRX 백필 필요 (04_Research/01_reports/rawdata_april_gap_incident_20260711.md 참조)"
  else
    echo "[boot] 거래일 연속성 체크: SKIP (R 실행 실패)"
  fi
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

# 4g. (2026-07-04 Cleaner) 주간 증류 대기 마커 + (2026-07-18 WT_D20260718_001 np#1) distill claim 정체 가시성.
#     ① weekly_cleaner_sweep(토 09:00 무인 기계 스윕)가 남긴 cleaner_pending.json(awaiting_distill) 감지 시
#        /cleaner 증류 안내.
#     ② distill_status=in_progress ∧ distill_claimed_at 이 stale(>6h)이면 크래시 세션 stuck claim 노출 —
#        cleaner_claim.R(cleaner_claim_distill)의 stale 자동 재점유는 조용하므로 "정체" 자체를 가시화.
#     둘 다 WARN-only(차단 없음)·fail-soft. jq 미의존 — grep 추출 + date 파싱, 필드/타임스탬프 결측 시 조용히 skip.
CLEANER_PENDING="$PROJECT/.cache/cleaner_pending.json"
CLEANER_STALE_HOURS=6   # cleaner_claim.R stale_hours 기본과 동기 (boot WARN ↔ helper stale_reclaim 정합)
if [ -f "$CLEANER_PENDING" ]; then
  if grep -q '"status"[[:space:]]*:[[:space:]]*"awaiting_distill"' "$CLEANER_PENDING"; then
    echo "[boot] WARN: [cleaner] 주간 증류 대기 (cleaner_pending.json awaiting_distill) — /cleaner 실행 (기계 스윕 완료·엑기스 증류/L-code 적립/잔재 삭제 미완)"
  fi
  CL_DSTATUS=$(grep -oE '"distill_status"[[:space:]]*:[[:space:]]*"[^"]*"' "$CLEANER_PENDING" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
  if [ "$CL_DSTATUS" = "in_progress" ]; then
    CL_CLAIMED=$(grep -oE '"distill_claimed_at"[[:space:]]*:[[:space:]]*"[^"]*"' "$CLEANER_PENDING" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
    CL_OWNER=$(grep -oE '"distill_owner"[[:space:]]*:[[:space:]]*"[^"]*"' "$CLEANER_PENDING" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')
    # 빈/결측 timestamp 가드: GNU date -d "" 는 오늘 자정을 반환(exit 0)해 거짓 stale를 유발하므로 비어있으면 skip.
    CL_CLAIMED_S=""
    [ -n "$CL_CLAIMED" ] && CL_CLAIMED_S=$(date -d "$CL_CLAIMED" +%s 2>/dev/null || echo "")
    if [ -n "$CL_CLAIMED_S" ]; then
      CL_AGE_H=$(( ($(date +%s) - CL_CLAIMED_S) / 3600 ))
      if [ "$CL_AGE_H" -gt "$CLEANER_STALE_HOURS" ]; then
        echo "[boot] WARN: [cleaner] 증류 claim이 in_progress로 ${CL_AGE_H}h 정체 (owner=${CL_OWNER:-?}) — 크래시 세션 의심, 다음 /cleaner claim이 stale 재점유"
      fi
    fi
  fi
fi

# 4h. (2026-07-25) Worktree 가시성 — 병렬 세션 미병합/미커밋 감지. WARN-only (블록 아님).
#     근본: bootstrap 전문에 git 점검이 0건이라 "수리는 됐는데 worktree에 갇힘" 상태가 부팅에 안 보였음.
#     동일 패턴 실사고 2건 — benchmark date32 writer(미커밋 7일 방치 후 07-25 재적용) ·
#     lcode_harvester substring 수리(미병합=게이트). 감지 장치 부재가 공통 근본원인.
#     읽기 전용(status/rev-list/log만). 실패해도 부팅 진행.
WT_STALE_DAYS=3
if command -v git >/dev/null 2>&1 && git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
  WTV_AHEAD=0; WTV_DIRTY=0; WTV_STALE=0; WTV_N=0
  WTV_LINES=""
  while IFS='|' read -r wt br; do
    [ -z "$wt" ] && continue
    case "$wt" in *worktrees*) ;; *) continue ;; esac
    WTV_N=$((WTV_N + 1))
    sb="${br#refs/heads/}"
    ahead=$(git -C "$PROJECT" rev-list --count "main..$sb" 2>/dev/null || echo 0)
    dirty=$(git -C "$wt" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    ct=$(git -C "$PROJECT" log -1 --format=%ct "$sb" 2>/dev/null || echo 0)
    age=$(( ct > 0 ? ($(date +%s) - ct) / 86400 : -1 ))
    [ "${ahead:-0}" -gt 0 ] 2>/dev/null && WTV_AHEAD=$((WTV_AHEAD + 1))
    [ "${dirty:-0}" -gt 0 ] 2>/dev/null && WTV_DIRTY=$((WTV_DIRTY + 1))
    if [ "${dirty:-0}" -gt 0 ] 2>/dev/null && [ "${age:-0}" -ge "$WT_STALE_DAYS" ] 2>/dev/null; then
      WTV_STALE=$((WTV_STALE + 1))
      WTV_LINES="${WTV_LINES}    [방치 ${age}d] $(basename "$sb"): 미커밋 ${dirty}파일$([ "${ahead:-0}" -gt 0 ] && echo " + 미병합 ${ahead}커밋")\n"
    elif [ "${ahead:-0}" -gt 0 ] 2>/dev/null || [ "${dirty:-0}" -gt 0 ] 2>/dev/null; then
      WTV_LINES="${WTV_LINES}    [활동 ${age}d] $(basename "$sb"): $([ "${dirty:-0}" -gt 0 ] && echo "미커밋 ${dirty}파일 ")$([ "${ahead:-0}" -gt 0 ] && echo "미병합 ${ahead}커밋")\n"
    fi
  done <<< "$(git -C "$PROJECT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{w=$2} /^branch /{print w"|"$2}')"

  if [ "$WTV_N" -eq 0 ]; then
    echo "[boot] Worktree: 없음 (단일 세션)"
  elif [ "$WTV_AHEAD" -eq 0 ] && [ "$WTV_DIRTY" -eq 0 ]; then
    echo "[boot] Worktree: OK — ${WTV_N}개 전부 병합·클린"
  else
    echo "[boot] WARN: Worktree ${WTV_N}개 중 미커밋 ${WTV_DIRTY} / 미병합 ${WTV_AHEAD}$([ "$WTV_STALE" -gt 0 ] && echo " · ★${WTV_STALE}건 ${WT_STALE_DAYS}일+ 방치")"
    printf "%b" "$WTV_LINES"
    [ "$WTV_STALE" -gt 0 ] && echo "    → 방치분은 '수리했는데 main에 없음' 실사고 패턴(date32 writer·lcode harvester). 병합 여부 확인 필요"
    [ "$WTV_DIRTY" -gt 0 ] && echo "    → 확인: git -C <worktree경로> status  ·  목록: git worktree list"
  fi

  # [4h-2] worktree venv 가용성 (2026-07-25) — qvest_hook_router 등록 커맨드가
  #   $CLAUDE_PROJECT_DIR/.venv_qvest_ml 에서 검증기를 찾는다. worktree엔 venv가 없어
  #   **보호패턴(05_Production 등) 편집이 fail-closed로 차단**되는 실사고 발생(07-25).
  #   게이트 약화가 아니라 '검증기 부재'가 원인이므로 junction으로 복구한다(내용 복사 아님).
  #   Windows junction = 관리자 권한 불필요. 실패해도 부팅 진행(읽기 전용 경고).
  if [ -x "$PROJECT/.venv_qvest_ml/Scripts/python.exe" ]; then
    WTV_FIXED=0; WTV_MISS=0
    while IFS='|' read -r wt br; do
      [ -z "$wt" ] && continue
      case "$wt" in *worktrees*) ;; *) continue ;; esac
      [ -d "$wt" ] || continue
      if [ ! -e "$wt/.venv_qvest_ml" ]; then
        WTV_MISS=$((WTV_MISS + 1))
        # 함정 2종 (07-25 실측):
        #   ★`< /dev/null` — cmd.exe가 while 루프의 stdin(here-string)을 소비해 첫 항목
        #     처리 후 루프가 조기 종료됨(14개 중 1개만 처리).
        #   ★`MSYS_NO_PATHCONV=1` — Git Bash가 `/c`·`/J`를 경로로 변환해 cmd가 실행 대신
        #     대화형 배너만 찍고 exit 0 반환(성공 오보 13건). 변환 차단 필수.
        if command -v cmd.exe >/dev/null 2>&1 &&
           MSYS_NO_PATHCONV=1 cmd.exe /c mklink /J \
             "$(cygpath -w "$wt/.venv_qvest_ml" 2>/dev/null || echo "$wt/.venv_qvest_ml")" \
             "$(cygpath -w "$PROJECT/.venv_qvest_ml" 2>/dev/null || echo "$PROJECT/.venv_qvest_ml")" \
             >/dev/null 2>&1 < /dev/null &&
           [ -e "$wt/.venv_qvest_ml" ]   # ★생성 실증 — exit 0을 믿지 않는다
        then WTV_FIXED=$((WTV_FIXED + 1)); fi
      fi
    done <<< "$(git -C "$PROJECT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{w=$2} /^branch /{print w"|"$2}')"
    if [ "$WTV_MISS" -gt 0 ]; then
      echo "[boot] Worktree venv: 부재 ${WTV_MISS}건 → junction 복구 ${WTV_FIXED}건$([ "$WTV_FIXED" -lt "$WTV_MISS" ] && echo " · ★$((WTV_MISS - WTV_FIXED))건 실패 — 해당 worktree에서 보호패턴 편집이 차단됨")"
    fi
  fi
fi

# 4i. (2026-07-26) 예약작업 바깥 경계 — 이미 측정된 값을 *읽기만* 한다(부팅에서 재수집 금지: 느림).
#     왜 필요: 07-26 실측 당시 저장소에 예약작업 rc를 읽는 코드가 0건이었고, 그 결과
#     InsiderBackfill이 매일 02:00에 시작해 03:15경 rc=0xC000013A로 죽는 것을 아무도 보지 못했다.
#     오늘 배선한 계측은 전부 스크립트 *안*이라 "실행 자체가 없었다"를 관측할 수 없다.
#     수집 담체 = StrandedRepairs(12/20시) + MorningBrief(07:10). 부팅은 소비만.
STH="$PROJECT/06_Registry/scheduler_task_health.json"
if [ -f "$STH" ]; then
  STH_LINE=$("${QVEST_PY:-python}" -c '
import json, io, sys, datetime
try:
    d = json.load(io.open(sys.argv[1], encoding="utf-8-sig"))
except Exception as e:
    print("PARSE_FAIL %s" % type(e).__name__); raise SystemExit
ts = d.get("measured_at", "")
# (2026-08-02) ★판정을 여기서 다시 만들지 않는다 — 원장에 기록된 판정을 *소비*한다.
#   실사고: 이 블록이 원시 rc 만 보고 5건을 개별 "★실패"로 보고하는 동안, 같은 데이터를
#   읽는 권위 스크립트(scheduler_task_health.sh)는 "실패 1 · 정지(동시종료) 1"로 판정했다.
#   같은 사실에 렌더러가 둘이면 판정도 둘이 된다 — 부팅은 더 놀라운 쪽을 보여줬다.
co = d.get("cotermination") or {}
co_names = set(co.get("tasks") or [])
bad, stale = [], []
for t in d.get("tasks") or []:
    if not t.get("enabled", True): continue
    if t.get("task") in co_names: continue      # 하나의 사건으로 접힌 항목 — 개별 계수 금지
    if int(t.get("rc") or 0) and t.get("rc_label") not in ("still_running", "never_run"):
        bad.append("%s=%s" % (t.get("task", "?").replace("Qvest_", ""), t.get("rc_label")))
    ms, ag = t.get("max_stale_days"), t.get("age_days")
    if ms and ag is not None and ag > ms:
        stale.append("%s(%.0f일)" % (t.get("task", "?").replace("Qvest_", ""), ag))
co_txt = ""
if co_names:
    co_txt = "동시종료 %d건 %s [%s]" % (co.get("n") or len(co_names),
             (co.get("when") or "")[5:16].replace("T", " "), co.get("classification") or "미분류")
# 측정 자체가 오래됐으면 그것부터 알린다 — 낡은 GREEN이 제일 위험하다
age_h = ""
try:
    dt = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S")
    h = (datetime.datetime.now() - dt).total_seconds() / 3600.0
    if h > 26: age_h = " ★측정 %.0f시간 전(수집 담체도 멈춤 의심)" % h
except Exception: pass
print("%s|%s|%s|%s" % ("·".join(bad), "·".join(stale), age_h, co_txt))
' "$STH" 2>/dev/null)
  if [ "${STH_LINE:-}" = "PARSE_FAIL" ] || [ -z "${STH_LINE:-}" ]; then
    echo "[boot] ★예약작업 상태 판독 실패 — $STH 확인"
  else
    STH_BAD="${STH_LINE%%|*}";   STH_R1="${STH_LINE#*|}"
    STH_STALE="${STH_R1%%|*}";   STH_R2="${STH_R1#*|}"
    STH_AGE="${STH_R2%%|*}";     STH_COTERM="${STH_R2#*|}"
    if [ -n "$STH_BAD" ] || [ -n "$STH_STALE" ] || [ -n "$STH_AGE" ] || [ -n "$STH_COTERM" ]; then
      echo "[boot] 예약작업:${STH_BAD:+ ★실패 $STH_BAD}${STH_STALE:+ · ★정체 $STH_STALE}${STH_COTERM:+ · $STH_COTERM}${STH_AGE}"
      echo "    → 상세: 06_Registry/scheduler_task_health.json · 재측정: bash 02_Infrastructure/ops/scheduler_task_health.sh"
    fi
  fi
fi

# 4h-3. (2026-07-26) auto-commit 격리 가시성 — main 저장소 쪽 '수리가 git에 못 닿음' 감시.
#   §4h(worktree 좌초)의 거울: Stop 훅 밸브 v2가 대량-신규 디렉터리를 격리하면
#   .cache/auto_commit_quarantine.json 원장을 남기고, 여기서 부팅 WARN으로 노출한다.
#   근거: v1 밸브가 171회 조용히 격리(CORE_ONLY_STAGED)하는 동안 아무 표면에도 안 보여
#   08_Tests 회귀가드·04_Research 보고서가 영구 미커밋된 실사고(2026-07-26 적발). WARN-only.
AC_QUAR="$PROJECT/.cache/auto_commit_quarantine.json"
if [ -f "$AC_QUAR" ]; then
  AC_TS=$(grep -oE '"ts":"[^"]*"' "$AC_QUAR" 2>/dev/null | head -1 | sed 's/.*:"//;s/"$//')
  AC_DIRS=$(grep -oE '"dir":"[^"]*","n_new":[0-9]+' "$AC_QUAR" 2>/dev/null \
            | sed 's/"dir":"//;s/","n_new":/ (/;s/$/건)/' | head -5 | tr '\n' ' ')
  echo "[boot] WARN: auto-commit 격리 활성 (${AC_TS:-시각?}) — ${AC_DIRS:-원장 파싱 실패, 직접 확인: $AC_QUAR}"
  echo "[boot]    → 정상 산출물이면 git add <해당 디렉터리> 후 수동 커밋으로 드레인 / dump면 정리·.gitignore (M/D는 영향 없음)"
fi

# 5. 데이터 리프레시 (백그라운드 — xlsx 증분 + KRX/FRED/ECOS)
REFRESH_LOG="/tmp/qm_boot_refresh_$(date +%Y%m%d_%H%M).log"
(cd "$PROJECT/02_Infrastructure" && bash "$PROJECT/02_Infrastructure/data/daily_refresh.sh") > "$REFRESH_LOG" 2>&1 &
REFRESH_PID=$!
echo "[boot] 데이터 리프레시 백그라운드 (PID=$REFRESH_PID, log=$REFRESH_LOG)"

# 6. v53 Axiom 엔진 주간 갱신 (백그라운드, 빠른 실행)
QVEST_PROJECT_DIR="$PROJECT" \
  "$QVEST_PY" "$PROJECT/02_Infrastructure/axiom/lcode_harvester.py" >/tmp/axiom_boot.log 2>&1 &
echo "[boot] L-code harvester 백그라운드 (QVEST_PY — bare python3 stub 회피 2026-07-06)"

# 6b. (2026-07-06 통합, 도훈 confirm) 주간 axiom 사이클 = Cleaner 정규경로로 통일.
#     bootstrap 7일 게이트(신뢰 트리거)가 canonical weekly_cleaner_sweep.R(hygiene+inventory+
#     axiom step[3.5]+digest)를 실행. Qvest_WeeklyCleaner Sat task는 백업(공유 cleaner_pending
#     7일 게이트가 이중실행 방지). 구 axiom_weekly.sh/run_axiom_weekly.R 자동실행 제거 → manual-only.
#     (2026-07-17 인터페이스 계약) weekly_cleaner_sweep.R가 시작 시 .cache/cleaner_sweep.lock 생성 /
#     종료 시 삭제 — lock 존재 ∧ mtime<2h면 스윕 기동 스킵 (Sat task ↔ boot 게이트 동시 기동 race ~80초 실측).
LAST_CLEAN="$PROJECT/.cache/cleaner_pending.json"
LASTC_T=0; [ -f "$LAST_CLEAN" ] && LASTC_T=$(stat -c %Y "$LAST_CLEAN" 2>/dev/null || echo 0)
if [ $(( ($(date +%s) - LASTC_T) / 86400 )) -ge 7 ]; then
  CSW_LOCK="$PROJECT/.cache/cleaner_sweep.lock"
  CSW_LOCK_T=0; [ -e "$CSW_LOCK" ] && CSW_LOCK_T=$(stat -c %Y "$CSW_LOCK" 2>/dev/null || echo 0)
  if [ "$CSW_LOCK_T" -gt 0 ] && [ $(( $(date +%s) - CSW_LOCK_T )) -lt 7200 ]; then
    echo "[boot] 주간 Cleaner 사이클 스킵 — cleaner_sweep.lock 활성 (<2h, 타 프로세스 스윕 진행 중)"
  else
    (cd "$PROJECT" && PYTHONUTF8=1 LANG=C.UTF-8 LC_ALL="English_United States.utf8" Rscript "$PROJECT/02_Infrastructure/ops/weekly_cleaner_sweep.R") >/tmp/cleaner_boot.log 2>&1 &
    echo "[boot] 주간 Cleaner 사이클(axiom step3.5 포함) 백그라운드 (7일+ 경과 · Sat task 백업)"
  fi
fi

# 7. Hook health check (v8.1.1 — 침묵 삼킴 금지: 빈 결과 = ERROR)
HH_OUT=$(bash "$PROJECT/02_Infrastructure/hooks/harness_health.sh" 2>&1)
HH_SUMMARY=$(echo "$HH_OUT" | grep -E "Result:" | head -1)
# (2026-07-26 부팅감사 수리) 등록 카운터 라인을 grep이 버려 "settings.json hooks 블록 소실"이
# 부팅에서 불가시였음 — 등록 수를 함께 노출 + FAIL 라인 승격
HH_REG=$(echo "$HH_OUT" | grep -E "hook entries registered|hook 등록 계측 실패" | head -1 | sed 's/^ *//')
if [ -z "$HH_SUMMARY" ]; then
  echo "[boot] ERROR: harness_health 실행 불가 — hook 전수 점검 필요 (첫 줄: $(echo "$HH_OUT" | head -1))"
  BOOT_FAILS=$((BOOT_FAILS+1))
else
  echo "[boot] $HH_SUMMARY${HH_REG:+ · $HH_REG}"
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

# 7a-2. (2026-07-26 도훈 지시 "부팅 최신화 자동으로") 부팅 시퀀스 자기-정합 검사 —
#   배너/체크리스트 기대값/인벤토리 스냅샷/훅 총계/PG2 참조가 헌법(CLAUDE.md)·실측보다
#   낡으면 즉시 WARN. 기대값은 하드코딩 없이 매 부팅 CLAUDE.md/파일시스템에서 파생하므로,
#   헌법이 바뀌는 순간(예: v8.4 승격) 다음 부팅이 낡은 곳을 전부 짚는다. WARN-only —
#   수리는 세션 몫(WARN 발화 = 즉시 수리 의무, 수동 지시 불요 원칙).
BCC="$PROJECT/02_Infrastructure/ops/boot_currency_check.sh"
if [ -f "$BCC" ]; then
  bash "$BCC" --boot || true
else
  echo "[boot] WARN: boot_currency_check.sh 부재 — 부팅 자기-정합 검사 소실 (자동 최신화 배선 끊김)"
fi

# 7a-3. (2026-07-26 도훈 승인) 게이트급 훅 "발화 0회" 감지 — events.jsonl 원장 소비면.
#   이 저장소 실패부류의 지문은 "경고 0"이 아니라 **"발화 0"**이다(harness_health 가 훅 등록
#   0건을 INFO 로 통과·게이트가 조용히 미발화한 사례들). v7.0 Sprint 6 원장이 그 목적이었으나
#   writer 가 죽어 49일 STALE 이었고, _shared_parse.sh 자동 emit(4.0ms/회)으로 배관을 살렸다.
#   관측창이 요구 기간보다 짧으면 판정 보류(미측정 ≠ 0). WARN-only.
HFC="$PROJECT/02_Infrastructure/ops/hook_fire_coverage.sh"
if [ -f "$HFC" ]; then
  bash "$HFC" --boot || true
fi

# 7b. v1.2 Charter §10 Measurement Coherence Health Score (Component D)
BS_PATH="$PROJECT/qepm/mailbox/governor/book_state.json"
MBA_R="$PROJECT/02_Infrastructure/portfolio/measurement_basis_audit.R"
MBA_TIER=""
if [ -f "$BS_PATH" ] && [ -f "$MBA_R" ]; then
  # (2026-07-26 CBA-02 수리) 구현은 stderr 를 /dev/null 로 버리고 빈 출력을 양성 톤
  #   "SKIP (no admitted_ids or audit error)" 로 융합했다 — 감사가 크래시하면 MBA_TIER=""
  #   가 되어 7c 게이트([[ DRIFTED || WARNING ]])가 **영영 미발화**하고, 실제로 DRIFTED 인
  #   북이 계측 사망과 함께 '조용히 정상' 부팅으로 위장된다. 크래시와 admitted-0 을 구분한다.
  MBA_RAW=$(Rscript "$MBA_R" "$BS_PATH" "$PROJECT/qepm/mailbox/worktask" 2>&1); MBA_RC=$?
  MBA_OUT=$(printf '%s' "$MBA_RAW" | grep -E "(Book score:|Tier:)" | head -2 | tr '\n' ' ')
  if [ -n "$MBA_OUT" ]; then
    echo "[boot] Measurement coherence: $MBA_OUT"
    MBA_TIER=$(echo "$MBA_OUT" | grep -oE 'Tier: [A-Z]+' | awk '{print $2}' | head -1)
  elif [ "$MBA_RC" != "0" ]; then
    echo "[boot] WARN: coherence audit FAILED (exit $MBA_RC) — 판정 없음이지 정상 아님. 7c 백필 게이트도 미발화"
    echo "[boot]    출력 말미: $(printf '%s' "$MBA_RAW" | tail -2 | tr '\n' ' ' | cut -c1-160)"
  elif printf '%s' "$MBA_RAW" | grep -q "NO_ADMITTED_IDS"; then
    echo "[boot] Measurement coherence: SKIP (admitted_ids 0건 — 판정 대상 없음)"
  else
    echo "[boot] WARN: coherence 출력에 Book score/Tier 부재 (exit 0) — 출력 포맷 드리프트 의심"
    echo "[boot]    출력 말미: $(printf '%s' "$MBA_RAW" | tail -2 | tr '\n' ' ' | cut -c1-160)"
  fi
fi

# ── AST v1.1 Step 4 사이드카 실전 캡처 노출 (2026-08-02 신설) ──────────────────
#  ★신설 사유(실사고): Step 4 는 07-25 배선 후 8일간 아무 경고 없이 **실전 레코드 0건**
#  이었다. 원장은 399행이라 겉보기엔 "쌓이고 있음"이었으나 전량 테스트 배터리 산물이었고,
#  그 상태로 Step 5(N>=30 -> complexity_prior 추정 -> alpha 프롬프트 주입)에 진입하면
#  합성 데이터로 사전분포를 만들게 된다. 부팅이 이 수치를 보지 않았기에 아무도 몰랐다.
#  → live_with_ast(실전 구조특징 표본)를 상시 노출한다. 총행수가 아니라 **실전 수**가 지문이다.
AST_SC_R="$PROJECT/02_Infrastructure/contracts/ast_sidecar.R"
if [ -f "$AST_SC_R" ]; then
  # cd 후 상대경로 — QM_ROOT 미설정 세션에서도 동작(경로 하드코딩·환경변수 의존 회피)
  AST_SC_OUT=$(cd "$PROJECT" && Rscript -e 'source("02_Infrastructure/contracts/ast_sidecar.R"); s <- ast_sidecar_status(); cat(sprintf("total=%s live=%s live_with_ast=%s legacy=%s", s$total, s$live, s$live_with_ast, s$legacy_unlabeled))' 2>/dev/null | tr -d '\r' | tail -1)
  if [ -n "$AST_SC_OUT" ]; then
    AST_LWA=$(printf '%s' "$AST_SC_OUT" | grep -oE 'live_with_ast=[0-9]+' | cut -d= -f2)
    if [ "${AST_LWA:-0}" -ge 30 ] 2>/dev/null; then
      echo "[boot] AST sidecar: $AST_SC_OUT — ★Step 5 진입 조건(N>=30) 충족, complexity_prior 추정 가능"
    elif [ "${AST_LWA:-0}" -gt 0 ] 2>/dev/null; then
      echo "[boot] AST sidecar: $AST_SC_OUT — 실전 적립 중 (Step 5 는 live_with_ast>=30 부터)"
    else
      echo "[boot] AST sidecar: $AST_SC_OUT — 실전 캡처 0 (배선은 존재. 라운드가 계약 경유를 안 하면 0 유지)"
    fi
  else
    echo "[boot] WARN: AST sidecar 상태 산출 실패 — 계측 사망과 '아직 0' 을 구분 불가"
  fi
fi

# ── 벤치마크 2소스 정합 (2026-08-02 신설) ────────────────────────────────────
#  ★신설 사유(실사고): RAWDATA.parquet::BM_Ret 과 benchmark.parquet::BM_Ret 은 독립
#  생성 경로(krx_build_rawdata.R:223 자체계산 / incremental_update_file.R:181 조인)인데
#  정합 검사가 없었다. 2026-07 에 8일이 갈렸고 4일은 RAWDATA 가 정확히 0 —
#  07-28 폭락 -11.55% 가 0으로 소실(월 누적 -17.70% vs 정본 -23.63%, 5.93%p 괴리).
#  값 0 은 "그날 안 움직였다"로 읽혀 결손이 정상 데이터로 위장된다. 소스가 둘이면
#  정합 검사가 있어야 한다 — 07-25 date32 writer 계통(감지장치 0, 7일 방치)의 재발.
#  최근 400일만 대조(전 기간 스캔은 14M행 — 부팅 지연 회피. 과거 구간은 배터리가 담당).
BSP_R="$PROJECT/02_Infrastructure/validation/benchmark_source_parity.R"
if [ -f "$BSP_R" ]; then
  BSP_OUT=$(cd "$PROJECT" && Rscript 02_Infrastructure/validation/benchmark_source_parity.R 400 2>/dev/null | tr -d '\r' | grep -m1 '^\[benchmark_source_parity\]')
  if [ -n "$BSP_OUT" ]; then
    case "$BSP_OUT" in
      *CRITICAL*) echo "[boot] WARN: ${BSP_OUT#\[benchmark_source_parity\] } — 정본=benchmark.parquet. 7월 등 해당 구간 포함 측정 전 bench 소스 확인" ;;
      *UNMEASURED*) echo "[boot] WARN: 벤치 정합 미측정 (소스 부재) — '정상'과 구분할 것" ;;
      *) echo "[boot] 벤치 2소스 정합: ${BSP_OUT#\[benchmark_source_parity\] }" ;;
    esac
  else
    echo "[boot] WARN: 벤치 정합 검사 산출 실패 — 계측 사망과 정상을 구분 불가"
  fi
fi

# 7c. Layer 2 — DRIFTED/WARNING 감지 시 cert backfill audit auto 호출
CERT_BACKFILL_R="$PROJECT/02_Infrastructure/ops/cert_backfill_audit.R"
if [[ "$MBA_TIER" == "DRIFTED" || "$MBA_TIER" == "WARNING" ]] && [ -f "$CERT_BACKFILL_R" ]; then
  echo "[boot] Coherence $MBA_TIER detected — cert_backfill_audit.R --auto 호출"
  BACKFILL_OUT=$(cd "$PROJECT" && Rscript "$CERT_BACKFILL_R" --auto 2>&1); BACKFILL_RC=$?
  # (2026-07-26 CBA-03 수리) exit code 를 아무데서도 안 봐서, 스크립트가 기동 직후 죽어도
  #   grep -c 가 0 을 내고 "0 cert(s) issued" 로 보고됐다 — 정상 실행·대상 0건과 형태가 동일.
  #   ("총계 0 = 성공 아니라 계측 사망" 부류)
  if [ "${BACKFILL_RC:-0}" != "0" ]; then
    echo "[boot] WARN: backfill script FAILED (exit ${BACKFILL_RC}) — 아래 집계는 신뢰 불가"
    echo "[boot]    출력 말미: $(printf '%s' "$BACKFILL_OUT" | tail -2 | tr '
' ' ' | cut -c1-160)"
  fi
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
  # (2026-07-26 probe① 도훈 승인) warn 축 노출 + 자가검산 — 구판은 pass/fail/skip만 파싱해
  # soak WARN(critical, human 확인 의무)이 이름 없이 상태문자 "WARN"에만 묻혔고,
  # pass+fail+warn+skip ≠ 총 check수여도 침묵(파싱 결손 불가시)이었다.
  V8_PARSED=$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    s = d.get('summary', {})
    checks = d.get('checks', []) or []
    warns = ';'.join(str(c.get('name','?')) for c in checks
                     if str(c.get('status','')).upper() == 'WARN')
    print(f\"{d.get('overall','?')}|{s.get('pass','?')}|{s.get('fail','?')}|{s.get('warn','?')}|{s.get('skip','?')}|{len(checks)}|{warns}\")
except Exception:
    print('?|?|?|?|?|?|')
" < "$V8_TMP" 2>/dev/null || echo "?|?|?|?|?|?|")
  rm -f "$V8_TMP"
  IFS='|' read -r V8_OVERALL V8_PASS V8_FAIL V8_WARN V8_SKIP V8_NCHK V8_WARN_NAMES <<< "$V8_PARSED"
  echo "[boot] v8 readiness (--no-write, ${V8_NCHK:-?} check incl v8_architecture): $V8_OVERALL — pass=$V8_PASS fail=$V8_FAIL warn=$V8_WARN skip=$V8_SKIP (e2e+timeline SKIP 정상, memory_health cached)"
  if [ "${V8_WARN:-0}" != "0" ] && [ "${V8_WARN:-?}" != "?" ] && [ -n "$V8_WARN_NAMES" ]; then
    echo "[boot]    warn 항목: ${V8_WARN_NAMES//;/ · } (soak류 = human 확인 의무)"
  fi
  # 자가검산: 파싱된 4축 합 ≠ 총 check수 → 파서/스키마 드리프트로 축이 새는 중
  if [ "${V8_NCHK:-?}" != "?" ] && [ "${V8_PASS:-?}" != "?" ]; then
    V8_SUM=$(( ${V8_PASS:-0} + ${V8_FAIL:-0} + ${V8_WARN:-0} + ${V8_SKIP:-0} ))
    if [ "$V8_SUM" != "$V8_NCHK" ]; then
      echo "[boot] WARN: readiness 자가검산 불일치 — pass+fail+warn+skip=$V8_SUM ≠ checks=$V8_NCHK (파서/스키마 드리프트, 축 결손 의심)"
    fi
  fi
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
# (2026-07-26 부팅감사 수리) inbox 디렉터리 부재 시 0이 아니라 n/a — 0은 "비었음"의 관측이어야
# 하는데 구판은 경로가 없어도 0을 찍어 상수-0이 관측처럼 보였다 (계측 사망 부류).
_inbox_cnt() {
  local d="$PROJECT/qepm/mailbox/$1/inbox"
  if [ -d "$d" ]; then ls "$d"/TODO_*.json 2>/dev/null | wc -l | tr -d ' '; else echo "n/a"; fi
}
ALPHA_T=$(_inbox_cnt alpha)
RISK_T=$(_inbox_cnt risk)
OPT_T=$(_inbox_cnt optimizer)
FORGE_T=$(_inbox_cnt forge)
JUDGE_T=$(_inbox_cnt judge)
GOV_T=$(_inbox_cnt governor)

# Work Task 상태 — (2026-07-26 정직 라벨) 이 수는 역대 WT 디렉터리 누적 총수이지 진행중이 아니다.
WT_ACTIVE=$(ls -d "$PROJECT"/qepm/mailbox/worktask/WT*_*/ 2>/dev/null | wc -l | tr -d ' ')

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
  if [ "$AX_CACHE_COUNT" = "?" ]; then
    # (2026-07-26) 카운터 사망 시 "?" = "?" 비교가 FULL로 성립하던 트랩 — 미상은 일치가 아니다
    AX_CACHE_STATUS="UNKNOWN (카운터 미가용 — python3/파싱 실패)"
  elif [ "$AX_CACHE_COUNT" = "$AX_DOC_ACTIVE" ]; then
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
    # Layer4 removal 감지 (WT-D20260702_002): β overlay(AR/faith) 제거 여부
    aid0 = admitted[0] if admitted else ''
    layer4_removed = ('LAYER4 REMOVED' in sched) or ('noLayer4' in aid0)
    beta_r05 = float((r05_state.get('beta_r05_params') or {}).get('NORMAL', 1.0))
    lines = []
    if admitted:
        w_pct = round(float(weights.get(aid0, 0)) * 100)
        lines.append(f'PG2 admit:  {aid0} ({w_pct}%, {updated}~)')
        if layer4_removed:
            # 현 book = STR_1715 × m4 × β_R05 (Layer4 β-overlay 제거) — 지표는 layer4_removal 이벤트 C_noL4
            l4ev = {}
            for k, v in d.items():
                if k.startswith('event_') and 'layer4_removal' in k and isinstance(v, dict):
                    l4ev = v; break
            # C_noL4 지표는 evidence_clean_3way_* sub-dict 안 — 키명 무관 robust 탐색
            m2 = {}
            for kk, vv in l4ev.items():
                if isinstance(vv, dict) and isinstance(vv.get('C_noL4'), dict):
                    m2 = vv['C_noL4']; break
            sr = m2.get('SR_geo'); cagr = m2.get('CAGR'); mdd = m2.get('MDD')
            calmar = m2.get('Calmar'); port_t = m2.get('PORT_t_NW_lag3')
            risk_pct = round(1.0 * beta_r05 * 100); cash_pct = 100 - risk_pct
            lines.append('PG2 layer:  STR_1715 alpha × M4 BOCPD × R05 Tail-Risk (Layer4 β-overlay REMOVED, WT-D20260702_002)')
            lines.append(f'PG2 regime: m4=NORMAL × β_R05={beta_r05:.2f} = {risk_pct}% risk + {cash_pct}% cash (admit baseline, noLayer4)')
            if sr is not None and cagr is not None and mdd is not None:
                extra = ''
                if calmar is not None: extra += f' / Calmar {calmar:.3f}'
                if port_t is not None: extra += f' / PORT_t {port_t:.2f}'
                lines.append(f'PG2 admit:  SR_geo {sr:.4f} / MDD -{mdd*100:.2f}% / CAGR {cagr*100:.2f}%{extra} (269m clean, stored admit-baseline)')
        else:
            # legacy Layer4 book (β overlay 활성) — 구 admit_basis_metrics 경로
            beta_ar = 0.7
            risk_pct = round(1.0 * beta_ar * beta_r05 * 100); cash_pct = 100 - risk_pct
            m = r05_log.get('admit_basis_metrics') or {}
            sr = m.get('SR_admit_255m'); mdd = m.get('MDD_pct_255m'); cagr = m.get('CAGR_pct_255m')
            lines.append(f'PG2 layer:  {n_layer}-Layer ({" + ".join(layers)})')
            if sr is not None and mdd is not None and cagr is not None:
                lines.append(f'PG2 regime: m4=NORMAL × β_AR={beta_ar:.2f} × β_R05={beta_r05:.2f} = {risk_pct}% risk + {cash_pct}% cash (admit baseline)')
                lines.append(f'PG2 admit:  SR {sr:.4f} / MDD {mdd:.2f}% / CAGR {cagr:.2f}% (255m PerfA, stored admit-baseline)')
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
    # (2026-07-26 probe① 도훈 승인) 감사 산출물 자신의 나이 검증 — audit이 멈추면
    # 낡은 스냅샷이 무기한 "FRESH"로 재보고되던 갭(감시가 감시 대상보다 먼저 죽는 부류).
    try:
        import datetime as _dt
        _ra = _dt.datetime.fromisoformat(str(d.get('ran_at', ''))[:19])
        _age_h = (_dt.datetime.now() - _ra).total_seconds() / 3600.0
        if _age_h > 36:
            line += "  ★audit 산출 자체가 %.0fh 낡음(36h+) — daily_refresh Step5 정지 의심, 아래 값은 과거 상태" % _age_h
    except Exception:
        line += "  ★audit ran_at 파싱 불가 — 나이 미상(신선 취급 금지)"
    # (2026-07-26 CFA-04) 경보 채널 자신의 실패 노출 — stale이 실재하는데 텔레그램이
    # 죽은 상태가 지금까지 어느 표면에도 안 남았다(무인 잡 stdout 소멸).
    _ad = d.get('alert_delivery')
    if _ad:
        line += "  ★ALERT-DELIVERY %s — stale 경보가 도훈에게 도달하지 않았다" % str(_ad)[:70]
    if crit:
        line += " — crit: " + ", ".join((os.path.basename(c.rstrip('/')) or c) for c in crit[:4])
    print(line)
    if key_stale:
        print("  WARN: 핵심 연구캐시 stale — " + ", ".join(os.path.basename(c) for c in key_stale)
              + " (성과수치 산출 전 갱신 의무 — performance-real-code-only)")
    else:
        print("  핵심 연구캐시(rawdata/benchmark/regime): FRESH")
    # IC 월-프론티어 (P3 2026-07-26): 월말 재빌드 체인 지연은 WARN 카운터에만 묻히면
    #   안 되는 상시 감시 항목 — 상태를 항상 이름으로 노출한다(정상도 1줄).
    #   판정 자체는 cache_freshness_audit(1c)/ic_frontier_check.R 소관, 여기선 읽기만.
    fr = next((r for r in res if str(r.get('check')) == 'ic_month_frontier'), None)
    if fr is not None:
        if fr.get('severity') in ('WARN', 'CRITICAL'):
            print("  %s: IC 프론티어 %s / 기대 %s — %s" % (
                fr.get('severity'), fr.get('ic_month', '?'),
                fr.get('expected_month', '?'), fr.get('note', '')))
        else:
            print("  IC 월-프론티어: %s = 기대치 (월말 재빌드 체인 정상)"
                  % fr.get('ic_month', '?'))
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
  # (2026-07-26 probe①) lock=시작 증명일 뿐 — done 마커로 완주/중도사망 구분 (구판은 시작=실행됨 오보)
  if [ -f "${MR_LOCK}.done" ]; then
    MR_D=$(cat "${MR_LOCK}.done" 2>/dev/null | head -1)
    MORNING_STATUS="MorningRun:  $(date +%Y-%m-%d) 완주 (시작 ${MR_T:-?} → 종료 ${MR_D:-?}) — paper/router/dispatch + 평일 brief/regime"
  else
    MORNING_STATUS="MorningRun:  $(date +%Y-%m-%d) ★시작됨(${MR_T:-?})·완주 마커 없음 — 진행 중이거나 중도 사망 (/tmp/qm_morning_run.log tail 확인)"
  fi
else
  MORNING_STATUS="MorningRun:  $(date +%Y-%m-%d) 미실행 (오늘 lock 부재 — 스케줄러 미발화/미도래. 수동: bash 02_Infrastructure/ops/morning_run.sh manual)"
fi

# 8h2. (2026-07-17 B4) deadman-lite — 무인 paper_recharge 라인 결손 사후 인지 (07-16 결측 실사례:
#      머신-오프 공백을 어느 표면도 알리지 않음). 최신 .done/mcp_discovery 파일명 날짜 vs 오늘 갭>1일 = WARN.
DM_LAST=$(ls "$PROJECT"/stage_artifacts/paper_recharge/paper_recharge_*.done "$PROJECT"/stage_artifacts/paper_recharge/mcp_discovery_*.json 2>/dev/null | grep -oE '(paper_recharge|mcp_discovery)_20[0-9]{6}' | grep -oE '20[0-9]{6}' | sort | tail -1)
DM_TS=""; [ -n "$DM_LAST" ] && DM_TS=$(date -d "$DM_LAST" +%s 2>/dev/null || echo "")
if [ -n "$DM_TS" ]; then
  DM_GAP=$(( ($(date +%s) - DM_TS) / 86400 ))
  [ "$DM_GAP" -gt 1 ] && echo "[boot] WARN: 무인 paper_recharge 라인 결손 — 최신 산출 ${DM_LAST} (오늘과 ${DM_GAP}일 갭, 머신-오프/스케줄러 미발화 의심 — /tmp/qm_paper_recharge_boot.log 확인)"
else
  echo "[boot] WARN: paper_recharge .done/mcp_discovery 산출물 0건 — 무인 적재 라인 미가동 의심"
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

# hypothesis_index 재빌드 (2026-07-05 / 2026-07-17 B1 관측성) — 검색면 자동 정합. bootstrap이
#   lcode_corpus는 매 세션 무조건 regen하나 hypothesis_index는 안 해 다음 세션 첫 조회부터 stale
#   배너 상시 발화하던 갭 수리. .R 파일 경유 CLI(한글 -e 아님). lcode_corpus 백그라운드 job 이후
#   실행되도록 부트 말미 배치. (B1) 침묵 fail-open 폐지 — 실패 시 BOOT_FAILS 계상 + 사유 1줄
#   (부트 전체 중단 아님, 기존 BOOT_FAILS DEGRADED 패턴. 실측: 07-13 이후 4일 침묵 정지).
HI_R="$PROJECT/02_Infrastructure/tools/hypothesis_index.R"
if [ -f "$HI_R" ]; then
  HI_FULL=$(cd "$PROJECT" && Rscript "$HI_R" build 2>&1)
  HI_RC=$?
  HI_OUT=$(echo "$HI_FULL" | grep -oE '\[hypothesis_index\].*entries.*' | tail -1 || true)
  if [ "$HI_RC" -eq 0 ] && [ -n "$HI_OUT" ]; then
    echo "[boot] hypothesis_index rebuilt: $HI_OUT"
  else
    HI_ERR=$(echo "$HI_FULL" | grep -iE 'error|오류|fail' | head -1)
    echo "[boot] ERROR: hypothesis_index 재빌드 실패 (rc=$HI_RC) — ${HI_ERR:-$(echo "$HI_FULL" | tail -1)} (중복실험 방지 게이트 stale 위험)"
    BOOT_FAILS=$((BOOT_FAILS+1))
  fi
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
  echo "=== 부트스트랩 완료 (Qvest v8.3 — Fable 5-Native · 4-Mode +RAMP · 알파 발굴 중심 · 실측 거버넌스) ==="
fi

# (2026-07-17 B2) 부트 스탬프 — SessionStart 카나리아(hooks/boot_stamp_check.sh)의 신선도 판정 원천.
#   07-05 이후 12일 무부트 세션 가동 실측 대응. fail-soft (스탬프 기록 실패가 부트를 죽이지 않음).
mkdir -p "$PROJECT/.cache" 2>/dev/null || true
printf '{"ts":"%s","ts_epoch":%s,"boot_fails":%s}\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$(date +%s)" "${BOOT_FAILS:-0}" > "$PROJECT/.cache/boot_stamp.json" 2>/dev/null || true
if [ -n "$PG2_INFO" ]; then
  echo "$PG2_INFO"
fi
echo "v8.3:       알파 발굴 중심 재편(canonical PORT_t 1급·dual-basis·frontier 큐 확인 의무) + Fable 5 정합(모델 핀 제거·상속) / 4-Mode 헌법(alpha-search 논문복제·K200∪KQ150·2005 / factor-rotation Lane3 / RAMP Gate0~11 / Axiom r7) / 실측 거버넌스 / register_module 자동흐름"
echo "v8.0 base:  R+Python 1급 / SR목표 2.5 / agent effort(judge·gov xhigh) / axiom_context_inject / qvest-*-style skill"
echo "Modes:      ① QEPM(/worktask) ② alpha-search ③ factor-rotation ④ RAMP(/ramp · Gate0~11·CCS 13-score · governor 정지/자본 수동) — CLAUDE.md 4-Mode 헌법(RAMP 2026-06-17)"
echo "Skills:     $(ls "$PROJECT"/.claude/skills/*/SKILL.md 2>/dev/null | wc -l)개 (2026-07-24 C3: exec/mon=off 은닉·리서치 3종=user-invocable 스텁·구 worktask/telegram-protocol 삭제)"
echo "Hooks:      settings.json 등록 (harness_health 결과 위 참조)"
# ── 감시 probe 2종 (2026-07-25) ────────────────────────────────────────────
#   hook_integrity_check : 훅 *집행*이 이 트리에서 실제로 사는가 (라우터 열화 탐지)
#   suite_totals_watch   : 계측 사망은 '실패'가 아니라 '총계 감소'로 온다
#
# ★감시의 감시 (next_probe ④): 종전 배선은 `[ -f ... ] && bash ... || true` 라
#   **스크립트가 사라지거나 무출력이면 아무 흔적 없이 조용히 없어졌다.** 이 아크가
#   내내 고쳐온 구조(가드가 빠져도 신호가 없음)를 감시 도구 자신이 갖고 있던 셈이다.
#   → 부재·무출력·비정상종료를 전부 **가시적 경고**로 바꾼다. 여전히 부트는 안 깬다.
_run_probe() {
  local name="$1"; shift
  local path="$PROJECT/02_Infrastructure/ops/$name.sh"
  if [ ! -f "$path" ]; then
    echo "            ⚠ [$name] 감시 도구 부재 — 이 트리에 파일이 없습니다(감시 무력화)."
    return 0
  fi
  local out rc
  out=$(bash "$path" "$@" 2>&1); rc=$?
  if [ -z "$out" ]; then
    echo "            ⚠ [$name] 무출력 (rc=$rc) — 감시 도구 이상. 정상이면 항상 1줄 이상 출력합니다."
  else
    printf '%s\n' "$out" | sed 's/^/            /'
  fi
  return 0
}
_run_probe hook_integrity_check
_run_probe suite_totals_watch --check
echo "WT 누적:    ${WT_ACTIVE}건 (역대 디렉터리 총수 — 진행중 아님. 진행 상태는 wt_list())"
echo "Inbox:      alpha=$ALPHA_T risk=$RISK_T optimizer=$OPT_T forge=$FORGE_T judge=$JUDGE_T governor=$GOV_T"
echo "Axioms:     active=$AX_ACTIVE candidates=$AX_CAND (sot_map documented=$AX_DOC_ACTIVE: documented=$AX_DOCUMENTED_MODE / block=$AX_BLOCK_MODE / advisory=$AX_ADVISORY_MODE)"
echo "Cache_core: $AX_CACHE_STATUS"
# (2026-07-26 도훈 지시) 사용률 배너 제거 — 한도는 구독 외생 변수, 관리 변수로 취급 금지.
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
echo "다음: /qvest 5-B 절차 따라 Work Task 생성 + 6-agent 순차 spawn"
echo "  wt_create('{hypothesis}') -> alpha -> risk -> optimizer -> forge(실측권위) -> judge -> governor(수동)"
echo "===================================="
