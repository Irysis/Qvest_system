#!/usr/bin/env bash
#==============================================================================
# suite_totals_watch.sh — 테스트 스위트 "총계 회귀" 감시
#
# 왜 (2026-07-25 실사고 3건):
#   계측 사망은 실패로 안 드러나고 **총계가 조용히 줄어드는** 형태로 온다.
#     - hooks 러너   : 27 → 0   ("✅ ALL PASS" 로 위장)
#     - regime 러너  : 5  → 0   ("0 passed / 0 failed (of 0 total)")
#     - continuity   : 31 → 9   (운영 마커 오염으로 차단 케이스 22건 자동 통과)
#   셋 다 "실패 0건"이라 기존 감시로는 안 잡힌다. 잡히는 유일한 신호가 **총계 감소**다.
#   ★원칙: 총계가 줄면 회귀가 아니라 '침묵 결손'을 먼저 의심한다.
#
# 사용:
#   --collect   4개 러너 실행 → 현재 총계를 .cache 에 기록 (느림, 무인/수동용)
#   --check     기록 vs 기준선 비교만 (빠름, 부트 배선용) — 기본 동작
#   --baseline  현재 수집값을 기준선으로 승격 (06_Registry, 커밋 대상)
#
# 종료코드: 0=정상/정보부족 · 1=총계 감소 감지
#==============================================================================
set -uo pipefail

_norm() { local p="${1:-}"; printf '%s' "${p//\\//}"; }
DIR="$(_norm "${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}")"

BASELINE="$DIR/06_Registry/suite_totals_baseline.json"
LATEST="$DIR/.cache/suite_totals_latest.json"
MODE="${1:---check}"

_py() {
  local p="$DIR/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$p" ] || p="$(_norm "${QM_ROOT:-}")/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$p" ] || p="$(_norm "${QVEST_PY:-}")"
  printf '%s' "$p"
}
PY="$(_py)"

#──────────────────────────────────────────────────────────────────────────────
collect() {
  mkdir -p "$DIR/.cache"
  local hooks regime contract continuity
  local hooks_out regime_out cont_out hooks_fail regime_fail continuity_fail

  # (2026-07-26 probe① 도훈 승인) fail 축 동시 수집 — 구판은 total만 봐서
  # total=pass+fail 구조상 FAIL이 나도 총계 불변 = 회귀가 감시를 그냥 통과했다.
  hooks_out=$(cd "$DIR" && CLAUDE_PROJECT_DIR="$DIR" bash 08_Tests/hooks/run_all_hooks.sh 2>/dev/null \
          | grep -oE 'FINAL: [0-9]+ pass / [0-9]+ fail / [0-9]+ total' | head -1)
  hooks=$(printf '%s' "$hooks_out" | grep -oE '[0-9]+ total' | grep -oE '[0-9]+')
  hooks_fail=$(printf '%s' "$hooks_out" | grep -oE '[0-9]+ fail' | grep -oE '[0-9]+')
  regime_out=$(cd "$DIR" && CLAUDE_PROJECT_DIR="$DIR" Rscript 08_Tests/regime/run_all.R 2>/dev/null)
  regime=$(printf '%s' "$regime_out" | grep -oE 'of [0-9]+ total' | grep -oE '[0-9]+')
  regime_fail=$(printf '%s' "$regime_out" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' | head -1)
  contract=$(cd "$DIR" && CLAUDE_PROJECT_DIR="$DIR" Rscript 08_Tests/contract_regression/run_contract_regression.R 2>/dev/null \
          | grep -oE 'cases=[0-9]+' | grep -oE '[0-9]+' | head -1)
  cont_out=$([ -x "$PY" ] && "$PY" "$DIR/02_Infrastructure/tests/test_continuity_gate.py" 2>/dev/null \
          | grep -oE 'BATTERY: [0-9]+/[0-9]+' | head -1)
  continuity=$(printf '%s' "$cont_out" | grep -oE '/[0-9]+' | tr -d '/')
  continuity_fail=""
  if [ -n "$cont_out" ]; then
    local _cp _ct
    _cp=$(printf '%s' "$cont_out" | grep -oE '[0-9]+/' | tr -d '/')
    _ct=$(printf '%s' "$cont_out" | grep -oE '/[0-9]+' | tr -d '/')
    [ -n "$_cp" ] && [ -n "$_ct" ] && continuity_fail=$((_ct - _cp))
  fi

  # (2026-08-02) 수집 시점의 **트리 정체성**을 함께 남긴다.
  #   왜: --check 는 이 스냅샷을 읽어 판정을 출력하는데, 스냅샷이 어느 트리에서 나온
  #   값인지 표시가 없어 부팅이 **과거 값을 현재 판정으로 단언**했다(08-02 실측:
  #   00:40 수집 fail=6 을 01:5x 부팅이 그대로 보고 → 그 사이 8 커밋이 4건을 수리해
  #   실제는 fail=2). 나이(48h) 만으로는 못 잡는다 — 이 저장소는 시간당 여러 번 커밋한다.
  #   ★시간이 아니라 트리가 판정의 유효범위다("mtime→최신성" 대체 계열).
  local head_sha
  head_sha=$(cd "$DIR" && git rev-parse --short HEAD 2>/dev/null)

  # 빈 값 = 수집 실패 → 0 이 아니라 null 로 남긴다(0 으로 적으면 그 자체가 거짓 경보/거짓 안심)
  printf '{\n' > "$LATEST"
  printf '  "collected_at": "%s",\n' "$(date -Iseconds)" >> "$LATEST"
  printf '  "tree_head": %s,\n' "$( [ -n "${head_sha:-}" ] && printf '"%s"' "$head_sha" || printf 'null' )" >> "$LATEST"
  printf '  "hooks": %s,\n'      "${hooks:-null}"      >> "$LATEST"
  printf '  "regime": %s,\n'     "${regime:-null}"     >> "$LATEST"
  printf '  "contract_regression": %s,\n' "${contract:-null}" >> "$LATEST"
  printf '  "continuity": %s,\n'  "${continuity:-null}" >> "$LATEST"
  printf '  "hooks_fail": %s,\n'      "${hooks_fail:-null}"      >> "$LATEST"
  printf '  "regime_fail": %s,\n'     "${regime_fail:-null}"     >> "$LATEST"
  printf '  "continuity_fail": %s\n'  "${continuity_fail:-null}" >> "$LATEST"
  printf '}\n' >> "$LATEST"
  echo "[suite-totals] 수집: hooks=${hooks:-?}(fail ${hooks_fail:-?}) regime=${regime:-?}(fail ${regime_fail:-?}) contract=${contract:-?} continuity=${continuity:-?}(fail ${continuity_fail:-?})"
  echo "[suite-totals] → $LATEST"
}

#──────────────────────────────────────────────────────────────────────────────
check() {
  if [ ! -f "$BASELINE" ]; then
    echo "[suite-totals] 기준선 없음 — '--collect 후 --baseline' 으로 생성하세요"
    return 0
  fi
  if [ ! -f "$LATEST" ]; then
    echo "[suite-totals] 최근 수집 없음 (기준선만 존재) — --collect 필요"
    return 0
  fi
  [ -x "$PY" ] || { echo "[suite-totals] python 해석 실패 — 비교 생략"; return 0; }

  # (2026-08-02) 스냅샷이 나온 트리와 **현재 트리**를 대조한다. 다르면 이 판정은
  #   "과거 트리에 대한 사실"이지 현재 상태가 아니다 — 그 구분을 출력에 강제한다.
  local cur_head snap_head ncommits
  cur_head=$(cd "$DIR" && git rev-parse --short HEAD 2>/dev/null)
  snap_head=$("$PY" -c 'import io,json,sys; print(json.load(io.open(sys.argv[1],encoding="utf-8")).get("tree_head") or "")' "$LATEST" 2>/dev/null)
  ncommits=""
  if [ -n "${cur_head:-}" ] && [ -n "${snap_head:-}" ] && [ "$snap_head" != "$cur_head" ]; then
    ncommits=$(cd "$DIR" && git rev-list --count "${snap_head}..HEAD" 2>/dev/null)
  fi

  "$PY" - "$BASELINE" "$LATEST" "${cur_head:-}" "${ncommits:-}" <<'PYEOF'
import datetime, io, json, sys
b = json.load(io.open(sys.argv[1], encoding="utf-8"))
l = json.load(io.open(sys.argv[2], encoding="utf-8"))
cur_head = sys.argv[3] if len(sys.argv) > 3 else ""
ncommits = sys.argv[4] if len(sys.argv) > 4 else ""

# 나이 — 항상 표시한다. "언제 잰 값인지"를 안 적으면 읽는 쪽이 현재로 읽는다.
age_txt = ""
ts = l.get("collected_at")
if ts:
    try:
        age_h = (datetime.datetime.now(datetime.timezone.utc)
                 - datetime.datetime.fromisoformat(ts).astimezone(datetime.timezone.utc)
                 ).total_seconds() / 3600.0
        age_txt = "%.1fh 전" % age_h
        if age_h >= 48:
            print("[suite-totals] ⚠ 수집 %.0fh 경과(48h+) — 이 비교는 과거값 기준입니다. "
                  "--collect 재실행 또는 daily_refresh 동작 확인" % age_h, file=sys.stderr)
    except Exception:
        pass

# (2026-08-02) ★트리 정체성 = 판정의 유효범위.
#   08-02 실측: 00:40 수집(fail=6)을 01:5x 부팅이 현재 판정으로 단언했으나, 그 사이 8 커밋이
#   4건을 수리해 실제는 fail=2 였다. 나이 임계(48h)로는 못 잡는다 — 이 저장소는 시간당
#   여러 번 커밋한다. 그래서 시간이 아니라 **트리가 움직였는가**로 유효범위를 판정한다.
#   ★단, 트리가 움직였다고 조용히 통과시키지 않는다(그건 검사 사망이다). 경보는 유지하고
#   '무엇에 대한 사실인지'만 정확히 라벨링한다.
snap_head = l.get("tree_head")
if snap_head and cur_head and snap_head != cur_head:
    vintage = ("수집 시점 %s 기준 · 현재 %s%s — 현재 트리 미검증"
               % (snap_head, cur_head, (" · 이후 %s 커밋" % ncommits) if ncommits else ""))
elif not snap_head:
    vintage = "수집 시점 트리 미기록(구식 스냅샷) — 현재 트리와의 일치 미확인"
else:
    vintage = ""

def scope(label):
    return "%s [%s%s]" % (label, ("수집 %s" % age_txt) if age_txt else "수집 시점 미상",
                          (" · " + vintage) if vintage else " · 현재 트리와 동일")

# (2026-07-26 probe①) fail 축 — total 불변이어도 FAIL>0 은 회귀다. 수집 실패(null)는
# 구식 latest(fail 축 도입 전) 호환으로 조용히 통과시키지 않고 이름으로 표시.
fails = {k: v for k, v in l.items() if k.endswith("_fail")}
fail_hits = [(k, v) for k, v in fails.items() if isinstance(v, int) and v > 0]
if fail_hits:
    print(scope("[suite-totals] ★FAIL>0 — 총계 불변이어도 회귀:"), file=sys.stderr)
    for k, v in fail_hits:
        print("  - %-20s fail=%d" % (k, v), file=sys.stderr)
    if vintage:
        print("  ※이 수치는 위 수집 시점 트리의 사실입니다. 현재 상태를 알려면 "
              "'bash 02_Infrastructure/ops/suite_totals_watch.sh --collect' 재실행.", file=sys.stderr)

keys = [k for k in b if k not in ("collected_at", "note", "tree_head")]
drops, unknown, ok = [], [], []
for k in keys:
    bv, lv = b.get(k), l.get(k)
    if lv is None:
        unknown.append(k)
    elif isinstance(bv, int) and lv < bv:
        drops.append((k, bv, lv))
    else:
        ok.append((k, lv))
if drops:
    print(scope("[suite-totals] ★총계 감소 — 회귀가 아니라 '침묵 결손'을 먼저 의심하세요:"), file=sys.stderr)
    for k, bv, lv in drops:
        print("  - %-20s %d → %d  (%+d)" % (k, bv, lv, lv - bv), file=sys.stderr)
    print("  점검: 해당 러너를 직접 돌려 케이스가 실행되는지 확인(총계 0 = 계측 사망)", file=sys.stderr)
if unknown:
    print("[suite-totals] ⚠ 수집 실패(null): %s — 수치 없음은 '정상'이 아니다" % ", ".join(unknown), file=sys.stderr)
if not drops and not unknown and not fail_hits:
    print(scope("[suite-totals] OK " + " · ".join("%s=%s" % (k, v) for k, v in ok)))
sys.exit(1 if (drops or fail_hits) else 0)
PYEOF
}

#──────────────────────────────────────────────────────────────────────────────
promote() {
  [ -f "$LATEST" ] || { echo "[suite-totals] 수집 결과 없음 — 먼저 --collect"; exit 1; }
  mkdir -p "$DIR/06_Registry"
  "$PY" - "$LATEST" "$BASELINE" <<'PYEOF'
import io, json, sys
l = json.load(io.open(sys.argv[1], encoding="utf-8"))
if any(v is None for k, v in l.items() if k not in ("collected_at", "tree_head")):
    print("null 포함 — 기준선 승격 거부(불완전 수집을 기준선으로 삼으면 이후 감소를 못 잡는다)")
    sys.exit(1)
l["note"] = ("테스트 스위트 총계 기준선. 감소 = 회귀가 아니라 침묵 결손 우선 의심. "
             "갱신은 suite_totals_watch.sh --collect 후 --baseline.")
io.open(sys.argv[2], "w", encoding="utf-8").write(json.dumps(l, ensure_ascii=False, indent=2) + "\n")
print("기준선 갱신:", {k: v for k, v in l.items() if k not in ("note", "collected_at")})
PYEOF
}

case "$MODE" in
  --collect)  collect ;;
  --baseline) promote ;;
  --check|*)  check ;;
esac
