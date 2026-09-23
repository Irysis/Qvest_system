#!/usr/bin/env bash
# test_llm_lane_wiring.sh — 무인 LLM 호출의 모델·노력 배선 (2026-09-23 도훈 지시 "무인실행에서 LLM 개입부 모두 opus max")
#
# 실사고: 레인 정책(06_Registry/reinforce_auto_config.json::llm.lanes)을 바꿔도 **닿지 않는 레인**이 넷 있었다
#   (paper_router · alpha_search_queue · mode_queue_research · factor_deep_recheck) — `claude -p` 를
#   --model/--effort 없이 불러 CLI 기본값으로 돌았다. 격자 제안(rf_grid_propose)은 충실구현 레인 변수를 빌려 썼다.
#   정책 문서가 소비자에게 닿는지는 문서를 읽어선 모른다 — **호출부를 재도출**해야 한다.
# 재는 것:
#   A. 정적 배선 — 02_Infrastructure/ops/*.sh 의 모든 실행 `claude -p` 논리 줄(\ 연속 결합)이 --model 과 --effort 를 싣는다
#   B. 위반 주입 — 레인 스크립트 사본에서 모델 인자를 지우면 A 가 잡는다(판별력)
#   C. 해석 — 새로 배선한 5 레인이 rf_llm_resolve 를 부르고 설정 lane 이름과 일치한다
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"; [ -x "$PY" ] || PY=python
P=0; F=0
ok(){ P=$((P+1)); echo "  OK   $1"; }
ng(){ F=$((F+1)); echo "  FAIL $1 — ${2:-}"; }

scan(){  # $1 = 디렉터리 → 위반 목록(파일:논리줄 시작)을 stdout 으로
  "$PY" - "$1" <<'PYEOF'
import io, os, re, sys
d = sys.argv[1]
CALL = re.compile(r'(^|[\s;(&|])("?\$\{?[A-Za-z_]*(CLAUDE_BIN|bin)\}?"?|claude)\s+-p(\s|$)')
bad = []
for fn in sorted(os.listdir(d)):
    if not fn.endswith('.sh'): continue
    lines = io.open(os.path.join(d, fn), encoding='utf-8', errors='replace').read().splitlines()
    i = 0
    while i < len(lines):
        start = i; buf = lines[i]
        while buf.rstrip().endswith('\\') and i + 1 < len(lines):
            i += 1; buf = buf.rstrip()[:-1] + ' ' + lines[i]
        i += 1
        s = buf.strip()
        if not s or s.startswith('#'): continue
        # 문자열 속 언급(log/echo/printf/주석성 문장)은 실행 호출이 아니다
        if re.match(r'^(log|echo|printf|jl|jlog|note|reason)\b', s): continue
        code = s.split(' #', 1)[0]
        mm = CALL.search(code)
        if not mm: continue
        # echo/printf 인자 속 문자열(안내문)은 실행 호출이 아니다 — 매치 앞에 echo 가 있으면 건너뛴다
        if re.search(r'\b(echo|printf)\b', code[:mm.start()]): continue
        # 모델·노력을 배열로 싣는 레인: 파일이 LANE_LLM_ARGS=(--model … --effort …) 를 정의하고 호출이 그 배열을 펼친다
        arr_ok = ('"${LANE_LLM_ARGS[@]}"' in code and
                  any(re.match(r'^\s*LANE_LLM_ARGS=\(.*--model.*--effort.*\)', l) for l in lines))
        if not arr_ok and ('--model' not in code or '--effort' not in code):
            bad.append(f'{fn}:{start+1}')
print('\n'.join(bad))
PYEOF
}

echo "=== A. 정적 배선 — 모든 claude -p 호출이 --model · --effort 를 싣는다 ==="
OPS="$ROOT/02_Infrastructure/ops"
out=$(scan "$OPS" | tr -d '\r')
[ -z "$out" ] && ok "A1 ops/*.sh 실행 호출 전부 모델·노력 명시" || ng "A1 모델·노력 누락 호출" "$(echo "$out" | head -5 | tr '\n' ' ')"

echo "=== B. 위반 주입 (사본) ==="
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cp "$OPS/paper_router_run.sh" "$T/"
sed -i 's/ "\${LANE_LLM_ARGS\[@\]}"//' "$T/paper_router_run.sh"
out2=$(scan "$T" | tr -d '\r')
[ -n "$out2" ] && ok "B1 모델 인자를 지운 사본을 잡는다 ($out2)" || ng "B1 판별력 없음 — 인자를 지워도 통과"
cp "$OPS/rf_grid_propose.sh" "$T/"
sed -i 's/--effort "\$LLM_EFFORT" //' "$T/rf_grid_propose.sh"
out3=$(scan "$T" | tr -d '\r' | grep rf_grid_propose || true)
[ -n "$out3" ] && ok "B2 노력 인자만 지워도 잡는다" || ng "B2 판별력 없음(effort)"

echo "=== C. 새 배선 5 레인 — 해석기 호출 · 설정 lane 일치 ==="
for pair in paper_router_run.sh:paper_router alpha_search_queue_run.sh:alpha_search_queue \
            mode_queue_research_run.sh:mode_queue_research factor_deep_recheck_run.sh:factor_deep_recheck \
            rf_grid_propose.sh:grid_propose; do
  f="${pair%%:*}"; lane="${pair#*:}"
  if grep -q "^rf_llm_resolve $lane " "$OPS/$f"; then ok "C $f → rf_llm_resolve $lane"; else ng "C $f" "rf_llm_resolve $lane 부재"; fi
done
lanes=$("$PY" -c "import io,json;c=json.loads(io.open(r'$ROOT/06_Registry/reinforce_auto_config.json','rb').read().decode('utf-8'));print(' '.join(sorted((c.get('llm') or {}).get('lanes',{}).keys())))" | tr -d '\r')
miss=""
for l in paper_router alpha_search_queue mode_queue_research factor_deep_recheck grid_propose; do
  case " $lanes " in *" $l "*) ;; *) miss="$miss $l" ;; esac
done
[ -z "$miss" ] && ok "C6 설정 llm.lanes 에 5 레인 등재" || ng "C6 설정 누락" "$miss"
for f in paper_router_run.sh alpha_search_queue_run.sh mode_queue_research_run.sh factor_deep_recheck_run.sh rf_grid_propose.sh; do
  bash -n "$OPS/$f" || ng "C7 문법 $f"
done
ok "C7 5 레인 문법(bash -n)"

echo
echo "합계: 통과 $P · 실패 $F"
echo "{\"test\":\"llm_lane_wiring\",\"pass\":$P,\"fail\":$F,\"total\":$((P+F))}"
[ "$F" -eq 0 ]
