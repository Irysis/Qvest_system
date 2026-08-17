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
#   C8a 항해도: CLAUDE.md Active Version ↔ 00_Lawbook/INDEX.md 헤더 버전
#   C8c 커버리지: CLAUDE.md "★ Active SOT" 나열 ⊆ 00_Lawbook/INDEX.md 인용
#   C9  환경  : python-policy.md 가 선언한 ML 실행기(venv)가 실제로 실행 가능한가
#
# C8 배경 (2026-08-16 감사 wf_31a04a99): 00_Lawbook/INDEX.md 가 v8.1.0(06-12)에서 2개월·
#   헌법 4회 전이분 낙후. 원인 1위는 "안 열어서"가 아니라 **부분 갱신이 버전 배너를 안
#   고치는 것** — 07-03·07-04 두 번 편집됐는데 헤더는 06-12 그대로여서 한 문서 안에 세
#   vintage 가 공존했다. 원인 2위는 낙후 감시 대상이 전부 하드코딩 열거라 이 파일이 어느
#   목록에도 없던 것. C8a 가 1위를, "대상을 CLAUDE.md에서 파생"하는 이 파일의 설계 계약이
#   2위를 각각 막는다. 그 문서는 자동 생성 대상이 아니다(빌더 존 목록 4개에 부재) —
#   기계는 낙후를 **알리기만** 하고 갱신은 사람이 한다(WARN-only).
#   ※C8b(개수 박제 ↔ handbook_facts.json 실측 대조)는 **미구현** — key 가 영문
#     (axioms_active)이고 문서는 한국어라 key→문구 매핑 테이블이 필요한데, 그 테이블
#     자체가 이 저장소가 반복 실패한 "자유 형식 패턴 감사" 형태다. 생산자(handbook_facts
#     _audit.sh)가 doc-facing 라벨을 함께 emit 하면 매핑 없이 가능해진다.
#
# 원칙: 부재/파싱실패 = UNKNOWN(FAIL 계상) — 0이나 통과로 위장 금지 (fail-open 금지).
# 출력: --boot  → [boot] 접두 1~N줄 (bootstrap용, WARN-only)
#       기본    → 상세 + 마지막 줄 JSON {"test":"boot_currency","pass":N,"fail":N,"total":N}
# 테스트 오버라이드: QVEST_BCC_CLAUDE_MD / _BOOTSTRAP / _QVEST_MD / _SETTINGS / _DISPATCH
#                    / _BOOK_STATE / _AGENTS_DIR / _LAWBOOK_INDEX
#                    (08_Tests/hooks/test_boot_currency.sh 전용)
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
F_LAWBOOK="${QVEST_BCC_LAWBOOK_INDEX:-$PROJECT/00_Lawbook/INDEX.md}"
F_PYPOLICY="${QVEST_BCC_PY_POLICY:-$PROJECT/.claude/rules/python-policy.md}"

MODE="${1:-detail}"
PASS=0; FAIL=0; WARN_LINES=()
ok()  { PASS=$((PASS+1)); [ "$MODE" != "--boot" ] && echo "  PASS  $1" || true; }
bad() { FAIL=$((FAIL+1)); WARN_LINES+=("$1"); [ "$MODE" != "--boot" ] && echo "  FAIL  $1" || true; }

# ── 정본 파생 (CLAUDE.md Active Version 절) ──────────────────────────────────
# (수리) 구 sed range는 헤더 직후 빈 줄에서 종료돼 본문을 못 잡았다 — awk로 헤더 후 첫 매치
AV_LINE=$(awk '/^## Active Version/{f=1;next} f && /^\*\*Qvest v/{print;exit}' "$F_CLAUDE" 2>/dev/null)
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

  # ── C8a 항해도 배너 정합: 헌법 버전 ↔ 00_Lawbook/INDEX.md 헤더 ─────────────
  # 시간 문턱(mtime N일)을 쓰지 않는다 — 헌법 문자열이 실제로 움직였을 때만 발화해야
  # 오탐이 없다(고정 문턱은 분포가 이동하면 정상을 결함으로 신고한다).
  if [ -f "$F_LAWBOOK" ]; then
    if head -8 "$F_LAWBOOK" 2>/dev/null | grep -q "$VER"; then
      ok "C8a Lawbook INDEX 헤더 = $VER"
    else
      _lw=$(head -8 "$F_LAWBOOK" 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+' | head -1)
      bad "C8a Lawbook INDEX 헤더 낡음 — 헌법 $VER vs INDEX '${_lw:-표기없음}' (00_Lawbook/INDEX.md 는 자동 생성 대상이 아니므로 사람이 갱신)"
    fi
  else
    bad "C8a UNKNOWN — 00_Lawbook/INDEX.md 부재 (통과로 위장 금지)"
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
  # (수리) dispatch 엔트리는 bare 파일명("script": "safety_guard.sh") — 경로절단 sed로는
  #   접두사가 안 벗겨져 union이 부풀었다(48 오측). 접두사-절단 후 경로절단. 또 union을
  #   02_Infrastructure/hooks/ 실존 파일로 필터 — 비-훅 토큰(bootstrap.sh)을 배제해
  #   헌법 총계와 같은 모집단으로 비교.
  REAL_HOOKS=$( { grep -oE '[A-Za-z0-9_]+\.sh' "$F_SETTINGS"; \
                  grep -oE '"script"[[:space:]]*:[[:space:]]*"[^"]*"' "$F_DISPATCH" \
                    | sed 's/.*"script"[^"]*"//;s/"$//;s|.*/||'; } \
                | tr -d '\r' | sort -u \
                | while IFS= read -r _h; do [ -f "$PROJECT/02_Infrastructure/hooks/$_h" ] && echo "$_h"; done \
                | wc -l | tr -d ' ')
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

# ── C8c SOT 커버리지: CLAUDE.md ★Active SOT ⊆ Lawbook INDEX ──────────────────
# basename 으로 비교한다 — 경로 표기(전체경로/축약)가 정규화돼도 불변이라, 병행 중인
# 경로 정규화 작업과 충돌하지 않는다. 대상 목록은 CLAUDE.md 에서 파생(하드코딩 금지).
if [ -f "$F_LAWBOOK" ]; then
  SOT_LINE=$(grep -m1 'Active SOT' "$F_CLAUDE" 2>/dev/null)
  if [ -z "$SOT_LINE" ]; then
    bad "C8c CLAUDE.md에서 '★ Active SOT' 절을 못 찾음 — 절 포맷 변경 시 이 파서도 갱신 필요"
  else
    MISS8=""; N8=0
    for _f in $(printf '%s' "$SOT_LINE" | grep -oE '`[^`]+\.md`' | tr -d '`' | sed 's|.*/||' | sort -u); do
      N8=$((N8+1))
      grep -qF "$_f" "$F_LAWBOOK" || MISS8="$MISS8$_f "
    done
    if [ "$N8" -eq 0 ]; then
      bad "C8c Active SOT 절에서 .md 참조 0건 추출 — 파서 갱신 필요 (통과로 위장 금지)"
    elif [ -z "$MISS8" ]; then
      ok "C8c SOT 커버리지 = INDEX가 Active SOT ${N8}건 전부 인용"
    else
      bad "C8c SOT 커버리지 낡음 — CLAUDE.md Active SOT 중 ${MISS8}가 00_Lawbook/INDEX.md 에 없음 (헌법 전이 후 INDEX §1 미갱신)"
    fi
  fi
fi

# ── C9 환경 정합: 선언된 ML 실행기가 실재하나 ────────────────────────────────
# 2026-08-16 실사고: .venv_qvest_ml 이 16:02 에 비워졌는데(생성 06-10) 부팅은 아무것도
#   말하지 않았고, 무관한 배터리 실패를 쫓다 우연히 발견했다. python-policy.md 는 "환경
#   선언은 라운드 전제이므로 착수 전 실측"을 요구하지만 그 실측을 기계가 하지 않았다.
#   결손 시 v8.4 Lane A(분포-표적 ML) 가 착수 불가이므로 알파 라운드를 직접 막는다.
# 기대 경로는 하드코딩하지 않는다 — python-policy.md 선언에서 파생(C0 계약과 동일).
if [ -f "$F_PYPOLICY" ]; then
  DECL_PY=$(grep -oE '`[^`]*\.venv[^`]*python\.exe`' "$F_PYPOLICY" 2>/dev/null | tr -d '`' | head -1)
  if [ -z "$DECL_PY" ]; then
    bad "C9 python-policy.md 에서 ML 실행기 선언을 못 찾음 — 선언 포맷 변경 시 이 파서도 갱신 필요"
  else
    case "$DECL_PY" in /*|[A-Za-z]:*) _pypath="$DECL_PY" ;; *) _pypath="$PROJECT/$DECL_PY" ;; esac
    if [ -x "$_pypath" ]; then
      ok "C9 ML 실행기 실재 = $DECL_PY"
    else
      bad "C9 선언된 ML 실행기 부재/실행불가 — python-policy.md '$DECL_PY' (ML 라운드 착수 불가. 선언≠실측 — venv 재생성 또는 선언 갱신 필요)"
    fi
  fi
else
  bad "C9 UNKNOWN — python-policy.md 부재 (통과로 위장 금지)"
fi

# ── C10 삭제 감시 카나리아 생존 ──────────────────────────────────────────────
# 2026-08-16: venv 가 16:02:11 에 비워졌으나 파일시스템 감사가 꺼져 있어 주체가 영구
#   추적 불가로 확정됐다. 이후 감사(4660/4663)+폴더 SACL 을 걸고 양성 대조로 기록됨을
#   실증했지만, Security 로그는 관리자 권한이라 이 검사가 읽을 수 없다. 대신 표식 파일의
#   생존만 본다 — 사라졌으면 "삭제 주체가 실재"이고, 그때 관리자가 로그를 조회하면 된다.
#   ★이 축은 "언제"만 답한다. "누가"는 관리자 조회 몫 — 그 한계를 메시지에 적어 둔다.
if [ -n "${_pypath:-}" ]; then
  _venvdir=$(dirname "$(dirname "$_pypath")")
  if [ -d "$_venvdir" ]; then
    _can=$(ls "$_venvdir"/.canary_* 2>/dev/null | head -1)
    if [ -n "$_can" ]; then
      ok "C10 삭제 감시 카나리아 생존 ($(basename "$_can"))"
    else
      bad "C10 카나리아 소실 — venv 트리의 삭제 감시 표식이 사라짐. 의도적 재생성이면 표식을 다시 놓을 것. 아니면 관리자 PowerShell 로 주체 조회: Get-WinEvent -FilterHashtable @{LogName='Security';Id=4660,4663}"
    fi
  else
    bad "C10 UNKNOWN — venv 디렉터리 부재 ($_venvdir) — 카나리아 판정 불가"
  fi
else
  bad "C10 UNKNOWN — 실행기 경로 파생 실패로 venv 디렉터리를 특정 못 함"
fi

# ── C11 감사 감시 생존: 삭제 주체를 볼 수 있는 상태인가 ──────────────────────
# C10 은 "표식이 사라졌다"까지만 말한다. "누가 지웠나"는 Security 로그(4660/4663)에
#   있는데 그건 관리자 권한이라 이 검사가 못 읽는다. 그래서 상승 권한 스케줄 작업
#   (Qvest_AuditWatch.bat → audit_watch.ps1)이 대신 읽어 평탄 JSON 으로 떨구고,
#   여기서는 그 **결론만** 읽는다.
# ★세 가지를 한꺼번에 본다 — 어느 하나만 빠져도 "조용함"이 "안전"으로 위장된다:
#   ① 디제스트가 신선한가(작업이 살아 있나) ② 감사 정책이 켜져 있나 ③ SACL 이 붙어 있나
#   특히 ①이 없으면 작업이 죽은 순간부터 영원히 초록이다(2026-08-16 에 감사 자체가
#   꺼져 있어 삭제 주체를 영구히 잃은 것과 같은 구조).
F_AUDITW="${QVEST_BCC_AUDIT_WATCH:-$PROJECT/.cache/audit_watch_status.json}"
AUDITW_MAX_AGE_H="${QVEST_BCC_AUDIT_MAX_AGE_H:-30}"
if [ ! -f "$F_AUDITW" ]; then
  bad "C11 감사 감시 미배선 — $F_AUDITW 부재. 삭제 주체를 볼 수 없다(4660/4663 는 관리자만 읽음). 등록: 02_Infrastructure/ops/scheduler/Qvest_AuditWatch.bat 을 '가장 높은 수준의 권한으로 실행'으로 예약"
else
  _gen=$(grep -oE '"generated_epoch"[[:space:]]*:[[:space:]]*[0-9]+' "$F_AUDITW" | grep -oE '[0-9]+$' | head -1)
  _now=$(date +%s)
  if [ -z "$_gen" ]; then
    bad "C11 UNKNOWN — 디제스트에서 generated_epoch 파싱 실패 (포맷 변경 시 파서 갱신). 통과로 위장 금지"
  elif [ $(( (_now - _gen) / 3600 )) -gt "$AUDITW_MAX_AGE_H" ]; then
    bad "C11 감사 디제스트 정체 $(( (_now - _gen) / 3600 ))h (> ${AUDITW_MAX_AGE_H}h) — 감시 작업이 돌지 않는다. 죽은 감시는 '이벤트 0'과 구분되지 않는다"
  else
    _verd=$(grep -oE '"verdict"[[:space:]]*:[[:space:]]*"[A-Z]+"' "$F_AUDITW" | grep -oE '[A-Z]+"$' | tr -d '"' | head -1)
    case "$_verd" in
      OK)       ok "C11 감사 감시 생존 (정책 on · SACL 부착 · 삭제 이벤트 0)" ;;
      DEGRADED) bad "C11 감사 감시 불능(DEGRADED) — 대개 권한 부족. 작업을 '가장 높은 수준의 권한으로 실행'으로 재등록할 것. 사유: $(grep -oE '"[^"]*(NOT ELEVATED|UNPARSEABLE|threw)[^"]*"' "$F_AUDITW" | head -1)" ;;
      ALERT)    bad "C11 ★감사 경보(ALERT) — $(grep -oE '"[^"]*(AUDIT POLICY OFF|SACL MISSING|WATCHED PATH ABSENT|DELETION ACTIVITY)[^"]*"' "$F_AUDITW" | head -2 | tr '\n' ' ')" ;;
      *)        bad "C11 UNKNOWN — verdict 파싱 실패 (값='$_verd')" ;;
    esac
  fi
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
