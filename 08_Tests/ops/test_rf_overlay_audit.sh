#!/usr/bin/env bash
#==============================================================================
# test_rf_overlay_audit.sh — G1 적대적 설계시점 감사 **양방향 검사** (v10.4 2026-09-17)
#
# 대상: 02_Infrastructure/ops/rf_overlay_audit.sh · rf_overlay_audit_merge.R · 06_Registry/rf_overlay_adversary_axes.json
# 지키는 것:
#   ① 채택된 발견만 판정을 끈다 — 근거가 파일에 실재해야 한다(가짜 행 인용은 무시 + 기록) · 진술(verdict 문자열)은 증거가 아니다
#   ② duplicate 는 **활성** id 일 때만 · 퇴역·미등재 id 는 무시
#   ③ required 축 미산출·파손 = unavailable(호출자 등재 금지) · 거부는 unavailable 보다 우선
#   ④ Fable 한도 → opus 폴백이 rf_llm_agent_run 을 통해 실제로 밟힌다 · 한도가 폴백까지 오면 환경 실패로 남는다
#   ⑤ [돌연변이] 근거 검증을 건너뛰는 병합기는 이 검사가 잡는다
# claude 는 가짜 실행 파일(RF_CLAUDE_BIN)로 대체 — 실제 모델 호출 0 · 한도 소모 0. 운영 카탈로그·원장·로그에 쓰지 않는다.
# 실행: bash 08_Tests/ops/test_rf_overlay_audit.sh   (.cache/_test_rf_overlay_audit.<pid> 만 쓰고 지운다)
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
# ★POSIX 형 루트(/c/…)는 Windows 형으로 — 네이티브 python 이 -c 코드 안에 박힌 /c/… 경로를 못 연다(argv 만 MSYS 가 변환한다)
case "$ROOT" in /[A-Za-z]/*) command -v cygpath >/dev/null 2>&1 && ROOT=$(cygpath -m "$ROOT") ;; esac
export QM_ROOT="$ROOT"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"; export QVEST_PY="$PY"
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
T="$ROOT/.cache/_test_rf_overlay_audit.$$"
rm -rf "$T"; mkdir -p "$T/arms" "$T/out" "$T/prompts"
trap 'rm -rf "$T"' EXIT
LANE="$ROOT/02_Infrastructure/ops/rf_overlay_audit.sh"
MERGE="$ROOT/02_Infrastructure/ops/rf_overlay_audit_merge.R"
AXES="$ROOT/06_Registry/rf_overlay_adversary_axes.json"
REAL_JLOG="$ROOT/.cache/reinforce_auto_log.jsonl"
JL0=$( [ -f "$REAL_JLOG" ] && wc -l < "$REAL_JLOG" || echo 0 )
REAL_OA_EXISTED=$( [ -d "$ROOT/.cache/rf_overlay_audit" ] && echo 1 || echo 0 )
unset QVEST_LLM_FALLBACK QVEST_OA_MODEL QVEST_OA_EFFORT

# ── 픽스처: 누출 arm(3행에 H$fwd[t]) · 활성/퇴역 카탈로그 · 설정 ──────────────────────────
KIND="zz_audit_leak"
cat > "$T/arms/$KIND.R" <<'EOF'
overlay_expo_zz_audit_leak <- function(H, t, ctx) {
  q <- stats::ecdf(H$dd[is.finite(H$dd)])(H$dd[t])
  f <- H$fwd[t]                      # 미실현 익월 수익
  max(0, min(1, 1 - q - f))
}
EOF
printf '{"id":"zz_audit_leak_v1","family":"drawdown","state":"drawdown","basis":"검사 픽스처","est_cost_min":1}' > "$T/arms/$KIND.arm.json"
cat > "$T/catalog.json" <<'EOF'
{"schema":"overlay_catalog_v1","families":{"cross_sectional":"x"},
 "arms":[{"id":"dbeta_tilt_rank","kind":"dbeta_tilt","family":"cross_sectional","status":"active","action":"cross_sectional","state":"drawdown","basis":"낙폭 경험분포 중앙 위에서 하방베타 순위에 비례해 축소"},
         {"id":"old_arm_retired","kind":"old_arm","family":"drawdown","status":"retired","action":"scalar_exposure","state":"drawdown","basis":"퇴역"}]}
EOF
cat > "$T/cfg.json" <<'EOF'
{"llm":{"model":"opus","effort":"max","fable_limit_fallback":{"model":"opus","effort":"max"},
        "lanes":{"overlay_audit":{"model":"opus","effort":"xhigh"}}}}
EOF
# 가짜 claude — 프롬프트(stdin)에서 산출 경로를 읽어 시나리오대로 축 파일을 쓴다. 호출 인자·프롬프트는 검사용으로 남긴다.
cat > "$T/claude_stub.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_CALLS"
model=""; prev=""
for a in "$@"; do [ "$prev" = "--model" ] && model="$a"; prev="$a"; done
prompt=$(cat)
out=$(printf '%s\n' "$prompt" | sed -n 's/^AUDIT_OUTPUT_FILE=//p' | head -1 | tr -d '\r')
axis=$(basename "$out" .json); axis=${axis#axis_}
printf '%s' "$prompt" > "$STUB_PROMPTS/$axis.txt"
case "$STUB_SCENARIO:$model" in
  limit_then_ok:fable) echo "You've reached your Fable limit · resets 2am (Asia/Seoul)"; exit 1 ;;
  limit_both:*)        echo "You've hit your session limit · resets 2am (Asia/Seoul)"; exit 1 ;;
  auth:*)              echo "API Error: 401 OAuth access token has expired"; exit 1 ;;
esac
pass='{"axis":"'"$axis"'","verdict":"pass","findings":[]}'
w(){ printf '%s' "$1" > "$out"; }
case "$STUB_SCENARIO:$axis" in
  leak_valid:leak)       w '{"axis":"leak","verdict":"reject","findings":[{"type":"leak","evidence":"zz_audit_leak.R:3 f <- H$fwd[t]","explanation":"t 행 fwd 는 신호일에 미실현","duplicate_of":null}]}' ;;
  leak_fabricated:leak)  w '{"axis":"leak","verdict":"reject","findings":[{"type":"leak","evidence":"zz_audit_leak.R:1 f <- H$fwd[t]","explanation":"지어낸 행 인용","duplicate_of":null}]}' ;;
  degenerate_valid:degenerate) w '{"axis":"degenerate","verdict":"reject","findings":[{"type":"full_sample","evidence":"zz_audit_leak.R:2 stats::ecdf(H$dd[is.finite(H$dd)])","explanation":"픽스처 설명","duplicate_of":null}]}' ;;
  dup_active:duplicate)  w '{"axis":"duplicate","verdict":"reject","findings":[{"type":"duplicate","evidence":"","explanation":"낙폭 경험분포 × 하방베타 순위 — 같은 결정 규칙","duplicate_of":"dbeta_tilt_rank"}]}' ;;
  dup_retired:duplicate) w '{"axis":"duplicate","verdict":"reject","findings":[{"type":"duplicate","explanation":"퇴역과 같다","duplicate_of":"old_arm_retired"}]}' ;;
  dup_unknown:duplicate) w '{"axis":"duplicate","verdict":"reject","findings":[{"type":"duplicate","explanation":"없는 id","duplicate_of":"ghost_arm_v9"}]}' ;;
  missing_axis:duplicate) : ;;                                    # 축 파일을 안 쓴다(레인 실패 재현)
  broken_json:leak)      w '{not json' ;;
  declared_reject_empty:*) w '{"axis":"'"$axis"'","verdict":"reject","findings":[]}' ;;
  *)                     w "$pass" ;;
esac
echo "Done."; exit 0
EOF
chmod +x "$T/claude_stub.sh"
export QVEST_OA_AXES="$AXES" QVEST_OA_CATALOG="$T/catalog.json" QVEST_OA_ARMDIR="$T/arms" QVEST_OA_OUT="$T/out"
export QVEST_RF_CONFIG="$T/cfg.json" QVEST_RP_JLOG="$T/jlog.jsonl" QVEST_OA_LOG="$T/lane.log" QVEST_OA_TIMEOUT=60
export RF_CLAUDE_BIN="$T/claude_stub.sh" STUB_CALLS="$T/calls.log" STUB_PROMPTS="$T/prompts"
ODIR="$T/out/$KIND"
AUD="$ODIR/audit.json"
run_lane(){ export STUB_SCENARIO="$1"; : > "$STUB_CALLS"; rm -f "$STUB_PROMPTS"/*.txt
  bash "$LANE" "${2:-$KIND}" > "$T/lane_out.txt" 2>&1; LANE_RC=$?; LAST=$(tail -1 "$T/lane_out.txt" | tr -d '\r'); }
jq_(){ "$PY" -c "
import json,io,sys
d=json.load(io.open(sys.argv[1],encoding='utf-8'))
for k in sys.argv[2].split('.'):
    d=d[int(k)] if isinstance(d,list) else d.get(k)
print(json.dumps(d,ensure_ascii=False) if isinstance(d,(dict,list)) else ('' if d is None else d))" "$1" "$2" 2>/dev/null | tr -d '\r'; }
ncalls(){ local n; n=$(grep -c . "$STUB_CALLS" 2>/dev/null); echo "${n:-0}"; }   # grep -c 는 0건이면 '0' 을 찍고 rc 1 — '|| echo 0' 이면 0 이 두 줄

#── A. 축 등록부 · 설정 · 배선 ──────────────────────────────────────────────────────────
echo "=== A. 축 등록부 · 설정 · 배선 ==="
AXN=$("$PY" -c "import json,io,sys;a=json.load(io.open(sys.argv[1],encoding='utf-8'))['axes'];print(len(a))" "$AXES" | tr -d '\r')
[ "$AXN" = 3 ] && ok "A1 축 3개(leak·degenerate·duplicate)" || ng "A1" "axes=$AXN"
w=$("$PY" -c "
import json,io,re,sys
a=json.load(io.open(sys.argv[1],encoding='utf-8'))['axes']; bad=[]
for x in a:
    if not x.get('required'): bad.append(x['id']+':not_required')
    if re.match(r'^claude-',x.get('model','')): bad.append(x['id']+':pinned_id')
    if x.get('model','').lower().startswith('fable'): bad.append(x['id']+':same_family_as_designer')
print(';'.join(bad))" "$AXES" | tr -d '\r')
[ -z "$w" ] && ok "A2 전 축 required · 모델은 별칭(opus) · 설계자(fable)와 다른 계열" || ng "A2" "$w"
cfg_m=$("$PY" -c "import json,io,sys;c=json.load(io.open(sys.argv[1],encoding='utf-8'));l=c['llm']['lanes']['overlay_audit'];print(l['model']+'/'+l['effort'])" "$ROOT/06_Registry/reinforce_auto_config.json" 2>/dev/null | tr -d '\r')
[ "$cfg_m" = "opus/xhigh" ] && ok "A3 설정 llm.lanes.overlay_audit = opus/xhigh (JSON 유효)" || ng "A3" "[$cfg_m]"
lsrc=$(cat "$LANE")
w=""
printf '%s' "$lsrc" | grep -q "rf_llm_agent_run " || w="$w no_agent_run"
printf '%s' "$lsrc" | grep -q 'disallowed-tools "Bash,Agent"' || w="$w agent_bash_allowed"
printf '%s' "$lsrc" | grep -qE '^[[:space:]]*timeout [0-9]+ claude -p' && w="$w direct_claude_call"
printf '%s' "$lsrc" | grep -q "rf_overlay_audit_merge.R" || w="$w no_merge"
for k in leak degenerate duplicate; do printf '%s' "$lsrc" | grep -q "\"$k\"" && w="$w axis_${k}_hardcoded"; done
[ -z "$w" ] && ok "A4 레인: 실행기 경유 · Bash/Agent 금지 · R 병합 · 축 이름 미하드코딩" || ng "A4" "$w"
bash -n "$LANE" && ok "A5 레인 문법" || ng "A5" "bash -n"

#── B. 레인 끝까지 — 채택 규칙 ─────────────────────────────────────────────────────────
echo "=== B. 레인 끝까지 — 채택 규칙 ==="
run_lane all_pass
if [ "$LANE_RC" = 0 ] && [ "$(jq_ "$AUD" verdict)" = pass ] && [ "$(ncalls)" = 3 ] && [ -f "$ODIR/axis_leak.json" ] && [ -f "$ODIR/axis_degenerate.json" ] && [ -f "$ODIR/axis_duplicate.json" ] \
   && printf '%s' "$LAST" | grep -q "^audit: $KIND | pass"; then
  ok "B1 전 축 발견 0 → pass · rc 0 · 축 파일 3 · 마지막 줄 = 판정"
else ng "B1" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict) calls=$(ncalls) last=[$LAST]"; fi
run_lane leak_valid
if [ "$LANE_RC" = 3 ] && [ "$(jq_ "$AUD" verdict)" = reject ] && jq_ "$AUD" reasons | grep -q "leak" && [ "$(jq_ "$AUD" axis_verdicts.0.n_verified)" = 1 ]; then
  ok "B2 실재하는 행 인용의 leak → reject · rc 3 ★핵심"
else ng "B2" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict)"; fi
run_lane leak_fabricated
nig=$("$PY" -c "import json,io,sys;print(len(json.load(io.open(sys.argv[1],encoding='utf-8'))['ignored_findings']))" "$AUD" | tr -d '\r')
if [ "$LANE_RC" = 0 ] && [ "$(jq_ "$AUD" verdict)" = pass ] && [ "$nig" = 1 ] && jq_ "$AUD" reasons | grep -q "무시된 발견"; then
  ok "B3 지어낸 행 인용의 leak → 무시 · pass · ignored_findings 1 + reasons 에 기록 ★핵심"
else ng "B3" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict) ignored=$nig"; fi
cp -r "$ODIR" "$T/fabricated_snapshot"          # D 절 돌연변이용 스냅샷
run_lane dup_active
if [ "$LANE_RC" = 3 ] && [ "$(jq_ "$AUD" verdict)" = reject ] && [ "$(jq_ "$AUD" duplicate_of)" = dbeta_tilt_rank ]; then
  ok "B4 활성 id 중복 → reject · duplicate_of=dbeta_tilt_rank"
else ng "B4" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict) dup=$(jq_ "$AUD" duplicate_of)"; fi
run_lane dup_retired
[ "$LANE_RC" = 0 ] && [ "$(jq_ "$AUD" verdict)" = pass ] && [ -z "$(jq_ "$AUD" duplicate_of)" ] \
  && ok "B5 퇴역 id 중복 → 무시 · pass" || ng "B5" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict)"
run_lane dup_unknown
[ "$LANE_RC" = 0 ] && [ "$(jq_ "$AUD" verdict)" = pass ] \
  && ok "B6 미등재 id 중복 → 무시 · pass" || ng "B6" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict)"
run_lane missing_axis
if [ "$LANE_RC" = 4 ] && [ "$(jq_ "$AUD" verdict)" = unavailable ] && [ ! -f "$ODIR/axis_duplicate.json" ] && jq_ "$AUD" reasons | grep -q "duplicate"; then
  ok "B7 required 축 미산출 → unavailable · rc 4 (호출자 등재 금지) ★핵심"
else ng "B7" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict)"; fi
run_lane broken_json
[ "$LANE_RC" = 4 ] && [ "$(jq_ "$AUD" verdict)" = unavailable ] \
  && ok "B8 축 산출물 파손(JSON 아님) → unavailable" || ng "B8" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict)"
run_lane declared_reject_empty
[ "$LANE_RC" = 0 ] && [ "$(jq_ "$AUD" verdict)" = pass ] \
  && ok "B9 verdict='reject' 인데 발견 0 → pass (진술은 증거가 아니다)" || ng "B9" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict)"
run_lane degenerate_valid
[ "$LANE_RC" = 3 ] && [ "$(jq_ "$AUD" verdict)" = reject ] && jq_ "$AUD" reasons | grep -q "full_sample" \
  && ok "B10 실재 인용의 full_sample(degenerate 축) → reject" || ng "B10" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict)"
# 잔재: 직전 run 이 남긴 reject 축 파일이 다음 run 에 섞이면 안 된다
run_lane all_pass
[ "$LANE_RC" = 0 ] && [ "$(jq_ "$AUD" verdict)" = pass ] \
  && ok "B11 이전 실행의 reject 축 파일이 다음 판정에 섞이지 않는다(실행 전 잔재 제거)" || ng "B11" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict)"
# 프롬프트 내용 — 행 번호 · 계약 · PIT · duplicate 축에만 카탈로그
PL="$STUB_PROMPTS/leak.txt"; PD="$STUB_PROMPTS/duplicate.txt"
w=""
grep -q '   3 | .*H\$fwd\[t\]' "$PL"      || w="$w no_numbered_arm_line"
grep -q 'ctx = list(t, date, v_now, tgt, n_min, hold, strict)' "$PL" || w="$w no_ctx_contract"
grep -q 'C5' "$PL"                        || w="$w no_pit_summary"
grep -q 'AUDIT_OUTPUT_FILE=' "$PL"        || w="$w no_output_path"
grep -q 'zz_audit_leak_v1' "$PL"          || w="$w no_arm_json"
grep -q 'dbeta_tilt_rank' "$PD"           || w="$w dup_prompt_missing_active"
grep -q 'old_arm_retired' "$PD"           && w="$w dup_prompt_has_retired"
grep -q '활성 카탈로그 arm' "$PL"          && w="$w leak_prompt_has_catalog"
grep -q '"type": "leak | probe_evasion' "$PL" || w="$w no_schema"
[ -z "$w" ] && ok "B12 프롬프트: 행 번호 붙은 arm · arm.json · ctx/PIT 계약 · 산출 경로 · 스키마 · 카탈로그는 duplicate 축에만(활성만)" || ng "B12" "$w"
if [ "$(grep -c -- "--model opus --effort xhigh" "$STUB_CALLS")" = 3 ] && grep -q -- "--disallowed-tools Bash,Agent" "$STUB_CALLS" && grep -q -- "--add-dir $ODIR" "$STUB_CALLS" && ! grep -q -- "--fallback-model" "$STUB_CALLS"; then
  ok "B13 호출 인자: 축별 opus/xhigh ×3 · Bash/Agent 금지 · --add-dir 산출 디렉터리 · Opus 라 폴백 없음"
else ng "B13" "$(head -1 "$STUB_CALLS")"; fi
ls_m=$(jq_ "$ODIR/lane_status.json" axes.leak.model_used)
[ "$ls_m" = opus ] && ok "B14 lane_status.json 에 축별 실제 사용 모델이 남는다" || ng "B14" "[$ls_m]"

#── C. Fable 한도 → opus 폴백 (rf_llm_agent_run 경유) · 폴백까지 한도 · auth ──────────────
echo "=== C. 폴백 · 환경 실패 ==="
export QVEST_OA_MODEL=fable
run_lane limit_then_ok
c2=$(sed -n 2p "$STUB_CALLS")
if [ "$LANE_RC" = 0 ] && [ "$(jq_ "$AUD" verdict)" = pass ] && [ "$(ncalls)" = 6 ] \
   && printf '%s' "$(sed -n 1p "$STUB_CALLS")" | grep -q -- "--model fable --effort xhigh --fallback-model opus" \
   && printf '%s' "$c2" | grep -q -- "--model opus --effort max" \
   && [ "$(jq_ "$ODIR/lane_status.json" axes.leak.fell_back)" = True ] && [ "$(jq_ "$ODIR/lane_status.json" axes.leak.model_used)" = opus ] \
   && [ -f "$ODIR/run_leak.out.primary" ] && [ "$(jq_ "$AUD" axis_verdicts.0.fell_back)" = True ]; then
  ok "C1 Fable 한도 → 축마다 opus/max 로 재실행(6호출) · pass · lane_status/audit 에 fell_back·model_used 기록 ★핵심"
else ng "C1" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict) calls=$(ncalls) c1=[$(sed -n 1p "$STUB_CALLS")] c2=[$c2]"; fi
run_lane limit_both
if [ "$LANE_RC" = 4 ] && [ "$(jq_ "$AUD" verdict)" = unavailable ] && [ "$(jq_ "$AUD" env_failure)" = True ] \
   && [ "$(jq_ "$ODIR/lane_status.json" axes.leak.env_failure)" = limit ] && jq_ "$AUD" reasons | grep -q "환경 실패"; then
  ok "C2 폴백까지 한도 → 축 미산출 = unavailable · env_failure 표식(재실행 사유이지 설계 결함 아님)"
else ng "C2" "rc=$LANE_RC verdict=$(jq_ "$AUD" verdict) env=$(jq_ "$AUD" env_failure)"; fi
unset QVEST_OA_MODEL
run_lane auth
if [ "$LANE_RC" = 4 ] && [ "$(jq_ "$AUD" verdict)" = unavailable ] && [ "$(ncalls)" = 1 ] && grep -q '"event": *"halt_auth_expired"' "$QVEST_RP_JLOG"; then
  ok "C3 401 → 첫 축에서 멈춤(1호출) · unavailable · halt_auth_expired 저널"
else ng "C3" "rc=$LANE_RC calls=$(ncalls) verdict=$(jq_ "$AUD" verdict)"; fi

#── D. 돌연변이 — 근거 검증을 건너뛰는 병합기를 잡는가 ──────────────────────────────────
echo "=== D. 돌연변이 ==="
rm -rf "$ODIR"; cp -r "$T/fabricated_snapshot" "$ODIR"          # B3 의 지어낸 근거 축 파일
check_fabricated_ignored(){   # $1 = 병합기 경로 → 판정 출력
  Rscript "$1" "$KIND" > "$T/m.out" 2>/dev/null; printf '%s' "$(jq_ "$AUD" verdict)"; }
v0=$(check_fabricated_ignored "$MERGE")
[ "$v0" = pass ] && ok "D1 정본 병합기: 지어낸 근거 → pass" || ng "D1" "[$v0]"
sed 's/^\.oa_verify_evidence <- function(ev, arm_lines, arm_file) {/&\n  return(list(ok = TRUE, why = "MUTANT"))/' "$MERGE" > "$T/mutant.R"
grep -q 'MUTANT' "$T/mutant.R" || ng "D2 돌연변이 주입 실패" "sed"
v1=$(check_fabricated_ignored "$T/mutant.R")
[ "$v1" = reject ] && ok "D2 [돌연변이] 근거 검증을 건너뛴 병합기는 지어낸 근거로 reject 를 낸다 → 검사가 잡는다(D1 기준과 갈린다)" \
  || ng "D2 돌연변이가 검출되지 않았다" "[$v1]"
Rscript "$MERGE" "$KIND" > /dev/null 2>&1; rc0=$?
[ "$rc0" = 0 ] && ok "D3 병합기 CLI 종료 코드 pass=0" || ng "D3" "rc=$rc0"
rm -rf "$ODIR"; cp -r "$T/fabricated_snapshot" "$ODIR"; rm -f "$ODIR/axis_leak.json"
Rscript "$MERGE" "$KIND" > /dev/null 2>&1; rc4=$?
[ "$rc4" = 4 ] && ok "D4 병합기 CLI 종료 코드 unavailable=4" || ng "D4" "rc=$rc4"

#── E. 분리 실행 · 결측 arm · 격리 ───────────────────────────────────────────────────────
echo "=== E. 분리 실행 · 결측 arm · 격리 ==="
rm -rf "$ODIR"; cp -r "$T/fabricated_snapshot" "$ODIR"
: > "$STUB_CALLS"
QVEST_OA_MERGE_ONLY=1 bash "$LANE" "$KIND" > "$T/mo.txt" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(ncalls)" = 0 ] && tail -1 "$T/mo.txt" | grep -q "^audit: $KIND | pass" \
  && ok "E1 QVEST_OA_MERGE_ONLY=1 → 에이전트 호출 0 · 병합만" || ng "E1" "rc=$rc calls=$(ncalls)"
run_lane all_pass nonexistent_arm_kind
[ "$LANE_RC" = 4 ] && [ "$(ncalls)" = 0 ] && [ "$(jq_ "$T/out/nonexistent_arm_kind/audit.json" verdict)" = unavailable ] \
  && ok "E2 arm 파일 부재 → 호출 0 · unavailable · rc 4" || ng "E2" "rc=$LANE_RC calls=$(ncalls)"
JL1=$( [ -f "$REAL_JLOG" ] && wc -l < "$REAL_JLOG" || echo 0 )
[ "$JL0" = "$JL1" ] && ok "E3 운영 저널(reinforce_auto_log.jsonl) 무오염" || ng "E3" "$JL0→$JL1"
if [ "$REAL_OA_EXISTED" = 1 ] || [ ! -d "$ROOT/.cache/rf_overlay_audit" ]; then ok "E4 운영 산출 디렉터리(.cache/rf_overlay_audit) 미생성"; else ng "E4" "운영 경로에 썼다"; fi
grep -q "zz_audit_leak" "$ROOT/06_Registry/overlay_catalog.json" && ng "E5 운영 카탈로그 오염" "" || ok "E5 운영 카탈로그 무오염"

echo
printf '합계: 통과 %d · 실패 %d\n' "$PASS" "$FAIL"
printf '{"test":"rf_overlay_audit","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
