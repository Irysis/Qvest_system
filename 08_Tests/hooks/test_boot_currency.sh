#!/usr/bin/env bash
#==============================================================================
# test_boot_currency.sh — boot_currency_check.sh 위반 주입 테스트
#
# 목적: 부팅 자기-정합 검사가 각 드리프트 축을 **실제로 잡는지** 일부러 틀린 입력을
#   주입해 확인한다. "통과"만 세는 테스트는 검사가 죽어도 초록이므로, 깨끗한 픽스처
#   PASS + 위반 픽스처별 FAIL을 모두 단언한다.
#
# 픽스처는 QVEST_BCC_* 오버라이드로 주입 (실파일 무접촉).
#   ※ C6 필터는 실저장소 02_Infrastructure/hooks/ 실존으로 판정하므로 픽스처 훅 이름은
#     실존 훅(safety_guard.sh 등)을 쓴다 — 필터 자체도 이로써 함께 검증됨.
#
# 요약 규약: 마지막 줄 {"test":"boot_currency_guard","pass":N,"fail":N,"total":N}
#==============================================================================
set -u

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHK="$_SELF_DIR/../../02_Infrastructure/ops/boot_currency_check.sh"
[ -f "$CHK" ] || { echo "FATAL: checker 부재"; echo '{"test":"boot_currency_guard","pass":0,"fail":1,"total":1}'; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1  ($2)"; }

FX=$(mktemp -d); trap 'rm -rf "$FX"' EXIT

# ── 깨끗한 픽스처 세트 (합성 버전 v9.9 · claude-testfam-7 · 5-Mode) ───────────
mk_clean() {
  cat > "$FX/CLAUDE.md" <<'EOF'
## Active Version

**Qvest v9.9 — Testfam 7-Native · 5-Mode 헌법** (세션 모델 `claude-testfam-7`)

- **현행 hook 등록 = settings.json 2 distinct .sh** (합성)

**★ Active SOT (단일 진실)**: `02_Infrastructure/docs/synth_alpha_sot.md` (합성)
EOF
  cat > "$FX/lawbook_index.md" <<'EOF'
# Qvest Index

**합성 항해도** — navigation + debug map.
**v9.9 — 5-Mode 헌법** (합성).

## 1. Active SOT

- `02_Infrastructure/docs/synth_alpha_sot.md` — 합성 SOT
EOF
  cat > "$FX/bootstrap.sh" <<'EOF'
echo "=== Qvest v9.9 부트스트랩 (Testfam 7-Native · 5-Mode +X) ==="
echo "=== 부트스트랩 완료 (Qvest v9.9 — Testfam 7-Native · 5-Mode) ==="
echo "v9.9:       합성 상태라인"
EOF
  cat > "$FX/qvest.md" <<'EOF'
---
description: "합성 v9.9"
---
# 합성 (실측 2종) STR_1111_TEST_PG2
EOF
  cat > "$FX/settings.json" <<'EOF'
{"hooks": {"a": "safety_guard.sh", "b": "agent_role_guard.sh"}}
EOF
  cat > "$FX/dispatch.json" <<'EOF'
[{"script": "safety_guard.sh"}]
EOF
  cat > "$FX/book.json" <<'EOF'
{"admitted_ids": ["STR_1111_TEST_PG2"]}
EOF
  mkdir -p "$FX/agents"; : > "$FX/agents/a1.md"; : > "$FX/agents/a2.md"
}

run_chk() { # 픽스처 세트로 checker 실행 → exit code 반환, 출력은 $OUT
  OUT=$(env QVEST_BCC_CLAUDE_MD="$FX/CLAUDE.md" QVEST_BCC_BOOTSTRAP="$FX/bootstrap.sh" \
    QVEST_BCC_QVEST_MD="$FX/qvest.md" QVEST_BCC_SETTINGS="$FX/settings.json" \
    QVEST_BCC_DISPATCH="$FX/dispatch.json" QVEST_BCC_BOOK_STATE="$FX/book.json" \
    QVEST_BCC_AGENTS_DIR="$FX/agents" QVEST_BCC_LAWBOOK_INDEX="$FX/lawbook_index.md" \
    bash "$CHK" 2>&1)
  return $?
}

echo "=== test_boot_currency (자기-정합 검사 위반 주입) ==="

# ── T0. 깨끗한 픽스처 = 전체 PASS ────────────────────────────────────────────
mk_clean
if run_chk; then ok "T0 깨끗한 픽스처 전체 PASS"; else bad "T0 깨끗한 픽스처 전체 PASS" "$(echo "$OUT" | grep FAIL | head -2 | tr '\n' ' ')"; fi

# ── 위반 주입: 각각 반드시 exit 1 + 해당 축 FAIL ─────────────────────────────
inject() { # $1=이름 $2=축토큰 $3=주입함수
  mk_clean; "$3"
  if run_chk; then
    bad "$1" "위반이 통과됨 (검사 죽음)"
  elif echo "$OUT" | grep -q "FAIL  $2"; then
    ok "$1"
  else
    bad "$1" "exit 1이나 다른 축이 잡음: $(echo "$OUT" | grep FAIL | head -1)"
  fi
}

v1() { sed -i 's/Qvest v9\.9 부트스트랩/Qvest v9.8 부트스트랩/' "$FX/bootstrap.sh"; }
inject "V1 배너 버전 낡음 검출" "C1 " v1

v2() { sed -i 's/Testfam 7-Native/Oldfam 6-Native/g' "$FX/bootstrap.sh"; }
inject "V2 배너 모델 낡음 검출" "C2 " v2

v3() { sed -i 's/5-Mode/4-Mode/g' "$FX/bootstrap.sh"; }
inject "V3 배너 모드 낡음 검출" "C3 " v3

v4() { printf 'Cache_core: FULL (8)\n' >> "$FX/qvest.md"; }
inject "V4 낡은-기대값 재유입 검출" "C4 " v4

v5() { sed -i 's/실측 2종/실측 5종/' "$FX/qvest.md"; }
inject "V5 인벤토리 스냅샷 낡음 검출" "C5 " v5

v6() { sed -i 's/settings\.json 2 distinct/settings.json 9 distinct/' "$FX/CLAUDE.md"; }
inject "V6 훅 총계 낡음 검출" "C6 " v6

v7() { printf '\nSTR_9999_GHOST_PG2\n' >> "$FX/qvest.md"; }
inject "V7 PG2 참조 낡음 검출" "C7 " v7

v8() { sed -i 's/^## Active Version/## 다른 절/' "$FX/CLAUDE.md"; }
inject "V8 정본 파생 실패 = FAIL(통과 위장 금지)" "C0 " v8

v9a() { sed -i 's/^\*\*v9\.9 — 5-Mode/**v9.1 — 5-Mode/' "$FX/lawbook_index.md"; }
inject "V9a Lawbook INDEX 헤더 낡음 검출" "C8a " v9a

v9c() { sed -i '/Active SOT/s|$| + `qvest_ghost_sot.md` (합성2)|' "$FX/CLAUDE.md"; }
inject "V9c SOT 커버리지 누락 검출(신규 SOT가 INDEX에 없음)" "C8c " v9c

# ── T9. 파일 부재 = UNKNOWN FAIL (fail-open 금지) ────────────────────────────
mk_clean; rm -f "$FX/book.json"
if run_chk; then bad "T9 book_state 부재 = FAIL" "통과됨(fail-open)"; else
  echo "$OUT" | grep -q "C7 UNKNOWN" && ok "T9 book_state 부재 = UNKNOWN FAIL" || bad "T9" "다른 사유"; fi

# ── T10. Lawbook INDEX 부재 = UNKNOWN FAIL (fail-open 금지) ──────────────────
mk_clean; rm -f "$FX/lawbook_index.md"
if run_chk; then bad "T10 Lawbook INDEX 부재 = FAIL" "통과됨(fail-open)"; else
  echo "$OUT" | grep -q "C8a UNKNOWN" && ok "T10 Lawbook INDEX 부재 = UNKNOWN FAIL" || bad "T10" "다른 사유"; fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"boot_currency_guard\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
