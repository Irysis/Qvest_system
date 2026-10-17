#!/usr/bin/env bash
#==============================================================================
# test_replication_lane.sh — 무인 충실구현 레인 · 스케줄 진입점 · 논문 공급 (v10.01 · 2026-10-13)
#
# 왜: 구 test_reinforce_auto.sh(1,068줄)는 고정 격자 강화 러너(reinforce_auto_parallel.R)와 충실구현 레인을 한 파일에서 쟀다.
#   러너가 퇴역해(v10.01 · 롤백 태그 pre-v10.01-prescription-20261013) 러너 절(kill switch · daily_cap · 러너 claim 통합 ·
#   퇴역 러너 · 격자 무결성 · 병렬 배치 · 결합 검토 · 승격 · 블록 L-code · 격자↔원장 · 결합 착수 · 승계 · 재개 출구 · 기저 가중)은
#   대상과 함께 지웠다. 남는 레인·공급·진입점 절만 옮겨 오고, v10.01 이 바꾼 두 계약을 새로 잰다:
#     ① 스위치 분리 — 레인은 config replication_lane.enabled 만 본다(퇴역 러너의 전역 enabled=false 에 멈추지 않는다)
#     ② 공급기 — 다음 논문은 programs/next_replication.R 이 낸다(구 reinforce_auto_next_paper.R 퇴역)
# 원칙: 양방향(정상 + 위반 주입) · 공유 요청·claim·로그 무접촉(QVEST_RP_* 격리 경로) · 주석이 아니라 실행 코드를 잰다.
# 개별 검사 파일(셀 엔진 스모크 · claim · 포트 사양 · 선택 키 · 백필 · 보유 축 · 근거 논문 · 오버레이 등록부 · 재구현 대기열)은
#   배터리(08_Tests/hooks/run_all_hooks.sh SUITES)에 따로 편입돼 있어 여기서 다시 돌리지 않는다.
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
LANE=02_Infrastructure/ops/rf_replication_auto.sh
VERIFY=02_Infrastructure/ops/rf_replication_verify.R
TICK=02_Infrastructure/ops/reinforce_auto_tick.sh
SUPPLY=02_Infrastructure/programs/next_replication.R
# 임시 디렉터리는 Windows 경로로 — 파이썬 -c 본문 안 경로는 MSYS 인자 변환을 받지 못한다(첫 판 실측: /tmp/... FileNotFoundError)
T="$(cygpath -m "$(mktemp -d)" 2>/dev/null)"; [ -n "$T" ] || T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "=== 1. 구문 ==="
for f in 02_Infrastructure/reinforcement/rf_cell_engine.R "$SUPPLY" "$VERIFY" 02_Infrastructure/ops/rf_claim.R; do
  if Rscript -e "invisible(parse('$f'))" >/dev/null 2>&1; then ok "parse $f"; else ng "parse $f"; fi
done
for f in "$LANE" "$TICK"; do bash -n "$f" 2>/dev/null && ok "syntax $f" || ng "syntax $f"; done
if "$PY" -c "import ast,io; ast.parse(io.open('02_Infrastructure/ops/rf_next_paper_pick.py',encoding='utf-8').read())" 2>/dev/null; then
  ok "parse rf_next_paper_pick.py"; else ng "parse rf_next_paper_pick.py"; fi

echo "=== 2. 스케줄 진입점 — 퇴역 러너 호출 0 (양방향 · 주석 제외) ==="
TICK_NC=$(sed 's/#.*$//' "$TICK")
if printf '%s' "$TICK_NC" | grep -q "rf_replication_auto.sh" && printf '%s' "$TICK_NC" | grep -q "rf_l2_auto.sh"; then
  ok "tick 이 충실구현 레인 · 2계층 레인을 부른다"; else ng "tick 이 남길 레인을 안 부른다"; fi
RETIRED_RE='reinforce_auto_parallel\.R|reinforce_auto_run\.R|reinforce_auto_next_paper\.R|rf_b1_design\.sh|rf_b5_design\.sh|rf_overlay_propose\.sh|rf_grid_propose\.sh|rf_director\.R'
if printf '%s' "$TICK_NC" | grep -qE "$RETIRED_RE"; then ng "tick 이 퇴역 레인을 부른다" "$(printf '%s' "$TICK_NC" | grep -oE "$RETIRED_RE" | head -2 | tr '\n' ' ')"
else ok "tick 실행 코드에 퇴역 러너·설계 레인·디렉터 호출 0"; fi
printf 'Rscript "$ROOT/02_Infrastructure/ops/reinforce_auto_parallel.R"\n' > "$T/tick_probe.sh"
if sed 's/#.*$//' "$T/tick_probe.sh" | grep -qE "$RETIRED_RE"; then ok "퇴역 호출 검사기 양성 대조 발화"; else ng "퇴역 호출 검사기 미발화 — 죽은 검사"; fi
for f in "$TICK" 02_Infrastructure/ops/morning_run.sh; do
  for g in $(sed 's/#.*$//' "$f" | grep -oE '02_Infrastructure/[A-Za-z0-9_/]+\.(sh|R|py)' | sort -u); do
    [ -f "$g" ] || ng "$(basename "$f") 가 없는 파일을 부른다" "$g"
  done
done
ok "tick · morning_run 이 부르는 파일 실재 확인(없으면 위에 FAIL)"

echo "=== 3. claim 단위 — rf_claim_acquire 양방향(러너 무관 · 2계층·증류·재측정이 쓴다) ==="
cat > "$T/claim_probe.R" <<'RPROBE'
args <- commandArgs(trailingOnly = TRUE)
ROOT <- args[1]; CL <- args[2]
suppressMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_claim.R")))
unlink(CL, recursive = TRUE); dir.create(CL, recursive = TRUE, showWarnings = FALSE)
self <- Sys.getpid(); DEAD <- 999901L
wr <- function(pid) writeLines(toJSON(list(pid = pid, started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), host = "fixture"),
        auto_unbox = TRUE), file.path(CL, "owner.json"))
r <- list()
r$instr_self_alive <- isTRUE(rf_claim_pid_alive(self))
r$instr_dead_alive <- isTRUE(rf_claim_pid_alive(DEAD))
wr(self); a1 <- rf_claim_acquire(CL, stale_hours = 6)
r$live_ok <- isTRUE(a1$ok); r$live_reason <- as.character(a1$reason %||% "")
wr(DEAD); a2 <- rf_claim_acquire(CL, stale_hours = 6)
r$dead_ok <- isTRUE(a2$ok); r$dead_reason <- as.character(a2$reason %||% "")
unlink(CL, recursive = TRUE)
cat(toJSON(r, auto_unbox = TRUE), "\n")
RPROBE
PROBE=$(Rscript "$T/claim_probe.R" "$ROOT" "$T/claim_unit" 2>&1 | tail -1)
jget(){ printf '%s' "$PROBE" | "$PY" -c "
import sys,json
try: print(json.loads(sys.stdin.read()).get(sys.argv[1]))
except Exception: print('PARSE_FAIL')" "$1" 2>/dev/null; }
[ "$(jget instr_self_alive)" = "True" ] && ok "계기 양성 대조 — 살아있는 Windows pid = 생존" || ng "계기가 살아있는 pid 를 사망으로 읽는다" "$PROBE"
[ "$(jget instr_dead_alive)" = "False" ] && ok "계기 위반 주입 — 없는 pid = 사망" || ng "계기가 없는 pid 를 생존으로 읽는다" "$PROBE"
[ "$(jget live_ok)" = "False" ] && [ "$(jget live_reason)" = "claimed" ] && ok "살아있는 소유자 → 인수 거부(claimed)" || ng "살아있는 소유자 claim 을 빼앗았다" "$PROBE"
[ "$(jget dead_ok)" = "True" ] && [ "$(jget dead_reason)" = "acquired" ] && ok "죽은 소유자 → 즉시 회수(acquired)" || ng "죽은 소유자 claim 을 회수 못 한다" "$PROBE"

echo "=== 4. 논문 선택기 (양방향) ==="
OUT=$("$PY" 02_Infrastructure/ops/rf_next_paper_pick.py stage_artifacts/paper_recharge 2>&1)
if printf '%s' "$OUT" | "$PY" -c "
import sys,json; o=json.loads(sys.stdin.read()); sys.exit(0 if o.get('url','').startswith('http') else 1)" 2>/dev/null; then
  ok "큐 상단 논문 + 원문 링크 산출"; else ng "논문 선택 실패" "${OUT:0:200}"; fi
mkdir -p "$T/empty_q"; OUT=$("$PY" 02_Infrastructure/ops/rf_next_paper_pick.py "$T/empty_q" 2>&1)
if printf '%s' "$OUT" | grep -q '"error"'; then ok "빈 큐 → 오류 반환(링크 날조 없음)"; else ng "빈 큐인데 링크를 냈다" "${OUT:0:200}"; fi

echo "=== 5. 자본 경계 (정적 · 실행 코드) ==="
HITS=$(for f in 02_Infrastructure/reinforcement/rf_cell_engine.R "$SUPPLY" "$VERIFY" 02_Infrastructure/programs/*.R; do
         sed 's/#.*$//' "$f" | grep -nE "book_state|05_Production" | sed "s|^|$f:|"; done)
[ -z "$HITS" ] && ok "레인·공급기·프로그램 실행 코드에 book_state/05_Production 미참조" || ng "실행 코드가 자본 경로를 참조" "$HITS"
printf 'x <- "05_Production/foo"\n' > "$T/boundary_probe.R"
sed 's/#.*$//' "$T/boundary_probe.R" | grep -qE "book_state|05_Production" && ok "자본 경계 검사기 양성 대조 발화" || ng "자본 경계 검사기 미발화"

echo "=== 6. 공리 자동 활성화 (정적 · 동결 경로) ==="
Rscript -e "invisible(parse('02_Infrastructure/ops/rf_axiom_activate.R'))" >/dev/null 2>&1 && ok "parse rf_axiom_activate.R" || ng "parse rf_axiom_activate.R"
sed 's/#.*$//' 02_Infrastructure/ops/rf_axiom_activate.R | grep -q "x\$refine" && ok "초안 배제 조건 존재" || ng "초안 배제 조건 없음"
grep -q "deactivate_axiom" 02_Infrastructure/ops/rf_axiom_activate.R && ok "되돌리기 경로 안내 포함" || ng "되돌리기 경로 없음"
if "$PY" - <<'PYX'
import io,json,glob,sys
bad=[]
for f in glob.glob("qepm/memory/axioms/active/modes/**/AX-*.json", recursive=True):
    d=json.loads(io.open(f,"rb").read().decode("utf-8"))
    if (d.get("status") or "active")=="active" and d.get("needs_refinement"): bad.append(d.get("axiom_id"))
sys.exit(1 if bad else 0)
PYX
then ok "활성 공리 중 초안 0건(불변식)"; else ng "활성 공리에 초안이 섞였다"; fi

echo "=== 7. 무인 충실구현 안전장치 (정적) ==="
grep -q "disallowed-tools" "$LANE" && grep -q "Bash,Agent" "$LANE" && ok "헤드리스 권한 축소(Bash/Agent 금지)" || ng "권한 축소 없음"
grep -q "failed_needs_session" "$VERIFY" && ok "검증 실패 → 세션 대기" || ng "실패 경로 없음"
grep -q "authoritative_remeasure" "$VERIFY" && ok "등급 출처 = 계약 산출물" || ng "등급 출처 불명"
grep -q 'ENV_FAIL="claude_auth_expired"' "$LANE" && grep -q "jl halt_env_failure" "$LANE" && ok "환경 실패(인증 만료) 분기 — 리서치 실패와 구분" || ng "환경 실패 미구분"
sed -n '/jl halt_env_failure/,/^fi$/p' "$LANE" | grep -q 'd\["status"\] = "pending"' && ok "환경 실패 → pending 유지(자동 재시도)" || ng "환경 실패 시 pending 미유지"
grep -q "pit_structural" "$VERIFY" && ok "PIT 구조 검사 존재" || ng "PIT 구조 검사 없음"
grep -q "in_progress" "$LANE" && ok "요청 상태 전이(pending→in_progress)" || ng "상태 전이 없음 — 중복 LLM 호출 위험"
grep -q "fidelity=adapted" "$LANE" && ok "변형구현 경로가 프롬프트에 존재" || ng "변형구현 경로 없음"
grep -q "_adapted_rulefast" "$VERIFY" && ok "adapted 귀속이 base_id 에 새겨짐" || ng "귀속 미구분"
grep -q "대리변수로 지어내지 마라" "$LANE" && ok "데이터 부재 → ABORT 유지(날조 차단)" || ng "데이터 부재 시 날조 허용 위험"
[ -f 06_Registry/replication_skiplist.json ] && grep -q "skiplist" 02_Infrastructure/ops/rf_next_paper_pick.py && ok "재현불가 논문 건너뛰기 배선" || ng "건너뛰기 없음"

echo "=== 8. LLM 모델·노력수준 — 실행기 경유 + D12 배정 ==="
if grep -q "rf_llm_agent_run " "$LANE" && sed -n '/^rf_llm_agent_run()/,/^}/p' 02_Infrastructure/ops/rf_llm_env.sh | grep -q -- '--model "\$LLM_MODEL" --effort "\$LLM_EFFORT"'; then
  ok "레인이 실행기(rf_llm_agent_run)를 부르고 실행기가 --model/--effort 를 싣는다"; else ng "model/effort 미지정"; fi
if "$PY" -c "
import io,json,sys
d=json.loads(io.open('06_Registry/reinforce_auto_config.json','rb').read().decode('utf-8'))
l=(d.get('llm') or {}).get('lanes') or {}
r=l.get('replication') or {}
sys.exit(0 if r.get('model')=='opus' and r.get('effort')=='max' else 1)"; then ok "replication 레인 = opus/max(D12 판단 역할)"; else ng "replication 레인 배정 불일치"; fi

echo "=== 9. 기저 신호 캐시 (셀 엔진) ==="
grep -q "rf_base_signal" 02_Infrastructure/reinforcement/rf_cell_engine.R && ok "기저 캐시 존재" || ng "기저 캐시 없음"
grep -q "md5sum" 02_Infrastructure/reinforcement/rf_cell_engine.R && ok "캐시 키에 엔진 내용 해시" || ng "내용 해시 없음"
grep -q "rawdata.parquet" 02_Infrastructure/reinforcement/rf_cell_engine.R && ok "캐시 키에 데이터 판본" || ng "데이터 판본 없음"
grep -q "캐시 저장 실패(비치명)" 02_Infrastructure/reinforcement/rf_cell_engine.R && ok "캐시 저장 실패 비치명 폴백" || ng "캐시 실패가 셀을 죽인다"

echo "=== 10. 기저 품질 문턱 · 이월은 공급기로 ==="
grep -q "base_below_threshold" "$VERIFY" && ok "기저 품질 문턱 존재" || ng "문턱 없음"
"$PY" -c "
import io,json,sys
d=json.loads(io.open('06_Registry/reinforce_auto_config.json','rb').read().decode('utf-8'))
sys.exit(0 if 'base_min_port_t' in d else 1)" && ok "설정에 base_min_port_t" || ng "설정 항목 없음"
sed -n '/base_below_threshold/,/quit(status = 0)/p' "$VERIFY" | grep -q "done_no_reinforce" && ok "미달 시에도 측정 기록 보존(done_no_reinforce)" || ng "미달 시 기록 소실"
sed -n '/base_below_threshold/,/quit(status = 0)/p' "$VERIFY" | grep -q "next_replication.R" && ok "미달 → 공급기(next_replication.R)로 다음 논문" || ng "미달 시 이월 없음"

echo "=== 11. 논문 소비 기록 · 프롬프트 백틱 ==="
grep -q "reinforce_ledger_l1" 02_Infrastructure/ops/rf_next_paper_pick.py && ok "선택기가 원장(L1)을 소비 기록으로 읽는다" || ng "원장 미참조 — 같은 논문 무한 재선택"
if "$PY" -c "
import io,json,subprocess,sys
led=json.loads(io.open('06_Registry/reinforce_ledger_l1.json','rb').read().decode('utf-8'))
done={str(e.get('paper_key')) for e in led['entries'] if e.get('paper_key')}
out=subprocess.run([sys.executable,'02_Infrastructure/ops/rf_next_paper_pick.py'],capture_output=True,text=True,encoding='utf-8').stdout
picked=set()
for l in out.split(chr(10)):
    l=l.strip()
    if not l: continue
    try: picked.add(str(json.loads(l).get('paper_key')))
    except Exception: pass
sys.exit(1 if (picked & done) else 0)"; then ok "원장 등재 논문이 후보에서 제외됨(양성 대조)"; else ng "원장 논문이 후보에 남아 있다"; fi
"$PY" 08_Tests/ops/check_prompt_backticks.py "$LANE" >/dev/null 2>&1 && ok "레인 프롬프트 미이스케이프 백틱 0" || ng "미이스케이프 백틱 — 명령 치환으로 프롬프트 절단"
_INJ="$T/bt_inject.sh"
"$PY" - "$LANE" "$_INJ" <<'PYINJ'
import io,sys
s=io.open(sys.argv[1],'rb').read().decode('utf-8'); BT=chr(96); BS=chr(92)
io.open(sys.argv[2],'wb').write(s.replace(BS+BT+'ABORT.txt'+BS+BT, BT+'ABORT.txt'+BT).encode('utf-8'))
PYINJ
"$PY" 08_Tests/ops/check_prompt_backticks.py "$_INJ" >/dev/null 2>&1 && ng "백틱 검사기 죽음 — 위반을 못 잡았다" || ok "백틱 위반 주입 적발(양성 대조)"

echo "=== 12. 충실구현 유한 재시도 (무인 종점에 사람 대기 금지) ==="
grep -q "PYRETRY" "$LANE" && ok "재시도 블록 배선" || ng "failed_needs_session 이 종점 — 루프가 죽는다"
if "$PY" - "$LANE" "$T" <<'PYT'
import io,json,os,re,subprocess,sys
src=io.open(sys.argv[1],"rb").read().decode("utf-8"); td=sys.argv[2]
m=re.search(r"<<'PYRETRY'\n(.*?)\nPYRETRY", src, re.S)
if not m: sys.exit(1)
tf=os.path.join(td,"rf_retry_blk.py"); io.open(tf,"wb").write(m.group(1).encode("utf-8"))
fx=os.path.join(td,"rf_req_fx.json"); cl=os.path.join(td,"rf_req_fx.claim")
def run(st,n,claim=False):
    io.open(fx,"wb").write(json.dumps({"status":st,"auto_retries":n,"paper":{"paper_key":"T.1"}}).encode("utf-8"))
    if claim: os.makedirs(cl,exist_ok=True)
    elif os.path.isdir(cl): os.rmdir(cl)
    rc=subprocess.run([sys.executable,tf,fx,cl],capture_output=True,text=True).returncode
    d=json.loads(io.open(fx,"rb").read().decode("utf-8"))
    return rc,d.get("status"),d.get("auto_retries")
ok=(run("failed_needs_session",0)==(0,"pending",1) and run("failed_needs_session",3)[0]==2 and run("pending",0)==(0,"pending",0)
    and run("done_no_reinforce",0)==(0,"done_no_reinforce",0) and run("in_progress",0)==(0,"pending",0)
    and run("in_progress",0,claim=True)==(0,"in_progress",0))
sys.exit(0 if ok else 1)
PYT
then ok "재시도 6경우(양성 대조 + 완료건 부활 금지 + in_progress 부활 양방향)"; else ng "재시도 로직 오작동"; fi
grep -q "retries_exhausted" "$LANE" && sed 's/#.*$//' "$LANE" | grep -q "programs/next_replication.R" && ok "3회 소진 → 스킵리스트 → 공급기 다음 논문" || ng "소진 후 이월 없음"

echo "=== 13. 성과 요약 · 팩터 분석 발송 ==="
[ -f 02_Infrastructure/ops/rf_perf_summary.R ] && ok "성과 요약 헬퍼 존재" || ng "헬퍼 없음"
grep -qE "06_metrics.csv|07_benchmark_compare.csv" 02_Infrastructure/ops/rf_perf_summary.R && ! grep -qE "sd\(|mean\(ret|cumprod|Return\.annualized" 02_Infrastructure/ops/rf_perf_summary.R \
  && ok "계약 산출물 읽기 전용(자체 계산 없음)" || ng "헬퍼가 성과를 자체 계산한다"
grep -q "run_analysis(.sim_fa" 02_Infrastructure/alpha_search/run_paper_replication.R && ok "FF3/FF5/Carhart + FMB 생산 배선" || ng "팩터 회귀 미생산"
## 2026-10-16 도훈 "파마맥베스 … 메세지 다시 살려줘" — [팩터 분석]은 보고 1통의 섹션(비중형 엔진은 사후 분석 · 점수 = 보유 비중)
VNC=$(sed 's/#.*$//' "$VERIFY")
printf '%s' "$VNC" | grep -q "replication_factor_analysis.R" && [ "$(printf '%s' "$VNC" | grep -c 'extra = c(.v1001_grade_extra(dirname(ar)), .v1001_variants_extra(), .v1001_factor_section(dirname(ar)))')" = "2" ] \
  && ok "[팩터 분석] · [논문 방법 N종](10-17) = 검증기 보고 1통의 섹션(성공 분기 2곳 · 사후 분석 배선)" || ng "팩터 분석 · 변형 섹션 미배선"
printf '%s' "$VNC" | grep -q 'jlog("factor_analysis"' && ok "분석 상태 기록(근거 · 상태 · 사유 · 소요)" || ng "분석 상태가 조용히 넘어간다"
! printf '%s' "$VNC" | grep -q "tg_pass_analysis" && ok "[팩터 분석] 별도 발송 없음(1단위 1통)" || ng "팩터 분석을 따로 또 보낸다"

echo "=== 14. v10.01 보고·인계 — 검증기가 행동 카드 · 프로그램 큐 · 발송기를 탄다 ==="
VC=$(sed 's/#.*$//' "$VERIFY")
printf '%s' "$VC" | grep -q "bc_card_from_artifacts" && ok "검증기가 행동 카드를 쓴다(bc_card_from_artifacts)" || ng "행동 카드 미배선"
printf '%s' "$VC" | grep -q "pr_enqueue" && ok "검증기가 엔진을 리서치 프로그램 큐에 넣는다(pr_enqueue)" || ng "프로그램 인계 미배선"
printf '%s' "$VC" | grep -q "prep_send" && ok "검증기 보고 = v10.01 발송기(prep_send)" || ng "발송기 미배선"
if printf '%s' "$VC" | grep -qE "rf_auto_notify|rf_block_insights|rf_grade_fanfare|reinforce_auto_next_paper"; then ng "검증기가 퇴역 발송기·이월을 부른다"
else ok "검증기 실행 코드에 퇴역 발송기·이월 호출 0"; fi

echo "=== 15. 충실구현 claim — 죽은 소유자를 회수하는가 (정적) ==="
grep -q 'echo \$\$ > "\$CLAIM/owner"' "$LANE" && ok "claim 이 owner pid 를 남긴다" || ng "owner pid 미기록"
grep -q 'kill -0 "\$COWN"' "$LANE" && ok "pid 사망 시 즉시 회수" || ng "나이 기준만 본다"

echo "=== 16. 텔레그램 '보냈다' 가 실제 발송인가 ==="
if sed 's/#.*$//' 02_Infrastructure/telegram/telegram_notify.R | grep -qE "^[[:space:]]*tg_send_rich\("; then
  ng "tg_agent_brief 가 발송 반환값을 버린다" "단독 호출 — 실패가 성공으로 기록된다"; else ok "tg_agent_brief 가 발송 반환값을 읽는다"; fi
printf '  tg_send_rich(msg, emoji_min = emoji_min)\n' > "$T/send_probe.R"
sed 's/#.*$//' "$T/send_probe.R" | grep -qE "^[[:space:]]*tg_send_rich\(" && ok "발송 반환값 검사기 양성 대조 발화" || ng "검사기 미발화"

echo "=== 17. 레인 스위치 분리 + 고아 claim 회수 순서 (격리 실행 · 양방향) ==="
# 레인을 실제로 돌린다 — 요청·claim·로그·config 전부 격리 경로(QVEST_RP_* · QVEST_RF_CONFIG). 공유 상태 무접촉.
_RPD="$T/rp"; mkdir -p "$_RPD"; : > "$_RPD/jlog.jsonl"
_mkreq(){ printf '%s\n' "{\"requested_at\":\"2026-01-01T00:00:00+0900\",\"source\":\"test\",\"paper\":{\"title\":\"t\",\"paper_title\":\"t\",\"url\":\"\",\"paper_key\":\"TEST\",\"source\":\"arxiv\"},\"status\":\"$1\",\"started_at\":\"2026-01-01T00:00:00+0900\"}" > "$_RPD/req.json"; }
# $1 = 전역 enabled(퇴역 러너) · $2 = replication_lane.enabled · _RP_STALE = claim_stale_hours 덮기
_mkcfg(){ "$PY" -c "import io,json,os,sys;src=os.path.join(os.environ['QM_ROOT'] if os.environ.get('QM_ROOT') else '.','06_Registry','reinforce_auto_config.json');d=json.loads(io.open(src,'rb').read().decode('utf-8'));d['enabled']=(sys.argv[1]=='1');d['replication_lane']={'enabled':sys.argv[2]=='1'};s=os.environ.get('_RP_STALE','');d.update({'claim_stale_hours':int(s)} if s else {});io.open(r'$_RPD/config.json','w',encoding='utf-8',newline='').write(json.dumps(d,ensure_ascii=False))" "$1" "$2"; }
# 갱신 잠금도 격리 경로로(10-17) — 밤 갱신이 실제 잠금을 잡은 동안 C1 · C4 가 halt_refresh_lock 으로 빨개졌다(운영 상태 차용)
_rprun(){ QVEST_RP_REQUEST="$_RPD/req.json" QVEST_RP_CLAIM="$_RPD/claim" QVEST_RP_JLOG="$_RPD/jlog.jsonl" QVEST_RF_CONFIG="$_RPD/config.json" \
          QM_REFRESH_LOCKDIR="$_RPD/refresh.lock" QM_RAWDATA_WRITER_LOCKDIR="$_RPD/writer.lock" \
          bash "$LANE" >/dev/null 2>&1; }
_st(){ "$PY" -c "
import io,json
print(json.loads(io.open(r'$_RPD/req.json','rb').read().decode('utf-8')).get('status'))" 2>/dev/null; }
_ev(){ grep -o '"event": *"[a-z_]*"' "$_RPD/jlog.jsonl" | sed 's/.*"\([a-z_]*\)"$/\1/' | tr '\n' ' '; }
# (S1) 위반 주입: 레인 스위치 off → 전역이 켜져 있어도 halt_disabled
: > "$_RPD/jlog.jsonl"; _mkreq done; _mkcfg 1 0; _rprun
grep -q '"halt_disabled"' "$_RPD/jlog.jsonl" && ok "S1 replication_lane.enabled=false → halt_disabled(전역 enabled=true 여도)" || ng "S1 레인 스위치 무시" "$(_ev)"
# (S2) 양성 대조: 퇴역 러너 스위치 off + 레인 on → 게이트 통과(halt_disabled 아님 · 요청 종결이라 no_pending_request)
: > "$_RPD/jlog.jsonl"; _mkreq done; _mkcfg 0 1; _rprun
if ! grep -q '"halt_disabled"' "$_RPD/jlog.jsonl" && grep -qE '"(no_pending_request|halt_refresh_lock)"' "$_RPD/jlog.jsonl"; then
  ok "S2 전역 enabled=false(퇴역 러너) · 레인 on → 게이트 통과(러너 퇴역이 레인을 세우지 않는다)"; else ng "S2 레인이 퇴역 러너 스위치에 묶였다" "$(_ev)"; fi
# (C1) 위반 상태 주입: 죽은 소유자 claim + in_progress → 회수 + 되살리기
: > "$_RPD/jlog.jsonl"; _mkreq in_progress; mkdir -p "$_RPD/claim"; echo 999999 > "$_RPD/claim/owner"; _mkcfg 0 1; _rprun
[ "$(_st)" = "pending" ] && grep -q claim_stale_reclaim "$_RPD/jlog.jsonl" && ok "C1 고아 claim 회수 — 죽은 소유자 + in_progress → pending" || ng "C1 고아 claim 회수" "status=$(_st) $(_ev)"
# (C2) 양성 대조: 살아있는 소유자 claim 은 회수하지 않는다
: > "$_RPD/jlog.jsonl"; rm -rf "$_RPD/claim"; _mkreq in_progress; mkdir -p "$_RPD/claim"; echo $$ > "$_RPD/claim/owner"; _mkcfg 0 1; _rprun
[ "$(_st)" = "in_progress" ] && [ -d "$_RPD/claim" ] && ok "C2 동시 실행 방지선 — 살아있는 소유자 claim 유지" || ng "C2 살아있는 claim 을 빼앗았다" "status=$(_st)"
_mkclaim_aged(){ rm -rf "$_RPD/claim"; mkdir -p "$_RPD/claim"; echo $$ > "$_RPD/claim/owner"
                 cat /proc/$$/winpid > "$_RPD/claim/owner_win" 2>/dev/null; touch -d "$1 hours ago" "$_RPD/claim"; }
# (C3) 위반 주입: 살아있는 소유자 + 나이 3h < stale 6h → 회수 금지
: > "$_RPD/jlog.jsonl"; _mkreq in_progress; _mkclaim_aged 3; export _RP_STALE=6; _mkcfg 0 1; _rprun; unset _RP_STALE
[ "$(_st)" = "in_progress" ] && [ -d "$_RPD/claim" ] && ! grep -q claim_stale_reclaim "$_RPD/jlog.jsonl" && ok "C3 생존 소유자 3h claim 유지(stale 6h 전)" || ng "C3 3h 생존 claim 을 빼앗았다" "status=$(_st)"
# (C4) 10-17 도훈 '논문당 계산 시간 상한 없음' — 생존 소유자는 나이 ≥ stale 이어도 회수하지 않고 claim_live_long 만 남긴다
: > "$_RPD/jlog.jsonl"; _mkreq in_progress; _mkclaim_aged 7; export _RP_STALE=6; _mkcfg 0 1; _rprun; unset _RP_STALE
[ "$(_st)" = "in_progress" ] && [ -d "$_RPD/claim" ] && grep -q claim_live_long "$_RPD/jlog.jsonl" && ! grep -q claim_stale_reclaim "$_RPD/jlog.jsonl" \
  && ok "C4 7h ≥ 6h 생존 claim 유지 + claim_live_long 경고(계산 시간 상한 없음 · 10-17)" || ng "C4 생존 claim 처리" "status=$(_st) $(_ev)"
# (C4b) 양성 대조: 설정 live_claim_reclaim=true(격리 사본 · QVEST_RP_VARIANTS_CFG) 면 구판 그대로 회수(alive=1 표식) — 배선이 설정을 읽는다
"$PY" -c "import io,json,os;src=os.path.join(os.environ.get('QM_ROOT') or '.','06_Registry','rf_replication_variants.json');d=json.loads(io.open(src,'rb').read().decode('utf-8'));d['compute']['live_claim_reclaim']=True;io.open(r'$_RPD/variants_cfg.json','w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))"
: > "$_RPD/jlog.jsonl"; _mkreq in_progress; _mkclaim_aged 7; export _RP_STALE=6; _mkcfg 0 1
QVEST_RP_VARIANTS_CFG="$_RPD/variants_cfg.json" _rprun; unset _RP_STALE
[ "$(_st)" = "pending" ] && grep -q '"stale_h": "6"' "$_RPD/jlog.jsonl" && grep -q '"alive": "1"' "$_RPD/jlog.jsonl" \
  && ok "C4b 설정 live_claim_reclaim=true → 7h 생존 claim 회수(구판 동작 · alive=1)" || ng "C4b 설정 미배선" "status=$(_st) $(_ev)"
# (C4c) 소유자 표식이 없는 구판 claim 은 생존을 알 수 없다 → 나이 ≥ stale 이면 회수(구판 그대로)
: > "$_RPD/jlog.jsonl"; _mkreq in_progress; rm -rf "$_RPD/claim"; mkdir -p "$_RPD/claim"; touch -d "7 hours ago" "$_RPD/claim"; export _RP_STALE=6; _mkcfg 0 1; _rprun; unset _RP_STALE
[ "$(_st)" = "pending" ] && grep -q claim_stale_reclaim "$_RPD/jlog.jsonl" && ok "C4c 소유자 표식 없는 7h claim 회수(나이 기준)" || ng "C4c 구판 claim" "status=$(_st) $(_ev)"
# (C5) 구현 에이전트 시간 상한 = 설정 변수(구판 3000 리터럴 0곳 · 기본 0 = 상한 없음)
LNC=$(sed 's/#.*$//' "$LANE")
[ "$(printf '%s' "$LNC" | grep -c 'rf_llm_agent_run "$PF" "$RUN_OUT" "$RP_AGENT_TMO"')" = "2" ] && ! printf '%s' "$LNC" | grep -q 'rf_llm_agent_run "$PF" "$RUN_OUT" 3000' \
  && grep -q '"agent_timeout_sec": 0' 06_Registry/rf_replication_variants.json && ok "C5 구현 에이전트 시간 상한 = 설정(0 = 상한 없음 · 호출 2곳)" || ng "C5 시간 상한 배선"
# (R0) 양성 대조: 격리 잠금 경로가 실제로 읽힌다 — 방금 만든 빈 잠금 디렉터리(held:empty_pid) → halt_refresh_lock
#      요청은 done 으로 둔다(잠금이 무시되면 no_pending_request 로 끝난다 — 에이전트를 띄우지 않는다)
: > "$_RPD/jlog.jsonl"; rm -rf "$_RPD/claim"; _mkreq done; mkdir -p "$_RPD/refresh.lock"; _mkcfg 0 1; _rprun; rm -rf "$_RPD/refresh.lock"
grep -q '"halt_refresh_lock"' "$_RPD/jlog.jsonl" && ok "R0 갱신 잠금 격리 경로가 읽힌다(빈 잠금 → halt_refresh_lock) — C1 · C4 초록은 격리 덕이다" || ng "R0 격리 잠금 경로 미배선" "$(_ev)"

echo "=== 18. 기각 → 즉시 재구현 연쇄 (2026-10-17 · 함수 격리 실행 · 양방향 + 뮤테이션) ==="
# 레인의 rp_chain_reimplement 정의를 떼어 격리 셸에서 돌린다 — exec 대상 = 기록용 대역(RP_CHAIN_SELF). 운영 요청·claim 무접촉.
_CH="$T/chain"; mkdir -p "$_CH"
"$PY" - "$LANE" "$_CH/fn.sh" <<'PYCH'
import io, re, sys
s = io.open(sys.argv[1], "rb").read().decode("utf-8")
m = re.search(r"^rp_chain_reimplement\(\) \{\n.*?^\}\n", s, re.S | re.M)
io.open(sys.argv[2], "wb").write((m.group(0) if m else "").encode("utf-8"))
PYCH
printf '%s\n' '#!/usr/bin/env bash' 'echo "exec depth=${RP_CHAIN_DEPTH:-} claim_gone=$([ -d "$CLAIM_PATH" ] && echo 0 || echo 1)" > "$CHAIN_REC"' > "$_CH/stub.sh"
# $1 함수 파일 · $2 rc · $3 요청 status · $4 요청 key · $5 P_KEY · $6 RP_CHAIN_DEPTH
_chrun(){ rm -f "$_CH/rec"; : > "$_CH/j.log"; mkdir -p "$_CH/claim"
  printf '{"status":"%s","paper":{"paper_key":"%s"}}' "$3" "$4" > "$_CH/req.json"
  ( REQ="$_CH/req.json"; CLAIM="$_CH/claim"; P_KEY="$5"
    jl(){ echo "$1" >> "$_CH/j.log"; }
    export CHAIN_REC="$_CH/rec" CLAIM_PATH="$_CH/claim" RP_CHAIN_SELF="$_CH/stub.sh" RP_CHAIN_DEPTH="$6"
    . "$1"; rp_chain_reimplement "$2"; echo returned >> "$_CH/j.log" ) >/dev/null 2>&1; }
if [ -s "$_CH/fn.sh" ]; then
  _chrun "$_CH/fn.sh" 0 pending TEST TEST ""
  grep -q "exec depth=1 claim_gone=1" "$_CH/rec" 2>/dev/null && grep -q reimplement_chain "$_CH/j.log" && ! grep -q returned "$_CH/j.log" \
    && ok "K1 같은 논문 pending + rc 0 → claim 반납 후 레인 재실행(exec · 깊이 1)" || ng "K1 연쇄 미발화" "$(cat "$_CH/rec" 2>/dev/null) $(tr '\n' ' ' < "$_CH/j.log")"
  _chrun "$_CH/fn.sh" 1 pending TEST TEST ""
  [ ! -f "$_CH/rec" ] && [ -d "$_CH/claim" ] && grep -q returned "$_CH/j.log" && ok "K2 rc ≠ 0(검증 실패 · 리프레시 연기) → 잇지 않는다" || ng "K2 실패에도 연쇄"
  _chrun "$_CH/fn.sh" 0 pending OTHER TEST ""
  [ ! -f "$_CH/rec" ] && grep -q returned "$_CH/j.log" && ok "K3 다음 논문 pending(키 다름 · 소비 뒤 공급기 발행) → 잇지 않는다(재구현만 잇는다)" || ng "K3 다른 논문으로 연쇄"
  _chrun "$_CH/fn.sh" 0 done_no_reinforce TEST TEST ""
  [ ! -f "$_CH/rec" ] && grep -q returned "$_CH/j.log" && ok "K4 pending 아님(소비 · 보류) → 잇지 않는다" || ng "K4 종결 요청으로 연쇄"
  _chrun "$_CH/fn.sh" 0 pending TEST TEST 3
  [ ! -f "$_CH/rec" ] && grep -q reimplement_chain_cap "$_CH/j.log" && grep -q returned "$_CH/j.log" && ok "K5 연쇄 상한(깊이 3) → 멈추고 기록(reimplement_chain_cap · 다음 tick 이 잇는다)" || ng "K5 상한 무시"
  sed 's/\[ "\$nxt" = "pending|\$P_KEY" \]/true/' "$_CH/fn.sh" > "$_CH/fn_mut.sh"
  if ! cmp -s "$_CH/fn.sh" "$_CH/fn_mut.sh"; then
    _chrun "$_CH/fn_mut.sh" 0 pending OTHER TEST ""
    [ -f "$_CH/rec" ] && ok "K6 뮤테이션(같은 논문 조건 제거)판은 다른 논문으로 연쇄 → K3 가 잡는다(검출력)" || ng "K6 뮤테이션이 탐지되지 않는다"
  else ng "K6 뮤테이션 치환 불발(소스 텍스트)"; fi
else ng "K0 레인에 rp_chain_reimplement 정의가 없다"; fi
LNC=$(sed 's/#.*$//' "$LANE")
[ "$(printf '%s' "$LNC" | grep -c 'rp_chain_reimplement "\$VRC"')" = "2" ] && printf '%s' "$LNC" | grep -q 'rp_chain_reimplement 0' \
  && ok "K7 연쇄 배선 = 검증 2곳(verify-only 재실행 · 정상 끝) + 사전검사 기각 1곳" || ng "K7 연쇄 배선 누락"

echo "=== 19. 구현자 = 감사자와 같은 원문 · 같은 축 (2026-10-17 · 원문 전문 경로 + 제출 전 자가 감사) ==="
_AXL=$(grep -E '^P_AXID=' "$LANE")
_axid(){ ( P_URL="$1"; eval "$_AXL"; printf '%s' "$P_AXID" ); }
[ -n "$_AXL" ] && [ "$(_axid https://arxiv.org/abs/1908.01112)" = "1908.01112" ] && [ "$(_axid https://arxiv.org/abs/2411.08864v2)" = "2411.08864" ] \
  && [ -z "$(_axid https://papers.ssrn.com/sol3/papers.cfm?abstract_id=1)" ] \
  && ok "J1 원문 전문 id 추출 — abs · 판 접미사 제거 · arXiv 아님 = 빈 값" || ng "J1 전문 id 추출" "$(_axid https://arxiv.org/abs/2411.08864v2)"
printf '%s' "$LNC" | grep -q 'https://arxiv.org/html/${P_AXID}v1' && grep -q '^\${P_TEXTLINE}$' "$LANE" && grep -q '^\${P_ACCESS}$' "$LANE" && grep -q '^\${SELF_AUDIT_SEC}$' "$LANE" \
  && ok "J2 프롬프트 = 원문 줄(축자본 · 없으면 전문 주소) + 읽는 법 + 자가 감사 절(축 정본 생성) 배선" || ng "J2 프롬프트 배선 누락"
printf '%s' "$LNC" | grep -q 'rf_preaudit.py" --self-audit-block' && printf '%s' "$LNC" | grep -q 'jl self_audit_block_absent' \
  && ok "J3 자가 감사 절 = rf_preaudit.py --self-audit-block(사본 없음) · 생성 실패는 저널" || ng "J3 절 생성 배선"
_sa_line=$(grep -n '^\${SELF_AUDIT_SEC}$' "$LANE" | head -1 | cut -d: -f1); _out_line=$(grep -n '^## 산출 (이것만)$' "$LANE" | head -1 | cut -d: -f1)
[ -n "$_sa_line" ] && [ -n "$_out_line" ] && [ "$_sa_line" -lt "$_out_line" ] && [ "$(grep -c '^## 산출 (이것만)$' "$LANE")" = "1" ] \
  && ok "J4 자가 감사 절이 산출 절 앞(결합 꼬리에는 안 실린다) · 산출 머리 1개" || ng "J4 절 위치" "sa=$_sa_line out=$_out_line"
# J5~J7 — 원문 축자본 선수집(10-17 · 1차 기각 원인 1위 '전문 미열람' 32% · WebFetch = 요약기)
_mk=$(grep -n '^mkdir -p "\$WDIR"$' "$LANE" | head -1 | cut -d: -f1); _pt=$(grep -n 'rf_paper_text.py" --url "\$P_URL" --wdir "\$WDIR"' "$LANE" | head -1 | cut -d: -f1)
_pv=$(grep -n '^PREV_FAIL=' "$LANE" | head -1 | cut -d: -f1)
[ -n "$_mk" ] && [ -n "$_pt" ] && [ -n "$_pv" ] && [ "$_mk" -lt "$_pt" ] && [ "$_pt" -lt "$_pv" ] && printf '%s' "$LNC" | grep -q 'jl paper_text' \
  && ok "J5 축자본 선수집 = 작업 디렉터리 직후 · 검증기만 재실행 경로보다 앞(두 경로가 같은 파일) · 저널 paper_text" || ng "J5 선수집 배선" "mk=$_mk pt=$_pt pv=$_pv"
! grep -q 'PDF 를 받았으면 Read' "$LANE" && grep -q '미확인 재현' "$LANE" && printf '%s' "$LNC" | grep -q 'download_paper → read_paper' \
  && ok "J6 잘못된 PDF-Read 안내 제거(pdftoppm 부재) · 위임 사양 규칙 · 대체 경로 = arxiv MCP 끝까지" || ng "J6 원문 접근 문구"
_PB="$T/prompt_block.sh"; _a=$(grep -n '^P_AXID=' "$LANE" | head -1 | cut -d: -f1); _b=$(grep -n '^엔진을 쓰고 1~2줄로 무엇을 구현했는지만 보고하라."$' "$LANE" | head -1 | cut -d: -f1)
if [ -n "$_a" ] && [ -n "$_b" ]; then
  sed -n "${_a},${_b}p" "$LANE" > "$_PB"
  _render(){ ( ROOT="$ROOT"; LOG="$T/pb.log"; IS_COMBO=0; P_KEY=T1; P_URL=https://arxiv.org/abs/1908.01112; P_TITLE=t; P_FNAME=x; P_FDEF=y; WDIR=W
               jl(){ :; }; P_TEXT_OK="$1"; PT_OUT="$2"; . "$_PB"; printf '%s' "$PROMPT" ) 2>/dev/null; }
  _r1=$(_render 1 "ok kind=html version=v1 chars=45234 path=.clean_paper/paper.md cached=0"); _r0=$(_render 0 "fail why=x")
  printf '%s' "$_r1" | grep -q '^원문 축자본: W/.clean_paper/paper.md' && ! printf '%s' "$_r1" | grep -q '^원문 전문: ' \
    && printf '%s' "$_r0" | grep -q '^원문 전문: https://arxiv.org/html/1908.01112v1' && printf '%s' "$_r0" | grep -q 'arxiv MCP 로 전문을 끝까지' \
    && ok "J7 렌더 양방향 — 축자본 있음 = 축자본 줄(주소 줄 없음) · 없음 = 전문 주소 + arxiv MCP 대체 지시" || ng "J7 렌더" "$(printf '%s' "$_r1" | sed -n '4,6p')"
else ng "J7 프롬프트 블록 경계 없음"; fi

echo
printf '합계: 통과 %d · 실패 %d\n' "$PASS" "$FAIL"
printf '{"test":"replication_lane","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
