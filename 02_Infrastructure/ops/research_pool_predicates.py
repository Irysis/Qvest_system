#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#==============================================================================
# research_pool_predicates.py — 페이퍼 적재 파이프라인 술어 정본(SOT)
#   승격 2026-08-02 (도훈 사전등록 조건 발효: "세 번째 소비자가 나타나면 공용 모듈 승격 재판정")
#
# 왜 이 파일이 있나:
#   같은 술어가 소비자마다 **독립 구현**돼 있었고, 그래서 같은 결함이 소비자 수만큼
#   독립으로 재발했다 — 2026-08-02 하루에 세 건, 전부 오류 없이 조용히 틀린 숫자:
#     · alpha_search_queue_run.sh   id 미정규화 + 키 드리프트 + OR 부활  (N 6→4→1)
#     · factor_deep_recheck_run.sh  같은 id 미정규화 — 큐 3/3 전량 이미 처리분(참값 0)
#     · paper_research_dispatch.R   mode_queue queue{} 중첩 미해석 — 14편 전량 드롭
#   소비자 측에서 세 번을 각각 고쳤고, 그 시점의 조건이 "세 번째 소비자가 나타나면
#   공용 모듈 승격 재판정"이었다. 부팅 리더(research_pool_status.py)가 정확히 그
#   세 번째 소비자이므로 여기로 승격한다.
#
# ★계약: 이 파일이 술어의 **유일 정의**다.
#   소비자는 import 하거나 CLI 로 호출한다. 술어를 소비자 쪽에 다시 적는 순간
#   이 파일의 존재 이유가 사라지고 위 3연발이 그대로 재발한다.
#   재분기 방지축 = 08_Tests/ops/test_alpha_queue_pending.py ·
#                   test_factor_recheck_pending.py 의 배선 단언(소비자가 이 모듈을 경유하는가).
#
# ★R 쌍둥이: paper_research_dispatch.R 은 R 이라 import 할 수 없어 `getrt` 를 유지한다.
#   대신 08_Tests/ops/test_mode_queue_dispatch_schema.R 이 **R↔Python 동치**를 매 실행
#   대조한다 — 무검사 포크가 아니라 검사된 쌍둥이다. 어느 한쪽만 고치면 그 검사가 깨진다.
#
# ★공통 기전(이 모듈이 방어하는 것): "필드명·모양 불일치가 예외 없이 조용한 빈 값이 된다."
#   빈 값은 '없음'과 겉보기가 같아서, 계측 사망이 정상값 0 으로 내려앉는다.
#
# CLI (소비자 .sh 가 쓰는 진입점):
#   research_pool_predicates.py alpha-pending  <stage_dir>
#       → 미소비 testable 후보 수를 stdout 에 1줄 출력
#   research_pool_predicates.py recheck-build  <stage_dir> <out_json> [<today>]
#       → uncertain 재검 큐를 out_json 에 쓰고 건수를 stdout 에 1줄 출력
#==============================================================================
import os
import re
import sys
# ── 논문 id 정규화 정본 (2026-08-22). 같은 대상에 수치가 셋이던 문제의 수리 —
#   좌초 154/62/61 · 재발견 27/10 이 전부 정규화 규약 차이였다.
#   ★폴백 유지: 정본을 못 불러와도 러너가 죽지 않는다(종전 동작).
try:
    from paper_id_norm import norm_id as _norm_paper_id
except Exception:  # pragma: no cover
    try:
        import os as _os, sys as _sys
        _sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
        from paper_id_norm import norm_id as _norm_paper_id
    except Exception:
        def _norm_paper_id(x):
            """폴백 — 정본 부재 시 최소 정규화(접두만).""" 
            import re as _re
            if not x:
                return ""
            return _re.sub(r"^(?:arxiv\s*:)", "", str(x).strip(), flags=_re.I)
import glob
import json

MODE_ROUTES = ("optimizer", "risk", "regime")

# ── id 표기 정규화 ────────────────────────────────────────────────────────────
#   생산자 계열마다 표기가 다르다 — 실측:
#     alpha_search_route_20260727.json  papers[].id   = "arxiv:2607.19497"
#     그 외 route(0619~0726) / 구 queue  .id/.arxiv_id = bare "2607.19497"
#     *_done.json                       processed[]    = bare
#   정규화 없이 문자열 비교하면 `pid not in done` 이 **항상 참** → 이미 소비·판정난 건이
#   영구 pending 으로 남는다(recheck 쪽은 표시가 아니라 실행 트리거라 매일 토큰을 태웠다).
#   ★curated 논문 id 는 arXiv 꼴이 아닌 파일명(MAN_AHL_*.pdf 등, 실측 15건)이므로
#     arXiv 꼴일 때만 접두/버전을 벗기고 그 외는 원형 보존한다.
_AXPFX = re.compile(r"^(?:https?://)?(?:www\.)?(?:arxiv\.org/(?:abs|pdf)/|arxiv[:/])", re.I)
_AXID = re.compile(r"^(\d{4}\.\d{4,5})(?:v\d+)?$")


def nid(v):
    """arXiv id 표기 정규화. arXiv 꼴이 아니면 원형 보존. None/공백 → ''."""
    s = str(v if v is not None else "").strip()
    if not s:
        return ""
    s = _AXPFX.sub("", s).strip()
    m = _AXID.match(s)
    if m:
        return m.group(1)
    # v9 2026-08-23: curated PDF id 는 원장 기록기(paper_id_norm.norm_id)가 확장자를 벗겨 적는다.
    #   여기서 `.pdf` 를 보존하면 done 집합과 영구히 안 만나 기록된 논문이 pending 으로 남는다
    #   (실측: ACADIAN/ROBECO 2편이 SKIP 기록 후에도 집계됨). 양쪽 규약을 같게 둔다.
    if s.lower().endswith(".pdf"):
        s = s[:-4]
    return s


# ── id 키 이름 드리프트 ───────────────────────────────────────────────────────
#   구판은 `id` → `arxiv_id` 만 봤는데 queue_20260726/20260727 의 candidates 는 키가
#   `paper_id` 다 → pid='' → 해당 후보 **전부 침묵 미계수**(정규화 결함과 반대 방향의
#   오계수라 총계가 그럴듯하게 상쇄됐다).
_IDKEYS = ("paper_id", "id", "arxiv_id")


def pid_of(o, src="", warn=True):
    """레코드에서 정규화된 논문 id 를 뽑는다. 키가 여러 개면 충돌을 stderr 로 알린다."""
    vals = {nid(o.get(k)) for k in _IDKEYS if o.get(k)}
    vals.discard("")
    if len(vals) > 1 and warn:
        # 같은 레코드가 서로 다른 id 를 이고 있으면 어느 쪽을 골라도 오계수다. 숨기지 않는다.
        sys.stderr.write("[predicates] id 키 충돌 %s: %s\n" % (src, sorted(vals)))
    for k in _IDKEYS:
        v = nid(o.get(k))
        if v:
            return v
    return ""


def is_testable(o):
    """alpha-search 대상 판정.

    verdict 위치 드리프트 관용 — queue_20260726 은 candidate **최상위** verdict 이고
    route/구 queue 는 factor_candidate.verdict 다. 한쪽만 보면 침묵 미계수.

    ★명시 부정 verdict 에 거부권: 구판은 `verdict=="testable" or (route=="alpha" and
      kr_feasible)` 였는데 OR 이라 라우터가 redundant/infeasible/uncertain 으로 **명시
      기각한 건**을 뒷 분기가 되살렸다(실측 4건, 그중 3건이 잔여 pending 에 올라 있었다).
      뒷 분기는 판정이 **아직 없을 때**의 폴백이지, 판정을 뒤집는 우회로가 아니다.
    """
    fc = o.get("factor_candidate") or {}
    v = str(fc.get("verdict") or o.get("verdict") or "").strip().lower()
    if v == "testable":
        return True
    if v:
        return False
    # route 동의어: "replication" = v10 트리아지(paper_router_v4)의 alpha 계승 라벨.
    # v4 는 kr_feasible 필드를 내지 않으므로(충실구현 관점 — 유니버스 치환만 평가)
    # replication 폴백은 route 단독으로 성립한다.
    route = str(o.get("route") or "").strip().lower()
    if route == "replication":
        return True
    return route == "alpha" and bool(o.get("kr_feasible"))


# 레코드 자신의 종결 표식 — done 원장 append 를 빠뜨린 런이 실재하므로 2차 방어로 둔다.
_TERMINAL = {"quarantine", "quarantined", "adopt", "adopted",
             "done", "processed", "skip", "skipped"}


def is_resolved(o):
    """레코드에 종결 표식(status/gate_decision)이 있으면 되살리지 않는다."""
    for k in ("status", "gate_decision"):
        if str(o.get(k) or "").strip().lower() in _TERMINAL:
            return True
    return False


def display_name(o):
    """후보 표시명 — 생산자 스키마 2세대(최상위 factor_name/factor_title, 구 fc.name) 관용.

    ★마지막 폴백은 `title` 이다: route papers 중 `factor_candidate: null` 인 건
      (= 라우터가 팩터를 못 뽑았지만 route=alpha ∧ kr_feasible 로 남긴 건)은 팩터명이
      아예 없어서, title 이 없으면 화면에 논문 id 만 뜬다 — 사람이 못 알아본다.
    """
    fc = o.get("factor_candidate") or {}
    return (o.get("factor_name") or o.get("factor_title")
            or fc.get("name") or fc.get("factor_name")
            or o.get("name") or o.get("title") or "")


def factor_hint(o):
    """후보의 '무엇을 팩터로 볼 것인가' 한 조각. 없으면 빈 문자열.

    생산자 계열마다 자리가 다르다 — arXiv 라우트는 `factor_candidate.factor_id`,
    pg2 큐는 `angle`(+`pg2_lever`) 이다. 한쪽만 보면 목록이 절반 비어 보인다.
    """
    fc = o.get("factor_candidate") or {}
    v = (fc.get("factor_id") or fc.get("id") or o.get("factor_id")
         or o.get("factor_name") or o.get("factor_title")
         or o.get("angle") or fc.get("name") or "")
    return " ".join(str(v).split())


class LedgerUnreadable(Exception):
    """소비 원장이 존재하는데 읽을 수 없다 = 계측 사망. 빈 값으로 내려앉히지 않는다."""


def _load_json(path):
    """부재/손상 모두 None. 손상 1건이 나머지 계수를 죽이지 않는다(fail-soft).

    ★fail-soft 가 옳은 곳은 **원천 파일**(route/queue)뿐이다 — 결과가 pending 을
      과소 계상하는 보수적 방향이기 때문이다. 감산항(done)에는 _load_ledger 를 쓸 것.
    ★인코딩은 `utf-8-sig` — BOM 을 쓰는 생산자 계열이 실재한다(pg2 큐). `utf-8-sig` 는
      BOM 없는 UTF-8 도 그대로 읽으므로 종전 동작의 상위집합이다.
    """
    try:
        with open(path, encoding="utf-8-sig") as fh:
            return json.load(fh)
    except Exception:
        return None


def _load_ledger(path):
    """소비 원장 전용 로더 — 부재는 None(정상: 아직 아무것도 소비 안 함),
    **존재하는데 파싱 실패면 예외**(계측 사망).

    실사고 2026-08-09: 원장 구조 손상(배열 조기 닫힘)을 fail-soft 가 삼켜
    done=∅ → pending 1→10 으로 부풀었다. 그대로면 차기 무인 런이 판정난 논문을 재처리한다.
    ★"모른다"를 "없다"로 읽으면 감산항에서는 **부호가 뒤집힌다**.
    """
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8-sig") as fh:
            return json.load(fh)
    except Exception as e:
        raise LedgerUnreadable("%s: %s" % (os.path.basename(path), e))


# ── alpha 큐 ──────────────────────────────────────────────────────────────────
def alpha_done_ids(stage):
    """소비 원장(alpha_search_queue_done.json)의 정규화 id 집합.

    processed[] 뿐 아니라 records[] 도 소비 사실이다 — processed append 를 빠뜨린
    런이 실재한다(원장 6건 중 일부가 그 자리였다).
    """
    done = set()
    d = _load_ledger(os.path.join(stage, "alpha_search_queue_done.json"))
    if isinstance(d, dict):
        done = {nid(x) for x in (d.get("processed") or []) if nid(x)}
        for r in (d.get("records") or []):
            if isinstance(r, dict):
                v = pid_of(r, "done.records")
                if v:
                    done.add(v)
    return done


# ── pg2 강화 큐(id 없는 계열) ─────────────────────────────────────────────────
#   `pg2_reinforcement_queue_*.json` 은 학술지·워킹페이퍼 혼합이라 **arXiv id 가 없다**
#   (43편 중 doi.org URL 1편, 나머지는 기관 PDF·페이월). 그래서 `pid_of()` 가 빈 문자열을
#   내고, 그 순간 이 큐 전체가 **조용히 0 편**으로 계수된다 — 이 모듈이 방어하는 바로 그
#   기전이다. 여기서는 id 를 **파생**해 쓴다(없는 id 를 지어내는 게 아니라 규약을 고정한다):
#     1. URL 안에 arXiv id 가 있으면 그것 (→ 기존 done 원장과 그대로 대조된다)
#     2. 없으면 DOI (`doi.org/…` 또는 본문 `doi:…`) → `doi:<소문자 doi>`
#     3. 둘 다 없으면 제목 정규화 → `title:<영숫자만·소문자>`
#   ★3번은 **제목 기준**이라 표기 변형에 약하다. paper_id_norm.py 서문이 경고한 그
#     약점이고, 여기서는 대안이 없으므로 규약을 명시해 두는 선까지만 한다.
_DOI_URL = re.compile(r"(?:doi\.org/|\bdoi\s*:\s*)(10\.\d{4,9}/[^\s\"'<>)\]]+)", re.I)
_ARXIV_IN_URL = re.compile(r"arxiv\.org/(?:abs|pdf)/(\d{4}\.\d{4,5})", re.I)
_TITLE_JUNK = re.compile(r"[^0-9a-z가-힣]+")


def _title_key(t):
    s = _TITLE_JUNK.sub("", str(t or "").strip().lower())
    return ("title:" + s) if s else ""


def pg2_key(o):
    """pg2 큐 레코드의 대조 키. 판별 불가면 빈 문자열(있는 척하지 않는다)."""
    url = str(o.get("url") or "")
    m = _ARXIV_IN_URL.search(url)
    if m:
        return nid(m.group(1))
    m = _DOI_URL.search(url) or _DOI_URL.search(str(o.get("source") or ""))
    if m:
        return "doi:" + m.group(1).rstrip(".,;").lower()
    return _title_key(o.get("title"))


def alpha_done_keys(stage):
    """done 원장을 **pg2 키 공간**으로도 투영한다.

    원장 레코드는 arXiv id 기준이라 `pg2_key` 가 내는 `doi:`/`title:` 키와 만나지
    않는다. 감산항이 만나지 못하면 이미 소비한 논문이 영구 pending 으로 남는다.
    """
    keys = set()
    d = _load_ledger(os.path.join(stage, "alpha_search_queue_done.json"))
    if isinstance(d, dict):
        for r in (d.get("records") or []):
            if not isinstance(r, dict):
                continue
            t = _title_key(r.get("paper_title") or r.get("title"))
            if t:
                keys.add(t)
            for fld in ("doi", "url", "paper_url", "source"):
                m = _DOI_URL.search(str(r.get(fld) or ""))
                if m:
                    keys.add("doi:" + m.group(1).rstrip(".,;").lower())
    return keys


def alpha_pending(stage):
    """미소비 testable 후보 = (큐 candidates ∪ route papers ∪ pg2 큐) − done − 종결표식.

    ★`_latest` 한 파일이 아니라 **전 파일**을 훑는다 — 진짜 미소비분은 과거 파일에
      남아 있고, 최신 파일만 보면 그 자리가 통째로 안 보인다(부팅 리더의 실결함).
    반환 = {pid: 최초 발견 레코드} (표시명 파생을 위해 레코드를 들고 있는다).
    """
    done = alpha_done_ids(stage)
    pend = {}

    def scan(objs, src):
        for o in objs:
            if not isinstance(o, dict):
                continue
            p = pid_of(o, src)
            if p and p not in done and is_testable(o) and not is_resolved(o):
                pend.setdefault(p, o)

    for f in sorted(glob.glob(os.path.join(stage, "alpha_search_queue_*.json"))):
        if f.endswith("_done.json"):
            continue
        d = _load_json(f)
        if isinstance(d, dict):
            scan(d.get("candidates") or [], os.path.basename(f))
    for f in sorted(glob.glob(os.path.join(stage, "alpha_search_route_*.json"))):
        r = _load_json(f)
        if isinstance(r, dict):
            scan(r.get("papers") or [], os.path.basename(f))

    # pg2 강화 큐 — id 없는 계열이라 키 파생 + 제목/DOI 대조를 따로 쓴다.
    pg2_files = sorted(glob.glob(os.path.join(stage, "pg2_reinforcement_queue_*.json")))
    if pg2_files:
        done_keys = alpha_done_keys(stage)
        for f in pg2_files:
            d = _load_json(f)
            if not isinstance(d, dict):
                continue
            for o in (d.get("papers") or []):
                if not isinstance(o, dict):
                    continue
                k = pg2_key(o)
                if not k or k in done or k in done_keys or k in pend:
                    continue
                if _title_key(o.get("title")) in done_keys:
                    continue
                if is_testable(o) and not is_resolved(o):
                    pend[k] = o
    return pend


# ── factor recheck(tier-2) 큐 ─────────────────────────────────────────────────
def recheck_done_ids(stage):
    """재검 완료 원장의 정규화 id 집합. processed[] 는 dict/bare-string 양쪽 관용."""
    done = set()
    d = _load_ledger(os.path.join(stage, "factor_recheck_done.json"))
    if isinstance(d, dict):
        for x in (d.get("processed") or []):
            pid = nid(x.get("paper_id") if isinstance(x, dict) else x)
            if pid:
                done.add(pid)
    return done


def recheck_uncertain(stage):
    """route 전 파일의 verdict=uncertain − done. {pid: item} (적재 순서 보존).

    ★큐에 적재하는 id 도 정규화형으로 쓴다 — 하류(프롬프트·done writer)가 접두를 그대로
      물려받아 원장과 또 어긋나는 것을 원천에서 끊는다.
    """
    done = recheck_done_ids(stage)
    seen = {}
    for f in sorted(glob.glob(os.path.join(stage, "alpha_search_route_*.json"))):
        r = _load_json(f)
        if not isinstance(r, dict):
            continue
        for p in (r.get("papers") or []):
            if not isinstance(p, dict):
                continue
            fc = p.get("factor_candidate") or {}
            if fc.get("verdict") != "uncertain":
                continue
            pid = nid(p.get("id") or p.get("arxiv_id") or p.get("paper_id"))
            if pid and pid not in done and pid not in seen:
                seen[pid] = {"paper_id": pid,
                             "title": p.get("title", ""),
                             "source": p.get("source", ""),
                             "factor_hint": fc.get("name") or fc.get("factor_hint", ""),
                             "prior_verdict": fc.get("verdict"),
                             "prior_reason": fc.get("reason") or fc.get("summary", "")}
    return seen


def recheck_residual(stage, queue_obj):
    """이미 물질화된 factor_recheck_queue_*.json 의 잔여 = items − done (정규화 비교).

    리더는 소비자가 재생성하기 전의 **큐 파일**을 읽으므로 이 축이 필요하다.
    (구판은 큐의 'arxiv:' 접두 id 를 done 의 bare id 와 raw 비교해 잔여를 부풀렸다.)
    """
    done = recheck_done_ids(stage)
    items = (queue_obj or {}).get("items") or [] if isinstance(queue_obj, dict) else []
    ids = set()
    for it in items:
        pid = nid(it.get("paper_id") if isinstance(it, dict) else it)
        if pid:
            ids.add(pid)
    return ids - done


# ── mode 큐 ───────────────────────────────────────────────────────────────────
# 생산자가 선언한 메타 키(라우트가 아닌 것). 미해석 키 판정에서 제외한다.
MODE_META_KEYS = ("date", "schema", "schema_version", "note", "dispatch_note",
                  "generated_by", "generated_at", "source", "router_version",
                  "queued_by", "skip", "skip_logged")


def mode_queue_routes(obj):
    """mode_queue 3라우트 해석 — 평면(정본) / queue{} 중첩 2형태 관용.

    실사고: mode_queue_20260727.json 이 3키를 최상위가 아니라 `queue`{} 안에 넣었는데
    소비자가 최상위만 봐서 0/0/0 으로 읽었다 → actions=[] = 14편(opt 7·risk 4·regime 3)
    전량 드롭. ★schema_version 으로는 분기 불가 — 07-27="mode_queue_v1" /
    08-02="paper_router_v2" 로 **생산자 이름**이 들어가 있어 형태를 구별하지 못한다.

    ★paper_research_dispatch.R::getrt 의 Python 쌍둥이. 길이 의미를 R 과 맞춘다
      (R: NULL→0 · 원소 리스트→n · 원자 스칼라→1 · named list→키 수).
      두 구현의 동치는 test_mode_queue_dispatch_schema.R 이 매 실행 대조한다.
    """
    q = obj.get("queue") if isinstance(obj, dict) else None
    out = {}
    for k in MODE_ROUTES:
        v = obj.get(k) if isinstance(obj, dict) else None
        if v is None and isinstance(q, dict):
            v = q.get(k)
        if v is None:
            out[k] = []
        elif isinstance(v, list):
            out[k] = v
        elif isinstance(v, dict):
            out[k] = list(v.values())      # R named list 의 length 와 맞춘다
        else:
            out[k] = [v]                   # R atomic scalar length = 1
    return out


def mode_queue_unresolved(obj):
    """3라우트가 전부 비었는데 미해석 키가 남아 있으면 그 키 목록을 돌려준다(없으면 []).

    "0편"과 "못 읽음"은 겉보기가 같다 — 이 축이 드롭의 유일한 지문이다.
    """
    if not isinstance(obj, dict):
        return []
    r = mode_queue_routes(obj)
    if sum(len(r[k]) for k in MODE_ROUTES) > 0:
        return []
    known = set(MODE_META_KEYS) | set(MODE_ROUTES)
    return [k for k in obj.keys() if k not in known]



# ── mode 큐 소비 (optimizer/risk/regime → method_registry) ────────────────────
#   신설 2026-08-21 (도훈 결정: opt/risk/regime 레인 무인 개시).
#   ★소비자 쪽에 다시 적지 말 것 — 이 모듈의 존재 이유가 08-02 3연발 재분기다.
#     소비자 = mode_queue_research_run.sh. 배선 단언 = 08_Tests/ops/test_mode_queue_pending.py.
#
#   실측 근거(2026-08-21): mode_queue 20파일 고유 93편 vs method_registry 16건,
#   전건 added 2026-08-08~09 → 그 뒤 12일 등재 0. 유입은 계속인데 소비가 멈춘 상태.

MODE_REGISTRY_REL = ("06_Registry", "method_registry.json")

# screen_priority = 라우터가 채우는 3축 중 서열축(실측 표기 3종).
#   ★문자열 비교로 정렬하지 않는다 — 코드포인트 순서면 "후순위"가 "⭐⭐"보다 앞선다.
_PRIO_RANK = {"⭐⭐⭐": 0, "⭐⭐": 1, "⭐": 2, "후순위": 4}
_PRIO_DEFAULT = 3          # 미표기는 ⭐와 후순위 사이 — 모르는 것을 버리지 않는다


def method_registry_ids(root):
    """등재 완료 논문 id 집합 — **감산항이므로 _load_ledger**.

    부재는 None(정상: 아직 아무것도 등재 안 함) → 빈 집합.
    존재하는데 파싱 실패면 예외. 여기서 빈 집합으로 내려앉히면 이미 등재·판정난
    논문을 무인 런이 재처리한다(alpha 쪽 2026-08-09 실사고와 같은 부호 뒤집힘).
    """
    obj = _load_ledger(os.path.join(root, *MODE_REGISTRY_REL))
    if obj is None:
        return set()
    out = set()
    for m in (obj.get("methods") or []):
        v = pid_of(m, "method_registry")
        if v:
            out.add(v)
    return out


def mode_queue_pending(stage, root):
    """미소비 mode_queue 항목 — 전 날짜 합집합에서 등재분을 뺀다.

    ★날짜별이 아니라 **합집합**인 이유: 같은 논문이 여러 날 큐에 재등장한다
      (실측 연인원 181 vs 고유 93). 날짜별로 세면 같은 건을 반복 처리한다.
    ★route 는 항목이 아니라 큐의 **레인 키**에 있다 — mode_queue_routes 로만 읽는다
      (queue{} 중첩 미해석이 08-02 에 14편을 통째로 드롭시킨 자리다).
    """
    done = method_registry_ids(root)          # 손상 시 LedgerUnreadable 전파
    seen = {}
    for fn in sorted(glob.glob(os.path.join(stage, "mode_queue_*.json"))):
        obj = _load_json(fn)                  # 원천은 fail-soft (보수 방향)
        if not isinstance(obj, dict):
            continue
        routes = mode_queue_routes(obj)
        for lane in MODE_ROUTES:
            for it in routes[lane]:
                if not isinstance(it, dict):
                    continue
                k = pid_of(it, "mode_queue:%s" % os.path.basename(fn))
                if not k or k in done or is_resolved(it):
                    continue
                if k not in seen:
                    seen[k] = {"paper_id": k, "lane": lane,
                               "title": it.get("title") or display_name(it),
                               "screen_priority": it.get("screen_priority") or "",
                               "shrinkage_builtin": it.get("shrinkage_builtin") or "",
                               "statistic_order": it.get("statistic_order") or "",
                               "reason": it.get("reason") or "",
                               "first_seen": os.path.basename(fn)}
    items = list(seen.values())
    items.sort(key=lambda r: (_PRIO_RANK.get(str(r["screen_priority"]).strip(),
                                             _PRIO_DEFAULT),
                              r["paper_id"]))
    return items


# ── alpha-research 레인 (2026-08-22 도훈 결정 "route=alpha 항목을 alpha-research 로") ──
#   ★이중 소비 방지가 이 함수의 핵심 계약이다.
#     기존 무인 alpha 레인(alpha_search_queue_run.sh)은 alpha_pending() = **is_testable** 인
#     것만 가져간다(라우터가 구체 팩터를 뽑아낸 건). 그러니 이 레인은 그 여집합만 가진다:
#     **route=alpha ∧ NOT is_testable** = 기전은 있는데 팩터가 아직 없는 논문 = QEPM 코어가
#     (alpha-hypothesis → alpha-research) 설계해야 하는 대상.
#   구성상 서로소이므로 두 레인이 같은 논문을 두 번 태우지 않는다.

def alpha_research_done_ids(stage):
    """alpha-research 레인 소비 원장 — **감산항이므로 _load_ledger**(손상 시 예외)."""
    d = _load_ledger(os.path.join(stage, "alpha_research_queue_done.json"))
    if not isinstance(d, dict):
        return set()
    done = {nid(x) for x in (d.get("processed") or []) if nid(x)}
    for r in (d.get("records") or []):
        if isinstance(r, dict):
            v = pid_of(r, "alpha_research_done.records")
            if v:
                done.add(v)
    return done


def alpha_research_pending(stage):
    """QEPM 코어(alpha-hypothesis→alpha-research)가 받을 논문.

    ★2026-08-22 자가 정정: 초판은 "alpha-search 여집합(= NOT is_testable)" 으로 잡았는데
      **품질 순서가 뒤집혔다**. `is_testable()` 의 폴백이 `route==alpha ∧ kr_feasible` 만으로도
      참이라, 여집합에는 **kr_feasible=False(라우터가 KR 불가로 본 것)** 와 **명시 기각 verdict**
      만 남는다 — 가장 안 유망한 것을 가장 비싼 에이전트에 보내는 배선이 된다.

    정정된 정의 = **route=alpha ∧ kr_feasible ∧ factor_candidate 부재**.
      = "KR 에서 될 것 같은데 아직 팩터가 없다" = 정확히 가설 설계가 필요한 것.
      팩터가 이미 있는 건(`factor_candidate.verdict=testable`)은 바로 백테할 수 있으므로
      경량 레인(alpha-search)이 맞다 — 그건 건드리지 않는다.

    ★중복 소비 해소 = **선점(first-claim-wins)**: 이 레인의 소비 기록을 alpha 레인과
      **같은 원장**(`alpha_search_queue_done.json`)에도 남기면 `alpha_pending()` 이 그것을
      감산하므로, alpha-search 가 같은 논문을 다시 태우지 않는다.
      (alpha-search 술어를 고치지 않는 이유: 도는 레인을 흔들지 않는다.)
    """
    done = alpha_research_done_ids(stage) | alpha_done_ids(stage)
    out = {}
    for f in sorted(glob.glob(os.path.join(stage, "alpha_search_route_*.json"))):
        r = _load_json(f)
        if not isinstance(r, dict):
            continue
        for o in (r.get("papers") or []):
            if not isinstance(o, dict) or o.get("route") != "alpha":
                continue
            if not o.get("kr_feasible"):
                continue                      # 라우터가 KR 불가로 본 건은 대상 아님
            fc = o.get("factor_candidate")
            if isinstance(fc, dict) and fc:
                continue                      # 팩터가 이미 있음 → 경량 레인(alpha-search)
            k = pid_of(o, os.path.basename(f))
            if not k or k in done or is_resolved(o):
                continue
            out.setdefault(k, {"paper_id": k, "lane": "alpha",
                               "title": o.get("title") or display_name(o),
                               "kr_feasible": True,
                               "screen_priority": o.get("screen_priority") or "",
                               "shrinkage_builtin": "", "statistic_order": "",
                               "reason": o.get("reason") or "",
                               "first_seen": os.path.basename(f)})
    return list(out.values())


# ── 등재→측정 칸 (2026-08-22 도훈 결정) ──────────────────────────────────────
#   실측 결함: method_registry 16건 중 measurement_status 기입은 **1건**뿐이었다.
#   큐→등재만 배선하면 어댑터만 쌓이고 원장이 다시 멈춘다 — 등재는 리서치의 끝이 아니다.
#   ★blocked_by_capability 는 대상에서 뺀다: 구현 자체가 막힌 건을 측정하라고 큐에 올리면
#     매 런 실패하며 토큰만 태운다(사유가 해소되면 verdict 가 바뀌고 자동 재편입된다).
_MEASURE_EXCLUDE_VERDICT = {"blocked_by_capability"}


def method_measure_pending(root):
    """실측이 남은 등재 method — measurement_status 가 비어 있는 건."""
    obj = _load_ledger(os.path.join(root, *MODE_REGISTRY_REL))
    if not isinstance(obj, dict):
        return []
    out = []
    for m in (obj.get("methods") or []):
        if not isinstance(m, dict):
            continue
        if str(m.get("verdict") or "").strip() in _MEASURE_EXCLUDE_VERDICT:
            continue
        ms = str(m.get("measurement_status") or "").strip()
        if ms:
            continue
        mid = str(m.get("method_id") or m.get("id") or "").strip()
        if not mid:
            continue
        out.append({"paper_id": pid_of(m, "method_registry") or mid,
                    "method_id": mid, "lane": "method_measure",
                    "title": m.get("paper_title") or mid,
                    "route": m.get("route"), "adapter_kind": m.get("adapter_kind"),
                    "entrypoint": m.get("entrypoint"),
                    "screen_priority": "", "shrinkage_builtin": "",
                    "statistic_order": "",
                    "reason": "어댑터는 등재됐으나 measurement_status 미기입 — 실측 미완",
                    "first_seen": "method_registry.json"})
    return out


# ── 어댑터 등재 백로그 레인 (2026-08-24 v9.2 S3-④) ──────────────────────────
#   실측 결함: 06_Registry/adapter_registration_queue.json 은 **생산자만 있고 소비자가 0** 이다.
#     생산자 = 02_Infrastructure/ops/mode_queue_axis_audit.py --emit-queue
#     소비자 = 없음. ranked 29 / meets_frontier 5 가 쌓인 채 아무도 안 읽는다.
#   ★큐를 만든 쪽의 판단이 옳았다 — "측정 arm 수는 큐 길이가 아니라 **등재 수**에 비례한다".
#     그런데 등재로 가는 순번이 없으면 그 판단이 실행되지 않는다. 이 레인이 그 칸이다.
#   정렬 = screen_priority 우선(⭐⭐⭐→⭐⭐→⭐→미표기→후순위) → first_date 오름차순(오래된 것 먼저).
#   ★unranked(축 미표기 47건)는 여기 넣지 않는다 — 정렬 불가를 0 으로 위장하지 않는다
#     (그쪽은 라우터가 축을 채운 뒤에 ranked 로 올라온다).
ADAPTER_QUEUE_REL = ("06_Registry", "adapter_registration_queue.json")


def adapter_backlog_pending(root, registered=None):
    """라우팅됐으나 method_registry 미등재인 어댑터 후보 — 등재 순번을 준다."""
    obj = _load_ledger(os.path.join(root, *ADAPTER_QUEUE_REL))
    if not isinstance(obj, dict):
        return []
    if registered is None:
        registered = method_registry_ids(root)
    out = []
    for r in (obj.get("ranked") or []):
        if not isinstance(r, dict):
            continue
        key = nid(r.get("paper_key") or r.get("paper_id") or "")
        if not key or key in registered:
            continue
        out.append({
            "paper_id": key,
            "lane": "adapter_backlog",
            "title": r.get("title") or key,
            "route": r.get("lane"),
            "adapter_kind": None,
            "screen_priority": str(r.get("screen_priority") or ""),
            "shrinkage_builtin": str(r.get("shrinkage_builtin") or ""),
            "statistic_order": str(r.get("statistic_order") or ""),
            "meets_frontier_criteria": bool(r.get("meets_frontier_criteria")),
            "first_date": str(r.get("first_date") or ""),
            "reason": "라우팅·2축 판정 완료 · method_registry 미등재 — new_adapter() → register_method() 대상",
            "first_seen": "adapter_registration_queue.json",
        })
    # 우선순위 → 오래된 것 먼저. 문자열 비교로 정렬하지 않는다(코드포인트 순서면 후순위가 앞선다).
    out.sort(key=lambda r: (_PRIO_RANK.get(r["screen_priority"].strip(), _PRIO_DEFAULT),
                            r["first_date"] or "99999999",
                            r["paper_id"]))
    return out


# ── QEPM 계속 레인 (2026-08-22 도훈 지시 "QEPM 모드 실행까지 이어지는 파이프라인") ──
#   실측 결함: 무인 러너 4종 어디에도 WT 생성/진행이 없고(전수 0건), 프롬프트 3종도
#   WorkTask 를 언급하지 않는다. 그래서 파이프라인이 **알파에서 끊긴다**.
#   ★그런데 재료는 이미 쌓여 있다 — alpha_package.json 보유 WT 220건 중
#     ALPHA_DONE 78 · FORGE_DONE 15 · OPTIMIZER_DONE 5 · RISK_DONE 5 = **판정 전 103건**,
#     JUDGE 도달은 12건뿐. dossier 워크플로(Risk→Optimizer→Forge→Judge)의 전제인
#     "alpha_package 가 WT mailbox 에 있을 것" 은 충족돼 있는데 **개시하는 것이 없었다.**
#   ⇒ 이 레인이 그 칸을 채운다. 자본(governor/book_state)은 여전히 사람 손이다.
#
# ★동결(도훈 결정 QEPM-R0-FREEZE · 2026-09-25): 이 레인(qepm_dossier)과 아래 paper_promotion 은 QEPM WT 체인 진입로다.
#   체인이 동결돼 next_agent 스폰(forge·judge 포함)·wt_create 는 하지 않는다(소비자 mode_queue_research_run.sh 도 v10 퇴역).
#   술어는 사료로 남기되 항목마다 frozen 표식을 붙여 소비자가 읽게 한다 — 자문·설계는 /advisor(결정 QEPM-ADVISOR-MODE),
#   측정은 도훈 승인 뒤 정본 계약(run_paper_replication)만. 해제 = 06_Registry/decision_register.json 재상정.
QEPM_FREEZE_MARK = "QEPM-R0-FREEZE"
QEPM_FREEZE_NOTE = ("QEPM WT 체인 동결 — next_agent 스폰·wt_create 금지(해제 = decision_register 재상정) · "
                    "자문·설계는 /advisor(QEPM-ADVISOR-MODE) · 측정은 도훈 승인 뒤 정본 계약 run_paper_replication 만")

WT_ROOT_REL = ("qepm", "mailbox", "worktask")

# 판정 전 = 다음 단계로 진행할 수 있는 상태. 종결/중단 표식은 제외한다.
_QEPM_ADVANCEABLE = {"ALPHA_DONE", "RISK_DONE", "OPTIMIZER_DONE", "FORGE_DONE"}
_QEPM_TERMINAL = {"TERMINATED", "ABORTED", "COMPLETED", "JUDGE_DONE", "JUDGE_FAILED",
                  "ALPHA_DONE_NEGATIVE", "SPEC_APPROVED"}
# ★SPEC_APPROVED 를 제외하는 이유: 스펙만 승인된 상태라 alpha_package 가 있어도
#   그 WT 는 아직 alpha 단계 소관이다(다음 단계 주체가 risk 가 아니다).

_QEPM_NEXT = {"ALPHA_DONE": "risk-research", "RISK_DONE": "optimizer-research",
              "OPTIMIZER_DONE": "forge", "FORGE_DONE": "judge"}

# ★phase 필드는 낡을 수 있다 — **산출물이 진실이다**.
#   실측 2026-08-22: WT-D20260424_006 은 phase=FORGE_DONE 인데 judge_verdict.json 이 이미 있다.
#   phase 만 믿으면 이미 판정난 WT 에 judge 를 또 붙인다(중복 소비·판정 오염).
#   ⇒ 각 단계의 **다음 산출물이 이미 있으면 그 WT 는 대상이 아니다**.
_QEPM_NEXT_ARTIFACT = {
    "ALPHA_DONE": ("risk_package.json",),
    "RISK_DONE": ("optimization_package.json", "optimizer_package.json"),
    "OPTIMIZER_DONE": ("forge_package.json", "backtest_result"),
    "FORGE_DONE": ("judge_verdict.json", "judge_package.json"),
}


def _qepm_next_done(wt_dir, phase):
    """다음 단계 산출물이 이미 있는가 (파일 또는 디렉터리)."""
    for nm in _QEPM_NEXT_ARTIFACT.get(phase, ()):
        if os.path.exists(os.path.join(wt_dir, nm)):
            return True
    return False


def qepm_dossier_pending(root, max_age_days=None):
    """판정 전 단계에서 멈춘 WT — 다음 에이전트를 붙이면 진행되는 것만.

    ★phase 키가 두 세대다: 신 `current_phase` · 구 `phase`. 한쪽만 보면 174건이
      '(없음)' 으로 떨어진다(2026-08-22 내 초판이 정확히 그렇게 오계수했다).
    """
    import datetime
    wt_root = os.path.join(root, *WT_ROOT_REL)
    if not os.path.isdir(wt_root):
        return []
    out = []
    for d in sorted(glob.glob(os.path.join(wt_root, "WT-*"))):
        has_pkg = os.path.exists(os.path.join(d, "alpha_package.json"))
        has_hyp = os.path.exists(os.path.join(d, "alpha_hypothesis.json"))
        st = _load_json(os.path.join(d, "status.json")) or {}
        ph = str(st.get("current_phase") or st.get("phase") or "").strip().upper()

        # ★(2026-08-22 수리) **중단된 승격**을 고아로 남기지 않는다.
        #   실사고: paper_promotion 이 wt_create → alpha-hypothesis 까지 하고 세션 한도로 끊기면
        #   그 WT 는 alpha_hypothesis.json 만 남는다. 그러면
        #     · qepm_dossier 는 alpha_package 를 요구해 제외
        #     · paper_promotion 은 "이미 WT 가 참조" 로 제외
        #   → **어느 레인에도 안 잡히는 고아**가 된다. 실측 3건(08-13 건은 9일 방치).
        #   세션 한도·타임아웃마다 재발할 구조이므로 여기서 흡수한다: 다음은 alpha-research.
        if has_hyp and not has_pkg:
            if ph in ("TERMINATED", "ABORTED", "COMPLETED"):
                continue
            upd0 = str(st.get("updated_at") or st.get("started_at") or "")[:10]
            out.append({"paper_id": os.path.basename(d), "wt_id": os.path.basename(d),
                        "lane": "qepm_dossier", "phase": ph or "HYPOTHESIS_ONLY",
                        "next_agent": "alpha-research",
                        "title": str(st.get("framing_anchor")
                                     or os.path.basename(d))[:90],
                        "updated_at": upd0,
                        "screen_priority": "", "shrinkage_builtin": "", "statistic_order": "",
                        "reason": "alpha_hypothesis 만 있고 alpha_package 부재 — 승격이 중간에 끊긴 WT",
                        "first_seen": "status.json",
                        "frozen": QEPM_FREEZE_MARK, "frozen_note": QEPM_FREEZE_NOTE})
            continue

        if not has_pkg:
            continue
        if ph in _QEPM_TERMINAL or ph not in _QEPM_ADVANCEABLE:
            continue
        if _qepm_next_done(d, ph):
            continue          # 다음 산출물이 이미 있다 = phase 가 낡은 것
        upd = str(st.get("updated_at") or st.get("started_at")
                   or st.get("alpha_draft_completed_at") or "")[:10]
        if not upd:
            # status.json 이 시각을 안 담는 세대 — 파일 mtime 으로 대체(정렬용, 판정용 아님)
            try:
                import datetime as _dt
                upd = _dt.date.fromtimestamp(os.path.getmtime(os.path.join(d, "status.json"))).isoformat()
            except Exception:
                upd = ""
        if max_age_days and upd:
            try:
                age = (datetime.date.today() - datetime.date.fromisoformat(upd)).days
                if age > max_age_days:
                    continue
            except Exception:
                pass
        out.append({"paper_id": os.path.basename(d), "wt_id": os.path.basename(d),
                    "lane": "qepm_dossier", "phase": ph,
                    "next_agent": _QEPM_NEXT.get(ph, "?"),
                    "title": str(st.get("framing_anchor") or st.get("alpha_verdict") or os.path.basename(d))[:90],
                    "updated_at": upd,
                    "screen_priority": "", "shrinkage_builtin": "", "statistic_order": "",
                    "reason": "alpha_package 보유·판정 전 — 다음 단계(%s) 미개시" % _QEPM_NEXT.get(ph, "?"),
                    "first_seen": "status.json",
                    "frozen": QEPM_FREEZE_MARK, "frozen_note": QEPM_FREEZE_NOTE})
    # 최근 것 우선 — 오래된 legacy 보다 살아있는 라운드를 먼저 잇는다
    out.sort(key=lambda r: (r.get("updated_at") or ""), reverse=True)
    return out


# ── 승격 게이트: 경량 레인 → QEPM (2026-08-22 도훈 "문제 없이 완성시켜줘") ────
#   실측 결함: 라우터가 screen_priority·verdict·grade 로 가치를 판정하는데 그 판정이
#   QEPM 으로 올라가는 코드가 **없었다** — 무인 러너 4종 wt_create 0건 ·
#   프롬프트 3종 WorkTask 언급 0건 · grade B 3건 승격 0건.
#
#   ★기준 = grade ∈ {A, B}. fr_eligible(99건)은 **국면배합(FR) 소비 자격**이지
#     "정식 라운드를 태울 값어치" 의 척도가 아니다 — 축이 다르다. 게다가 99건을
#     forge/judge 에 태우면 비용이 감당 범위를 넘는다(라운드당 수십 분).
#   ★승격은 등급 복사가 아니다: 경량은 sim_result.rds, QEPM 은 alpha_package.json 이라
#     wt_create → alpha-hypothesis → alpha-research 로 **다시 만들어야** 한다.
#     그래서 이 술어는 "대상 후보" 만 내고, 생성은 프롬프트가 한다.

MODULE_CATALOG_REL = ("06_Registry", "module_catalog.json")
_PROMOTE_GRADES = {"A", "B"}


def _wt_referenced_strategy_ids(root):
    """WT request.json 이 언급하는 strategy_id 집합 — 중복 승격 방지.

    ★파일 존재가 아니라 **참조**로 판정한다. WT 는 id 규칙이 달라(WT-D…) 전략 id 를
      경로로 역추적할 수 없다 — 이름 매칭이 유일한 연결이다
      ([[feedback-pinning-field-names-breaks-on-extension]] 의 반대 사례).
    """
    out = set()
    wt_root = os.path.join(root, *WT_ROOT_REL)
    for d in glob.glob(os.path.join(wt_root, "WT-*")):
        rq = os.path.join(d, "request.json")
        if not os.path.exists(rq):
            continue
        try:
            with open(rq, encoding="utf-8", errors="replace") as fh:
                blob = fh.read()
        except Exception:
            continue
        for m in re.finditer(r"STR_[A-Za-z0-9_]+", blob):
            out.add(m.group(0))
    return out


def promotion_pending(root, grades=None):
    """QEPM 승격 대상 — grade 통과 · 오염 없음 · 아직 WT 미생성."""
    want = set(grades or _PROMOTE_GRADES)
    obj = _load_ledger(os.path.join(root, *MODULE_CATALOG_REL))
    if not isinstance(obj, dict):
        return []
    mods = obj.get("modules")
    mods = list(mods.values()) if isinstance(mods, dict) else (mods or [])
    already = _wt_referenced_strategy_ids(root)
    out = []
    for m in mods:
        if not isinstance(m, dict):
            continue
        sid = str(m.get("strategy_id") or "")
        if not sid or str(m.get("grade") or "").strip().upper() not in want:
            continue
        # ★오염 라벨이 붙은 건 승격 금지 — 등급 자체를 신뢰할 수 없다.
        if m.get("grade_contaminated") or m.get("label_contaminated") or m.get("contamination"):
            continue
        if sid in already:
            continue          # 이미 WT 가 이 전략을 참조 = 승격 완료/진행 중
        meta = m.get("meta") or {}
        out.append({"paper_id": sid, "strategy_id": sid, "lane": "paper_promotion",
                    "grade": m.get("grade"),
                    "title": str(meta.get("strategy_idea") or sid)[:120],
                    "sim_result_path": m.get("sim_result_path"),
                    "bt_result_path": m.get("bt_result_path"),
                    "registered_at": str(m.get("registered_at") or "")[:10],
                    "fr_eligible": m.get("fr_eligible"),
                    "screen_priority": "", "shrinkage_builtin": "", "statistic_order": "",
                    "reason": "grade %s · 경량 검증 통과했으나 QEPM WT 미생성" % m.get("grade"),
                    "first_seen": "module_catalog.json",
                    "frozen": QEPM_FREEZE_MARK, "frozen_note": QEPM_FREEZE_NOTE})
    out.sort(key=lambda r: (r.get("grade") or "Z", r.get("registered_at") or ""), reverse=False)
    return out


def research_queue_pending(stage, root, lanes=None):
    """무인 배분 대상 전체 = mode_queue(opt/risk/regime) + alpha-research + 측정 백로그.

    ★lane 은 소비자(프롬프트)가 어느 에이전트를 스폰할지 고르는 유일 키다.
    """
    items = (mode_queue_pending(stage, root)
             + alpha_research_pending(stage)
             + method_measure_pending(root)
             + adapter_backlog_pending(root)
             + qepm_dossier_pending(root, max_age_days=90)
             + promotion_pending(root))
    # lanes: 특정 레인만 뽑는 **표적 소비**. 정렬상 앞 레인이 상한을 다 먹어 뒤 레인이
    #   영영 안 도는 문제를 푼다(2026-08-22 실측: method_measure 12건이 risk/opt/regime 을 막음).
    #   ★필터는 선택이지 기본이 아니다 — 기본 경로의 정렬 계약(측정 백로그 우선)은 그대로 둔다.
    if lanes:
        _want = set(lanes)
        items = [x for x in items if x.get("lane") in _want]
    # 측정 백로그를 먼저 — 이미 등재된 것을 끝내는 편이 새로 쌓는 것보다 값이 크다
    # (등재만 쌓여 원장이 12일 멈춘 것이 이 배선의 발단이다).
    # ★qepm_dossier 가 1순위 — 이미 알파까지 간 라운드를 판정까지 잇는 편이
    #   새 논문을 또 쌓는 것보다 값이 크다(판정 전 103건 vs 판정 도달 12건).
    # paper_promotion 이 qepm_dossier 다음 — 이미 알파까지 간 것을 판정까지 잇는 게 먼저고,
    #   그 다음이 "검증 통과했는데 정식 라운드를 못 받은 것" 을 올리는 일이다.
    # adapter_backlog 은 method_measure 바로 뒤 — "이미 등재된 것을 끝내는 편이 먼저"라는
    #   같은 논리의 다음 칸이다(등재 → 측정 순서를 뒤집지 않는다). 기존 서열을 흔들지 않으려
    #   정수 사이 값을 쓴다. 실제 소비는 대개 `--lane adapter_backlog` 표적 호출이다.
    _LANE_ORDER = {"qepm_dossier": 0, "paper_promotion": 1, "method_measure": 2,
                   "adapter_backlog": 2.5,
                   "alpha": 3, "optimizer": 4, "risk": 4, "regime": 5}

    def _rank(r):
        lane = r.get("lane")
        # ★qepm_dossier 안에서는 **최신 우선**이다. 기본 정렬(paper_id 오름차순)을 그대로 쓰면
        #   4월 legacy 가 선두를 먹고 방금 끊긴 라운드가 뒤로 밀린다 — 이어붙이기의 취지에 반한다.
        #   중단된 승격(HYPOTHESIS_ONLY/SPEC_APPROVED)은 그중에서도 최우선: 방금 만든 WT 를
        #   미완으로 두면 다음 런이 또 새 WT 를 만들어 고아가 늘어난다.
        if lane == "qepm_dossier":
            stalled = 0 if str(r.get("phase", "")).upper() in ("SPEC_APPROVED", "HYPOTHESIS_ONLY") else 1
            # updated_at 내림차순 = 문자열 역순 키
            inv = "".join(chr(255 - ord(c)) if ord(c) < 255 else c
                          for c in str(r.get("updated_at") or ""))
            return (_LANE_ORDER[lane], stalled, inv, str(r.get("paper_id")))
        return (_LANE_ORDER.get(lane, 9),
                _PRIO_RANK.get(str(r.get("screen_priority", "")).strip(), _PRIO_DEFAULT),
                "", str(r.get("paper_id")))

    items.sort(key=_rank)
    return items


# ── CLI ───────────────────────────────────────────────────────────────────────
_USAGE = ("usage: research_pool_predicates.py alpha-pending <stage_dir>\n"
          "       research_pool_predicates.py recheck-build <stage_dir> <out_json> [<today>]\n"
          "       research_pool_predicates.py mode-routes   <mode_queue_json>\n"
          "       research_pool_predicates.py mode-queue-pending <stage_dir> <root> [--json <out>]\n"
          "       research_pool_predicates.py research-queue-pending <stage_dir> <root> [--lane a,b] [--json <out>]\n")


def main(argv):
    if not argv:
        sys.stderr.write(_USAGE)
        return 2
    cmd = argv[0]
    if cmd == "alpha-pending":
        if len(argv) < 2:
            sys.stderr.write(_USAGE)
            return 2
        # ★원장 손상은 숫자를 내지 않는다 — 소비자(.sh)의 sched_assert_count 가
        #   비숫자를 잡아 count_measurement_failed 경보 후 중단한다.
        #   여기서 0 이나 과대값을 내면 그 방어선이 통째로 무력해진다.
        # ★`--list N` 은 **추가 출력**이다. 기본 출력(정수 1줄)은 불변 — 소비자 .sh 가
        #   그 한 줄을 그대로 파싱한다(형식을 바꾸면 러너가 조용히 죽는다).
        n_list = 0
        if "--list" in argv:
            i = argv.index("--list")
            if i + 1 >= len(argv):
                sys.stderr.write("--list 에 개수가 없습니다\n")
                return 2
            try:
                n_list = int(argv[i + 1])
            except ValueError:
                sys.stderr.write("--list 인자는 정수여야 합니다: %s\n" % argv[i + 1])
                return 2
        try:
            pend = alpha_pending(argv[1])
        except LedgerUnreadable as e:
            sys.stderr.write("LEDGER_UNREADABLE %s\n" % e)
            return 3
        print(len(pend))
        if n_list > 0:
            for pid, o in list(pend.items())[:n_list]:
                title = " ".join(str(display_name(o) or o.get("title") or "").split())
                print("%s | %s | %s" % (pid, title[:40], factor_hint(o)))
        return 0
    if cmd == "recheck-build":
        if len(argv) < 3:
            sys.stderr.write(_USAGE)
            return 2
        stage, out = argv[1], argv[2]
        today = argv[3] if len(argv) > 3 else None
        try:
            items = list(recheck_uncertain(stage).values())
        except LedgerUnreadable as e:
            sys.stderr.write("LEDGER_UNREADABLE %s\n" % e)
            return 3
        with open(out, "w", encoding="utf-8") as fh:
            json.dump({"date": today, "n": len(items), "items": items},
                      fh, ensure_ascii=False, indent=2)
        print(len(items))
        return 0
    if cmd == "mode-routes":
        # R 쌍둥이(paper_research_dispatch.R::getrt)와의 동치 대조용 진입점.
        #   같은 JSON 바이트를 양쪽에 먹여 라우트 길이가 일치하는지 검사가 매 실행 확인한다.
        if len(argv) < 2:
            sys.stderr.write(_USAGE)
            return 2
        obj = _load_json(argv[1])
        if obj is None:
            sys.stderr.write("parse fail: %s\n" % argv[1])
            return 2
        r = mode_queue_routes(obj)
        print(json.dumps({k: len(r[k]) for k in MODE_ROUTES},
                         ensure_ascii=False, sort_keys=True))
        return 0
    if cmd == "research-queue-pending":
        # 무인 배분 정본 진입점 (alpha-research + opt/risk/regime + 측정 백로그).
        if len(argv) < 3:
            sys.stderr.write(_USAGE)
            return 2
        _lanes = None
        if "--lane" in argv:
            _lanes = [x for x in argv[argv.index("--lane") + 1].split(",") if x]
        try:
            items = research_queue_pending(argv[1], argv[2], lanes=_lanes)
        except LedgerUnreadable as e:
            sys.stderr.write("LEDGER_UNREADABLE %s\n" % e)
            return 3
        if "--json" in argv:
            with open(argv[argv.index("--json") + 1], "w", encoding="utf-8") as fh:
                json.dump({"n": len(items), "items": items}, fh,
                          ensure_ascii=False, indent=2)
        print(len(items))
        return 0
    if cmd == "mode-queue-pending":
        # ★원장 손상은 숫자를 내지 않는다 — 소비자(.sh)가 비숫자를 잡아 경보 후 중단한다.
        #   여기서 0 을 내면 "대기 없음" 정상 skip 으로 위장된다(alpha 쪽 실사고 동형).
        if len(argv) < 3:
            sys.stderr.write(_USAGE)
            return 2
        try:
            items = mode_queue_pending(argv[1], argv[2])
        except LedgerUnreadable as e:
            sys.stderr.write("LEDGER_UNREADABLE %s\n" % e)
            return 3
        if "--json" in argv:
            with open(argv[argv.index("--json") + 1], "w", encoding="utf-8") as fh:
                json.dump({"n": len(items), "items": items}, fh,
                          ensure_ascii=False, indent=2)
        print(len(items))
        return 0
    sys.stderr.write("unknown command: %s\n%s" % (cmd, _USAGE))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
