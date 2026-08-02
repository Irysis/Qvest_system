#!/usr/bin/env bash
#==============================================================================
# test_worktree_stranded_axis.sh — worktree 좌초 판정축 위반 주입
#------------------------------------------------------------------------------
# 신설 2026-08-02. 대상 = bootstrap.sh §4h worktree 가시성 판정.
#
# ★왜: 이 판정축이 **하루에 세 번 뒤집혔다**. 검사 없이 두면 또 뒤집힌다.
#   (1) 원판 = 방치 연차(브랜치 마지막 커밋 age >= 3d).
#       → 실측 반증: 강조된 3건이 전부 main 반영 완료(무해)였고, 정작 이틀간 main 에
#         없던 진짜 좌초(serene-liskov: resolve_project marker 6파일)는 **age 0d 라 미검출**.
#         기전 = age 가 *브랜치 커밋* 시각이라, 커밋 없이 미커밋만 쌓이는 형태(=가장 위험)가
#         항상 '활동 중'으로 보인다.
#   (2) 1차 수리 = main부재 파일 수 단독.
#       → 실측 반증: 그날 아침 시작한 background task 2건(신규 테스트 파일)까지 ★좌초로 오인.
#         main부재는 '좌초'와 '진행 중'을 구분하지 못한다.
#   (3) 정본 = **main부재 > 0  AND  변경파일 mtime 무활동 >= WT_IDLE_HOURS**.
#         serene-liskov(부재 O, 이틀 방치) = 좌초 / 진행 중 task(부재 O, 0h) = 작업중.
#
#   부수 수리: 표시명을 브랜치명 → **디렉토리명**(종전엔 안내가 `git -C <worktree경로>` 인데
#   브랜치명을 보여줘 경로를 찾을 수 없었다. 실측: 디렉토리 compassionate-cerf-363c47
#   ↔ 브랜치 claude/amazing-booth-ea1592 로 서로 다르다).
#   성능: 전트리 find 는 5분 초과 → 변경파일 목록 mtime 만 보게 축소(실측 9초).
#
# 실행: bash 08_Tests/ops/test_worktree_stranded_axis.sh
#==============================================================================
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)}}"
ROOT="${ROOT//\\//}"
BOOT="$ROOT/02_Infrastructure/ops/bootstrap.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s — %s\n' "$1" "${2:-}"; }

# 판정 로직 격리 재현 (bootstrap §4h 와 동일 규칙)
decide() {  # $1=main부재수  $2=idle시간  $3=dirty  [$4=IDLE문턱]
  local miss="$1" idle="$2" dirty="$3" thr="${4:-12}"
  if [ "$miss" -gt 0 ] && [ "$idle" -ge "$thr" ]; then echo "stranded"
  elif [ "$miss" -gt 0 ]; then echo "working"
  elif [ "$dirty" -gt 0 ]; then echo "merged"
  else echo "clean"; fi
}

echo "=== test_worktree_stranded_axis (판정축 위반 주입) ==="

echo "--- A. 실사고 재현: 세 번 뒤집힌 케이스가 각각 옳게 나오나 ---"
r=$(decide 6 48 6)
[ "$r" = "stranded" ] && ok "A1 ★serene-liskov 형(부재 6 · 48h 방치) → stranded" \
  || bad "A1 진짜 좌초 검출" "got $r — 원판이 놓쳤던 케이스"
r=$(decide 1 0 9)
[ "$r" = "working" ] && ok "A2 ★진행중 task 형(부재 1 · 0h) → working (좌초 아님)" \
  || bad "A2 진행중 오인 방지" "got $r — 1차 수리가 오인했던 케이스"
r=$(decide 0 189 20)
[ "$r" = "merged" ] && ok "A3 ★frosty-torvalds 형(부재 0 · 189h) → merged (무해)" \
  || bad "A3 무해분 오강조 방지" "got $r — 원판이 ★로 강조했던 케이스"

echo "--- B. 축 분리: 한 축만으로는 판별 불가함을 실증 ---"
s1=$(decide 0 999 5); s2=$(decide 5 0 5)
[ "$s1" != "stranded" ] && [ "$s2" != "stranded" ] \
  && ok "B1 ★연차만·부재만 각각 단독으로는 stranded 아님 (AND 결합 실증)" \
  || bad "B1 AND 결합" "연차단독=$s1 부재단독=$s2"
r=$(decide 5 999 5)
[ "$r" = "stranded" ] && ok "B2 두 조건 동시 충족 시에만 stranded" || bad "B2" "got $r"

echo "--- C. 문턱 경계 ---"
r=$(decide 1 11 1); [ "$r" = "working" ] && ok "C1 idle 11h(<12) → working" || bad "C1" "got $r"
r=$(decide 1 12 1); [ "$r" = "stranded" ] && ok "C2 idle 12h(=문턱) → stranded" || bad "C2" "got $r"
r=$(decide 1 20 1 24); [ "$r" = "working" ] && ok "C3 문턱 24h 로 올리면 20h 는 working (문턱 파라미터 유효)" || bad "C3" "got $r"

echo "--- D. 음성 통제: 무조건 stranded 를 뱉는 게 아님 ---"
r=$(decide 0 0 0); [ "$r" = "clean" ] && ok "D1 변경 없음 → clean" || bad "D1" "got $r"
r=$(decide 0 5 3); [ "$r" = "merged" ] && ok "D2 부재 0 · 활동중 → merged" || bad "D2" "got $r"

echo "--- E. 구현 동기: bootstrap 이 실제로 이 축을 갖고 있나 ---"
grep -q 'wt_missing' "$BOOT" && ok "E1 main부재 축(wt_missing) 존재" || bad "E1 부재 축" "수리 되돌려짐"
grep -q 'wt_idle_h' "$BOOT" && ok "E2 무활동 축(wt_idle_h) 존재" || bad "E2 활동 축" "수리 되돌려짐"
grep -q 'WT_IDLE_HOURS' "$BOOT" && ok "E3 문턱 파라미터화" || bad "E3 문턱" ""
grep -q 'basename "\$wt"' "$BOOT" && ok "E4 ★표시명 = 디렉토리명(브랜치명 아님 — git -C 조회 가능)" \
  || bad "E4 표시명" "브랜치명을 보여주면 안내한 경로로 조회 불가"
grep -q 'find "\$wt" -type f' "$BOOT" && bad "E5 전트리 find 잔존" "부팅 5분+ 지연 — 변경파일 mtime 만 봐야 함" \
  || ok "E5 전트리 find 없음 (부팅 지연 회피)"

echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
printf '{"test":"worktree_stranded_axis","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
