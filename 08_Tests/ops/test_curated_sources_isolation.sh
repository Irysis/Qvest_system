#!/bin/bash
# test_curated_sources_isolation.sh — curated 결손이 **arXiv 축까지 죽이지 않는가** (2026-08-22)
#
# 왜 있나 (감사 실측 + 오늘 확인):
#   `paper_recharge_daily.R` 이 `nrow(curated_sources)==0` 이면 `stop()` 으로 즉사했다.
#   · 08-15/16/17 **세 날 연속** crash (원문 "sources.csv is empty or missing")
#   · MCP discovery 는 **이미 성공해 JSON 을 남긴 뒤**였고 완주 스탬프는 훨씬 뒤라
#     "산출은 있고 완주는 없는" 상태가 **구조적으로 보장**됐다
#   · 라우터는 `.done` 을 보므로 discovery 29편씩이 **3일간 미소비**
#   · 그 crash 는 **마커를 남기지 않았다**(감사: paper_recharge exit=1 7회 / ★경보발행 0건)
#
# ★두 결함이 겹쳤다:
#   ① 관심사 결합 — curated(정적 PDF, 실측 15/15 소진으로 사실상 idle)의 파일 하나가
#      독립 원천인 arXiv MCP 축까지 죽였다. idle 한 축이 매일의 수집을 인질로 잡았다.
#   ② 무마커 사망 — 사람이 알 방법이 없었다.
#
# ★1급 축은 "죽지 않는가" 가 아니라 **"조용히 넘기지도 않는가"** 다.
#   즉사를 skip 으로 바꾸기만 하면 결손이 정상값으로 내려앉는다 — 오늘 반복 확인된 그 계통.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
RR="$ROOT/02_Infrastructure/tools/paper_recharge_daily.R"
PROBE="$SELF_DIR/lib/_probe_curated_branch.R"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

[ -f "$RR" ] || { echo "  SKIP  recharge 스크립트 부재"; echo "== t_summary: PASS=0 FAIL=0 =="; exit 0; }

echo "== 배선 축: 즉사가 제거됐는가 =="
if grep -q 'stop("paper_recharge_sources.csv is empty or missing")' "$RR"; then
  ng "즉사 잔존" "curated 결손이 arXiv 축까지 죽인다 — 08-15/16/17 3일 연속 전례"
else
  ok "stop() 제거됨"
fi
grep -q 'reason=curated_sources_missing' "$RR" && ok "결손이 경보로 남는다" \
  || ng "무마커 skip" "즉사를 조용한 skip 으로 바꾸면 결손이 정상값이 된다"
grep -q 'curated 축만 skip, arXiv MCP 축은 계속 진행' "$RR" && ok "축 분리 의도가 코드에 명시" \
  || ng "축 분리" "두 독립 원천이 여전히 결합"

echo "== 하류 내성: 빈 curated 로 rbind/health 가 견디는가 =="
grep -q 'curated_health <- tryCatch(audit_curated_health' "$RR" && ok "health 감사가 tryCatch 로 보호" \
  || ng "health 취약" "빈 프레임에서 죽을 수 있다"
grep -q 'sources_all <- rbind(mcp_sources, curated_sources)' "$RR" && ok "rbind 합류 지점 확인" \
  || ng "합류 지점" "구조가 바뀌었다 — 재검 필요"

echo "== ★행동 축: 실제로 즉사하지 않고 경보를 남기는가 (분기 실행) =="
if command -v Rscript >/dev/null 2>&1 && [ -f "$PROBE" ]; then
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/.cache/scheduler_alerts" "$T/02_Infrastructure/config"
  OUT=$(cd "$ROOT" && Rscript --no-save "$PROBE" "$T" 2>&1)
  echo "$OUT" | grep -q "정상 진행" && ok "빈 curated → 즉사 안 함 (실행 확인)" \
    || ng "여전히 즉사" "$(echo "$OUT" | tail -2 | tr '\n' ' ')"
  echo "$OUT" | grep -q "경보 마커: 1 건" && ok "경보 마커 1건 발행 (실행 확인)" \
    || ng "마커 미발행" "$(echo "$OUT" | tail -2 | tr '\n' ' ')"
else
  echo "  SKIP  Rscript 또는 probe 부재"
fi

echo "== git 축: sources.csv 가 추적 대상인가 (신규 클론 내성) =="
C="02_Infrastructure/config/paper_recharge_sources.csv"
if (cd "$ROOT" && git ls-files --error-unmatch "$C" >/dev/null 2>&1); then
  ok "sources.csv git 추적 — 신규 클론에서도 존재"
else
  ng "미추적" "이 머신에만 존재 — 신규 클론은 curated 축이 항상 결손"
fi
if (cd "$ROOT" && git check-ignore -q "$C" 2>/dev/null); then
  ng "ignore 잔존" ".gitignore 예외가 안 먹는다"
else
  ok ".gitignore 예외 실효"
fi

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ] || exit 1
