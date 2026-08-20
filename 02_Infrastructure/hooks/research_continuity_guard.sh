#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
#==============================================================================
# research_continuity_guard.sh — Stop hook (Continuity Firewall: 포기 원천차단)
#
# 도훈 mandate 2026-07-15: "자체적으로 포기하지 않는 자가발전형 아키텍처. 누적 실패 후
#   '끝남 표현들'로 라운드를 마무리하려는 것을 원천차단."
#   → warn-only(2026-07-13)에서 BLOCK으로 승격. settings.json _doc이 예고한 "2주 관찰 후
#     block 승격"의 집행 + 도훈 명시 mandate.
#
# 아키텍처(4레이어 — SOT 02_Infrastructure/docs/rules/continuity-firewall.md):
#   L1 차단 실효: 이 훅이 continuity_gate.py 판정을 받아 {"decision":"block"} 발행 →
#                 종결 턴을 되돌려 강제 속행(사후 넛지가 아니라 현재 턴 개입).
#   L2 독립 semantic 판정: continuity_gate.py = 케이스 결정론 + verdict-close 일반화(신어
#                 커버) + 선택적 Haiku(QVEST_CONTINUITY_LLM=1). 편향 당사자 self-certify 차단.
#   L3 건설적 종료계약: 종결 프레이밍 감지 시 next_probe≥2 (+negative면 live_trigger) 요구.
#                 close_round()가 이 계약을 인자로 강제(paved path) → 마커로 게이트 자동 통과.
#   L4 자가발전: 06_Registry/continuity_cases.json 성장(잡을수록 강해짐). 차단 이력은
#                 .cache/continuity_blocks.jsonl 감사 → 주간 /cleaner가 신규 우회를 케이스로 승격.
#
# 무한루프 방지: continuity_gate.py 내부 per-turn cap(기본 3) + stop_hook_active + ERR trap.
# 안전: 어떤 오류든 '{}'(통과)로 빠져 내 턴을 깨지 않음(fail-open — 포기억제가 목적이지
#       작업차단이 아님).
#==============================================================================
set -uo pipefail
trap 'echo "{}"; exit 0' ERR

DIR="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
GATE="$DIR/02_Infrastructure/axiom/continuity_gate.py"

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("hook_event_name",""))' 2>/dev/null || echo "")
if [ "$EVENT" != "Stop" ]; then echo '{}'; exit 0; fi
TP=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("transcript_path",""))' 2>/dev/null || echo "")
if [ -z "$TP" ] || [ ! -f "$TP" ]; then echo '{}'; exit 0; fi

# ── L1~L3: continuity_gate 판정 (block JSON 또는 '{}') ────────────────────────
GATE_OUT='{}'
if [ -f "$GATE" ]; then
  GATE_OUT=$(CLAUDE_PROJECT_DIR="$DIR" PYTHONUTF8=1 "$QVEST_PY_BIN" "$GATE" --transcript "$TP" 2>>/tmp/continuity_gate.stderr.log || echo '{}')
  [ -n "$GATE_OUT" ] || GATE_OUT='{}'
fi

# block 발행 시 그대로 전달(차단 실효). 차단 이력 감사는 gate 내부(_log_block)가 확장 스키마
# ({ts,tp,categories,verdict_tokens,matched_terms,reason,span_hash})로 continuity_blocks.jsonl에
# 직접 기록 — 여기서 {ts,tp} 중복 append 하지 않음(C4 정합). pass 분모는 gate가
# .cache/continuity_gate_counters/passes_YYYYMMDD.json 일자 카운트로 확보.
if printf '%s' "$GATE_OUT" | grep -q '"decision"'; then
  printf '%s\n' "$GATE_OUT"
  exit 0
fi

# ── W3(유지): 라운드 수집(신규 L-code) 후 계층 병목 지도 미갱신 warn ──────────
# gate가 pass일 때만. block과 달리 순수 컨텍스트 넛지.
#
# ★2026-08-20 대리지표 제거 (map_freshness_v1). 구 구현은 지도의 **mtime** 을 최신 L-code
#   mtime 과 비교했다 → 지도를 touch 하거나 헤더 `**갱신**:` 줄만 한 줄 append 해도 초록.
#   실측(git 이력에서 표 본문 sha 추적): 표 본문이 2026-08-09 12:49 → 08-17 16:48 까지
#   **8일 바이트 동일**한 사이 파일을 건드린 커밋 20건, 직전 정체는 07-19 → 08-02 **14일/16커밋**.
#   그 내내 mtime 은 최신이라 W3·W8 둘 다 침묵했다.
# 판정 규약은 memory_knowledge_health.R 의 .mf_* 헬퍼(map_freshness_v1)와 **동일**해야 한다:
#   ① 해시 대상 = `|` 로 시작하고 구분선이 아닌 줄 전부(계층 표 9행 + 재료 표 3행 + 헤더 2행 = 14행).
#      버전 체인·인용 갱신 이력·부기 문단은 append 로 증식하므로 제외.
#   ② sha256(rows join "\n" 의 UTF-8) — R digest 와 python hashlib 동일값 실측 확인.
#   ③ 스냅샷 .cache/layer_bottleneck_map_content.json {schema,table_sha,n_rows,observed_at}.
#      부재 시 최초 1회 생성만(observed_at=now → lag<=0 → 무경보, 초기화 오탐 방지).
#   ④ 임계 24h. W3 은 여기에 자기 발화 범위(최근 6h 내 L-code 적립)만 곱한다.
#   ⑤ L-code 시각 = W8 과 같은 3-glob + /superseded/ 제외 + created_at(부재 시 mtime).
#      mtime 내림차순 조기중단 — 실측 428/428 에서 created_at <= mtime 이라 결과 동일하고
#      전수 파싱 0.86s → 수 ms. 두 구현 판정 동치는 08_Tests/hooks/test_map_freshness_content.R 강제.
# 폴백(회귀 없음): 표 0행 / 스냅샷 read·write 불가 → 구 mtime 판정 그대로 수행하고 메시지에 명시.
# 안전: 어떤 예외든 '{}'(무경보)로 빠짐 — 기존 fail-open 자세 유지.
ACTIVE=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; print(json.load(sys.stdin).get("stop_hook_active",False))' 2>/dev/null || echo "False")
if [ "$ACTIVE" = "True" ]; then echo '{}'; exit 0; fi

"$QVEST_PY_BIN" - "$DIR" <<'PY' 2>/dev/null || echo '{}'
import os, sys, glob, time, json, re, hashlib

root = sys.argv[1]
MF_SCHEMA = "map_freshness_v1"
MF_THRESH_H = 24.0
MF_RECENT_S = 6 * 3600          # W3 고유 발화 범위(판정 기준 아님)

_SEP_RE = re.compile(r'^\|[\s:|-]+\|\s*$')
_EOL_RE = re.compile(r'[\r\n]+$')


def mf_table_rows(map_p):
    with open(map_p, 'r', encoding='utf-8', errors='replace') as fh:
        lines = fh.read().split('\n')
    rows = [_EOL_RE.sub('', x) for x in lines]
    rows = [x for x in rows if x.startswith('|')]
    return [x for x in rows if not _SEP_RE.match(x)]


def mf_table_sha(rows):
    return hashlib.sha256('\n'.join(rows).encode('utf-8')).hexdigest()


def mf_observed_at(root, table_sha, n_rows, now_s):
    """스냅샷과 대조해 table_sha 최초 관측 시각을 반환. 실패 시 None(→ mtime 폴백)."""
    snap_p = os.path.join(root, '.cache', 'layer_bottleneck_map_content.json')
    try:
        with open(snap_p, 'r', encoding='utf-8') as fh:
            prev = json.load(fh)
        if (prev.get('schema') == MF_SCHEMA
                and isinstance(prev.get('table_sha'), str)
                and prev.get('table_sha') == table_sha):
            return float(prev['observed_at'])
    except Exception:
        pass
    try:
        os.makedirs(os.path.dirname(snap_p), exist_ok=True)
        tmp = snap_p + '.tmp%d' % os.getpid()
        with open(tmp, 'w', encoding='utf-8') as fh:
            json.dump({'schema': MF_SCHEMA, 'table_sha': table_sha,
                       'n_rows': int(n_rows), 'observed_at': now_s,
                       'observed_at_iso': time.strftime('%Y-%m-%dT%H:%M:%S',
                                                        time.localtime(now_s))}, fh)
        os.replace(tmp, snap_p)
        return now_s
    except Exception:
        return None


def mf_newest_lcode(root):
    """W8(.lc_research_time)과 동일: 3-glob, /superseded/ 제외, created_at(부재 시 mtime)."""
    pats = [os.path.join(root, 'stage_artifacts', 'l_code', '*', 'l_code_*.json'),
            os.path.join(root, 'stage_artifacts', 'l_code_*.json'),
            os.path.join(root, '04_Research', 'strategies', '*', 'stage_artifacts', '[Ll]_code*.json')]
    files = []
    for p in pats:
        files.extend(glob.glob(p))
    files = [f for f in files if '/superseded/' not in f.replace('\\', '/')]
    if not files:
        return None
    pairs = sorted(((os.path.getmtime(f), f) for f in files), reverse=True)
    best = 0.0
    for mt, f in pairs:
        if mt <= best:
            break                # created_at <= mtime 불변식 하에서 더 개선 불가
        ts = None
        try:
            with open(f, 'r', encoding='utf-8') as fh:
                ca = json.load(fh).get('created_at')
            if ca:
                s = str(ca).replace('T', ' ').replace('Z', '').strip()
                # R as.POSIXct(optional=TRUE) 와 동일 순서/폭 (초 → 분 → 날짜)
                for width, fmtstr in ((19, '%Y-%m-%d %H:%M:%S'), (16, '%Y-%m-%d %H:%M'),
                                      (10, '%Y-%m-%d')):
                    try:
                        ts = time.mktime(time.strptime(s[:width], fmtstr))
                        break
                    except Exception:
                        continue
        except Exception:
            ts = None
        best = max(best, ts if ts is not None else mt)
    return best


msgs = []
try:
    now_s = time.time()
    newest_lc = mf_newest_lcode(root)
    map_p = os.path.join(root, '06_Registry', 'layer_bottleneck_map.md')
    if newest_lc and os.path.exists(map_p) and (now_s - newest_lc) < MF_RECENT_S:
        basis, reason = 'content', ''
        rows = mf_table_rows(map_p)
        obs = None
        if rows:
            obs = mf_observed_at(root, mf_table_sha(rows), len(rows), now_s)
            if obs is None:
                basis, reason = 'mtime', '스냅샷 read/write 불가'
        else:
            basis, reason = 'mtime', '표 본문 추출 0행(지도 형식 변경 의심)'
        if basis == 'mtime':
            obs = os.path.getmtime(map_p)
        lag_h = (newest_lc - obs) / 3600.0
        if lag_h > MF_THRESH_H:
            msgs.append("[research_continuity_guard/W3] 최근 6시간 내 L-code가 적립됐는데 계층 병목 지도"
                        "(06_Registry/layer_bottleneck_map.md)의 **표 본문**이 %.1fh 째 그대로입니다"
                        "(임계 24h · basis=%s%s) — 라운드 수집 시 지도 갱신 의무"
                        "(answer-principles 연속성 5호). mtime 갱신·헤더 부기로는 해소되지 않습니다. "
                        "해당 계층 행·갭 귀속을 갱신하세요." % (lag_h, basis,
                                                                (' · 폴백 사유: ' + reason) if reason else ''))
except Exception:
    pass
print(' | '.join(msgs) if msgs else '{}')
PY
