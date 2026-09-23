#!/usr/bin/env bash
# test_inject_usage_ranking — 주입 훅의 **극성**과 예산 검증 (v9 Lean Loop 재작성 2026-08-23 · 샌드박스 이관 2026-09-23)
#
# 이 파일이 원래 재던 것(2026-08-16 신설): DIST negative top-5 의 랭킹이 실사용 빈도를 따르는가.
# v9 재설계로 **그 블록 자체가 주입면에서 빠졌다** — negative 카드 top-5 를 매 spawn 마다
# 싣던 것이 "죽은 방향 재제안 금지" 편향의 본체였기 때문이다(distilled 167 중 negative 71 vs
# positive 11). 랭킹을 재는 검사는 대상이 없어졌으므로, 같은 자리에서 **재설계가 실제로
# 성립했는지**를 잰다. 랭킹 계산(build_distilled_usage.py) 자체는 살아 있고 그 산출물
# `.cache/distilled_usage.json` 도 계속 생성되나, 주입 경로의 소비자는 없다.
#
# 재는 것 (전부 주입문 실측 — 문서 선언이 아니라 훅 출력):
#   [A] 예산: additionalContext ≤ 2,000자 (v9 컨텍스트 예산)
#   [B] 양성: 전략 id(STR_*) 줄이 ≥1 — "무엇이 통했나" 가 실제로 실린다
#   [C] 교훈: L-code(L-XX-…) 줄이 ≥1 — "최근 교훈" 이 실제로 실린다
#   [D] 극성: "재제안 금지 / 재시도 금지" 문구 0건 — 금지 목록으로 되돌아가면 FAIL
#   [E] 무결: 유효 JSON + 고정부(공리·고정 축·dead 포인터) 상시 존재
#   [F] 폴백(위반 주입): positive_context.json 이 없어도 죽지 않고 고정부만 낸다
#   [Z] 격리(2026-09-23 신설): 운영 루트의 어떤 파일도 쓰지 않는다 — 실행 전후 대조 + 샌드박스 도달 증명
#
# ★2026-09-23 샌드박스 이관 (적대 검증 실측):
#   구판은 운영 루트에서 ①lcode_harvester 를 돌려 .cache/lcode_corpus.json·positive_context.json 을 다시 쓰고
#   ②[F] 절에서 **운영 positive_context.json 을 지운 채** 훅을 발화했다. 그 결과 배터리를 돌릴 때마다
#     · 운영 이벤트 원장(qepm/observability/events.jsonl)에 axiom_context_inject.sh hook_fired 2줄이 쌓였고
#     · .cache/axiom_inject_last.json 이 **열화 기록**(len 1441 · pc_status=missing · 마커 0/3)으로 남아
#       memory_knowledge_health HARD_10 을 발화시켰으며(09-23 19:25:31 실측 — 그 뒤 실 스폰 0회라 잔존)
#     · 그 창(rm ~ mv 복원) 동안 실제 Agent 스폰은 변동부 없는 축소 주입을 받았다.
#   수리 = 측정 대상(운영 훅·운영 하베스터 코드 + 운영 입력의 읽기 전용 사본)은 그대로, **쓰기 루트만** 샌드박스로.
#     입력 사본: L-code 원천 3경로(tar — mtime 보존: 최근 교훈 정렬이 mtime 이다) · 06_Registry 5종 · axioms/active
#       + tombstones · failure_revival_flags · CLAUDE.md. 하베스터는 --project-dir=샌드박스, 훅은
#       CLAUDE_PROJECT_DIR=QM_ROOT=샌드박스(qepm/observability 를 만들어 두어 발신이 **샌드박스 원장**에 떨어지게 한다).
#   [Z] 판정 규칙(동시 쓰기와 누수를 가른다 — 운영 원장은 다른 세션 훅이 수 초마다 append 한다):
#     · events.jsonl  : 훅 단계 [S0,S1) 에 append 된 바이트 안의 axiom_context_inject.sh 줄 = 0 (원장 머리 불변)
#                       + 샌드박스 원장에 정확히 훅 호출 수만큼(발신기는 호출당 한 경로에만 쓴다 → 운영 0 의 직접 증거)
#     · axiom_inject_last.json : 바뀌었고 agent = 이 검사 고유 토큰 → 누수. 다른 agent = 실 스폰(정보)
#     · positive_context·lcode_corpus·주입 캐시 2종 : 사라졌거나, 검사 창(스냅샷~훅 단계 끝) 안의 mtime 으로 바뀌면 누수.
#       창 밖 변경 = 동시 외부 쓰기(강화 러너 하베스트 등 — 정보)
#     · 검출기 양성 대조: 디코이 루트에 **구판 동작**(운영 경로 하베스트 + 변동부 삭제 후 발화 + 복원)을 재현하면
#       positive_context·axiom_inject_last·events 3종을 모두 누수로 잡아야 한다(ZM). 무처치 디코이는 0(ZN).
set -uo pipefail

# ── 루트 해석: 코드 = 이 파일이 실린 트리(러너 규약 self-first) · 데이터 = 운영(env) ────────────
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_MARK="08_Tests/hooks/run_all_hooks.sh"
_pick_code_root() {
  local c n
  for c in "$_SELF_DIR/../.." "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$PWD"; do
    [ -n "$c" ] || continue
    n="${c//\\//}"
    if [ -f "$n/$_MARK" ]; then (cd "$n" && pwd); return 0; fi
  done
  return 1
}
PASS=0; FAIL=0; SKIP=0; SKIPS=""
note() { printf '  %-66s %s\n' "$1" "$2"; }
ok()   { PASS=$((PASS+1)); note "$1" "OK"; }
bad()  { FAIL=$((FAIL+1)); note "$1" "★FAIL — $2"; }
skp()  { SKIP=$((SKIP+1)); note "$1" "SKIP — $2"
         SKIPS="${SKIPS:+$SKIPS,}{\"axis\":\"$1\",\"reason\":\"$2\",\"missing\":\"$3\"}"; }
summary() {
  echo
  echo "=== $PASS PASS / $FAIL FAIL / $SKIP SKIP ==="
  # 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 미편입 상태였다.
  echo "{\"test\":\"test_inject_usage_ranking\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL)),\"skipped\":$SKIP,\"skips\":[${SKIPS}]}"
}

echo "=== test_inject_usage_ranking (v9 주입 극성·예산 · 샌드박스) ==="

if ! CODE_ROOT="$(_pick_code_root)"; then
  bad "R0 코드 루트 해석" "표지 $_MARK 를 가진 후보 없음"; summary; exit 1
fi
DATA_ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$CODE_ROOT}}"
DATA_ROOT="${DATA_ROOT//\\//}"
DATA_ROOT="$(cygpath -u "$DATA_ROOT" 2>/dev/null || printf '%s' "$DATA_ROOT")"
HOOK="$CODE_ROOT/02_Infrastructure/hooks/axiom_context_inject.sh"
HARV="$CODE_ROOT/02_Infrastructure/axiom/lcode_harvester.py"
PY="${QVEST_PY_BIN:-${QVEST_PY:-python}}"; PY="${PY//\\//}"
# 이 검사의 훅 호출에만 붙는 고유 agent 토큰 — axiom_inject_last.json 의 agent 필드로 누수를 귀속한다.
#   ★forge/judge/book 을 포함하면 훅 헤더 분기가 바뀐다(= 원 검사와 다른 렌더). 아래 R1 이 그걸 막는다.
AGENT_TOKEN="alpha-research-sbx$$"

# ── 샌드박스 ─────────────────────────────────────────────────────────────────────
SB="$(mktemp -d "${TMPDIR:-/tmp}/qvest_inj_rank_XXXXXX")" || { bad "R0 샌드박스 생성" "mktemp 실패"; summary; exit 1; }
cleanup() {
  # 샌드박스 경로 형태를 확인한 뒤에만 지운다(빈 값·오설정으로 엉뚱한 트리를 지우지 않게).
  case "$SB" in */qvest_inj_rank_*) rm -rf "$SB" ;; esac
}
trap cleanup EXIT
P="$SB/proj"          # 하베스터·훅의 프로젝트 루트(샌드박스)
PW="$(cygpath -m "$P" 2>/dev/null || printf '%s' "$P")"   # native python·훅 DIR 용(C:/… 형식 — /tmp 형은 python glob 0건)

# 입력 사본(읽기 전용 원천 → 샌드박스). 원천 경로 = lcode_harvester.harvest / write_positive_context / 훅의 읽기 목록.
mk_inputs() {   # $1 = 대상 루트
  local d="$1" f
  mkdir -p "$d/.cache" "$d/qepm/memory/axioms" "$d/qepm/observability" "$d/06_Registry" "$d/stage_artifacts"
  ( cd "$DATA_ROOT" && {
      find stage_artifacts -maxdepth 1 -type f -name 'l_code_*.json' -print0
      [ -d stage_artifacts/l_code ] && find stage_artifacts/l_code -type f -name 'l_code_*.json' -print0
      find 04_Research/strategies -mindepth 3 -maxdepth 3 -type f -path '04_Research/strategies/*/stage_artifacts/l_code*.json' -print0
    } | tar --null -T - -cf - ) | tar -xf - -C "$d"
  for f in lcode_distill_plan_20260704.json lcode_family_override.json module_catalog.json \
           distilled_knowledge.json hypothesis_index.json; do
    [ -f "$DATA_ROOT/06_Registry/$f" ] && cp -p "$DATA_ROOT/06_Registry/$f" "$d/06_Registry/$f"
  done
  cp -rp "$DATA_ROOT/qepm/memory/axioms/active" "$d/qepm/memory/axioms/"
  [ -f "$DATA_ROOT/qepm/memory/axioms/tombstones.json" ] && cp -p "$DATA_ROOT/qepm/memory/axioms/tombstones.json" "$d/qepm/memory/axioms/"
  [ -f "$DATA_ROOT/.cache/failure_revival_flags.json" ] && cp -p "$DATA_ROOT/.cache/failure_revival_flags.json" "$d/.cache/"
  cp -p "$DATA_ROOT/CLAUDE.md" "$d/CLAUDE.md"
  return 0
}
mk_inputs "$P"
N_LC_SB=$(find "$P/stage_artifacts" "$P/04_Research" -type f -name 'l_code*.json' 2>/dev/null | wc -l)
[ "$N_LC_SB" -ge 1 ] && [ -d "$P/qepm/memory/axioms/active" ] && [ -f "$P/06_Registry/module_catalog.json" ] \
  && ok "R0 샌드박스 입력 사본 (L-code ${N_LC_SB}건 · registry · axioms)" \
  || bad "R0 샌드박스 입력 사본" "L-code ${N_LC_SB}건 · 원천 DATA_ROOT=$DATA_ROOT"
case "$AGENT_TOKEN" in
  *forge*|*judge*|*book*) bad "R1 고유 agent 토큰이 기본 헤더 분기" "토큰=$AGENT_TOKEN" ;;
  *) ok "R1 고유 agent 토큰이 기본 헤더 분기(원 검사 alpha-research 와 같은 렌더)" ;;
esac

# ── [Z] 운영 쓰기 검출기 ────────────────────────────────────────────────────────────
WATCH=(.cache/positive_context.json .cache/axiom_inject_last.json .cache/lcode_corpus.json
       .cache/axiom_inject_body.md .cache/axiom_inject_modelocal.md)
LEDGER_REL="qepm/observability/events.jsonl"
AX_PAT='"hook_name":"axiom_context_inject.sh"'
snap() {   # $1 = 루트 → 'rel<TAB>md5:size:mtime' | 'rel<TAB>ABSENT'
  local r="$1" f p
  for f in "${WATCH[@]}"; do
    p="$r/$f"
    if [ -e "$p" ]; then
      printf '%s\t%s:%s:%s\n' "$f" "$(md5sum < "$p" | cut -c1-32)" "$(stat -c %s "$p")" "$(stat -c %Y "$p")"
    else
      printf '%s\tABSENT\n' "$f"
    fi
  done
}
led_size() { stat -c %s "$1/$LEDGER_REL" 2>/dev/null || echo 0; }
led_head_md5() { head -c "$2" "$1/$LEDGER_REL" 2>/dev/null | md5sum | cut -c1-32; }
agent_of() { "$PY" -c "import json,sys
try:
    print(json.load(open(sys.argv[1],encoding='utf-8')).get('agent',''))
except Exception:
    print('__UNREADABLE__')" "$(cygpath -m "$1" 2>/dev/null || printf '%s' "$1")"; }
# detect <root> <snap_before_file> <W0> <W1> <S0> <S1> <head_md5_S0>
#   → 'V <설명>'(누수) / 'I <설명>'(동시 외부 쓰기 — 정보) / 'U <설명>'(판정 불가) 줄을 낸다.
detect() {
  local r="$1" sb="$2" w0="$3" w1="$4" s0="$5" s1="$6" h0="$7"
  local f before after mt ag n cur now_all
  now_all="$(snap "$r")"
  while IFS=$'\t' read -r f before; do
    after="$(printf '%s\n' "$now_all" | awk -F'\t' -v k="$f" '$1==k{print $2}')"
    [ "$before" = "$after" ] && continue
    if [ "$after" = "ABSENT" ]; then echo "V $f 삭제됨(실행 전 존재)"; continue; fi
    mt="${after##*:}"
    if [ "$f" = ".cache/axiom_inject_last.json" ]; then
      ag="$(agent_of "$r/$f")"
      if [ "$ag" = "$AGENT_TOKEN" ]; then echo "V $f 이 검사 토큰(agent=$ag)으로 기록됨"
      else echo "I $f 변경(agent=$ag — 실 스폰 기록, 이 검사 발신 아님)"; fi
      continue
    fi
    if [ "$mt" -ge $((w0-1)) ] && [ "$mt" -le $((w1+1)) ]; then
      echo "V $f 검사 창 안에서 변경(mtime=$mt ∈ [$w0,$w1])"
    else
      echo "I $f 검사 창 밖 변경(mtime=$mt — 동시 외부 쓰기)"
    fi
  done < "$sb"
  cur="$(led_size "$r")"
  if [ "$cur" -lt "$s0" ] || [ "$(led_head_md5 "$r" "$s0")" != "$h0" ]; then
    echo "U $LEDGER_REL 머리가 바뀜(회전·재작성?) — 누수 판정 불가"
  else
    n=$(tail -c +"$((s0+1))" "$r/$LEDGER_REL" 2>/dev/null | head -c "$((s1-s0))" | grep -c -F "$AX_PAT")
    [ "${n:-0}" -gt 0 ] && echo "V $LEDGER_REL 훅 단계에 $AX_PAT ${n}줄 append"
    n=$(tail -c +"$((s0+1))" "$r/$LEDGER_REL" 2>/dev/null | wc -l)
    echo "I $LEDGER_REL 검사 창 동안 타 발신 ${n}줄(다른 세션 훅 — 정상)"
  fi
  return 0
}

OPS_ROOTS=("$DATA_ROOT")
[ "$CODE_ROOT" != "$DATA_ROOT" ] && OPS_ROOTS+=("$CODE_ROOT")
OPS_SNAP=(); OPS_S0=(); OPS_S1=(); OPS_H0=()
_i=0
for r in "${OPS_ROOTS[@]}"; do
  OPS_SNAP[$_i]="$SB/ops_snap_$_i.tsv"; snap "$r" > "${OPS_SNAP[$_i]}"; _i=$((_i+1))
done
W0=$(date +%s)   # 검사 창 시작(입력 사본 뒤 — 사본은 운영을 읽기만 한다)

# 훅 1회 발화(샌드박스 루트) → additionalContext 원문(stdout). 실패 시 __BADJSON__.
#   ★샌드박스가 없으면 훅의 DIR 폴백이 **운영 루트**로 떨어진다(훅 :34-36) — 그래서 호출 전에 확인하고, 없으면 발화하지 않는다.
#   ★호출 수(N_HOOK)는 호출부에서 센다 — ctx_of 는 $( ) 서브셸에서 돌아 안에서 올린 카운터는 사라진다(초판 실측: 0회로 집계).
N_HOOK=0
ctx_of() {   # $1 = 루트(C:/… 형식)
  local root="$1"
  if [ ! -d "$root/.cache" ] || [ ! -d "$root/qepm/observability" ]; then echo "__NOSANDBOX__"; return 0; fi
  printf '%s' "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"$AGENT_TOKEN\",\"prompt\":\"t\"}}" \
    | CLAUDE_PROJECT_DIR="$root" QM_ROOT="$root" QVEST_EVENT_LEDGER=1 bash "$HOOK" 2>/dev/null \
    | "$PY" -c "
import json,sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
try:
    d=json.load(sys.stdin)
except Exception:
    print('__BADJSON__'); raise SystemExit
print(d.get('hookSpecificOutput',{}).get('additionalContext') or d.get('additionalContext') or '')
"
}

# ── 사전: 변동부 산출물 최신화 (생산자 = lcode_harvester · 샌드박스 루트) ──────────────
#   ★없으면 훅은 고정부만 낸다 = B/C 가 FAIL 한다. 그건 훅 결함이 아니라 생산자 미실행이므로
#     여기서 한 번 돌려 조건을 맞춘 뒤 잰다(생산자 실패 자체도 아래에서 드러난다).
#   ★운영 입력의 사본 위에서 운영 코드를 그대로 돌린다 — 측정 대상은 같고 쓰기 루트만 다르다.
QVEST_PROJECT_DIR="$PW" CLAUDE_PROJECT_DIR="$PW" QM_ROOT="$PW" "$PY" "$HARV" --project-dir "$PW" >/dev/null 2>&1
PC="$P/.cache/positive_context.json"
[ -f "$PC" ] && ok "positive_context 산출물 존재(샌드박스 — 사본 입력으로 방금 생성)" || bad "positive_context 산출물" "$PC 부재"
[ -f "$P/.cache/lcode_corpus.json" ] && ok "Z0 하베스터 정본 corpus 도 샌드박스에 기록" \
  || bad "Z0 하베스터 정본 corpus 샌드박스 기록" "$P/.cache/lcode_corpus.json 부재 — --project-dir 미적용?"

_i=0; for r in "${OPS_ROOTS[@]}"; do OPS_S0[$_i]=$(led_size "$r"); OPS_H0[$_i]=$(led_head_md5 "$r" "${OPS_S0[$_i]}"); _i=$((_i+1)); done
CTX=$(ctx_of "$PW"); [ "$CTX" != "__NOSANDBOX__" ] && N_HOOK=$((N_HOOK+1))
if [ "$CTX" = "__BADJSON__" ] || [ "$CTX" = "__NOSANDBOX__" ] || [ -z "$CTX" ]; then
  bad "E1 훅이 유효 JSON + 비어있지 않은 컨텍스트" "출력=[$CTX]"
  summary; exit 1
fi
ok "E1 훅이 유효 JSON + 비어있지 않은 컨텍스트"
case "$CTX" in "[AX 전제] 아래 공리는"*) ok "E0 기본 헤더 렌더(원 검사와 같은 분기)" ;;
               *) bad "E0 기본 헤더 렌더" "선두=[${CTX:0:30}]" ;; esac

# ── [A] 예산 ≤ 2,000자 ────────────────────────────────────────────────────────
#   ★bash ${#VAR} 는 로케일에 따라 바이트를 세므로 **python 으로 문자 수**를 센다
#     (한글 1자 = UTF-8 3바이트 — 바이트로 재면 초록/빨강이 뒤집힌다).
read -r NCHARS NSTR NLC NBAN <<EOF
$(printf '%s' "$CTX" | "$PY" -c "
import re,sys
c=sys.stdin.buffer.read().decode('utf-8','replace')
lines=c.splitlines()
print(len(c),
      sum(1 for l in lines if re.search(r'STR_[A-Z0-9_]+', l)),
      sum(1 for l in lines if re.search(r'L-[A-Z]+-\d', l)),
      len(re.findall(r'재제안 금지|재시도 금지', c)))
")
EOF

[ "$NCHARS" -le 2000 ] && ok "A1 주입 예산 ≤2000자 (실측 ${NCHARS}자)" \
  || bad "A1 주입 예산 ≤2000자" "실측 ${NCHARS}자 — MAX 초과"

# ── [B] 양성 지식: 전략 id 줄 ≥1 ──────────────────────────────────────────────
[ "${NSTR:-0}" -ge 1 ] && ok "B1 STR_* 전략 줄 ≥1 (실측 ${NSTR}줄)" \
  || bad "B1 STR_* 전략 줄 ≥1" "0줄 — '무엇이 통했나' 가 주입되지 않는다"

# ── [C] 최근 교훈: L-code 줄 ≥1 ───────────────────────────────────────────────
[ "${NLC:-0}" -ge 1 ] && ok "C1 L-code 교훈 줄 ≥1 (실측 ${NLC}줄)" \
  || bad "C1 L-code 교훈 줄 ≥1" "0줄 — 최근 교훈이 주입되지 않는다"

# ── [D] 극성: 금지 어휘 0건 ───────────────────────────────────────────────────
[ "${NBAN:-1}" -eq 0 ] && ok "D1 '재제안/재시도 금지' 문구 0건" \
  || bad "D1 '재제안/재시도 금지' 문구 0건" "${NBAN}건 — 금지 목록 주입으로 회귀"

# ── [E] 고정부 상시 존재 ──────────────────────────────────────────────────────
case "$CTX" in *"AX-000"*) ok "E2 active 공리 적재" ;; *) bad "E2 active 공리 적재" "AX-000 부재" ;; esac
case "$CTX" in *"고정 축"*) ok "E3 고정 제약 축 적재" ;; *) bad "E3 고정 제약 축 적재" "블록 부재" ;; esac
case "$CTX" in *"dead configs"*) ok "E4 dead 포인터 1줄 적재" ;; *) bad "E4 dead 포인터 1줄" "부재" ;; esac
case "$CTX" in *"hypothesis_index.R lookup"*) ok "E5 dead 조회 명령 동봉" ;;
                *) bad "E5 dead 조회 명령 동봉" "lookup 명령 부재 — 개수만 주면 조회 불가" ;; esac

# ── [F] 폴백(위반 주입): 변동부 파일 제거 시 고정부만, 죽지 않음 ──────────────
#   ★이 축이 없으면 "훅이 살아있음" 과 "변동부를 실제로 읽음" 이 구분되지 않는다.
#   ★제거 대상은 **샌드박스** 사본이다(구판은 운영 파일을 지웠다 — 헤더 참조).
rm -f "$PC"
CTX_F=$(ctx_of "$PW"); [ "$CTX_F" != "__NOSANDBOX__" ] && N_HOOK=$((N_HOOK+1))
if [ "$CTX_F" = "__BADJSON__" ] || [ "$CTX_F" = "__NOSANDBOX__" ] || [ -z "$CTX_F" ]; then
  bad "F1 변동부 부재 시 훅 생존" "출력=[$CTX_F]"
else
  ok "F1 변동부 부재 시 훅 생존"
fi
case "$CTX_F" in *"AX-000"*) ok "F2 폴백에도 고정부 유지" ;; *) bad "F2 폴백에도 고정부 유지" "공리 소실" ;; esac
NSTR_F=$(printf '%s' "$CTX_F" | "$PY" -c "
import re,sys
c=sys.stdin.buffer.read().decode('utf-8','replace')
print(sum(1 for l in c.splitlines() if re.search(r'STR_[A-Z0-9_]+', l)))")
[ "${NSTR_F:-1}" -eq 0 ] && ok "F3 변동부 부재 시 전략 줄 소실(=실제로 그 파일을 읽는다)" \
  || bad "F3 변동부 부재 시 전략 줄 소실" "${NSTR_F}줄 잔존 — 어딘가 하드코딩"

_i=0; for r in "${OPS_ROOTS[@]}"; do OPS_S1[$_i]=$(led_size "$r"); _i=$((_i+1)); done
W1=$(date +%s)   # 검사 창 끝(훅 단계 종료)

# ── [Z] 격리 판정 ───────────────────────────────────────────────────────────────
echo
echo "  [Z] 격리 — 운영 루트 무쓰기 · 샌드박스 도달"
# Z1 샌드박스 원장 = 훅 호출 수(발신기 qvest_emit_event 는 호출당 한 경로에만 append → 운영 0 의 직접 증거)
N_SB_AX=$(grep -c -F "$AX_PAT" "$P/$LEDGER_REL" 2>/dev/null); N_SB_AX=${N_SB_AX:-0}
[ "$N_SB_AX" -eq "$N_HOOK" ] && [ "$N_HOOK" -ge 2 ] \
  && ok "Z1 hook_fired 발신이 샌드박스 원장에 정확히 ${N_HOOK}줄(훅 호출 수)" \
  || bad "Z1 hook_fired 샌드박스 도달" "샌드박스 ${N_SB_AX}줄 vs 호출 ${N_HOOK}회"
# Z2 열화 기록(pc_status=missing)은 샌드박스에 남는다 — 구판이 운영 HARD_10 을 발화시킨 바로 그 기록
_IL_SB="$(cygpath -m "$P/.cache/axiom_inject_last.json" 2>/dev/null || echo "$P/.cache/axiom_inject_last.json")"
read -r IL_AGENT IL_PCS IL_LEN <<EOF
$("$PY" -c "import json,sys
try:
    d=json.load(open(sys.argv[1],encoding='utf-8')); print(d.get('agent',''), d.get('pc_status',''), d.get('len',''))
except Exception:
    print('__NONE__ __NONE__ 0')" "$_IL_SB")
EOF
[ "$IL_AGENT" = "$AGENT_TOKEN" ] && [ "$IL_PCS" = "missing" ] \
  && ok "Z2 [F] 열화 기록(pc_status=missing · len ${IL_LEN})은 샌드박스 axiom_inject_last 에 남음" \
  || bad "Z2 샌드박스 axiom_inject_last" "agent=$IL_AGENT pc_status=$IL_PCS"
# Z3 운영 루트 쓰기 0 (실행 전후 대조 — 판정 규칙은 헤더)
_i=0
for r in "${OPS_ROOTS[@]}"; do
  OUT_Z=$(detect "$r" "${OPS_SNAP[$_i]}" "$W0" "$W1" "${OPS_S0[$_i]}" "${OPS_S1[$_i]}" "${OPS_H0[$_i]}")
  while IFS= read -r l; do [ -n "$l" ] && [ "${l:0:1}" = "I" ] && note "    ↳ ${l:2}" "(정보)"; done <<< "$OUT_Z"
  NV=$(printf '%s\n' "$OUT_Z" | grep -c '^V ')
  NU=$(printf '%s\n' "$OUT_Z" | grep -c '^U ')
  if [ "$NV" -eq 0 ]; then
    ok "Z3 운영 루트 무쓰기 — positive_context·axiom_inject_last·events 외 3종 ($r)"
  else
    bad "Z3 운영 루트 무쓰기 ($r)" "$(printf '%s\n' "$OUT_Z" | grep '^V ' | cut -c3- | tr '\n' ';')"
  fi
  [ "$NU" -gt 0 ] && skp "Z3u 원장 머리 대조 ($r)" "$(printf '%s\n' "$OUT_Z" | grep '^U ' | cut -c3- | head -1)" "$r/$LEDGER_REL"
  _i=$((_i+1))
done

# ── [ZM·ZN] 검출기 양방향 — 디코이 루트 ─────────────────────────────────────────────
#   ZM(위반 주입): 구판 동작(운영 경로 하베스트 → 발화 → 변동부 삭제 후 발화 → 복원)을 디코이에 재현 → 누수 3종 검출.
#   ZN(음성 대조): 아무것도 안 한 디코이 → 누수 0.
D="$SB/decoy"; DW="$(cygpath -m "$D" 2>/dev/null || printf '%s' "$D")"
DN="$SB/decoy_null"
for dd in "$D" "$DN"; do
  mkdir -p "$dd/.cache" "$dd/qepm/memory/axioms" "$dd/qepm/observability"
  cp -rp "$P/qepm/memory/axioms/active" "$dd/qepm/memory/axioms/"
  cp -p "$P/CLAUDE.md" "$dd/CLAUDE.md"
  printf '{"seed":1}\n' > "$dd/.cache/positive_context.json"
  printf '{"at":"2026-01-01T00:00:00+09:00","len":1900,"agent":"seed","pc_status":"ok"}\n' > "$dd/.cache/axiom_inject_last.json"
  printf '{"seed":1}\n' > "$dd/.cache/lcode_corpus.json"
  printf '{"timestamp":"2026-01-01T00:00:00+0900","event_type":"seed","hook_name":"seed.sh","decision":"x","latency_ms":0}\n' > "$dd/$LEDGER_REL"
  touch -d '2026-01-01 00:00:00' "$dd/.cache/positive_context.json" "$dd/.cache/axiom_inject_last.json" "$dd/.cache/lcode_corpus.json"
done
snap "$D" > "$SB/decoy_snap.tsv"; snap "$DN" > "$SB/decoy_null_snap.tsv"
DS0=$(led_size "$D"); DH0=$(led_head_md5 "$D" "$DS0"); NS0=$(led_size "$DN"); NH0=$(led_head_md5 "$DN" "$NS0")
DW0=$(date +%s)
QVEST_PROJECT_DIR="$DW" CLAUDE_PROJECT_DIR="$DW" QM_ROOT="$DW" "$PY" "$HARV" --project-dir "$DW" >/dev/null 2>&1
_ctx=$(ctx_of "$DW")
cp -f "$D/.cache/positive_context.json" "$SB/decoy_pc_bak" 2>/dev/null && rm -f "$D/.cache/positive_context.json"
_ctx=$(ctx_of "$DW")
mv -f "$SB/decoy_pc_bak" "$D/.cache/positive_context.json" 2>/dev/null
DS1=$(led_size "$D"); DW1=$(date +%s)
OUT_M=$(detect "$D" "$SB/decoy_snap.tsv" "$DW0" "$DW1" "$DS0" "$DS1" "$DH0")
_mv() { printf '%s\n' "$OUT_M" | grep '^V ' | grep -c -F "$1"; }
[ "$(_mv positive_context.json)" -ge 1 ] && [ "$(_mv axiom_inject_last.json)" -ge 1 ] && [ "$(_mv events.jsonl)" -ge 1 ] \
  && ok "ZM 위반 주입(구판 동작 → 디코이): 누수 3종 검출(positive_context·axiom_inject_last·events)" \
  || bad "ZM 위반 주입 검출" "검출 결과=[$(printf '%s\n' "$OUT_M" | tr '\n' ';')]"
OUT_N=$(detect "$DN" "$SB/decoy_null_snap.tsv" "$DW0" "$(date +%s)" "$NS0" "$(led_size "$DN")" "$NH0")
[ "$(printf '%s\n' "$OUT_N" | grep -c '^[VU] ')" -eq 0 ] \
  && ok "ZN 음성 대조(무처치 디코이): 누수 0" \
  || bad "ZN 음성 대조" "검출 결과=[$(printf '%s\n' "$OUT_N" | tr '\n' ';')]"

summary
[ "$FAIL" -eq 0 ]
