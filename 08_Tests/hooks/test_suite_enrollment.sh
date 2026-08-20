#!/usr/bin/env bash
#==============================================================================
# test_suite_enrollment.sh — suite_enrollment_check.sh 위반 주입 테스트
#
# 목적: "배터리가 안 도는 테스트가 있다"는 드리프트를 검사기가 **실제로 잡는지** 확인.
#   깨끗한 픽스처 PASS + 위반 픽스처별 FAIL 을 모두 단언한다("경고 0" 보고 순간이
#   최고 위험 — 검사가 죽어도 초록인 테스트는 테스트가 아니다).
#
# 픽스처는 QVEST_SEC_RUNNER / QVEST_SEC_TESTS_DIR 오버라이드로 주입 (실 트리 무접촉).
# 요약 규약: 마지막 줄 {"test":"suite_enrollment_guard","pass":N,"fail":N,"total":N}
#==============================================================================
set -u

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHK="$_SELF_DIR/../../02_Infrastructure/ops/suite_enrollment_check.sh"
[ -f "$CHK" ] || { echo "FATAL: checker 부재"; echo '{"test":"suite_enrollment_guard","pass":0,"fail":1,"total":1}'; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1  ($2)"; }

FX=$(mktemp -d); trap 'rm -rf "$FX"' EXIT

# ── 깨끗한 픽스처: test_a.sh 가 SUITES 에 직접 등재된 상태 ────────────────────
mk_clean() {
  rm -rf "$FX/tests" "$FX/runner.sh"
  mkdir -p "$FX/tests/zone"
  : > "$FX/tests/zone/test_a.sh"
  cat > "$FX/runner.sh" <<'EOF'
#!/usr/bin/env bash
SUITES=(
  "08_Tests/zone/test_a.sh"
)
EOF
}

run_chk() {
  OUT=$(env QVEST_SEC_RUNNER="$FX/runner.sh" QVEST_SEC_TESTS_DIR="$FX/tests" bash "$CHK" 2>&1)
  return $?
}

echo "=== test_suite_enrollment (편입 드리프트 위반 주입) ==="

# ── T0. 전부 등재 = PASS (양성 대조) ─────────────────────────────────────────
mk_clean
if run_chk; then ok "T0 전부 등재 = PASS"; else bad "T0 전부 등재 = PASS" "$(echo "$OUT" | grep FAIL | head -1)"; fi

# ── V1. 미등재 테스트 추가 → E2 FAIL ─────────────────────────────────────────
mk_clean; : > "$FX/tests/zone/test_b.sh"
if run_chk; then
  bad "V1 미등재 테스트 검출" "위반이 통과됨 (검사 죽음)"
elif echo "$OUT" | grep -q "FAIL  E2"; then
  echo "$OUT" | grep -q "test_b.sh" && ok "V1 미등재 테스트 검출 (파일명까지 지목)" \
    || bad "V1" "E2 는 떴으나 파일명 미지목 — 조치 불가능한 보고"
else
  bad "V1" "다른 축이 잡음: $(echo "$OUT" | grep FAIL | head -1)"
fi

# ── V2. 집계 러너 규칙: 자동 탐색 러너가 등재되면 같은 디렉터리는 커버됨 ──────
#   ★이 축이 없으면 검사기가 집계 경유 실행을 전부 미편입으로 오탐한다.
mk_clean; : > "$FX/tests/zone/test_b.sh"
: > "$FX/tests/zone/run_zone.R"
cat > "$FX/runner.sh" <<'EOF'
#!/usr/bin/env bash
SUITES=(
  "08_Tests/zone/test_a.sh"
  "08_Tests/zone/run_zone.R"
)
EOF
if run_chk; then ok "V2 집계 러너 등재 시 같은 디렉터리 커버 인정"; else
  bad "V2 집계 러너 커버 인정" "오탐: $(echo "$OUT" | grep FAIL | head -1)"; fi

# ── V2b. 집계 러너가 있어도 **등재 안 됐으면** 커버 아님 ─────────────────────
mk_clean; : > "$FX/tests/zone/test_b.sh"; : > "$FX/tests/zone/run_zone.R"
if run_chk; then
  bad "V2b 미등재 집계 러너는 커버 아님" "통과됨 — 러너 존재만으로 커버 인정하면 안 됨"
else
  echo "$OUT" | grep -q "FAIL  E2" && ok "V2b 미등재 집계 러너는 커버 아님" || bad "V2b" "다른 사유"
fi

# ── V6. lib/ 제외 경계: 헬퍼는 무시하되 그 옆 진짜 테스트는 잡아야 한다 ──────
#   제외를 디렉터리 단위로 두면 "제외가 진짜 결함을 가린다"는 위험이 생긴다.
#   그래서 양쪽을 함께 단언한다 — lib/ 안은 무시(PASS), lib/ 밖은 검거(FAIL).
mk_clean; mkdir -p "$FX/tests/lib"; : > "$FX/tests/lib/test_helper.sh"
if run_chk; then ok "V6a lib/ 헬퍼는 미편입으로 세지 않음"; else
  bad "V6a lib/ 헬퍼 제외" "오탐: $(echo "$OUT" | grep FAIL | head -1)"; fi

mk_clean; mkdir -p "$FX/tests/lib"; : > "$FX/tests/lib/test_helper.sh"
: > "$FX/tests/zone/test_real.sh"
if run_chk; then
  bad "V6b lib/ 밖 미등재는 여전히 검거" "제외가 진짜 결함까지 가림"
else
  echo "$OUT" | grep -q "test_real.sh" && ok "V6b lib/ 밖 미등재는 여전히 검거" \
    || bad "V6b" "E2 는 떴으나 test_real.sh 미지목"; fi

# ── V3. SUITES 선언 부재 = UNKNOWN FAIL (fail-open 금지) ─────────────────────
mk_clean; printf '#!/usr/bin/env bash\necho no suites here\n' > "$FX/runner.sh"
if run_chk; then bad "V3 SUITES 부재 = FAIL" "통과됨(fail-open)"; else
  echo "$OUT" | grep -q "E1 UNKNOWN" && ok "V3 SUITES 선언 부재 = UNKNOWN FAIL" || bad "V3" "다른 사유"; fi

# ── V4. 테스트 파일 0건 = UNKNOWN FAIL (스캔 실패를 통과로 위장 금지) ────────
mk_clean; rm -f "$FX/tests/zone/test_a.sh"
if run_chk; then bad "V4 test_* 0건 = FAIL" "통과됨 — 스캔 실패가 초록으로 위장됨"; else
  echo "$OUT" | grep -q "E2 UNKNOWN" && ok "V4 test_* 0건 = UNKNOWN FAIL" || bad "V4" "다른 사유"; fi

# ── V5. 러너 부재 = UNKNOWN FAIL ─────────────────────────────────────────────
mk_clean; rm -f "$FX/runner.sh"
if run_chk; then bad "V5 러너 부재 = FAIL" "통과됨(fail-open)"; else
  echo "$OUT" | grep -q "E0 UNKNOWN" && ok "V5 러너 부재 = UNKNOWN FAIL" || bad "V5" "다른 사유"; fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"suite_enrollment_guard\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
