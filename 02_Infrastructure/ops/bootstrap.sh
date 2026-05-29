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
cd "$PROJECT"

echo "━━━ Qvest v8.0 부트스트랩 (Opus 4.8 Native) ━━━"

# 1. 원격 제어 (텔레그램 listener 등 상시 데몬)
RC_SCRIPT="$PROJECT/02_Infrastructure/ops/persistent_remote_control.sh"
if [ ! -f "$RC_SCRIPT" ]; then
  RC_SCRIPT="$PROJECT/02_Infrastructure/persistent_remote_control.sh"
fi
if [ -f "$RC_SCRIPT" ]; then
  tmux has-session -t rc 2>/dev/null || \
    tmux new-session -d -s rc "bash '$RC_SCRIPT'"
  if tmux has-session -t rc 2>/dev/null; then
    echo "[boot] 원격 제어 ✓ (tmux rc)"
  else
    echo "[boot] 원격 제어 WARN: rc 세션 즉시 종료 — $RC_SCRIPT 내용 확인"
  fi
else
  echo "[boot] 원격 제어 SKIP: persistent_remote_control.sh 없음"
fi

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
bash "$PROJECT/02_Infrastructure/ops/cleanup.sh" --execute 2>/dev/null &
echo "[boot] Cleanup 백그라운드"

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
  fi
else
  echo "[boot] Memory health: SKIP (memory_knowledge_health.R 부재)"
fi

# 4b. memory_metadata_normalize selftest (v7.2.1 — fallback chain hard fail)
MMN_R="$PROJECT/02_Infrastructure/memory/memory_metadata_normalize.R"
if [ -f "$MMN_R" ]; then
  MMN_OUT=$(cd "$PROJECT" && Rscript "$MMN_R" selftest 2>&1 || true)
  if echo "$MMN_OUT" | grep -q 'selftest 2/2 PASS'; then
    echo "[boot] memory_metadata_normalize selftest 2/2 PASS ✓"
  else
    echo "[boot] WARN: memory_metadata_normalize selftest FAIL — promote helper 호환 위반 가능"
  fi
fi

# 4c. lcode_corpus rebuild (v7.2.1 — 4 source 통합, 백그라운드)
LCR_R="$PROJECT/02_Infrastructure/memory/lcode_corpus_rebuild.R"
if [ -f "$LCR_R" ]; then
  (cd "$PROJECT" && Rscript "$LCR_R" >/tmp/lcode_corpus_boot.log 2>&1) &
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

# 5. 데이터 리프레시 (백그라운드 — xlsx 증분 + KRX/FRED/ECOS)
REFRESH_LOG="/tmp/qm_boot_refresh_$(date +%Y%m%d_%H%M).log"
(cd "$PROJECT/02_Infrastructure" && bash "$PROJECT/02_Infrastructure/data/daily_refresh.sh" > "$REFRESH_LOG" 2>&1) &
REFRESH_PID=$!
echo "[boot] 데이터 리프레시 백그라운드 (PID=$REFRESH_PID, log=$REFRESH_LOG)"

# 6. v53 Axiom 엔진 주간 갱신 (백그라운드, 빠른 실행)
QVEST_PROJECT_DIR="$PROJECT" \
  python3 "$PROJECT/02_Infrastructure/axiom/lcode_harvester.py" >/tmp/axiom_boot.log 2>&1 &
echo "[boot] L-code harvester 백그라운드"

# 7. Hook health check
HH_OUT=$(bash "$PROJECT/02_Infrastructure/hooks/harness_health.sh" 2>&1)
HH_SUMMARY=$(echo "$HH_OUT" | grep -E "Result:" | head -1)
echo "[boot] $HH_SUMMARY"

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
  # L-314 follow-up: temp file 경유로 stdin pipe parse 문제 회피 + 1회 parse로 4값 동시 추출
  V8_TMP=$(mktemp)
  # qvest_v8_ready CLI exit code 0=PASS / 1=FAIL / 2=WARN — 모두 정상 JSON 반환. 'true'로 exit code 무시.
  bash "$QV8_CLI" --no-write --json > "$V8_TMP" 2>/dev/null || true
  [ -s "$V8_TMP" ] || echo "{}" > "$V8_TMP"
  V8_PARSED=$(python3 -c "
import json
try:
    with open('$V8_TMP') as fp:
        d = json.load(fp)
    s = d.get('summary', {})
    print(f\"{d.get('overall','?')}|{s.get('pass','?')}|{s.get('fail','?')}|{s.get('skip','?')}\")
except Exception:
    print('?|?|?|?')
" 2>/dev/null || echo "?|?|?|?")
  rm -f "$V8_TMP"
  IFS='|' read -r V8_OVERALL V8_PASS V8_FAIL V8_SKIP <<< "$V8_PARSED"
  echo "[boot] v8 readiness (--no-write, 15 check): $V8_OVERALL — pass=$V8_PASS fail=$V8_FAIL skip=$V8_SKIP (e2e+timeline SKIP 정상, memory_health cached)"
  if [ "${V8_FAIL:-99}" != "0" ] && [ "${V8_FAIL:-99}" != "?" ]; then
    echo "[boot] WARN: v8_readiness FAIL — bash 02_Infrastructure/tools/qvest_v8_ready --strict 직접 실행 권장"
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
  AX_DOC_ACTIVE=$(python3 -c "import json; d=json.load(open('$AX_SOT_MAP')); print(sum(1 for a in d.get('axioms',[]) if a.get('documented_active')))" 2>/dev/null || echo "?")
  AX_DOCUMENTED_MODE=$(python3 -c "import json; d=json.load(open('$AX_SOT_MAP')); print(sum(1 for a in d.get('axioms',[]) if a.get('documented_active') and a.get('enforcement_mode')=='documented'))" 2>/dev/null || echo "?")
  AX_BLOCK_MODE=$(python3 -c "import json; d=json.load(open('$AX_SOT_MAP')); print(sum(1 for a in d.get('axioms',[]) if a.get('documented_active') and a.get('enforcement_mode')=='block'))" 2>/dev/null || echo "?")
  AX_ADVISORY_MODE=$(python3 -c "import json; d=json.load(open('$AX_SOT_MAP')); print(sum(1 for a in d.get('axioms',[]) if a.get('documented_active') and a.get('enforcement_mode')=='advisory'))" 2>/dev/null || echo "?")
fi
# .cache/axiom_core.json STALE 표시 (derived cache, NOT SOT)
AX_CACHE_PATH="$PROJECT/.cache/axiom_core.json"
AX_CACHE_STATUS="MISSING"
if [ -f "$AX_CACHE_PATH" ]; then
  AX_CACHE_COUNT=$(python3 -c "import json; d=json.load(open('$AX_CACHE_PATH')); print(len(d.get('axioms',[])))" 2>/dev/null || echo "?")
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

echo ""
echo "━━━ 부트스트랩 완료 (Qvest v8.0 — Opus 4.8 Native · Polyglot · Workflow) ━━━"
if [ -n "$PG2_INFO" ]; then
  echo "$PG2_INFO"
fi
echo "v8.0:       R+Python 1급 / SR목표 2.5 / agent effort(judge·gov xhigh) / axiom_context_inject(unified_agent_guard 폐기) / qvest-*-style skill"
echo "Skills:     $(ls "$PROJECT"/.claude/skills/*/SKILL.md 2>/dev/null | wc -l)개 (worktask/alpha/risk/optimizer + qvest-*-style 4종)"
echo "Hooks:      settings.json 등록 (harness_health 결과 위 참조)"
echo "WT Active:  $WT_ACTIVE건"
echo "Inbox:      alpha=$ALPHA_T risk=$RISK_T optimizer=$OPT_T forge=$FORGE_T judge=$JUDGE_T governor=$GOV_T"
echo "Axioms:     active=$AX_ACTIVE candidates=$AX_CAND (sot_map documented=$AX_DOC_ACTIVE: documented=$AX_DOCUMENTED_MODE / block=$AX_BLOCK_MODE / advisory=$AX_ADVISORY_MODE)"
echo "Cache_core: $AX_CACHE_STATUS"
free -m | awk '/Mem:/ {printf "RAM:        %.0f%%\n", $3/$2*100}'
echo "Remote:     tmux rc 세션 가동 (persistent_remote_control)"
echo ""
echo "다음: /qvest 5-B 절차 따라 Work Task 생성 + 3-agent 순차 spawn"
echo "  wt_create('{hypothesis}') → alpha-research → risk-research → optimizer-research"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
