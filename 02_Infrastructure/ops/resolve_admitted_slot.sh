#!/usr/bin/env bash
# resolve_admitted_slot.sh — book_state.admitted_ids → 배포 슬롯 디렉토리·파일 TAG 해석
#
# 왜: 월간 리밸 실행기가 슬롯을 하드코딩하고 있었다(run_nolayer4_monthly.sh:13 /
#     run_pg2_rebalance_full.sh). 2026-07-19 D3 swap-in 으로 admitted 가
#     STR_1715_on_M4gAE_R05_noLayer4_PG2(슬롯 2-4)로 바뀐 뒤에도 실행기는 계속 슬롯 2-3
#     (구 변형)을 산출했다. 2026-08 은 m4 미발화(gate=1.00)라 우연히 값이 같았을 뿐,
#     M4 가 발화하는 달에는 30% de-risk 가 누락된 **틀린 비중**이 나온다.
#
# ★정확 매칭만 쓴다. basename 이 ^[0-9]+-[0-9]+\.<ID>$ 인 디렉토리 하나만 인정한다.
#   부분문자열 매칭은 위험하다 — 실측 주입(2026-08-01): 같은 ID 에 대해
#   `_v2` / `OLD_` / `_DEPRECATED` 변형이 생기면 naive 는 4건으로 폭발하고
#   head -1 로 뽑으면 **임의 선택**이 된다. 0건이거나 2건 이상이면 해석 실패로 중단한다.
#
# 사용:  source resolve_admitted_slot.sh   → ADMITTED_ID / SLOT_DIR / HOLD_TAG 설정
#        bash   resolve_admitted_slot.sh   → 진단 출력(사람이 확인용)
# 실패 시: 비어있는 값을 남기고 비정상 종료(source 면 return 1) — 조용히 기본값으로
#          되돌아가지 않는다. 잘못된 슬롯으로 배포하느니 멈추는 게 낫다.

_ras_root() {
  local c
  for c in "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}"; do
    c="${c//\\//}"
    [ -n "$c" ] && [ -f "$c/02_Infrastructure/hooks/qvest_hook_router.py" ] && { printf '%s' "$c"; return 0; }
  done
  c="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." 2>/dev/null && pwd)"
  [ -n "$c" ] && [ -f "$c/02_Infrastructure/hooks/qvest_hook_router.py" ] && { printf '%s' "$c"; return 0; }
  return 1
}

resolve_admitted_slot() {
  local root py bs out
  root="$(_ras_root)" || { echo "[slot] ERROR 프로젝트 루트 해석 실패" >&2; return 1; }
  # ★python 은 존재가 아니라 **실행**으로 확인한다. bare python3 는 Windows Store 스텁일 수
  #   있고, 스텁은 "Python" 한 줄만 찍고 종료해 명령치환이 빈 문자열을 반환한다 —
  #   `-x` 검사는 스텁도 통과시킨다(2026-08-01 실측 재현). 기지 함정:
  #   [[reference-python3-windows-stub-use-qvest-py]]
  py=""
  for _c in "${QVEST_PY_RESOLVED:-}" "${QVEST_PY:-}" \
            "$root/.venv_qvest_ml/Scripts/python.exe" \
            "$(command -v python3 2>/dev/null)" "$(command -v python 2>/dev/null)"; do
    [ -n "$_c" ] || continue
    "$_c" -c 'import sys' >/dev/null 2>&1 && { py="$_c"; break; }
  done
  [ -n "$py" ] || { echo "[slot] ERROR 실행 가능한 python 없음 (스텁 폴백 차단)" >&2; return 1; }
  bs="$root/qepm/mailbox/governor/book_state.json"
  [ -f "$bs" ] || { echo "[slot] ERROR book_state 부재: $bs" >&2; return 1; }

  out="$("$py" - "$bs" "$root/05_Production/2.Factor_Model" <<'PYEOF'
import json, os, re, sys
bs, base = sys.argv[1], sys.argv[2]
try:
    ids = json.load(open(bs, encoding="utf-8-sig")).get("admitted_ids") or []
except Exception as e:
    print(f"ERR book_state 판독 실패: {e}"); raise SystemExit
if len(ids) != 1:
    # 복수 admitted = 배포 슬롯이 유일하지 않다 → 사람이 정해야 한다(임의 선택 금지).
    print(f"ERR admitted_ids 가 {len(ids)}건 (유일해야 함): {ids}"); raise SystemExit
sid = ids[0]
if not os.path.isdir(base):
    print(f"ERR 슬롯 base 부재: {base}"); raise SystemExit
pat = re.compile(r"[0-9]+-[0-9]+\." + re.escape(sid) + r"$")
hit = [d for d in sorted(os.listdir(base))
       if os.path.isdir(os.path.join(base, d)) and pat.fullmatch(d)]
if len(hit) != 1:
    print(f"ERR '{sid}' 에 정확 매칭되는 슬롯이 {len(hit)}건 (1건이어야): {hit}"); raise SystemExit
slot = hit[0]
# 파일 TAG: 슬롯의 02_holdings_universe 에 이미 있는 산출물에서 규칙을 읽는다.
#   ${YYYYMMDD}_<TAG>_weights_cap_0p20.csv  — TAG 를 코드에 별도 매핑하지 않는다
#   (매핑을 두면 슬롯 추가 때 또 하드코딩이 늘어난다).
hu = os.path.join(base, slot, "02_holdings_universe")
tags = set()
if os.path.isdir(hu):
    for f in os.listdir(hu):
        m = re.fullmatch(r"\d{8}_(.+)_weights_cap_0p20\.csv", f)
        if m:
            tags.add(m.group(1))
if len(tags) != 1:
    print(f"ERR 슬롯 {slot} 의 파일 TAG 가 {len(tags)}종 (1종이어야): {sorted(tags)}"); raise SystemExit
tag = tags.pop()

# ── 생성기 경로 ─────────────────────────────────────────────────────────────
# ★슬롯의 01_reproducible_code 를 **파일명 패턴으로 발견하지 않는다.** 실측(2026-08-01):
#   2-1 은 forward_weights_M4only_DEPRECATED_20260617.R + forward_weights_R05_AR.R,
#   2-2 는 _R05_AR.R + _R05_FAITH.R 로 각각 2건 — 패턴 매칭은 폐기본까지 후보로 올려
#   임의 선택이 된다(naive substring 과 같은 계통).
# 대신 **인프라측 미러**를 정본 호출 경로로 쓴다. 05_Production 은 수정 금지이지만
#   호출은 가능하고, 미러는 그 사본이라 실행 결과가 같다 — 단 "같다"를 믿지 않고
#   sha1 로 대조한다(2026-08-01 실측: D3 미러 == production 사본, sha1 1c432a77...).
#   미러가 없거나 어긋나면 중단한다. 잘못된 생성기로 배포하느니 멈추는 게 낫다.
import hashlib
root = os.path.dirname(os.path.dirname(base))          # <root>/05_Production/.. → <root>
mirror_dir = os.path.join(root, "02_Infrastructure/portfolio")
prod_dir = os.path.join(base, slot, "01_reproducible_code")
cands = []
if os.path.isdir(prod_dir):
    cands = [f for f in sorted(os.listdir(prod_dir)) if f.endswith(".R")]
def sha(p):
    return hashlib.sha1(open(p, "rb").read()).hexdigest()
mirror = None
if os.path.isdir(mirror_dir):
    for mf in sorted(os.listdir(mirror_dir)):
        if not mf.endswith(".R"):
            continue
        mp = os.path.join(mirror_dir, mf)
        for cf in cands:
            cp = os.path.join(prod_dir, cf)
            try:
                if sha(mp) == sha(cp):
                    mirror = mp
                    break
            except Exception:
                pass
        if mirror:
            break
if not mirror:
    print(f"ERR 슬롯 {slot} 생성기의 인프라 미러를 찾지 못함 "
          f"(02_Infrastructure/portfolio 에 production 사본과 sha1 일치하는 .R 없음). "
          f"미러를 만들거나 호출 경로를 명시할 것 — 패턴 추측으로 진행하지 않음"); raise SystemExit
print(f"OK {sid}|{slot}|{tag}|{os.path.relpath(mirror, root).replace(os.sep, '/')}")
PYEOF
)"

  case "$out" in
    OK\ *)
      out="${out#OK }"
      ADMITTED_ID="${out%%|*}"; out="${out#*|}"
      local slot="${out%%|*}"; out="${out#*|}"
      HOLD_TAG="${out%%|*}"; local gen="${out#*|}"
      SLOT_DIR="$root/05_Production/2.Factor_Model/$slot"
      GEN_SCRIPT="$root/$gen"
      export ADMITTED_ID SLOT_DIR HOLD_TAG GEN_SCRIPT
      return 0 ;;
    *)
      echo "[slot] ${out:-ERR 해석기 무출력}" >&2
      ADMITTED_ID=""; SLOT_DIR=""; HOLD_TAG=""
      return 1 ;;
  esac
}

# 직접 실행 시 진단 출력
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  if resolve_admitted_slot; then
    echo "ADMITTED_ID=$ADMITTED_ID"
    echo "SLOT_DIR=$SLOT_DIR"
    echo "HOLD_TAG=$HOLD_TAG"
    echo "GEN_SCRIPT=$GEN_SCRIPT"
  else
    exit 1
  fi
fi
