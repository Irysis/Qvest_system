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

  hooks=$(cd "$DIR" && CLAUDE_PROJECT_DIR="$DIR" bash 08_Tests/hooks/run_all_hooks.sh 2>/dev/null \
          | grep -oE 'FINAL: [0-9]+ pass / [0-9]+ fail / [0-9]+ total' | grep -oE '[0-9]+ total' | grep -oE '[0-9]+')
  regime=$(cd "$DIR" && CLAUDE_PROJECT_DIR="$DIR" Rscript 08_Tests/regime/run_all.R 2>/dev/null \
          | grep -oE 'of [0-9]+ total' | grep -oE '[0-9]+')
  contract=$(cd "$DIR" && CLAUDE_PROJECT_DIR="$DIR" Rscript 08_Tests/contract_regression/run_contract_regression.R 2>/dev/null \
          | grep -oE 'cases=[0-9]+' | grep -oE '[0-9]+' | head -1)
  continuity=$([ -x "$PY" ] && "$PY" "$DIR/02_Infrastructure/tests/test_continuity_gate.py" 2>/dev/null \
          | grep -oE 'BATTERY: [0-9]+/[0-9]+' | grep -oE '/[0-9]+' | tr -d '/')

  # 빈 값 = 수집 실패 → 0 이 아니라 null 로 남긴다(0 으로 적으면 그 자체가 거짓 경보/거짓 안심)
  printf '{\n' > "$LATEST"
  printf '  "collected_at": "%s",\n' "$(date -Iseconds)" >> "$LATEST"
  printf '  "hooks": %s,\n'      "${hooks:-null}"      >> "$LATEST"
  printf '  "regime": %s,\n'     "${regime:-null}"     >> "$LATEST"
  printf '  "contract_regression": %s,\n' "${contract:-null}" >> "$LATEST"
  printf '  "continuity": %s\n'  "${continuity:-null}" >> "$LATEST"
  printf '}\n' >> "$LATEST"
  echo "[suite-totals] 수집: hooks=${hooks:-?} regime=${regime:-?} contract=${contract:-?} continuity=${continuity:-?}"
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

  "$PY" - "$BASELINE" "$LATEST" <<'PYEOF'
import datetime, io, json, sys
b = json.load(io.open(sys.argv[1], encoding="utf-8"))
l = json.load(io.open(sys.argv[2], encoding="utf-8"))

# 신선도: stale 한 latest 를 비교하면 '과거를 현재로 착각'한다 — 감시가 조용히 무의미해지는
# 형태라 이 아크가 고쳐온 계열과 같다. 수집은 daily_refresh 가 매일 돌린다.
ts = l.get("collected_at")
if ts:
    try:
        age_h = (datetime.datetime.now(datetime.timezone.utc)
                 - datetime.datetime.fromisoformat(ts).astimezone(datetime.timezone.utc)
                 ).total_seconds() / 3600.0
        if age_h >= 48:
            print("[suite-totals] ⚠ 수집 %.0fh 경과(48h+) — 이 비교는 과거값 기준입니다. "
                  "--collect 재실행 또는 daily_refresh 동작 확인" % age_h, file=sys.stderr)
    except Exception:
        pass

keys = [k for k in b if k not in ("collected_at", "note")]
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
    print("[suite-totals] ★총계 감소 감지 — 회귀가 아니라 '침묵 결손'을 먼저 의심하세요:", file=sys.stderr)
    for k, bv, lv in drops:
        print("  - %-20s %d → %d  (%+d)" % (k, bv, lv, lv - bv), file=sys.stderr)
    print("  점검: 해당 러너를 직접 돌려 케이스가 실행되는지 확인(총계 0 = 계측 사망)", file=sys.stderr)
if unknown:
    print("[suite-totals] ⚠ 수집 실패(null): %s — 수치 없음은 '정상'이 아니다" % ", ".join(unknown), file=sys.stderr)
if not drops and not unknown:
    print("[suite-totals] OK " + " · ".join("%s=%s" % (k, v) for k, v in ok))
sys.exit(1 if drops else 0)
PYEOF
}

#──────────────────────────────────────────────────────────────────────────────
promote() {
  [ -f "$LATEST" ] || { echo "[suite-totals] 수집 결과 없음 — 먼저 --collect"; exit 1; }
  mkdir -p "$DIR/06_Registry"
  "$PY" - "$LATEST" "$BASELINE" <<'PYEOF'
import io, json, sys
l = json.load(io.open(sys.argv[1], encoding="utf-8"))
if any(v is None for k, v in l.items() if k != "collected_at"):
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
