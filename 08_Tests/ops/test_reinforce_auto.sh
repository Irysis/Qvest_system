#!/usr/bin/env bash
#==============================================================================
# test_reinforce_auto.sh — 강화 무인 러너 **양방향 검사** (2026-08-30)
#
# 왜 양방향인가: 이 저장소의 반복 교훈 — "경고 0" 을 보고하는 순간이 최고 위험이고,
#   위반 주입 없이 통과만 확인한 계기는 방어선으로 세지 않는다. 그래서 각 가드마다
#   ①정상 경로에서 통과하는가 ②위반을 주입하면 실제로 막는가 를 **둘 다** 건다.
#
# 실행: bash 08_Tests/ops/test_reinforce_auto.sh
# 부작용 없음 — 원장·산출물에 쓰지 않는다(kill switch off 상태에서만 러너를 부른다).
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
# ★검사는 공유 설정을 직접 만지지 않는다 — 2026-08-30 실측: 검사가 daily_cap 을 0/9999 로
#   바꿔 놓은 창에 스케줄러 tick 이 끼어들어 halt_daily_cap done=6 cap=0 을 찍었다.
#   trap restore 로 되돌리지만 그 사이가 위험하다. 격리 사본 + 락으로 창을 없앤다.
CFG="$ROOT/.cache/_test_reinforce_auto_config.json"
CFG_REAL="$ROOT/06_Registry/reinforce_auto_config.json"
cp "$CFG_REAL" "$CFG" 2>/dev/null
export QVEST_RF_CONFIG="$CFG"   # 러너가 이 값을 우선한다
# ★claim 도 격리한다 — restore 가 공유 claim 을 rm 하면 살아있는 배치의 mutex 를
#   빼앗게 되어 다음 tick 이 동시 배치를 띄운다(설정 격리와 같은 사유).
CLAIM="$ROOT/.cache/_test_reinforce_auto.claim"
export QVEST_RF_CLAIM="$CLAIM"
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }

BAK="$(mktemp)"; cp "$CFG" "$BAK" 2>/dev/null   # 사본의 사본 — 공유 설정 무접촉
restore(){ [ -s "$BAK" ] && cp "$BAK" "$CFG"; rm -f "$BAK" "$CFG"; rm -rf "$CLAIM"; unset QVEST_RF_CONFIG QVEST_RF_CLAIM; }
trap restore EXIT

echo "=== 1. 구문 ==="
for f in 02_Infrastructure/reinforcement/rf_cell_engine.R \
         02_Infrastructure/ops/reinforce_auto_run.R \
         02_Infrastructure/ops/reinforce_auto_next_paper.R; do
  if Rscript -e "invisible(parse('$f'))" >/dev/null 2>&1; then ok "parse $f"; else ng "parse $f"; fi
done
if "$PY" -c "import ast,io,sys; ast.parse(io.open('02_Infrastructure/ops/rf_next_paper_pick.py',encoding='utf-8').read())" 2>/dev/null; then
  ok "parse rf_next_paper_pick.py"; else ng "parse rf_next_paper_pick.py"; fi

echo "=== 2. kill switch (양방향) ==="
# ②위반 주입: enabled=false → 반드시 즉시 정지하고 아무것도 안 한다
"$PY" -c "
import io,json;p=r'$CFG';d=json.load(io.open(p,encoding='utf-8'));d['enabled']=False
io.open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False,indent=1))"
OUT=$(Rscript 02_Infrastructure/ops/reinforce_auto_run.R 2>&1)
if printf '%s' "$OUT" | grep -q "halt_disabled"; then ok "kill switch off → halt_disabled"; else ng "kill switch off" "$(printf '%s' "$OUT" | head -2)"; fi
if [ -d "$CLAIM" ]; then ng "kill switch off 인데 claim 을 잡았다"; else ok "kill switch off → claim 미점유"; fi

# ①정상 대조: enabled=true 면 halt_disabled 가 아니어야 한다(다른 사유로는 멈출 수 있다)
"$PY" -c "
import io,json;p=r'$CFG';d=json.load(io.open(p,encoding='utf-8'));d['enabled']=True;d['daily_cap']=0
io.open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False,indent=1))"
OUT=$(Rscript 02_Infrastructure/ops/reinforce_auto_run.R 2>&1)
if printf '%s' "$OUT" | grep -q "halt_disabled"; then ng "enabled=true 인데 halt_disabled" ; else ok "enabled=true → kill switch 통과"; fi
# ②daily_cap=0 주입 → 예산 가드가 실제로 막는가
if printf '%s' "$OUT" | grep -q "halt_daily_cap"; then ok "daily_cap 가드 발화"; else ng "daily_cap=0 인데 미발화" "$(printf '%s' "$OUT" | head -2)"; fi

echo "=== 3. claim mutex (양방향) ==="
# ★daily_cap 은 claim 보다 **먼저** 판정된다. 오늘 실행분이 많으면 claim 축에 닿기도 전에
#   halt_daily_cap 으로 멈춰 이 검사가 엉뚱한 이유로 실패한다(2026-08-30 실사고).
#   그래서 claim 축만 재도록 상한을 충분히 올린다.
"$PY" -c "
import io,json;p=r'$CFG';d=json.load(io.open(p,encoding='utf-8'));d['enabled']=True;d['daily_cap']=9999
io.open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False,indent=1))"
mkdir -p "$CLAIM"                       # ②위반 주입: 이미 점유된 상태
OUT=$(Rscript 02_Infrastructure/ops/reinforce_auto_run.R 2>&1)
if printf '%s' "$OUT" | grep -q "halt_claimed"; then ok "claim 점유 중 → halt_claimed"; else ng "claim 점유 무시" "$(printf '%s' "$OUT" | head -2)"; fi
rm -rf "$CLAIM"
if [ ! -d "$CLAIM" ]; then ok "claim 해제 확인"; else ng "claim 해제 실패"; fi

echo "=== 4. 프로그램 격자 무결성 ==="
"$PY" - <<'PYEOF'
import io, json, sys
d = json.load(io.open("06_Registry/reinforce_program.json", encoding="utf-8"))
# ★칸 수를 20 으로 박지 않는다 — 오버레이 B5 신설처럼 블록이 늘면 검사가 낡는다.
#   계약은 "블록마다 5칸"(병렬 배치 단위)이고 총합은 거기서 파생된다.
n = sum(b["n"] for b in d["blocks"])
assert all(b["n"] == 5 for b in d["blocks"]), "블록당 5칸 계약 위반: %s" % [(b["id"], b["n"]) for b in d["blocks"]]
codes = [c["code"] for b in d["blocks"] for c in b["cells"]]
assert len(codes) == n and len(set(codes)) == n, "코드 중복/누락: %s" % codes
for b in d["blocks"]:
    assert len(b["cells"]) == b["n"], "%s 선언 n=%d 실제 %d" % (b["id"], b["n"], len(b["cells"]))
    for c in b["cells"]:
        # 근거 의무: 논문 url 또는 method(risk_overlay 는 문헌이 아니라 방법이 근거 — 도훈 2026-08-30).
        # B4(조합)는 앞 블록 승자를 물려받으므로 자체 근거를 갖지 않는다.
        if b["id"] == "B4":
            continue
        has_url = c.get("root_paper", {}).get("url", "").startswith("http")
        has_method = bool(str(c.get("basis", "")).strip())
        assert has_url or has_method, "%s 근거 없음(논문 url 도 method 도 아님)" % c["code"]
        if b["axis"] == "risk_overlay":
            assert has_method, "%s 오버레이는 method 명시 필수" % c["code"]
ax = d["fixed_axes"]
assert ax["long_only"] is True and ax["n_max"] == 25, "고정 축 위반: %s" % ax
print("  OK   격자 %d칸(블록 %d x 5) · 코드 유일 · 근거(논문 url 또는 method) · 고정 축" % (n, len(d["blocks"])))
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "  FAIL 격자 무결성"; }

echo "=== 5. 논문 선택기 (양방향) ==="
OUT=$("$PY" 02_Infrastructure/ops/rf_next_paper_pick.py stage_artifacts/paper_recharge 2>&1)
if printf '%s' "$OUT" | "$PY" -c "
import sys,json; o=json.loads(sys.stdin.read()); sys.exit(0 if o.get('url','').startswith('http') else 1)"; then
  ok "큐 상단 논문 + 원문 링크 산출"; else ng "논문 선택 실패" "$OUT"; fi
# ②위반 주입: 빈 디렉터리 → 반드시 링크를 지어내지 않는다
TMPD=$(mktemp -d); OUT=$("$PY" 02_Infrastructure/ops/rf_next_paper_pick.py "$TMPD" 2>&1); rm -rf "$TMPD"
if printf '%s' "$OUT" | grep -q '"error"'; then ok "빈 큐 → 오류 반환(링크 날조 없음)"; else ng "빈 큐인데 링크를 냈다" "$OUT"; fi

echo "=== 6. 자본 경계 (정적) ==="
# ★주석 제외 — 이 검사의 첫 판이 러너의 "book_state/05_Production 에 도달하는 코드 없음"
#   이라는 **주석 자체**에 걸려 오탐했다. 판정 축은 실행 코드다.
HITS=$(for f in 02_Infrastructure/ops/reinforce_auto_run.R                 02_Infrastructure/ops/reinforce_auto_next_paper.R                 02_Infrastructure/reinforcement/rf_cell_engine.R; do
         sed 's/#.*$//' "$f" | grep -nE "book_state|05_Production" | sed "s|^|$f:|"
       done)
if [ -n "$HITS" ]; then ng "무인 러너 실행 코드가 book_state/05_Production 을 참조한다" "$HITS"
else ok "자본 경계 — 실행 코드에 book_state/05_Production 미참조"; fi
# ①양성 대조: 검사기가 실제로 발화하는가 (위반 주입)
TMPF="$ROOT/.cache/_rf_boundary_probe.R"; printf 'x <- "05_Production/foo"
' > "$TMPF"
if sed 's/#.*$//' "$TMPF" | grep -qE "book_state|05_Production"; then ok "자본 경계 검사기 양성 대조 발화"
else ng "자본 경계 검사기가 위반 주입에도 미발화 — 죽은 검사"; fi
rm -f "$TMPF"

echo "=== 7. 병렬 배치 (규칙) ==="
for f in 02_Infrastructure/ops/reinforce_auto_parallel.R 02_Infrastructure/ops/rf_cell_worker.R; do
  if Rscript -e "invisible(parse('$f'))" >/dev/null 2>&1; then ok "parse $f"; else ng "parse $f"; fi
done
# ★워커는 원장을 만지면 안 된다 (병렬 경합 원천 차단 계약)
if sed 's/#.*$//' 02_Infrastructure/ops/rf_cell_worker.R | grep -qE "rf_record_result|rf_append_attempt|rf_write"; then
  ng "워커가 원장을 쓴다 — 병렬 경합 위험"
else ok "워커 원장 미접근 (등록·수집은 부모 순차)"; fi
PRB="$ROOT/.cache/_rf_worker_probe.R"; printf 'rf_record_result(1L)\n' > "$PRB"
if sed 's/#.*$//' "$PRB" | grep -qE "rf_record_result"; then ok "워커 원장검사 양성 대조 발화"
else ng "워커 원장검사 미발화 — 죽은 검사"; fi
rm -f "$PRB"
if "$PY" -c "
import io,json,sys
g=json.loads(io.open('06_Registry/reinforce_program.json','rb').read().decode('utf-8'))
e=g.get('execution') or {}
sys.exit(0 if e.get('mode')=='parallel_within_block' and 'ledger_contract' in e else 1)"; then
  ok "정본에 병렬 규칙(블록 내 한정 + 원장 계약) 명시"; else ng "정본에 병렬 규칙 없음"; fi

echo "=== 8. 결합 검토 배선 (논문 3편마다) ==="
if Rscript -e "invisible(parse('02_Infrastructure/ops/rf_combination_review.R'))" >/dev/null 2>&1; then
  ok "parse rf_combination_review.R"; else ng "parse rf_combination_review.R"; fi
# ★핵심: 호출자가 실제로 있는가 (2026-08-30 이전에는 정의·문서·테스트만 있고 호출 0개였다)
if sed 's/#.*$//' 02_Infrastructure/ops/reinforce_auto_next_paper.R | grep -q "rf_combination_review.R"; then
  ok "이월 러너가 결합 검토를 호출한다"; else ng "결합 검토 호출자 없음 — 소비자 없는 계기"; fi
# ①양성 대조: 이 검사가 발화하는가
PRB2="$ROOT/.cache/_rf_combo_probe.R"; printf 'x <- 1\n' > "$PRB2"
if sed 's/#.*$//' "$PRB2" | grep -q "rf_combination_review.R"; then ng "빈 파일에서 오발화 — 죽은 검사"
else ok "결합검토 호출 검사 음성 대조 정상"; fi
rm -f "$PRB2"
if "$PY" -c "
import io,json,sys
d=json.loads(io.open('06_Registry/reinforce_auto_config.json','rb').read().decode('utf-8'))
sys.exit(0 if int(d.get('combination_review_every',0))>0 and int(d.get('parallel_cells',0))>0 else 1)"; then
  ok "설정에 결합 주기·병렬 수 명시"; else ng "설정 항목 누락"; fi

echo "=== 9. 공리 자동 활성화 ==="
if Rscript -e "invisible(parse('02_Infrastructure/ops/rf_axiom_activate.R'))" >/dev/null 2>&1; then
  ok "parse rf_axiom_activate.R"; else ng "parse rf_axiom_activate.R"; fi
# ★초안(needs_refinement)을 켜지 않는가 — 이 조건이 빠지면 클러스터 메타데이터가 대전제가 된다
if sed 's/#.*$//' 02_Infrastructure/ops/rf_axiom_activate.R | grep -q "x\$refine"; then
  ok "초안 배제 조건 존재"; else ng "초안 배제 조건 없음 — 초안 문구가 공리로 주입될 수 있다"; fi
# ★되돌리기 경로를 알림에 포함하는가 (통보만 하고 되돌릴 방법을 안 주면 통보가 아니다)
if grep -q "deactivate_axiom" 02_Infrastructure/ops/rf_axiom_activate.R; then
  ok "되돌리기 경로 안내 포함"; else ng "되돌리기 경로 없음"; fi
# ★실측 불변식: 활성 공리 중 needs_refinement=TRUE 가 있으면 게이트가 뚫린 것
if "$PY" - <<'PYX'
import io,json,glob,sys
bad=[]
for f in glob.glob("qepm/memory/axioms/active/modes/**/AX-*.json", recursive=True):
    d=json.loads(io.open(f,"rb").read().decode("utf-8"))
    if (d.get("status") or "active")=="active" and d.get("needs_refinement"): bad.append(d.get("axiom_id"))
sys.exit(1 if bad else 0)
PYX
then ok "활성 공리 중 초안 0건(불변식 유지)"; else ng "활성 공리에 초안이 섞였다 — 게이트 뚫림"; fi

echo "=== 10. 무인 충실구현 (LLM 경계 초과 — 안전장치 필수) ==="
bash -n 02_Infrastructure/ops/rf_replication_auto.sh 2>/dev/null && ok "syntax rf_replication_auto.sh" || ng "syntax rf_replication_auto.sh"
Rscript -e "invisible(parse('02_Infrastructure/ops/rf_replication_verify.R'))" >/dev/null 2>&1 \
  && ok "parse rf_replication_verify.R" || ng "parse rf_replication_verify.R"
# ★권한 축소: 헤드리스 에이전트에 Bash/Agent 를 주면 안 된다
if grep -q "disallowed-tools" 02_Infrastructure/ops/rf_replication_auto.sh \
   && grep -q "Bash,Agent" 02_Infrastructure/ops/rf_replication_auto.sh; then
  ok "헤드리스 권한 축소(Bash/Agent 금지)"; else ng "권한 축소 없음 — 무인 LLM 에 셸/스폰 권한"; fi
# ★검증 실패 시 원장을 열지 않는가 (조용한 통과 차단)
if grep -q "failed_needs_session" 02_Infrastructure/ops/rf_replication_verify.R; then
  ok "검증 실패 → 세션 대기(원장 미개설)"; else ng "실패 경로 없음 — 조용한 통과 위험"; fi
# ★등급은 계약에서만 오는가 (에이전트가 등급을 쓰면 안 된다)
if grep -q "authoritative_remeasure" 02_Infrastructure/ops/rf_replication_verify.R; then
  ok "등급 출처 = 계약 산출물"; else ng "등급 출처 불명"; fi
# ★PIT 구조 검사 존재 (정적 CLEAN 만 믿지 않는다)
# ★환경 실패(인증 만료)와 리서치 실패를 구분하는가 — 뭉뚱그리면 엉뚱한 판단을 부른다
if grep -q "halt_auth_expired" 02_Infrastructure/ops/rf_replication_auto.sh; then
  ok "인증 만료 분기 존재(리서치 실패와 구분)"; else ng "환경 실패 미구분"; fi
# ★인증 만료 시 pending 을 유지하는가 — failed 로 바꾸면 재인증해도 재시도가 안 된다
if sed -n '/halt_auth_expired/,/^fi$/p' 02_Infrastructure/ops/rf_replication_auto.sh | grep -q "status'\]='pending'"; then
  ok "인증 만료 → pending 유지(자동 재시도 가능)"; else ng "인증 만료 시 pending 미유지"; fi
if grep -q "pit_structural" 02_Infrastructure/ops/rf_replication_verify.R; then
  ok "PIT 구조 검사 존재"; else ng "PIT 구조 검사 없음"; fi

echo "=== 11. 비중 카탈로그 소비 (재구현 금지) ==="
Rscript -e "invisible(parse('02_Infrastructure/ops/rf_weight_arms.R'))" >/dev/null 2>&1 \
  && ok "parse rf_weight_arms.R" || ng "parse rf_weight_arms.R"
# ★격자 B2 가 카탈로그를 소비하는가 (세션 재구현으로 되돌아가면 실패)
if "$PY" -c "
import io,json,sys
g=json.loads(io.open('06_Registry/reinforce_program.json','rb').read().decode('utf-8'))
b2=[b for b in g['blocks'] if b['id']=='B2'][0]
kinds={c['weighting']['kind'] for c in b2['cells']}
src=(b2.get('source') or {}).get('registry','')
sys.exit(0 if kinds=={'catalog'} and 'weight_catalog' in src else 1)"; then
  ok "B2 전 셀이 카탈로그 소비"; else ng "B2 에 재구현 비중이 섞였다"; fi
# ★계열 다양성 — 한 계열에 3개 이상 몰리면 같은 결론만 나온다(2026-08-30 실측)
if "$PY" -c "
import io,json,sys,collections
g=json.loads(io.open('06_Registry/reinforce_program.json','rb').read().decode('utf-8'))
b2=[b for b in g['blocks'] if b['id']=='B2'][0]
fam=collections.Counter(c['label'].split('(')[-1].rstrip(')') for c in b2['cells'])
sys.exit(0 if max(fam.values())<=1 else 1)"; then
  ok "B2 계열 중복 없음(계열당 1개)"; else ng "B2 계열이 중복 — 정보량 낭비"; fi
# ★카탈로그 성장 경로가 배선됐는가
if [ -x 02_Infrastructure/ops/rf_weight_catalog_grow.sh ] \
   && grep -q "sync_catalog" 02_Infrastructure/ops/rf_weight_catalog_grow.sh; then
  ok "카탈로그 성장+재색인 배선"; else ng "카탈로그 성장 경로 없음"; fi

echo "=== 12. 변형구현(착안) 경로 ==="
# ★논문이 횡단면 형태가 아니어도 인사이트 이식을 먼저 시도하는가 (도훈 2026-08-30)
if grep -q "fidelity=adapted" 02_Infrastructure/ops/rf_replication_auto.sh; then
  ok "변형구현 경로가 프롬프트에 존재"; else ng "변형구현 경로 없음 — 인사이트를 버린다"; fi
# ★귀속 구분 — adapted 를 충실구현으로 오독하면 misattribution
if grep -q "_adapted_rulefast" 02_Infrastructure/ops/rf_replication_verify.R; then
  ok "adapted 귀속이 base_id 에 새겨짐"; else ng "귀속 미구분 — misattribution 위험"; fi
# ★데이터 부재는 여전히 ABORT 인가 (대리변수 날조 차단)
if grep -q "대리변수로 지어내지 마라" 02_Infrastructure/ops/rf_replication_auto.sh; then
  ok "데이터 부재 → ABORT 유지(날조 차단)"; else ng "데이터 부재 시 날조 허용 위험"; fi
# ★건너뛰기 목록이 무한 재시도를 막는가
if [ -f 06_Registry/replication_skiplist.json ] \
   && grep -q "skiplist" 02_Infrastructure/ops/rf_next_paper_pick.py; then
  ok "재현불가 논문 건너뛰기 배선"; else ng "건너뛰기 없음 — 같은 논문 무한 재시도"; fi

echo "=== 13. LLM 모델·노력수준 명시 ==="
# ★미지정이면 CLI 기본값에 의존한다 — 무인이라 아무도 눈치채지 못한다(도훈 지적 2026-08-30)
for f in 02_Infrastructure/ops/rf_replication_auto.sh 02_Infrastructure/ops/rf_grid_propose.sh; do
  if grep -q -- "--model" "$f" && grep -q -- "--effort" "$f"; then
    ok "model/effort 명시: $(basename $f)"; else ng "model/effort 미지정: $(basename $f)"; fi
done
if "$PY" -c "
import io,json,sys
d=json.loads(io.open('06_Registry/reinforce_auto_config.json','rb').read().decode('utf-8'))
l=d.get('llm') or {}
sys.exit(0 if l.get('model')=='opus' and l.get('effort')=='max' else 1)"; then
  ok "설정에 opus/max 기록"; else ng "설정에 llm 정책 없음"; fi

echo "=== 14. 사이클 시간 계측 · 상태 전이 ==="
if "$PY" -c "import ast,io; ast.parse(io.open('02_Infrastructure/ops/rf_cycle_time.py',encoding='utf-8').read())" 2>/dev/null; then
  ok "parse rf_cycle_time.py"; else ng "parse rf_cycle_time.py"; fi
# ★검증이 오래 돌 때 LLM 호출이 중복되지 않게 상태가 전이되는가(cleaner distill_status 선례)
if grep -q "in_progress" 02_Infrastructure/ops/rf_replication_auto.sh; then
  ok "요청 상태 전이(pending→in_progress) 존재"; else ng "상태 전이 없음 — 중복 LLM 호출 위험"; fi
# ★인증 실패는 pending 으로 되돌아가야 재인증 후 자동 재시도된다
if sed -n '/halt_auth_expired/,/^fi$/p' 02_Infrastructure/ops/rf_replication_auto.sh | grep -q "pending"; then
  ok "인증 실패 → pending 복원"; else ng "인증 실패 후 재시도 불가"; fi

echo "=== 15. 기저 신호 캐시 ==="
# ★강화 25칸은 같은 기저를 쓴다 — 캐시가 없으면 무거운 논문에서 25배를 버린다
if grep -q "rf_base_signal" 02_Infrastructure/reinforcement/rf_cell_engine.R; then
  ok "기저 캐시 존재"; else ng "기저 캐시 없음 — 셀마다 기저 재계산"; fi
# ★캐시 키에 엔진 내용 해시가 들어가는가 (없으면 엔진을 고쳐도 옛 신호를 쓴다)
if grep -q "md5sum" 02_Infrastructure/reinforcement/rf_cell_engine.R; then
  ok "캐시 키에 엔진 내용 해시 포함"; else ng "내용 해시 없음 — 낡은 신호 재사용 위험"; fi
# ★캐시 키에 데이터 판본이 들어가는가
if grep -q "rawdata.parquet" 02_Infrastructure/reinforcement/rf_cell_engine.R; then
  ok "캐시 키에 데이터 판본 포함"; else ng "데이터 판본 없음 — 갱신 후에도 옛 신호"; fi
# ★캐시 저장 실패가 치명적이면 안 된다(비치명 폴백)
if grep -q "캐시 저장 실패(비치명)" 02_Infrastructure/reinforcement/rf_cell_engine.R; then
  ok "캐시 저장 실패 시 비치명 폴백"; else ng "캐시 실패가 셀을 죽인다"; fi

echo "=== 16. 기저 품질 문턱 ==="
# ★기저 알파가 음수면 강화 25칸이 헛돈다 — 예산을 다음 논문에 쓴다(도훈 2026-08-30)
if grep -q "base_below_threshold" 02_Infrastructure/ops/rf_replication_verify.R; then
  ok "기저 품질 문턱 존재"; else ng "문턱 없음 — 음수 알파 위에서 25칸 낭비"; fi
if "$PY" -c "
import io,json,sys
d=json.loads(io.open('06_Registry/reinforce_auto_config.json','rb').read().decode('utf-8'))
sys.exit(0 if 'base_min_port_t' in d else 1)"; then
  ok "설정에 base_min_port_t 기록"; else ng "설정 항목 없음"; fi
# ★문턱 미달이어도 측정 기록은 남아야 한다(생략 = 포기가 아니라 예산 배분)
if sed -n '/base_below_threshold/,/quit(status = 0)/p' 02_Infrastructure/ops/rf_replication_verify.R \
   | grep -q "done_no_reinforce"; then
  ok "미달 시에도 측정 기록 보존(done_no_reinforce)"; else ng "미달 시 기록 소실"; fi
# ★미달이면 다음 논문으로 이월되는가 (멈추면 루프가 끊긴다)
if sed -n '/base_below_threshold/,/quit(status = 0)/p' 02_Infrastructure/ops/rf_replication_verify.R \
   | grep -q "reinforce_auto_next_paper"; then
  ok "미달 → 다음 논문 이월"; else ng "미달 시 루프 정지"; fi

echo "=== 17. 논문 소비 기록 · 프롬프트 백틱 ==="
# ★실사고 2026-08-30: 무인 루프가 방금 끝낸 논문을 연속 두 번 다시 집었다(로그 12:43·12:44).
if grep -q "reinforce_ledger_l1" 02_Infrastructure/ops/rf_next_paper_pick.py; then
  ok "선택기가 원장을 소비 기록으로 읽는다"; else ng "원장 미참조 — 같은 논문 무한 재선택"; fi
# 양성 대조: 원장에 있는 paper_key 가 실제로 후보에서 빠지는가
if "$PY" -c "
import io,json,subprocess,sys,os
led=json.loads(io.open('06_Registry/reinforce_ledger_l1.json','rb').read().decode('utf-8'))
done={str(e.get('paper_key')) for e in led['entries'] if e.get('paper_key')}
out=subprocess.run([sys.executable,'02_Infrastructure/ops/rf_next_paper_pick.py'],
                   capture_output=True,text=True,encoding='utf-8').stdout
picked=set()
for l in out.split(chr(10)):
    l=l.strip()
    if not l: continue
    try: picked.add(str(json.loads(l).get('paper_key')))
    except Exception: pass
sys.exit(1 if (picked & done) else 0)"; then
  ok "원장 등재 논문이 후보에서 제외됨(양성 대조)"; else ng "원장 논문이 후보에 남아 있다"; fi
# ★bash -n 은 백틱을 못 잡는다(명령 치환은 적법 구문) — 전용 검사기가 필요한 이유
if "$PY" 08_Tests/ops/check_prompt_backticks.py \
     02_Infrastructure/ops/rf_replication_auto.sh \
     02_Infrastructure/ops/rf_grid_propose.sh >/dev/null 2>&1; then
  ok "프롬프트 미이스케이프 백틱 0"; else ng "미이스케이프 백틱 — 명령 치환으로 프롬프트 절단"; fi
# 위반 주입: 검사기가 실제로 발화하는가
_INJ="$($PY - <<'PYINJ'
import io,os,tempfile
s=io.open('02_Infrastructure/ops/rf_replication_auto.sh','rb').read().decode('utf-8')
BT=chr(96); BS=chr(92)
f=os.path.join(tempfile.gettempdir(),'rf_bt_inject.sh')
io.open(f,'wb').write(s.replace(BS+BT+'ABORT.txt'+BS+BT, BT+'ABORT.txt'+BT).encode('utf-8'))
print(f)
PYINJ
)"
if "$PY" 08_Tests/ops/check_prompt_backticks.py "$_INJ" >/dev/null 2>&1; then
  ng "백틱 검사기 죽음 — 위반을 못 잡았다"; else ok "백틱 위반 주입 적발(양성 대조)"; fi
rm -f "$_INJ"

echo "=== 18. 충실구현 유한 재시도 (무인 종점에 사람 대기 금지) ==="
if grep -q "PYRETRY" 02_Infrastructure/ops/rf_replication_auto.sh; then
  ok "재시도 블록 배선"; else ng "failed_needs_session 이 종점 — 루프가 죽는다"; fi
# ★스크립트에서 블록을 **추출해** 돌린다 — 사본 재구현이면 검사가 죽는다
if "$PY" - <<'PYT'
import io,json,os,re,subprocess,sys,tempfile
src=io.open("02_Infrastructure/ops/rf_replication_auto.sh","rb").read().decode("utf-8")
m=re.search(r"<<'PYRETRY'\n(.*?)\nPYRETRY", src, re.S)
if not m: sys.exit(1)
tf=os.path.join(tempfile.gettempdir(),"rf_retry_blk.py"); io.open(tf,"wb").write(m.group(1).encode("utf-8"))
fx=os.path.join(tempfile.gettempdir(),"rf_req_fx.json")
cl=os.path.join(tempfile.gettempdir(),"rf_req_fx.claim")
def run(st,n,claim=False):
    io.open(fx,"wb").write(json.dumps({"status":st,"auto_retries":n,"paper":{"paper_key":"T.1"}}).encode("utf-8"))
    if claim: os.makedirs(cl,exist_ok=True)
    elif os.path.isdir(cl): os.rmdir(cl)
    rc=subprocess.run([sys.executable,tf,fx,cl],capture_output=True,text=True).returncode
    d=json.loads(io.open(fx,"rb").read().decode("utf-8"))
    return rc,d.get("status"),d.get("auto_retries")
ok = (run("failed_needs_session",0)==(0,"pending",1)
      and run("failed_needs_session",3)[0]==2
      and run("pending",0)==(0,"pending",0)
      and run("done_no_reinforce",0)==(0,"done_no_reinforce",0)
      and run("in_progress",0)==(0,"pending",0)
      and run("in_progress",0,claim=True)==(0,"in_progress",0))
if os.path.isdir(cl): os.rmdir(cl)
sys.exit(0 if ok else 1)
PYT
then ok "재시도 6경우 정상(양성 대조 + 완료건 부활 금지 + in_progress 부활 양방향)"; else ng "재시도 로직 오작동"; fi
if grep -q "retries_exhausted" 02_Infrastructure/ops/rf_replication_auto.sh \
   && grep -q "reinforce_auto_next_paper" 02_Infrastructure/ops/rf_replication_auto.sh; then
  ok "3회 소진 → 스킵리스트 → 다음 논문"; else ng "소진 후 이월 없음"; fi

echo "=== 19. 성과 요약 · 팩터 회귀 (예전 알파 서칭 포맷) ==="
if [ -f 02_Infrastructure/ops/rf_perf_summary.R ]; then
  ok "성과 요약 헬퍼 존재"; else ng "헬퍼 없음"; fi
# ★수치를 재계산하지 않는가 — 계약 산출물 읽기 전용이어야 한다(손계산 금지)
if grep -qE "06_metrics.csv|07_benchmark_compare.csv" 02_Infrastructure/ops/rf_perf_summary.R \
   && ! grep -qE "sd\(|mean\(ret|cumprod|Return\.annualized" 02_Infrastructure/ops/rf_perf_summary.R; then
  ok "계약 산출물 읽기 전용(자체 계산 없음)"; else ng "헬퍼가 성과를 자체 계산한다"; fi
# 실산출물로 kv 가 채워지는가 (양성 대조)
if "$PY" -c "
import io,os,subprocess,sys
d='stage_artifacts/replication/20260830_123019_12956'
if not os.path.isdir(d): sys.exit(0)
r=subprocess.run(['Rscript','-e','source(\"02_Infrastructure/ops/rf_perf_summary.R\"); k <- rf_perf_kv(\"'+d+'\"); cat(length(k))'],
                 capture_output=True,text=True)
sys.exit(0 if '10' in r.stdout or '11' in r.stdout or '12' in r.stdout or '13' in r.stdout else 1)"; then
  ok "실산출물에서 성과 요약 10항 이상"; else ng "kv 가 비어 나온다"; fi
# FF3/FF5/Carhart + FMB 생산자 배선
if grep -q "run_analysis(.sim_fa" 02_Infrastructure/alpha_search/run_paper_replication.R; then
  ok "FF3/FF5/Carhart + FMB 생산 배선(충실구현·강화 셀 공통)"; else ng "팩터 회귀 미생산"; fi
# 소비자 — 생산만 하고 안 보내면 계기에 소비자가 없다
if grep -q "tg_pass_analysis" 02_Infrastructure/ops/rf_replication_verify.R \
   && grep -q "tg_pass_analysis" 02_Infrastructure/ops/rf_auto_notify.R; then
  ok "[팩터 분석] 소비자 2곳 배선"; else ng "생산만 하고 발송 없음 — 소비자 없는 계기"; fi
# 산출물 부재를 침묵하지 않는가
if grep -q "factor_analysis_absent" 02_Infrastructure/ops/rf_replication_verify.R; then
  ok "산출물 부재 시 사유 기록(침묵 누락 금지)"; else ng "부재가 조용히 넘어간다"; fi

echo "=== 20. 엔진 실행 스모크 (양방향) ==="
# 1번 섹션은 엔진에 parse() 만 건다. 2026-08-30 실사고 — N-ary 리팩터가 남긴
# 미정의 변수(.f2)가 parse 를 통과해 B1 다섯 칸을 전멸시켰다(등급 0건).
# 구문만 보는 계기는 런타임 결함을 구조적으로 못 본다 — 엔진을 실제로 평가한다.
SMOKE=$(Rscript 08_Tests/reinforcement/test_rf_cell_engine_smoke.R 2>&1); SRC=$?
if [ "$SRC" -eq 0 ]; then
  ok "엔진 실행 스모크 — $(echo "$SMOKE" | tail -1)"
else
  ng "엔진 실행 스모크" "$(echo "$SMOKE" | grep FAIL | head -1)"
fi
# 계기의 계기 — 스모크가 양성 대조만 돌고 있지 않은가
if grep -q "f2ghost" 08_Tests/reinforcement/test_rf_cell_engine_smoke.R; then
  ok "스모크에 위반 주입 항 존재(통과만 확인하는 계기 금지)"
else
  ng "스모크 위반 주입 부재" "양성 대조만 있는 계기는 방어선이 아니다"
fi
# claim 격리 — 검사의 restore 가 공유 mutex 를 지우면 살아있는 배치가 무방비가 된다
if grep -q "QVEST_RF_CLAIM" 02_Infrastructure/ops/reinforce_auto_run.R && grep -q "QVEST_RF_CLAIM" 02_Infrastructure/ops/reinforce_auto_parallel.R; then
  ok "러너 2종이 claim 경로 오버라이드를 존중(검사가 공유 claim 무접촉)"
else
  ng "claim 오버라이드 미지원" "검사 restore 가 살아있는 배치의 mutex 를 지운다"
fi

echo "=== 21. B+ 승격 분기 (양방향) ==="
# 도훈 지시 2026-08-30 — 25칸 소진 시 승자가 B 이상이면 그 구성(carry)을 물려 새 25칸을 열다.
# 게이트가 회귀하면 ①영영 승격 안 함 ②무한 승격 — 둘 다 로그가 조용해 정상처럼 보인다.
if grep -q "rf_promote_decide" 02_Infrastructure/ops/reinforce_auto_next_paper.R; then
  ok "이월 경로가 승격 판정을 호출"
else ng "승격 분기 미배선" "25칸 소진 = 무조건 다음 논문"; fi
if grep -q 'E$carry' 02_Infrastructure/ops/reinforce_auto_parallel.R && grep -q 'E$carry' 02_Infrastructure/ops/reinforce_auto_run.R; then
  ok "러너 2종이 carry 를 셀 스펙에 병합"
else ng "carry 미병합" "승격해도 승자 구성이 안 물려진다"; fi
if grep -q "count_paper" 02_Infrastructure/reinforcement/reinforce_ledger.R; then
  ok "승격은 논문 소비 카운터를 안 올린다(결합 검토 3편 주기 보존)"
else ng "count_paper 부재" "승격이 결합 검토 주기를 앞당긴다"; fi
PROMO=$(Rscript 08_Tests/reinforcement/test_rf_promote.R 2>&1); PRC=$?
if [ "$PRC" -eq 0 ]; then
  ok "승격 판정 양방향 — $(echo "$PROMO" | tail -1)"
else
  ng "승격 판정" "$(echo "$PROMO" | grep FAIL | head -1)"
fi

echo "=== 22. claim 소유권 (양방향) ==="
# 고아 claim 은 **정상 대기와 로그가 같다**(halt_claimed 반복) — 2026-08-30 에 두 번,
# 각각 최대 6시간씩 무인 루프를 조용히 세웠다. 회귀해도 조용하므로 검사로 박아둔다.
if grep -q "rf_claim_acquire" 02_Infrastructure/ops/reinforce_auto_parallel.R && grep -q "rf_claim_acquire" 02_Infrastructure/ops/reinforce_auto_run.R; then
  ok "러너 2종이 claim 헬퍼 경유"
else ng "claim 인라인" "고아 회수가 시간 폴백(6h)으로만 남는다"; fi
if grep -q "claim_release_failed" 02_Infrastructure/ops/reinforce_auto_parallel.R; then
  ok "해제 실패를 조용히 넘기지 않는다"
else ng "해제 실패 무기록" "고아가 생겨도 로그에 흔적이 없다"; fi
# 위임 라이브락 — 부모가 claim 을 쥔 채 자식을 부르면 자식이 자기 부모에게 막힌다.
# 2026-08-30 실사고: halt_exhausted_delegate → halt_claimed 가 8분마다 2시간 반 반복,
# 소진 전이가 영영 안 됐다. 로그는 오류가 아니라 정상 대기처럼 보였다.
if grep -q "QVEST_RF_CLAIM_HELD" 02_Infrastructure/ops/reinforce_auto_parallel.R && grep -q "QVEST_RF_CLAIM_HELD" 02_Infrastructure/ops/reinforce_auto_run.R; then
  ok "위임 시 claim 상속 플래그(라이브락 방지)"
else ng "claim 상속 플래그 부재" "위임이 자기 부모에게 막혀 소진 전이가 멈춘다"; fi
# Windows 에서 system2(env=) 는 무시된다 — 부모 환경에 심어야 자식이 상속한다
if grep -q "Sys.setenv(QVEST_RF_CLAIM_HELD" 02_Infrastructure/ops/reinforce_auto_parallel.R; then
  ok "플래그를 부모 환경에 심는다(system2 env= 는 Windows 에서 무시)"
else ng "플래그 전달 방식" "system2(env=) 는 Windows 에서 자식에게 안 간다"; fi
CLM=$(Rscript 08_Tests/reinforcement/test_rf_claim.R 2>&1); CRC=$?
if [ "$CRC" -eq 0 ]; then
  ok "claim 소유권 양방향 — $(echo "$CLM" | tail -1)"
else
  ng "claim 소유권" "$(echo "$CLM" | grep FAIL | head -1)"
fi

echo "=== 23. 블록 L-code 무인 발행 · 대상 표기 ==="
# SKILL §0 은 '블록당 L-code 1건' 을 규정했는데 러너에 소비자가 0개였다 — 세션이
# 안 오면 그 블록의 학습이 원장 밖에서 증발한다. 조용한 실패라 계기로 박아둔다.
if grep -q "rf_emit_block_lcode" 02_Infrastructure/ops/reinforce_auto_parallel.R && grep -q "rf_emit_block_lcode" 02_Infrastructure/ops/reinforce_auto_run.R; then
  ok "러너 2종이 블록 L-code 발행을 호출"
else ng "L-code 소비자 부재" "무인 루프에 사람 대기 지점이 남는다"; fi
# 대상 표기 — 논문 제목이 하드코딩되어 모든 블록 텔레그램이 틀린 대상을 보고했다(2026-08-30)
if grep -q "rf_target_label" 02_Infrastructure/ops/rf_auto_notify.R; then
  ok "텔레그램 대상을 원장에서 파생"
else ng "대상 파생 부재" "논문이 바뀜어도 안 따라온다"; fi
# ★주석이 아니라 **코드**를 재야 한다 — 수리를 설명하는 주석에 그 단어가 남아 있어서
#   첫 판이 자기 설명문에 걸렸다(계기가 프로즈를 쟀다).
if grep "제가디시" 02_Infrastructure/ops/rf_auto_notify.R | grep -qv "^ *#"; then
  ng "논문 제목 하드코딩 잔존(코드)" "하드코딩 전면 금지(헌법)"
else ok "논문 제목 하드코딩 0건(주석 제외)"; fi
LCB=$(Rscript 08_Tests/reinforcement/test_rf_block_lcode.R 2>&1); LRC=$?
if [ "$LRC" -eq 0 ]; then
  ok "L-code 계약 — $(echo "$LCB" | tail -1)"
else
  ng "L-code 계약" "$(echo "$LCB" | grep FAIL | head -1)"
fi

echo "=== 24. 격자 ↔ 원장 계약 ==="
# 격자와 원장 검증기는 다른 파일인데 서로를 전제한다. 2026-08-30 B3 축이
# risk_overlay → universe 로 바뀌었는데 원장 허용 목록이 안 따라와 B3 5칸이 **등록에서**
# 거부됐고(append_failed → halt_no_jobs) 루프가 10/20 에서 영구 정지했다.
# 로그에는 오류가 아니라 '할 일 없음' 으로 찍혀 정상 대기처럼 보였다.
GRD=$(Rscript 08_Tests/reinforcement/test_rf_grid_contract.R 2>&1); GRC=$?
if [ "$GRC" -eq 0 ]; then
  ok "격자↔원장 계약 — $(echo "$GRD" | tail -1)"
else
  ng "격자↔원장 계약" "$(echo "$GRD" | grep FAIL | head -1)"
fi

echo "=== 25. 오버레이 등록부 소비 ==="
# 도훈 2026-08-30 "오버레이 방법론을 특정하는건 별로인데" — 격자에 방법을 박으면 새 방법이
# 등록돼도 아무도 안 쓰고 같은 다섯 개만 반복 측정한다. 격자는 축만 선언하고 칸은 등록부에서 뽑는다.
OVA=$(Rscript 08_Tests/reinforcement/test_rf_overlay_arms.R 2>&1); ORC=$?
if [ "$ORC" -eq 0 ]; then
  ok "오버레이 등록부 — $(echo "$OVA" | tail -1)"
else
  ng "오버레이 등록부" "$(echo "$OVA" | grep FAIL | head -1)"
fi
echo "=== 22b. 충실구현 claim — 죽은 소유자를 회수하는가 ==="
# 강화 러너(rf_claim.R)는 owner pid 사망을 보고 나이 무관 즉시 회수한다. 충실구현 claim 은
# 2시간 경과만 봐서, 에이전트가 죽으면 그 두 시간 동안 in_progress 복원이 "아직 돌고 있다" 로
# 판단해 루프가 통째로 선다(2026-08-31: 22:58 사망 후 45분 halt_no_active_entry 반복).
# 같은 계기가 한쪽에만 깔려 있으면 죽은 claim 하나가 루프를 영구 차단한다.
if grep -q 'echo \$\$ > "\$CLAIM/owner"' 02_Infrastructure/ops/rf_replication_auto.sh; then
  ok "충실구현 claim 이 owner pid 를 남긴다"
else ng "owner pid 미기록" "죽은 소유자를 구분할 수 없다"; fi
if grep -q 'kill -0 "\$COWN"' 02_Infrastructure/ops/rf_replication_auto.sh; then
  ok "pid 사망 시 즉시 회수"
else ng "나이 기준만 본다" "에이전트 사망이 2시간 정지가 된다"; fi
# ★양성 대조 — 검사기가 실제로 발화하는가
PRB5="$ROOT/.cache/_rf_claim_probe.sh"; printf 'mkdir "$CLAIM"
' > "$PRB5"
if grep -q 'kill -0 "\$COWN"' "$PRB5"; then ng "claim 검사기 오발화 — 죽은 검사"
else ok "claim 검사기 음성 대조 정상"; fi
rm -f "$PRB5"

echo "=== 23b. 논문 간 결합 — 착수 소비자가 있는가 ==="
# 검토기는 2026-08-30 부터 후보를 쌓았지만(4회·10쌍) 소비자가 없었다. 검토 note 가 스스로
# "착수하지 않는다" 고 적어 두었고 세션도 착수한 적이 없다 — 생산자만 있는 계기.
CBL=$(Rscript 08_Tests/reinforcement/test_rf_combination_launch.R 2>&1); CBR=$?
if [ "$CBR" -eq 0 ]; then ok "결합 착수 — $(echo "$CBL" | tail -1)"
else ng "결합 착수" "$(echo "$CBL" | grep FAIL | head -1)"; fi

echo "=== 24a. 충실구현 — 엔진이 낸 비중이 버려지지 않는가 ==="
# 무인 3편(2608.24703·27156·27076)이 전부 top_n_long 으로 측정됐다. 엔진은 논문 비중을
# PORTFOLIO 로 냈는데 construction 기본값이 그걸 덮었고, 검증기는 portfolio_spec 을 아예
# 안 넘겼다. 27076 은 롱숏(베타≈0) 논문이 롱온리 36종으로 나가 비교가 성립하지 않았다.
PSP=$(Rscript 08_Tests/reinforcement/test_rp_portfolio_spec.R 2>&1); PRC=$?
if [ "$PRC" -eq 0 ]; then ok "충실구현 포트 사양 — $(echo "$PSP" | tail -1)"
else ng "충실구현 포트 사양" "$(echo "$PSP" | grep FAIL | head -1)"; fi

echo "=== 24b. 텔레그램 '보냈다' 가 실제 발송인가 ==="
# tg_send() 는 HTTP 실패를 **예외가 아니라** list(ok=FALSE,...) 로 돌려준다. 구판은 그 값을
# 버리고 예외만 없으면 성공으로 기록했다 — 실증 2026-08-30 07:16: 429 로 9건이 유실됐는데
# 발신자는 전부 sent=true 였다. 아무도 모른 채 사라졌다.
# 판정 축 = **결과를 변수에 받는가**. 줄 끝 패턴으로 재면 ".r <- tg_send_rich(...)" 도
# 같은 모양이라 고친 코드가 오탐된다(2026-08-31 첫 판이 실제로 그랬다).
if sed 's/#.*$//' 02_Infrastructure/telegram/telegram_notify.R | grep -qE "^[[:space:]]*tg_send_rich\("; then
  ng "tg_agent_brief 가 발송 반환값을 버린다" "결과를 변수에 안 받는 단독 호출 — 실패가 성공으로 기록된다"
else ok "tg_agent_brief 가 발송 반환값을 읽는다"; fi
# ★양성 대조 — 구판 형태(단독 호출)를 주입하면 발화하는가
PRB4="$ROOT/.cache/_rf_send_probe.R"; printf '  tg_send_rich(msg, emoji_min = emoji_min)
' > "$PRB4"
if sed 's/#.*$//' "$PRB4" | grep -qE "^[[:space:]]*tg_send_rich\("; then ok "발송 반환값 검사기 양성 대조 발화"
else ng "검사기 미발화 — 죽은 검사"; fi
rm -f "$PRB4"
# 러너 2종이 rf_auto_notify 결과를 쓰는가 (예외 부재를 성공으로 지어내지 않는가)
if grep -rqn "rf_auto_notify(.*); TRUE" 02_Infrastructure/ops/reinforce_auto_parallel.R 02_Infrastructure/ops/reinforce_auto_run.R; then
  ng "러너가 '보냈다' 를 지어낸다" "rf_auto_notify 반환값 미사용"
else ok "러너 2종이 실제 발송 결과로 sent 를 정한다"; fi
# ★거동 검사 — 성공/실패/구판 3경우를 실제 함수로 통과시킨다
TGO=$(Rscript 08_Tests/reinforcement/test_rf_send_verdict.R 2>&1); TGR=$?
if [ "$TGR" -eq 0 ]; then ok "발송 판정 3경우 — $(echo "$TGO" | tail -1)"
else ng "발송 판정 거동" "$(echo "$TGO" | grep FAIL | head -1)"; fi

echo "=== 25a. 텔레그램 '무엇을 강화했나' — 기저·비율을 지어내지 않는가 ==="
# 2026-08-31 적발: .rf_f2 가 기저를 "모멘텀 12-1" 로, 결합 비율을 "rankZ 50:50" 으로 **하드코딩**해
# 논문이 바뀌어도(현행 기저 = 충실구현 engine.R) 비율이 바뀌어도(2팩터면 1/3씩) 따라오지 않았다.
# 무인 보고라 아무도 대조하지 않는다 — 틀린 설명이 조용히 반복된다.
if sed 's/#.*$//' 02_Infrastructure/ops/rf_auto_notify.R | grep -qE "모멘텀 12-1|50:50"; then
  ng "텔레그램이 기저/비율을 하드코딩" "논문·팩터수가 바뀌어도 안 따라온다"
else ok "기저·비율 하드코딩 0건(실행 코드)"; fi
# ★양성 대조 — 검사기가 실제로 발화하는가
PRB3="$ROOT/.cache/_rf_tg_probe.R"; printf 'x <- "모멘텀 12-1 + A rankZ 50:50"\n' > "$PRB3"
if sed 's/#.*$//' "$PRB3" | grep -qE "모멘텀 12-1|50:50"; then ok "기저 하드코딩 검사기 양성 대조 발화"
else ng "검사기 미발화 — 죽은 검사"; fi
rm -f "$PRB3"
# 승격 entry 의 대상 라벨이 **최초 조상**에서 오는가 (부모 승자 셀의 근거 논문이 아니라)
if sed 's/#.*$//' 02_Infrastructure/ops/rf_auto_notify.R | grep -q "cur\$parent"; then
  ok "대상 라벨이 승격 사슬을 거슬러 최초 entry 를 읽는다"
else ng "대상이 승자 셀 근거 논문으로 표시된다" "승격 entry 의 base_artifacts 는 부모 승자 셀 산출물이다"; fi

echo "=== 25b. 유니버스 격자 — 넓히는 처치 금지 (구조적 미전달) ==="
# 기저 신호는 충실구현 engine.R 에서 오고 그 엔진이 헌법 유니버스(K200∪KQ150)를 먼저 자른다.
# 그래서 all_listed 같은 **넓히는** 처치는 넓힐 대상이 없다 — rf_cell_engine 이 "측정 무효" 로
# 거절하고, 격자에 남아 있으면 매 논문마다 25칸 중 1칸이 죽은 채 소비된다(2026-08-31 실사고).
if "$PY" -c "
import io,json,sys
g=json.loads(io.open('06_Registry/reinforce_program.json','rb').read().decode('utf-8'))
bad=[c['code'] for b in g['blocks'] for c in b['cells']
     if (c.get('universe') or {}).get('kind')=='all_listed']
sys.exit(1 if bad else 0)"; then
  ok "격자에 all_listed 셀 0건(넓히는 처치 미포함)"
else ng "격자에 all_listed 셀 잔존" "기저가 유니버스를 먼저 자르므로 영구 미전달 — 칸 낭비"; fi
# ★양성 대조: 이 검사가 실제로 발화하는가 (격자 사본에 위반 주입)
if "$PY" -c "
import io,json,sys
g=json.loads(io.open('06_Registry/reinforce_program.json','rb').read().decode('utf-8'))
b3=[b for b in g['blocks'] if b['id']=='B3'][0]
b3['cells'][0]['universe']={'kind':'all_listed'}
bad=[c['code'] for b in g['blocks'] for c in b['cells']
     if (c.get('universe') or {}).get('kind')=='all_listed']
sys.exit(1 if bad else 0)"; then
  ng "all_listed 검사기 죽음 — 위반을 주입해도 통과했다"
else ok "all_listed 검사기 양성 대조 발화"; fi
# ★유니버스 셀은 기저 지지집합의 **부분집합**이어야 처치가 전달된다 — index flag 는 실재해야 한다
if "$PY" -c "
import io,json,sys
g=json.loads(io.open('06_Registry/reinforce_program.json','rb').read().decode('utf-8'))
flags={(c.get('universe') or {}).get('flag') for b in g['blocks'] for c in b['cells']
       if (c.get('universe') or {}).get('kind')=='index'}
sys.exit(0 if flags <= {'K200','KQ150'} else 1)"; then
  ok "index 셀 flag 가 실재 멤버십 열(K200/KQ150)"
else ng "index 셀이 없는 멤버십 열을 참조 — 엔진이 '멤버십 열 부재' 로 죽는다"; fi

echo "=== 25d. 스펙 중복 — 같은 포트폴리오를 다시 재지 않는가 ==="
# carry 대조만으로는 부족하다. 2026-08-31 B4_16~19 는 carry 와도 다르고(유니버스가 격자
# 기본값으로 떨어졌다) 서로는 같아서 같은 t(2.241)를 네 번 냈는데 아무 가드도 안 걸렸다.
DUP=$(Rscript 08_Tests/reinforcement/test_rf_spec_dedup.R 2>&1); DRC=$?
if [ "$DRC" -eq 0 ]; then ok "스펙 중복 가드 — $(echo "$DUP" | tail -1)"
else ng "스펙 중복 가드" "$(echo "$DUP" | grep FAIL | head -1)"; fi
# ★양성 대조: 서명에서 유니버스 축을 빼면 음성 대조가 무너져야 한다.
#   셸 sed 로 하려다 패턴의 '|' 가 구분자와 충돌해 조용히 실패했고, 빈 프로브에서 검사가
#   실패하는 것을 "발화" 로 오독했다(2026-08-31). 주입 실패와 검사 통과를 구분한다.
_DUPP="$("$PY" 08_Tests/ops/mk_partial_sig_probe.py)"
if [ -z "$_DUPP" ]; then ng "중복 검사기 양성 대조 주입 실패" "서명이 바뀌었다 — 검사기가 낡음"
elif QVEST_RF_SIG="$_DUPP" Rscript 08_Tests/reinforcement/test_rf_spec_dedup.R >/dev/null 2>&1; then
  ng "중복 검사기 죽음 — 축을 빼도 통과했다"
else ok "중복 검사기 양성 대조 발화(축 누락 적발)"; fi
rm -f "$_DUPP"

echo "=== 25c. 승계(carry) 처치 전달 ==="
# 승계는 부모 승자 구성을 물려받아 그 위에서 다시 탐색하는 장치인데, 병합이 단순 연결이라
# 같은 팩터가 두 번 들어갔다. 스코어가 rowMeans 등가중이라 기저 가중이 조용히 깎이고
# (실측 2026-08-31: 부모 2.63 -> 자식 2.251, 기저 캐시 md5 동일), carry 와 같아진 칸이
# 블록 승자가 되어 격자가 자기 자신을 반복 측정했다.
CRT=$(Rscript 08_Tests/reinforcement/test_rf_carry_treatment.R 2>&1); CRC=$?
if [ "$CRC" -eq 0 ]; then
  ok "승계 처치 전달 — $(echo "$CRT" | tail -1)"
else
  ng "승계 처치 전달" "$(echo "$CRT" | grep FAIL | head -1)"
fi
# ★양성 대조: 중복 제거를 항등함수로 되돌린 사본에서 실제로 발화하는가
_OLDC="$("$PY" 08_Tests/ops/mk_old_carry_probe.py)"
if [ -n "$_OLDC" ] && QVEST_RF_SIG="$_OLDC" Rscript 08_Tests/reinforcement/test_rf_carry_treatment.R >/dev/null 2>&1; then
  ng "승계 검사기 죽음 — 구판을 주입해도 통과했다"
elif [ -n "$_OLDC" ]; then ok "승계 검사기 양성 대조 발화"
else ng "양성 대조 주입 실패 — 헬퍼를 못 찾았다(검사기 낡음)"; fi
rm -f "$_OLDC"

echo "=== 26. 재개의 출구 (구조적 실패 != 일시 실패) ==="
# 재개는 *일시적* 실패만 상정한 장치였다. rf_cell_engine 의 결정론적 거절(처치 미전달)에는
# 출구가 없어 B3_11 이 2026-08-31 00:16~07:46 사이 16회 동일 실패로 재실행됐고 루프가
# 7.5시간 제자리를 돌았다. 로그는 매번 정상으로 보였다(resume -> spawn -> error -> batch_done).
TRM=$(Rscript 08_Tests/reinforcement/test_rf_terminal_retry.R 2>&1); TRC=$?
if [ "$TRC" -eq 0 ]; then
  ok "재개 출구 계약 — $(echo "$TRM" | tail -1)"
else
  ng "재개 출구 계약" "$(echo "$TRM" | grep FAIL | head -1)"
fi
# ★양성 대조: 구판 술어를 주입하면 위 검사가 실제로 발화하는가 (공유 러너 무접촉 — 사본에 주입)
_OLDR="$("$PY" 08_Tests/ops/mk_old_pending_probe.py)"
if [ -n "$_OLDR" ] && QVEST_RF_RUNNER="$_OLDR" Rscript 08_Tests/reinforcement/test_rf_terminal_retry.R >/dev/null 2>&1; then
  ng "재개 출구 검사기 죽음 — 구판 술어를 주입해도 통과했다"
elif [ -n "$_OLDR" ]; then ok "재개 출구 검사기 양성 대조 발화"
else ng "양성 대조 주입 실패 — 술어를 못 찾았다(검사기 낡음)"; fi
rm -f "$_OLDR"
echo "=== 27. 논문 소비 판정 키의 정본성 ==="
# 판정 쪽에서 키를 다시 만들면 정규화 전후가 어긋나 소비한 논문이 큐 상단에 영원히 남는다.
# 실사고 2026-09-01: paper_key='axv:2505.20608'(접두) vs 원장 '2505.20608'(pid_of 정본) →
# 소비 7초 뒤 같은 논문을 다시 집어 충실구현 재실행, 2608.23944 는 4회 반복 측정, 큐 74건 정체.
PKY=$("$PY" 08_Tests/reinforcement/test_rf_pick_key.py 2>&1); PKR=$?
if [ "$PKR" -eq 0 ]; then
  ok "소비 키 정본 — $(echo "$PKY" | tail -1)"
else
  ng "소비 키 정본" "$(echo "$PKY" | grep FAIL | head -1)"
fi

echo "=== 28. 고아 claim 회수의 순서 (상태 판정보다 먼저) ==="
# 회수 블록이 pending 게이트 뒤에 있으면, in_progress 되살리기가 "claim 없음"을 조건으로 쓰는
# 탓에 고아 claim + in_progress 조합에서 **회수 코드에 영영 도달하지 못한다**.
# 실사고 2026-09-01: owner pid 사망 + in_progress -> 13시간 동안 no_pending_request 만 반복.
# 이 검사는 격리 경로(QVEST_RP_*)로만 돈다 — 공유 요청·claim 무접촉.
_RPD="$ROOT/.cache/_test_rp_claim_order"
rm -rf "$_RPD"; mkdir -p "$_RPD"; : > "$_RPD/jlog.jsonl"
_mkreq(){ printf '%s\n' '{"requested_at":"2026-01-01T00:00:00+0900","source":"test","paper":{"title":"t","paper_title":"t","url":"","paper_key":"TEST","source":"arxiv"},"status":"in_progress","started_at":"2026-01-01T00:00:00+0900"}' > "$_RPD/req.json"; }
_rprun(){ QVEST_RP_REQUEST="$_RPD/req.json" QVEST_RP_CLAIM="$_RPD/claim" QVEST_RP_JLOG="$_RPD/jlog.jsonl" \
          bash 02_Infrastructure/ops/rf_replication_auto.sh >/dev/null 2>&1; }
_st(){ "$PY" -c "
import io,json
print(json.loads(io.open(r'$_RPD/req.json','rb').read().decode('utf-8')).get('status'))" 2>/dev/null; }

# (1) 위반 상태 주입: 죽은 소유자 claim + in_progress -> 회수 + 되살리기
_mkreq; mkdir -p "$_RPD/claim"; echo 999999 > "$_RPD/claim/owner"; _rprun
if [ "$(_st)" = "pending" ] && grep -q claim_stale_reclaim "$_RPD/jlog.jsonl"; then
  ok "고아 claim 회수 — 죽은 소유자 + in_progress 에서 pending 으로 복귀"
else
  ng "고아 claim 회수" "status=$(_st)"
fi
# (2) 양성 대조: 살아있는 소유자 claim 은 회수되지 않는다(동시 배치 방지선 생존)
: > "$_RPD/jlog.jsonl"; rm -rf "$_RPD/claim"; _mkreq; mkdir -p "$_RPD/claim"; echo $$ > "$_RPD/claim/owner"; _rprun
if [ "$(_st)" = "in_progress" ] && [ -d "$_RPD/claim" ]; then
  ok "동시 실행 방지선 생존 — 살아있는 소유자 claim 은 회수하지 않는다"
else
  ng "동시 실행 방지선" "살아있는 claim 을 빼앗았다 (status=$(_st))"
fi
rm -rf "$_RPD"

echo "=== 29. 기저 가중 w0 — 깊이와 희석의 교락 차단 ==="
# 등가중 컴포짓은 팩터 n개에서 논문 신호를 1/(1+n) 로 깎는다(50/33/25/20/17%). B1 이 결합
# 깊이를 재는 블록이 되면서 깊이와 희석이 교락되므로 w0 를 고정했다. 1팩터에서 w0=0.5 가
# 등가중과 수치 동일한 것이 이 검사의 양성 대조다.
BWT=$(Rscript 08_Tests/reinforcement/test_rf_base_weight.R 2>&1); BWR=$?
if [ "$BWR" -eq 0 ]; then
  ok "기저 가중 계약 — $(echo "$BWT" | tail -1)"
else
  ng "기저 가중 계약" "$(echo "$BWT" | grep FAIL | head -1)"
fi

echo "=== 30. 백필 멱등 — '있나' 가 아니라 '쓸 수 있나' ==="
# 고쳐야 하는 값은 대개 없는 게 아니라 있는데 못 쓰는 것이다. C15 는 301개월에 존재하지만
# 전 종목 0.0(sd=0 -> Z NA -> Coverage FALSE)이었고, 생산자가 수리된 뒤에도 백필이
# "이미 있음" 으로 건너뛰어 영원히 안 고쳐졌다.
BFI=$(Rscript 08_Tests/reinforcement/test_rf_backfill_idempotence.R 2>&1); BFR=$?
if [ "$BFR" -eq 0 ]; then
  ok "백필 멱등 판정 축 — $(echo "$BFI" | tail -1)"
else
  ng "백필 멱등 판정 축" "$(echo "$BFI" | grep FAIL | head -1)"
fi

echo "=== 31. 보유 종목수 축 — 이중 선정 차단 ==="
# 강화 셀이 전부 3종목 포트폴리오를 재고 있었다(고정 축은 25). 엔진이 이미 상위 25를 잘라
# FACTORS 를 내보내는데 러너의 top_n_long 이 그 25를 다시 분위(10%)로 잘랐다. 거들던 것은
# 키 불일치 — 워커/러너가 `n =` 을 넘기는데 러너는 spec$n_max / spec$n_long 을 읽는다.
HAX=$(Rscript 08_Tests/reinforcement/test_rf_holdings_axis.R 2>&1); HRC=$?
if [ "$HRC" -eq 0 ]; then
  ok "보유 종목수 축 — $(echo "$HAX" | tail -1)"
else
  ng "보유 종목수 축" "$(echo "$HAX" | grep FAIL | head -1)"
fi

echo "=== 32. 근거 논문 목록 — 첫 계열만 인용·승자 논문 차용 차단 (양방향) ==="
# B1 사슬 5칸이 전부 Amihud(2002) 하나로 원장에 적혔다(첫 계열 = 항상 시드). B5 오버레이는 자체 논문이
# 없어 B1 승자 논문을 차용했다(낙폭 브레이크가 유동성 논문 인용). '같은 root_papers 3회 연속' WARN 20회는
# 한 논문 매몰이 아니라 이 표기 결함을 재고 있었다. 매핑 없는 계열은 이름으로 남아야 한다(침묵 누락 금지).
RPZ=$(Rscript 08_Tests/reinforcement/test_rf_root_papers.R 2>&1); RPR=$?
if [ "$RPR" -eq 0 ]; then
  ok "근거 논문 목록 — $(echo "$RPZ" | tail -1)"
else
  ng "근거 논문 목록" "$(echo "$RPZ" | grep FAIL | head -1)"
fi



echo
printf '합계: 통과 %d · 실패 %d\n' "$PASS" "$FAIL"
printf '{"test":"reinforce_auto","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
