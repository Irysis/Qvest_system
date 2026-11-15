#!/usr/bin/env bash
#==============================================================================
# test_qw_autologin_preflight.sh — QW 자동로그인 사전 점검의 양방향 검증
#
# 배경 (2026-08-29 실사고): qw_refresh.ps1 의 Ensure-Login 은 **LOGIN 버튼 클릭만** 한다
#   (ID/PW 는 앱이 기억한다는 전제 — 도훈이 만든 자동 로그인 = maincfg.ini [LOGIN]
#   SAVEUSERPW=1 + USERPW 저장). 그 플래그가 0 으로 풀리자 PW 칸이 매번 빈 채로 떴고,
#   구판은 그 조건을 못 읽어 **40라운드를 빈 비밀번호로 클릭**했다. 헛수고이자
#   **계정 잠금 위험**이며, 로그는 "login failed, retry"만 40줄이라 원인이 안 보였다.
#   ⇒ 라운드 전에 플래그를 읽고 즉시 중단(exit 3) + 사람이 할 일을 출력한다.
#
# 계약 (분기가 실제로 갈리는가 — 한쪽만 재면 검사 사망과 정상이 겉보기 같다):
#   ① SAVEUSERPW=0 · 세션 없음   → exit 3 + 'ABORT [autologin]' (라운드 진입 금지)
#   ①b SAVEUSERPW=0 · 세션 살아 있음 → 'WARN [autologin]' + 로그인만 끄고 라운드 진입(no_saved_pw — 2026-11-14 f89084e5e 계약:
#        살아 있는 세션은 쓰고, 빈 비밀번호로는 누르지 않는다 · 11-14 밤 수급 0 사고)
#   ② SAVEUSERPW=1        → 통과 (사전 점검이 정상 실행을 막지 않는다 — 음성 대조)
#   ③ -SkipLogin          → 점검 생략 (이미 로그인된 세션 전제)
#   ④ 한글 메시지 깨짐 없음 (BOM — PowerShell 5.1 은 BOM 없는 .ps1 을 ANSI 로 읽는다)
# ★2026-11-15 수리(refresh-root-fix): 11-14 판은 점검을 도우미 함수(Read-SavePw · Resolve-SavedPwMode · Enter-NoSavedPw)로 옮겼는데 이 시험은
#   블록만 떼어 돌려 '함수 없음'으로 ①이 깨졌고, ②는 아무 판정도 못 한 채 우연히 통과했다. 11-13 판(e7d2fcf40)은 루프 줄을 '$spent' 로 바꿔
#   순서 검사가 루프를 못 찾았다. → 도우미 함수를 원문에서 함께 꺼내고(QW-Alive 는 가짜) · 루프 줄은 변수 이름에 묶지 않는다.
#==============================================================================
set -uo pipefail
QM="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$QM" || exit 9
SRC="02_Infrastructure/ops/qw_refresh.ps1"
[ -f "$SRC" ] || { echo "XX 스크립트 부재"; exit 9; }

PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

# ④ BOM — 없으면 한글 출력이 로그에서 깨진다(진단 메시지가 진단을 못 한다)
if [ "$(head -c 3 "$SRC" | xxd -p)" = "efbbbf" ]; then
  ok "④ UTF-8 BOM 존재 — PowerShell 5.1 이 한글을 정상 판독"
else
  ng "④ BOM 부재 — 진단 메시지가 ANSI 오독으로 깨진다"
fi

# ① 사전 점검 로직이 소스에 실재하는가 (부활 방지 — 텍스트 재도출)
for tok in "SAVEUSERPW" "ABORT \[autologin\]" "exit 3"; do
  if grep -qE "$tok" "$SRC"; then ok "① 소스에 '$tok' 실재"; else ng "① 소스에 '$tok' 부재 — 사전 점검 소실"; fi
done

# ① 점검이 **라운드 루프보다 먼저** 오는가 (뒤에 있으면 이미 40회 클릭한 뒤다)
p_chk=$(grep -n "ABORT \[autologin\]" "$SRC" | head -1 | cut -d: -f1)
p_loop=$(grep -nE '^while \(\$[A-Za-z]+ -lt \$MaxRounds\)' "$SRC" | head -1 | cut -d: -f1)   # 루프 변수 이름에 묶지 않는다($round → $spent · 11-13)
if [ -n "$p_chk" ] && [ -n "$p_loop" ] && [ "$p_chk" -lt "$p_loop" ]; then
  ok "① 순서 = 사전 점검 → 라운드 루프 (헛클릭 0회)"
else
  ng "① 점검이 루프 뒤/부재 (chk=$p_chk loop=$p_loop)"
fi

# ③ -SkipLogin 이면 점검을 건너뛰는가 (이미 로그인된 세션을 막으면 안 된다)
if grep -q 'if (-not \$SkipLogin) {' "$SRC"; then
  ok "③ -SkipLogin 시 점검 생략 배선"
else
  ng "③ SkipLogin 분기 부재 — 로그인된 세션도 차단될 수 있다"
fi

# ②① 실동작 3분기 — 임시 maincfg 로 플래그를 갈아 끼워 판정이 갈리는지 본다
PS="$(command -v powershell.exe || echo powershell)"
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
fn_src() { awk -v n="$1" '$0 ~ "^function "n"[ (]" {f=1} f{print} f&&/^\}$/{exit}' "$QM/$SRC"; }
probe() {  # $1 = SAVEUSERPW 값 · $2 = 세션(1 살아 있음 / 0 없음) → 사전 점검 블록 + 그 도우미 함수만 격리 실행(QW-Alive 는 가짜 · 단말 무접촉)
  local v="$1" alive="$2"
  local cfg; cfg="$TMPD/maincfg_$v.ini"
  printf '[LOGIN]\r\nSAVEID = 1\r\nSAVEUSERPW = %s\r\nID = testid\r\n' "$v" > "$cfg"
  local script; script="$TMPD/probe_${v}_$alive.ps1"
  printf '\xef\xbb\xbf' > "$script"
  {
    echo '$SkipLogin = $false; $script:NO_SAVED_PW = $false'
    echo "\$MAINCFG = '$(cygpath -m "$cfg" 2>/dev/null || echo "$cfg")'"
    echo "function QW-Alive { return \$$( [ "$alive" = 1 ] && echo true || echo false ) }"
    for f in Read-SavePw Resolve-SavedPwMode Enter-NoSavedPw; do fn_src "$f"; done
    sed -n '/^if (-not \$SkipLogin) {$/,/^}$/p' "$QM/$SRC" | head -60
    echo 'Write-Host "NOPW=$($script:NO_SAVED_PW) SKIP=$SkipLogin"'
    echo 'Write-Host "REACHED_LOOP"'
  } >> "$script"
  "$PS" -ExecutionPolicy Bypass -File "$script" 2>&1 | tr -d '\r'
}
for f in Read-SavePw Resolve-SavedPwMode Enter-NoSavedPw; do [ -n "$(fn_src "$f")" ] || ng "도우미 함수 $f 추출 실패(원문에서 이름이 바뀌었나)"; done

OUT="$(probe 0 0)"
if echo "$OUT" | grep -q "ABORT \[autologin\]" && ! echo "$OUT" | grep -q "REACHED_LOOP" && ! echo "$OUT" | grep -q 'CommandNotFoundException'; then
  ok "① SAVEUSERPW=0 · 세션 없음 → 중단 (루프 미진입)"
else
  ng "① SAVEUSERPW=0 · 세션 없음인데 통과했다: $(echo "$OUT" | head -2 | tr '\n' ' ')"
fi

OUT="$(probe 0 1)"
if echo "$OUT" | grep -q "WARN \[autologin\] SAVEUSERPW=0" && echo "$OUT" | grep -q "NOPW=True SKIP=True" && echo "$OUT" | grep -q "REACHED_LOOP" && ! echo "$OUT" | grep -q "ABORT"; then
  ok "①b SAVEUSERPW=0 · 세션 살아 있음 → 경고 + 로그인만 끄고 진입(no_saved_pw · SkipLogin)"
else
  ng "①b SAVEUSERPW=0 · 세션 살아 있음 분기: $(echo "$OUT" | head -3 | tr '\n' ' ')"
fi

OUT="$(probe 1 1)"
if echo "$OUT" | grep -q "REACHED_LOOP" && echo "$OUT" | grep -q "NOPW=False" && ! echo "$OUT" | grep -q "ABORT" && ! echo "$OUT" | grep -q 'CommandNotFoundException'; then
  ok "② SAVEUSERPW=1 → 통과 (음성 대조 — 정상 실행을 막지 않는다 · 로그인 켜짐 그대로)"
else
  ng "② SAVEUSERPW=1 인데 막혔거나 판정 못 함: $(echo "$OUT" | head -2 | tr '\n' ' ')"
fi

echo "결과: PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"qw_autologin_preflight\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
