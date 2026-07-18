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


def _span_of(text):
    """차단/pending 공용 span (hash join 키의 단일 정의 — C4)."""
    return _tail(text or "", 0.4, 600).strip()[:400]


def _span_hash(span):
    return hashlib.sha1((span or "").encode("utf-8", "replace")).hexdigest()[:12]


def _ts_to_epoch(user_ts):
    if not user_ts:
        return None
    try:
        import datetime
        return datetime.datetime.fromisoformat(user_ts.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def _apply_suppressions(text, cases):
    """C3-②: dismissed 오탐(--review/--dismiss)에서 학습된 suppression 구절을 마스킹 —
    결정론 판정 한정(오탐도 학습되는 양방향 루프). 구절은 반드시 문맥 포함 — bare 토큰
    whitelisting으로 재현율이 새는 것을 최소 길이 가드로 차단."""
    sup = cases.get("suppressions", [])
    if not sup:
        return text
    for s in sup:
        ph = s.get("phrase", "")
        tok = s.get("token", "")
        if not ph or len(ph) < max(len(tok) + 3, 8):
            continue
        if ph in text:
            text = text.replace(ph, " ")
    return text


def _ops_progress(tail, cases):
    """C2 입력: 진행/운영 마커(케이스 파일 ops_context_terms — 하드코딩 아닌 열린 스키마)."""
    return [t for t in cases.get("ops_context_terms", []) if t and t in tail]


def turn_verdict_artifacts(root, user_ts):
    """C1 운영-턴 판별: 이번 턴(user_ts 이후)에 신규 '판정 산출물'이 실재하는가.
    판정 산출물 = stage_artifacts/l_code/** 신규 파일 · .cache/round_closures.jsonl append
    (close_round 원장) · qepm/mailbox/**/verdict.json 신규 write.
    부재 = 이 턴은 판정 생산 턴이 아님(보고/브리핑/운영) → verdict_close(간접 NEG-토큰
    신호)를 차단 근거에서 제외. 명시 종결어휘(category backstop)는 이 판별과 무관하게 유효.
    user_ts 불명·스캔 오류 = 판별 불가 → True(기존 재현율 보존, fail-toward-recall)."""
    ref = _ts_to_epoch(user_ts)
    if ref is None:
        return True, ["user_ts_unknown"]
    ref -= 2
    ev = []
    try:
        for f in (os.path.join(root, ".cache", "round_closures.jsonl"),
                  os.path.join(root, ".cache", "last_round_closure.json")):
            if os.path.isfile(f) and os.path.getmtime(f) >= ref:
                ev.append(os.path.basename(f))
        for pat in (os.path.join(root, "stage_artifacts", "l_code", "**", "*.json"),
                    os.path.join(root, "qepm", "mailbox", "**", "verdict.json")):
            for f in glob.glob(pat, recursive=True):
                if os.path.isfile(f) and os.path.getmtime(f) >= ref:
                    ev.append(os.path.relpath(f, root))
                    break
    except Exception:
        return True, ["scan_error"]
    return (len(ev) > 0), ev


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
    text = _apply_suppressions(text, cases)  # C3-② dismissed-오탐 학습분 마스킹
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
        "ops_progress": _ops_progress(tail, cases),  # C2 입력(진행/운영 마커)
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
    ref = _ts_to_epoch(user_ts)
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
               use_llm=False, verdict_artifact_override=None):
    # tool_inputs: 의도적 판정 제외(미소비 유지) — tool 호출 인자는 코드/경로/과거-판정 인용
    # 노이즈라 종결 어휘 오탐만 늘림. 판정 대상 = assistant 서술 텍스트만.
    diag = {"research_context": False, "detected": False}
    if not text or not text.strip():
        return {"block": False, "diag": diag}
    if not research_context(text, cases):
        return {"block": False, "diag": diag}
    diag["research_context"] = True
    cl = detect_closure(text, cases)
    # ── C1 운영-턴 판별: verdict_close(간접 NEG-토큰 신호)는 '이번 턴 신규 판정 산출물'이
    #    실재할 때만 차단 근거. 없으면 보고/브리핑/운영 턴 — 과거 판정 어휘 인용은 종결이 아님.
    #    명시 종결어휘(has_finality)·대기-마감(has_waiting)은 이 판별과 무관하게 유효(재현율 불변).
    if cl["verdict_close"]:
        if verdict_artifact_override is None:
            va, va_ev = turn_verdict_artifacts(root, user_ts)
        else:
            va, va_ev = bool(verdict_artifact_override), ["override"]
        diag["verdict_artifacts"] = {"produced": va, "evidence": va_ev[:5]}
        if not va:
            cl["verdict_close"] = False
            cl["verdict_close_suppressed"] = "no_new_verdict_artifact"
        elif cl["ops_progress"] and not cl["has_finality"]:
            # ── C2 in-progress 예외(케이스 파일 '진행 중 리서치 실재 시 허용' 일반화의 코드화):
            #    진행/운영 마커 실재 ∧ 종결어휘(backstop) 부재 → NEG-토큰 서술은 상태보고.
            cl["verdict_close"] = False
            cl["verdict_close_suppressed"] = "in_progress_context"
    # 선택적 LLM: detection만 확장(계약 게이트는 불변)
    llm = llm_verdict(text, cases) if use_llm else None
    llm_flag = bool(llm and llm.get("is_giving_up_closure"))
    detected = cl["has_finality"] or cl["has_waiting"] or cl["verdict_close"] or llm_flag
    cl["detected"] = detected
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
    h = _span_hash(span)
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


def _count_pass(root, res, forced=None):
    """C4: 게이트 검사 pass 경량 카운트(FP율 분모 확보). 일자 파일 —
    .cache/continuity_gate_counters/passes_YYYYMMDD.json (per-turn cap 키 파일과 접두사 분리)."""
    try:
        d = os.path.join(root, ".cache", "continuity_gate_counters")
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, "passes_" + time.strftime("%Y%m%d") + ".json")
        try:
            with open(p, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {"date": time.strftime("%Y-%m-%d"), "n_pass": 0, "by": {}}
        data["n_pass"] = int(data.get("n_pass", 0)) + 1
        diag = res.get("diag", {}) if res else {}
        if forced:
            k = forced
        elif not diag.get("research_context"):
            k = "non_research"
        elif not diag.get("detected"):
            sup = diag.get("closure", {}).get("verdict_close_suppressed")
            k = ("suppressed:" + sup) if sup else "no_closure_detected"
        elif diag.get("contract", {}).get("satisfied"):
            k = "contract_satisfied"
        else:
            k = "other"
        by = data.setdefault("by", {})
        by[k] = int(by.get(k, 0)) + 1
        with open(p, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
    except Exception:
        pass


def _log_block(root, tp, turn, res):
    """C4 차단 감사 스키마: 무엇이(categories/verdict_tokens/matched_terms) 왜(reason) 막았는지
    + span_hash(pending_cases와 join 키). guard.sh의 {ts,tp} 최소 기록을 대체 —
    guard.sh는 중복 append하지 않는다(정합)."""
    try:
        diag = res.get("diag", {})
        cl = diag.get("closure", {})
        ct = diag.get("contract", {})
        span = _span_of(turn.get("text", ""))
        rec = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "tp": tp,
            "decision": "block",
            "categories": cl.get("categories", []),
            "verdict_tokens": cl.get("verdict_tokens", []),
            "matched_terms": cl.get("matched_terms", []),
            "reason": "; ".join(ct.get("missing", []))[:300],
            "span_hash": _span_hash(span),
        }
        p = os.path.join(root, ".cache", "continuity_blocks.jsonl")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        pass


def run_transcript(tp, cap=3):
    root = project_root()
    cases = load_cases(root)
    turn = extract_current_turn(tp)
    res = judge_text(turn["text"], turn["tool_inputs"], cases, root,
                     user_ts=turn["user_ts"], use_llm=True)
    if not res["block"]:
        _count_pass(root, res)  # C4: FP율 분모
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
        _count_pass(root, res, forced="cap_exceeded")
        return {}
    _log_block(root, tp, turn, res)  # C4: 차단 감사(스키마 확장)
    return {"decision": "block", "reason": res["reason"]}


def _triage_hint(span, cases):
    """C3-③ /cleaner 판별 힌트 1줄: FP성(진행보고·브리핑) vs TP성(종결 프레이밍) 구분."""
    span = span or ""
    has_fin = any(t and t in span
                  for cat in cases.get("categories", [])
                  for t in cat.get("backstop_terms", []))
    ops = [t for t in cases.get("ops_context_terms", []) if t and t in span]
    if not has_fin and ops:
        return ("FP성 추정 — 진행/운영 마커(" + ", ".join(ops[:3]) +
                ") 실재·종결어휘 무 → --dismiss 후보")
    if not has_fin:
        return ("FP성 가능 — NEG-토큰 인용만·종결어휘 무. 보고/브리핑이면 --dismiss, "
                "완곡 종결 신어면 --append-case --term 승격")
    return "TP성 추정 — 종결어휘 backstop 실재 → --append-case 승격 검토"


def _context_phrases(span, tok, win=18, limit=3):
    """dismissed span에서 트리거 토큰의 문맥 구절 추출(±win자, 원문 substring 보존 —
    마스킹 매칭이 깨지지 않도록 내부 공백 정규화 금지)."""
    out = []
    if not tok or not span:
        return out
    i = span.find(tok)
    while i != -1 and len(out) < limit:
        ph = span[max(0, i - win): i + len(tok) + win].strip()
        if len(ph) >= max(len(tok) + 3, 8):
            out.append(ph)
        i = span.find(tok, i + 1)
    return out


def _learn_suppressions_from_dismissed(root):
    """C3-②: pending의 status=dismissed 항목에서 트리거 어휘 문맥 구절을
    continuity_cases.json `suppressions`로 기록(결정론 판정이 매칭 시 마스킹) —
    오탐도 학습되는 양방향 루프. 처리분은 suppression_recorded=True 마킹(1회성)."""
    pend_p = os.path.join(root, ".cache", "continuity_pending_cases.json")
    if not os.path.exists(pend_p):
        return 0
    try:
        pend = json.load(open(pend_p, encoding="utf-8"))
    except Exception:
        return 0
    cases = load_cases(root)
    existing = {(s.get("token"), s.get("phrase")) for s in cases.get("suppressions", [])}
    new_sups, changed_pend = [], False
    for e in pend.get("pending", []):
        if e.get("status") != "dismissed" or e.get("suppression_recorded"):
            continue
        span = e.get("caught_span", "")
        for tok in e.get("verdict_tokens", []):
            for ph in _context_phrases(span, tok):
                if (tok, ph) not in existing:
                    new_sups.append({"span_hash": e.get("hash"), "token": tok, "phrase": ph,
                                     "added_at": time.strftime("%Y-%m-%d"),
                                     "source": "review_dismissed"})
                    existing.add((tok, ph))
        e["suppression_recorded"] = True
        changed_pend = True
    if new_sups:
        cp = os.path.join(root, "06_Registry", "continuity_cases.json")
        data = json.load(open(cp, encoding="utf-8"))
        data.setdefault("suppressions", []).extend(new_sups)
        with open(cp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    if changed_pend:
        with open(pend_p, "w", encoding="utf-8") as f:
            json.dump(pend, f, ensure_ascii=False, indent=2)
    return len(new_sups)


def review(root):
    """주간 /cleaner 소비: 차단 이력 + pending 신어 후보 통계·목록(+FP/TP 판별 힌트)
    + dismissed→suppression 학습(C3-② 양방향 루프)."""
    blocks_p = os.path.join(root, ".cache", "continuity_blocks.jsonl")
    pend_p = os.path.join(root, ".cache", "continuity_pending_cases.json")
    n_blocks = 0
    if os.path.exists(blocks_p):
        try:
            with open(blocks_p, encoding="utf-8") as f:
                n_blocks = sum(1 for ln in f if ln.strip())
        except Exception:
            pass
    n_new_sup = 0
    try:
        n_new_sup = _learn_suppressions_from_dismissed(root)
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
        "n_suppressions": len(cases.get("suppressions", [])),
        "n_new_suppressions_learned": n_new_sup,
        "n_pending_novel": len([p for p in pending if p.get("status") == "await_review"]),
        "pending": [{"hash": p.get("hash"),
                     "caught_span": p.get("caught_span"), "tokens": p.get("verdict_tokens"),
                     "captured_at": p.get("captured_at"),
                     "triage_hint": _triage_hint(p.get("caught_span"), cases)}
                    for p in pending if p.get("status") == "await_review"],
        "action": "await_review 항목: TP성은 --append-case [--term <lexeme>]로 승격(결정론 "
                  "backstop 즉시 소비), FP성은 --dismiss <hash>(suppression 학습 — 같은 FP "
                  "재차단 방지). (자가발전: 양방향 모두 잡을수록 강해짐)",
    }


# ──────────────────────────────────────────────────────────────────────────
# append_case (자가발전: 새 우회 → 라이브러리)
# ──────────────────────────────────────────────────────────────────────────
def append_case(root, category, caught_text, why, reframed_to, missing=None, source="manual",
                terms=None):
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
    # C3-①: --term lexeme을 해당 category backstop_terms에 동시 주입 — 결정론 경로가 실제
    # 소비(케이스만 쌓이고 판정이 안 강해지는 'L4 무영향' 구멍 폐쇄).
    added_terms, term_note = [], None
    if terms:
        cat_found = False
        for cat in data.get("categories", []):
            if cat.get("id") == category:
                cat_found = True
                bt = cat.setdefault("backstop_terms", [])
                for t in terms:
                    if t and t not in bt:
                        bt.append(t)
                        added_terms.append(t)
                break
        if not cat_found:
            term_note = f"category '{category}' 미존재 — term 미주입(케이스만 등재)"
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    out = {"appended": True, "n_cases": len(data["cases"]), "added_terms": added_terms}
    if term_note:
        out["term_note"] = term_note
    return out


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
        rest = args[1:]
        marker = "--marker-fresh" in rest
        no_va = "--no-verdict-artifact" in rest  # C1 판별 강제(운영-턴 재현 테스트용)
        pos = [a for a in rest if a not in ("--marker-fresh", "--no-verdict-artifact")]
        text = pos[0] if pos else sys.stdin.read()
        cases = load_cases(root)
        res = judge_text(text, "", cases, root, marker_override=(True if marker else None),
                         verdict_artifact_override=(False if no_va else None))
        print(json.dumps({"block": res["block"], "reason": res.get("reason"),
                          "diag": res["diag"]}, ensure_ascii=False, indent=2))
        return
    if args[0] == "--append-case":
        # --append-case <category> <caught_text> <why> <reframed_to> [--term <lexeme> ...]
        rest, terms, pos = args[1:], [], []
        i = 0
        while i < len(rest):
            if rest[i] == "--term" and i + 1 < len(rest):
                terms.append(rest[i + 1])
                i += 2
            else:
                pos.append(rest[i])
                i += 1
        r = append_case(root, pos[0], pos[1], pos[2], pos[3] if len(pos) > 3 else "",
                        terms=terms)
        print(json.dumps(r, ensure_ascii=False))
        return
    if args[0] == "--dismiss":
        # --dismiss <span_hash> — pending 오탐을 dismissed 표기 + suppression 즉시 학습(C3-②)
        h = args[1] if len(args) > 1 else ""
        pend_p = os.path.join(root, ".cache", "continuity_pending_cases.json")
        found = False
        try:
            pend = json.load(open(pend_p, encoding="utf-8"))
            for e in pend.get("pending", []):
                if e.get("hash") == h and e.get("status") == "await_review":
                    e["status"] = "dismissed"
                    found = True
            if found:
                with open(pend_p, "w", encoding="utf-8") as f:
                    json.dump(pend, f, ensure_ascii=False, indent=2)
        except Exception:
            pass
        n_sup = _learn_suppressions_from_dismissed(root) if found else 0
        print(json.dumps({"dismissed": found, "hash": h,
                          "n_suppressions_learned": n_sup}, ensure_ascii=False))
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
