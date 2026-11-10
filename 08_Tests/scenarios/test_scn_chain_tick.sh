#!/usr/bin/env bash
# test_scn_chain_tick.sh — 강화 사슬 무인 틱(02_Infrastructure/ops/chain_tick.sh) 셸 오케스트레이션 시나리오 (2026-11-10)
#   격리: 임시 루트(저장소 밖 mktemp) · 가짜 round.sh(CT_RS · 호출 기록) · 가짜 계획기(CT_HELPER · 시나리오 상태 파일) · 가짜 생성기(CT_GEN) · 가짜 배리어(RB_SH)
#   실제 측정 · LLM · 텔레그램 0(QVEST_NO_ALERT=1 · 마커만) · 운영 등록부 · 원장 · .cache 무접촉(전후 md5 단정)
#   단정: 허용 목록(등록 · 닫기 · 새 판 · 격리를 부르지 않는다) · 배리어 · 스위치 · 설정 판독 불가 · 신선도 앞세움 · 생성 실패 상한 · 경합 · 닫기 대기 1회 ·
#         잠금 · 한도 물러남 · 가드 탐침 · 포기 · 틱당 측정 상한 · 드라이런 · 리셋 + 돌연변이(소스 텍스트 치환 · 치환 성사 단정)
# 실행: bash 08_Tests/scenarios/test_scn_chain_tick.sh   (대상 = CT_UNDER_TEST 또는 저장소 02_Infrastructure/ops/chain_tick.sh)
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${CT_TEST_REPO:-$(cd "$SELF_DIR/../.." && pwd)}"
TICK_SRC="${CT_UNDER_TEST:-$REPO/02_Infrastructure/ops/chain_tick.sh}"
SH="${BASH:-bash}"; PY="${QVEST_PY:-python}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: ${2:-}"; }
chk(){ if [ "$2" = "0" ]; then ok "$1"; else ng "$1" "${3:-}"; fi; }
[ -f "$TICK_SRC" ] || { echo "대상 없음: $TICK_SRC"; printf '{"test":"scn_chain_tick","pass":0,"fail":1,"total":1}\n'; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
case "$(cd "$T" && pwd -W 2>/dev/null || pwd)" in "$(cd "$REPO" && pwd -W 2>/dev/null || pwd)"*) echo "임시 루트가 저장소 안"; exit 1 ;; esac
OPSF=("06_Registry/research_programs.json" "06_Registry/round_outcomes.jsonl" "06_Registry/rx_generator.json")
md5_ops(){ for f in "${OPSF[@]}"; do [ -f "$REPO/$f" ] && md5sum "$REPO/$f" | cut -c1-32 || echo absent; done; ls -1 "$REPO/.cache/chain_tick" 2>/dev/null | wc -l; [ -d "$REPO/.cache/chain_tick.lock" ] && echo lock || echo nolock; }
OPS0="$(md5_ops)"

# ── 가짜 부품 ────────────────────────────────────────────────────────────────
mkdir -p "$T/bin"
cat > "$T/bin/round.sh" <<'EOF'
#!/usr/bin/env bash
cd_="$1"; st="$2"; shift 2; cid=$(basename "$cd_")
echo "$cid $st $*" >> "$SCN/calls.log"
if [ "$st" = "p4-workdir" ]; then w=""; while [ $# -gt 0 ]; do [ "$1" = "--out" ] && w="$2"; shift; done
  mkdir -p "$w"; for f in design_input.md investment_philosophy_charter.md toolbox.md parent_cell_spec.json; do echo x > "$w/$f"; done; fi
rc=0; [ -f "$SCN/rc.$st" ] && rc=$(cat "$SCN/rc.$st"); [ -f "$SCN/rc.$cid.$st" ] && rc=$(cat "$SCN/rc.$cid.$st")
[ -f "$SCN/out.$st" ] && cat "$SCN/out.$st"
[ "$rc" = "0" ] && [ -f "$SCN/next.$cid.$st" ] && cp "$SCN/next.$cid.$st" "$SCN/plan.$cid"
exit "$rc"
EOF
cat > "$T/bin/helper.sh" <<'EOF'
#!/usr/bin/env bash
c="$1"; shift
case "$c" in
  config) [ -f "$SCN/config_bad" ] && { echo "config_unreadable"; exit 2; }
          case "$1" in enabled) cat "$SCN/enabled" 2>/dev/null || echo true ;; measures_per_tick) echo "${MPT:-1}" ;; lanes_dir) echo "04_Research/programs/P4_ASSEMBLY/_lanes" ;; *) echo 1 ;; esac ;;
  plan) cid=$(basename "$1"); p=$(cat "$SCN/plan.$cid" 2>/dev/null || printf 'skip\t-\tclosed\t-')
        case "$p" in open*) [ -f "$SCN/genblocked.$cid" ] && p=$(printf 'blocked\t1\tgen_failures\t-') ;; esac; printf '%s\n' "$p" ;;
  list) for f in "$SCN"/plan.*; do printf '%s\t%s\t-\n' "${f##*plan.}" "$(cat "$f")"; done; echo "LISTED" >> "$SCN/helper.log" ;;
  record) cid="$1"; ev="$2"; v="${3:-}"
    case "$ev" in
      served) n=$(cat "$SCN/clock" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$SCN/clock"; printf '%05d\n' "$n" > "$SCN/served.$cid" ;;
      mark) if grep -qxF "$v" "$SCN/marks.$cid" 2>/dev/null; then echo seen; else echo "$v" >> "$SCN/marks.$cid"; echo new; fi ;;
      mark_daily) v="$v@${CT_DAY:-d1}"; if grep -qxF "$v" "$SCN/marks.$cid" 2>/dev/null; then echo seen; else echo "$v" >> "$SCN/marks.$cid"; echo new; fi ;;
      gen_ok) rm -f "$SCN/genfail.$cid" ;;
      gen_fail) n=$(cat "$SCN/genfail.$cid" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$SCN/genfail.$cid"
                if [ "$n" -ge 2 ]; then touch "$SCN/genblocked.$cid"; echo blocked; else echo "count=$n"; fi ;;
      decide_ok) : ;; decide_error) echo "count=1" ;;
    esac ;;
  state) cat "$SCN/served.$1" 2>/dev/null || echo "" ;;
  backoff-set) echo "${CT_DAY:-d1}" > "$SCN/backoff"; echo "next-day" ;;
  backoff-active) [ -f "$SCN/backoff" ] && [ "$(cat "$SCN/backoff")" = "${CT_DAY:-d1}" ] && echo yes || echo no ;;
  abandon-reason) echo "정본 셀 워커 측정이 반복해 실패했다 — 무인 틱이 포기를 기록한다(가설 기각 아님)" ;;
  prompt) echo ok ;;
  compile) [ -f "$SCN/compile_reject" ] && { echo "reject $(cat "$SCN/compile_reject")"; exit 10; }
           w="$2"; mkdir -p "$w/open"; echo "$3" > "$w/open/k.txt"; echo "가설" > "$w/open/hypothesis.txt"; echo "기전" > "$w/open/mechanism.txt"
           echo weighting > "$w/open/block.txt"; echo "$1/cells/k$3.json" > "$w/open/cell.txt"; echo 0 > "$w/open/parent.txt"; echo g1 > "$w/open/generator.txt"
           mkdir -p "$RC_ROOT_POSIX/$1/cells"; echo '{}' > "$RC_ROOT_POSIX/$1/cells/k$3.json"
           [ -f "$SCN/compile_hold" ] && printf 'skip\t-\theld_by_session\td\n' > "$SCN/plan.$(basename "$1")"
           echo "ok $1/cells/k$3.json" ;;
  notify) cid=$(basename "$1"); [ -f "$SCN/notify_fail" ] && { echo "notify 실패: 발송 결과 ok 아님"; echo failed; exit 1; }; if grep -qxF "close_wait:$3" "$SCN/marks.$cid" 2>/dev/null; then echo seen; else echo "close_wait:$3" >> "$SCN/marks.$cid"; echo "$cid $3" >> "$SCN/notify.log"; echo sent; fi ;;
  reset) rm -f "$SCN/genblocked.$1" "$SCN/genfail.$1"; echo "reset $1" ;;
  *) exit 2 ;;
esac
exit 0
EOF
cat > "$T/bin/gen.sh" <<'EOF'
#!/usr/bin/env bash
echo "$(basename "${2:-?}") GEN $1" >> "$SCN/calls.log"
[ -f "$SCN/gen_skip" ] && exit 0                                    # 실제 생성기: 다른 인스턴스 잠금 = 산출 없이 0
echo out > "$1/out.md"; echo prompt > "$1/prompt.md"; echo '{"rc":0,"reason":"ok","model":"fake"}' > "$1/gen_result.json"
[ -f "$SCN/gen_hold" ] && printf 'skip\t-\theld_by_session\td\n' > "$SCN/plan.$(basename "${2:-?}")"     # 생성 도중 세션이 tick_hold
exit "$(cat "$SCN/gen_rc" 2>/dev/null || echo 0)"
EOF
cat > "$T/bin/rb.sh" <<'EOF'
#!/usr/bin/env bash
if [ -f "$SCN/barrier_held" ]; then printf 'RB\tstate=held\n'; exit 10; fi
printf 'RB\tstate=free\n'; exit 0
EOF

N=0
new(){ # 새 시나리오 — 임시 루트 + 사슬(이름들 · 등록됨) → SCN · R 설정
  N=$((N+1)); R="$T/r$N"; SCN="$T/s$N"; mkdir -p "$R" "$SCN"; RW="$(cd "$R" && pwd -W 2>/dev/null || pwd)"
  for c in "$@"; do local d="$R/04_Research/programs/P4_ASSEMBLY/$c"; mkdir -p "$d"; echo '{}' > "$d/chain_spec.json"
    printf '{"schema":"rc_p4_chain_steps_v1","at":"x","prev":"genesis","event":"chain_registered","chain_id":"%s"}\n' "$c" > "$d/chain_steps.jsonl"; done
  export SCN
}
setp(){ printf '%s\t%s\t%s\t%s\n' "$2" "$3" "${4:--}" "${5:-d}" > "$SCN/${6:-plan}.$1"; }       # setp <cid> ACTION k reason detail [plan|next.<cid>.<stage> 접두]
nextp(){ printf '%s\t%s\t%s\t%s\n' "$3" "$4" "${5:--}" d > "$SCN/next.$1.$2"; }                # nextp <cid> <stage> ACTION k [reason]
tick(){ # [인자] — 대상 = $TK
  ( cd "$R" && env RC_ROOT_POSIX="$R" RC_ROOT_WIN="$RW" CT_RS="$T/bin/round.sh" CT_HELPER="$T/bin/helper.sh" CT_RSCRIPT="$SH" CT_GEN="$T/bin/gen.sh" \
      RB_SH="$T/bin/rb.sh" SCN="$SCN" QVEST_NO_ALERT=1 QVEST_TG_DRY_RUN=1 QVEST_UNATTENDED=0 "$SH" "$TK" "$@" ) > "$SCN/out.txt" 2>&1
  echo $? > "$SCN/rc.txt"
}
calls(){ cat "$SCN/calls.log" 2>/dev/null; }
ncall(){ calls | grep -cE "$1"; }
marker(){ ls "$R/.cache/scheduler_alerts/" 2>/dev/null | grep -c "^chain_tick_$1"; }
FORBID=' (p4-register|p4-close|p4-quarantine|p4-generator-review|outcomes-quarantine|register|close|reviewed|draft) '

mk_tick(){ mkdir -p "$T/$1"; cp "$TICK_SRC" "$T/$1/chain_tick.sh"; cp "$REPO/02_Infrastructure/ops/_sched_failure_classify.sh" "$T/$1/"; echo "$T/$1/chain_tick.sh"; }
mutate(){ "$PY" -c 'import sys,io;p,a,b=sys.argv[1:4];s=io.open(p,encoding="utf-8").read();n=s.count(a);io.open(p,"w",encoding="utf-8",newline="").write(s.replace(a,b));print(n)' "$1" "$2" "$3"; }

## 시나리오 — 각 함수 = 0(기대대로) | 1
s_T2(){ new A; setp A measure_base 0; echo false > "$SCN/enabled"; tick; [ ! -s "$SCN/out.txt" ] && [ "$(cat "$SCN/rc.txt")" = 0 ] && [ "$(ncall .)" = 0 ]; }
s_T7(){ new A; setp A decide 1; touch "$SCN/barrier_held"; tick; [ "$(ncall 'p4-step-decide|measure|p4-workdir|GEN')" = 0 ] && grep -q '배리어' "$SCN/out.txt"; }
s_T8(){ new A; setp A open 1; echo 6 > "$SCN/rc.fresh-check"; tick; [ "$(ncall 'fresh-check')" = 1 ] && [ "$(ncall 'GEN|p4-workdir|p4-step-open')" = 0 ]; }
s_T13(){ new A; setp A close 1; tick; [ "$(ncall 'p4-close')" = 0 ] && [ "$(marker forbidden_stage)" = 1 ] && [ "$(cat "$SCN/rc.txt")" = 1 ]; }
s_T16(){ new A; setp A open 1; echo 3 > "$SCN/gen_rc"; tick; local g1; g1=$(ncall GEN)
  [ "$g1" = 1 ] && [ -f "$SCN/backoff" ] && [ "$(marker llm_limit)" = 1 ] && [ ! -f "$SCN/genfail.A" ] || return 1
  rm -f "$SCN/gen_rc"; : > "$SCN/calls.log"; tick; [ "$(ncall GEN)" = 0 ] || return 1                 # 같은 날 = 생성 안 함
  setp A measure_step 1; : > "$SCN/calls.log"; tick; [ "$(ncall p4-step-measure)" = 1 ] || return 1     # 측정은 계속
  setp A open 2; : > "$SCN/calls.log"; ( export CT_DAY=d2; tick ); [ "$(ncall GEN)" = 1 ]; }             # 다음 날 = 재개
s_T20(){ new A B; setp A measure_step 1; setp B measure_step 1; tick; local a1 b1; a1=$(ncall '^A p4-step-measure'); b1=$(ncall '^B p4-step-measure')
  [ $((a1 + b1)) = 1 ] || return 1; tick; [ "$(ncall '^A p4-step-measure')" = 1 ] && [ "$(ncall '^B p4-step-measure')" = 1 ]; }
s_T20c(){ new A; setp A measure_step 1; export MPT=0; tick; local a; a=$(ncall p4-step-measure); setp A open 1; tick; unset MPT; [ "$a" = 0 ] && [ "$(ncall GEN)" = 0 ]; }
lanes_n(){ ls -d "$R"/04_Research/programs/P4_ASSEMBLY/_lanes/"$1"/k* 2>/dev/null | wc -l | tr -d ' '; }
mk_ledger(){ local d="$R/04_Research/programs/P4_ASSEMBLY/$1"; printf '%s\n' "$2" >> "$d/chain_steps.jsonl"; }
REASON_VIP='[p4-base-measure] 기준 칸 — vintage_in_progress · 팩터 DB 수리 1건이 진행 중(완료 시각 없음 · factor_db_vintage.json) — 판이 정해지지 않아 측정하지 않는다(수리 완료 뒤 다시)'
s_T23(){ new A; setp A measure_base 0; printf '%s\n' "$REASON_VIP" > "$SCN/out.p4-base-measure"; echo 1 > "$SCN/rc.p4-base-measure"; tick
  [ "$(ncall p4-base-measure)" = 1 ] && [ "$(marker measure_error)" = 0 ] && [ "$(cat "$SCN/rc.txt")" = 0 ] && grep -q 'vintage_in_progress(rc 1)' "$SCN/out.txt"; }
s_T23b(){ new A; setp A measure_base 0; echo "Error in rc_p4_base_measure: 워커 크래시" > "$SCN/out.p4-base-measure"; echo 1 > "$SCN/rc.p4-base-measure"; tick
  [ "$(marker measure_error_A)" = 1 ] && [ "$(cat "$SCN/rc.txt")" = 1 ]; }
s_T11b(){ new A; setp A close_wait - budget_steps; touch "$SCN/notify_fail"; tick; local r1 m1; r1=$(cat "$SCN/rc.txt"); m1=$(marker close_wait_notify_A)
  rm -f "$SCN/notify_fail"; tick; [ "$r1" = 1 ] && [ "$m1" = 1 ] && [ "$(wc -l < "$SCN/notify.log" 2>/dev/null | tr -d ' ')" = 1 ] && [ "$(cat "$SCN/rc.txt")" = 0 ]; }
s_T24(){ new A; setp A open 1; touch "$SCN/gen_hold"; tick
  [ "$(ncall GEN)" = 1 ] && [ "$(ncall p4-step-open)" = 0 ] && [ ! -f "$SCN/genfail.A" ] && [ "$(lanes_n A)" = 0 ] && [ "$(cat "$SCN/rc.txt")" = 0 ]; }
s_T24b(){ new A; setp A open 1; touch "$SCN/compile_hold"; tick
  [ "$(ncall p4-step-open)" = 0 ] && [ ! -f "$SCN/genfail.A" ] && [ ! -f "$R/04_Research/programs/P4_ASSEMBLY/A/cells/k1.json" ] && [ "$(lanes_n A)" = 0 ]; }
s_T25(){ new A; setp A open 1; touch "$SCN/gen_skip"; tick; tick
  [ "$(ncall GEN)" = 2 ] && [ ! -f "$SCN/genfail.A" ] && [ "$(marker gen_blocked_A)" = 0 ] && [ "$(ncall p4-step-open)" = 0 ] && [ "$(lanes_n A)" = 0 ]; }
s_T17c(){ new A; setp A open 1; echo 5 > "$SCN/gen_rc"; tick; tick; local a; a=$(lanes_n A)
  echo 4 > "$SCN/gen_rc"; tick; [ "$a" = 0 ] && [ "$(lanes_n A)" = 0 ] && [ "$(ncall GEN)" = 3 ]; }
s_T1c(){ new A; mk_ledger A '{"schema":"rc_p4_chain_steps_v1","at":"y","prev":"p","event":"chain_closed","chain_id":"A"}'; setp A measure_base 0; tick
  [ ! -s "$SCN/out.txt" ] && [ "$(cat "$SCN/rc.txt")" = 0 ] && [ "$(ncall .)" = 0 ] && [ ! -d "$R/.cache" ]; }
s_T1d(){ new A; touch "$R/04_Research/programs/P4_ASSEMBLY/A/tick_hold"; setp A measure_base 0; tick
  [ ! -s "$SCN/out.txt" ] && [ "$(ncall .)" = 0 ] && [ ! -d "$R/.cache" ]; }
s_T1e(){ new A; setp A skip - closed; tick; [ "$(ls "$R"/.cache/scheduler_logs/chain_tick_*.log 2>/dev/null | wc -l | tr -d ' ')" = 0 ] && [ "$(cat "$SCN/rc.txt")" = 0 ]; }
s_T15b(){ new A; setp A measure_base 0; local L="$R/.cache/chain_tick.lock"; mkdir -p "$L"; echo 999999 > "$L/pid"
  ( export CT_LOCK_RACE_HOOK="rm -rf '$L'; mkdir -p '$L'; echo $$ > '$L/pid'"; tick )
  [ "$(ncall .)" = 0 ] && [ -d "$L" ] && [ "$(cat "$L/pid" 2>/dev/null)" = "$$" ] && [ "$(ls -d "$L".reclaim.* 2>/dev/null | wc -l | tr -d ' ')" = 0 ]; }
s_T26(){ new A; setp A blocked 0 base_failed "기준 칸 실패 상한"; tick; local a1 a2; a1=$(grep -c '\[경보\] blocked_base_failed_A' "$SCN/out.txt")
  tick; a2=$(grep -c '\[경보\] blocked_base_failed_A' "$SCN/out.txt"); ( export CT_DAY=d2; tick )
  [ "$a1" = 1 ] && [ "$a2" = 0 ] && [ "$(grep -c '\[경보\] blocked_base_failed_A' "$SCN/out.txt")" = 1 ]; }
s_T2b(){ new A; setp A measure_base 0; ( export QVEST_CHAIN_TICK=off; tick ); [ ! -s "$SCN/out.txt" ] && [ "$(ncall .)" = 0 ]; }

TK="$(mk_tick base)"
echo "== 대상 $TICK_SRC =="
# T1 사슬 0 · 등록 안 된 사슬만
new; tick; chk "T1 사슬 폴더 0 → 출력 0바이트 · 종료 0 · 호출 0 · 잠금 · 로그 없음" "$([ ! -s "$SCN/out.txt" ] && [ "$(cat "$SCN/rc.txt")" = 0 ] && [ "$(ncall .)" = 0 ] && [ ! -d "$R/.cache" ] && echo 0 || echo 1)"
new; d="$R/04_Research/programs/P4_ASSEMBLY/P4C01_x"; mkdir -p "$d" "$R/04_Research/programs/P4_ASSEMBLY/_lanes/x"; echo '{}' > "$d/chain_spec.json"; : > "$d/chain_steps.jsonl"
echo '{}' > "$R/04_Research/programs/P4_ASSEMBLY/_lanes/chain_spec.json"; setp P4C01_x measure_base 0; tick
chk "T1b 등록 안 된 사슬(빈 원장)만 · _ 폴더 → 무음 0 · 계획기조차 안 부른다" "$([ ! -s "$SCN/out.txt" ] && [ "$(ncall .)" = 0 ] && [ ! -d "$R/.cache" ] && echo 0 || echo 1)"
s_T2; chk "T2 enabled=false → 무음 0 · 호출 0" $?
s_T2b; chk "T2b QVEST_CHAIN_TICK=off → 무음 0 · 호출 0" $?
new A; setp A measure_base 0; touch "$SCN/config_bad"; tick
chk "T3 설정 판독 불가 → round.sh 호출 0 · 경보 마커 config_unreadable 1 · 종료 0" "$([ "$(ncall .)" = 0 ] && [ "$(marker config_unreadable)" = 1 ] && [ "$(cat "$SCN/rc.txt")" = 0 ] && echo 0 || echo 1)"
new A; setp A measure_base 0; printf '[p4-base-measure] 기준 칸 — measured\n' > "$SCN/out.p4-base-measure"; nextp A p4-base-measure open 1; echo 6 > "$SCN/rc.fresh-check"; tick
chk "T4 기준 칸 미측정 → p4-base-measure 1회(그 틱 측정 상한 = 1 · 생성 0)" "$([ "$(ncall 'p4-base-measure')" = 1 ] && [ "$(ncall 'GEN')" = 0 ] && echo 0 || echo 1)" "$(calls | tr '\n' '|')"
new A; setp A decide 1; nextp A p4-step-decide skip - closed; tick
chk "T5 측정된 걸음 → p4-step-decide 1 · 측정 0" "$([ "$(ncall 'p4-step-decide --k 1')" = 1 ] && [ "$(ncall measure)" = 0 ] && echo 0 || echo 1)"
new A; setp A open 1; nextp A p4-step-open measure_step 1; nextp A p4-step-measure decide 1; nextp A p4-step-decide open 2
printf '[p4-step-measure] 걸음 1 — measured\n' > "$SCN/out.p4-step-measure"; tick
seq6=$(calls | awk '{print $2}' | grep -E '^(fresh-check|p4-workdir|GEN|p4-step-open|p4-step-measure|p4-step-decide)$' | tr '\n' ' ')
chk "T6 열기 경로 끝까지 — fresh-check → p4-workdir → 생성기 1 → p4-step-open → p4-step-measure → p4-step-decide(같은 틱)" \
    "$([ "$seq6" = "fresh-check p4-workdir GEN p4-step-open p4-step-measure p4-step-decide " ] && [ ! -f "$SCN/genfail.A" ] && echo 0 || echo 1)" "$seq6"
chk "T6b 생성 산출 출처 기록(tick_provenance.json) · 작업 폴더 = lanes_dir/<chain_id>/k1_<ts>" "$(ls "$R"/04_Research/programs/P4_ASSEMBLY/_lanes/A/k1_*/tick_provenance.json >/dev/null 2>&1 && echo 0 || echo 1)"
s_T7; chk "T7 배리어 잠김 → 판정 · 측정 · 작업 폴더 · 생성 0 · 로그 한 줄" $?
s_T8; chk "T8 데이터 낡음(fresh-check 6) · 열기 필요 → 생성 0 · 열기 0" $?
new A; setp A open 1; echo "invalid rx_validate 실패" > "$SCN/compile_reject"; tick; g1=$(ncall GEN); tick; g2=$(ncall GEN); tick; g3=$(ncall GEN)
chk "T9 생성 산출 거부 2회 → 장부 차단 · 경보 gen_blocked 1 · 세 번째 틱 생성 0 · 열기 0" \
    "$([ "$g1" = 1 ] && [ "$g2" = 2 ] && [ "$g3" = 2 ] && [ -f "$SCN/genblocked.A" ] && [ "$(marker gen_blocked_A)" = 1 ] && [ "$(ncall p4-step-open)" = 0 ] && echo 0 || echo 1)" "g=$g1,$g2,$g3"
new A; setp A open 1; echo 1 > "$SCN/rc.p4-step-open"; echo "걸음 열기 거부(k = 1): - 이미 쓴 칸 사양(md5) — 새 칸이 아니다" > "$SCN/out.p4-step-open"; tick
chk "T9b 열기 거부 '이미 쓴 칸 사양' = 생성 실패 +1 · 원장 명령 p4-step-open 1회 · 고아 칸 사양 삭제" \
    "$([ "$(cat "$SCN/genfail.A" 2>/dev/null)" = 1 ] && [ "$(ncall p4-step-open)" = 1 ] && [ ! -f "$R/04_Research/programs/P4_ASSEMBLY/A/cells/k1.json" ] && echo 0 || echo 1)"
new A; setp A open 1; echo 1 > "$SCN/rc.p4-step-open"; echo "원장 추가 거부(잠금 안 재확인) — 걸음 1 가 이미 열렸다(다른 프로세스)" > "$SCN/out.p4-step-open"; tick
chk "T10 경합 문구('이미 열렸다') = 실패로 세지 않음" "$([ ! -f "$SCN/genfail.A" ] && echo 0 || echo 1)"
new A; setp A close_wait - budget_steps; tick; tick
chk "T11 닫기 대기 두 틱 → 알림(prep_send 경로) 1회만 · p4-close 0" "$([ "$(wc -l < "$SCN/notify.log")" = 1 ] && [ "$(ncall 'p4-close')" = 0 ] && echo 0 || echo 1)"
s_T13; chk "T13 계획기가 모르는 행동(close) → 허용 목록이 막음 · round.sh p4-close 0 · 경보 forbidden_stage · 종료 1" $?
new A; setp A measure_base 0; mkdir -p "$R/.cache/chain_tick.lock"; echo $$ > "$R/.cache/chain_tick.lock/pid"; tick
chk "T14 살아 있는 잠금 보유자 → 0 종료 · 호출 0" "$([ "$(cat "$SCN/rc.txt")" = 0 ] && [ "$(ncall .)" = 0 ] && echo 0 || echo 1)"
new A; setp A measure_base 0; mkdir -p "$R/.cache/chain_tick.lock"; echo 999999 > "$R/.cache/chain_tick.lock/pid"; tick
chk "T15 죽은 pid 잠금 → 인계 · 정상 진행 · 끝나면 잠금 해제" "$([ "$(ncall p4-base-measure)" = 1 ] && [ ! -d "$R/.cache/chain_tick.lock" ] && echo 0 || echo 1)"
s_T16; chk "T16 생성기 한도(종료 3) → 물러남 파일 · 경보 llm_limit 1 · 실패 수 불변 · 같은 날 생성 0 · 측정은 진행 · 다음 날 재개" $?
new A; setp A open 1; echo 5 > "$SCN/gen_rc"; tick; m5=$(marker guard_probe); tick; m5b=$(marker guard_probe)
chk "T17 가드 탐침 실패(종료 5) → 경보 guard_probe 하루 1 · 실패 수 불변 · 열기 0" "$([ "$m5" = 1 ] && [ "$m5b" = 1 ] && [ ! -f "$SCN/genfail.A" ] && [ "$(ncall p4-step-open)" = 0 ] && echo 0 || echo 1)"
new A; setp A open 1; echo 4 > "$SCN/gen_rc"; tick
chk "T17b 인증 실패(종료 4) → 경보 auth · 실패 수 불변" "$([ "$(marker auth)" = 1 ] && [ ! -f "$SCN/genfail.A" ] && echo 0 || echo 1)"
new A; setp A abandon 2 measure_failed; nextp A p4-step-abandon skip - closed; tick
ab=$(calls | grep 'p4-step-abandon'); abr=${ab#*--reason }
chk "T18 측정 실패 상한 → p4-step-abandon --k 2 · 사유 문장에 숫자 · 날짜 없음" "$(printf '%s' "$ab" | grep -q -- '--k 2' && ! printf '%s' "$abr" | grep -q '[0-9]' && echo 0 || echo 1)" "$ab"
new A B; setp A skip - held_by_session; setp B measure_base 0; tick
chk "T19 tick_hold(계획 skip) 사슬 호출 0 · 다른 사슬은 진행" "$([ "$(ncall '^A ')" = 0 ] && [ "$(ncall '^B p4-base-measure')" = 1 ] && echo 0 || echo 1)"
s_T20c; chk "T20c 측정 예산 0(measures_per_tick) → 측정 0 · 열고 못 재는 걸음을 만들지 않는다(생성 0)" $?
s_T20; chk "T20 두 사슬 모두 측정 필요 → 틱당 측정 1 · 마지막 처리 순환(두 틱에 걸쳐 둘 다)" $?
new A; setp A open 1; tick --dry-run
chk "T21 --dry-run → round.sh · 생성기 0 · 잠금 · 로그 0 · 계획 표 출력" "$([ "$(ncall .)" = 0 ] && [ ! -d "$R/.cache/scheduler_logs" ] && grep -q '드라이런' "$SCN/out.txt" && grep -q LISTED "$SCN/helper.log" && echo 0 || echo 1)"
new A; touch "$SCN/genblocked.A"; L0=$(md5sum "$R/04_Research/programs/P4_ASSEMBLY/A/chain_steps.jsonl"); tick --reset A
chk "T22 --reset → 장부 차단 해제 · 원장 무접촉 · round.sh 0" "$([ ! -f "$SCN/genblocked.A" ] && [ "$L0" = "$(md5sum "$R/04_Research/programs/P4_ASSEMBLY/A/chain_steps.jsonl")" ] && [ "$(ncall .)" = 0 ] && echo 0 || echo 1)"
new A; tick --bogus; chk "T22b 모르는 인자 → 종료 2" "$([ "$(cat "$SCN/rc.txt")" = 2 ] && echo 0 || echo 1)"
echo "== 재수리(11-10 독립 검증 지적) =="
s_T23; chk "R1 기준 칸 측정 상태 줄 사유에 ' — ' (vintage_in_progress · rc 1) → 상태 판독 · measure_error 경보 0 · 종료 0" $?
s_T23b; chk "R1b 양성 대조 — 상태 줄 없는 rc 1 → measure_error 경보 1 · 종료 1" $?
s_T11b; chk "R2 닫기 대기 알림 발송 실패 → 경보 close_wait_notify 1 · 종료 1 · 다음 틱 재발송 1통" $?
s_T24; chk "R3 생성 도중 tick_hold(재계획 skip) → 걸음 열기 0 · 실패 수 불변 · 작업 폴더 삭제" $?
s_T24b; chk "R3b 산출 검사 뒤 tick_hold → 열기 0 · 칸 사양 삭제 · 실패 수 불변" $?
s_T1c; chk "R4 닫힌 사슬(원장 마지막 chain_closed)만 → 무음 0 · 계획기 호출 0 · .cache 없음" $?
s_T1d; chk "R4b tick_hold 사슬만 → 무음 0 · 호출 0" $?
s_T1e; chk "R4c 모든 행동 skip → 틱 로그 파일 남기지 않음" $?
s_T17c; chk "R5 생성기 종료 5 ×2 · 4 ×1 → 쓰지 않은 작업 폴더 0" $?
s_T25; chk "R6 생성기가 산출 없이 0(잠금 건너뜀) ×2 → 실패로 세지 않음 · 차단 경보 0 · 폴더 0" $?
s_T15b; chk "R7 죽은 잠금 판정 뒤 다른 실행이 새 잠금(살아 있음) → 회수 안 함 · 호출 0 · 남의 잠금 보존" $?
s_T26; chk "R8 정지 알림(blocked) = 하루 단위 — 같은 날 두 번째 0 · 다음 날 다시 1" $?
ALLC=$(cat "$T"/s*/calls.log 2>/dev/null | awk '{print " "$2" "}' | grep -cE "$FORBID")
chk "T12 전 시나리오 합 — 등록 · 닫기 · 격리 · 생성기 새 판 · 결과 원장 격리 호출 0건" "$([ "$ALLC" = 0 ] && echo 0 || echo 1)" "$ALLC"

echo "== 돌연변이(소스 텍스트 치환 · 치환 성사 단정 · 사본 단독 실행) =="
mut(){ # id 시나리오 from to 설명
  local tk n; tk="$(mk_tick "m_$1")"; n=$(mutate "$tk" "$3" "$4" | tr -d '\r')
  if [ "$n" != "1" ]; then ng "$1 치환 성사" "치환 수 $n ≠ 1"; return; fi
  TK="$tk"; if "$2"; then ng "$1 $5" "돌연변이가 살아남았다(검사가 막고 있지 않다)"; else ok "$1 $5 → 빨강"; fi
  TK="$(mk_tick base)"
}
mut M1 s_T13 'case "$ALLOWED" in *" $2 "*) ;; *)' 'case "$ALLOWED" in *) ;; *)' "허용 목록 검사 제거"
mut M2 s_T7 'BARRIER_OK=1; [ "$BRC" = "0" ] || {' 'BARRIER_OK=1; [ "$BRC" = "0" ] || [ 1 = 1 ] || {' "배리어 분기 제거"
mut M3 s_T2 '[ "$EN" = "true" ] || exit 0' ': enabled 검사 제거' "enabled 검사 제거"
mut M4 s_T16 'if [ "$BACKOFF" = "yes" ]; then' 'if false; then' "한도 물러남 검사 제거"
mut M7 s_T8 'elif ! rs "$PICK" fresh-check; then' 'elif false; then' "fresh-check 앞세움 제거"
mut M8 s_T20c '[ "$MEAS_LEFT" -gt 0 ] || {' '[ 1 -gt 0 ] || {' "틱당 측정 상한 제거"
mut M10 s_T23 'rest=${ln#* — }; [ "$rest" != "$ln" ] && st=${rest%%[!a-z_]*}' 'st=$(printf '"'"'%s\n'"'"' "$ln" | sed -n '"'"'s/^\[p4-[a-z-]*measure\] .* — \([a-z_]*\).*/\1/p'"'"')' '상태 줄 탐욕 파싱(원 결함)'
mut M11 s_T1c 'grep -q '"'"'"event":"chain_closed"'"'"' && continue' 'grep -q NEVERMATCH && continue' '닫힌 사슬 0단계 제외 제거'
mut M12 s_T24 'plan "$1"; [ "$ACT" = "open" ] && [ "$K" = "$2" ] && return 0' 'return 0' '생성 뒤 재계획 제거'
mut M13 s_T25 'if [ ! -f "$ROOT/$wrel/gen_result.json" ]; then' 'if false; then' '산출 없는 0 = 건너뜀 분류 제거'
mut M14 s_T15b 'h=$(lock_holder "$RCL")' 'h=""' '회수 뒤 재판정 제거'
mut M15 s_T26 'H record "$1" mark_daily "$2"' 'H record "$1" mark "$2"' '하루 단위 표식 → 영구 표식'
mut M16 s_T11b 'if [ "$nrc" != "0" ] || [ "$nr" = "failed" ] || [ -z "$nr" ]; then RC=1' 'if false; then RC=1' '알림 발송 실패 분기 제거'
mut M17 s_T17c 'chmod -R u+w "$ROOT/$wrel" 2>/dev/null; rm -rf "$ROOT/$wrel"; }' ':; }' '쓰지 않은 작업 폴더 삭제 제거'
mut M18 s_T1e 'if [ "$NONSKIP" = "0" ] && [ "$RC" = "0" ]; then rm -f "$LOG"; exit 0; fi' ':' '전부 skip 로그 삭제 제거'
mut M9 s_T20 'PICK=""; PICK_AT=""' 'PICK=""; PICK_AT=""; HEAVY=("${HEAVY[0]}")' "마지막 처리 순환(last_served) 무시"

OPS1="$(md5_ops)"
chk "Z 운영 등록부 · 결과 원장 · 생성기 등록부 · .cache/chain_tick md5 전후 동일(무접촉)" "$([ "$OPS0" = "$OPS1" ] && echo 0 || echo 1)"
echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
printf '{"test":"scn_chain_tick","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
