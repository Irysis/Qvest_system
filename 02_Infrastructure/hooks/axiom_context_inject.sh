#!/usr/bin/env bash
#==============================================================================
# axiom_context_inject.sh — PreToolUse[Agent] 지식 주입 (v9 Lean Loop, 2026-08-23)
#
# 무엇이 바뀌었나 (재극성):
#   구(v8): 주입문 ~3KB 의 대부분이 "죽은 방향 재제안 금지" 목록이었다 —
#     strategic_truths 블록 + Distilled **negative/conditional** top-5 + 부활 발화 +
#     판정 어휘 규약. distilled 167 카드 중 negative 71 vs positive 11(6.6%)이라
#     에이전트가 매 spawn 마다 받는 창의성 입력이 사실상 울타리였다.
#   신(v9): "무엇이 통했나 + 최근 교훈" 으로 뒤집고 **2,000자** 상한을 건다.
#     dead 지식은 삭제가 아니라 **1줄 포인터**(개수 + lookup 명령)로 강등 —
#     필요하면 에이전트가 직접 조회한다(INV-7 재도전 규약 보존).
#
# 계산은 여기서 하지 않는다: 변동부(상위 전략·양성 DIST·최근 교훈·dead 개수)는
#   02_Infrastructure/axiom/lcode_harvester.py::write_positive_context() 가
#   .cache/positive_context.json 으로 미리 만든다. 이 훅은 **읽기만** 한다
#   (매 Agent spawn 경로라 레지스트리 3종 파싱을 얹을 수 없다).
#   파일 부재 = 고정부만 주입 (회귀 없음, 조용한 축소).
#
# 고정부(절대 절단 없음) = [AX 전제] 헤더 + active 공리 + [고정 축]/프론티어 + dead 줄.
# 감축 사다리(예산 초과 시)  = ①DIST 포기 ②최근 교훈 3→2→1 ③전략 5→3.
#==============================================================================
trap 'echo "{}"; exit 0' ERR
# (v8.1.2 2026-06-11) python stdio/open UTF-8 강제 — cache body가 cp949로 쓰이고 additionalContext에
# lone surrogate(\udcXX) 주입돼 Agent spawn 세션 전체가 API 400 나던 사건 수리.
export PYTHONUTF8=1
# (v8.2.1 HOOK-P0-1) bare python3 = Windows Store 스텁 → 주입 전체 무발화. 공용 해석기 사용.
QVEST_PARSE_RESOLVE_ONLY=1; source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"; unset QVEST_PARSE_RESOLVE_ONLY
INPUT=$(cat)
# CLAUDE_PROJECT_DIR(native Windows 경로) 우선 — MSYS형(/c/...) 경로를 native python glob에 넘기면 0건 매치로
# regen 실패 → ERR trap {} 무출력이던 버그 수정 (2026-06-10). 백슬래시도 슬래시로 정규화.
DIR="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-}}"
DIR="${DIR//\\//}"
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
fi
# (v10.1 2026-08-29) 2줄 추출 — 1행 agent, 2행 round_type.
#   ★사유: 구판은 subagent_type 만 읽어 고정 축을 **하드코딩 리터럴 1벌**로 주입했고, 그 리터럴에
#   '충실구현 라운드: 논문 그대로(롱숏·종목수·비중·리밸)' 줄이 들어 있었다. 강화(WT-R) 에이전트도
#   이 줄을 매 spawn 마다 받았으므로 **롱숏이 정당한 프로필로 광고**됐다(실측 2026-08-29 —
#   강화 라운드에서 롱숏 설계 반복 등장, 도훈 지적 "롱숏을 왜 자꾸 설계하는거야").
#   판별은 WT id 접두(R=reinforcement)라는 **구조**로 한다 — 프롬프트 문구가 아니라 식별자다.
_AX_META=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,re,sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
try:
    d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace")); ti=d.get("tool_input",{})
    print(ti.get("subagent_type","") or ti.get("description",""))
    _t = str(ti.get("prompt","")) + " " + str(ti.get("description",""))
    print("reinforcement" if re.search(r"WT-R[0-9]{8}_[0-9]{3}", _t) else "")
except Exception:
    print(""); print("")' 2>/dev/null || echo "")
AGENT_NAME=$(sed -n '1p' <<< "$_AX_META")
ROUND_TYPE=$(sed -n '2p' <<< "$_AX_META")
AGENT_NAME_LC=$(printf '%s' "$AGENT_NAME" | tr "[:upper:]" "[:lower:]")

ACTIVE_DIR="$DIR/qepm/memory/axioms/active"
CACHE_BODY="$DIR/.cache/axiom_inject_body.md"
# (v9.1 2026-08-23 커밋2) 캐시 2분리 — 전역 Law 는 **고정부**, mode-local 은 **감축 tier**.
#   한 파일에 섞으면 mode-local 이 body_fixed 로 들어가 감축 사다리의 손이 닿지 않는다
#   (실측 예측: 18건 활성화 시 body_fixed 368→1,827자 → 렌더 3,030자 → ctx[:2000] 절단으로
#   '[현재 최고 연구-tier 전략]'·'[최근 교훈]'·'dead configs' 가 전부 소실 = v9 재극성 역전).
CACHE_ML="$DIR/.cache/axiom_inject_modelocal.md"
INJECT_LAST="$DIR/.cache/axiom_inject_last.json"

# regen body if missing or active AX newer than cache
# (v9 2026-08-23) ★훅 자신이 캐시보다 새로우면 함께 재생성 — 렌더 규칙(status 필터·길이)을
#   바꿔도 캐시가 낡은 규칙으로 남아 조용히 구 동작을 유지하던 계통 차단.
shopt -s globstar 2>/dev/null  # mode-local(active/modes/**) 포함
NEWEST=$(ls -t "$ACTIVE_DIR"/**/AX-*.json "$ACTIVE_DIR"/AX-*.json 2>/dev/null | head -1)
SELF="${BASH_SOURCE[0]:-$0}"
# (2026-09-23) rollback_axiom 은 파일을 active/ 에서 **빼기만** 하므로 NEWEST 가 새로워지지 않는다 — 삭제는 mtime 을
#   남기지 않는다. 그러면 mode-local 캐시가 롤백된 공리를 계속 주입한다. rollback 이 같은 트랜잭션에서 쓰는
#   tombstones.json 이 캐시보다 새로우면 재생성한다(Axiom 전수감사 0-5 의 주입면 도달 보장).
TOMB="$DIR/qepm/memory/axioms/tombstones.json"
if [ -n "$NEWEST" ] && { [ ! -f "$CACHE_BODY" ] || [ ! -f "$CACHE_ML" ] || \
      [ "$NEWEST" -nt "$CACHE_BODY" ] || [ "$SELF" -nt "$CACHE_BODY" ] || \
      [ "$NEWEST" -nt "$CACHE_ML" ] || [ "$SELF" -nt "$CACHE_ML" ] || \
      { [ -f "$TOMB" ] && [ "$TOMB" -nt "$CACHE_ML" ]; }; }; then
  "$QVEST_PY_BIN" -c "
import json, os, glob
lines = []
ml = []
_files = set(glob.glob(os.path.join('$ACTIVE_DIR', '**', 'AX-*.json'), recursive=True)) | set(glob.glob(os.path.join('$ACTIVE_DIR', 'AX-*.json')))
_n = 0
ML_LINE_MAX = 70
for f in sorted(_files):
    try:
        ax = json.load(open(f, encoding='utf-8'))
        # (v9) mode-local(active/modes/**) 은 status=active 인 것만 주입한다.
        #   승격 사다리가 status=proposed 로 후보를 적재하므로(무인 활성화 게이트 R0~R6
        #   미통과분 = HELD/proposed), 필터가 없으면 미정제 공리가 '대전제' 로 광고된다.
        #   전역 AX-*.json 은 status 필드 자체가 없어 이 조건에 걸리지 않는다(구 동작 불변).
        _rel = os.path.normpath(f).replace(chr(92), '/')
        _is_ml = '/modes/' in _rel
        if _is_ml and (ax.get('status') or 'active') != 'active':
            continue
        axid = ax.get('axiom_id') or ax.get('id') or os.path.basename(f)[:-5]
        if _is_ml:
            # (커밋2) mode-local 은 별도 캐시로. 주입 문구는 statement_inject(정제기 S8 산출)
            #   우선 — 없으면 statement 앞 70자. 정렬 = promotion.weighted_score 내림차순.
            _txt = (ax.get('statement_inject') or ax.get('statement') or ax.get('text') or '')
            _txt = ' '.join(str(_txt).split())[:ML_LINE_MAX]
            _mode = ax.get('research_mode') or 'unknown'
            try:
                _w = float((ax.get('promotion') or {}).get('weighted_score') or 0.0)
            except Exception:
                _w = 0.0
            ml.append((-_w, str(axid), '%s\t  - %s: %s' % (_mode, axid, _txt)))
            continue
        # (2026-09-23 Axiom 전수감사 K11 · 판정서 단계 1-6) 전역 Law 는 **절단하지 않는다**.
        #   구판 [:75] 가 AX-000 금지절 전체 · AX-001 조건 · AX-008 조작 조항을 잘라 주입했다.
        #   공백만 한 줄로 접는다(아래 body_fixed 가 줄 단위로 읽으므로 개행이 섞이면 줄이 쪼개진다).
        stmt = ' '.join(str(ax.get('statement') or ax.get('text') or ax.get('name') or '').split())
        tt = ax.get('type') or ax.get('grade') or 'IMMUTABLE'
        tp = ax.get('polarity') or ('axiom' if ax.get('grade')=='IMMUTABLE' else '?')
        lines.append(f'  - {axid} [{tt}/{tp}]: {stmt}')
        _n += 1
    except Exception: pass
lines.append(f'  → 전문: .claude/rules/axioms.md / active/ (+ modes/, total {_n})')
open('$CACHE_BODY', 'w', encoding='utf-8').write(chr(10).join(lines))
ml.sort()
open('$CACHE_ML', 'w', encoding='utf-8').write(chr(10).join(m[2] for m in ml))
" 2>/dev/null
fi

[ -s "$CACHE_BODY" ] || { echo '{}'; exit 0; }

case "$AGENT_NAME_LC" in
  *forge*)    HEADER='[AX 전제 — Forge] AX 범위 내 실험이면 AX 인용 + 경계 조건 명시.' ;;
  *judge*)    HEADER='[AX 전제 — Judge] AX 범위인데 반대 결과면 결과가 아닌 실험을 먼저 의심 (auditor).' ;;
  *book*)     HEADER='[AX 전제 — BOOK 트래커] frozen 스펙 재현만 — 등급 재채점 금지.' ;;
  *)          HEADER='[AX 전제] 아래 공리는 qvest 모든 행위의 대전제.' ;;
esac

# (2026-08-17 폐쇄루프 감사 Rank2 수리) 프론티어 목록 = CLAUDE.md 정본 런타임 파생.
#   하드코딩(M7 07-10)이 v8.4 재편(08-13) 이후 38일간 낙후돼 매 spawn 마다 도훈이 08-09 에
#   닫은 lane 을 ①순위 레버로 광고했다(주입문 v8.4 키워드 5종 실측 0건). 캐시를 두면 그
#   캐시가 다시 낡으므로 캐시 없이 매 호출 CLAUDE.md 를 읽는다.
CLAUDE_MD="$DIR/CLAUDE.md"
# (v9 2026-08-23) 변동부 단일 원천 — lcode_harvester.py::write_positive_context() 산출물.
POSITIVE_CTX="$DIR/.cache/positive_context.json"
ESC=$(printf '%s' "$HEADER" | CB="$CACHE_BODY" PC="$POSITIVE_CTX" CM="$CLAUDE_MD" \
      ML="$CACHE_ML" IL="$INJECT_LAST" QVEST_INJECT_AGENT="$AGENT_NAME_LC" QVEST_ROUND_TYPE="$ROUND_TYPE" "$QVEST_PY_BIN" -c "
import json, os, sys
def rd(p):
    try:
        return open(p, encoding='utf-8', errors='replace').read().strip()
    except Exception:
        return ''
hdr = sys.stdin.buffer.read().decode('utf-8', 'replace')
body = rd(os.environ.get('CB', ''))
# (E+F 2026-07-04) 고정 제약 7종 = 불가침 문제-축 블록. 제약 완화는 레버 아님(AX-000).
# (2026-08-17 Rank2 수리) 프론티어 줄 = CLAUDE.md FRONTIER_AXES 마커 구간 런타임 파생.
#   구 동작: 07-10 문장 하드코딩 → v8.4(08-13) 재편이 반영 안 돼 폐쇄 lane 을 ①순위로 광고.
#   신 동작: 마커 구간을 매 호출 파싱(캐시 없음 = 원리적으로 낡을 수 없음).
#   ★마커 부재/파싱 실패/파일 부재 시 _FRONTIER_FALLBACK 으로 폴백 — 회귀 없음.
import re as _re_fa
_FRONTIER_FALLBACK = '  조건-안 레버 프론티어(폴백 — CLAUDE.md FRONTIER_AXES 마커 미발견): 정본 확인 필요.'
_SETTLED_FALLBACK = r'DPL|regime.?conditional|ML.?sizing|uncertainty.?sizing'
_FA_MAX = 200   # (v9) 프론티어 줄 상한 — 구 330자. 2,000자 예산의 고정부 몫.
def _fa_strip(s):
    for a in ('**', '\`', '★', '⚠'):
        s = s.replace(a, '')
    return ' '.join(s.split())
def _fa_derive():
    raw = rd(os.environ.get('CM', ''))
    if not raw or 'FRONTIER_AXES_START' not in raw or 'FRONTIER_AXES_END' not in raw:
        return _FRONTIER_FALLBACK, _SETTLED_FALLBACK
    seg = raw.split('FRONTIER_AXES_START', 1)[1].split('FRONTIER_AXES_END', 1)[0]
    lever, carve = '', ''
    for ln in seg.splitlines():
        t = ln.lstrip('>').strip()
        if '조건-안 레버만 프론티어' in t and not lever:
            lever = _fa_strip(t.split('조건-안 레버만 프론티어', 1)[1])
            # 원문이 '프론티어 — 현행(...)' 이라 선두 대시/구두점 잔재 제거
            lever = lever.lstrip('-–—:').strip()
        elif '부활이 아님을 구분' in t and not carve:
            carve = _fa_strip(t)
    if not lever:
        return _FRONTIER_FALLBACK, _SETTLED_FALLBACK
    # 문장 중간 절단 방지 — 상한 안에서 **문장 경계**(마침표) 우선.
    #   ★반쪽 인용이 위험한 이유: 정본 꼬리가 'DPL·regime-conditional·ML sizing 은
    #     settled-negative — 레버 아님' 이라 부정어가 잘리면 폐쇄 lane 목록이 그대로
    #     '레버 프론티어' 줄에 남는다(v8 이 38일간 저지른 것과 같은 오독). 잘릴 바엔 버린다.
    _lv = lever[:_FA_MAX]
    if len(lever) > _FA_MAX:
        _cut = _lv.rfind('.')
        if _cut < 100:
            _cut = _lv.rfind(')')
        if _cut > 100:
            _lv = _lv[:_cut + 1]
    out = '  조건-안 레버 프론티어(CLAUDE.md 정본 파생): ' + _lv
    if carve:
        out = out + chr(10) + '  ' + carve[:200]
    # settled lane 토큰도 같은 정본 문장에서 파생.
    #   ※v9 에서 '부활 발화' 블록이 dead 1줄로 접히며 현재 소비자는 없다. 파생 자체는
    #     유지한다 — 블록 재도입 레시피(_archive_v8_enforcement)가 이 패턴을 전제한다.
    pat = _SETTLED_FALLBACK
    if 'settled-negative' in lever:
        head = lever.split('settled-negative', 1)[0]
        head = _re_fa.split(r'[①②③④⑤]', head)[-1]
        toks = []
        for p in head.split(chr(183)):
            p = p.split('(')[0].strip()
            p = _re_fa.sub(r'[은는이가]\$', '', p).strip()
            if 2 <= len(p) <= 30:
                toks.append(_re_fa.escape(p))
        if toks:
            pat = '|'.join(toks)
    return out, pat
_fa_line, _SETTLED_PAT = _fa_derive()
# (v10.1) 고정 축은 **라운드 종류에 따라 다른 것**이라 리터럴 1벌로 주입하면 안 된다.
#   강화(WT-R)에는 충실구현 프로필(롱숏 허용)을 아예 보여주지 않는다 — 보이면 선택지가 된다.
_rt = os.environ.get('QVEST_ROUND_TYPE', '')
if _rt == 'reinforcement':
    _axis2 = ('  ★강화 라운드(WT-R) — 실투형 단일 프로필: long-only(w>=0)·<=25종·K200∪KQ150·15bps(v2.4 delta)·Σw=1 + PIT C1~C15. 비중 상한 없음(v10 폐지). 제약-귀속·완화 금지.' + chr(10) +
              '  ★롱숏·>25종·논문 원구성 복제는 이 라운드의 선택지가 아니다 — 논문이 롱숏으로 보고해도 후보는 롱온리다. 원문 수치는 앵커로만 쓰고 구성은 이식하지 않는다.')
else:
    _axis2 = ('  실투형(강화 프로세스부터): long-only(w>=0)·<=25종·K200∪KQ150·15bps(v2.4 delta)·Σw=1 + PIT C1~C15. 비중 상한 없음(v10 폐지). 제약-귀속·완화 금지.' + chr(10) +
              '  충실구현 라운드(1계층 최초): 논문 그대로(롱숏·종목수·비중·리밸) — 유니버스만 K200∪KQ150 치환. PIT 는 계층 무관 불변.')
axis = ('[고정 축 — 변수 아님, 이 안에서 풀 것] (v10 2026-08-29 2계층)' + chr(10) +
        _axis2 + chr(10) +
        '[정체성 — quant-identity.md 정본] 최정상급 퀀트: ①최신 수리통계·ML 적극 ②냉소는 방법론(과적합·스누핑·시점오염)을 향한다 — 실증 통과 성과 폄하 금지' + chr(10) +
        '  ③리서치는 지난하다 — 실패가 정상, 지름길(허들 완화·측정 우회)이 진짜 실패 ④모든 수치 결정 = 논문 뿌리(원문 링크)·하드코딩 금지·한 논문 매몰 금지.' + chr(10) +
        _fa_line)

# ── 변동부: .cache/positive_context.json (생산자 = lcode_harvester.py) ────────
#   부재/파손 = 고정부만 주입. 훅이 레지스트리를 직접 읽지 않는 이유 = 매 spawn 경로.
pos_lines, dist_lines, rec_lines = [], [], []
dead_line = ''
pc_status = 'ok'

def _load_pc():
    global pos_lines, dist_lines, rec_lines, dead_line
    _pc = json.load(open(os.environ.get('PC', ''), encoding='utf-8'))
    pos_lines = [l for l in (_pc.get('positive_block') or '').splitlines() if l.strip()]
    dist_lines = [l for l in (_pc.get('dist_block') or '').splitlines() if l.strip()]
    rec_lines = [l for l in (_pc.get('recent_block') or '').splitlines() if l.strip()]
    dead_line = (_pc.get('dead_line') or '').strip()
    if not dead_line and isinstance(_pc.get('n_dead'), int):
        dead_line = ('[dead configs %d — 착수 전 '
                     '\`Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <kw>\` 1줄 확인]'
                     % _pc['n_dead'])

# ★1회 재시도(0.15s) — 사유 정정 (2026-08-23 v9.1 후속 실측).
#   구 주석은 생산자가 비원자적으로 쓴다고 적었으나 사실이 아니었다:
#   write_positive_context() 는 도입 시점부터 _write_json_atomic(= os.replace) 을 썼고,
#   os.replace 는 Windows 에서도 원자적이라 이 파일은 애초에 찢기지 않는다.
#   실측한 진짜 기전은 반대 방향이다 — 이 훅이 파일 핸들을 연 순간 생산자의
#   os.replace 가 PermissionError[WinError 5] 로 실패한다(교체가 통째로 취소).
#   즉 소비자가 보는 것은 절단된 파일이 아니라 낡았거나 아직 없는 파일이고,
#   HARD_10 이 잡은 (len 807 · 마커 3/3 소실) 은 그 부재·정체의 결과다.
#   ⇒ 생산자 쪽 수리 = os.replace 유한 재시도 + tmp 정리 (lcode_harvester.py).
#     소비자 쪽 재시도는 그와 별개로 유지한다 — 파일이 교체되는 찰나의 open 실패와
#     OneDrive/AV 의 일시 잠금은 생산자가 못 없앤다. 실패해도 조용히 축소되지 않도록
#     pc_status 를 계측에 남긴다(missing/unreadable/retry_ok).
# ★2026-08-24 재발방지 — 이 파이썬 블록 전체는 셸의 -c 큰따옴표 문자열 안에 있다.
#   그래서 주석에 이스케이프 없는 큰따옴표나 백틱을 넣으면 그 자리에서 셸 문자열이
#   끊기거나 명령치환이 일어나고, 파이썬은 잘린 프로그램을 받아 죽는다 → ESC 가 비어
#   additionalContext 가 공백이 되고 훅은 깨진 JSON 을 낸다.
#   실제로 오늘 주석-only 변경 하나가 이 훅을 통째로 무력화했다
#   (frontier_axes_derive 13 fail + inject_usage_ranking 1 fail 로 검출).
#   ⇒ 이 블록 안 주석에는 큰따옴표·백틱을 쓰지 말 것. 홑따옴표로 대체한다.

try:
    _load_pc()
except Exception:
    try:
        import time as _t
        _t.sleep(0.15)
        _load_pc()
        pc_status = 'retry_ok'
    except Exception:
        pos_lines, dist_lines, rec_lines, dead_line = [], [], [], ''
        pc_status = 'missing' if not os.path.exists(os.environ.get('PC', '')) else 'unreadable'

H_POS = '[현재 최고 연구-tier 전략 — 여기서 출발·결합할 것]'
H_DIST = '[검증된 양성 지식]'
# 공리 블록: 고정부 — 절대 절단 대상 아님.
#   (2026-09-23 Axiom 전수감사 K11) 구판은 렌더 라인당 [:80] 상한이라 고정부가 사실상 절단됐다
#   (AX-000 은 조기 한계 단정 금지절 전체가 소실). 전역 Law 4건은 전문 렌더 — 예산은 아래 사다리가 변동부에서 흡수한다.
#   들여쓰기 재부여 = rd() 의 .strip() 이 캐시 첫 줄의 선행 공백만 먹어 정렬이 깨지던 것 수리.
#   ★고정부 = 전역 Law 뿐. mode-local 은 아래 ml_lines(감축 tier)로 간다.
body_fixed = chr(10).join('  ' + ln.strip() for ln in body.splitlines() if ln.strip())

# ── mode-local 공리(감축 tier, 커밋2) ────────────────────────────────────────
#   캐시 형식 = '<mode>\\t  - <AX-ID>: <statement_inject ≤70자>' 한 줄에 하나.
#   ML_MAX_TOTAL/PER_MODE 는 렌더 시점 상한이고, 사다리가 여기서 더 깎는다.
ML_MAX_TOTAL = 5
ML_MAX_PER_MODE = 2
ml_all = []
for _ln in rd(os.environ.get('ML', '')).splitlines():
    if not _ln.strip():
        continue
    _m, _sep, _txt = _ln.partition(chr(9))
    ml_all.append((_m if _sep else 'unknown', _txt if _sep else _ln))
ML_N = len(ml_all)
ML_PTR = ('[mode-local 공리 %d건 — Rscript -e \\'source(\"02_Infrastructure/axiom/promote.R\"); '
          'list_active_axioms()\\']' % ML_N)

def _ml_pick(n):
    '''상위 n줄 — 모드당 ML_MAX_PER_MODE 상한을 지키며 weighted_score 순서(캐시 순서) 유지.'''
    out, per = [], {}
    for m, txt in ml_all:
        if len(out) >= n:
            break
        if per.get(m, 0) >= ML_MAX_PER_MODE:
            continue
        per[m] = per.get(m, 0) + 1
        out.append(txt)
    return out

def _blk(header, lines):
    return (header + chr(10) + chr(10).join(lines)) if lines else ''

def _assemble(n_pos, n_dist, n_rec, n_ml):
    parts = [hdr, body_fixed]
    if ML_N:
        _ml = _ml_pick(min(n_ml, ML_MAX_TOTAL))
        # n_ml==0 (사다리 마지막 단) = 1줄 포인터로 접는다. 활성 0건이면 아무것도 붙지 않는다
        #   ⇒ mode-local 이 없는 저장소에서는 렌더 결과가 커밋2 이전과 **바이트 동일**.
        parts.append(_blk('[mode-local 공리 %d/%d]' % (len(_ml), ML_N), _ml) if _ml else ML_PTR)
    parts.append(axis)
    b = _blk(H_POS, pos_lines[:n_pos])
    if b:
        parts.append(b)
    b = _blk(H_DIST, dist_lines[:n_dist])
    if b:
        parts.append(b)
    _r = rec_lines[:n_rec]
    b = _blk('[최근 교훈 %d]' % len(_r), _r)
    if b:
        parts.append(b)
    if dead_line:
        parts.append(dead_line)
    return (chr(10) * 2).join(p for p in parts if p)

MAX = 2000
# 감축 사다리 — 고정부(hdr/전역 공리/고정 축/프론티어/dead)는 어떤 단계에서도 손대지 않는다.
#   ①DIST 포기 → ②최근 교훈 3→2→1 → ③전략 5→3 → ④mode-local 5→3→1→0(1줄 포인터).
#   ★mode-local 을 **맨 마지막**에 깎는 이유: 마지막 구(舊) 감축단이 1,571자라 여유 429자로
#     5줄이 들어간다(실측 근거 §S4c-1). 그보다 먼저 깎으면 상한 5의 근거가 무너진다.
#   ★2026-09-03 연장: v10 고정부 증가로 (3,0,1,0) 이 ~2,045자가 돼 사다리가 소진됐다.
#     전략 줄을 3→2→1 로 더 깎는 단을 잇는다. 검사 계약상 최소 1줄(B1 STR·C1 L-code)은 남긴다.
_ladder = [(5, 3, 3, 5), (5, 0, 3, 5), (5, 0, 2, 5), (5, 0, 1, 5), (3, 0, 1, 5),
           (3, 0, 1, 3), (3, 0, 1, 1), (3, 0, 1, 0), (2, 0, 1, 0), (1, 0, 1, 0)]
ctx = ''
_rung = 0
_nml = 0
for _i, (_np, _nd, _nr, _nm) in enumerate(_ladder):
    ctx = _assemble(_np, _nd, _nr, _nm)
    _rung, _nml = _i, min(_nm, ML_MAX_TOTAL) if ML_N else 0
    if len(ctx) <= MAX:
        break
# ★하드 절단은 dead 줄을 **보존**한다 — 사다리가 다 소진돼도 조회 명령은 살아야 한다.
#   ★이 블록은 셸 -c 큰따옴표 안이다 — 주석에도 큰따옴표/달러/백틱 금지(넣으면 훅이 통째로 죽는다).
#   개수만 주고 조회 방법을 자르면 dead 505건은 행동으로 옮길 수 없는 숫자가 된다(E5).
if len(ctx) > MAX:
    _tail = ((chr(10) * 2) + dead_line) if dead_line else ''
    _head = ctx[:max(0, MAX - len(_tail))]
    _nl = _head.rfind(chr(10))
    if _nl > 0:
        _head = _head[:_nl].rstrip()          # 문장 중간 절단 금지 — 줄 경계로 물린다
    ctx = _head + _tail
ctx = ctx[:MAX]
ctx = ''.join(ch if not (0xD800 <= ord(ch) <= 0xDFFF) else '?' for ch in ctx)
# ── 계측(커밋1): 이 파일이 memory_knowledge_health.R HARD_10 의 **유일한 입력**이다.
#   조립기를 R 로 재구현하면 두 구현이 갈라지고, 갈라진 순간 계약이 실제 주입면을 안 잰다.
#   fail-soft — 계측 실패가 주입 자체를 막지 않는다.
try:
    import datetime as _dt
    _ml_rendered = len(_ml_pick(_nml)) if (ML_N and _nml) else 0
    _p = os.environ.get('IL', '')
    if _p:
        _d = os.path.dirname(_p)
        if _d and not os.path.isdir(_d):
            os.makedirs(_d, exist_ok=True)
        with open(_p, 'w', encoding='utf-8') as _fh:
            json.dump({'at': _dt.datetime.now().astimezone().isoformat(timespec='seconds'),
                       'len': len(ctx), 'max': MAX,
                       'ladder_rung': _rung, 'ladder_total': len(_ladder),
                       'ml_rendered': _ml_rendered, 'ml_active_total': ML_N,
                       'ml_max_total': ML_MAX_TOTAL, 'ml_max_per_mode': ML_MAX_PER_MODE,
                       'agent': os.environ.get('QVEST_INJECT_AGENT', ''),
                       'pc_status': pc_status,
                       'markers': {'positive': H_POS[:20] in ctx,
                                   'recent': '[최근 교훈' in ctx,
                                   'dead': 'dead configs' in ctx,
                                   'dist': H_DIST in ctx}},
                      _fh, ensure_ascii=False)
except Exception:
    pass
print(json.dumps(ctx))
")
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":$ESC}}"
exit 0
