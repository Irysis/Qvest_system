#!/usr/bin/env bash
#==============================================================================
# test_rf_b5_design.sh — B5 오버레이 자체 설계 **레인 끝까지** 양방향 검사 (2026-09-17)
#
# 대상: 02_Infrastructure/ops/rf_b5_design.sh (+ rf_b5_design_lib.R · rf_overlay_audit.sh · rf_overlay_admit_cli.R 실물 배선)
# 도훈 지시 2026-09-17: "매 강화 사이클마다 LLM 이 … 오버레이를 자체 설계" + "한 칸에 여러 오버레이 중첩"
#   + "오버레이층만 무한대로 탐색하는 버그 방지" + "오버레이 적대적 검증부".
# 시나리오 (claude = 가짜 실행 파일 RF_CLAUDE_BIN — 실제 모델 호출 0 · 한도 소모 0):
#   S1  정상: 새 arm 2 + 스택 포함 4칸 → probe·G1 감사(opus)·등재(source=b5_design) · 설계 source/round · 원장 라운드 · 기전 설계 백업
#   S1b [위반] 같은 entry 자동 재발화 → H1 거부 · LLM 호출 0
#   S2  probe 실패 arm → 삭제 + 방출 기록 · 미신고 파일 · 이름 규약 위반 · 기존 arm 파일 변조 복원 · 다른 레인 산출 불가침
#   S3  G1 감사 reject(실재 근거) → 삭제 + 방출 기록 · 그 arm 을 쓴 칸 제외
#   S4  정체(H3) → compose_only → 새 arm 무시·기록 · 감사 호출 0
#   S5  일간 상한(H2) → 할당 1 → 두 번째 arm 무시(quota)
#   S6  수동 재설계 → 덧붙임 + b5_redesign · [위반] 두 번째 재설계 → H1 거부
#   S7  유효 칸 2 < 3 → 폴백 · 기전 설계 불변 · 폴백 라운드 기록
#   S8  Fable 한도 → 훅이 1차 산출 치움 → opus 로 처음부터 → 등재 모델 opus
#   S9  401 → 환경 실패 · 산출 제거 · 라운드 미기록
#   S10 B5 착수된 entry → 발화 안 함(다음 블록 부정)
#   S11 설정 게이트(전역 정지 · b5_design 꺼짐)
# 격리: 샌드박스 루트(.cache/_test_rf_b5_design.<pid>/root) — 자식 Rscript 가 샌드박스를 루트로 읽는지 **사전 확인**하고, 아니면
#   레인을 한 번도 돌리지 않고 실패로 끝낸다(~/.Renviron 의 QM_ROOT 가 상속값을 덮는 실사고). 끝에 운영 등록부 해시 대조.
# 실행: bash 08_Tests/ops/test_rf_b5_design.sh
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
case "$ROOT" in /[A-Za-z]/*) command -v cygpath >/dev/null 2>&1 && ROOT=$(cygpath -m "$ROOT") ;; esac
cd "$ROOT" || exit 1
PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"; export QVEST_PY="$PY" PYTHONUTF8=1
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
T="$ROOT/.cache/_test_rf_b5_design.$$"; SB="$T/root"
rm -rf "$T"; mkdir -p "$T"
# S12 실물 잠금 픽스처(08_Tests/lib/dir_hold.R)가 남았으면 먼저 내보낸다 — 붙잡힌 디렉터리는 rm -rf 로 안 지워진다
trap '[ -s "$T/hold.ready" ] && { : > "$T/hold.stop"; sleep 0.5; }; rm -rf "$T"' EXIT
LANE="${QVEST_B5_TEST_LANE:-$ROOT/02_Infrastructure/ops/rf_b5_design.sh}"   # 돌연변이 검사용 재지정(사본은 저장소 밖 · QVEST_B5_CODE_ROOT 동반)
ADIR="$SB/02_Infrastructure/reinforcement/overlay_arms"
BID="T_E1"
FINAL="$SB/.cache/rf_block_design/${BID}_B5.json"
GD="$SB/.cache/rf_b5_design/$BID"
JL="$SB/jlog.jsonl"
unset QVEST_B5_MODEL QVEST_B5_EFFORT QVEST_OA_MODEL QVEST_OA_EFFORT QVEST_LLM_FALLBACK QVEST_B5_IGNORE_PAUSE QVEST_OA_CATALOG QVEST_OA_ARMDIR \
      QVEST_OA_OUT QVEST_OA_AXES QVEST_OA_LOG QVEST_B5_AUDIT_SH QVEST_B5_ADMIT_CLI QVEST_B5_LANE_BUDGET_SEC RF_CLAUDE_BIN

# 운영 등록부 해시(끝에 대조)
real_hash(){ for f in 06_Registry/reinforce_ledger_l1.json 06_Registry/overlay_catalog.json 06_Registry/overlay_arm_ledger.jsonl 06_Registry/reinforce_auto_config.json; do
  md5sum "$ROOT/$f" 2>/dev/null | cut -d' ' -f1; done; ls -1 "$ROOT/02_Infrastructure/reinforcement/overlay_arms" | md5sum | cut -d' ' -f1; }
REAL0=$(real_hash)
REAL_JL="$ROOT/.cache/reinforce_auto_log.jsonl"; REAL_JL_N=$( [ -f "$REAL_JL" ] && wc -l < "$REAL_JL" || echo 0 )

#── 픽스처 ─────────────────────────────────────────────────────────────────────
mkdir -p "$SB/06_Registry" "$SB/02_Infrastructure/reinforcement/overlay_arms" "$SB/02_Infrastructure/portfolio" "$SB/art/$BID" \
         "$SB/.cache/rf_block_design" "$SB/stage_artifacts/l_code/reinforcement"
cp "$ROOT/06_Registry/reinforce_program.json" "$ROOT/06_Registry/rf_overlay_adversary_axes.json" "$SB/06_Registry/"
cp "$ROOT/02_Infrastructure/reinforcement/overlay_probe.R" "$ROOT/02_Infrastructure/reinforcement/rf_overlay_admit.R" "$SB/02_Infrastructure/reinforcement/"
cp "$ROOT/02_Infrastructure/portfolio/weight_catalog.R" "$SB/02_Infrastructure/portfolio/"
cat > "$T/mk.py" <<'PYEOF'
import io, json, sys, datetime
what, sb = sys.argv[1], sys.argv[2]
def w(p, o): io.open(p, 'w', encoding='utf-8', newline='\n').write(json.dumps(o, ensure_ascii=False, indent=2))
if what == 'config':
    en_all, en_b5 = sys.argv[3] == '1', sys.argv[4] == '1'
    w(sb + '/06_Registry/reinforce_auto_config.json', {
        'enabled': en_all, 'claim_stale_hours': 6,
        'b5_design': {'enabled': en_b5, 'max_cells': 8, 'min_cells': 3, 'max_new_arms': 3, 'max_layers': 3, 'prior_entries': 12,
                      'guards': {'max_redesign_rounds': 1, 'daily_arm_cap': 6, 'stagnation_window': 2, 'max_active_generated': 40}},
        'llm': {'model': 'opus', 'effort': 'max', 'fable_limit_fallback': {'model': 'opus', 'effort': 'max'},
                'lanes': {'b5_design': {'model': 'fable', 'effort': 'max'}, 'overlay_audit': {'model': 'opus', 'effort': 'xhigh'}}}})
elif what == 'catalog':
    def arm(i, k, st='active', act='scalar_exposure', state='vol', src=None):
        a = {'id': i, 'kind': k, 'family': 'vol_target', 'basis': 'fixture ' + i, 'status': st, 'est_cost_min': 1, 'action': act, 'state': state}
        if src: a['source'] = src
        return a
    w(sb + '/06_Registry/overlay_catalog.json', {'schema': 'overlay_catalog_v1', 'note': 'fixture', 'families': {'vol_target': 'x'}, 'arms': [
        arm('arm_vol', 'fx_vol'), arm('arm_dd', 'fx_dd', act='cross_sectional', state='drawdown'), arm('arm_trend', 'fx_trend', state='trend'),
        arm('arm_old', 'fx_old', st='retired'), arm('pg2_risk_overlay_v1', 'pg2_risk_overlay', state='multivar', src='overlay_propose')]})
elif what == 'ledger':
    variant = sys.argv[3]
    def att(n, code, pt, art=None):
        a = {'n': n, 'cell_code': code, 'idea': '[%s] fixture' % code,
             'essence': {'cell_code': code, 'block': code.split('_')[0], 'port_t': pt, 'cagr': 0.22, 'mdd': 0.55, 'calmar': 0.38, 'oos_retention': 0.5, 'spec': ''}}
        if art: a['artifacts'] = art
        return a
    atts = [att(i, 'B1_%d' % i, float(i), sb + '/art/T_E1' if i == 5 else None) for i in range(1, 6)]
    if variant == 'b5attempted': atts.append(att(6, 'B5_16', 2.0))
    e1 = {'base_id': 'T_E1', 'status': 'active', 'base_grade': 'C', 'base_artifacts': '', 'attempts_used': len(atts), 'attempts': atts,
          'block_order': ['B1', 'B5', 'B2', 'B3', 'B4']}
    if variant == 'designed':   # 라운드 1 기록 → 자동 실행은 H1 거부(claim 획득 → 가드 → 해제만 도는 최단 경로 · S12)
        e1['b5_design'] = {'rounds': [{'round': 1, 'at': '2026-09-18T23:53:00+0900', 'source': 'b5_design_lane', 'n_cells': 3,
                                       'new_arms_admitted': 0, 'new_arms_rejected': 0, 'compose_only': False, 'fallback': False, 'new_arm_ids': []}]}
    ents = []
    if variant == 'stagnation':
        for k, day in (('X1', '01'), ('X2', '02')):
            ents.append({'base_id': 'T_' + k, 'status': 'exhausted', 'attempts_used': 0, 'attempts': [],
                         'b5_design': {'rounds': [{'round': 1, 'at': '2026-09-%sT10:00:00+0900' % day, 'source': 'b5_design_lane', 'n_cells': 3,
                                                   'new_arms_admitted': 1, 'new_arms_rejected': 0, 'compose_only': False, 'fallback': False,
                                                   'new_arm_ids': ['arm_%s' % k.lower()]}]}})
    ents.append(e1)
    w(sb + '/06_Registry/reinforce_ledger_l1.json', {'schema_version': 'reinforce_ledger_v2', 'layer': 1, 'max_attempts': 25, 'note': 'fixture', 'entries': ents,
        'combination_review': {'papers_since_last_review': 0, 'last_review_date': '', 'history': []}, 'last_updated': ''})
elif what == 'armledger':
    n = int(sys.argv[3]); today = datetime.date.today().isoformat()
    io.open(sb + '/06_Registry/overlay_arm_ledger.jsonl', 'w', encoding='utf-8', newline='\n').write(''.join(
        json.dumps({'record_type': 'arm_emission', 'kind': 'k%d' % i, 'emitted_at': today + 'T09:00:00+0900', 'source': 'b5_design'}) + '\n' for i in range(n)))
elif what == 'mech':
    w(sb + '/.cache/rf_block_design/T_E1_B5.json', {'block': 'B5', 'cells': [{'pick': 'arm_trend', 'label': 'mech1'}, {'pick': 'arm_vol', 'label': 'mech2'}, {'pick': 'arm_dd', 'label': 'mech3'}]})
elif what == 'nav':
    d = datetime.date(2005, 1, 31); rows_n = ['date,nav_net']; rows_b = ['date,benchmark_nav']
    nav = [1, 1.1, 0.88, 0.99, 1.2, 1.0, 0.9, 1.3, 1.35]; bn = [1, 1, 1, 1, 1, 0.9, 0.8, 1, 1]
    for i in range(len(nav)):
        m = (d.month - 1 + i) % 12 + 1; y = d.year + (d.month - 1 + i) // 12
        rows_n.append('%04d-%02d-28,%s' % (y, m, nav[i])); rows_b.append('%04d-%02d-28,%s' % (y, m, bn[i]))
    io.open(sb + '/art/T_E1/02_nav.csv', 'w', newline='\n').write('\n'.join(rows_n) + '\n')
    io.open(sb + '/art/T_E1/05_benchmark_returns.csv', 'w', newline='\n').write('\n'.join(rows_b) + '\n')
PYEOF
"$PY" "$T/mk.py" nav "$SB"
fx_arms(){   # 기존 arm 파일 2종(설계 전부터 있는 파일 — 레인이 지우거나 고치면 안 된다)
  rm -rf "$ADIR"; mkdir -p "$ADIR"
  cat > "$ADIR/fx_vol.R" <<'EOF'
overlay_expo_fx_vol <- function(H, t, ctx) {
  h <- H$rv60[is.finite(H$rv60)]
  if (length(h) < 24L) return(1)
  max(0, min(1, stats::median(h) / H$rv60[t]))
}
EOF
  printf '{"id":"arm_vol","family":"vol_target","basis":"fixture"}' > "$ADIR/fx_vol.arm.json"
  printf 'overlay_expo_fx_dd <- function(H, t, ctx) 1\n' > "$ADIR/fx_dd.R"
  printf '{"id":"arm_dd","family":"cross_sectional","basis":"fixture"}' > "$ADIR/fx_dd.arm.json"
}
reset_sb(){   # $1 = 원장 변형(base|b5attempted|stagnation) · $2 = 오늘 b5_design 방출 수
  "$PY" "$T/mk.py" config "$SB" 1 1; "$PY" "$T/mk.py" catalog "$SB"; "$PY" "$T/mk.py" ledger "$SB" "${1:-base}"
  "$PY" "$T/mk.py" armledger "$SB" "${2:-0}"; "$PY" "$T/mk.py" mech "$SB"
  fx_arms
  rm -rf "$SB/.cache/rf_b5_design" "$SB/.cache/rf_overlay_audit" "$SB/.cache/rf_b5_design.claim" "$SB/.cache/scheduler_logs" "$JL"
  : > "$STUB_CALLS"; : > "$STUB_AUDITS"; rm -f "$STUB_PROMPT_COPY"
}

# 가짜 claude — 설계 프롬프트(B5_DESIGN_OUTPUT_FILE=)와 감사 프롬프트(AUDIT_OUTPUT_FILE=)를 가른다
cat > "$T/claude_stub.sh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_CALLS"
model=""; prev=""
for a in "$@"; do [ "$prev" = "--model" ] && model="$a"; prev="$a"; done
prompt=$(cat)
if printf '%s\n' "$prompt" | grep -q '^AUDIT_OUTPUT_FILE='; then
  out=$(printf '%s\n' "$prompt" | sed -n 's/^AUDIT_OUTPUT_FILE=//p' | head -1 | tr -d '\r')
  axis=$(basename "$out" .json); axis=${axis#axis_}
  kind=$(printf '%s\n' "$prompt" | sed -n 's/^## 대상 arm: //p' | head -1 | tr -d '\r')
  printf '%s %s %s\n' "$axis" "$kind" "$model" >> "$STUB_AUDITS"
  if [ "$axis" = degenerate ] && [ "$kind" = "${STUB_AUDIT_REJECT_KIND:-}" ]; then
    code=$(printf '%s\n' "$prompt" | sed -n 's/^   2 | //p' | head -1 | tr -d '\r')
    printf '{"axis":"degenerate","verdict":"reject","findings":[{"type":"full_sample","evidence":"%s.R:2 %s","explanation":"fixture","duplicate_of":null}]}' "$kind" "$code" > "$out"
  else
    printf '{"axis":"%s","verdict":"pass","findings":[]}' "$axis" > "$out"
  fi
  echo "Done."; exit 0
fi
design=$(printf '%s\n' "$prompt" | sed -n 's/^B5_DESIGN_OUTPUT_FILE=//p' | head -1 | tr -d '\r')
adir=$(printf '%s\n' "$prompt" | sed -n 's/^B5_ARM_DIR=//p' | head -1 | tr -d '\r')
[ -n "$design" ] && [ -n "$adir" ] || { echo "stub: 산출 경로 없음"; exit 3; }
printf '%s' "$prompt" > "$STUB_PROMPT_COPY"
r=$(basename "$design" .json); r=${r#design_r}
good_scalar(){ cat > "$adir/$1.R" <<EOF
overlay_expo_$1 <- function(H, t, ctx) {
  h <- H\$rv60[is.finite(H\$rv60)]
  if (length(h) < 24L) return(1)
  v <- H\$rv60[t]
  if (!is.finite(v) || v <= 0) return(1)
  max(0, min(1, stats::median(h) / v))
}
EOF
  printf '{"id":"%s","family":"vol_target","action":"scalar_exposure","state":"vol","basis":"fixture scalar %s","est_cost_min":1,"external_data":"none"}' "$2" "$1" > "$adir/$1.arm.json"; }
good_xs(){ cat > "$adir/$1.R" <<EOF
overlay_expo_$1 <- function(H, t, ctx) {
  hd <- ctx\$hold
  if (is.null(hd) || !nrow(hd)) return(1)
  d <- H\$dd[is.finite(H\$dd)]
  if (length(d) < 24L) return(1)
  g <- stats::ecdf(d)(H\$dd[t])
  k <- rank(hd\$dbeta) / nrow(hd)
  data.table::data.table(Ticker = hd\$Ticker, e = pmax(0, pmin(1, 1 - g * k)))
}
EOF
  printf '{"id":"%s","family":"cross_sectional","action":"cross_sectional","state":"drawdown","basis":"fixture xs %s","est_cost_min":1,"external_data":"none"}' "$2" "$1" > "$adir/$1.arm.json"; }
lit_arm(){ cat > "$adir/$1.R" <<EOF
overlay_expo_$1 <- function(H, t, ctx) {
  if (is.finite(H\$dd[t]) && H\$dd[t] > 0.2) return(0.5)
  1
}
EOF
  printf '{"id":"%s","family":"drawdown","action":"scalar_exposure","state":"drawdown","basis":"fixture literal","est_cost_min":1}' "$2" > "$adir/$1.arm.json"; }
na(){ printf '{"kind":"%s","id":"%s","action":"%s","state":"%s","family":"fx","basis":"fixture","external_data":"none"}' "$1" "$2" "$3" "$4"; }
cell(){ local l="$1"; shift; local p=""; for x in "$@"; do p="${p:+$p,}\"$x\""; done; printf '{"picks":[%s],"label":"%s","why":"fixture"}' "$p" "$l"; }
wdesign(){ printf '{"schema":"rf_b5_design_v1","base_id":"T_E1","round":%s,"rationale":"fixture","cells":[%s],"new_arms":[%s]}' "$r" "$1" "$2" > "$design"; }
case "$STUB_SCENARIO:$model" in
  normal:*|quota:*)
    good_scalar "b5gen_vgap_$r" "vgap_${r}_arm"; good_xs "b5gen_xsdd_$r" "xsdd_${r}_arm"
    wdesign "$(cell v arm_vol),$(cell s1 arm_dd "vgap_${r}_arm"),$(cell s2 "xsdd_${r}_arm" arm_vol),$(cell s3 arm_trend arm_dd)" \
            "$(na "b5gen_vgap_$r" "vgap_${r}_arm" scalar_exposure vol),$(na "b5gen_xsdd_$r" "xsdd_${r}_arm" cross_sectional drawdown)" ;;
  probe_fail:*)
    lit_arm "b5gen_lit_$r" "lit_${r}_arm"; good_scalar "b5gen_good_$r" "good_${r}_arm"
    good_scalar "b5gen_stray_$r" "stray_${r}_arm"                              # 미신고
    good_scalar "b5gen_BAD" "bad_arm_x"                                        # 이름 규약 위반(대문자 · 라운드 접미 없음)
    good_scalar "gen_20260917_999999" "foreign_arm"                            # 다른 레인 산출 이름
    printf '# tampered by designer\n' >> "$adir/fx_vol.R"                     # 기존 arm 변조
    rm -f "$adir/fx_dd.arm.json"                                               # 기존 arm 메타 삭제
    wdesign "$(cell a arm_vol),$(cell b arm_dd),$(cell c arm_trend),$(cell d "lit_${r}_arm"),$(cell e "good_${r}_arm" arm_dd)" \
            "$(na "b5gen_lit_$r" "lit_${r}_arm" scalar_exposure drawdown),$(na "b5gen_good_$r" "good_${r}_arm" scalar_exposure vol),$(na "b5gen_BAD" "bad_arm_x" scalar_exposure vol)" ;;
  audit_reject:*)
    good_scalar "b5gen_audrej_$r" "audrej_${r}_arm"
    wdesign "$(cell a arm_vol),$(cell b arm_dd),$(cell c arm_trend arm_vol),$(cell d "audrej_${r}_arm" arm_dd)" "$(na "b5gen_audrej_$r" "audrej_${r}_arm" scalar_exposure vol)" ;;
  compose:*)
    good_scalar "b5gen_cmp_$r" "cmp_${r}_arm"; good_xs "b5gen_cmpx_$r" "cmpx_${r}_arm"
    wdesign "$(cell a arm_vol),$(cell b arm_dd arm_vol),$(cell c arm_trend),$(cell d "cmp_${r}_arm")" \
            "$(na "b5gen_cmp_$r" "cmp_${r}_arm" scalar_exposure vol),$(na "b5gen_cmpx_$r" "cmpx_${r}_arm" cross_sectional drawdown)" ;;
  redesign:*)
    wdesign "$(cell r1 arm_vol arm_dd),$(cell r2 arm_trend arm_vol),$(cell r3 arm_trend arm_dd),$(cell dup arm_vol)" "" ;;
  few_cells:*)
    wdesign "$(cell a arm_vol),$(cell b arm_dd),$(cell c arm_old)" "" ;;
  fable_limit:fable)
    good_scalar "b5gen_partial_$r" "partial_${r}_arm"; wdesign "$(cell a arm_vol)" ""
    echo "You've reached your Fable limit · resets 2am (Asia/Seoul)"; exit 1 ;;
  fable_limit:*)
    good_scalar "b5gen_opus_$r" "opus_${r}_arm"
    wdesign "$(cell a arm_vol),$(cell b arm_dd),$(cell c arm_trend),$(cell d "opus_${r}_arm" arm_dd)" "$(na "b5gen_opus_$r" "opus_${r}_arm" scalar_exposure vol)" ;;
  auth:*)
    good_scalar "b5gen_auth_$r" "auth_${r}_arm"; wdesign "$(cell a arm_vol),$(cell b arm_dd),$(cell c arm_trend)" ""
    echo "API Error: 401 OAuth access token has expired"; exit 1 ;;
  *) echo "stub: 알 수 없는 시나리오 $STUB_SCENARIO:$model"; exit 3 ;;
esac
echo "Done."; exit 0
STUBEOF
chmod +x "$T/claude_stub.sh"
export STUB_CALLS="$T/calls.log" STUB_AUDITS="$T/audits.log" STUB_PROMPT_COPY="$T/prompt_copy.txt"
: > "$STUB_CALLS"; : > "$STUB_AUDITS"

run_lane(){   # $1 = 시나리오 · 나머지 = 레인 인자
  export STUB_SCENARIO="$1"; shift
  QVEST_RF_ROOT="$SB" QVEST_RF_CONFIG="$SB/06_Registry/reinforce_auto_config.json" QVEST_RP_JLOG="$JL" RF_CLAUDE_BIN="$T/claude_stub.sh" \
    QVEST_OA_TIMEOUT=120 QVEST_B5_TIMEOUT=300 bash "$LANE" "$@" > "$T/lane_out.txt" 2>&1; LANE_RC=$?
}
jq_(){ "$PY" -c "
import json,io,sys
try: d=json.load(io.open(sys.argv[1],encoding='utf-8'))
except Exception: print(''); sys.exit(0)
for k in sys.argv[2].split('.'):
    if isinstance(d,list):
        try: d=d[int(k)]
        except Exception: d=None
    elif isinstance(d,dict): d=d.get(k)
    else: d=None
print(json.dumps(d,ensure_ascii=False) if isinstance(d,(dict,list)) else ('' if d is None else d))" "$1" "$2" 2>/dev/null | tr -d '\r'; }
evc(){ local n; n=$(grep -c "\"event\": *\"$1\"" "$JL" 2>/dev/null); echo "${n:-0}"; }
ncalls(){ local n; n=$(grep -c . "$STUB_CALLS" 2>/dev/null); echo "${n:-0}"; }
naudits(){ local n; n=$(grep -c . "$STUB_AUDITS" 2>/dev/null); echo "${n:-0}"; }
led_rows(){ "$PY" -c "
import json,io,sys
for l in io.open(sys.argv[1],encoding='utf-8'):
    l=l.strip()
    if not l: continue
    r=json.loads(l)
    if r.get('source')!='b5_design' or r.get('kind','').startswith('k'): continue
    print('%s|%s|%s|%s|%s|%s' % (r.get('kind'), r.get('admitted', True), r.get('rejected_stage',''), r.get('n_siblings'), r.get('generator_model'), r.get('selection_type')))
" "$SB/06_Registry/overlay_arm_ledger.jsonl" 2>/dev/null | tr -d '\r'; }
cat_has(){ "$PY" -c "
import json,io,sys
c=json.load(io.open(sys.argv[1],encoding='utf-8'))
print(' '.join('%s:%s:%s' % (a.get('id'),a.get('status'),a.get('source','')) for a in c['arms']))" "$SB/06_Registry/overlay_catalog.json" 2>/dev/null | tr -d '\r'; }
round_field(){ "$PY" -c "
import json,io,sys
L=json.load(io.open(sys.argv[1],encoding='utf-8'))
e=[x for x in L['entries'] if x['base_id']=='T_E1'][0]
rs=(e.get('b5_design') or {}).get('rounds') or []
if sys.argv[2]=='n': print(len(rs))
elif sys.argv[2]=='redesign': print(json.dumps(e.get('b5_redesign'),ensure_ascii=False) if e.get('b5_redesign') is not None else '')
else:
    v=rs[int(sys.argv[3])].get(sys.argv[2]) if rs else None
    print(json.dumps(v) if isinstance(v,(list,dict,bool)) else ('' if v is None else v))" "$SB/06_Registry/reinforce_ledger_l1.json" "$@" 2>/dev/null | tr -d '\r'; }
n_cells_final(){ "$PY" -c "
import json,io,sys
d=json.load(io.open(sys.argv[1],encoding='utf-8'))
print('%d|%s' % (len(d.get('cells') or []), ','.join(str(len(c.get('picks') or ([c['pick']] if c.get('pick') else []))) for c in d.get('cells') or [])))" "$FINAL" 2>/dev/null | tr -d '\r'; }

#── A. 사전 확인 · 배선 ─────────────────────────────────────────────────────────
echo "=== A. 사전 확인 · 레인 배선 ==="
bash -n "$LANE" && ok "A1 레인 문법" || ng "A1" "bash -n"
w=""
grep -q 'rf_llm_agent_run "\$PF"' "$LANE"                         || w="$w no_agent_run"
grep -q -- '--disallowed-tools "Bash,Agent"' "$LANE"               || w="$w bash_allowed"
grep -q -- '--allowed-tools "Read,Write,Edit,Glob,Grep"' "$LANE"   || w="$w tools"
grep -qE '^[[:space:]]*timeout [0-9]+ claude -p' "$LANE"           && w="$w direct_claude_call"
grep -q 'rf_llm_limit_hit "\$RUN_OUT"' "$LANE"                     || w="$w env_fail_not_run_out"
grep -q '^rf_llm_before_fallback()' "$LANE"                        || w="$w no_fallback_hook"
grep -q 'rf_llm_resolve b5_design' "$LANE"                         || w="$w no_resolve_lane"
grep -q 'R_ENVIRON_USER=' "$LANE"                                  || w="$w no_renviron_isolation"
[ -z "$w" ] && ok "A2 레인: 실행기·훅·이번 실행 출력 판정·Bash/Agent 금지·설정 레인 해석·자식 R 환경 격리" || ng "A2" "$w"
: > "$T/empty.Renviron"
CHILD=$(R_ENVIRON_USER="$T/empty.Renviron" QM_ROOT="$SB" Rscript -e 'cat(Sys.getenv("QM_ROOT"))' 2>/dev/null | tr -d '\r')
if [ "$CHILD" = "$SB" ]; then ok "A3 자식 Rscript 가 샌드박스를 QM_ROOT 로 읽는다(~/.Renviron 우회) — 레인 절 실행"
else
  ng "A3 자식 루트가 샌드박스가 아니다 — 레인을 돌리지 않고 종료(운영 오염 방지)" "[$CHILD]"
  printf '{"test":"rf_b5_design","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"; exit 1
fi

#── S1. 정상 ─────────────────────────────────────────────────────────────────────
echo "=== S1. 정상 — 새 arm 2 + 스택 4칸 ==="
reset_sb base 0
MECH_MD5=$(md5sum "$FINAL" | cut -d' ' -f1)
run_lane normal
if [ "$LANE_RC" = 0 ] && [ "$(jq_ "$FINAL" source)" = b5_design_lane ] && [ "$(jq_ "$FINAL" round)" = 1 ] && [ -n "$(jq_ "$FINAL" written_at)" ] \
   && [ "$(n_cells_final)" = "4|1,2,2,2" ]; then
  ok "S1a ★설계 쓰기 — source=b5_design_lane · round 1 · written_at · 4칸(단층 1 + 스택 3)"
else ng "S1a" "rc=$LANE_RC source=$(jq_ "$FINAL" source) cells=$(n_cells_final) $(tail -3 "$T/lane_out.txt" | tr '\n' ' ')"; fi
CH=$(cat_has)
if printf '%s' "$CH" | grep -q "vgap_1_arm:active:b5_design" && printf '%s' "$CH" | grep -q "xsdd_1_arm:active:b5_design" \
   && [ -f "$ADIR/b5gen_vgap_1.R" ] && [ -f "$ADIR/b5gen_xsdd_1.R" ] && [ "$(evc arm_admitted)" = 2 ]; then
  ok "S1b 새 arm 2 → probe·G1·등재 — 카탈로그 active · source=b5_design · 파일 존치"
else ng "S1b" "catalog=[$CH] admitted=$(evc arm_admitted)"; fi
LR=$(led_rows)
if printf '%s\n' "$LR" | grep -q "^b5gen_vgap_1|True||2|fable|sweep_candidate_family$" && printf '%s\n' "$LR" | grep -q "^b5gen_xsdd_1|True||2|fable|"; then
  ok "S1c 방출 원장 — source=b5_design · n_siblings=2(한 요청 방출 수) · generator=fable · sweep 후보군"
else ng "S1c" "[$LR]"; fi
if [ "$(round_field n)" = 1 ] && [ "$(round_field round 0)" = 1 ] && [ "$(round_field n_cells 0)" = 4 ] && [ "$(round_field new_arms_admitted 0)" = 2 ] \
   && [ "$(round_field fallback 0)" = false ] && [ "$(round_field compose_only 0)" = false ] && [ "$(round_field source 0)" = b5_design_lane ] && [ -z "$(round_field redesign)" ]; then
  ok "S1d 원장 b5_design.rounds[0] = {round 1 · n_cells 4 · arms +2 · fallback false · source} · b5_redesign 없음"
else ng "S1d" "n=$(round_field n) cells=$(round_field n_cells 0) adm=$(round_field new_arms_admitted 0) fb=$(round_field fallback 0)"; fi
BK="$GD/${BID}_B5.mech.json"
[ -f "$BK" ] && [ "$(md5sum "$BK" | cut -d' ' -f1)" = "$MECH_MD5" ] && [ -z "$(ls "$SB/.cache/rf_block_design" | grep -v "^${BID}_B5.json$")" ] \
  && ok "S1e 기전 설계 백업 = 레인 디렉터리(원본 해시 동일) · rf_block_design 에는 최종 설계 하나뿐" || ng "S1e" "$(ls "$GD" "$SB/.cache/rf_block_design" | tr '\n' ' ')"
C1=$(sed -n 1p "$STUB_CALLS")
if [ "$(ncalls)" = 7 ] && printf '%s' "$C1" | grep -q -- "--model fable --effort max --fallback-model opus" \
   && printf '%s' "$C1" | grep -q -- "--permission-mode acceptEdits" && printf '%s' "$C1" | grep -q -- "--disallowed-tools Bash,Agent" \
   && printf '%s' "$C1" | grep -q -- "--add-dir $ADIR" && printf '%s' "$C1" | grep -q -- "--add-dir $GD" \
   && [ "$(naudits)" = 6 ] && [ "$(grep -c ' opus$' "$STUB_AUDITS")" = 6 ]; then
  ok "S1f 호출 — 설계 1회(fable/max · 폴백 opus · acceptEdits · Bash/Agent 금지 · 쓰기 디렉터리 2) + 감사 6회(arm 2 × 축 3 · opus)"
else ng "S1f" "calls=$(ncalls) audits=$(naudits) c1=[$C1]"; fi
w=""
for e in b5_design_start overlay_guard_h1_once overlay_guard_h2_quota overlay_guard_h3_stagnation overlay_guard_h4_active_generated materials_written design_verified verify_done; do
  [ "$(evc "$e")" -ge 1 ] || w="$w $e"; done
[ -z "$w" ] && ok "S1g jlog — 시작·가드 H1~H4·재료·검증 이벤트" || ng "S1g 이벤트 누락" "$w"
if grep -q "## (1) 이 entry — T_E1" "$STUB_PROMPT_COPY" && grep -q "## (2) 바닥(floor) 낙폭 해부" "$STUB_PROMPT_COPY" && grep -q "B5_DESIGN_OUTPUT_FILE=$GD/design_r1.json" "$STUB_PROMPT_COPY" \
   && ! "$PY" -c "
import re,sys,io
t=io.open(sys.argv[1],encoding='utf-8').read()
bad=re.findall(r'(?<![\w.\-/])(19[89]\d|20[0-3]\d)(?![\w.\-/])', t)
sys.exit(0 if bad else 1)" "$STUB_PROMPT_COPY" && [ ! -d "$SB/.cache/rf_b5_design.claim" ]; then
  ok "S1h 프롬프트(stdin) — 재료 절 · 산출 경로 · 맨 연도 0 · claim 해제"
else ng "S1h" "prompt/claim"; fi
echo "=== S1b. 같은 entry 자동 재발화 ==="
N0=$(ncalls); run_lane normal
[ "$LANE_RC" = 0 ] && [ "$(ncalls)" = "$N0" ] && [ "$(evc b5_design_refused)" = 1 ] && grep -q '"why": "h1_already_designed"' "$JL" && [ "$(round_field n)" = 1 ] \
  && ok "S1i [위반] 라운드 1 기록 뒤 자동 재발화 → H1 거부 · LLM 호출 0 · 라운드 불변 ★핵심" || ng "S1i" "rc=$LANE_RC calls $N0→$(ncalls) refused=$(evc b5_design_refused)"

#── S2. probe 실패 · 미신고 · 이름 위반 · 기존 arm 변조 · 다른 레인 산출 ───────────────────────
echo "=== S2. probe 실패 + 레인 위생 ==="
reset_sb base 0
VOL_MD5=$(md5sum "$ADIR/fx_vol.R" | cut -d' ' -f1)
run_lane probe_fail
LR=$(led_rows)
if [ "$LANE_RC" = 0 ] && [ "$(evc arm_probe_fail)" = 1 ] && [ ! -f "$ADIR/b5gen_lit_1.R" ] && [ ! -f "$ADIR/b5gen_lit_1.arm.json" ] \
   && printf '%s\n' "$LR" | grep -q "^b5gen_lit_1|False|probe|4|"; then
  ok "S2a ★probe 실패(리터럴 문턱) → 파일 삭제 + 방출 원장 admitted=false · stage=probe · n_siblings 4"
else ng "S2a" "rc=$LANE_RC probe_fail=$(evc arm_probe_fail) led=[$LR]"; fi
printf '%s\n' "$LR" | grep -q "^b5gen_good_1|True||4|" && printf '%s' "$(cat_has)" | grep -q "good_1_arm:active:b5_design" \
  && ok "S2b 같은 요청의 정상 arm 은 등재(한 arm 의 실패가 다른 arm 을 막지 않는다)" || ng "S2b" "[$LR]"
[ ! -f "$ADIR/b5gen_stray_1.R" ] && [ "$(evc arm_undeclared)" -ge 1 ] && printf '%s\n' "$LR" | grep -q "^b5gen_stray_1|False|undeclared|" \
  && ok "S2c 미신고 arm 파일 → 삭제 + 방출 원장(undeclared)" || ng "S2c" "undeclared=$(evc arm_undeclared)"
[ ! -f "$ADIR/b5gen_BAD.R" ] && grep -q '"stage": "invalid_name"' "$JL" && printf '%s\n' "$LR" | grep -q "|False|invalid_name|" \
  && ok "S2d 이름 규약 위반 kind → 거부 기록 · 파일은 미신고 정리가 지운다(검증 안 된 이름으로 파일 연산 없음)" || ng "S2d" "$(ls "$ADIR" | tr '\n' ' ')"
[ "$(md5sum "$ADIR/fx_vol.R" | cut -d' ' -f1)" = "$VOL_MD5" ] && [ -f "$ADIR/fx_dd.arm.json" ] && [ "$(evc arm_existing_tampered)" -ge 1 ] \
  && ok "S2e ★기존 arm 파일 변조·삭제 → 백업에서 복원 + arm_existing_tampered" || ng "S2e" "tampered=$(evc arm_existing_tampered) $(ls "$ADIR" | tr '\n' ' ')"
[ -f "$ADIR/gen_20260917_999999.R" ] && [ "$(evc arm_foreign_skipped)" -ge 1 ] \
  && ok "S2f 다른 레인 산출 이름(gen_<날짜>_<시각>)은 새 파일이어도 건드리지 않는다" || ng "S2f" "foreign=$(evc arm_foreign_skipped)"
[ "$(n_cells_final)" = "4|1,1,1,2" ] && [ "$(round_field new_arms_admitted 0)" = 1 ] \
  && ok "S2g 설계 — probe 실패 arm 을 쓴 칸 제외 · 4칸 기록" || ng "S2g" "cells=$(n_cells_final)"

#── S3. G1 감사 reject ───────────────────────────────────────────────────────────
echo "=== S3. G1 감사 reject ==="
reset_sb base 0
STUB_AUDIT_REJECT_KIND=b5gen_audrej_1 run_lane audit_reject
LR=$(led_rows)
if [ "$LANE_RC" = 0 ] && [ "$(evc arm_audit_reject)" = 1 ] && [ ! -f "$ADIR/b5gen_audrej_1.R" ] && printf '%s\n' "$LR" | grep -q "^b5gen_audrej_1|False|audit|" \
   && ! printf '%s' "$(cat_has)" | grep -q audrej && [ "$(jq_ "$SB/.cache/rf_overlay_audit/b5gen_audrej_1/audit.json" verdict)" = reject ]; then
  ok "S3a ★감사 reject(실재 행 인용 · R 병합기 채택) → 등재 안 됨 · 파일 삭제 · 방출 원장 stage=audit"
else ng "S3a" "rc=$LANE_RC reject=$(evc arm_audit_reject) led=[$LR] verdict=$(jq_ "$SB/.cache/rf_overlay_audit/b5gen_audrej_1/audit.json" verdict)"; fi
[ "$(n_cells_final)" = "3|1,1,2" ] && [ "$(round_field new_arms_rejected 0)" = 1 ] && [ "$(naudits)" = 3 ] \
  && ok "S3b 거부 arm 을 쓴 칸 제외 → 3칸 · 원장 arms 거부 1" || ng "S3b" "cells=$(n_cells_final) rej=$(round_field new_arms_rejected 0) audits=$(naudits)"

#── S4. 정체 → compose_only ──────────────────────────────────────────────────────
echo "=== S4. 정체(H3) → compose_only ==="
reset_sb stagnation 0
run_lane compose
LR=$(led_rows)
if [ "$LANE_RC" = 0 ] && grep -qE '"event": *"overlay_guard_h3_stagnation".*"decision": *"compose_only"' "$JL" && [ "$(evc arm_ignored)" = 2 ] \
   && [ ! -f "$ADIR/b5gen_cmp_1.R" ] && [ ! -f "$ADIR/b5gen_cmpx_1.R" ] && [ "$(naudits)" = 0 ] \
   && printf '%s\n' "$LR" | grep -q "^b5gen_cmp_1|False|compose_only|" && printf '%s\n' "$LR" | grep -q "^b5gen_cmpx_1|False|compose_only|"; then
  ok "S4a ★arm 을 낸 최근 2라운드가 G2 pass 0 → compose_only → 새 arm 2 무시·삭제·원장 기록 · 감사 호출 0"
else ng "S4a" "rc=$LANE_RC ignored=$(evc arm_ignored) audits=$(naudits) led=[$LR]"; fi
[ "$(round_field compose_only 0)" = true ] && [ "$(n_cells_final)" = "3|1,2,1" ] && grep -q "compose_only = TRUE" "$STUB_PROMPT_COPY" \
  && ok "S4b 라운드 compose_only=true · 무시 arm 칸 제외 3칸 · 프롬프트에 compose_only 고지" || ng "S4b" "co=$(round_field compose_only 0) cells=$(n_cells_final)"

#── S5. 일간 상한 → 할당 1 ───────────────────────────────────────────────────────
echo "=== S5. 일간 상한(H2) → 할당 초과 arm 무시 ==="
reset_sb base 5
run_lane quota
LR=$(led_rows)
if [ "$LANE_RC" = 0 ] && grep -qE '"arm_quota": *"?1"?[,}]' "$JL" && [ "$(evc arm_admitted)" = 1 ] && grep -q '"stage": "quota"' "$JL" \
   && printf '%s\n' "$LR" | grep -q "^b5gen_vgap_1|True||2|" && printf '%s\n' "$LR" | grep -q "^b5gen_xsdd_1|False|quota|" && [ ! -f "$ADIR/b5gen_xsdd_1.R" ] \
   && [ "$(n_cells_final)" = "3|1,2,2" ] && [ "$(naudits)" = 3 ]; then
  ok "S5a ★오늘 b5_design 방출 5 → 할당 min(3, 6−5)=1 → 두 번째 arm quota 무시·삭제·기록 · 그 칸 제외 3칸"
else ng "S5a" "rc=$LANE_RC adm=$(evc arm_admitted) cells=$(n_cells_final) led=[$LR]"; fi

#── S6. 수동 재설계 → 덧붙임 · 두 번째 재설계 거부 ──────────────────────────────────
echo "=== S6. 수동 재설계 · H1 상한 ==="
reset_sb base 0
run_lane redesign --redesign "$BID"
RD=$(round_field redesign)
if [ "$LANE_RC" = 0 ] && [ "$(round_field round 0)" = 2 ] && [ "$(n_cells_final)" = "6|1,1,1,2,2,2" ] && [ "$(jq_ "$FINAL" base_design_cells)" = 3 ] \
   && printf '%s' "$RD" | grep -q '"active": true' && printf '%s' "$RD" | grep -q '"cells_added": 3' && printf '%s' "$RD" | grep -q '"base_design_cells": 3' \
   && [ ! -f "$GD/${BID}_B5.mech.json" ] && grep -qE '"why": *"기존 설계 칸과 같은 스택' "$JL"; then
  ok "S6a ★재설계 round 2 — 기존 3칸 뒤에 새 3칸(중복 1 제외) · b5_redesign{active · cells_added 3 · base 3} · 백업은 라운드 1 전용"
else ng "S6a" "rc=$LANE_RC round=$(round_field round 0) cells=$(n_cells_final) redesign=[$RD]"; fi
N0=$(ncalls); run_lane redesign --redesign "$BID"
[ "$LANE_RC" = 0 ] && [ "$(ncalls)" = "$N0" ] && grep -q '"why": "h1_max_redesign_rounds"' "$JL" && [ "$(round_field n)" = 1 ] \
  && ok "S6b [위반] 두 번째 재설계 → H1 상한(1) 거부 · LLM 호출 0 ★핵심" || ng "S6b" "rc=$LANE_RC calls $N0→$(ncalls)"

#── S7. 유효 칸 부족 → 폴백 ──────────────────────────────────────────────────────
echo "=== S7. 폴백 ==="
reset_sb base 0
MECH_MD5=$(md5sum "$FINAL" | cut -d' ' -f1)
run_lane few_cells
[ "$LANE_RC" = 0 ] && [ "$(md5sum "$FINAL" | cut -d' ' -f1)" = "$MECH_MD5" ] && [ "$(evc design_fallback)" = 1 ] && [ "$(round_field fallback 0)" = true ] \
  && [ ! -f "$GD/${BID}_B5.mech.json" ] \
  && ok "S7a ★유효 칸 2 < 3 → 폴백 · 기전 설계 비트 동일 · 폴백 라운드 기록(무성 금지 · 재발화 차단)" || ng "S7a" "rc=$LANE_RC fb=$(round_field fallback 0) events=$(evc design_fallback)"

#── S8. Fable 한도 → opus 폴백 ───────────────────────────────────────────────────
echo "=== S8. Fable 한도 → opus ==="
reset_sb base 0
run_lane fable_limit
C1=$(sed -n 1p "$STUB_CALLS"); C2=$(sed -n 2p "$STUB_CALLS")
LR=$(led_rows)
if [ "$LANE_RC" = 0 ] && printf '%s' "$C1" | grep -q -- "--model fable" && printf '%s' "$C2" | grep -q -- "--model opus --effort max" && ! printf '%s' "$C2" | grep -q -- "--fallback-model" \
   && [ "$(evc model_fallback)" = 1 ] && grep -q '"removed": ".*b5gen_partial_1.R' "$JL" && [ ! -f "$ADIR/b5gen_partial_1.R" ] \
   && printf '%s\n' "$LR" | grep -q "^b5gen_opus_1|True||1|opus|chain$" && ! printf '%s\n' "$LR" | grep -q partial \
   && [ -f "$GD/run_r1.out.primary" ] && [ "$(n_cells_final)" = "4|1,1,1,2" ]; then
  ok "S8a ★Fable 한도 → 훅이 1차 arm·설계 제거 → opus/max 로 처음부터 → 등재 generator=opus · 1차 출력 보존 · 반쪽 arm 원장 흔적 0"
else ng "S8a" "rc=$LANE_RC c1=[$C1] c2=[$C2] fb=$(evc model_fallback) led=[$LR] cells=$(n_cells_final)"; fi

#── S9. 환경 실패(401) ───────────────────────────────────────────────────────────
echo "=== S9. 환경 실패 ==="
reset_sb base 0
MECH_MD5=$(md5sum "$FINAL" | cut -d' ' -f1)
run_lane auth
[ "$LANE_RC" = 2 ] && [ "$(evc halt_env_failure)" = 1 ] && [ ! -f "$ADIR/b5gen_auth_1.R" ] && [ ! -f "$GD/design_r1.json" ] && [ -f "$GD/run_r1.out" ] \
  && [ "$(round_field n)" = 0 ] && [ -z "$(led_rows)" ] && [ "$(md5sum "$FINAL" | cut -d' ' -f1)" = "$MECH_MD5" ] && [ ! -d "$SB/.cache/rf_b5_design.claim" ] \
  && ok "S9a ★401 → halt_env_failure · rc 2 · 새 arm·설계 제거(실행 출력 보존) · 라운드·방출 미기록(재시도 정당) · claim 해제" \
  || ng "S9a" "rc=$LANE_RC env=$(evc halt_env_failure) rounds=$(round_field n)"

#── S10. 다음 블록 부정 ──────────────────────────────────────────────────────────
echo "=== S10. B5 착수된 entry ==="
reset_sb b5attempted 0
run_lane normal
[ "$LANE_RC" = 0 ] && [ "$(ncalls)" = 0 ] && grep -q '"event": "not_due".*B5 시도' "$JL" && [ ! -d "$GD" ] \
  && ok "S10a [위반] B5 시도가 있는 entry → not_due · LLM 호출 0 · 레인 디렉터리 미생성" || ng "S10a" "rc=$LANE_RC calls=$(ncalls)"

#── S11. 설정 게이트 ────────────────────────────────────────────────────────────
echo "=== S11. 설정 게이트 ==="
reset_sb base 0; "$PY" "$T/mk.py" config "$SB" 0 1
run_lane normal
[ "$LANE_RC" = 0 ] && [ "$(ncalls)" = 0 ] && grep -q '"why": "enabled=false"' "$JL" && ok "S11a 전역 enabled=false → halt_disabled · 호출 0" || ng "S11a" "rc=$LANE_RC calls=$(ncalls)"
QVEST_B5_IGNORE_PAUSE=1 run_lane redesign --redesign "$BID"
[ "$LANE_RC" = 0 ] && [ "$(evc pause_ignored)" = 1 ] && [ "$(round_field round 0)" = 2 ] \
  && ok "S11b 전역 정지 중 수동 재설계 + QVEST_B5_IGNORE_PAUSE=1 → 진행(러너는 여전히 정지)" || ng "S11b" "rc=$LANE_RC pause_ignored=$(evc pause_ignored)"
reset_sb base 0; "$PY" "$T/mk.py" config "$SB" 1 0
QVEST_B5_IGNORE_PAUSE=1 run_lane redesign --redesign "$BID"
[ "$LANE_RC" = 0 ] && [ "$(ncalls)" = 0 ] && grep -q '"event": "halt_disabled"' "$JL" \
  && ok "S11c [위반] b5_design.enabled=false 는 IGNORE_PAUSE 로도 못 넘는다" || ng "S11c" "rc=$LANE_RC calls=$(ncalls)"

#── S12. claim 해제 판정 = 사실 (실물 잠금 · 2026-09-19) ─────────────────────────────
echo "=== S12. claim 해제 — 표식이 남으면 정보 · 표식도 못 쓰면 실패 ==="
# 2026-09-18 23:53 실측: 정상 완주가 claim_release_failed 로 찍혔다 — unlink 이 owner.json 만 지우고 디렉터리를 남겼지만
#   released.json 은 남았다(다음 실행이 즉시 제자리 인수 = 운영상 해제). 경로 = 획득 → H1 거부 → 해제(LLM 호출 0 · 최단).
#   잠금은 실물(다른 프로세스의 작업 디렉터리 — 08_Tests/lib/dir_hold.R). 표식 쓰기 실패만 코드 루트 사본
#   (QVEST_B5_CODE_ROOT)의 rf_claim.R 끝에 rf_claim_write_marker 재정의를 덧붙여 주입한다(운영 코드 무접촉).
CLM="$SB/.cache/rf_b5_design.claim"; H_READY="$T/hold.ready"; H_STOP="$T/hold.stop"
REL_FIX='{"released_at":"fixture","by_pid":1}'   # 앞 실행이 남긴 표식 = 잠긴 claim 에 제자리로 들어가는 입구
hold_start(){ rm -f "$H_READY" "$H_STOP"; mkdir -p "$1"
  Rscript "$ROOT/08_Tests/lib/dir_hold.R" "$1" "$H_READY" "$H_STOP" 180 >/dev/null 2>&1 &
  for _ in $(seq 1 100); do [ -s "$H_READY" ] && return 0; sleep 0.2; done; return 1; }
hold_stop(){ : > "$H_STOP"
  for _ in $(seq 1 50); do rm -rf "$1" 2>/dev/null; [ -d "$1" ] || break; sleep 0.2; done
  if [ -d "$1" ] && [ -s "$H_READY" ]; then local hp; hp=$(tr -d '\r\n' < "$H_READY")
    tasklist //FI "PID eq $hp" //FI "IMAGENAME eq Rscript.exe" //NH 2>/dev/null | grep -q "$hp" && taskkill //F //PID "$hp" >/dev/null 2>&1
    sleep 0.5; rm -rf "$1" 2>/dev/null; fi
  rm -f "$H_READY" "$H_STOP"; [ ! -d "$1" ]; }
b5log_has(){ cat "$SB"/.cache/scheduler_logs/b5_design_*.log 2>/dev/null | tr -d '\r' | grep -qF "$1"; }
s12_state(){ echo "rc=$LANE_RC refused=$(evc b5_design_refused) claimed=$(evc halt_claimed) marker=$(evc claim_release_marker) failed=$(evc claim_release_failed) calls=$(ncalls) dir=[$(ls -A "$CLM" 2>&1 | tr '\n' ' ')]"; }
reset_sb designed 0
run_lane normal
if [ "$LANE_RC" = 0 ] && [ "$(evc b5_design_refused)" = 1 ] && [ ! -d "$CLM" ] && [ "$(evc claim_release_marker)" = 0 ] \
   && [ "$(evc claim_release_failed)" = 0 ] && [ "$(ncalls)" = 0 ]; then
  ok "S12a 잠금 없음 — 획득·H1 거부·해제 → 디렉터리 제거 · 해제 이벤트 0 · LLM 호출 0"
else ng "S12a" "$(s12_state)"; fi
if hold_start "$CLM"; then
  printf '%s' "$REL_FIX" > "$CLM/released.json"
  run_lane normal
  if [ "$LANE_RC" = 0 ] && [ "$(evc halt_claimed)" = 0 ] && [ "$(evc b5_design_refused)" = 2 ] && [ "$(evc claim_release_marker)" = 1 ] \
     && [ "$(evc claim_release_failed)" = 0 ] && b5log_has "release: marker_left"; then
    ok "S12b ★실물 잠금 → 해제 marker_left(rc 0) → claim_release_marker(정보) · claim_release_failed 0"
  else ng "S12b 표식이 남았는데 실패로 찍거나 무기록" "$(s12_state)"; fi
  [ -d "$CLM" ] && [ -f "$CLM/released.json" ] && [ ! -f "$CLM/owner.json" ] \
    && ok "S12c 사실: 디렉터리 존치 · released.json 있음 · owner.json 없음(09-18 23:53 실측 모양)" || ng "S12c 잠금 모양" "$(s12_state)"
  run_lane normal
  [ "$LANE_RC" = 0 ] && [ "$(evc halt_claimed)" = 0 ] && [ "$(evc b5_design_refused)" = 3 ] && [ "$(evc claim_release_marker)" = 2 ] \
    && ok "S12d 다음 실행 — b5_claim_acquire 가 표식을 보고 나이 무관 즉시 제자리 인수(halt_claimed 0)" || ng "S12d 표식을 남겼는데 다음 실행이 막혔다" "$(s12_state)"
  # 음성 대조 — 코드 루트 사본(ops · reinforcement 최상위 통째 · 손으로 고르지 않는다)의 rf_claim.R 만 돌연변이
  CODE2="$T/code"; mkdir -p "$CODE2/02_Infrastructure/ops" "$CODE2/02_Infrastructure/reinforcement"
  cp "$ROOT"/02_Infrastructure/ops/*.R "$ROOT"/02_Infrastructure/ops/*.sh "$ROOT"/02_Infrastructure/ops/*.py "$CODE2/02_Infrastructure/ops/" 2>/dev/null
  cp "$ROOT"/02_Infrastructure/reinforcement/*.R "$CODE2/02_Infrastructure/reinforcement/" 2>/dev/null
  printf '\nrf_claim_write_marker <- function(claim) "injected: marker write blocked (S12)"\n' >> "$CODE2/02_Infrastructure/ops/rf_claim.R"
  QVEST_B5_CODE_ROOT="$CODE2" run_lane normal
  if [ "$LANE_RC" = 0 ] && [ "$(evc b5_design_refused)" = 4 ] && [ "$(evc claim_release_failed)" = 1 ] && [ "$(evc claim_release_marker)" = 2 ] \
     && grep -E '"event": *"claim_release_failed"' "$JL" | grep -F '"rc": "1"' | grep -qF 'unlink_failed | injected: marker write blocked (S12)'; then
    ok "S12e ★[위반] 잠금 + 표식 쓰기 차단(코드 루트 사본 돌연변이) → claim_release_failed(reason=unlink_failed | 원인 · rc 1)"
  else ng "S12e 진짜 해제 실패를 못 잡는다" "$(s12_state)"; fi
  [ -d "$CLM" ] && [ ! -f "$CLM/released.json" ] && ok "S12f 사실: 디렉터리 존치 · 표식 없음" || ng "S12f 상태" "$(s12_state)"
  run_lane normal   # 원본 코드 — 표식 없이 갓 비워진 claim 은 빈 고아 60초 유예로 즉시 인수 불가
  [ "$LANE_RC" = 0 ] && [ "$(evc halt_claimed)" = 1 ] && [ "$(evc b5_design_refused)" = 4 ] \
    && ok "S12g 표식 없는 잔존 claim → 다음 실행 halt_claimed — 그래서 이것만 실패로 남긴다" || ng "S12g" "$(s12_state)"
else ng "S12 잠금 픽스처 준비 실패 — S12b~g 판정 없음" "08_Tests/lib/dir_hold.R ready 미기록"; fi
hold_stop "$CLM" && ok "S12h 잠금 해제 · claim 정리" || ng "S12h 잠금 픽스처가 안 풀린다" "$CLM"

#── Z. 격리 ─────────────────────────────────────────────────────────────────────
echo "=== Z. 격리 ==="
[ "$(real_hash)" = "$REAL0" ] && ok "Z1 운영 원장·카탈로그·방출 원장·설정·arm 디렉터리 불변" || ng "Z1 운영 파일 변화 ★" ""
NEWJL=0   # ★grep -c 는 0건이면 '0' 을 찍고 rc 1 — '|| echo 0' 을 붙이면 0 이 두 줄이 된다
[ -f "$REAL_JL" ] && NEWJL=$(tail -n +"$((REAL_JL_N + 1))" "$REAL_JL" | grep -c '"base_id": *"T_E1"')
[ "${NEWJL:-0}" = 0 ] && ok "Z2 운영 jlog 에 픽스처 이벤트 0" || ng "Z2" "$NEWJL"
[ ! -d "$ROOT/.cache/rf_b5_design/$BID" ] && [ ! -d "$ROOT/.cache/rf_overlay_audit/b5gen_vgap_1" ] && ok "Z3 운영 .cache 에 픽스처 산출 0" || ng "Z3" "운영 경로에 썼다"

echo
printf '합계: 통과 %d · 실패 %d\n' "$PASS" "$FAIL"
printf '{"test":"rf_b5_design","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
