#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""mode_queue_axis_audit.py — 비-alpha 큐의 **우선순위 축 채움**을 발행 시점에 검사하고,
어댑터 등재 후보 큐를 산출한다. (2026-08-13 신설)

왜:
  비-alpha 레인의 실질 병목은 백로그가 아니라 **어댑터 등재**다. Σ-A/B 배터리는 큐가 아니라
  `06_Registry/method_registry.json` 에서 arm 을 고르므로(paper_research_dispatch.R:363),
  큐가 몇 편이든 측정 arm 수는 등재 수에 묶인다. 실측 2026-08-13(★고유 단위): 큐 행 173 = **고유 112편**
  vs 레지스트리 11 entry = **고유 9편**, 그중 큐에서 온 것 6편 → **미등재 106편**.

  그 격차를 좁히려면 무엇부터 등재할지 정해야 하는데, 그 정렬 축(`screen_priority`
  ⭐⭐/⭐/후순위 + `shrinkage_builtin` + `statistic_order`)이 축요구 135건 중 **11건에만** 있다.

  ★단, 그것은 지시 미준수가 아니다 — 확인해보니 축 지시는 라우터 프롬프트에 2026-08-08 01:41
    (커밋 826f29b8)에 들어갔고, 그 **이후** 발행된 큐는 08-09 7/7 · 08-13 4/4 = **11/11 100%** 다.
    08-08 큐는 00:27 발행으로 지시보다 74분 앞선다. 즉 미표기 124건은 전부 **지시 이전 재고**이고,
    남은 일은 강제가 아니라 ①소급 표기 ②준수가 조용히 풀리지 않는지 **회귀 감시**다.
    (초판 주석은 "지시만으로는 안 채워진다"로 적었는데, 날짜를 대조하기 전 서술이라 틀렸다.)

  ★감사 방식: 자유 서술을 사후에 패턴으로 훑지 않고(그 접근은 하루 3/3 실패한 전례가 있다),
    **발행 직후 구조 검사**로 본다. 검사가 잡는 것은 어휘가 아니라 **필드의 존재**다.

산출:
  · stdout 준수 리포트 (날짜별 / 전체)
  · --emit-queue 시 `06_Registry/adapter_registration_queue.json`
      = 라우팅됐으나 method_registry 에 없는 항목의 **우선순위 정렬 목록**.
      ★축이 없는 항목은 0 이나 최하위로 **위장하지 않고** priority="unranked" 로 분리한다
        (미측정을 0 으로 적는 것이 이 저장소의 반복 실패 형태).

사용:
  python 02_Infrastructure/ops/mode_queue_axis_audit.py                    # 전체 감사
  python 02_Infrastructure/ops/mode_queue_axis_audit.py --date 20260813    # 발행 직후 1일 검사
  python 02_Infrastructure/ops/mode_queue_axis_audit.py --emit-queue
exit: 0 = 검사 수행(미표기 있어도 0 — 라우터 런을 죽이지 않는다) / 2 = 입력 부재
"""
import argparse
import io
import json
import os
import re
import sys

AXES = ("screen_priority", "shrinkage_builtin", "statistic_order")
# ★비정본 키 (2026-08-13 적발): 라우터가 07-27 · 08-04 · 08-08 3일간 `screen_priority` 대신
#   숫자 `priority`(1/2/3, 28건)를 실었다. 프롬프트에는 그런 지시가 **없다**(git -S 확인) —
#   라우터 임의 키이고, 소비자는 이 키를 읽지 않으므로 **발행됐지만 소비되지 않는 표기**다.
#   (07-27 은 `queue{}` 중첩으로 14편이 드롭된 날과 같은 날 — 같은 계통의 스키마 이탈.)
#   ★1/2/3 ↔ ⭐⭐/⭐/후순위 매핑은 **근거가 없다**(두 키가 한 번도 동시 등장하지 않아 대조 불가).
#     그래서 표기로도 미표기로도 세지 않고 **별도 버킷**으로 드러낸다 — 추측 매핑으로 채우면
#     그 뒤 모든 우선순위가 근거 없는 수 위에 서게 된다.
NONCANON_PRIO_KEYS = ("priority",)
# 축이 요구되는 레인 — prompt:59 는 optimizer/risk 에만 요구한다(regime 은 어댑터 종류가 다름)
AXIS_LANES = ("optimizer", "risk")
LANES = ("optimizer", "risk", "regime")
PRIO_RANK = {"⭐⭐": 0, "⭐": 1, "후순위": 2}


def _root():
    for c in (os.environ.get("QM_ROOT"), os.environ.get("CLAUDE_PROJECT_DIR"),
              os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))):
        if c and os.path.isdir(os.path.join(c, "06_Registry")):
            return c
    return os.getcwd()


def _load(p):
    try:
        with io.open(p, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _items(q):
    """정본 평면 형태 + 구 queue{} 중첩 둘 다 수용 (07-27 사고 구제용 관용, 계약은 평면)."""
    src = q.get("queue", q) if isinstance(q, dict) else {}
    out = []
    for lane in LANES:
        for it in (src.get(lane) or []):
            if isinstance(it, dict):
                out.append((lane, it))
    return out


def _title(it):
    return str(it.get("title") or it.get("paper") or it.get("name") or it.get("id") or "").strip()


def _norm_title(t):
    return re.sub(r"[^a-z0-9]+", "", t.lower())[:60]


def _item_id(it):
    """★식별자 필드를 **한 번에 다** 읽는다 (2026-08-13).
    큐 항목은 날짜마다 `id` / `arxiv_id` 를 섞어 쓴다. 하나만 읽으면 같은 논문이 두 키로
    갈려 '고유' 수가 부푼다 — 실측: id 만 읽었을 때 unranked 76건 안에 제목 중복 17건.
    (오늘 이 계통으로 수를 세 번 틀렸다: 행/entry 혼동 → join 과소/과다 → 식별자 필드 누락.)"""
    for k in ("id", "arxiv_id", "paper_id", "arxivId"):
        v = it.get(k)
        if v:
            return _norm_id(str(v))
    return ""


def _norm_id(x):
    """arxiv:2608.01494 / 2608.01494v2 / arXiv 2608.01494 → 260801494"""
    return re.sub(r"[^0-9]", "", re.sub(r"v\d+$", "", str(x).strip().lower()))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="YYYYMMDD 한 날짜만 검사 (라우터 발행 직후용)")
    ap.add_argument("--emit-queue", action="store_true", help="등재 후보 큐 산출")
    a = ap.parse_args()

    root = _root()
    stage = os.path.join(root, "stage_artifacts", "paper_recharge")
    if not os.path.isdir(stage):
        print("[axis] stage 디렉터리 부재: %s" % stage, file=sys.stderr)
        return 2

    files = sorted(f for f in os.listdir(stage)
                   if re.match(r"^mode_queue_\d{8}\.json$", f))
    if a.date:
        files = [f for f in files if a.date in f]
    if not files:
        print("[axis] 대상 큐 없음%s" % ((" (date=%s)" % a.date) if a.date else ""))
        return 0

    # 등재 대조 — method_registry 의 제목/method_id 로 join
    # ★join 키는 **선언된 식별자**를 먼저 쓴다 (2026-08-13).
    #   초판은 method_id 기반 제목 정규화만 대조해서 등재 11건 중 **6건만** 잡았다
    #   ("ProperScoreGASFilter" vs 논문 제목 "Proper-score observation-driven filters:…" 는
    #   부분일치가 성립하지 않는다) → 이미 등재된 논문이 '후보'로 다시 올라왔다.
    #   레지스트리는 `paper_id`(arxiv:NNNN.NNNNN) 와 `paper_title` 을 **선언 필드로 갖고 있다** —
    #   이름 파싱으로 유추하지 말고 그것을 읽는다([[feedback-search-where-a-classification-is-already-defined]]).
    reg = _load(os.path.join(root, "06_Registry", "method_registry.json")) or {}
    ms = reg.get("methods", reg)
    ms = list(ms.values()) if isinstance(ms, dict) else (ms or [])
    reg_ids, reg_titles = set(), set()
    title2id = {}   # 제목 → paper_id : 키 통일용
    for m in ms:
        if not isinstance(m, dict):
            continue
        pid = _norm_id(str(m.get("paper_id") or m.get("id") or ""))
        if pid:
            reg_ids.add(pid)
        for k in (m.get("paper_title"), m.get("method_id"), m.get("title")):
            if k:
                nk = _norm_title(str(k))
                reg_titles.add(nk)
                if pid:
                    title2id.setdefault(nk, pid)
    n_reg = len([m for m in ms if isinstance(m, dict)])

    # ── 소급 표기 오버레이 (2026-08-13). 원 큐는 수정하지 않고 여기서 join 한다.
    #   역사 산출물을 덮어쓰면 "원래 무엇이 표기돼 있었나"를 잃는다 — 표기 출처가
    #   라우터인지 소급인지 구분 가능해야 감사가 성립한다.
    bf = _load(os.path.join(root, "06_Registry", "adapter_axis_backfill_20260813.json")) or {}
    overlay = {r["paper_key"]: r for r in (bf.get("rows") or []) if isinstance(r, dict)}

    tot = req = filled = 0
    per_date = []
    cands, unranked = [], []
    nonc = 0           # 비정본 키로 표기된 항목 (표기도 미표기도 아님)
    seen = {}          # paper_key -> row (고유 논문 단위 집계)
    seen_reg = set()   # 큐에 등장했고 등재된 고유 논문
    for f in files:
        d = f[len("mode_queue_"):-len(".json")]
        q = _load(os.path.join(stage, f))
        if q is None:
            per_date.append((d, 0, 0, 0, 0, "PARSE_FAIL"))
            continue
        dt = dr = df = dn = 0
        for lane, it in _items(q):
            tot += 1
            dt += 1
            need = lane in AXIS_LANES
            has = all(it.get(x) is not None for x in AXES)
            noncanon = (it.get("screen_priority") is None
                        and any(it.get(k) is not None for k in NONCANON_PRIO_KEYS))
            if need:
                req += 1
                dr += 1
                if has:
                    filled += 1
                    df += 1
                elif noncanon:
                    nonc += 1
                    dn += 1
            t = _title(it)
            nt = _norm_title(t)
            ni = _item_id(it)
            # ① 선언 식별자(paper_id) 우선 ② 제목은 **완전일치만** 보조.
            #   ★부분일치(`nt in rk or rk in nt`)를 쓰면 반대 방향으로 틀린다 — 60자 절단 제목끼리
            #     포함관계가 쉽게 성립해 등재 11건인데 **23건**이 매칭됐다(실측). 과소 6 → 과다 23.
            #     레지스트리 11건 전부 paper_id 를 갖고 있으므로 식별자 join 이 정본이고,
            #     제목은 큐 항목에 id 가 없는 경우(173 중 41)만 받는 안전망이다.
            # ★키 통일: id 없는 행은 제목→id 로 해소한다. 안 하면 같은 논문이 id행/제목행으로
            #   **두 키**가 되어 고유 편수가 부풀고(교집합 13 > 레지스트리 고유 9), 그 수가
            #   그대로 "미등재 N편"에 반영된다. 단위 오류는 조용히 비율을 바꾼다.
            if not ni and nt in title2id:
                ni = title2id[nt]
            registered = bool(ni and ni in reg_ids) or bool(nt and nt in reg_titles)
            if registered:
                seen_reg.add(ni or nt)
                continue
            # ★후보는 **고유 논문** 단위로 센다 (2026-08-13).
            #   같은 논문이 여러 날 큐에 재등장한다 — 행으로 세면 173 인데 고유는 112 다.
            #   행 수를 편수로 읽으면 격차가 부풀고(173 vs 11), 그 수치가 그대로 보고에 퍼진다.
            #   등재 쪽도 마찬가지: 레지스트리 11 entry 의 고유 paper_id 는 9 다(한 논문에서
            #   변형 어댑터 여럿). **양쪽 단위를 맞춰야 비율이 의미를 갖는다.**
            key = ni or nt
            ov = overlay.get(key)
            prev = seen.get(key)
            row = {"paper_key": key, "first_date": d, "dates": [d], "lane": lane, "title": t,
                   "screen_priority": it.get("screen_priority") or (ov or {}).get("screen_priority"),
                   "shrinkage_builtin": it.get("shrinkage_builtin") or (ov or {}).get("shrinkage_builtin"),
                   "statistic_order": it.get("statistic_order") or (ov or {}).get("statistic_order"),
                   "axis_source": ("router" if it.get("screen_priority") is not None
                                   else ("retro_backfill_20260813" if ov else None)),
                   "meets_frontier_criteria": (ov or {}).get("meets_frontier_criteria", False)}
            if prev is None:
                seen[key] = row
            else:
                if d not in prev["dates"]:
                    prev["dates"].append(d)
                # 축은 나중 표기가 있으면 채운다(뒤 날짜에서 표기된 경우)
                #   ★출처 라벨도 같이 갱신한다 — 안 하면 첫 행 기준으로 굳어 provenance 가 틀린다
                #     (실측: ranked 3건이 값은 있는데 axis_source=None 이었다).
                for ax in AXES:
                    if prev.get(ax) is None and it.get(ax) is not None:
                        prev[ax] = it.get(ax)
                        if ax == "screen_priority":
                            prev["axis_source"] = "router"
        per_date.append((d, dt, dr, df, dn, ""))

    for row in seen.values():
        (cands if row.get("screen_priority") in PRIO_RANK else unranked).append(row)

    print("== 비-alpha 큐 우선순위 축 채움 (계약: optimizer/risk 항목은 3축 전부) ==")
    for d, dt, dr, df, dn, err in per_date:
        pct = ("%3.0f%%" % (100.0 * df / dr)) if dr else "  -  "
        flag = " ★미표기" if dr and (df + dn) < dr else ""
        nc = (" · 비정본키 %d" % dn) if dn else ""
        print("  %s  항목 %3d · 축요구 %3d · 표기 %3d%s  %s%s%s"
              % (d, dt, dr, df, nc, pct, flag, (" " + err) if err else ""))
    print("  ── 전체: 항목 %d · 축요구 %d · 표기 %d (%.0f%%)" %
          (tot, req, filled, (100.0 * filled / req) if req else 0.0))
    print("  ★비정본 키(priority 1/2/3) %d건 — 표기도 미표기도 아님. 매핑 근거 없어 추측 금지." % nonc)
    print("  ★정렬 불가 %d건 — 0 이나 최하위로 접지 않는다(미측정 위장 금지)." % (req - filled - nonc))
    print("  ── 단위: 큐 행 %d = 고유 논문 %d편 · 레지스트리 %d entry = 고유 %d편 · 큐↔등재 교집합 %d편"
          % (tot, len(seen) + len(seen_reg), n_reg, len(reg_ids), len(seen_reg)))
    print("  ★미등재 고유 논문 %d편 — 이것이 등재 병목의 실제 크기다(행 수 아님)." % len(seen))

    if a.emit_queue:
        cands.sort(key=lambda r: (PRIO_RANK.get(r["screen_priority"], 9), r["first_date"]))
        out = {
            "_doc": ("어댑터 등재 후보 큐 — 라우팅됐으나 method_registry 미등재 항목. "
                     "생성기 02_Infrastructure/ops/mode_queue_axis_audit.py --emit-queue. "
                     "ranked=screen_priority 보유(정렬 가능) / unranked=축 미표기(정렬 불가, "
                     "0 위장 금지). ★측정 arm 수는 큐 길이가 아니라 **등재 수**에 비례한다 — "
                     "이 큐를 줄이는 것이 비-alpha 레인의 실질 레버."),
            "generated_from": "stage_artifacts/paper_recharge/mode_queue_*.json",
            "n_queue_rows": tot,
            "n_unique_papers": len(seen) + len(seen_reg),
            "n_registry_entries": n_reg,
            "n_registry_unique_papers": len(reg_ids),
            "n_unique_registered_from_queue": len(seen_reg),
            "unit_note": ("★행 수와 편수를 섞지 말 것. 큐 행 173 = 고유 112편(같은 논문이 여러 날 재등장), "
                          "레지스트리 11 entry = 고유 paper_id 9(한 논문에 변형 어댑터 여럿). "
                          "비율은 **고유:고유** 로만 의미가 있다."),
            "join_note": "join = paper_id(선언 식별자) 완전일치 우선 + 제목 정규화 완전일치 보조(id 없는 항목용).",
            "n_ranked": len(cands), "n_unranked": len(unranked),
            "n_meets_frontier": sum(1 for r in cands + unranked if r.get("meets_frontier_criteria")),
            "ranked": cands, "unranked": unranked,
        }
        op = os.path.join(root, "06_Registry", "adapter_registration_queue.json")
        with io.open(op, "w", encoding="utf-8") as f:
            f.write(json.dumps(out, ensure_ascii=False, indent=2))
        print("  → %s (ranked %d · unranked %d)" % (op, len(cands), len(unranked)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
