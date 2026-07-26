#!/usr/bin/env bash
#==============================================================================
# boot_currency_check.sh — /qvest 부팅 시퀀스 자기-정합 검사 (2026-07-26 도훈 지시
# "부팅 최신화를 수동 지시 아니라 자동으로")
#
# 배경: 2026-07-26 부팅감사(wf_a8619abc)가 배너 2세대 낙후·체크리스트 낡은 기대값
#   (수리를 FAIL로 채점)·인벤토리 2주 낙후를 적발 — 전부 "사람이 눈치채고 지시해야"
#   고쳐지는 구조였다. 이 검사가 매 부팅 돌면서 드리프트를 **발생 즉시** WARN으로
#   노출한다 (예: 도훈이 CLAUDE.md를 v8.4로 올리는 순간 다음 부팅이 낡은 곳을 전부 짚음).
#
# 검사 축 (기대값은 하드코딩하지 않는다 — 전부 CLAUDE.md/파일시스템에서 파생):
#   C1 버전  : CLAUDE.md Active Version(vX.Y) ↔ bootstrap 배너 2곳·버전라벨·qvest.md 헤더
#   C2 모델  : CLAUDE.md 세션 모델(claude-fable-5 → "Fable 5") ↔ 배너 / 구모델 표기 잔존
#   C3 모드  : CLAUDE.md "N-Mode" ↔ 배너
#   C4 래칫  : 제거된 낡은 기대값 문자열의 재유입 금지 (qvest.md — 07-26 수리 회귀 가드)
#   C5 인벤토리: qvest.md "실측 N종" 스냅샷 ↔ 실제 .claude/agents/*.md 수
#   C6 훅 총계: CLAUDE.md "NN distinct .sh" ↔ 실측(직접∪dispatch)
#   C7 PG2   : qvest.md에 등장하는 *_PG2 id ↔ book_state.json admitted_ids
#
# 원칙: 부재/파싱실패 = UNKNOWN(FAIL 계상) — 0이나 통과로 위장 금지 (fail-open 금지).
# 출력: --boot  → [boot] 접두 1~N줄 (bootstrap용, WARN-only)
#       기본    → 상세 + 마지막 줄 JSON {"test":"boot_currency","pass":N,"fail":N,"total":N}
# 테스트 오버라이드: QVEST_BCC_CLAUDE_MD / _BOOTSTRAP / _QVEST_MD / _SETTINGS / _DISPATCH
#                    / _BOOK_STATE / _AGENTS_DIR  (08_Tests/hooks/test_boot_currency.sh 전용)
#==============================================================================
set -u

# ── PROJECT 해석 (표지 검증 — 존재≠정체) ─────────────────────────────────────
_MARKER="02_Infrastructure/ops/boot_currency_check.sh"
PROJECT=""
for c in "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)"; do
  if [ -n "$c" ] && [ -f "$c/$_MARKER" ]; then PROJECT="$c"; break; fi
done
if [ -z "$PROJECT" ]; then
  echo "[boot-currency] FATAL: PROJECT 해석 실패"; echo '{"test":"boot_currency","pass":0,"fail":1,"total":1}'; exit 1
fi

F_CLAUDE="${QVEST_BCC_CLAUDE_MD:-$PROJECT/CLAUDE.md}"
F_BOOT="${QVEST_BCC_BOOTSTRAP:-$PROJECT/02_Infrastructure/ops/bootstrap.sh}"
F_QVEST="${QVEST_BCC_QVEST_MD:-$PROJECT/.claude/commands/qvest.md}"
F_SETTINGS="${QVEST_BCC_SETTINGS:-$PROJECT/.claude/settings.json}"
F_DISPATCH="${QVEST_BCC_DISPATCH:-$PROJECT/02_Infrastructure/hooks/policies/router_dispatch.json}"
F_BOOK="${QVEST_BCC_BOOK_STATE:-$PROJECT/qepm/mailbox/governor/book_state.json}"
D_AGENTS="${QVEST_BCC_AGENTS_DIR:-$PROJECT/.claude/agents}"

MODE="${1:-detail}"
PASS=0; FAIL=0; WARN_LINES=()
ok()  { PASS=$((PASS+1)); [ "$MODE" != "--boot" ] && echo "  PASS  $1" || true; }
bad() { FAIL=$((FAIL+1)); WARN_LINES+=("$1"); [ "$MODE" != "--boot" ] && echo "  FAIL  $1" || true; }

# ── 정본 파생 (CLAUDE.md Active Version 절) ──────────────────────────────────
AV_LINE=$(sed -n '/^## Active Version/,/^$/p' "$F_CLAUDE" 2>/dev/null | grep -m1 '^\*\*Qvest v')
VER=$(printf '%s' "$AV_LINE" | grep -oE 'v[0-9]+\.[0-9]+' | head -1)
MODEL_ID=$(printf '%s' "$AV_LINE" | grep -oE 'claude-[a-z0-9-]+' | head -1)     # 예: claude-fable-5
N_MODE=$(printf '%s' "$AV_LINE" | grep -oE '[0-9]+-Mode' | head -1)             # 예: 4-Mode
# 모델 패밀리 라벨: claude-fable-5 → "Fable 5" (첫 글자 대문자 + 숫자)
MODEL_LABEL=""
if [ -n "$MODEL_ID" ]; then
  _fam=$(printf '%s' "$MODEL_ID" | sed 's/^claude-//;s/-[0-9]*$//')
  _num=$(printf '%s' "$MODEL_ID" | grep -oE '[0-9]+$')
  MODEL_LABEL="$(printf '%s' "${_fam^}") ${_num}"
fi

if [ -z "$VER" ] || [ -z "$MODEL_ID" ] || [ -z "$N_MODE" ]; then
  bad "C0 정본 파생 실패 — CLAUDE.md Active Version 절에서 버전/모델/모드 추출 불가 (ver='$VER' model='$MODEL_ID' mode='$N_MODE'). 절 포맷 변경 시 이 파서도 갱신 필요"
else
  ok "C0 정본 파생: $VER · $MODEL_ID($MODEL_LABEL) · $N_MODE"

  # ── C1 버전 정합 ──────────────────────────────────────────────────────────
  BOOT_BANNERS=$(grep -E '^echo "=== (Qvest|부트스트랩 완료)' "$F_BOOT" 2>/dev/null)
  if [ -n "$BOOT_BANNERS" ]; then
    if printf '%s' "$BOOT_BANNERS" | grep -qv "Qvest $VER"; then
      _stale=$(printf '%s' "$BOOT_BANNERS" | grep -v "Qvest $VER" | grep -oE 'v[0-9]+\.[0-9]+' | head -1)
      bad "C1 bootstrap 배너 버전 불일치 — 헌법 $VER vs 배너 '${_stale:-추출불가}' (bootstrap.sh 시작/완료 배너 갱신 필요)"
    else ok "C1 bootstrap 배너 = $VER (2곳)"; fi
  else
    bad "C1 bootstrap 배너 라인 자체를 못 찾음 — 배너 포맷 변경 시 이 검사 갱신 필요"
  fi
  if grep -qE "^echo \"$VER: " "$F_BOOT" 2>/dev/null; then
    ok "C1b 버전 상태라벨 = $VER:"
  else
    bad "C1b bootstrap 버전 상태라벨('$VER: ...') 부재 — 구버전 라벨 잔존 의심 ($(grep -coE '^echo "v[0-9]+\.[0-9]+: ' "$F_BOOT" 2>/dev/null || echo 0)건 발견)"
  fi
  if head -12 "$F_QVEST" 2>/dev/null | grep -q "$VER"; then
    ok "C1c qvest.md 헤더에 $VER"
  else
    bad "C1c qvest.md 헤더(frontmatter~제목)에 현행 $VER 부재 — description/제목 갱신 필요"
  fi

  # ── C2 모델 정합 ──────────────────────────────────────────────────────────
  if printf '%s' "$BOOT_BANNERS" | grep -q "$MODEL_LABEL"; then
    ok "C2 배너 모델 라벨 = $MODEL_LABEL"
  else
    bad "C2 bootstrap 배너에 현행 모델 라벨('$MODEL_LABEL') 부재 — 구모델 표기 잔존 의심"
  fi

  # ── C3 모드 정합 ──────────────────────────────────────────────────────────
  if printf '%s' "$BOOT_BANNERS" | grep -q "$N_MODE"; then
    ok "C3 배너 모드 = $N_MODE"
  else
    bad "C3 bootstrap 배너에 '$N_MODE' 부재 — 모드 수 변경 미반영"
  fi
fi

# ── C4 낡은-기대값 재유입 래칫 (07-26 수리 회귀 가드 — 이 목록은 '제거된 것'만) ──
RATCHET=('documented=8:' 'Cache_core: FULL (8)' 'pass=13 fail=0' 'warn=3 정상' 'Opus 4.8 Native · 3-Mode' 'STR_1631 + STR_1656')
R_HIT=""
for pat in "${RATCHET[@]}"; do
  if grep -qF "$pat" "$F_QVEST" 2>/dev/null; then R_HIT="$R_HIT'$pat' "; fi
done
if [ -n "$R_HIT" ]; then
  bad "C4 낡은 기대값 재유입 — qvest.md에 제거됐던 문자열 부활: $R_HIT(07-26 수리 회귀)"
else
  ok "C4 낡은-기대값 래칫 통과 (${#RATCHET[@]}패턴)"
fi

# ── C5 인벤토리 스냅샷 ↔ 실측 ────────────────────────────────────────────────
CLAIM_N=$(grep -oE '실측 [0-9]+종' "$F_QVEST" 2>/dev/null | head -1 | grep -oE '[0-9]+')
REAL_N=$(ls "$D_AGENTS"/*.md 2>/dev/null | wc -l | tr -d ' ')
if [ -z "$CLAIM_N" ]; then
  ok "C5 인벤토리: qvest.md에 개수 스냅샷 없음(순수 위임) — 드리프트 불가 형태"
elif [ "$CLAIM_N" = "$REAL_N" ]; then
  ok "C5 인벤토리 스냅샷 ${CLAIM_N}종 = 실측 ${REAL_N}종"
else
  bad "C5 인벤토리 낡음 — qvest.md 스냅샷 ${CLAIM_N}종 vs 실제 .claude/agents ${REAL_N}종 (스냅샷 갱신 또는 순수 위임 전환)"
fi

# ── C6 훅 총계: CLAUDE.md 선언 ↔ 실측 (직접∪dispatch distinct) ───────────────
CL_HOOKS=$(grep -oE 'settings\.json [0-9]+ distinct \.sh' "$F_CLAUDE" 2>/dev/null | head -1 | grep -oE '[0-9]+')
if [ -f "$F_SETTINGS" ] && [ -f "$F_DISPATCH" ]; then
  REAL_HOOKS=$( { grep -oE '[A-Za-z0-9_]+\.sh' "$F_SETTINGS"; \
                  grep -oE '"script"[[:space:]]*:[[:space:]]*"[^"]*"' "$F_DISPATCH" | sed 's|.*/||;s/"$//'; } \
                | sort -u | wc -l | tr -d ' ')
  if [ -z "$CL_HOOKS" ]; then
    bad "C6 CLAUDE.md에서 훅 총계 선언('NN distinct .sh')을 못 찾음 — 포맷 변경 시 파서 갱신"
  elif [ "$CL_HOOKS" = "$REAL_HOOKS" ]; then
    ok "C6 훅 총계 ${CL_HOOKS} = 실측 ${REAL_HOOKS} (직접∪dispatch distinct)"
  else
    bad "C6 훅 총계 낡음 — CLAUDE.md '${CL_HOOKS} distinct' vs 실측 ${REAL_HOOKS} (훅 등재/해제 후 헌법 미갱신)"
  fi
else
  bad "C6 UNKNOWN — settings.json 또는 router_dispatch.json 부재 (통과로 위장 금지)"
fi

# ── C7 PG2 참조: qvest.md의 *_PG2 id ↔ book_state admitted_ids ───────────────
if [ -f "$F_BOOK" ]; then
  QV_PG2=$(grep -oE 'STR_[0-9]+[A-Za-z0-9_]*_PG2' "$F_QVEST" 2>/dev/null | sort -u)
  if [ -z "$QV_PG2" ]; then
    ok "C7 PG2: qvest.md에 book id 하드코딩 없음(순수 위임)"
  else
    MISS7=""
    for id in $QV_PG2; do
      grep -qF "\"$id\"" "$F_BOOK" || MISS7="$MISS7$id "
    done
    if [ -z "$MISS7" ]; then
      ok "C7 PG2 참조 = book_state admitted 일치 ($(printf '%s' "$QV_PG2" | wc -l | tr -d ' ')건)"
    else
      bad "C7 PG2 참조 낡음 — qvest.md의 ${MISS7}가 book_state.json admitted_ids에 없음 (book 교체 미반영)"
    fi
  fi
else
  bad "C7 UNKNOWN — book_state.json 부재"
fi

# ── 출력 ─────────────────────────────────────────────────────────────────────
if [ "$MODE" = "--boot" ]; then
  if [ "$FAIL" -eq 0 ]; then
    echo "[boot] boot-currency: OK — 부팅 시퀀스 ↔ 헌법($VER·$MODEL_LABEL·$N_MODE)·실측 정합 ($PASS축)"
  else
    echo "[boot] WARN: boot-currency 드리프트 ${FAIL}건 — 부팅 시퀀스가 헌법/실측보다 낡음. 세션이 즉시 수리할 것 (수동 지시 불요 원칙, 2026-07-26):"
    for w in "${WARN_LINES[@]}"; do echo "[boot]    ✗ $w"; done
    echo "[boot]    상세: bash 02_Infrastructure/ops/boot_currency_check.sh"
  fi
else
  echo ""
  echo "boot-currency: PASS=$PASS FAIL=$FAIL"
  echo "{\"test\":\"boot_currency\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
fi
[ "$FAIL" -eq 0 ] || exit 1
