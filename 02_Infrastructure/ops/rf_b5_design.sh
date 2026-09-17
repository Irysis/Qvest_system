#!/usr/bin/env bash
#==============================================================================
# rf_b5_design.sh — B5(리스크 오버레이) 블록 **매 강화 사이클 LLM 자체 설계** 레인 (v10.5 2026-09-17)
#
# 도훈 지시 2026-09-17: "매 강화 사이클마다 LLM 이 해당 강화 프로세스와 전체 리서치 아키텍처에 축적된 지식 기반으로
#   오버레이를 자체 설계" + "오버레이 한 칸에 여러 오버레이 중첩" + "오버레이층만 무한대로 탐색하는 버그 방지" + "오버레이 적대적 검증부".
#
# 흐름 (tick 안 · 러너 앞 · 조건이 안 맞으면 즉시 물러난다):
#   설정 게이트(enabled ∧ b5_design.enabled) → 대상 entry(활성 1건 또는 --redesign <BID>) → 발화 조건
#   (자동 = 다음 블록이 B5 · rf_b5_design_lib::b5_next_block_is_b5 — 러너가 순서를 아직 안 적었으면 같은 규칙으로 예측)
#   → pid-aware claim → 가드 H1~H4(원장·카탈로그·방출 원장) → 재료(날짜 제거) → claude -p(stdin · 쓰기 디렉터리 2개 · Bash/Agent 금지)
#   → 기존 arm 파일 무결성(바뀌면 복원) → 새 arm 마다: 신고·이름·중복 → 할당/compose → probe(기계 6검사)
#   → G1 적대 감사(rf_overlay_audit.sh · 다른 모델) → 등재(rf_overlay_admit_cli.R · source=b5_design)
#   → 설계 검증·최종 쓰기(rf_b5_design_lib verify — 거부된 arm 을 참조하는 칸은 뺀다 · 최소 칸 미달 = 폴백 · 기존 설계 보존).
#
# 안전 (구조로 강제):
#   ① LLM 산출은 설계 JSON 1개 + arm 파일(overlay_arms/<kind>.R · .arm.json). 카탈로그·원장·최종 설계는 R 만 쓴다.
#   ② 등재 전 거부된 arm 도 원장(overlay_arm_ledger.jsonl · admitted=false)에 남긴다 — 패자를 숨기지 않는다(H7).
#   ③ Fable 한도 → opus 폴백(rf_llm_env.sh) 직전 훅이 1차 실행이 만든 arm·설계 파일을 치운다(두 모델 합작 금지 · 실행 출력은 보존).
#   ④ auth·한도 판정은 **이번 실행 출력**만 본다(그날 로그 전체 X — 앞선 실행의 문구가 뒤의 성공을 덮는 실사고).
#      환경 실패 = 라운드 미기록(재시도 정당). 에이전트가 설계를 안 냈거나 시간초과면 **폴백 라운드로 기록**한다 —
#      미기록이면 H1 이 안 서서 매 tick 같은 LLM 호출이 반복된다(무한 탐색 방지 H8).
#   ⑤ 러너 계약: 최종 설계 = .cache/rf_block_design/<BID>_B5.json(source="b5_design_lane" · round · written_at) · 원장 b5_design$rounds ·
#      재설계면 b5_redesign{active,round,at,cells_added,base_design_cells}(rf_record_b5_redesign · 러너가 경계에서 닫는다).
#   ⑥ (2026-09-17 감사) 파일 연산은 **검증된 kind** 로만 — 구판은 이름 규약을 어긴 kind 로 rm 을 불러 `../` 경로가 레인 밖 파일을
#      지울 수 있었다. 기존 arm 파일(설계 전 스냅샷)은 LLM 이 고치거나 지우면 백업에서 복원하고 arm_existing_tampered 로 남긴다.
#      다른 레인의 arm(gen_<날짜>_<시각> · prompt_gen_*)은 새 파일이어도 건드리지 않는다(tick 이 겹치면 남의 산출을 지운다).
#   ⑦ 레인 시간 예산(QVEST_B5_LANE_BUDGET_SEC · 기본 5400초) — 넘으면 남은 arm 은 lane_budget 으로 무시·기록한다.
#      스케줄 태스크 실행 상한이 2시간이라, 감사가 길어지면 tick 이 잘려 반쪽 상태(arm 등재 · 라운드 미기록)가 남는다.
#
# 사용: bash rf_b5_design.sh                 (tick · 자동 설계 · entry 당 1회)
#       bash rf_b5_design.sh --redesign <BID> (수동 재설계 · guards.max_redesign_rounds 까지)
# 환경: QM_ROOT/QVEST_RF_ROOT(데이터 루트 · 샌드박스) · QVEST_RF_CONFIG · QVEST_RP_JLOG · RF_CLAUDE_BIN(가짜 claude · 검사) ·
#       QVEST_B5_MODEL/QVEST_B5_EFFORT(최우선) · QVEST_B5_TIMEOUT · QVEST_B5_LANE_BUDGET_SEC ·
#       감사·등재 재지정 QVEST_OA_*(rf_overlay_audit.sh 규약) · QVEST_B5_AUDIT_SH · QVEST_B5_ADMIT_CLI ·
#       QVEST_B5_IGNORE_PAUSE=1(--redesign 전용 · 전역 enabled=false 무시 · b5_design.enabled 는 못 넘는다).
#==============================================================================
set -uo pipefail
# ── 루트 2층: 코드 루트 = 이 파일의 위치(self-first) · 데이터 루트 = QVEST_RF_ROOT > QM_ROOT ─────────────
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
# 검사 돌연변이(레인 사본을 저장소 밖에 둔다)용 — 명시 재지정이 실재 코드 트리를 가리킬 때만 받는다
[ -n "${QVEST_B5_CODE_ROOT:-}" ] && [ -f "${QVEST_B5_CODE_ROOT}/02_Infrastructure/ops/rf_b5_design_lib.R" ] && CODE_ROOT="$QVEST_B5_CODE_ROOT"
ROOT="${QVEST_RF_ROOT:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
ROOT="${ROOT//\\//}"; ROOT="${ROOT%/}"
case "$ROOT" in /[A-Za-z]/*) command -v cygpath >/dev/null 2>&1 && ROOT=$(cygpath -m "$ROOT") ;; esac
case "$CODE_ROOT" in /[A-Za-z]/*) command -v cygpath >/dev/null 2>&1 && CODE_ROOT=$(cygpath -m "$CODE_ROOT") ;; esac
cd "$ROOT" || exit 1
export QM_ROOT="$ROOT"
PY="${QVEST_PY:-$CODE_ROOT/.venv_qvest_ml/Scripts/python.exe}"; [ -x "$PY" ] || PY="$CODE_ROOT/.venv_qvest_ml/Scripts/python.exe"
export QVEST_PY="$PY" PYTHONUTF8=1
CFG="${QVEST_RF_CONFIG:-$ROOT/06_Registry/reinforce_auto_config.json}"; export QVEST_RF_CONFIG="$CFG"
JLOG="${QVEST_RP_JLOG:-$ROOT/.cache/reinforce_auto_log.jsonl}"; export QVEST_RP_JLOG="$JLOG"
LOG="$ROOT/.cache/scheduler_logs/b5_design_$(date +%Y%m%d).log"
DDIR="$ROOT/.cache/rf_b5_design"
ADIR="$ROOT/02_Infrastructure/reinforcement/overlay_arms"
CAT_P="$ROOT/06_Registry/overlay_catalog.json"
CLAIM="$ROOT/.cache/rf_b5_design.claim"
LIB="$CODE_ROOT/02_Infrastructure/ops/rf_b5_design_lib.R"
ADMIT_CLI="${QVEST_B5_ADMIT_CLI:-$CODE_ROOT/02_Infrastructure/ops/rf_overlay_admit_cli.R}"
AUDIT_SH="${QVEST_B5_AUDIT_SH:-$CODE_ROOT/02_Infrastructure/ops/rf_overlay_audit.sh}"
mkdir -p "$(dirname "$LOG")" "$(dirname "$JLOG")" "$DDIR" "$ADIR"
export QVEST_B5_CODE_ROOT="$CODE_ROOT"
# ★샌드박스/명시 루트 — 자식 Rscript 는 ~/.Renviron 의 QM_ROOT 가 상속값을 **덮는다**(2026-09-17 실사고: 검사 자식이 운영 원장에 썼다).
#   데이터 루트가 코드 루트와 다르거나 QVEST_RF_ROOT 가 주어졌으면 빈 환경파일을 물려 QM_ROOT(=ROOT)·QVEST_PY 가 살아남게 한다.
#   (운영 = 두 루트가 같다 = 종전 그대로. ~/.Renviron 의 키는 QM_ROOT·QVEST_PY·PYTHONUTF8 셋이고 셋 다 위에서 export 했다.)
if [ -n "${QVEST_RF_ROOT:-}" ] || [ "$ROOT" != "$CODE_ROOT" ]; then
  export QVEST_RF_ROOT="$ROOT"
  : > "$DDIR/.Renviron.empty"; export R_ENVIRON_USER="$DDIR/.Renviron.empty"
fi
T0=$(date +%s)

jl() { local ev="$1"; shift
  JL_EV="$ev" JL_FILE="$JLOG" "$PY" - "$@" <<'PYEOF' 2>/dev/null || true
import io, json, os, sys, datetime
d = {'ts': datetime.datetime.now().astimezone().isoformat(timespec='seconds'), 'event': os.environ['JL_EV'], 'src': 'b5_design'}
for kv in sys.argv[1:]:
    k, _, v = kv.partition('='); d[k] = v
io.open(os.environ['JL_FILE'], 'a', encoding='utf-8').write(json.dumps(d, ensure_ascii=False) + '\n')
PYEOF
  echo "[b5_design] $ev $*" >> "$LOG"; }

# ── 인자 ──────────────────────────────────────────────────────────────────────
MODE="auto"; BID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --redesign) MODE="redesign"; BID="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    *) echo "usage: rf_b5_design.sh [--redesign <BID>]"; exit 2 ;;
  esac
done
[ "$MODE" = "redesign" ] && [ -z "$BID" ] && { echo "usage: rf_b5_design.sh --redesign <BID>"; exit 2; }
case "$BID" in *[!A-Za-z0-9_.-]*) echo "invalid base_id: $BID"; exit 2 ;; esac

# ── 설정 게이트 (b5_design.enabled 는 **명시적 true** 만 · 부재 = 꺼짐 — b1_design 규약) ───────────────────
read -r EN_ALL EN_B5 MAXC MINC MAXL <<<"$(CFG="$CFG" "$PY" - <<'PYEOF' 2>/dev/null | tr -d '\r'
import io, json, os
try: c = json.loads(io.open(os.environ['CFG'], 'rb').read().decode('utf-8'))
except Exception: c = {}
b = c.get('b5_design') or {}
def iv(k, d):
    try: return int(b.get(k)) if b.get(k) is not None else d
    except Exception: return d
print('1' if c.get('enabled') is True else '0', '1' if b.get('enabled') is True else '0', iv('max_cells', 8), iv('min_cells', 3), iv('max_layers', 3))
PYEOF
)"
[ -n "${EN_ALL:-}" ] || { EN_ALL=0; EN_B5=0; MAXC=8; MINC=3; MAXL=3; }
[ "${EN_B5:-0}" = "1" ] || { jl halt_disabled "why=b5_design.enabled 가 true 가 아니다"; exit 0; }
if [ "${EN_ALL:-0}" != "1" ]; then
  if [ "$MODE" = "redesign" ] && [ "${QVEST_B5_IGNORE_PAUSE:-0}" = "1" ]; then
    jl pause_ignored "mode=redesign" "base_id=$BID" "note=전역 enabled=false 지만 수동 재설계(QVEST_B5_IGNORE_PAUSE=1) — 러너는 여전히 정지"
  else jl halt_disabled "why=enabled=false" "mode=$MODE"; exit 0; fi
fi

# ── 대상 entry · 발화 조건 (R 1회 기동) ───────────────────────────────────────────────
if [ "$MODE" = "auto" ]; then
  DUE_LINE=$(Rscript "$LIB" due 2>>"$LOG" | tr -d '\r' | tail -1)
  IFS=$'\t' read -r BID NEED WHY <<<"$DUE_LINE"
  [ -n "${BID:-}" ] && [ "$BID" != "-" ] || { jl not_due "why=${WHY:-활성 entry 없음}"; exit 0; }
  [ "${NEED:-0}" = "1" ] || { jl not_due "base_id=$BID" "why=${WHY:-due 판정 실패}"; exit 0; }
fi
CLAUDE_BIN="${RF_CLAUDE_BIN:-claude}"
command -v "$CLAUDE_BIN" >/dev/null 2>&1 || { jl halt_no_claude_cli "base_id=$BID"; exit 0; }

# ── claim (pid-aware · 소유자 = 이 레인의 Windows pid · 생존 판정 = rf_claim.R 정본 · proc_start 대조) ─────────────
WINPID=$(cat /proc/$$/winpid 2>/dev/null || echo $$)
CSTALE=$(CFG="$CFG" "$PY" -c "
import io,json,os
try: v=float(json.loads(io.open(os.environ['CFG'],'rb').read().decode('utf-8')).get('claim_stale_hours',6)); print(int(v) if v>=1 else 6)
except Exception: print(6)" 2>/dev/null | tr -d '\r'); case "$CSTALE" in ''|*[!0-9]*) CSTALE=6;; esac
CL_TMP="$DDIR/.claim_out.$$"
Rscript "$LIB" claim "$CLAIM" "$WINPID" "$CSTALE" > "$CL_TMP" 2>>"$LOG"; CL_RC=$?
CL_OUT=$(tr -d '\r' < "$CL_TMP" | tail -1); rm -f "$CL_TMP"
[ "$CL_RC" -eq 0 ] || { jl halt_claimed "base_id=$BID" "claim=$CL_OUT"; exit 0; }
ARM_BACKUP=""
cleanup() {
  [ -n "$ARM_BACKUP" ] && rm -rf "$ARM_BACKUP" 2>/dev/null
  Rscript "$LIB" release "$CLAIM" >>"$LOG" 2>&1 || jl claim_release_failed "base_id=$BID"
}
trap cleanup EXIT

# ── 가드 H1~H4 (판정·사유는 lib 가 jlog 에 남긴다) ────────────────────────────────
GDIR="$DDIR/$BID"; mkdir -p "$GDIR"
GJSON="$GDIR/guards_$MODE.json"; rm -f "$GJSON"        # ★낡은 판정 파일을 읽지 않는다(가드가 죽으면 파일이 없어야 한다)
Rscript "$LIB" guards "$BID" "$MODE" "$GJSON" >>"$LOG" 2>&1; G_RC=$?
[ -s "$GJSON" ] || { jl guards_failed "base_id=$BID" "rc=$G_RC" "note=entry 부재(rc 2) 또는 가드 실행 실패"; exit 1; }
read -r G_OK G_WHY COMPOSE QUOTA ROUND <<<"$(GJ="$GJSON" "$PY" - <<'PYEOF' 2>/dev/null | tr -d '\r'
import io, json, os
g = json.load(io.open(os.environ['GJ'], encoding='utf-8'))
print('1' if g.get('ok') is True else '0', g.get('refuse_reason') or '-', '1' if g.get('compose_only') is True else '0', int(g.get('arm_quota') or 0), int(g.get('round') or 1))
PYEOF
)"
[ "${G_OK:-0}" = "1" ] || { jl b5_design_refused "base_id=$BID" "mode=$MODE" "why=${G_WHY:-guards_unreadable}"; exit 0; }
case "${QUOTA:-}" in ''|*[!0-9]*) QUOTA=0 ;; esac
case "${ROUND:-}" in ''|*[!0-9]*) jl guards_failed "base_id=$BID" "why=round 판독 실패"; exit 1 ;; esac
[ "$COMPOSE" = "1" ] && QUOTA=0
jl b5_design_start "base_id=$BID" "mode=$MODE" "round=$ROUND" "compose_only=$COMPOSE" "arm_quota=$QUOTA" "max_cells=$MAXC" "max_layers=$MAXL"

# ── 재료 ─────────────────────────────────────────────────────────────────────
MAT="$GDIR/materials_r${ROUND}.txt"; rm -f "$MAT"
Rscript "$LIB" materials "$BID" "$MAT" "$COMPOSE" "$QUOTA" "$ROUND" >>"$LOG" 2>&1 || { jl materials_failed "base_id=$BID" "round=$ROUND"; exit 1; }
[ -s "$MAT" ] || { jl materials_failed "base_id=$BID" "round=$ROUND" "why=빈 파일"; exit 1; }

# ── 프롬프트 (stdin — argv 는 Windows 32K 에서 조용히 죽는다) ─────────────────────
DESIGN="$GDIR/design_r${ROUND}.json"; rm -f "$DESIGN"   # ★이전 실행이 남긴 설계를 이번 산출로 읽지 않는다
PF="$GDIR/prompt_r${ROUND}.txt"
{
cat <<'EOF'
너는 최정상급 퀀트 리서처다. 이 전략의 **B5 리스크 오버레이 블록**을 설계하라 — 이번 강화 사이클에서 무엇을 어떻게 잴지.
냉소는 방법론(과적합·스누핑·시점오염)을 향한다. 실증 성과를 폄하하지 않되, 개선이 타이밍에서 왔다는 명제는 반증을 견뎌야 한다.

## 무엇을 설계하는가
1. **칸(cells)** — 기존 활성 arm 을 고르거나 **여러 arm 을 한 칸에 중첩(스택)** 한다. 엔진은 층 노출을 종목별 곱으로 합성한다.
   각 칸은 "무엇을 가르는가" 가 분명해야 한다(같은 스택을 두 칸에 쓰면 칸 낭비 · 상주 칸은 넣지 마라).
   스칼라 현금 타이밍 층 × 종목별 차등 층 같이 **소비 지점이 다른 층**의 결합이 이 축의 미측정 내용이다.
2. **새 arm(new_arms)** — 필요할 때만, 할당 수 안에서. 기존 arm 의 상수만 바꾼 것·라벨만 다른 것은 G1 감사가 중복으로 거부한다.
   새 arm 은 아래 계약대로 파일 2개(overlay_arms/<kind>.R + <kind>.arm.json)를 **새로** 쓰고 new_arms 에 신고한다.
   신고 없는 파일은 지워지고 원장에 남는다. **기존 arm 파일은 읽기만 하라** — 고치거나 지우면 복원되고 위반으로 기록된다.
   할당이 0 이거나 compose_only 면 새 arm 을 내지 마라 — 내도 무시·삭제되고 원장에 남는다.

## 읽는 순서
재료의 (1) 이 entry 측정표 → (2) 바닥 낙폭 해부(급락형인가 침식형인가 · 벤치 대비 비) → (3) arm 성과 이력 → (4) 앞선 논문들의 B5 교훈 →
(5) 증류 지식 → (6) 기전 지도·활성 카탈로그 → (7) 계약·중첩 의미론·PIT·금칙·검증부 → (8) 가드 상태. 공리는 전제다.
★수치는 이 entry 의 것이고, 남의 entry 수치는 기전만 옮겨 붙는다. ★재료의 날짜는 지워져 있다 — 설계는 특정 시기에 기대면 안 된다.

EOF
cat "$MAT"
cat <<EOF

## 산출 (이것만) — 아래 파일을 Write 로 써라
B5_DESIGN_OUTPUT_FILE=${DESIGN}
B5_ARM_DIR=${ADIR}
B5_ARM_QUOTA=${QUOTA}
B5_COMPOSE_ONLY=${COMPOSE}
스키마:
{
  "schema": "rf_b5_design_v1",
  "base_id": "${BID}",
  "round": ${ROUND},
  "rationale": "이 entry 의 낙폭이 어디서 오고(기전) 그래서 어느 소비 지점에서 무엇을 곱하는지 2~4줄",
  "cells": [
    {"picks": ["<활성 arm id>", "<활성 arm id>"], "label": "짧은 이름", "why": "이 칸이 무엇을 가르는가 1~2줄"}
  ],
  "new_arms": [
    {"kind": "b5gen_<short>_${ROUND}", "id": "<고유 id>", "action": "cross_sectional|scalar_exposure",
     "state": "vol|drawdown|multivar|ml|trend|dispersion|holding_level", "family": "<계열>",
     "basis": "무엇을 어떻게 추정하는지 · 기존 arm 과 무엇이 다른지 3~6문장", "external_data": "none 또는 어떤 외부 패널을 어떤 컷오프로"}
  ]
}
- cells: ${MINC}~${MAXC}칸 · 각 칸 층 1~${MAXL} · picks 는 재료 (6) 의 활성 id **또는** 이번에 신고한 new_arms 의 id 만 · 같은 kind 두 층 금지 ·
  칸끼리 같은 스택 금지 · 이미 측정된 스택(재료 (1) 의 B5 칸 스택 열)을 다시 넣지 마라(검증이 빼고, 유효 칸이 ${MINC} 미만이면 설계 전체가 폴백된다).
  등재 거부된 새 arm 을 참조한 칸은 자동으로 빠진다 — 새 arm 에만 기대는 설계는 그 arm 이 떨어지면 함께 무너진다.
- new_arms: 최대 ${QUOTA}개 · kind 는 정규식 ^b5gen_[a-z0-9_]{1,40}_${ROUND}\$ 이고 카탈로그·arm 디렉터리에 **없는** 이름 ·
  파일 ${ADIR}/<kind>.R 에 함수 overlay_expo_<kind>(H, t, ctx) 하나 ·
  ${ADIR}/<kind>.arm.json 에 {"id","family","action","state","basis","est_cost_min","external_data"} — **id 는 new_arms 에 신고한 id 와 같아야 한다** · basis 는 비면 거부된다.
  본보기 = ${ADIR}/dbeta_tilt.R (종목별) · ${ADIR}/pg2_risk_overlay.R (외부 패널 + PIT 가드).
- ★모든 새 arm 은 probe(계약·측정누출·리터럴·달력·fwd 섭동·처치) → G1 적대 감사(leak/degenerate/duplicate · 다른 모델) → 등재를 지나야
  설계에 남는다. 측정 뒤엔 G2 반증(lag-1·strict-PIT·노출 짝지은 placebo·정적 등가)이 pass 인 칸만 소비된다.

## 금지
- ${GDIR} · ${ADIR} 밖 쓰기. 기존 arm 파일 수정·삭제. 원장·설정·카탈로그·훅·테스트·엔진 수정. 백테스트 실행(측정은 계약이 한다). 등급·성과 수치 선언.
- 카탈로그에 없는 id 를 picks 에 쓰는 것.
- arm 소스에 성과 토큰·리터럴 문턱·달력 리터럴·H\$fwd[t] 읽기(재료 (7) 금칙).

설계 파일(과 새 arm 파일)을 쓰고, 무엇을 시험하려는지 2~3줄로만 보고하라.
EOF
} > "$PF"

# ── 스냅샷: 새 파일 판별 · 기존 arm 파일 백업/해시 · 등록부 해시 ──────────────────────────
snap_files() { for f in "$ADIR"/* "$GDIR"/*; do [ -f "$f" ] && printf '%s\n' "$f"; done | LC_ALL=C sort; }
SNAP_BEFORE="$GDIR/.snap_before_r${ROUND}.txt"; snap_files > "$SNAP_BEFORE"
new_files() { snap_files | LC_ALL=C comm -13 "$SNAP_BEFORE" - ; }
existed_before() { grep -qxF "$1" "$SNAP_BEFORE"; }
is_run_output() { case "$(basename "$1")" in run_r*.out|run_r*.out.primary|.snap_*|guards_*|materials_r*|prompt_r*|new_arms_r*|audit_*.out|probe_*.out|.arms_*|.claim_out.*) return 0 ;; esac; return 1; }
is_foreign_arm() { case "$(basename "$1")" in gen_[0-9]*_[0-9]*.R|gen_[0-9]*_[0-9]*.arm.json|prompt_gen_*) return 0 ;; esac; return 1; }
ARM_MANIFEST="$GDIR/.arms_manifest_r${ROUND}.md5"; ARM_BACKUP="$GDIR/.arms_backup_r${ROUND}"
rm -rf "$ARM_BACKUP"; mkdir -p "$ARM_BACKUP"
( cd "$ADIR" && for f in *; do [ -f "$f" ] && printf '%s\n' "$f"; done ) > "$GDIR/.arms_list_r${ROUND}.txt"
: > "$ARM_MANIFEST"
while IFS= read -r f; do cp -p "$ADIR/$f" "$ARM_BACKUP/$f" 2>/dev/null; done < "$GDIR/.arms_list_r${ROUND}.txt"
( cd "$ADIR" && xargs -d '\n' -r md5sum < "$GDIR/.arms_list_r${ROUND}.txt" ) > "$ARM_MANIFEST" 2>/dev/null
REG_FILES=("$CAT_P" "$ROOT/06_Registry/reinforce_ledger_l1.json" "$ROOT/06_Registry/overlay_arm_ledger.jsonl" "$CFG")
reg_hash() { local f; for f in "${REG_FILES[@]}"; do printf '%s %s\n' "$( [ -f "$f" ] && md5sum "$f" | cut -d' ' -f1 || echo absent)" "$(basename "$f")"; done; }
REG_BEFORE=$(reg_hash)
#   새 산출(설계·arm·LLM 잔재)만 지운다 — 실행 출력·레인 기록·남의 arm 은 남긴다. 출력 = 지운 파일 이름들.
remove_new_outputs() {
  local f removed=""
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    is_run_output "$f" && continue
    case "$f" in "$ADIR"/*) is_foreign_arm "$f" && continue ;; esac
    rm -f "$f" && removed="$removed $(basename "$f")"
  done < <(new_files)
  printf '%s' "$removed"
}
#   기존 arm 파일이 바뀌거나 사라졌으면 백업에서 복원한다(측정된 arm 의 소스가 바뀌면 과거 측정이 다른 코드의 측정이 된다).
restore_tampered() {
  local line f changed=""
  while IFS= read -r line; do
    case "$line" in *": OK") continue ;; esac
    f="${line%%: FAILED*}"; [ -n "$f" ] && [ "$f" != "$line" ] || continue
    [ -f "$ARM_BACKUP/$f" ] && cp -p "$ARM_BACKUP/$f" "$ADIR/$f" && changed="$changed $f"
  done < <( cd "$ADIR" && md5sum -c "$ARM_MANIFEST" 2>/dev/null )
  [ -n "$changed" ] && jl arm_existing_tampered "base_id=$BID" "round=$ROUND" "restored=${changed# }" "note=기존 arm 파일은 읽기 전용 — 백업에서 복원"
  return 0
}

# ── 실행 (모델 = 설정 llm.lanes.b5_design · Fable 한도 → opus 폴백 · 훅이 1차 산출을 치운다) ──────────────
. "$CODE_ROOT/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve b5_design "${QVEST_B5_MODEL:-}" "${QVEST_B5_EFFORT:-}"
rf_llm_before_fallback() {
  local moved; restore_tampered; moved=$(remove_new_outputs)
  jl model_fallback "base_id=$BID" "from=$LLM_MODEL" "to=$LLM_FALLBACK_MODEL" "effort=$LLM_FALLBACK_EFFORT" "why=limit_in_run_output" "removed=${moved:- none}"
}
RUN_OUT="$GDIR/run_r${ROUND}.out"
jl model_selected "base_id=$BID" "model=$LLM_MODEL" "effort=$LLM_EFFORT" "fallback=${LLM_FALLBACK_MODEL:-none}"
rf_llm_agent_run "$PF" "$RUN_OUT" "${QVEST_B5_TIMEOUT:-2400}" \
  --permission-mode acceptEdits \
  --allowed-tools "Read,Write,Edit,Glob,Grep" \
  --disallowed-tools "Bash,Agent" \
  --add-dir "$ADIR" --add-dir "$GDIR"
RC=$LLM_RC
[ -f "$RUN_OUT.primary" ] && cat "$RUN_OUT.primary" >> "$LOG"
cat "$RUN_OUT" >> "$LOG" 2>/dev/null
jl agent_done "base_id=$BID" "rc=$RC" "model=$LLM_USED_MODEL" "effort=$LLM_USED_EFFORT" "fell_back=$LLM_FELL_BACK"
restore_tampered
REG_AFTER=$(reg_hash)
if [ "$REG_BEFORE" != "$REG_AFTER" ]; then
  jl registry_changed_during_agent "base_id=$BID" "changed=$(diff <(printf '%s\n' "$REG_BEFORE") <(printf '%s\n' "$REG_AFTER") | grep '^>' | awk '{print $3}' | tr '\n' ' ')" \
     "note=에이전트 실행 중 등록부가 바뀌었다 — 레인은 쓰지 않았다(동시 세션 또는 계약 위반) · 복원하지 않는다"
fi

# ★환경 실패 — 이번 실행 출력만 본다. 설계 없음 · 반쪽 산출 제거 · 라운드 미기록(재시도 정당).
ENV_FAIL=""
if grep -qE "OAuth access token has expired|Failed to authenticate|API Error: 401|Invalid API key" "$RUN_OUT" 2>/dev/null; then ENV_FAIL="auth_expired"
elif rf_llm_limit_hit "$RUN_OUT"; then ENV_FAIL="model_quota_exhausted"; fi
if [ -n "$ENV_FAIL" ]; then
  REMOVED=$(remove_new_outputs)
  jl halt_env_failure "base_id=$BID" "kind=$ENV_FAIL" "round=$ROUND" "removed=${REMOVED:- none}" "hint=환경 실패 — 리서치 판정 아님 · 설계·라운드 없음 · 다음 tick 재시도"; exit 2
fi
if [ ! -s "$DESIGN" ]; then
  jl no_design_file "base_id=$BID" "round=$ROUND" "rc=$RC" "note=에이전트가 설계를 안 냈다(시간초과 rc=124 포함) — 폴백 라운드로 기록해 같은 호출의 반복을 막는다"
fi

# ── 새 arm 처리: 신고 목록 판독(이름·중복·메타) → 미신고 파일 삭제·기록 → 할당/compose/예산 → probe → G1 감사 → 등재 ─────────────
ARMS_TSV="$GDIR/new_arms_r${ROUND}.tsv"
DESIGN="$DESIGN" OUT="$ARMS_TSV" ADIR="$ADIR" CATP="$CAT_P" SNAP="$SNAP_BEFORE" ROUND_N="$ROUND" "$PY" - <<'PYEOF' 2>>"$LOG" || : > "$ARMS_TSV"
import io, json, os, re
def clean(s, n=80): return re.sub(r'[\t\r\n]+', ' ', str(s or '')).strip()[:n]
try: d = json.load(io.open(os.environ['DESIGN'], encoding='utf-8'))
except Exception: d = {}
try: cat = json.load(io.open(os.environ['CATP'], encoding='utf-8')).get('arms') or []
except Exception: cat = []
cat_ids = {str(a.get('id') or '') for a in cat}; cat_kinds = {str(a.get('kind') or '') for a in cat}
try: before = {os.path.basename(l.strip()) for l in io.open(os.environ['SNAP'], encoding='utf-8') if l.strip()}
except Exception: before = set()
adir, rnd = os.environ['ADIR'], os.environ['ROUND_N']
rows, seen_k, seen_i = [], set(), set()
arms = d.get('new_arms') if isinstance(d, dict) else None
for a in (arms if isinstance(arms, list) else []):
    if not isinstance(a, dict): continue
    kind, aid = clean(a.get('kind'), 120), clean(a.get('id'), 120)
    act, st = clean(a.get('action'), 40), clean(a.get('state'), 40)
    if not re.match(r'^b5gen_[a-z0-9_]{1,40}_%s$' % re.escape(rnd), kind) or not re.match(r'^[A-Za-z0-9_]{3,60}$', aid):
        status = 'invalid_name'
    elif kind in seen_k: status = 'dup_kind_in_design'     # 파일은 앞선 신고의 것 — 지우지 않는다
    elif aid in seen_i: status = 'dup_id_in_design'
    elif kind in cat_kinds or (kind + '.R') in before or (kind + '.arm.json') in before: status = 'dup_kind'
    elif aid in cat_ids: status = 'dup_id'
    elif not os.path.isfile(os.path.join(adir, kind + '.R')): status = 'missing_file'
    else:
        mp = os.path.join(adir, kind + '.arm.json')
        try: meta = json.load(io.open(mp, encoding='utf-8'))
        except Exception: meta = None
        if not isinstance(meta, dict): status = 'missing_meta'
        elif str(meta.get('id') or '') != aid: status = 'id_mismatch'
        else: status = 'ok'
    if status != 'invalid_name': seen_k.add(kind); seen_i.add(aid)
    rows.append('\t'.join([kind or '-', aid or '-', act or '-', st or '-', status]))
io.open(os.environ['OUT'], 'w', encoding='utf-8', newline='').write('\n'.join(rows) + ('\n' if rows else ''))
PYEOF
# 신고된 **유효 이름** kind — 이 목록의 파일은 아래 루프가 판정한다(파일 연산은 이 이름으로만)
DECLARED_VALID=" $(awk -F'\t' '$5!="invalid_name"{print $1}' "$ARMS_TSV" 2>/dev/null | tr '\n' ' ') "
# 이름 규약을 어긴 신고 kind — 파일은 미신고 정리가 지우되 방출 기록은 루프(stage=invalid_name) 한 번만 남긴다(이중 기록 = 일간 상한 이중 산입)
DECLARED_INVALID=" $(awk -F'\t' '$5=="invalid_name"{print $1}' "$ARMS_TSV" 2>/dev/null | tr '\n' ' ') "
# 방출 수(n_siblings) = 신고 kind ∪ 새 .R 파일(남의 arm 제외) — selection_type 은 이 수에서 구조적으로 나온다
N_EMIT=$( { awk -F'\t' '{print $1}' "$ARMS_TSV" 2>/dev/null
            while IFS= read -r f; do case "$f" in "$ADIR"/*.R) is_foreign_arm "$f" || basename "$f" .R ;; esac; done < <(new_files); } | grep -v '^-$' | LC_ALL=C sort -u | grep -c . )
case "${N_EMIT:-}" in ''|*[!0-9]*|0) N_EMIT=1 ;; esac
rec_emit() {   # kind action state stage reason
  Rscript "$LIB" record_emission "$1" "${2:--}" "${3:--}" "$LLM_USED_MODEL" "$N_EMIT" "$4" "$5" >>"$LOG" 2>&1 || jl emission_record_failed "base_id=$BID" "kind=$1" "stage=$4"
}
drop_arm() {   # 검증된 kind 의 **새** 파일만 지운다 — 설계 전부터 있던 파일(남의 arm)은 절대 지우지 않는다
  local k="$1" x
  case " $DECLARED_VALID " in *" $k "*) ;; *) return 0 ;; esac
  for x in "$ADIR/$k.R" "$ADIR/$k.arm.json"; do existed_before "$x" || rm -f "$x"; done
}
# 미신고 파일 — 설계자가 new_arms 에 안 적은(또는 이름 규약을 어긴) 새 파일은 지우고, .R 이면 원장에 남긴다
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  case "$f" in "$ADIR"/*) ;; *) continue ;; esac
  if is_foreign_arm "$f"; then jl arm_foreign_skipped "base_id=$BID" "file=$(basename "$f")" "note=다른 레인의 산출 이름 — 건드리지 않는다"; continue; fi
  b=$(basename "$f"); k="${b%.arm.json}"; k="${k%.R}"
  case " $DECLARED_VALID " in *" $k "*) continue ;; esac
  case " $DECLARED_INVALID " in *" $k "*) rm -f "$f"; continue ;; esac
  if [ "${b%.R}" != "$b" ]; then
    jl arm_undeclared "base_id=$BID" "kind=$k"
    rec_emit "$k" "-" "-" undeclared "설계 JSON new_arms 에 유효 이름으로 신고되지 않은 파일"
  fi
  rm -f "$f"
done < <(new_files)

ADMITTED=""; REJECTED=""; N_DONE=0
add_rej() { [ -n "${1:-}" ] && [ "$1" != "-" ] && REJECTED="${REJECTED:+$REJECTED,}$1"; return 0; }
OA_AXES="${QVEST_OA_AXES:-$ROOT/06_Registry/rf_overlay_adversary_axes.json}"; [ -f "$OA_AXES" ] || OA_AXES="$CODE_ROOT/06_Registry/rf_overlay_adversary_axes.json"
export QVEST_OA_LOG="${QVEST_OA_LOG:-$ROOT/.cache/scheduler_logs/overlay_audit_$(date +%Y%m%d).log}"
BUDGET="${QVEST_B5_LANE_BUDGET_SEC:-5400}"; case "$BUDGET" in ''|*[!0-9]*) BUDGET=5400 ;; esac
while IFS=$'\t' read -r KIND AID ACT ST STATUS <&3; do
  [ -n "${KIND:-}" ] || continue
  case "$STATUS" in
    ok) ;;
    invalid_name)
      jl arm_rejected "base_id=$BID" "kind=$KIND" "id=$AID" "stage=invalid_name" "why=kind 는 ^b5gen_[a-z0-9_]{1,40}_${ROUND}\$ · id 는 [A-Za-z0-9_]{3,60}"
      rec_emit "$KIND" "$ACT" "$ST" invalid_name "이름 규약 위반(파일 연산 없음 — 새 파일은 미신고 정리가 지운다)"
      add_rej "$AID"; continue ;;
    missing_file)
      jl arm_rejected "base_id=$BID" "kind=$KIND" "id=$AID" "stage=missing_file"
      rec_emit "$KIND" "$ACT" "$ST" missing_file "신고됐으나 arm 파일 부재"; add_rej "$AID"; continue ;;
    dup_kind_in_design)
      # ★같은 kind 의 파일은 앞선 신고의 것이다(이미 등재됐을 수 있다) — 지우지 않는다. id 도 거부 목록에 넣지 않는다(앞선 신고와 같을 수 있다).
      jl arm_rejected "base_id=$BID" "kind=$KIND" "id=$AID" "stage=dup_kind_in_design" "note=같은 설계 안 kind 중복 — 파일은 앞선 신고 몫"
      rec_emit "$KIND" "$ACT" "$ST" dup_kind_in_design "같은 설계 안에서 kind 를 두 번 신고"; continue ;;
    dup_kind|dup_id|dup_id_in_design)
      # ★id 를 거부 목록에 넣지 않는다 — 그 id 는 기존 카탈로그 arm 또는 앞선 신고의 것이고, 설계 칸이 그 arm 을 정당하게 쓸 수 있다.
      #   (거부 목록은 verify 가 칸을 빼는 근거다. 없는 id 는 카탈로그 대조가 어차피 뺀다.)
      jl arm_rejected "base_id=$BID" "kind=$KIND" "id=$AID" "stage=$STATUS"
      rec_emit "$KIND" "$ACT" "$ST" "$STATUS" "신고 판독 거부: $STATUS"; drop_arm "$KIND"; continue ;;
    *)
      jl arm_rejected "base_id=$BID" "kind=$KIND" "id=$AID" "stage=$STATUS"
      rec_emit "$KIND" "$ACT" "$ST" "$STATUS" "신고 판독 거부: $STATUS"; drop_arm "$KIND"; add_rej "$AID"; continue ;;
  esac
  if [ "$COMPOSE" = "1" ] || [ "$N_DONE" -ge "$QUOTA" ]; then
    STAGE=$([ "$COMPOSE" = "1" ] && echo compose_only || echo quota)
    jl arm_ignored "base_id=$BID" "kind=$KIND" "id=$AID" "stage=$STAGE" "quota=$QUOTA" "done=$N_DONE"
    rec_emit "$KIND" "$ACT" "$ST" "$STAGE" "가드 — compose_only=$COMPOSE quota=$QUOTA"
    drop_arm "$KIND"; add_rej "$AID"; continue
  fi
  if [ $(( $(date +%s) - T0 )) -gt "$BUDGET" ]; then
    jl arm_ignored "base_id=$BID" "kind=$KIND" "id=$AID" "stage=lane_budget" "elapsed=$(( $(date +%s) - T0 ))" "budget=$BUDGET"
    rec_emit "$KIND" "$ACT" "$ST" lane_budget "레인 시간 예산 초과 — 감사 미실행"
    drop_arm "$KIND"; add_rej "$AID"; continue
  fi
  N_DONE=$((N_DONE + 1))
  # ① probe — 기계 6검사 (백테 0 소모) · 종료 코드는 파일 경유로 받는다(파이프 안 PIPESTATUS 는 밖에서 못 읽는다)
  POUT="$GDIR/probe_${KIND}.out"
  Rscript "$LIB" probe "$KIND" "$ST" > "$POUT" 2>>"$LOG"; PR_RC=$?
  PR_LINE=$(tr -d '\r' < "$POUT" | grep '^probe:' | tail -1)
  PR_AXIS=$(printf '%s' "$PR_LINE" | awk -F' [|] ' '{print $3}'); PR_ST=$(printf '%s' "$PR_LINE" | awk -F' [|] ' '{print $4}')
  PR_WHY=$(printf '%s' "$PR_LINE" | awk -F' [|] ' '{print $5}')
  if [ "$PR_RC" -eq 3 ]; then
    jl arm_probe_fail "base_id=$BID" "kind=$KIND" "id=$AID" "why=${PR_WHY:-?}"
    rec_emit "$KIND" "$ACT" "$ST" probe "${PR_WHY:-probe fail}"; drop_arm "$KIND"; add_rej "$AID"; continue
  elif [ "$PR_RC" -ne 0 ] || [ -z "$PR_LINE" ]; then
    jl arm_probe_error "base_id=$BID" "kind=$KIND" "id=$AID" "rc=$PR_RC" "note=probe 미실행 = 등재 금지"
    rec_emit "$KIND" "$ACT" "$ST" probe_error "probe 실행 실패 rc=$PR_RC"; drop_arm "$KIND"; add_rej "$AID"; continue
  fi
  case "$PR_AXIS" in cross_sectional|scalar_exposure) [ "$PR_AXIS" != "$ACT" ] && jl arm_action_from_probe "kind=$KIND" "declared=$ACT" "probe=$PR_AXIS"; ACT="$PR_AXIS" ;; esac
  [ -n "$PR_ST" ] && [ "$PR_ST" != "$ST" ] && { jl arm_state_defaulted "kind=$KIND" "declared=$ST" "used=$PR_ST"; ST="$PR_ST"; }
  # ② G1 적대 감사 — 설계자와 다른 모델(설정 llm.lanes.overlay_audit) · 판정 = 마지막 줄 · 0 pass · 3 reject · 4 unavailable
  AOUT="$GDIR/audit_${KIND}.out"
  QVEST_RF_ROOT="$CODE_ROOT" QM_ROOT="$CODE_ROOT" QVEST_OA_ARMDIR="$ADIR" QVEST_OA_CATALOG="${QVEST_OA_CATALOG:-$CAT_P}" QVEST_OA_AXES="$OA_AXES" \
    QVEST_OA_OUT="${QVEST_OA_OUT:-$ROOT/.cache/rf_overlay_audit}" bash "$AUDIT_SH" "$KIND" > "$AOUT" 2>&1; A_RC=$?
  A_LINE=$(tr -d '\r' < "$AOUT" | grep '^audit:' | tail -1)
  if [ "$A_RC" -eq 3 ]; then
    jl arm_audit_reject "base_id=$BID" "kind=$KIND" "id=$AID" "verdict=${A_LINE:-reject}"
    rec_emit "$KIND" "$ACT" "$ST" audit "${A_LINE:-G1 reject}"; drop_arm "$KIND"; add_rej "$AID"; continue
  elif [ "$A_RC" -ne 0 ]; then
    jl arm_audit_unavailable "base_id=$BID" "kind=$KIND" "id=$AID" "rc=$A_RC" "verdict=${A_LINE:-unavailable}" "note=미판정 = 등재 금지 · 파일 제거(다음 라운드에 다시 낼 수 있다)"
    rec_emit "$KIND" "$ACT" "$ST" audit_unavailable "${A_LINE:-G1 unavailable rc=$A_RC}"; drop_arm "$KIND"; add_rej "$AID"; continue
  fi
  # ③ 등재 — R 이 probe 를 다시 돌리고 원장(source=b5_design · n_siblings=이번 방출 수)을 먼저 쓴 뒤 카탈로그에 넣는다
  Rscript "$ADMIT_CLI" "$KIND" "$ACT" "$ST" "$LLM_USED_MODEL" "$N_EMIT" b5_design >>"$LOG" 2>&1; AD_RC=$?
  if [ "$AD_RC" -eq 0 ]; then
    ADMITTED="${ADMITTED:+$ADMITTED,}$AID"; jl arm_admitted "base_id=$BID" "kind=$KIND" "id=$AID" "action=$ACT" "state=$ST" "model=$LLM_USED_MODEL"
  elif [ "$AD_RC" -eq 3 ]; then
    jl arm_rejected "base_id=$BID" "kind=$KIND" "id=$AID" "stage=admit" "note=등재기가 거부 — 원장은 등재기가 이미 기록"; drop_arm "$KIND"; add_rej "$AID"
  else
    jl admit_infra_error "base_id=$BID" "kind=$KIND" "id=$AID" "rc=$AD_RC" "note=등재기 미실행 — 파일 보존 · 이 라운드 설계에서는 제외"; add_rej "$AID"
  fi
done 3< "$ARMS_TSV"

# ── 설계 검증 · 최종 쓰기 (R 재도출 · 실패 = 폴백 라운드 기록 · 기존 설계 보존) ────────────────────────────────
Rscript "$LIB" verify "$BID" "$DESIGN" "$ROUND" "$COMPOSE" "${ADMITTED:--}" "${REJECTED:--}" >>"$LOG" 2>&1; V_RC=$?
jl verify_done "base_id=$BID" "round=$ROUND" "rc=$V_RC" "admitted=${ADMITTED:-none}" "rejected=${REJECTED:-none}" "elapsed_sec=$(( $(date +%s) - T0 ))"
exit 0
