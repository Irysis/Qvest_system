#!/usr/bin/env bash
# stranded_repairs_audit.sh — 좌초 수리(stranded repair) 감사기
#
# 목적: 병렬 세션 worktree에 갇혀 main에 도달하지 못한 수리를 탐지·분류·등재한다.
#   근본: bootstrap 전문에 git 점검이 0건이라 "수리는 됐는데 worktree에 갇힘" 상태가 안 보였음.
#   동일 패턴 실사고 2건 — benchmark date32 writer(미커밋 6일 방치) · lcode_harvester family 수리
#   (메모리에 '미병합=게이트'로 기록). 감지 장치 부재가 공통 근본원인.
#
# bootstrap §4h(부팅 시점 WARN)의 상위 버전:
#   §4h  = 존재/개수만 · 세션 시작 때만 · 무인 시간대 방치 못 잡음
#   본 스크립트 = 파일 단위 triage(a/b/c) + 레지스트리 영속화 + 텔레그램 경보 + prune 후보
#
# triage 분류 (worktree 로컬 변경의 '추가 라인'이 main 파일에 존재하는가):
#   (a) merged_upstream — 전량 존재. worktree는 stale 사본. 안전하게 정리 가능
#   (b) lost           — 전무. main에 없는 진짜 유실 ★조치 필요
#   (c) partial        — 일부만. 별도 경로 반영 또는 충돌 — 수동 확인
#
# 읽기 전용: worktree에 절대 쓰지 않는다(status/diff/rev-list/log만). 타 세션 작업 무간섭.
#
# 사용:
#   bash 02_Infrastructure/ops/stranded_repairs_audit.sh              # 감사 + JSON + 텔레그램(조건부)
#   bash 02_Infrastructure/ops/stranded_repairs_audit.sh --no-telegram
#   bash 02_Infrastructure/ops/stranded_repairs_audit.sh --quiet      # JSON만, stdout 최소
#
# 산출: 06_Registry/stranded_repairs.json
# 2026-07-25 신규 (도훈 승인 next_probe ②③)

set -uo pipefail

PROJECT="${QM_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
cd "$PROJECT" 2>/dev/null || { echo "[stranded] PROJECT 해석 실패: $PROJECT" >&2; exit 0; }

OUT="$PROJECT/06_Registry/stranded_repairs.json"
STALE_DAYS="${STRANDED_STALE_DAYS:-3}"
MAIN_REF="${STRANDED_MAIN_REF:-main}"
MAX_LINES_PER_FILE=200          # triage 대조 상한 (대용량 diff 방어)
# worktree 1개당 triage 경로 상한 (2026-08-13). 초과분은 **미검으로 명시 보고**한다 — 무음 절단 금지.
MAX_FILES_PER_WT="${STRANDED_MAX_FILES:-400}"
DO_TG=1; QUIET=0; DO_PRUNE=0
for a in "$@"; do
  case "$a" in
    --no-telegram) DO_TG=0 ;;
    --quiet)       QUIET=1 ;;
    --prune)       DO_PRUNE=1 ;;
  esac
done
say() { [ "$QUIET" -eq 1 ] || echo "$@"; }
# hb = heartbeat: --quiet 여도 반드시 남긴다. 무인 로그가 비면 "돌긴 했나"를 답할 수 없고,
#      그건 본 스크립트가 고치려는 문제(침묵 실패)와 같은 부류다.
hb()  { echo "[$(date '+%F %T')] $*"; }

command -v git >/dev/null 2>&1 || { echo "[stranded] git 없음 — skip" >&2; exit 0; }
git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1 || { echo "[stranded] git repo 아님 — skip" >&2; exit 0; }

TMP="$(mktemp -d 2>/dev/null || echo /tmp/stranded_$$)"; mkdir -p "$TMP"
cleanup() { rm -rf "$TMP" 2>/dev/null || true; }
trap cleanup EXIT

jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r//g'; }

# ── 정규화: 선행/후행 공백 제거 + 빈 줄·주석기호단독 제외 (형식 차이로 인한 오탐 축소)
norm() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -vE '^$|^#$|^//$' ; }

# ── 파일 1건 triage: 추가 라인 중 main 파일에 없는 개수 + main 고유 줄 수
#    stdout: "<추가라인수> <미존재수> <main고유수>"
#    $1=추가라인 원본(raw) 파일 · $2=경로 · $3=worktree 판 전체 파일(없으면 "")
#    main고유수 = worktree 판에는 없고 main 에만 있는 줄 → **방향 판정의 내용 근거**(아래 supersede 절).
triage_added() {
  local addsrc="$1" f="$2" theirs="${3:-}"
  norm < "$addsrc" | head -n "$MAX_LINES_PER_FILE" | sort -u > "$TMP/added.txt"
  local tot; tot=$(wc -l < "$TMP/added.txt" | tr -d ' ')
  if [ -f "$PROJECT/$f" ]; then
    norm < "$PROJECT/$f" | sort -u > "$TMP/target.txt"
  else
    : > "$TMP/target.txt"
  fi
  local missing=0 extra=0
  if [ "${tot:-0}" -gt 0 ]; then
    missing=$(comm -23 "$TMP/added.txt" "$TMP/target.txt" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ -n "$theirs" ] && [ -f "$theirs" ] && [ -f "$PROJECT/$f" ]; then
    norm < "$theirs" | sort -u > "$TMP/theirs_n.txt"
    extra=$(comm -13 "$TMP/theirs_n.txt" "$TMP/target.txt" 2>/dev/null | wc -l | tr -d ' ')
  fi
  echo "${tot:-0} ${missing:-0} ${extra:-0}"
}

verdict_of() {   # $1=tot $2=missing
  if   [ "$1" -eq 0 ];      then echo "deletion_only"; return; fi
  if   [ "$2" -eq 0 ];      then echo "merged_upstream"; return; fi
  if   [ "$2" -eq "$1" ];   then echo "lost"; return; fi
  # 80%+ 미존재 = 사실상 유실 (partial 안에서 '1줄 다름'과 '20/22 없음'을 구분)
  if [ $(( $2 * 100 / $1 )) -ge 80 ]; then echo "mostly_lost"; else echo "partial"; fi
}

# ── 재분류 2종 (2026-08-08 수리) ─────────────────────────────────────────────
# 실측: 유실 36건 중 **26건(72%)이 append-only 원장**, 나머지 19건이 **이미 상위판으로
# 교체된 구판**, 진짜 미도달은 7건뿐이었다. 즉 경보의 80%가 허위였고 진짜 7건은 그 밑에 묻혀 있었다.
#
# (i) append-only 원장 — 각 worktree 세션이 자기 훅 이벤트를 덧붙이고 main 도 자기 것을
#     덧붙인다. 두 계열은 설계상 영원히 합쳐지지 않는다. 수리가 아니라 로그 분기다.
#     이걸 세는 한 경보는 **구조적으로 0 이 될 수 없다** — 상시 발화 = 죽은 경보.
LEDGER_RE="${STRANDED_LEDGER_RE:-(^|/)(events|ast_structure_log)\.jsonl$}"
is_ledger() { printf '%s' "$1" | grep -qE "$LEDGER_RE"; }

# (i-b) 파생 스크래치 — 실행 원 로그(`_*.txt|.log|.out`)와 백업(`*.bak*`)은 *수리*가 아니다.
#     artifact-storage.md §55 는 이들을 애초에 `01_reports/`·인프라 디렉터리에 두지 못하게
#     하고(§61 리텐션 30일 자동삭제), 그 증류본(보고서 .md·결과 .json)이 canonical 이다.
#     ★판별은 **파일명 모양이 아니라 부류**다 — §56 이 명시하듯 `_` 접두 자체는 private
#     *모듈*(실소비자 있는 `_root.R`·`_query.py` 등)에도 쓰인다. 그래서 소스 확장자
#     (`.R`/`.py`/`.sh`)는 제외 대상에서 **뺀다**: 스크래치로 접히는 건 파생 산출물뿐이다.
#     실증 2026-08-08: nostalgic-borg 의 `.bak`(477,388 B)은 git c5138e33 과 **바이트 동일**이고,
#     `_*.txt` 3건은 main 의 `factor_db_dedup_20260802.md`(30 KB)로 이미 증류돼 있었다.
SCRATCH_RE="${STRANDED_SCRATCH_RE:-((^|/)_[^/]*\.(txt|log|out)$|\.bak([^/]*)?$)}"
is_scratch() { printf '%s' "$1" | grep -qE "$SCRATCH_RE"; }

# (ii) superseded — main 이 그 경로에서 worktree 보다 **앞서 나간** 경우.
#     triage 는 "이 줄들이 main 에 있나"만 묻는다. **방향 개념이 없다.** 그래서 통합이
#     성공해 main 이 개선될수록(구판 줄이 더 나은 줄로 교체됨) 경보가 **커진다** — 신호가 뒤집힌다.
#     ★실증 2026-08-08 (내용 대조, mtime 추정 아님):
#       · test_deployed_holdings_check.sh — main 371줄이 worktree 246줄의 상위판
#         (_pick_proj BASH_SOURCE-우선 + _py_works 기능 프로브 보유)인데 '110줄 유실'로 계상
#       · r-portability.md — main §④-b 가 자신을 "이 계약의 단일 정본"으로 선언한 확장판인데
#         구판 초안의 26줄이 '유실'로 계상
#     판정 근거는 **git 이력**(main 이 그 경로를 마지막으로 커밋한 시각) 우선. main 에 파일이
#     아예 없으면 교체일 수 없으므로 재분류하지 않는다(진짜 유실은 그대로 유실로 남는다).
#
#     ★2026-08-13 수리 — **시각만으로는 방향을 못 정한다.**
#       triage 는 "이 줄들이 main 에 있나"를 묻는데 recency 는 "이 경로가 나중에 손댔나"를
#       묻는다. **다른 질문이다.** 그래서 bulk auto-commit 한 번이면 무조건 "나중"이 된다.
#       실측: eloquent-cray 의 frontier_queue_io.R 은 CAS·뮤텍스·churn 예산 **162줄**을 담은
#       동시쓰기 가드였는데(FQ-122 갱신 2회 유실의 직접 대응), main 쪽은 3113ac4f 가 무관한
#       `perl=TRUE` **10줄**을 넣었을 뿐이다. 그 10줄이 더 최신이라는 이유로 127/130 미도달이
#       `superseded_upstream` 으로 접혀 경보에서 **사라졌다** — 그동안 main 의 프론티어 큐
#       writer 는 CAS 없이 돌았다. ★"10줄이 162줄을 대체했다"는 판정을 시각 비교가 만들어낸다.
#       ⇒ 재분류에 **내용 근거**를 요구한다: main 고유 줄(worktree 판에 없는 main 줄)이
#         미도달 줄 수 이상일 것. 상위판 교체라면 main 은 자기 몫의 내용을 그만큼 갖고 있다.
#         (실측 대조: test_deployed_holdings_check.sh 는 main 371줄이 worktree 246줄의 상위판
#          → 조건 충족 → 교체 유지. frontier_queue_io.R 은 미충족 → 유실 유지.)
#       근거 수치는 `main_extra_lines` 로 산출물에 남긴다 — 판정이 사후 감사 가능해야 한다.
main_recency() {   # $1=path → main 이 그 경로를 마지막으로 갱신한 epoch (0 = 근거 없음)
  local p="$1" ct
  ct=$(git -C "$PROJECT" log -1 --format=%ct "$MAIN_REF" -- "$p" 2>/dev/null || echo 0)
  ct="${ct:-0}"
  # 미추적(파이프라인 생성 산출물 등)이면 git 이력이 없다 — 그때만 파일 mtime 으로 낙하
  if [ "$ct" -eq 0 ] && [ -e "$PROJECT/$p" ]; then
    ct=$(stat -c %Y "$PROJECT/$p" 2>/dev/null || echo 0)
  fi
  echo "${ct:-0}"
}

NOW_S=$(date +%s)
N_WT=0; N_DIRTY=0; N_AHEAD=0; N_STALE=0; N_LOST=0; N_PARTIAL=0; N_PRUNE=0
N_LEDGER=0; N_SUPER=0; N_SCRATCH=0; N_CAPPED=0
WT_JSON=""; PRUNE_JSON=""; LOST_SUMMARY=""
# ── (v10 2026-09-02) 세대(版) 경계 — pre-v10 레거시 worktree 분류 ──────────────────────────
#   v10 재편(2026-08-29 11:21, 태그 pre-v10-2layer) 이전에 브랜치 tip 이 멎은 worktree 의 '유실' 은 수리 유실이 아니라
#   폐기된 판의 잔재다. 구판은 세대 개념이 없어 15개 worktree 의 유실 127건을 08-29 이후 매일 같은 수치로 재발송했다
#   (도훈 지목 2026-09-02). 레거시는 **집계·JSON 에 남기되 경보 계수(N_LOST/N_PARTIAL/충돌)에서 뺀다** — 처분
#   (remove/cherry-pick)은 도훈 결정. 경계 ref 가 없으면(픽스처·타 저장소) 0 → 분기 미발화(종전 동작).
#   v10 이후 손댄 worktree(미커밋 파일 mtime ≥ 경계)는 레거시로 접지 않는다.
LEGACY_REF="${STRANDED_LEGACY_REF:-pre-v10-2layer}"
LEGACY_EPOCH=$(git -C "$PROJECT" log -1 --format=%ct "$LEGACY_REF" -- 2>/dev/null || echo 0); LEGACY_EPOCH="${LEGACY_EPOCH:-0}"
N_LEGACY_LOST=0; N_LEGACY_PARTIAL=0; N_LEGACY_WT=0; LEGACY_SUMMARY=""
: > "$TMP/touched.txt"   # "<path>\t<branch>" — 동시 수정 충돌 탐지용

while IFS='|' read -r wt br; do
  [ -z "${wt:-}" ] && continue
  case "$wt" in *worktrees*) ;; *) continue ;; esac
  [ -d "$wt" ] || continue
  N_WT=$((N_WT + 1))
  sb="${br#refs/heads/}"
  # ★라벨은 브랜치명이 아니라 **worktree 디렉터리명**을 쓴다.
  #   실측(2026-07-26): frosty-torvalds-5e24f0 디렉터리가 claude/angry-bhabha-b50a41 브랜치를
  #   체크아웃한 상태였고, 브랜치명으로 라벨링하니 "존재하지 않는 worktree"로 보고돼
  #   소멸한 유령처럼 보였다. 디렉터리와 브랜치는 이름이 다를 수 있다 — 한 이름으로 두 정체성을
  #   가리키지 말 것(오늘 반복 적발한 계통).
  short="$(basename "$wt")"
  brshort="$(basename "$sb")"

  ahead=$(git -C "$PROJECT" rev-list --count "${MAIN_REF}..${sb}" 2>/dev/null || echo 0)
  ct=$(git -C "$PROJECT" log -1 --format=%ct "$sb" 2>/dev/null || echo 0)
  age=-1; [ "${ct:-0}" -gt 0 ] && age=$(( (NOW_S - ct) / 86400 ))

  git -C "$wt" --no-optional-locks status --porcelain 2>/dev/null > "$TMP/st.txt" || : > "$TMP/st.txt"
  dirty=$(wc -l < "$TMP/st.txt" | tr -d ' ')

  # 레거시 판정 (v10): 브랜치 tip < v10 경계 ∧ (미커밋 없음 ∨ 미커밋 파일 최신 mtime < 경계)
  is_legacy=0
  if [ "${LEGACY_EPOCH:-0}" -gt 0 ] && [ "${ct:-0}" -gt 0 ] && [ "$ct" -lt "$LEGACY_EPOCH" ]; then
    is_legacy=1
    if [ "${dirty:-0}" -gt 0 ] 2>/dev/null; then
      while IFS= read -r _sl; do
        [ -n "${_sl:-}" ] || continue
        _p="${_sl:3}"; _p="${_p#\"}"; _p="${_p%\"}"
        _m=$(stat -c %Y "$wt/$_p" 2>/dev/null || echo 0)
        if [ "${_m:-0}" -ge "$LEGACY_EPOCH" ]; then is_legacy=0; break; fi
      done < "$TMP/st.txt"
    fi
  fi
  [ "$is_legacy" -eq 1 ] && N_LEGACY_WT=$((N_LEGACY_WT + 1))

  [ "${ahead:-0}" -gt 0 ] 2>/dev/null && N_AHEAD=$((N_AHEAD + 1))
  [ "${dirty:-0}" -gt 0 ] 2>/dev/null && N_DIRTY=$((N_DIRTY + 1))
  is_stale=0
  if [ "${dirty:-0}" -gt 0 ] 2>/dev/null && [ "${age:-0}" -ge "$STALE_DAYS" ] 2>/dev/null; then
    is_stale=1; N_STALE=$((N_STALE + 1))
  fi

  # ③ prune 후보: 클린 ∧ 미병합 0 → 안전 제거 대상 (자동 제거 안 함 — 후보 보고만)
  if [ "${dirty:-0}" -eq 0 ] 2>/dev/null && [ "${ahead:-0}" -eq 0 ] 2>/dev/null; then
    N_PRUNE=$((N_PRUNE + 1))
    printf '%s\t%s\n' "$wt" "$sb" >> "$TMP/prune.txt"
    [ -n "$PRUNE_JSON" ] && PRUNE_JSON="$PRUNE_JSON,"
    PRUNE_JSON="$PRUNE_JSON
      {\"branch\":\"$(jesc "$sb")\",\"path\":\"$(jesc "$wt")\",\"age_days\":$age}"
  fi

  # ── 대상 경로 = 미커밋(dirty) ∪ **미병합 커밋**(${MAIN_REF}...${sb})
  #   ★2026-08-13 수리 — 사각지대. 구판은 dirty 만 triage 하고 커밋된 미병합분은 충돌 후보로만
  #     넘겼다. 그런데 이 저장소는 Stop 훅 auto-commit 이 세션 변경분을 **자기 브랜치에** 커밋한다
  #     → 파일이 dirty→committed 로 옮겨가는 순간 유실 계수에서 사라진다. main 에는 여전히 없는데.
  #     실측(08-13): 경보는 "유실 4" 였는데, 미병합 커밋에 든 main-부재 파일이 **257건**이었다
  #     (jovial-mcnulty 254 · agitated-jones 3). 08-09 에 유실 29로 잡혔던 fq170 산출물 26건도
  #     고쳐진 게 아니라 **커밋되어 조용해진** 것이었다(29→4 감소의 정체).
  #   ⇒ 두 출처를 합쳐 같은 어휘로 triage 한다. 상태코드에 'B'(branch) 를 붙여 출처를 남긴다 — porcelain 의 'C'(copied)와 겹치지 않게.
  : > "$TMP/paths.txt"
  awk '{c=$1; $1=""; sub(/^ /,""); print c"\t"$0}' "$TMP/st.txt" >> "$TMP/paths.txt"
  if [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
    git -C "$PROJECT" diff --name-only "${MAIN_REF}...${sb}" 2>/dev/null \
      | awk 'NF{print "B\t"$0}' >> "$TMP/paths.txt"   # MUTATE_ANCHOR_BRANCH_COLLECT
  fi
  # 같은 경로가 양쪽에 있으면 상태를 합친다(예: "M+B")
  awk -F'\t' '{ if(!($2 in s)){s[$2]=$1; o[++n]=$2} else if(index(s[$2],$1)==0) s[$2]=s[$2]"+"$1 }
              END{for(i=1;i<=n;i++) print s[o[i]]"\t"o[i]}' "$TMP/paths.txt" > "$TMP/paths_u.txt"

  # ── 상한 (2026-08-13): 미병합 커밋 편입으로 경로당 git 호출이 늘어 소요가 ~16s → 수 분대가 됐다
  #   (실측: jovial-mcnulty 246파일). 파일 수천 개짜리 브랜치 하나가 무인 런을 몇 시간 붙잡는 것을 막는다.
  #   ★단, 무음 절단 금지 — 잘린 수를 로그와 산출물에 **반드시** 남긴다. 조용히 자르면
  #     "전부 훑었다"로 읽히고, 그게 이 스크립트가 고치려는 실패 형태와 같은 부류다.
  wt_capped=0
  _npaths=$(wc -l < "$TMP/paths_u.txt" | tr -d ' ')
  if [ "${_npaths:-0}" -gt "$MAX_FILES_PER_WT" ] 2>/dev/null; then
    wt_capped=$(( _npaths - MAX_FILES_PER_WT ))
    head -n "$MAX_FILES_PER_WT" "$TMP/paths_u.txt" > "$TMP/paths_cap.txt"
    mv "$TMP/paths_cap.txt" "$TMP/paths_u.txt"
    hb "★상한 적용: $short — 경로 ${_npaths}건 중 ${MAX_FILES_PER_WT}건만 triage · **${wt_capped}건 미검**(STRANDED_MAX_FILES 로 조정)"
  fi

  # ── 파일 단위 triage
  FILES_JSON=""; wt_lost=0; wt_partial=0; wt_legacy_lost=0; wt_legacy_partial=0
  while IFS=$'\t' read -r code path; do
    [ -z "${path:-}" ] && continue
    # theirs = 이 worktree/브랜치가 가진 판본 (방향 판정의 내용 근거로 쓴다)
    THEIRS=""
    if [ -f "$wt/$path" ]; then THEIRS="$wt/$path"
    elif case "$code" in *B*) true ;; *) false ;; esac; then
      if MSYS_NO_PATHCONV=1 git -C "$PROJECT" show "$sb:$path" > "$TMP/theirs_blob" 2>/dev/null; then
        THEIRS="$TMP/theirs_blob"
      fi
    fi
    # 추가 라인 = 미커밋 diff ∪ 미병합 커밋 diff
    : > "$TMP/add_raw"
    case "$code" in
      *M*|*A*|*R*|*U*) git -C "$wt" diff -- "$path" 2>/dev/null \
                         | grep '^+' | grep -v '^+++' | sed 's/^+//' >> "$TMP/add_raw" ;;
    esac
    case "$code" in
      *B*) MSYS_NO_PATHCONV=1 git -C "$PROJECT" diff "${MAIN_REF}...${sb}" -- "$path" 2>/dev/null \
             | grep '^+' | grep -v '^+++' | sed 's/^+//' >> "$TMP/add_raw" ;;
    esac

    case "$code" in
      "??")   # untracked — main 존재/동일 여부로 판정
        if [ ! -e "$PROJECT/$path" ]; then v="lost"; tot=1; miss=1; extra=0
        elif diff -q "$PROJECT/$path" "$wt/$path" >/dev/null 2>&1; then v="merged_upstream"; tot=1; miss=0; extra=0
        elif [ -f "$wt/$path" ]; then
          # ★내용이 다르면 **줄 단위로** 잰다 (2026-08-13). 구판은 1/1 센티넬을 박아
          #   미도달량도 방향 근거도 없이 partial 로 두었고, 그래서 방향 재분류가 mtime 에만
          #   의존할 수밖에 없었다. untracked 는 파일 전체가 곧 '추가 라인'이다.
          read -r tot miss extra <<< "$(triage_added "$wt/$path" "$path" "$wt/$path")"
          v="$(verdict_of "${tot:-0}" "${miss:-0}")"
        else
          # 디렉터리 등 줄로 잴 수 없는 대상 — 센티넬 유지(수동 확인)
          v="partial"; tot=1; miss=1; extra=0
        fi
        ;;
      D|*D*)  v="deletion_only"; tot=0; miss=0; extra=0 ;;
      *)
        read -r tot miss extra <<< "$(triage_added "$TMP/add_raw" "$path" "$THEIRS")"
        # ★커밋된 미병합 신규 파일: 추가 라인이 있는데 main 에 파일 자체가 없다 = 전량 미도달.
        if [ "${tot:-0}" -eq 0 ] && case "$code" in *B*) true ;; *) false ;; esac && [ ! -e "$PROJECT/$path" ]; then
          tot=1; miss=1
        fi
        v="$(verdict_of "${tot:-0}" "${miss:-0}")"
        ;;
    esac
    # ── 재분류: 원장 분기 / 상위판 교체는 '좌초 수리'가 아니다 (2026-08-08)
    if is_ledger "$path"; then
      v="ledger_divergence"
    elif is_scratch "$path"; then
      v="scratch_artifact"
    elif [ "$v" = "lost" ] || [ "$v" = "mostly_lost" ] || [ "$v" = "partial" ]; then
      if [ -e "$PROJECT/$path" ]; then
        _mr="$(main_recency "$path")"
        _wm="$(stat -c %Y "$wt/$path" 2>/dev/null || echo 0)"
        if [ "${_wm:-0}" -eq 0 ]; then   # 커밋-only 경로는 파일이 worktree 에 없을 수 있다
          _wm=$(git -C "$PROJECT" log -1 --format=%ct "$sb" -- "$path" 2>/dev/null || echo 0); _wm="${_wm:-0}"
        fi
        # ★시각 + **내용** 둘 다 요구한다. 시각만 보면 무관한 10줄 커밋이 162줄 수리를 덮는다.
        if [ "${_mr:-0}" -gt 0 ] && [ "${_wm:-0}" -gt 0 ] && [ "${_mr}" -gt "${_wm}" ] \
           && [ "${extra:-0}" -ge "${miss:-0}" ]; then
          v="superseded_upstream"
        fi
      fi
    fi
    if [ "$is_legacy" -eq 1 ]; then
      # (v10) pre-v10 레거시 — 유실/부분은 별도 계수 + verdict 접미(_legacy_pre_v10). 경보·충돌 접점에서 제외.
      case "$v" in
        lost|mostly_lost)    wt_legacy_lost=$((wt_legacy_lost + 1)); N_LEGACY_LOST=$((N_LEGACY_LOST + 1)); v="${v}_legacy_pre_v10" ;;
        partial)             wt_legacy_partial=$((wt_legacy_partial + 1)); N_LEGACY_PARTIAL=$((N_LEGACY_PARTIAL + 1)); v="${v}_legacy_pre_v10" ;;
        ledger_divergence)   N_LEDGER=$((N_LEDGER + 1)) ;;
        superseded_upstream) N_SUPER=$((N_SUPER + 1)) ;;
        scratch_artifact)    N_SCRATCH=$((N_SCRATCH + 1)) ;;
      esac
    else
      case "$v" in
        lost|mostly_lost)    wt_lost=$((wt_lost + 1)); N_LOST=$((N_LOST + 1)) ;;
        partial)             wt_partial=$((wt_partial + 1)); N_PARTIAL=$((N_PARTIAL + 1)) ;;
        ledger_divergence)   N_LEDGER=$((N_LEDGER + 1)) ;;
        superseded_upstream) N_SUPER=$((N_SUPER + 1)) ;;
        scratch_artifact)    N_SCRATCH=$((N_SCRATCH + 1)) ;;
      esac
    fi
    # ★충돌 후보는 **조치 대상 접점만** 센다. 충돌의 의미는 "병합 순서를 정해야 한다"인데,
    #   접점이 전부 원장 분기·상위판 교체·파생 스크래치면 병합할 것이 없어 정할 순서도 없다.
    #   (2026-08-08: 유실 0인데 충돌 8로 경보가 계속 떠서 "유실 0건 감지" 라는 자기모순 문구가 나갔다.
    #    events.jsonl 25 · run_all_hooks.sh 12 등 전부 stale 사본 접점이었다.)
    case "$v" in
      lost|mostly_lost|partial) printf '%s\t%s\n' "$path" "$short" >> "$TMP/touched.txt" ;;
    esac
    [ -n "$FILES_JSON" ] && FILES_JSON="$FILES_JSON,"
    FILES_JSON="$FILES_JSON
        {\"path\":\"$(jesc "$path")\",\"state\":\"$(jesc "$code")\",\"added_lines\":${tot:-0},\"missing_in_main\":${miss:-0},\"main_extra_lines\":${extra:-0},\"verdict\":\"$v\"}"
  done < "$TMP/paths_u.txt"

  N_CAPPED=$((N_CAPPED + ${wt_capped:-0}))
  if [ "$wt_lost" -gt 0 ]; then
    LOST_SUMMARY="${LOST_SUMMARY}${short}(${wt_lost}건·${age}일) "
  fi
  if [ "${wt_legacy_lost:-0}" -gt 0 ] || [ "${wt_legacy_partial:-0}" -gt 0 ]; then
    LEGACY_SUMMARY="${LEGACY_SUMMARY}${short}(유실${wt_legacy_lost}·부분${wt_legacy_partial}) "
  fi

  if [ "${dirty:-0}" -gt 0 ] 2>/dev/null || [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
    [ -n "$WT_JSON" ] && WT_JSON="$WT_JSON,"
    WT_JSON="$WT_JSON
    {
      \"worktree\":\"$(jesc "$short")\",
      \"branch\":\"$(jesc "$sb")\",
      \"path\":\"$(jesc "$wt")\",
      \"ahead_of_main\":${ahead:-0},
      \"dirty_files\":${dirty:-0},
      \"last_commit_age_days\":$age,
      \"stale\":$([ "$is_stale" -eq 1 ] && echo true || echo false),
      \"lost\":$wt_lost,
      \"partial\":$wt_partial,
      \"legacy_pre_v10\":$([ "$is_legacy" -eq 1 ] && echo true || echo false),
      \"lost_legacy\":${wt_legacy_lost:-0},
      \"partial_legacy\":${wt_legacy_partial:-0},
      \"uninspected_over_cap\":${wt_capped:-0},
      \"files\":[${FILES_JSON}
      ]
    }"
    say "  $([ "$is_stale" -eq 1 ] && echo '[방치' || echo '[활동') ${age}d] $short — 미커밋 ${dirty} / 미병합 ${ahead} / 유실 ${wt_lost} / 부분 ${wt_partial}"
  fi
done < <(git -C "$PROJECT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{w=$2} /^branch /{print w"|"$2}')

# ── 동시 수정 충돌 탐지: 2개 이상 worktree가 같은 파일을 main 밖에서 건드리는 중
#    병합 순서를 정하지 않으면 뒤에 병합되는 쪽이 앞을 덮거나 충돌한다.
COLL_JSON=""; N_COLL=0; COLL_SUMMARY=""
if [ -s "$TMP/touched.txt" ]; then
  sort -u "$TMP/touched.txt" | awk -F'\t' '{a[$1]=a[$1]" "$2; n[$1]++} END{for(p in n) if(n[p]>1) print p"\t"n[p]"\t"a[p]}' \
    | sort > "$TMP/coll.txt"
  while IFS=$'\t' read -r cpath cnt brs; do
    [ -z "${cpath:-}" ] && continue
    N_COLL=$((N_COLL + 1))
    BR_JSON=""
    for b in $brs; do
      [ -n "$BR_JSON" ] && BR_JSON="$BR_JSON,"
      BR_JSON="$BR_JSON\"$(jesc "$b")\""
    done
    [ -n "$COLL_JSON" ] && COLL_JSON="$COLL_JSON,"
    COLL_JSON="$COLL_JSON
      {\"path\":\"$(jesc "$cpath")\",\"worktree_count\":$cnt,\"branches\":[$BR_JSON]}"
    COLL_SUMMARY="${COLL_SUMMARY}$(basename "$cpath")(${cnt}) "
  done < "$TMP/coll.txt"
fi
[ "$N_COLL" -gt 0 ] && say "  ★ 동시 수정 충돌 후보 ${N_COLL}건: ${COLL_SUMMARY}"

# ── 레지스트리 기록
mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<JSON
{
  "_doc": "좌초 수리 감사 — worktree에 갇혀 main에 도달하지 못한 수리 탐지. 생성기 02_Infrastructure/ops/stranded_repairs_audit.sh. verdict: merged_upstream=worktree가 stale 사본(정리 가능) / lost=main에 전무(조치 필요) / mostly_lost=80%+ 미존재(사실상 유실) / partial=일부만 반영(수동 확인) / deletion_only=삭제만 / ledger_divergence=append-only 원장의 세션별 분기(수리 아님·경보 제외) / superseded_upstream=main이 그 경로에서 더 앞서 나감(구판 교체·조치 불요·경보 제외) / *_legacy_pre_v10=(v10 2026-09-02) 브랜치 tip 이 v10 경계(legacy_ref) 이전에 멎은 worktree 의 유실/부분 — 폐기된 판의 잔재라 경보·충돌 계수에서 제외, 처분은 도훈 결정. ★lost/partial만 조치 대상이다 — 2026-08-08 이전 판은 뒤 2종을 유실로 계상해 경보의 80%가 허위였다(36건 중 진짜 7건). collisions=2개 이상 worktree가 같은 파일을 main 밖에서 수정 중(병합 순서 결정 필요).",
  "generated_at": "$(date '+%Y-%m-%d %H:%M:%S')",
  "main_ref": "$(jesc "$MAIN_REF")",
  "stale_threshold_days": $STALE_DAYS,
  "summary": {
    "worktrees_total": $N_WT,
    "with_uncommitted": $N_DIRTY,
    "with_unmerged": $N_AHEAD,
    "stale_over_threshold": $N_STALE,
    "files_lost": $N_LOST,
    "files_partial": $N_PARTIAL,
    "files_ledger_divergence": $N_LEDGER,
    "files_superseded_upstream": $N_SUPER,
    "files_scratch_artifact": $N_SCRATCH,
    "worktrees_legacy_pre_v10": $N_LEGACY_WT,
    "files_lost_legacy_pre_v10": $N_LEGACY_LOST,
    "files_partial_legacy_pre_v10": $N_LEGACY_PARTIAL,
    "legacy_ref": "$(jesc "$LEGACY_REF")",
    "legacy_epoch": ${LEGACY_EPOCH:-0},
    "collisions": $N_COLL,
    "prune_candidates": $N_PRUNE,
    "uninspected_over_cap": $N_CAPPED
  },
  "worktrees": [${WT_JSON}
  ],
  "collisions": [${COLL_JSON}
  ],
  "prune_candidates": [${PRUNE_JSON}
  ]
}
JSON

say ""
hb "worktree ${N_WT} · 미커밋 ${N_DIRTY} · 미병합 ${N_AHEAD} · ${STALE_DAYS}일+ 방치 ${N_STALE} | 유실 ${N_LOST} · 부분 ${N_PARTIAL} · 충돌 ${N_COLL} · prune후보 ${N_PRUNE}"
# 접힌 2종도 수를 남긴다 — 경보에서 뺐다고 기록에서 지우면 '조용해진 것'과 '고쳐진 것'이 구분 안 된다
hb "  (경보 제외) 원장 분기 ${N_LEDGER} · 상위판 교체 ${N_SUPER} · 파생 스크래치 ${N_SCRATCH}"
[ "${N_LEGACY_WT:-0}" -gt 0 ] && hb "  (경보 제외) pre-v10 레거시 worktree ${N_LEGACY_WT} · 레거시 유실 ${N_LEGACY_LOST} · 레거시 부분 ${N_LEGACY_PARTIAL} — ${LEGACY_SUMMARY}(처분 = 도훈 결정)"
[ "$N_LOST" -gt 0 ] && hb "★ 유실 대상: ${LOST_SUMMARY}"
[ "$N_COLL" -gt 0 ] && hb "★ 동시수정 충돌: ${COLL_SUMMARY}"
say "[stranded] → $OUT"

# ── ③ worktree 생명주기: prune 후보 정리 (--prune 명시 시에만 실제 제거)
#    조건: 미커밋 0 ∧ 미병합 0 (= 작업이 전부 main에 있음). git worktree remove 는 dirty면 자체 거부 = 2중 안전.
#    자동 실행 금지 — 활동 중 세션의 worktree를 지우면 그 세션이 깨진다. 반드시 수동 판단.
if [ "$DO_PRUNE" -eq 1 ]; then
  if [ ! -s "$TMP/prune.txt" ]; then
    say "[stranded] prune: 후보 없음"
  else
    say ""
    say "[stranded] prune 실행 — 후보 ${N_PRUNE}건 (미커밋 0 ∧ 미병합 0)"
    PRUNED=0; PFAIL=0
    while IFS=$'\t' read -r pwt pbr; do
      [ -z "${pwt:-}" ] && continue
      if git -C "$PROJECT" worktree remove "$pwt" 2>"$TMP/prune_err.txt"; then
        PRUNED=$((PRUNED + 1)); say "    제거: $(basename "$pbr")"
      else
        PFAIL=$((PFAIL + 1)); say "    실패: $(basename "$pbr") — $(head -1 "$TMP/prune_err.txt" 2>/dev/null)"
      fi
    done < "$TMP/prune.txt"
    git -C "$PROJECT" worktree prune 2>/dev/null || true
    say "[stranded] prune 완료 — 제거 ${PRUNED} / 실패 ${PFAIL}"
  fi
else
  [ "$N_PRUNE" -gt 0 ] && say "[stranded] prune 후보 ${N_PRUNE}건 — 제거하려면 --prune (자동 실행 안 함)"
fi

# ── 텔레그램 경보: 유실 또는 충돌 후보가 있을 때. 같은 날 1회 스로틀.
if [ "$DO_TG" -eq 1 ] && { [ "$N_LOST" -gt 0 ] || [ "$N_PARTIAL" -gt 0 ] || [ "$N_COLL" -gt 0 ]; }; then
  TODAY=$(date +%Y%m%d)
  MARK="$PROJECT/.cache/stranded_alert_${TODAY}.marker"
  # (v10 2026-09-02) 변화 게이트 — 대상 worktree·건수·충돌 파일이 직전 발송과 같으면 재발송하지 않는다.
  #   구판 스로틀은 '같은 날 1회' 만이라 08-29~09-02 동일 수치(127/19/1)를 7회 재발송했다. 서명에서 경과 일수(·N일)는
  #   빼야 한다 — 그대로 넣으면 매일 달라져 게이트가 한 번도 억제하지 못한다(수리가 '작동 중' 으로 보이며 소음은 그대로).
  SIG="lost=${N_LOST}|partial=${N_PARTIAL}|coll=${N_COLL}|$(printf '%s' "$LOST_SUMMARY" | sed -E 's/·[0-9-]+일//g')|${COLL_SUMMARY}"
  SIGF="$PROJECT/.cache/stranded_alert_last.sig"
  if [ -f "$MARK" ]; then
    say "[stranded] 텔레그램 skip — 오늘 이미 발송 (스로틀)"
  elif [ -f "$SIGF" ] && [ "$(cat "$SIGF" 2>/dev/null)" = "$SIG" ]; then
    hb "텔레그램 skip — 직전 발송과 동일 서명(변화 없음): $SIG"
  else
    RS_BIN="$(command -v Rscript || true)"
    if [ -z "$RS_BIN" ]; then
      say "[stranded] 텔레그램 skip — Rscript 없음 (레지스트리는 기록됨)"
    else
      mkdir -p "$PROJECT/.cache"
      printf 'generated=%s\nlost=%s\nstale=%s\n' "$(date '+%F %T')" "$N_LOST" "$N_STALE" > "$MARK"
      RFILE="$TMP/_tg_stranded.R"
      cat > "$RFILE" <<RS
suppressWarnings(suppressMessages({
  root <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
  source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R"))
}))
invisible(tryCatch(tg_agent_brief(
  agent = "Q-Lead",
  title = "[무인] 좌초 수리 경보 — worktree 미반영 감지",
  relaxed = TRUE, force = TRUE,
  lock_scope = "stranded_repairs_${TODAY}",
  sections = list(
    list(type = "summary", emoji = "\U0001F6A8",
         body = "병렬 세션 worktree에 갇혀 main에 도달하지 못한 수리가 ${N_LOST}건 감지됐습니다. 세션이 끝나면 유실됩니다."),
    list(type = "bullet", emoji = "\U0001F4A1", heading = "쉬운 설명",
         items = c("다른 작업 공간에서 고친 코드가 본진에 합쳐지지 않은 상태입니다",
                   "같은 사고가 과거 2번 있었고 둘 다 일주일 가까이 방치됐습니다",
                   "판정이 유실이면 본진에 그 내용이 아예 없다는 뜻입니다")),
    list(type = "kv", emoji = "\U0001F4CB", heading = "상세",
         kv = list("유실 파일" = "${N_LOST}",
                   "부분 반영" = "${N_PARTIAL}",
                   "방치 worktree" = "${N_STALE}",
                   "대상" = "${LOST_SUMMARY}",
                   "레지스트리" = "06_Registry/stranded_repairs.json"))
  )
), error = function(e) cat("tg fail:", conditionMessage(e), "\n")))
RS
      if "$RS_BIN" "$RFILE" >/dev/null 2>&1; then
        printf '%s' "$SIG" > "$SIGF" 2>/dev/null || true   # 발송 성공 시에만 서명 기록 — 실패면 다음 실행이 재시도
        say "[stranded] 텔레그램 발송 시도 완료"
      else
        say "[stranded] 텔레그램 실패 (마커·레지스트리는 보존)"
      fi
    fi
  fi
fi

exit 0
