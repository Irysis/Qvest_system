#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
continuity_gate.py — 포기 원천차단 게이트의 판정기 (Continuity Firewall 두뇌)

도훈 mandate 2026-07-15: "자체적으로 포기하지 않는 자가발전형 아키텍처. 누적 실패 후
'끝남 표현들'로 라운드를 마무리하려는 것을 원천차단." 4차 메모리 강화 + warn-only 가드로도
재발 → 원천차단 = block(차단) + 독립 semantic 판정 + 자가발전 + 건설적 강제.

핵심 전환: '끝남 단어 금지'(어휘 발명에 매번 짐)가 아니라 '계속 산출물 요구'.
  게이트는 (1) research_context에서 (2) 종결/대기 프레이밍이 감지되면
  (3) required_closure_contract(next_probe≥2 + 소비면/frontier + negative면 live_trigger)
  충족을 요구하고, 미충족이면 그 턴을 block(강제 속행)한다.
  → 계약을 충족한 정당한 라운드 수렴(config-scoped negative + frontier)은 통과.
    계속을 생산하지 않는 bald 종료만 차단. (INV-7·AX-000 정합: 판정 자체는 막지 않음)

자가발전(§0.1 원리 3·4·5): 새 우회어는 코드가 아니라 06_Registry/continuity_cases.json에
  case/term 추가로 학습(append_case). 결정론 backstop은 그 term을 소비 → 잡을수록 강해짐.
  선택적 semantic 단계(Haiku)는 QVEST_CONTINUITY_LLM=1일 때 detection recall만 넓힘(계약이
  객관 게이트라 LLM이 통과를 강제로 clear하지 못함 — 편향 당사자 self-certify 차단).

배선: research_continuity_guard.sh(Stop hook)가 `--transcript`로 호출. 반환 = 훅 JSON.
안전: 어떤 오류든 통과('{}'). 무한루프 = per-turn cap(기본 3) + ERR trap.
"""
import json
import os
import re
import sys
import time
import glob
import hashlib

# ──────────────────────────────────────────────────────────────────────────
# 경로/로딩
# ──────────────────────────────────────────────────────────────────────────
def project_root():
    for k in ("CLAUDE_PROJECT_DIR", "QM_ROOT"):
        v = os.environ.get(k)
        if v and os.path.isdir(v):
            return v
    for c in ("C:/Users/99922/OneDrive/Quant_Module_Moltbot",
              "/c/Users/99922/OneDrive/Quant_Module_Moltbot",
              "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot"):
        if os.path.isdir(c):
            return c
    return os.getcwd()


def load_cases(root):
    p = os.path.join(root, "06_Registry", "continuity_cases.json")
    with open(p, encoding="utf-8") as f:
        return json.load(f)


# ──────────────────────────────────────────────────────────────────────────
# transcript → 현재 턴(마지막 user prompt 이후 assistant 텍스트 + tool_use)
# ──────────────────────────────────────────────────────────────────────────
def _is_user_prompt(m):
    if m.get("type") != "user":
        return False
    c = m.get("message", {}).get("content")
    if isinstance(c, str):
        return True
    if isinstance(c, list):
        return any(isinstance(b, dict) and b.get("type") == "text" for b in c)
    return False


def extract_current_turn(tp):
    lines = []
    with open(tp, "r", encoding="utf-8", errors="replace") as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                lines.append(json.loads(ln))
            except Exception:
                pass
    start = 0
    for i, m in enumerate(lines):
        if _is_user_prompt(m):
            start = i
    user_ts = None
    try:
        user_ts = lines[start].get("timestamp")
    except Exception:
        user_ts = None
    user_text = ""
    try:
        c = lines[start].get("message", {}).get("content")
        if isinstance(c, str):
            user_text = c
        elif isinstance(c, list):
            user_text = " ".join(b.get("text", "") for b in c
                                 if isinstance(b, dict) and b.get("type") == "text")
    except Exception:
        pass
    atext, tool_inputs = [], []
    for m in lines[start:]:
        if m.get("type") == "assistant":
            c = m.get("message", {}).get("content", [])
            if isinstance(c, list):
                for b in c:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "text":
                        atext.append(b.get("text", ""))
                    elif b.get("type") == "tool_use":
                        try:
                            tool_inputs.append(json.dumps(b.get("input", {}), ensure_ascii=False))
                        except Exception:
                            pass
    return {
        "text": "\n".join(atext),
        "tool_inputs": "\n".join(tool_inputs),
        "user_ts": user_ts,
        "user_text": user_text,
    }


# ──────────────────────────────────────────────────────────────────────────
# 판정 구성요소
# ──────────────────────────────────────────────────────────────────────────
def _tail(text, frac=0.4, floor=600):
    n = len(text)
    k = max(floor, int(n * frac))
    return text[-k:] if n > k else text


def research_context(text, cases):
    terms = cases.get("research_context_terms", [])
    hit = [t for t in terms if t and t in text]
    distinct = len(set(hit))
    # 종결/대기 lexeme이 있으면 research term 1개로도 문맥 성립(터스한 종료 커버)
    lex_present = _any_category_lexeme(text, cases)
    return distinct >= 2 or (distinct >= 1 and lex_present)


def _any_category_lexeme(text, cases):
    for cat in cases.get("categories", []):
        for term in cat.get("backstop_terms", []):
            if term and term in text:
                return True
    return False


# negative/종결-특정 토큰 — 마감 영역에 있으면 '실패-판정 stance'로 본다(신어에도 일반화,
# 조사-강건: 어간 substring이라 "미달로/미달입니다" 등 커버). 중립 확인어("확정/완료")는 제외 —
# progress 보고 오차단 방지. 실제 게이트는 detection이 아니라 계약(next_probe≥2)이다.
_NEG_TOKENS = [
    "negative", "screen-tier", "screen_tier", "미달", "기각", "전멸", "전량 부정",
    "졸업 불가", "졸업급 아님", "graduation=FALSE", "HARD FAIL", " FAIL", "REJECT",
    "dead-end", "dead end", "막다른", "소진", "무의미", "기여 부재", "signal-dead",
    "null 확정", "재시도 가치", "재도전 가치", "남은 경로", "볼 것이 없", "짜낼 것이 없",
]


def detect_closure(text, cases):
    tail = _tail(text)
    matched_cats, matched_terms = [], []
    has_waiting = False
    for cat in cases.get("categories", []):
        cid = cat.get("id")
        for term in cat.get("backstop_terms", []):
            if term and term in text:
                matched_cats.append(cid)
                matched_terms.append(term)
                if cid == "waiting_posture_close" and term in _tail(text, 0.18, 260):
                    has_waiting = True
    has_finality = any(c != "waiting_posture_close" for c in matched_cats)
    # verdict-close(신어 일반화): 마감 영역에 negative/종결-특정 토큰
    verdict_hit = [t for t in _NEG_TOKENS if t in tail]
    verdict_close = bool(verdict_hit)
    detected = has_finality or has_waiting or verdict_close
    return {
        "detected": detected,
        "categories": sorted(set(matched_cats)),
        "matched_terms": sorted(set(matched_terms)),
        "has_waiting": has_waiting,
        "has_finality": has_finality,
        "verdict_close": verdict_close,
        "verdict_tokens": verdict_hit,
    }


def _count_next_probes(text):
    enumr = len(re.findall(r"[①②③④⑤⑥]", text))
    numbered = len(re.findall(r"(?:(?<=\s)|^)(?:P[1-5]\b|\([1-5]\)|[1-5]\))", text))
    kw = len(re.findall(r"next_probe|다음\s*(?:가설|프로브|스텝|사이클|라운드)", text, re.I))
    # ≥2 probe의 보수 판정
    ok = (enumr >= 2) or (numbered >= 2) or (kw >= 2) or (enumr >= 1 and kw >= 1) \
        or (numbered >= 1 and kw >= 1)
    return {"enum": enumr, "numbered": numbered, "kw": kw, "ok": ok}


def _has_any(text, markers):
    return any(m and m in text for m in markers)


def marker_fresh(root, user_ts):
    """close_round()가 이번 턴에 쓴 마커의 신선도. user_ts 이후 mtime이면 fresh."""
    p = os.path.join(root, ".cache", "last_round_closure.json")
    if not os.path.exists(p):
        return False, None
    try:
        mt = os.path.getmtime(p)
    except Exception:
        return False, None
    ref = None
    if user_ts:
        try:
            # ISO8601 → epoch (Z 처리)
            ts = user_ts.replace("Z", "+00:00")
            import datetime
            ref = datetime.datetime.fromisoformat(ts).timestamp()
        except Exception:
            ref = None
    if ref is not None:
        fresh = mt >= (ref - 2)  # user 프롬프트 이후 작성 = 이번 턴
    else:
        fresh = (time.time() - mt) <= 1800  # 폴백: 30분 창
    rid = None
    try:
        with open(p, encoding="utf-8") as f:
            rid = json.load(f).get("round_id")
    except Exception:
        pass
    return fresh, rid


def check_contract(text, cases, root, user_ts, marker_override=None):
    probes = _count_next_probes(text)
    routing_ok = _has_any(text, cases.get("routing_markers", []))
    live_ok = _has_any(text, cases.get("live_trigger_markers", []))
    is_negative = any(t in text for t in
                      ["negative", "config-scoped", "screen-tier", "screen_tier",
                       "미달", "기각", "FAIL", "졸업 불가", "graduation=FALSE"])
    if marker_override is None:
        mk_fresh, mk_rid = marker_fresh(root, user_ts)
    else:
        mk_fresh, mk_rid = bool(marker_override), "override"
    # ★정밀도 원칙: bald 포기 vs 정당 종료를 가르는 최고신호 = next_probe≥2 (+negative면 live_trigger).
    #   소비면 라우팅(연속성 4호)은 하드 차단 조건이 아니라 soft 권고 — 라우팅 어휘 편차로 정당한
    #   종료를 오차단(false positive)하지 않기 위함. 4호의 하드 강제는 close_round()의 인자 계약이 담당.
    inline_ok = probes["ok"] and (live_ok if is_negative else True)
    satisfied = mk_fresh or inline_ok
    missing = []       # 하드 차단 사유(이게 있어야 통과)
    recommend = []     # soft 권고(차단 사유 아님)
    if not satisfied:
        if not probes["ok"]:
            missing.append("next_probe ≥2 (기전 진단에서 다음 가설 2개 이상 도출 — 연속성 3호)")
        if is_negative and not live_ok:
            missing.append("부활 조건(live_trigger) — negative는 영구 판결 아님, 경로-scoped 재도전 신호 필수 (INV-7)")
    if not routing_ok:
        recommend.append("소비면 라우팅/frontier 등재 권고 (팩터랭킹/유니버스/오버레이/위험/monitoring/선별라벨/타모드 또는 FQ 큐 — 연속성 4호. close_round()의 consumer_surfaces 인자로 강제됨)")
    return {
        "satisfied": satisfied,
        "marker_fresh": mk_fresh,
        "marker_round_id": mk_rid,
        "probes": probes,
        "routing_ok": routing_ok,
        "live_ok": live_ok,
        "is_negative": is_negative,
        "missing": missing,
        "recommend": recommend,
    }


# ──────────────────────────────────────────────────────────────────────────
# 선택적 semantic(LLM) 단계 — detection recall만 넓힘. 기본 OFF. 실패 시 graceful None.
# ──────────────────────────────────────────────────────────────────────────
def llm_verdict(text, cases, timeout=6.0):
    if os.environ.get("QVEST_CONTINUITY_LLM", "") != "1":
        return None
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not key:
        return None
    try:
        import urllib.request
        cat_lines = "\n".join(
            f"- {c['id']}: {c.get('description','')}" for c in cases.get("categories", [])
        )
        seg = _tail(text, 0.5, 1200)
        sys_p = (
            "너는 Qvest 리서치 로그 감사관이다. 주어진 assistant 턴 마감 텍스트가 "
            "'누적 실패 후 리서치 라운드를 끝냄으로 마무리하려는 종결 프레이밍'인지 판정하라. "
            "종결 프레이밍 범주:\n" + cat_lines + "\n"
            "단, config-scoped negative + 프론티어/next_probe/부활조건을 담은 정당한 수렴은 '아니오'다. "
            'JSON만 출력: {"is_giving_up_closure": bool, "category": str, "offending_span": str}'
        )
        body = json.dumps({
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 200,
            "system": sys_p,
            "messages": [{"role": "user", "content": seg}],
        }).encode("utf-8")
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages", data=body,
            headers={"content-type": "application/json",
                     "x-api-key": key,
                     "anthropic-version": "2023-06-01"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            resp = json.loads(r.read().decode("utf-8"))
        txt = "".join(b.get("text", "") for b in resp.get("content", [])
                      if b.get("type") == "text")
        mt = re.search(r"\{.*\}", txt, re.S)
        if mt:
            return json.loads(mt.group(0))
    except Exception:
        return None
    return None


# ──────────────────────────────────────────────────────────────────────────
# 종합 판정
# ──────────────────────────────────────────────────────────────────────────
def _reframe_hint(cases, categories):
    rmap = cases.get("reframe_map", [])
    hints = []
    picks = rmap[:2] if not categories else rmap
    for r in picks[:3]:
        hints.append(f"  · {r.get('from')} → {r.get('to')}")
    return "\n".join(hints)


def judge_text(text, tool_inputs, cases, root, user_ts=None, marker_override=None,
               use_llm=False):
    diag = {"research_context": False, "detected": False}
    if not text or not text.strip():
        return {"block": False, "diag": diag}
    if not research_context(text, cases):
        return {"block": False, "diag": diag}
    diag["research_context"] = True
    cl = detect_closure(text, cases)
    # 선택적 LLM: detection만 확장(계약 게이트는 불변)
    llm = llm_verdict(text, cases) if use_llm else None
    llm_flag = bool(llm and llm.get("is_giving_up_closure"))
    detected = cl["detected"] or llm_flag
    diag.update({"detected": detected, "closure": cl, "llm": llm})
    if not detected:
        return {"block": False, "diag": diag}
    ct = check_contract(text, cases, root, user_ts, marker_override)
    diag["contract"] = ct
    if ct["satisfied"]:
        return {"block": False, "diag": diag}
    # BLOCK — 계속 산출물 결측
    cats = ", ".join(cl["categories"]) or ("llm:" + str(llm.get("category")) if llm else "verdict_close")
    rec = ct.get("recommend", [])
    reason = (
        "[continuity_gate] 누적 실패 후 '끝남' 프레이밍으로 라운드를 마감하려 하는데 계속-산출물이 없습니다 "
        f"(감지 범주: {cats}). 이 턴은 아직 종료할 수 없습니다 — 다음을 반드시 채우세요:\n"
        + "\n".join(f"  ✗ {m}" for m in ct["missing"])
        + ("".join(f"\n  · (권고) {m}" for m in rec) if rec else "")
        + "\n\n원천차단 원칙: 종결 단어를 지우는 것으로는 통과하지 못합니다. 계속을 *생산*해야 합니다.\n"
        "가장 깔끔한 경로 = close_round() 호출(next_probe≥2·소비면·frontier·부활조건을 인자로 강제 → 마커 발행 → 이 게이트 자동 통과).\n"
        "  Rscript -e 'source(\"02_Infrastructure/contracts/close_round.R\"); close_round(round_id=..., verdict_type=..., mechanism_diagnosis=..., next_probes=c(...,...), consumer_surfaces=c(...), frontier_update=..., live_trigger=...)'\n"
        "또는 인라인으로 위 결측 항목을 서술로 채우세요. 재프레이밍 템플릿:\n"
        + _reframe_hint(cases, cl["categories"])
    )
    return {"block": True, "reason": reason, "diag": diag}


# ──────────────────────────────────────────────────────────────────────────
# per-turn 무한루프 cap (user_ts 키. block 시 증가, cap 초과 시 pass)
# ──────────────────────────────────────────────────────────────────────────
def _cap_key(user_ts, user_text):
    base = (user_ts or "") + "|" + (user_text or "")[:200]
    return hashlib.sha1(base.encode("utf-8", "replace")).hexdigest()[:16]


def _cap_bump(root, key):
    d = os.path.join(root, ".cache", "continuity_gate_counters")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, key + ".txt")
    n = 0
    try:
        with open(p, encoding="utf-8") as f:
            n = int(f.read().strip() or "0")
    except Exception:
        n = 0
    n += 1
    try:
        with open(p, "w", encoding="utf-8") as f:
            f.write(str(n))
    except Exception:
        pass
    return n


# ──────────────────────────────────────────────────────────────────────────
# 훅 모드 (transcript → 훅 JSON)
# ──────────────────────────────────────────────────────────────────────────
def _capture_pending(root, tail_span, closure):
    """자가발전(§0.1 원리3): 신어(backstop 사전 밖·verdict_close로만 잡힌) 차단을 pending
    케이스로 자동 포착 → /cleaner(또는 도훈)가 continuity_cases.json으로 승격. firewall의
    'append caller 0건 → 코퍼스 성장 정지' 실패를 반복하지 않기 위한 자동 트리거."""
    # novel = verdict_close로 잡혔으나 backstop finality lexeme 미매치(=사전 밖 표현)
    novel = closure.get("verdict_close") and not closure.get("has_finality")
    if not novel:
        return
    p = os.path.join(root, ".cache", "continuity_pending_cases.json")
    try:
        data = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {"pending": []}
    except Exception:
        data = {"pending": []}
    span = (tail_span or "").strip()[:400]
    h = hashlib.sha1(span.encode("utf-8", "replace")).hexdigest()[:12]
    if any(e.get("hash") == h for e in data.get("pending", [])):
        return
    data.setdefault("pending", []).append({
        "hash": h, "caught_span": span,
        "verdict_tokens": closure.get("verdict_tokens", []),
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "status": "await_review",
        "note": "신어 후보(backstop 사전 밖). /cleaner 또는 도훈이 category/why/reframe 정제 후 "
                "continuity_gate.py --append-case로 승격.",
    })
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


def run_transcript(tp, cap=3):
    root = project_root()
    cases = load_cases(root)
    turn = extract_current_turn(tp)
    res = judge_text(turn["text"], turn["tool_inputs"], cases, root,
                     user_ts=turn["user_ts"], use_llm=True)
    if not res["block"]:
        return {}
    # 자가발전: 신어 차단이면 pending 케이스 자동 포착
    try:
        _capture_pending(root, _tail(turn["text"], 0.4, 600),
                         res.get("diag", {}).get("closure", {}))
    except Exception:
        pass
    key = _cap_key(turn["user_ts"], turn["user_text"])
    n = _cap_bump(root, key)
    if n > cap:
        sys.stderr.write(f"[continuity_gate] cap {cap} 초과 — pass (loop 방지). "
                         "계속-산출물 미충족이 반복됨: 수동 확인 필요.\n")
        return {}
    return {"decision": "block", "reason": res["reason"]}


def review(root):
    """주간 /cleaner 소비: 차단 이력 + pending 신어 후보 통계·목록."""
    blocks_p = os.path.join(root, ".cache", "continuity_blocks.jsonl")
    pend_p = os.path.join(root, ".cache", "continuity_pending_cases.json")
    n_blocks = 0
    if os.path.exists(blocks_p):
        try:
            with open(blocks_p, encoding="utf-8") as f:
                n_blocks = sum(1 for ln in f if ln.strip())
        except Exception:
            pass
    pending = []
    if os.path.exists(pend_p):
        try:
            pending = json.load(open(pend_p, encoding="utf-8")).get("pending", [])
        except Exception:
            pending = []
    cases = load_cases(root)
    return {
        "n_blocks_logged": n_blocks,
        "n_cases": len(cases.get("cases", [])),
        "n_pending_novel": len([p for p in pending if p.get("status") == "await_review"]),
        "pending": [{"caught_span": p.get("caught_span"), "tokens": p.get("verdict_tokens"),
                     "captured_at": p.get("captured_at")} for p in pending
                    if p.get("status") == "await_review"],
        "action": "await_review 항목을 category/why/reframe 정제 후 --append-case로 승격 "
                  "(자가발전: 잡을수록 강해짐). 오탐 후보는 status=dismissed로.",
    }


# ──────────────────────────────────────────────────────────────────────────
# append_case (자가발전: 새 우회 → 라이브러리)
# ──────────────────────────────────────────────────────────────────────────
def append_case(root, category, caught_text, why, reframed_to, missing=None, source="manual"):
    p = os.path.join(root, "06_Registry", "continuity_cases.json")
    with open(p, encoding="utf-8") as f:
        data = json.load(f)
    h = hashlib.sha1(caught_text.strip().encode("utf-8", "replace")).hexdigest()[:12]
    for c in data.get("cases", []):
        if hashlib.sha1(c.get("caught_text", "").strip().encode("utf-8", "replace")).hexdigest()[:12] == h:
            return {"appended": False, "reason": "dedup"}
    data.setdefault("cases", []).append({
        "verdict": "violation", "category": category, "caught_text": caught_text,
        "why_violation": why, "missing_requirement": missing,
        "reframed_to": reframed_to, "added_at": time.strftime("%Y-%m-%d"),
        "seed": False, "source": source,
    })
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    return {"appended": True, "n_cases": len(data["cases"])}


# ──────────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────────
def _main():
    args = sys.argv[1:]
    root = project_root()
    if not args:
        print(json.dumps({}))
        return
    if args[0] == "--transcript":
        tp = args[1] if len(args) > 1 else ""
        if not tp or not os.path.isfile(tp):
            print(json.dumps({}))
            return
        try:
            out = run_transcript(tp)
        except Exception as e:
            sys.stderr.write(f"[continuity_gate] error: {type(e).__name__}: {e}\n")
            out = {}
        print(json.dumps(out, ensure_ascii=False))
        return
    if args[0] == "--text":
        text = args[1] if len(args) > 1 else sys.stdin.read()
        marker = "--marker-fresh" in args
        cases = load_cases(root)
        res = judge_text(text, "", cases, root, marker_override=(True if marker else None))
        print(json.dumps({"block": res["block"], "reason": res.get("reason"),
                          "diag": res["diag"]}, ensure_ascii=False, indent=2))
        return
    if args[0] == "--append-case":
        # --append-case <category> <caught_text> <why> <reframed_to>
        r = append_case(root, args[1], args[2], args[3], args[4] if len(args) > 4 else "")
        print(json.dumps(r, ensure_ascii=False))
        return
    if args[0] == "--review":
        print(json.dumps(review(root), ensure_ascii=False, indent=2))
        return
    if args[0] == "--stats":
        cases = load_cases(root)
        print(json.dumps({
            "n_cases": len(cases.get("cases", [])),
            "n_categories": len(cases.get("categories", [])),
            "n_backstop_terms": sum(len(c.get("backstop_terms", [])) for c in cases.get("categories", [])),
            "n_context_terms": len(cases.get("research_context_terms", [])),
            "llm_enabled": os.environ.get("QVEST_CONTINUITY_LLM", "") == "1",
        }, ensure_ascii=False, indent=2))
        return
    print(json.dumps({}))


if __name__ == "__main__":
    _main()
