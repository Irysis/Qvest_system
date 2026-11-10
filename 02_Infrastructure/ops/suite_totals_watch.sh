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
# --- 러너 FINAL 총계 추출 (2026-08-20 분리) ---------------------------------
#   테스트가 **실제 코드**를 태울 수 있도록 함수로 뺀다(파싱 로직을 검사 쪽에 복제하면
#   정본과 갈린다 - 이 저장소의 반복 실패 계통). 검사: 08_Tests/ops/test_suite_totals_anchor.sh
st_pick_hooks_final() {
  local raw="${1:-}" out
  # ★3단 앵커 (v10 2026-09-03 수리). 러너가 2026-08-24 에 unmeasured 구간을 추가해
  #   `FINAL: N pass / N fail / N skipped / N unmeasured / N total` 5-part 가 됐는데 구판 1차 패턴은
  #   4-part 를 **정확히** 요구해 매치 0 → 3-part 폴백이 **개별 테스트의 마지막 줄**을 집었다.
  #   실측 결과 hooks=12(실제 총계 3308) · hooks_fail=0(실제 6) — 총계·fail 축이 함께 죽어 있었다.
  #   같은 기전이 2026-08-20(1563→7)에 이미 한 번 났다. 순서: 5-part → 4-part → 3-part, 전부 tail -1.
  out=$(printf '%s' "$raw" | grep -oE 'FINAL: [0-9]+ pass / [0-9]+ fail / [0-9]+ skipped / [0-9]+ unmeasured / [0-9]+ total' | tail -1)
  [ -z "$out" ] && out=$(printf '%s' "$raw" | grep -oE 'FINAL: [0-9]+ pass / [0-9]+ fail / [0-9]+ skipped / [0-9]+ total' | tail -1)
  [ -z "$out" ] && out=$(printf '%s' "$raw" | grep -oE 'FINAL: [0-9]+ pass / [0-9]+ fail / [0-9]+ total' | tail -1)
  printf '%s' "$out"
}


#─────────────────────────────────────────────────────────────────────────
# --- 같은 날 재수집 건너뛰기 (2026-11-10 전수점검) ---------------------------
#   아침 체인(ensure_data_current → daily_refresh)이 자료가 낡았다고 리프레시를 다시 돌리면 후처리 끝의 이 수집(배터리 약 130분)도
#   다시 돈다 — 11-10 아침 브리핑이 그 끝까지 기다렸다. 수집은 하루 한 번이면 된다: 최근 수집이 오늘 날짜이고 값이 온전하면 건너뛴다.
#   강제 = QVEST_ST_FORCE=1 또는 `--collect --force`. 검사: 08_Tests/ops/test_suite_totals_anchor.sh
st_collected_today() {   # <latest.json> [오늘 YYYY-MM-DD] → 0 = 오늘 온전히 수집됨(hooks 수치 있음)
  local f="${1:-}" today="${2:-$(date +%Y-%m-%d)}" d
  [ -f "$f" ] || return 1
  d=$(grep -oE '"collected_at": *"[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  [ -n "$d" ] && [ "$d" = "$today" ] || return 1
  grep -qE '"hooks": *[0-9]+' "$f"          # 수집 실패(null)로 끝난 날은 다시 수집한다
}

# --- 폴더별 합계를 러너 결과에서 읽는다 (2026-11-10) -------------------------
#   종전엔 regime 합계를 얻으려고 08_Tests/regime/run_all.R 을 한 번 더 돌렸다. 그 러너는 sys.source 한 시험의 quit() 에서 죽어
#   09-12 부터 regime = null 이었고(기준선 승격 불가), 같은 시험 25개는 배터리 목록에도 전부 있어 이중 실행이었다.
#   러너가 결과 파일에 남기는 "timings"(경로 · pass · fail)에서 그 폴더 몫만 더한다. 출력 = "<total> <fail>" (없으면 빈 줄).
st_folder_totals() {     # <hook_dryrun_results.json> <폴더 접두 예: 08_Tests/regime/>
  [ -x "$PY" ] && [ -f "${1:-}" ] || return 0
  "$PY" - "$1" "${2:-}" <<'PYEOF' 2>/dev/null
import io, json, sys
try:
    d = json.load(io.open(sys.argv[1], encoding="utf-8"))
    rows = [t for t in (d.get("timings") or []) if str(t.get("suite", "")).startswith(sys.argv[2])]
    if rows and all(isinstance(t.get("pass"), int) and isinstance(t.get("fail"), int) for t in rows):
        print(sum(t["pass"] + t["fail"] for t in rows), sum(t["fail"] for t in rows))
except Exception:
    pass
PYEOF
}

# --- 단계(tier) — 밤 = nightly · 주 1회 = full (2026-11-10 전수점검) -----------
#   배터리 전체는 130분이고 매일 밤 리프레시 끝에서 돌았다. 대상이 전부 퇴역한 스위트까지 매일 돌 이유가 없다.
#   설정 = 08_Tests/hooks/profiles/tiers.json(full_weekday — ISO 요일 1~7) · 밤에 빼는 목록 = profiles/nightly.exclude(한 줄 한 경로 · # 주석).
#   설정을 못 읽으면 full(아무것도 빼지 않는다 — 조용히 줄이지 않는다). 강제 = QVEST_SUITES_TIER=full|nightly.
st_pick_tier() {         # <tiers.json> [오늘 ISO 요일] → full | nightly
  local f="${1:-}" dow="${2:-$(date +%u)}" fw
  [ -f "$f" ] || { printf 'full'; return 0; }
  fw=$(grep -oE '"full_weekday"[[:space:]]*:[[:space:]]*[1-7]' "$f" | grep -oE '[1-7]$' | head -1)
  [ -n "$fw" ] || { printf 'full'; return 0; }
  if [ "$dow" = "$fw" ]; then printf 'full'; else printf 'nightly'; fi
}
st_profile_regex() {     # <프로필 파일> → 러너의 QVEST_SUITES_EXCLUDE 에 넣을 정규식(경로를 | 로 이음 · 점은 이스케이프)
  [ -s "${1:-}" ] || return 0
  grep -v '^[[:space:]]*#' "$1" | tr -d '\r' | grep -v '^[[:space:]]*$' | sed 's/[[:space:]]*$//; s/\./\\./g' | paste -sd'|' -
}

collect() {
  mkdir -p "$DIR/.cache"
  local hooks regime contract continuity
  local hooks_out regime_out cont_out hooks_fail regime_fail continuity_fail hooks_unmeasured
  if [ "${QVEST_ST_FORCE:-0}" != "1" ] && [ "${1:-}" != "--force" ] && st_collected_today "$LATEST"; then
    echo "[suite-totals] 오늘 이미 수집됨($(grep -oE '"collected_at": *"[^"]+"' "$LATEST" | head -1)) — 재수집 건너뜀(강제 = QVEST_ST_FORCE=1)"
    return 0
  fi

  # (2026-07-26 probe① 도훈 승인) fail 축 동시 수집 — 구판은 total만 봐서
  # total=pass+fail 구조상 FAIL이 나도 총계 불변 = 회귀가 감시를 그냥 통과했다.
  # (2026-08-03) skipped 필드 선택 허용. 러너가 제3상태(skipped)를 도입하며 FINAL 줄이
  #   `FINAL: N pass / N fail / N skipped / N total` 로 바뀌었는데 이 패턴은 구 형식만
  #   매치해 **hooks=null** 이 됐다(실측 08-03 09:43 스냅샷). 러너 쪽 계약 변경이
  #   하류 파서를 조용히 깨뜨린 자리 — 다만 이 도구의 "수치 없음은 정상이 아니다" 가드가
  #   null 을 경보로 올려 침묵하지는 않았다. 양쪽 형식을 모두 받는다.
  # (2026-08-20) ★위 08-03 수리가 오늘의 버그를 만들었다 — skipped 를 선택적으로 만들어
  #   양쪽 형식을 받게 하자, **개별 테스트가 찍는 같은 모양의 줄**까지 매치되기 시작했다.
  #   러너 총계(run_all_hooks.sh:1148)는 항상 skipped 구간을 포함하고 항상 **맨 끝**에 나오는데,
  #   구판은 head -1 로 **먼저 나온 아무 테스트의 총계**를 집었다.
  #   실측 2026-08-20: 매치 3줄이 전부 개별 테스트(4891행 "FINAL: 7 pass / 0 fail / 7 total",
  #   4933행 29, 4981행 12) — head -1 이 7 을 집어 hooks=7 로 기록됐다(직전 정상값 1563).
  #   fail 0 이라 초록으로 보였다 = 계측 사망이 '실패'가 아니라 '총계 감소'로 오는 그 자리.
  #   2단 앵커: (1) 러너 현행 계약(skipped 포함)을 **정확히** 요구하고 tail -1
  #             (2) 없으면 구 형식 폴백, 역시 tail -1 (첫 줄이 아니라 마지막 줄)
  #   ★head -1 로 되돌리지 말 것. 검사: 08_Tests/ops/test_suite_totals_anchor.sh
  # (2026-11-10) 러너 출력을 버리지 않는다 — 종전엔 표준출력을 변수로만 받고 표준오류는 /dev/null 로 보내, 실패한 단언의 내용이
  #   어디에도 남지 않았다(총계 fail=107 만 보이고 무엇이 왜 실패했는지는 다시 돌려야 알 수 있었다). 마지막 1회분을 남긴다.
  mkdir -p "$DIR/.cache/test_results"
  # (2026-11-10 H1) 층 = QVEST_BATTERY_TIER(일일 체인이 넘김 · fast | nightly | weekly | full) → 없으면 tiers.json 요일 규칙
  #   (full_weekday = weekly · 그 밖 = nightly). 러너에는 같은 변수로 넘기고, 밤 층이면 nightly.exclude 예외도 함께 뺀다.
  #   구 변수 QVEST_SUITES_TIER(full | nightly)는 BATTERY_TIER 가 없을 때만 읽는다(full → weekly).
  local tier excl="${QVEST_SUITES_EXCLUDE:-}"
  tier="${QVEST_BATTERY_TIER:-}"
  if [ -z "$tier" ]; then
    tier="${QVEST_SUITES_TIER:-$(st_pick_tier "$DIR/08_Tests/hooks/profiles/tiers.json")}"
    [ "$tier" = "full" ] && tier="weekly"
  fi
  if [ "$tier" = "nightly" ] && [ -z "$excl" ]; then excl="$(st_profile_regex "$DIR/08_Tests/hooks/profiles/nightly.exclude")"; fi
  local _res="$DIR/.cache/test_results/hook_dryrun_results.json" _st0 _rm
  _st0=$(date +%s)
  _hooks_raw=$(cd "$DIR" && CLAUDE_PROJECT_DIR="$DIR" QVEST_BATTERY_TIER="$tier" QVEST_SUITES_EXCLUDE="$excl" bash 08_Tests/hooks/run_all_hooks.sh 2>"$DIR/.cache/test_results/run_all_hooks_last.stderr.log")
  printf '%s\n' "$_hooks_raw" > "$DIR/.cache/test_results/run_all_hooks_last.log" 2>/dev/null || true
  hooks_out=$(st_pick_hooks_final "$_hooks_raw")
  # (2026-11-10 H1) ★FINAL 을 집었어도 그것이 '이번 러너'의 것인지 확인한다 — 11-10 07:14 실행은 러너 꼬리가 깨져 결과 파일을
  #   다시 쓰지 못했는데, 자식 시험의 'FINAL … 9 total' 줄을 집어 hooks=9 로 기록했다. 결과 파일이 이번 실행 시작 뒤에
  #   쓰이지 않았으면 총계를 숫자가 아니라 null 로 둔다(check 가 '수집 실패'로 경고한다 · 숫자로 위장하지 않는다).
  _rm=$(date -r "$_res" +%s 2>/dev/null || echo 0)
  if [ -z "$hooks_out" ] || [ "${_rm:-0}" -lt "$_st0" ]; then
    echo "[suite-totals] ⚠ 러너 FINAL/결과 파일이 이번 실행의 것이 아님(FINAL='${hooks_out:-없음}' · 결과 파일 mtime ${_rm} < 시작 ${_st0}) — 총계 null"
    hooks_out=""
  fi
  unset _hooks_raw
  hooks=$(printf '%s' "$hooks_out" | grep -oE '[0-9]+ total' | grep -oE '[0-9]+')
  hooks_fail=$(printf '%s' "$hooks_out" | grep -oE '[0-9]+ fail' | grep -oE '[0-9]+')
  # ★unmeasured (v10 2026-09-03): 요약 JSON 을 안 내는 스위트는 러너가 UNMEASURED 로 계상한다 —
  #   그 스위트의 단언은 총계에 **0 으로** 들어가므로 '조용한 커버리지 구멍'이다. fail 과 같은 급으로 본다.
  hooks_unmeasured=$(printf '%s' "$hooks_out" | grep -oE '[0-9]+ unmeasured' | grep -oE '[0-9]+')
  # regime 합계 = 러너 결과의 08_Tests/regime/ 몫(위 st_folder_totals — 중복 러너 대체). 못 읽으면 null(0 으로 접지 않는다).
  regime_out=$(st_folder_totals "$DIR/.cache/test_results/hook_dryrun_results.json" "08_Tests/regime/" | tr -d '\r')
  regime="${regime_out%% *}"; regime_fail="${regime_out##* }"
  [ -n "$regime_out" ] || { regime=""; regime_fail=""; }
  contract=$(cd "$DIR" && CLAUDE_PROJECT_DIR="$DIR" Rscript 08_Tests/contract_regression/run_contract_regression.R 2>/dev/null \
          | grep -oE 'cases=[0-9]+' | grep -oE '[0-9]+' | head -1)
  cont_out=$([ -x "$PY" ] && "$PY" "$DIR/02_Infrastructure/tests/test_continuity_gate.py" 2>/dev/null \
          | grep -oE 'BATTERY: [0-9]+/[0-9]+' | head -1)
  continuity=$(printf '%s' "$cont_out" | grep -oE '/[0-9]+' | tr -d '/')
  continuity_fail=""
  if [ -n "$cont_out" ]; then
    local _cp _ct
    _cp=$(printf '%s' "$cont_out" | grep -oE '[0-9]+/' | tr -d '/')
    _ct=$(printf '%s' "$cont_out" | grep -oE '/[0-9]+' | tr -d '/')
    [ -n "$_cp" ] && [ -n "$_ct" ] && continuity_fail=$((_ct - _cp))
  fi

  # (2026-08-02) 수집 시점의 **트리 정체성**을 함께 남긴다.
  #   왜: --check 는 이 스냅샷을 읽어 판정을 출력하는데, 스냅샷이 어느 트리에서 나온
  #   값인지 표시가 없어 부팅이 **과거 값을 현재 판정으로 단언**했다(08-02 실측:
  #   00:40 수집 fail=6 을 01:5x 부팅이 그대로 보고 → 그 사이 8 커밋이 4건을 수리해
  #   실제는 fail=2). 나이(48h) 만으로는 못 잡는다 — 이 저장소는 시간당 여러 번 커밋한다.
  #   ★시간이 아니라 트리가 판정의 유효범위다("mtime→최신성" 대체 계열).
  local head_sha
  head_sha=$(cd "$DIR" && git rev-parse --short HEAD 2>/dev/null)

  # 빈 값 = 수집 실패 → 0 이 아니라 null 로 남긴다(0 으로 적으면 그 자체가 거짓 경보/거짓 안심)
  printf '{\n' > "$LATEST"
  printf '  "collected_at": "%s",\n' "$(date -Iseconds)" >> "$LATEST"
  printf '  "tree_head": %s,\n' "$( [ -n "${head_sha:-}" ] && printf '"%s"' "$head_sha" || printf 'null' )" >> "$LATEST"
  printf '  "tier": "%s",\n' "${tier:-full}" >> "$LATEST"
  printf '  "hooks": %s,\n'      "${hooks:-null}"      >> "$LATEST"
  printf '  "regime": %s,\n'     "${regime:-null}"     >> "$LATEST"
  printf '  "contract_regression": %s,\n' "${contract:-null}" >> "$LATEST"
  printf '  "continuity": %s,\n'  "${continuity:-null}" >> "$LATEST"
  printf '  "hooks_fail": %s,\n'      "${hooks_fail:-null}"      >> "$LATEST"
  printf '  "hooks_unmeasured": %s,\n' "${hooks_unmeasured:-null}" >> "$LATEST"
  printf '  "regime_fail": %s,\n'     "${regime_fail:-null}"     >> "$LATEST"
  printf '  "continuity_fail": %s\n'  "${continuity_fail:-null}" >> "$LATEST"
  printf '}\n' >> "$LATEST"
  echo "[suite-totals] 수집: hooks=${hooks:-?}(fail ${hooks_fail:-?} · unmeasured ${hooks_unmeasured:-?}) regime=${regime:-?}(fail ${regime_fail:-?}) contract=${contract:-?} continuity=${continuity:-?}(fail ${continuity_fail:-?})"
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

  # (2026-08-02) 스냅샷이 나온 트리와 **현재 트리**를 대조한다. 다르면 이 판정은
  #   "과거 트리에 대한 사실"이지 현재 상태가 아니다 — 그 구분을 출력에 강제한다.
  local cur_head snap_head ncommits
  cur_head=$(cd "$DIR" && git rev-parse --short HEAD 2>/dev/null)
  snap_head=$("$PY" -c 'import io,json,sys; print(json.load(io.open(sys.argv[1],encoding="utf-8")).get("tree_head") or "")' "$LATEST" 2>/dev/null)
  ncommits=""
  if [ -n "${cur_head:-}" ] && [ -n "${snap_head:-}" ] && [ "$snap_head" != "$cur_head" ]; then
    ncommits=$(cd "$DIR" && git rev-list --count "${snap_head}..HEAD" 2>/dev/null)
  fi

  "$PY" - "$BASELINE" "$LATEST" "${cur_head:-}" "${ncommits:-}" <<'PYEOF'
import datetime, io, json, sys
b = json.load(io.open(sys.argv[1], encoding="utf-8"))
l = json.load(io.open(sys.argv[2], encoding="utf-8"))
cur_head = sys.argv[3] if len(sys.argv) > 3 else ""
ncommits = sys.argv[4] if len(sys.argv) > 4 else ""

# 나이 — 항상 표시한다. "언제 잰 값인지"를 안 적으면 읽는 쪽이 현재로 읽는다.
age_txt = ""
ts = l.get("collected_at")
if ts:
    try:
        age_h = (datetime.datetime.now(datetime.timezone.utc)
                 - datetime.datetime.fromisoformat(ts).astimezone(datetime.timezone.utc)
                 ).total_seconds() / 3600.0
        age_txt = "%.1fh 전" % age_h
        if age_h >= 48:
            print("[suite-totals] ⚠ 수집 %.0fh 경과(48h+) — 이 비교는 과거값 기준입니다. "
                  "--collect 재실행 또는 daily_refresh 동작 확인" % age_h, file=sys.stderr)
    except Exception:
        pass

# (2026-08-02) ★트리 정체성 = 판정의 유효범위.
#   08-02 실측: 00:40 수집(fail=6)을 01:5x 부팅이 현재 판정으로 단언했으나, 그 사이 8 커밋이
#   4건을 수리해 실제는 fail=2 였다. 나이 임계(48h)로는 못 잡는다 — 이 저장소는 시간당
#   여러 번 커밋한다. 그래서 시간이 아니라 **트리가 움직였는가**로 유효범위를 판정한다.
#   ★단, 트리가 움직였다고 조용히 통과시키지 않는다(그건 검사 사망이다). 경보는 유지하고
#   '무엇에 대한 사실인지'만 정확히 라벨링한다.
snap_head = l.get("tree_head")
if snap_head and cur_head and snap_head != cur_head:
    vintage = ("수집 시점 %s 기준 · 현재 %s%s — 현재 트리 미검증"
               % (snap_head, cur_head, (" · 이후 %s 커밋" % ncommits) if ncommits else ""))
elif not snap_head:
    vintage = "수집 시점 트리 미기록(구식 스냅샷) — 현재 트리와의 일치 미확인"
else:
    vintage = ""

def scope(label):
    return "%s [%s%s]" % (label, ("수집 %s" % age_txt) if age_txt else "수집 시점 미상",
                          (" · " + vintage) if vintage else " · 현재 트리와 동일")

# (2026-07-26 probe①) fail 축 — total 불변이어도 FAIL>0 은 회귀다. 수집 실패(null)는
# 구식 latest(fail 축 도입 전) 호환으로 조용히 통과시키지 않고 이름으로 표시.
fails = {k: v for k, v in l.items() if k.endswith("_fail")}
fail_hits = [(k, v) for k, v in fails.items() if isinstance(v, int) and v > 0]
if fail_hits:
    print(scope("[suite-totals] ★FAIL>0 — 총계 불변이어도 회귀:"), file=sys.stderr)
    for k, v in fail_hits:
        print("  - %-20s fail=%d" % (k, v), file=sys.stderr)
    if vintage:
        print("  ※이 수치는 위 수집 시점 트리의 사실입니다. 현재 상태를 알려면 "
              "'bash 02_Infrastructure/ops/suite_totals_watch.sh --collect' 재실행.", file=sys.stderr)

# (2026-11-10) 단계가 다른 수집은 총계를 견주지 않는다 — 밤(nightly) 수집을 전체(full) 기준선과 비교하면 일부러 뺀 만큼이 '감소'로 뜬다.
#   fail 축(위)은 단계와 무관하게 그대로 본다.
_n = lambda t: "full" if (t or "full") in ("full", "weekly") else t   # weekly = 전체(모든 스위트) — 같은 단계로 본다
lt, bt = _n(l.get("tier")), _n(b.get("tier"))
tier_skip = ("hooks", "regime") if lt != bt else ()
if tier_skip:
    print("[suite-totals] 단계 %s 수집 — 기준선(%s)과 총계 비교 생략(%s). 전체 실행에서 비교한다" % (lt, bt, " · ".join(tier_skip)))
keys = [k for k in b if k not in ("collected_at", "note", "tree_head", "tier") and k not in tier_skip]
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
    print(scope("[suite-totals] ★총계 감소 — 회귀가 아니라 '침묵 결손'을 먼저 의심하세요:"), file=sys.stderr)
    for k, bv, lv in drops:
        print("  - %-20s %d → %d  (%+d)" % (k, bv, lv, lv - bv), file=sys.stderr)
    print("  점검: 해당 러너를 직접 돌려 케이스가 실행되는지 확인(총계 0 = 계측 사망)", file=sys.stderr)
if unknown:
    print("[suite-totals] ⚠ 수집 실패(null): %s — 수치 없음은 '정상'이 아니다" % ", ".join(unknown), file=sys.stderr)
if not drops and not unknown and not fail_hits:
    print(scope("[suite-totals] OK " + " · ".join("%s=%s" % (k, v) for k, v in ok)))
sys.exit(1 if (drops or fail_hits) else 0)
PYEOF
}

#──────────────────────────────────────────────────────────────────────────────
promote() {
  [ -f "$LATEST" ] || { echo "[suite-totals] 수집 결과 없음 — 먼저 --collect"; exit 1; }
  mkdir -p "$DIR/06_Registry"
  "$PY" - "$LATEST" "$BASELINE" <<'PYEOF'
import io, json, sys
l = json.load(io.open(sys.argv[1], encoding="utf-8"))
if (l.get("tier") or "full") not in ("full", "weekly"):
    print("단계 %s 수집 — 기준선 승격 거부(전체 실행만 기준선이 된다 · QVEST_SUITES_TIER=full 로 --collect --force)" % l.get("tier"))
    sys.exit(1)
if any(v is None for k, v in l.items() if k not in ("collected_at", "tree_head", "tier")):
    print("null 포함 — 기준선 승격 거부(불완전 수집을 기준선으로 삼으면 이후 감소를 못 잡는다)")
    sys.exit(1)
l["note"] = ("테스트 스위트 총계 기준선. 감소 = 회귀가 아니라 침묵 결손 우선 의심. "
             "갱신은 suite_totals_watch.sh --collect 후 --baseline.")
io.open(sys.argv[2], "w", encoding="utf-8").write(json.dumps(l, ensure_ascii=False, indent=2) + "\n")
print("기준선 갱신:", {k: v for k, v in l.items() if k not in ("note", "collected_at")})
PYEOF
}

# 라이브러리 모드: QVEST_ST_LIB=1 로 source 하면 디스패처를 돌리지 않는다(테스트용).
if [ "${QVEST_ST_LIB:-0}" = "1" ]; then return 0 2>/dev/null || exit 0; fi
case "$MODE" in
  --collect)  collect "${2:-}" ;;
  --baseline) promote ;;
  --check|*)  check ;;
esac
