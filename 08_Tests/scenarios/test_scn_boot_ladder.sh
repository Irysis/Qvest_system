#!/usr/bin/env bash
#==============================================================================
# test_scn_boot_ladder.sh — 부팅(boot_lean.sh) Programs 줄 '| 사다리: …' 꼬리 + Last 줄 '원장 다음 탐침' (v10.2 · 2026-11-11)
#
# 대상: boot_lean.sh 파이썬 heredoc 본문(_OUTCOMES · _last_probe · _LD_* · LADDER) — 블록을 통째로 꺼내 임시 루트에서 돌린다
#   (test_boot_lean_memo.sh 와 같은 주입: PROJECT=<임시 루트> · QM_ROOT 해제 · QVEST_BOOT_MEMO=0 → 임시 루트에도 메모를 쓰지 않는다).
# 정의 대조(부팅 ↔ 실행기):
#   상설 판 = standing_board_run.sh '등록된 판'(standing true · round_id = 디렉터리 · prereg.json 존재) · 항목 = round_core v1/standing.R::rc_standing_items
#   사슬 = chain_tick.sh 0단계(첫 줄 chain_registered · 마지막 줄 chain_closed = 닫힘 · '_' 폴더 제외 · tick_hold) · 생성 차단 = 틱 장부 state/<id>.json gen_blocked
#   결과 원장 = round_core v1/outcomes.R(격리 줄 제외 · 열린 탐침 = probe_consumed 에 없는 ref)
# 시나리오: a 판·사슬 없음 · b 등록 판(항목 2 · 통과 1 · 대기 1) + 미등록 사양 · c 열린 사슬 + 닫힌 사슬 + tick_hold + 생성 차단 ·
#   d 틱 꺼짐 / 설정 손상 · e 깨진 원장 → '?' · f 결과 원장(열린 탐침 · 격리 줄 · Last 꼬리)
# 돌연변이: M1 '사전등록 정본 있음' 조건 제거 → b red · M2 끊긴 원장을 빈 항목으로 접기 → e red
# 격리: 임시 루트만(운영 루트 · 운영 등록부 · .cache 쓰기 0 · R 0).
# 후보판 이음새: BOOT_LADDER_SRC=<boot_lean.sh 사본>(운영 교체 전 검사)
# 요약: 마지막 줄 {"test":"boot_ladder","pass":N,"fail":N,"total":N}
#==============================================================================
set -u
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$SELF/../.." && pwd)"
BOOT="${BOOT_LADDER_SRC:-$ROOT/02_Infrastructure/ops/boot_lean.sh}"
PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
STD="$ROOT/04_Research/programs/_lib/round_core/v1/standing.R"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1  ($2)"; }
finish() { echo "PASS=$PASS FAIL=$FAIL"; echo "{\"test\":\"boot_ladder\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"; [ "$FAIL" -eq 0 ] || exit 1; exit 0; }
[ -x "$PY" ] && [ -f "$BOOT" ] && [ -f "$STD" ] || { bad "0 전제" "venv python · boot_lean.sh · standing.R 중 없음"; finish; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
TW="$(cygpath -m "$T" 2>/dev/null || echo "$T")"
PR="$TW/proj"; mkdir -p "$T/proj"

awk '/<<.PYEOF.( |$)/{f=1;next} /^PYEOF/{if(f){exit}} f' "$BOOT" > "$T/block.py"
grep -q '^def LADDER():' "$T/block.py" && grep -q '^def _OUTCOMES(' "$T/block.py" && ok "0 블록 추출 · LADDER · _OUTCOMES 존재" || { bad "0 블록 추출" "LADDER/_OUTCOMES 없음"; finish; }

# 픽스처 도구: fx <시나리오> — 임시 루트를 비우고 그 시나리오 상태로 만든다
cat > "$T/fx.py" <<'PYEOF'
import os, sys, json, hashlib, shutil, datetime as dt
P, SC, STD = sys.argv[1], sys.argv[2], sys.argv[3]
for x in os.listdir(P): shutil.rmtree(os.path.join(P, x))
def w(rel, s):
    f = os.path.join(P, *rel.split("/")); os.makedirs(os.path.dirname(f), exist_ok=True)
    open(f, "w", encoding="utf-8", newline="\n").write(s)
def js(o): return json.dumps(o, ensure_ascii=False, separators=(",", ":"))
def ts(h): return (dt.datetime.now().astimezone() - dt.timedelta(hours=h)).strftime("%Y-%m-%dT%H:%M:%S%z")
def chain(recs, schema, extra=lambda r: r):
    out, prev = [], "genesis"
    for r in recs:
        s = js(extra(dict({"schema": schema, "at": r.pop("_at", ts(10)), "prev": prev}, **r))); out.append(s)
        prev = hashlib.md5(s.encode("utf-8")).hexdigest()
    return "\n".join(out) + "\n"
# 공통: 틱 켜짐 · 팩터 DB 수리 1건 · 코어 상수 원본(standing.R 사본 — 코어 상수 이름이 바뀌면 '대기 ?' 로 드러난다)
w("06_Registry/chain_tick.json", js({"schema": "chain_tick_v1", "enabled": SC != "d"}))
w("06_Registry/factor_db_vintage.json", js({"schema": "factor_db_vintage_v1", "entries": [{"id": "X", "completed_at": "2026-11-10T11:26:00+09:00", "scope": "all"}]}))
os.makedirs(os.path.join(P, "04_Research/programs/_lib/round_core/v1"), exist_ok=True)
shutil.copy(STD, os.path.join(P, "04_Research/programs/_lib/round_core/v1/standing.R"))
def spec(prog, rid, standing, rid_in=None):
    w("04_Research/programs/%s/%s/round_spec.json" % (prog, rid),
      json.dumps({"schema": "round_spec_v1", "program": prog, "round_id": rid_in or rid, "standing": standing}, indent=2, ensure_ascii=False))
if SC in ("b", "e", "f"):
    spec("P1_RETURN", "P1S01_board", True)                      # 등록(사전등록 정본 있음)
    spec("P1_RETURN", "P1S02_draft", True)                      # 미등록(사전등록 정본 없음)
    spec("P2_DEFENSE", "P2R01_plain", False)                    # 상설 아님
    spec("P2_DEFENSE", "P2S09_misnamed", True, rid_in="OTHER")  # round_id ≠ 디렉터리 = 판 아님
    w("stage_artifacts/programs/P1_RETURN/P1S01_board/prereg.json", "{}")
    led = chain([{"event": "enqueue", "code": "P1S01_A", "role": "variant"},
                 {"event": "enqueue", "code": "P1S01_B", "role": "variant"},
                 {"event": "measure", "code": "P1S01_A", "ok": True, "fp_same": True},
                 {"event": "verdict", "code": "P1S01_A", "status": "evaluated", "qualify": True, "_at": ts(3)}], "rc_standing_ledger_v1")
    if SC == "e":   # 가운데 줄의 앞 줄 md5 를 바꾼다(중간 수정) — 코어는 읽기를 거부한다
        L = led.split("\n"); L[1] = L[1].replace('"prev":"', '"prev":"0', 1); led = "\n".join(L)
    w("stage_artifacts/programs/P1_RETURN/P1S01_board/standing_ledger.jsonl", led)
if SC == "c":
    w("04_Research/programs/P4_ASSEMBLY/C1_open/chain_spec.json", "{}")
    w("04_Research/programs/P4_ASSEMBLY/C1_open/chain_steps.jsonl", chain([
        {"event": "chain_registered", "chain_id": "C1_open"}, {"event": "base_measured", "k": 0},
        {"event": "step_open", "k": 1}, {"event": "step_result", "k": 1, "decision": "reject"},
        {"event": "step_open", "k": 2, "_at": ts(5)}], "rc_p4_chain_steps_v1"))
    w("04_Research/programs/P4_ASSEMBLY/C1_open/tick_hold", "")
    w("04_Research/programs/P4_ASSEMBLY/C2_closed/chain_spec.json", "{}")
    w("04_Research/programs/P4_ASSEMBLY/C2_closed/chain_steps.jsonl", chain([
        {"event": "chain_registered", "chain_id": "C2_closed"}, {"event": "chain_closing"}, {"event": "chain_closed", "label": "x"}], "rc_p4_chain_steps_v1"))
    w("04_Research/programs/P4_ASSEMBLY/C3_unreg/chain_spec.json", "{}")                      # 등록 전 = 세지 않는다
    w("04_Research/programs/P4_ASSEMBLY/C3_unreg/chain_steps.jsonl", chain([{"event": "step_open", "k": 1}], "rc_p4_chain_steps_v1"))
    w("04_Research/programs/P4_ASSEMBLY/_generator/chain_spec.json", "{}")                     # '_' 폴더 제외
    w("04_Research/programs/P4_ASSEMBLY/_generator/chain_steps.jsonl", chain([{"event": "chain_registered"}], "rc_p4_chain_steps_v1"))
    w(".cache/chain_tick/state/C1_open.json", js({"gen_blocked": True, "consecutive_gen_failures": 2}))
if SC == "d2":
    w("06_Registry/chain_tick.json", "{not json")
if SC in ("e", "f"):
    o = [{"schema": "round_outcome_v1", "kind": "round", "program": "P1_RETURN", "round_id": "R1", "probes": ["a1", "a2"]},
         {"schema": "round_outcome_v1", "kind": "round", "program": "P1_RETURN", "round_id": "R2", "probes": ["b1", "b2"]},
         {"schema": "round_outcome_v1", "kind": "probe_consumed", "ref": "R2#1", "by": "R3"}]
    L = [js(x) for x in o]
    if SC == "f":   # 격리된 손상 줄 = 건너뛴다(outcomes.R rc_outcomes_quarantined)
        badl = '{"broken'
        L.insert(1, badl)
        L.append(js({"schema": "round_outcome_v1", "kind": "quarantine", "line_no": 2, "line_md5": hashlib.md5(badl.encode("utf-8")).hexdigest(), "reason": "t"}))
    else:           # 격리 안 된 손상 줄 = '?'
        L.insert(1, '{"broken')
    w("06_Registry/round_outcomes.jsonl", "\n".join(L) + "\n")
PYEOF

BLK="$T/block.py"
run() {  # run <시나리오> → 출력 전문을 $T/out_<시나리오>.txt
  "$PY" -X utf8 "$T/fx.py" "$PR" "$1" "$STD" || { echo "fixture fail $1"; return 1; }
  ( cd "$T/proj" && env -u QM_ROOT PROJECT="$PR" PY="$PY" QVEST_BOOT_MEMO=0 PYTHONUTF8=1 "$PY" -X utf8 "$BLK" > "$T/out_$1.txt" 2>/dev/null )
}
tail_of() { grep '^Programs:' "$T/out_$1.txt" | sed -n 's/^.* | 사다리: /사다리: /p'; }
last_of() { grep '^Last:' "$T/out_$1.txt"; }
expect() {  # expect <id> <시나리오> <기대 꼬리>
  local g; g="$(tail_of "$2")"
  [ "$g" = "$3" ] && ok "$1 → $g" || bad "$1" "got '$g' · want '$3'"
}
FDV="팩터DB 수리 11-10"

echo "=== 시나리오 ==="
run a; expect "a 판·사슬 없음" a "사다리: 상설 판 0 · 사슬 0 · 틱 켜짐 · 결과 원장 없음(첫 닫기 전) · $FDV"
[ "$(grep -c '' "$T/out_a.txt")" = "8" ] && ok "a2 출력 8줄 그대로" || bad "a2 줄 수" "$(grep -c '' "$T/out_a.txt")"
case "$(last_of a)" in *"원장 다음 탐침"*) bad "a3 Last" "원장 없는데 탐침 꼬리";; Last:*) ok "a3 원장 없음 → Last 꼬리 없음";; *) bad "a3 Last" "Last 줄 없음";; esac
run b; expect "b 등록 판 + 미등록 사양" b "사다리: 상설 판 1(P1S01 항목 2·통과 1·대기 1·3h 전 / P1S02 미등록) · 사슬 0 · 틱 켜짐 · 결과 원장 없음(첫 닫기 전) · $FDV"
run c; expect "c 열린 사슬(보류 · 생성 차단) + 닫힌 사슬" c "사다리: 상설 판 0 · 사슬 1(C1_open k2 step_open 5h 전 ·보류) · 닫힘 1 · ★생성 차단 1 · 틱 켜짐 · 결과 원장 없음(첫 닫기 전) · $FDV"
run d; expect "d 틱 꺼짐" d "사다리: 상설 판 0 · 사슬 0 · 틱 꺼짐 · 결과 원장 없음(첫 닫기 전) · $FDV"
run d2; expect "d2 틱 설정 손상 → ?" d2 "사다리: 상설 판 0 · 사슬 0 · 틱 ? · 결과 원장 없음(첫 닫기 전) · $FDV"
run e; expect "e 끊긴 판 원장 · 손상 결과 원장 → ?" e "사다리: 상설 판 1(P1S01 ?(원장 사슬 끊김) / P1S02 미등록) · 사슬 0 · 틱 켜짐 · 결과 원장 ?(판독 불가) · $FDV"
case "$(last_of e)" in *"원장 다음 탐침"*) bad "e2 Last" "손상 원장에서 탐침을 지어냈다";; Last:*) ok "e2 손상 결과 원장 → Last 꼬리 없음";; *) bad "e2" "Last 줄 없음";; esac
run f; expect "f 결과 원장(라운드 2 · 열린 탐침 3 · 격리 줄 제외)" f "사다리: 상설 판 1(P1S01 항목 2·통과 1·대기 1·3h 전 / P1S02 미등록) · 사슬 0 · 틱 켜짐 · 결과 원장 2건 · 열린 탐침 3 · $FDV"
case "$(last_of f)" in *' · 원장 다음 탐침 "b2"') ok "f2 Last 꼬리 = 최근 라운드 R2 의 첫 열린 탐침 b2";; *) bad "f2 Last" "$(last_of f)";; esac

echo "=== 돌연변이 ==="
mutate() {  # mutate <id> <원문> <치환> <시나리오> <기대 꼬리(원판)>
  local m="$T/mut_$1.py"
  "$PY" -X utf8 - "$T/block.py" "$m" "$2" "$3" <<'PYEOF'
import sys
s = open(sys.argv[1], encoding="utf-8").read(); a, b = sys.argv[3], sys.argv[4]
assert s.count(a) == 1, "치환 대상 %d곳" % s.count(a)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(a, b))
PYEOF
  [ $? -eq 0 ] || { bad "$1 사본" "치환 실패"; return; }
  BLK="$m" run "$4"; local g; g="$(tail_of "$4")"
  [ -n "$g" ] && [ "$g" != "$5" ] && ok "$1 사본이 $4 를 빨갛게 만든다 → $g" || bad "$1" "돌연변이를 못 잡는다('$g')"
}
mutate M1 'if not os.path.isfile(R("stage_artifacts","programs",prog,rid,"prereg.json")): un.append(tag); continue' 'pass' b \
  "사다리: 상설 판 1(P1S01 항목 2·통과 1·대기 1·3h 전 / P1S02 미등록) · 사슬 0 · 틱 켜짐 · 결과 원장 없음(첫 닫기 전) · $FDV"
mutate M2 'return "?(원장 사슬 끊김)"' 'return {"n":0,"q":0,"p":0,"age":None}' e \
  "사다리: 상설 판 1(P1S01 ?(원장 사슬 끊김) / P1S02 미등록) · 사슬 0 · 틱 켜짐 · 결과 원장 ?(판독 불가) · $FDV"

echo "=== 계약 ==="
if grep -nE 'subprocess|os\.system|Popen' <(sed -n '/^def _OUTCOMES(/,/^o\.append(S(PROGRAMS/p' "$T/block.py" | grep -v '^#'); then bad "C1 사다리 블록" "프로세스 호출"; else ok "C1 사다리 블록 = 프로세스 호출 0"; fi
if sed -n '/^def _OUTCOMES(/,/^o\.append(S(PROGRAMS/p' "$T/block.py" | grep -nE "open\([^)]*['\"][wa]b?['\"]|\.write\(|os\.replace|os\.remove|shutil" ; then bad "C2 사다리 블록" "쓰기"; else ok "C2 사다리 블록 = 쓰기 0"; fi
grep -q '^o.append(S(PROGRAMS,"Programs: ?(표시 예외)")+S(DECISIONS," · 대기결정 ?(표시 예외)")+S(LADDER,' "$T/block.py" && ok "C3 Programs 줄이 LADDER 를 붙인다(새 줄 없음)" || bad "C3" "소비 줄 없음"
finish
