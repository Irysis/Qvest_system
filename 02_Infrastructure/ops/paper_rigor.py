#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =============================================================================
# paper_rigor.py — 충실구현 큐 논문의 방법론 수준(rigor) 채점 · 큐 제외 (도훈 11-16 PAPER-ORDER-RIGOR-FILTER-20261116 = B)
#
# 왜: 큐 순서 규칙(next_paper_order)과 라우터 어디에도 논문 방법론 수준 입력이 없어서, 6개월 1회 검증 · 무작위 비중 ·
#   벤치 · 비용 · 검정이 없는 논문(2107.11371)이 큐 앞으로 올라왔다. 도훈 결정 B = low 는 큐에서 뺀다(재료로도 소비 안 함).
# 무엇: LLM(레인 paper_rigor · 단일 진입 rf_llm_agent_run — paper_rigor_run.sh)이 원문에서 기준 여섯을 참/거짓으로 답하고,
#   등급은 여기서 기계로 정한다(점수 = 참 개수 · high ≥ 5 · mid 3~4 · low ≤ 2 — 설정 06_Registry/paper_rigor.json).
#   기록 = 06_Registry/paper_rigor.jsonl(append · 논문별 마지막 줄이 정본). low = replication_skiplist.json 에 verdict low_rigor 항목
#   (되살리기 = 그 항목 status revoked — 기존 건너뛰기 규약 그대로).
# 정보 경계: 입력 = 논문 원문뿐. 우리 측정 성과 · 등급을 읽지 않는다. 근거 글에는 성과 수치를 싣지 않게 지시한다(τ_D 통로).
# 사용:
#   paper_rigor.py todo [--limit N]                 → 큐 순서대로 아직 채점 안 된 논문 'key<TAB>url<TAB>title' 줄
#   paper_rigor.py prompt <key> <title> <text_file> <out>   → 채점 프롬프트 파일
#   paper_rigor.py ingest <key> <url> <title> <run_out> [--text-kind K] [--model M]  → 기록 · low 면 건너뛰기
#   paper_rigor.py show [--key K]
# =============================================================================
import argparse
import io
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("QM_ROOT") or os.path.abspath(os.path.join(HERE, "..", ".."))
REG = os.path.join(ROOT, "06_Registry")
CFG_P = os.path.join(REG, "paper_rigor.json")
LOG_P = os.path.join(REG, "paper_rigor.jsonl")
SKIP_P = os.path.join(REG, "replication_skiplist.json")
STAGE = os.path.join(ROOT, "stage_artifacts", "paper_recharge")
CRITERIA_BY_TYPE = {   # v2(11-16 도훈 '1번') — 이론 · 방법론 논문은 실증 전략 기준으로 재지 않는다
    "empirical": ("long_evaluation", "benchmark", "costs", "stat_test", "nontrivial_method", "peer_reviewed"),
    "theory": ("rigorous_derivation", "simulation_validation", "real_data_illustration", "comparison_to_existing", "nontrivial_method", "peer_reviewed"),
}
CRITERIA = CRITERIA_BY_TYPE["empirical"]
TEXT_MAX = 150000


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def cfg():
    with io.open(CFG_P, encoding="utf-8") as fh:
        c = json.load(fh)
    b = c["bands"]
    return c, int(b["high_min"]), int(b["mid_min"])


def latest():
    out = {}
    if os.path.exists(LOG_P):
        for ln in io.open(LOG_P, encoding="utf-8"):
            ln = ln.strip()
            if not ln:
                continue
            try:
                r = json.loads(ln)
            except Exception:
                continue
            if r.get("paper_key"):
                out[str(r["paper_key"])] = r
    return out


def band(score, hi, mid):
    return "high" if score >= hi else ("mid" if score >= mid else "low")


def cmd_todo(a):
    sys.path.insert(0, HERE)
    import research_pool_predicates as rp
    # 다시 채점하지 않는 것 = 등급이 난 논문 · 원문이 없어 unknown 인 논문(no_text). LLM 실패(unparsed)는 다음 실행이 다시 본다.
    done = {k for k, r in latest().items() if (r.get("rigor") in ("high", "mid", "low") or r.get("why") == "no_text")
            and (not a.regrade or r.get("rubric") == "v2")}
    ordered, _st = rp.alpha_pending_ordered(STAGE, REG)
    try:
        sk = json.load(io.open(SKIP_P, encoding="utf-8"))
        skip = {str(e.get("paper_key")) for e in (sk.get("entries") or []) if e.get("status") != "revoked"
                and not (a.regrade and e.get("verdict") == "low_rigor")}
    except Exception:
        skip = set()
    n = 0
    for key, rec, _info in ordered:
        k = rp._order_key_id(key) or rp.pid_of(rec, warn=False)
        if not k or k in done or k in skip:
            continue
        url = str(rec.get("url") or rec.get("link") or "")
        if not url and re.match(r"^\d{4}\.\d{4,5}$", k):
            url = "https://arxiv.org/abs/" + k
        if not url:
            continue
        title = str(rec.get("paper_title") or rec.get("title") or "").replace("\t", " ").replace("\n", " ")
        print("%s\t%s\t%s" % (k, url, title))
        n += 1
        if a.limit and n >= a.limit:
            break


PROMPT = """너는 계량금융 논문의 **방법론 수준**만 판정한다. 결론이 맞는지, 성과가 좋은지는 판정하지 않는다.
먼저 논문 유형(paper_type)을 정하라:
- "empirical" — 투자 전략 · 신호 · 포트폴리오를 실제 자료로 운용해 성과를 보이는 것이 주결과인 논문
- "theory" — 주결과가 정리 · 유도 · 추정량 · 알고리즘 · 최적화 방법 자체이고 실자료는 예시인 논문
그다음 그 유형의 기준 여섯 개에 참(true) / 거짓(false)으로 답하라. 원문에서 확인되지 않으면 false 다.

[empirical 기준]
1. long_evaluation — 전략 · 포트폴리오 성과를 5년 이상의 자료로 평가했다(표본 밖 · 롤링 · 워크포워드 · 반복 재추정 · 긴 이력의 횡단면 포트폴리오 검정 모두 인정). 6개월 · 1년 한 번의 보유 평가는 false.
2. benchmark — 시장 지수나 단순 대안(동일가중 · 매수 후 보유 · 1/N · 기존 모형)과 같은 기간에 비교했다.
3. costs — 거래비용 · 회전율 · 슬리피지를 성과에 반영하거나 따로 분석했다.
4. stat_test — 성과 · 알파의 통계적 유의성을 검정했다(t 통계량 · 표준오차 · 부트스트랩 · 다중검정 보정 · DSR · SPA · 신뢰구간 등).
[theory 기준]
1. rigorous_derivation — 정리 · 명제의 증명이나 엄밀한 유도가 있다(서술만 · 직관만은 false).
2. simulation_validation — 합성 자료 · 몬테카를로로 이론 결과(수렴 · 편향 · 성능)를 확인했다.
3. real_data_illustration — 실제 시장 자료에 적용한 예시나 실증이 있다(길이 무관).
4. comparison_to_existing — 기존 방법 · 추정량 · 알고리즘과 같은 조건에서 비교했다.
[공통]
5. nontrivial_method — 방법 자체에 기여가 있다(새 신호 · 새 모형 · 새 추정량 · 새 알고리즘 · 새 이론 결과). 기성 기법(HRP · 표준 평균분산 · 표준 PCA · 무작위 비중 탐색 · 블랙-리터만 · LSTM · 랜덤포레스트 · 퍼지 규칙 등)을 새 시장 · 새 자료에 그대로 적용한 것만이면 false.
6. peer_reviewed — 심사 학술지 · 학회에 실렸다고 원문(첫 쪽 · 각주 · 인용 정보)에 적혀 있다. 프리프린트뿐이면 false.

규칙: 근거(evidence)는 기준마다 원문 위치를 짧게(절 번호 · 표 번호 · 30자 이내 인용). **성과 수치(수익률 · 샤프 · 낙폭 등 숫자)는 근거에 쓰지 않는다.**
출력은 JSON 한 개만(코드 블록 없이) — 키 = paper_type + 그 유형의 기준 여섯 + evidence:
{"paper_type": "empirical"|"theory", "<기준1>": true|false, ..., "<기준6>": true|false, "evidence": {"<기준1>": "...", ...}}

논문: %(key)s — %(title)s
원문(%(kind)s):
-----
%(text)s
-----
"""


def cmd_prompt(a):
    try:
        txt = io.open(a.text_file, encoding="utf-8", errors="replace").read()
    except Exception:
        txt = ""
    kind = "full" if len(txt) >= 5000 else ("short" if txt else "none")
    body = PROMPT % {"key": a.key, "title": a.title, "kind": kind, "text": txt[:TEXT_MAX] or "(원문을 받지 못했다 — 모든 기준 false 로 답하지 말고 첫 줄에 NO_TEXT 만 써라)"}
    io.open(a.out, "w", encoding="utf-8").write(body)
    print(kind)


def _parse(run_out):
    t = io.open(run_out, encoding="utf-8", errors="replace").read()
    if "NO_TEXT" in t[:200]:
        return None, "no_text"
    for m in re.finditer(r"\{", t):
        depth = 0
        for j in range(m.start(), len(t)):
            if t[j] == "{":
                depth += 1
            elif t[j] == "}":
                depth -= 1
                if depth == 0:
                    try:
                        o = json.loads(t[m.start():j + 1])
                    except Exception:
                        break
                    pt = str(o.get("paper_type") or "empirical").strip().lower()
                    crit = CRITERIA_BY_TYPE.get(pt)
                    if crit and all(isinstance(o.get(c), bool) for c in crit):
                        o["paper_type"] = pt
                        return o, "ok"
                    break
    return None, "unparsed"


def _skip_write(sk):
    tmp = SKIP_P + ".tmp"
    io.open(tmp, "w", encoding="utf-8", newline="\n").write(json.dumps(sk, ensure_ascii=False, indent=1) + "\n")
    os.replace(tmp, SKIP_P)


def _skip_release(key, rigor):
    """재채점에서 low 가 아니게 된 논문 — 자동(low_rigor) 건너뛰기 항목을 revoked 로(사람이 넣은 다른 사유 항목은 건드리지 않는다)."""
    sk = json.load(io.open(SKIP_P, encoding="utf-8"))
    n = 0
    for e in sk.get("entries") or []:
        if str(e.get("paper_key")) == key and e.get("verdict") == "low_rigor" and e.get("status") != "revoked":
            e["status"] = "revoked"; e["revoked_at"] = now(); e["revoked_by"] = "paper_rigor.py 재채점"
            e["revoke_reason"] = "재채점 rigor=%s(채점기 v2 · 논문 유형 구분)" % rigor
            n += 1
    if n:
        _skip_write(sk)
    return n


def _skip_add(key, url, title, score, crit):
    sk = json.load(io.open(SKIP_P, encoding="utf-8"))
    ents = sk.setdefault("entries", [])
    if any(str(e.get("paper_key")) == key and e.get("status") != "revoked" for e in ents):
        return False
    if any(str(e.get("paper_key")) == key and e.get("verdict") == "low_rigor" and e.get("status") == "revoked"
           and str(e.get("revoked_by") or "") != "paper_rigor.py 재채점" for e in ents):
        return False   # 사람이 되살린 논문은 다시 빼지 않는다
    ents.append({"paper_key": key, "title": title, "url": url, "skipped_at": now(), "verdict": "low_rigor",
                 "reason": "방법론 수준 low(점수 %d/6 · 참 = %s) — 도훈 11-16 PAPER-ORDER-RIGOR-FILTER-20261116 B(큐에서 제외 · 재료로도 소비 안 함)"
                           % (score, ", ".join(c for c, v in crit.items() if v) or "없음"),
                 "artifacts": "06_Registry/paper_rigor.jsonl",
                 "unblock": "되살리기 = 이 항목 status revoked(기존 건너뛰기 규약)"})
    tmp = SKIP_P + ".tmp"
    io.open(tmp, "w", encoding="utf-8", newline="\n").write(json.dumps(sk, ensure_ascii=False, indent=1) + "\n")
    os.replace(tmp, SKIP_P)
    return True


def cmd_ingest(a):
    _c, hi, mid = cfg()
    o, why = _parse(a.run_out)
    rec = {"schema": "paper_rigor_v1", "paper_key": a.key, "title": a.title, "url": a.url, "at": now(),
           "text_kind": a.text_kind, "model": a.model, "decision": "PAPER-ORDER-RIGOR-FILTER-20261116"}
    if o is None:
        rec.update({"rigor": "unknown", "why": why})
    else:
        CR = CRITERIA_BY_TYPE[o["paper_type"]]
        crit = {c: bool(o.get(c)) for c in CR}
        score = sum(crit.values())
        rg = band(score, hi, mid)
        if a.text_kind != "full" and rg == "low":
            rg = "unknown"   # 전문 없이 low 로 빼지 않는다(초록만으로는 기준 확인이 안 된다)
        ev = o.get("evidence") if isinstance(o.get("evidence"), dict) else {}
        rec.update({"rigor": rg, "score": score, "paper_type": o["paper_type"], "criteria": crit, "rubric": "v2",
                    "evidence": {c: str(ev.get(c) or "")[:120] for c in CR}})
    with io.open(LOG_P, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    skipped = False
    if rec.get("rigor") == "low":
        skipped = _skip_add(a.key, a.url, a.title, rec["score"], rec["criteria"])
    elif rec.get("rigor") in ("high", "mid"):
        _skip_release(a.key, rec["rigor"])
    print("RIGOR\t%s\t%s\tscore=%s\tskipped=%d" % (a.key, rec["rigor"], rec.get("score", ""), int(skipped)))


def cmd_show(a):
    L = latest()
    for k, r in L.items():
        if a.key and k != a.key:
            continue
        print("%s\t%s\t%s\t%s" % (k, r.get("rigor"), r.get("score", ""), (r.get("title") or "")[:70]))


def main(argv):
    ap = argparse.ArgumentParser(prog="paper_rigor")
    sp = ap.add_subparsers(dest="cmd", required=True)
    t = sp.add_parser("todo"); t.add_argument("--limit", type=int, default=0); t.add_argument("--regrade", action="store_true"); t.set_defaults(f=cmd_todo)
    p = sp.add_parser("prompt"); [p.add_argument(x) for x in ("key", "title", "text_file", "out")]; p.set_defaults(f=cmd_prompt)
    i = sp.add_parser("ingest"); [i.add_argument(x) for x in ("key", "url", "title", "run_out")]
    i.add_argument("--text-kind", default="full"); i.add_argument("--model", default=""); i.set_defaults(f=cmd_ingest)
    s = sp.add_parser("show"); s.add_argument("--key", default=""); s.set_defaults(f=cmd_show)
    a = ap.parse_args(argv)
    a.f(a)


if __name__ == "__main__":
    main(sys.argv[1:])
