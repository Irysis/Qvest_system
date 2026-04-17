#!/bin/bash
#==============================================================================
# Forge Code Guard — PreToolUse[Write|Edit|Bash] Hook
# 1) R 코드 최적화 위반 차단 (Write/Edit) — OPT-1~6
# 2) ML Guard L-123 강제 (Write/Edit) — OPT-7 (MC-P1~P3)
# 3) Codex PIT Review 미완료 시 실행 차단 (Bash)
# 참조: optimized-backtest 스킬, ml-factor-model 스킬, CLAUDE.md
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)

# 각 필드를 개별 python3 호출로 추출 (content에 줄바꿈이 있어도 안전)
TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_name', ''))
" 2>/dev/null || echo "")

FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
" 2>/dev/null || echo "")

COMMAND=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('command', ''))
" 2>/dev/null || echo "")

CONTENT=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('content', '') + ti.get('new_string', ''))
" 2>/dev/null || echo "")

LOG="/tmp/forge_code_guard.log"

# ══════════════════════════════════════════════════════════════════
# A. Write/Edit → 코드 최적화 패턴 검사
# ══════════════════════════════════════════════════════════════════
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  [ -z "$CONTENT" ] && { echo '{}'; exit 0; }

  # ML Guard (OPT-7)는 모든 .R 파일에 적용
  # OPT-1~6은 run_all.R / factor_engine.R만 적용
  IS_R_FILE=""
  IS_STRATEGY_FILE=""
  case "$FILE_PATH" in
    *.R|*.r) IS_R_FILE="yes" ;;
  esac
  case "$FILE_PATH" in
    *run_all.R|*factor_engine.R) IS_STRATEGY_FILE="yes" ;;
  esac

  # R 파일이 아니면 skip
  [ -z "$IS_R_FILE" ] && { echo '{}'; exit 0; }

  VIOLATIONS=""

  # === OPT-7: ML Guard (L-123 강제) — 모든 R 파일 대상 ===
  ML_DETECTED=""
  if echo "$CONTENT" | grep -qE 'library\(xgboost\)|library\(lightgbm\)|library\(randomForest\)|library\(ranger\)|library\(keras\)|library\(torch\)'; then
    ML_DETECTED="tree_or_nn"
  elif echo "$CONTENT" | grep -qE 'cv\.glmnet.*fwd_ret|cv\.glmnet.*target|cv\.glmnet.*binomial' \
       && echo "$CONTENT" | grep -qE 'fwd_ret|forward.*return|target.*ret'; then
    ML_DETECTED="linear_ml"
  fi

  if [ -n "$ML_DETECTED" ]; then
    if ! echo "$CONTENT" | grep -qEi 'mutual_info|MI_prefilter|ic_prefilter|top.?50|prefilter.*50|feature.*select.*50'; then
      VIOLATIONS="${VIOLATIONS}OPT-7/MC-P1: ML 코드에 MI/IC prefilter 미발견. L-123 §2.3: 309→50 pre-select 필수.\n"
    fi
    if ! echo "$CONTENT" | grep -qE 'fdb_daily|factor_db_daily|daily.*chunk|load_daily'; then
      VIOLATIONS="${VIOLATIONS}OPT-7/MC-P2: 일간 Factor DB 미참조. L-123 §4: 일간 5700일 학습 필수.\n"
    fi
    if ! echo "$CONTENT" | grep -qEi 'walk.?forward|expanding.*window|oos_year|oos_yr|MC1'; then
      VIOLATIONS="${VIOLATIONS}OPT-7/MC-P3: Walk-forward expanding 패턴 미발견. L-123 MC1 위반.\n"
    fi
    echo "$(date +%H:%M:%S) ML_GUARD: $FILE_PATH — $ML_DETECTED" >> "$LOG"
  fi

  # === OPT-1~6은 전략 파일(run_all.R, factor_engine.R)만 ===
  if [ -z "$IS_STRATEGY_FILE" ]; then
    # 전략 파일이 아니면 OPT-1~6 건너뛰고 ML Guard 결과만 평가
    if [ -n "$VIOLATIONS" ]; then
      echo "$(date +%H:%M:%S) BLOCK: $FILE_PATH" >> "$LOG"
      printf '%b' "$VIOLATIONS" >> "$LOG"
      REASON=$(printf '%b' "$VIOLATIONS" | tr '\n' ' ' | sed 's/"/\\"/g')
      printf '{"decision":"block","reason":"Forge Code Guard: %s ml-factor-model skill 참조."}' "$REASON"
      exit 0
    fi
    echo '{}'
    exit 0
  fi

  # OPT-1: 루프 내 parquet 반복 로드 (L-534)
  if echo "$CONTENT" | grep -qP 'for\s*\(' \
     && echo "$CONTENT" | grep -q 'load_month_factors'; then
    VIOLATIONS="${VIOLATIONS}OPT-1(L-534): for loop 내 load_month_factors() 금지. rbindlist bulk preload 패턴 사용.\n"
  fi
  if echo "$CONTENT" | grep -qP 'for\s*\(' \
     && echo "$CONTENT" | grep -q 'read_parquet'; then
    VIOLATIONS="${VIOLATIONS}OPT-1(L-534): for loop 내 read_parquet() 금지. 일괄 로드 후 메모리 필터.\n"
  fi

  # OPT-2: load_rawdata without use_cache
  if echo "$CONTENT" | grep -q 'load_rawdata' \
     && ! echo "$CONTENT" | grep -q 'use_cache.*TRUE'; then
    VIOLATIONS="${VIOLATIONS}OPT-2: load_rawdata(use_cache=TRUE) 필수.\n"
  fi

  # OPT-3: 인라인 daily NAV 루프 금지 — run_monthly_simulation() 또는 .compute_daily_nav() 사용 필수
  if echo "$CONTENT" | grep -qP 'for\s*\(' \
     && echo "$CONTENT" | grep -qE 'daily_val|daily_nav.*holdings|shares.*price_row|Close\)'; then
    VIOLATIONS="${VIOLATIONS}OPT-3: 인라인 daily NAV 루프 금지. run_monthly_simulation() 사용 (Rcpp sim_engine_nav.cpp 23x speedup 자동 적용).\n"
  fi

  # OPT-4: 독립 백테스트 2건+ 순차 실행 금지 — mclapply 병렬 필수
  # 패턴: for loop 내에서 run_monthly_simulation을 여러 variant로 호출
  # 허용: mclapply (COW fork, RAWDATA 복사 없음) 또는 future_lapply 또는 Agent tool 스폰
  if echo "$CONTENT" | grep -qP 'for\s*\(.*(method|variant|scoring|m\s+in)' \
     && echo "$CONTENT" | grep -q 'run_monthly_simulation' \
     && ! echo "$CONTENT" | grep -qE 'mclapply|future_lapply|future_sapply|plan\(multisession'; then
    VIOLATIONS="${VIOLATIONS}OPT-4: 독립 백테스트 순차 for loop 금지. mclapply(methods, ..., mc.cores=min(N, detectCores()-1)) 사용 (fork COW로 RAWDATA 복사 없음). 5건+ 대규모는 Agent tool 병렬 스폰 권장.\n"
  fi

  # OPT-5: stress_periods 하드코딩 시 8대 정본과 일치 검증
  # reference_stress_periods.md 정본: 9/11, GFC(2007-10), EU_Debt, China_Shock, Trade_War(2018-03), COVID(2020-01~06), Rate_Hike(2022-01~12), Iran_War(2026-02)
  if echo "$CONTENT" | grep -q 'stress_periods'; then
    STRESS_WARN=""
    # 정본 필수 키워드 체크
    echo "$CONTENT" | grep -q '2001-09' || STRESS_WARN="${STRESS_WARN}9/11 Terror(2001-09) 누락. "
    echo "$CONTENT" | grep -q '2007-10' || STRESS_WARN="${STRESS_WARN}GFC 시작일 2007-10 누락(2008 아님). "
    echo "$CONTENT" | grep -q '2018-03' || STRESS_WARN="${STRESS_WARN}Trade War 시작일 2018-03 누락. "
    echo "$CONTENT" | grep -q '2020-01' || STRESS_WARN="${STRESS_WARN}COVID 시작일 2020-01 누락. "
    echo "$CONTENT" | grep -q '2022-12' || STRESS_WARN="${STRESS_WARN}Rate Hike 종료일 2022-12 누락. "
    echo "$CONTENT" | grep -q '2026-02' || STRESS_WARN="${STRESS_WARN}Iran War(2026-02) 누락. "
    if [ -n "$STRESS_WARN" ]; then
      VIOLATIONS="${VIOLATIONS}OPT-5: stress_periods가 8대 정본(reference_stress_periods.md)과 불일치. ${STRESS_WARN}정본 참조 필수.\n"
    fi
  fi

  # OPT-6: Normal VaR 사용 차단 — EVT-VaR 또는 CF-VaR 사용 필수
  # 패턴: qnorm * sd( 또는 sd( * qnorm (정규 VaR 수동 계산) 탐지
  if echo "$CONTENT" | grep -qE 'qnorm.*\*.*sd\(|sd\(.*\*.*qnorm|VaR.*qnorm\(|qnorm\(.*sqrt\('; then
    VIOLATIONS="${VIOLATIONS}OPT-6: Normal VaR(qnorm*sd 패턴) 금지. compute_evt_var() 또는 compute_cf_var() 사용 (02_Infrastructure/portfolio/tail_risk_engine.R). Pfaff(2016) Ch.7 EVT-GPD 또는 Ch.6 Cornish-Fisher 기반 리스크 측정 필수.\n"
  fi

  # ─── v53 Sprint 3 P1-A: R-level 규칙 ─────────────────────────────────
  # OPT-9: 20종목 max (v53 신규) — n_hold / n_holdings / N_hold 리터럴 > 20 탐지
  # 대소문자 무관 + 함수 인자/변수 할당 모두 스캔
  if echo "$CONTENT" | grep -qEi '(n_hold(ings)?|N_HOLD(INGS)?)\s*(=|<-|=>)\s*[0-9]+L?' ; then
    N_VIOL=$(echo "$CONTENT" \
      | grep -oEi '(n_hold(ings)?|N_HOLD(INGS)?)\s*(=|<-)\s*[0-9]+L?' \
      | grep -oE '[0-9]+' | sort -un | awk '$1 > 20' | head -3 | tr '\n' ',' | sed 's/,$//')
    if [ -n "$N_VIOL" ]; then
      VIOLATIONS="${VIOLATIONS}OPT-9: 종목수 ${N_VIOL} > 20 (v53 신규 규칙). 단일 전략은 N<=20, 멀티슬리브 합산도 20 이하. CLAUDE.md '종목수 최대 20개' 참조.\n"
    fi
  fi

  # OPT-10: 유동성 필터 (LIQ_THRESHOLD 2e8 미달 탐지)
  if echo "$CONTENT" | grep -qE 'LIQ_THRESHOLD\s*(<-|=)\s*'; then
    if echo "$CONTENT" | grep -qE 'LIQ_THRESHOLD\s*(<-|=)\s*(1e[0-7]|[0-9]{1,8}e[0-7]|[0-9]{1,8}$)' \
       && ! echo "$CONTENT" | grep -qE 'LIQ_THRESHOLD\s*(<-|=)\s*([2-9]e8|[1-9][0-9]*e[89]|2[0-9]{8,}|[3-9][0-9]{8,})'; then
      VIOLATIONS="${VIOLATIONS}OPT-10: LIQ_THRESHOLD < 2e8 (2억원) 의심. CLAUDE.md '20일 평균 거래대금 >= 2억원'. 실투 무결성 침해.\n"
    fi
  fi
  # 유동성 필터 완전 누락 (run_all.R/factor_engine.R만)
  if [ -n "$IS_STRATEGY_FILE" ] \
     && ! echo "$CONTENT" | grep -qE 'LIQ_THRESHOLD|liq_threshold|LIQ_20d|liquidity_filter|TradVal.*frollmean'; then
    VIOLATIONS="${VIOLATIONS}OPT-10: 유동성 필터 코드 미발견 (LIQ_THRESHOLD 또는 frollmean(TradVal) 필수).\n"
  fi

  # OPT-11: VT/DD/FM t-1 lag 검증 (C9 강화)
  # 패턴 1: vol_target / dd_brake / factor_momentum 대입 후 당일 Ret에 곱 (same-day circular)
  if echo "$CONTENT" | grep -qE 'vol_target|VT_exposure|dd_brake|DD_brake|factor_mom|FM_z'; then
    # t-1 lag 흔적 체크: shift(/lag(/head(..., -1)/c(NA, ...[-n])
    if ! echo "$CONTENT" | grep -qEi 'shift\(|lag\(|head\(.*,\s*-[0-9]|c\(\s*NA.*\[1:\(?n-|dd_lag|vol_lag|fm_lag|_lag\s*(<-|=)'; then
      VIOLATIONS="${VIOLATIONS}OPT-11: VT/DD/FM 변수 사용 감지했으나 t-1 lag 패턴(shift/lag/head(-1)/_lag) 미발견. C9 same-day circular 의심. Session 37-38 검증: lag 미적용 시 SR 25~50% 과대추정.\n"
    fi
  fi

  # ─── v53 Sprint 3 P2-A: L-code reuse 탐지 (Forge S1 측) ──────────────
  # .cache/forge_ban_patterns.json + .cache/axiom_signals.json(reuse_penalty)
  PROJ_P2A=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
  BAN_JSON="$PROJ_P2A/.cache/forge_ban_patterns.json"
  AXIOM_JSON="$PROJ_P2A/.cache/axiom_signals.json"
  if [ -f "$BAN_JSON" ] || [ -f "$AXIOM_JSON" ]; then
    LCODE_REUSE=$(printf '%s' "$CONTENT" | python3 -c "
import sys, json, re
content = sys.stdin.read()
hits_block = []
hits_warn = []
try:
    import os
    if os.path.exists('$BAN_JSON'):
        bans = json.load(open('$BAN_JSON'))
        for p in bans.get('banned_patterns', []):
            rx = p.get('regex', '')
            if not rx: continue
            try:
                if re.search(rx, content, re.IGNORECASE | re.MULTILINE):
                    sev = p.get('severity', 'block')
                    line = f\"{p.get('pattern_id','?')} [{','.join(p.get('l_codes',[]))}] {p.get('reason','')[:100]}\"
                    (hits_block if sev == 'block' else hits_warn).append(line)
            except re.error: pass
    if os.path.exists('$AXIOM_JSON'):
        ax = json.load(open('$AXIOM_JSON'))
        for e in ax.get('reuse_penalty',{}).get('entries',[]):
            rx = e.get('regex') or e.get('pattern')
            if not rx: continue
            try:
                if re.search(rx, content, re.IGNORECASE):
                    line = f\"reuse_penalty [{e.get('l_code','?')}] {str(e.get('reason',''))[:100]}\"
                    hits_warn.append(line)
            except re.error: pass
except Exception as ex:
    print(f'ERR|{ex}')
    sys.exit(0)
for h in hits_block: print('BLOCK|'+h)
for h in hits_warn: print('WARN|'+h)
" 2>/dev/null)
    if [ -n "$LCODE_REUSE" ]; then
      BLOCKS=$(echo "$LCODE_REUSE" | grep '^BLOCK|' | cut -d'|' -f2- | head -3)
      WARNS=$(echo "$LCODE_REUSE" | grep '^WARN|' | cut -d'|' -f2- | head -3)
      if [ -n "$BLOCKS" ]; then
        BLOCKS_FMT=$(echo "$BLOCKS" | tr '\n' '|' | sed 's/|$//' | sed 's/|/ | /g')
        VIOLATIONS="${VIOLATIONS}OPT-12 (P2-A L-code reuse): 확정 실패 패턴 탐지 — ${BLOCKS_FMT}. methodology_memory.md 참조.\n"
      fi
      if [ -n "$WARNS" ]; then
        WARN_FMT=$(echo "$WARNS" | tr '\n' '|' | sed 's/|$//' | sed 's/|/ | /g')
        echo "$(date +%H:%M:%S) OPT-12_WARN: $FILE_PATH — $WARN_FMT" >> "$LOG"
      fi
    fi
  fi

  if [ -n "$VIOLATIONS" ]; then
    echo "$(date +%H:%M:%S) BLOCK: $FILE_PATH" >> "$LOG"
    printf '%b' "$VIOLATIONS" >> "$LOG"
    REASON=$(printf '%b' "$VIOLATIONS" | tr '\n' ' ' | sed 's/"/\\"/g')
    printf '{"decision":"block","reason":"Forge Code Guard: %s optimized-backtest skill 참조."}' "$REASON"
    exit 0
  fi

  # Warnings (allow but log)
  if echo "$CONTENT" | grep -qE 'merge\(' \
     && ! echo "$CONTENT" | grep -q 'setkey('; then
    echo "$(date +%H:%M:%S) WARN(OPT-W1): $FILE_PATH — setkey() 누락" >> "$LOG"
  fi
  if echo "$CONTENT" | grep -q 'copy(RAWDATA'; then
    echo "$(date +%H:%M:%S) WARN(OPT-W2): $FILE_PATH — copy(RAWDATA) 반복" >> "$LOG"
  fi

  # ── OPT-8: S1 Overlay Ban (v52 하네스) ──────────────────────────
  # S1 단계(s1_construction artifact 미존재)에서 overlay 코드 포함 시 차단
  if echo "$FILE_PATH" | grep -qE 'STR_[0-9]+.*/run_all\.R|STR_[0-9]+.*/factor_engine\.R'; then
    STR_ID=$(echo "$FILE_PATH" | grep -oP 'STR_\d+[A-Za-z0-9_]*' | head -1)
    if [ -n "$STR_ID" ]; then
      DIR_A=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
      S1_DONE=$(ls "$DIR_A/stage_artifacts/s1_construction_"*"${STR_ID}"*.json 2>/dev/null | head -1)
      S5_DONE=$(ls "$DIR_A/stage_artifacts/s5_research_slate_"*"${STR_ID}"*.json 2>/dev/null | head -1)
      # S1 미완료 AND S5 미진입 = 순수 S1 단계
      if [ -z "$S1_DONE" ] && [ -z "$S5_DONE" ]; then
        if echo "$CONTENT" | grep -qiE 'dd_brake|vol_target|regime_engine|mrs_score|overlay|cash_ratio.*exposure'; then
          echo "$(date +%H:%M:%S) OPT-8_BLOCK: $FILE_PATH — S1 overlay 금지" >> "$LOG"
          printf '{"decision":"block","reason":"OPT-8: S1 단계에서 overlay(dd_brake/vol_target/regime) 코드 금지. S5 Mutation에서만 허용. s1_construction artifact 미존재."}'
          exit 0
        fi
      fi
    fi
  fi

  echo '{}'
  exit 0
fi

# ══════════════════════════════════════════════════════════════════
# B. Bash → Codex PIT Review Gate (실행 전 검증 강제)
# ══════════════════════════════════════════════════════════════════
if [ "$TOOL_NAME" = "Bash" ]; then
  # run_all.R 실행 감지
  if echo "$COMMAND" | grep -qE 'Rscript.*source.*run_all|Rscript.*run_all\.R'; then
    # 테스트/인프라 코드는 gate 미적용
    case "$COMMAND" in
      *08_Tests*|*02_Infrastructure*|*test_*) echo '{}'; exit 0 ;;
    esac

    # ─── v53 Sprint 3 P3-A: Factor DB 신선도 체크 ─────────────────────
    PROJ_P3A=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
    MONTHLY_DB="$PROJ_P3A/.cache/factor_db"
    DAILY_DB="$PROJ_P3A/.cache/factor_db_daily"
    NOW_TS=$(date +%s)

    _max_mtime() {
      local dir="$1"
      [ -d "$dir" ] || { echo 0; return; }
      find "$dir" -maxdepth 1 -name "*.parquet" -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d'.' -f1
    }

    MONTH_MT=$(_max_mtime "$MONTHLY_DB")
    DAILY_MT=$(_max_mtime "$DAILY_DB")
    [ -z "$MONTH_MT" ] && MONTH_MT=0
    [ -z "$DAILY_MT" ] && DAILY_MT=0

    MONTH_AGE_D=$(( (NOW_TS - MONTH_MT) / 86400 ))
    DAILY_AGE_D=$(( (NOW_TS - DAILY_MT) / 86400 ))
    QVEST_ALLOW_STALE_DB="${QVEST_ALLOW_STALE_DB:-0}"

    STALE_BLOCK_REASON=""
    if [ "$MONTH_MT" -gt 0 ] && [ "$MONTH_AGE_D" -gt 30 ]; then
      STALE_BLOCK_REASON="monthly Factor DB age=${MONTH_AGE_D}d (> 30d)"
    fi
    if [ "$DAILY_MT" -gt 0 ] && [ "$DAILY_AGE_D" -gt 30 ]; then
      STALE_BLOCK_REASON="${STALE_BLOCK_REASON}${STALE_BLOCK_REASON:+ | }daily Factor DB age=${DAILY_AGE_D}d (> 30d)"
    fi

    if [ -n "$STALE_BLOCK_REASON" ] && [ "$QVEST_ALLOW_STALE_DB" != "1" ]; then
      echo "$(date +%H:%M:%S) P3-A_STALE_BLOCK: $STALE_BLOCK_REASON" >> "$LOG"
      printf '{"decision":"block","reason":"[P3-A Factor DB Freshness] %s. data-refresh skill 또는 update_factor_db_daily() 실행. QVEST_ALLOW_STALE_DB=1로 우회 가능."}' "$STALE_BLOCK_REASON"
      exit 0
    fi

    STALE_WARN=""
    if [ "$MONTH_MT" -gt 0 ] && [ "$MONTH_AGE_D" -gt 7 ]; then
      STALE_WARN="monthly age=${MONTH_AGE_D}d"
    fi
    if [ "$DAILY_MT" -gt 0 ] && [ "$DAILY_AGE_D" -gt 7 ]; then
      STALE_WARN="${STALE_WARN}${STALE_WARN:+ ; }daily age=${DAILY_AGE_D}d"
    fi
    if [ -n "$STALE_WARN" ]; then
      echo "$(date +%H:%M:%S) P3-A_STALE_WARN: $STALE_WARN" >> "$LOG"
    fi

    # 전략 디렉토리 추출 (cd "path" && Rscript 패턴)
    STRAT_NAME=$(echo "$COMMAND" | grep -oP 'STR_\d+[A-Za-z0-9_]*' | head -1)

    if [ -n "$STRAT_NAME" ]; then
      FLAG="/tmp/codex_pit_approved_${STRAT_NAME}.flag"
      if [ ! -f "$FLAG" ]; then
        echo "$(date +%H:%M:%S) PIT_GATE_BLOCK: $STRAT_NAME — Codex PIT review 미완료" >> "$LOG"
        printf '{"decision":"block","reason":"Codex PIT Review 미완료: %s. Q-Lead가 codex:codex-rescue로 C1~C15 검증 후 %s 생성 필요."}' "$STRAT_NAME" "$FLAG"
        exit 0
      else
        echo "$(date +%H:%M:%S) PIT_GATE_PASS: $STRAT_NAME" >> "$LOG"
      fi

      # ─── v53 Sprint 3 P0-A: PIT Engine v3 auto blocking_gate ────────
      # run_all.R 내용 해시 기반 캐시 (변경 없으면 재검사 skip, ~3s saving)
      PROJ=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
      STRAT_DIR=$(find "$PROJ/04_Research/strategies" -maxdepth 1 -type d -name "${STRAT_NAME}*" 2>/dev/null | head -1)
      if [ -n "$STRAT_DIR" ] && [ -d "$STRAT_DIR" ]; then
        RUN_ALL="$STRAT_DIR/run_all.R"
        FACTOR_ENGINE="$STRAT_DIR/factor_engine.R"
        CONTENT_HASH=""
        if [ -f "$RUN_ALL" ]; then
          CONTENT_HASH=$(cat "$RUN_ALL" "$FACTOR_ENGINE" 2>/dev/null | md5sum | cut -d' ' -f1)
        fi
        PIT_CACHE="/tmp/pit_v3_clean_${STRAT_NAME}_${CONTENT_HASH}.flag"
        QVEST_SKIP_PIT_V3="${QVEST_SKIP_PIT_V3:-0}"

        if [ "$QVEST_SKIP_PIT_V3" != "1" ] && [ -n "$CONTENT_HASH" ] && [ ! -f "$PIT_CACHE" ]; then
          # 오래된 cache 정리 (같은 전략 이전 해시)
          find /tmp -maxdepth 1 -name "pit_v3_clean_${STRAT_NAME}_*.flag" -mmin +10080 -delete 2>/dev/null
          PIT_OUT=$(cd "$PROJ" && timeout 45 Rscript -e "
options(warn = -1)
suppressPackageStartupMessages(source('02_Infrastructure/validation/pit_engine_v3.R'))
r <- pit_engine_v3\$blocking_gate('$STRAT_DIR', levels = c('static', 'ast'), verbose = FALSE)
cat(sprintf('PIT_RESULT|%s|%s|%d\n', if (isTRUE(r\$clean)) 'CLEAN' else 'FAIL', r\$severity, length(r\$violations)))
if (!isTRUE(r\$clean)) {
  for (v in r\$violations[1:min(5, length(r\$violations))]) {
    cat(sprintf('  - %s (line %s): %s\n',
      v\$code %||% 'PIT', v\$line %||% '?', substr(v\$match %||% v\$pattern %||% '?', 1, 80)))
  }
}
" 2>&1)
          PIT_STATUS=$(echo "$PIT_OUT" | grep '^PIT_RESULT|' | head -1 | cut -d'|' -f2)
          PIT_SEV=$(echo "$PIT_OUT" | grep '^PIT_RESULT|' | head -1 | cut -d'|' -f3)
          PIT_NV=$(echo "$PIT_OUT" | grep '^PIT_RESULT|' | head -1 | cut -d'|' -f4)

          if [ "$PIT_STATUS" = "CLEAN" ]; then
            touch "$PIT_CACHE"
            echo "$(date +%H:%M:%S) PIT_V3_CLEAN: $STRAT_NAME ($CONTENT_HASH)" >> "$LOG"
          else
            # 상위 5개 위반만 reason에 포함
            VIOLATIONS_BRIEF=$(echo "$PIT_OUT" | grep '^  -' | head -5 | tr '\n' '|' | sed 's/"/\\"/g; s/|/ | /g')
            echo "$(date +%H:%M:%S) PIT_V3_BLOCK: $STRAT_NAME severity=$PIT_SEV n=$PIT_NV" >> "$LOG"
            echo "$PIT_OUT" >> "$LOG"
            printf '{"decision":"block","reason":"[P0-A] PIT Engine v3 %s: %s — %d violations in %s. 상위: %s. 해결 후 재실행하거나 QVEST_SKIP_PIT_V3=1로 우회."}' \
              "$PIT_SEV" "$STRAT_NAME" "$PIT_NV" "$STRAT_DIR" "$VIOLATIONS_BRIEF"
            exit 0
          fi
        fi
      fi
    fi
  fi

  echo '{}'
  exit 0
fi

echo '{}'
exit 0
