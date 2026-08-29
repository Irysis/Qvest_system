#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#==============================================================================
# essence_regrade_apply.py — v9.21 §1-d 재계산표의 원장 반영 (도훈 승인 2026-08-24)
#
# ★왜 R 이 아니라 Python 인가 — **R 왕복이 원장을 변질시켰다(실측).**
#   구판 `essence_regrade_apply.R` 은 jsonlite `fromJSON(simplifyVector=FALSE)` →
#   `toJSON()` 왕복을 썼는데, 그 왕복이 JSON `null` 을 **`{}` (빈 객체)로 바꿨다**.
#   실측: 19개 파일의 `authoritative.dsr` 이 `null` → `{}` 로 조용히 변조됐다.
#   값-단위 대조(git HEAD vs 현재)로 잡아서 `git checkout` 으로 전량 롤백했다.
#   Python 의 json 은 None ↔ null 을 정확히 왕복한다. **원장에는 손실 없는 도구를 쓴다.**
#
# ★반영 원칙 = 병기(annotate)이지 덮어쓰기가 아니다.
#   원장은 역사다. 과거 L-code 의 `grade` 를 덮으면 "그때 그렇게 판정했다" 는 사실이 사라진다.
#   같은 날 개명에서 `factor_rotation` 을 enum 에 남긴 것과 같은 규약이다.
#
# 대상 2곳:
#   ① stage_artifacts/l_code/**/*.json  (strategy_id 조인)
#        + essence_grade / + essence_regrade{...}    · 기존 필드 전부 불변
#   ② 06_Registry/module_catalog.json
#        + meta.essence_grade / meta.essence_regrade_ref  ← run_alpha_search 6c 와 같은 자리
#
# 건드리지 않음: 기존 grade·grade_raw·score / .cache/lcode_corpus.json(캐시 — 사후 재생성)
#                qepm/mailbox/governor/book_state.json (도훈만 — 접근하지 않는다)
#
# 실행: essence_regrade_apply.py            # dry-run
#       essence_regrade_apply.py --apply    # 실반영
#==============================================================================
import io
import json
import os
import sys
import time
from collections import Counter

REF = "essence_regrade_20260824"


def root():
    for c in (os.environ.get("QM_ROOT", ""), os.getcwd()):
        if not c:
            continue
        c = c.replace("\\", "/")
        if os.path.exists(os.path.join(c, "CLAUDE.md")) and os.path.isdir(os.path.join(c, "06_Registry")):
            return c
    raise SystemExit("프로젝트 루트 해석 실패 — QM_ROOT 확인")


def load(p):
    with io.open(p, "r", encoding="utf-8-sig") as fh:
        return json.load(fh)


def save_atomic(p, obj):
    """★원자적 쓰기 — 선삭제 없이 tmp → replace. copy 폴백은 쓰지 않는다(절단원)."""
    tmp = p + ".tmp"
    with io.open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(obj, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, p)


def main(argv):
    apply_ = "--apply" in argv
    R = root()
    os.chdir(R)
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    print("[apply] 모드 = %s" % ("★실반영" if apply_ else "dry-run (기본)"))

    rg = load(os.path.join(R, "06_Registry", "essence_regrade_20260824.json"))
    rows = rg["rows"]
    by = {}
    for r in rows:
        sid = r.get("strategy_id")
        if sid:
            by[sid] = r
    print("[apply] 재계산표 %d행 · strategy_id 색인 %d건" % (len(rows), len(by)))

    def grade_of(r):
        """표의 'NA' 문자열은 **미발행**이지 등급이 아니다."""
        g = r.get("new_grade")
        return None if (g is None or g == "NA" or g == "") else g

    # ── ① L-code 원본 ────────────────────────────────────────────────────────
    base = os.path.join(R, "stage_artifacts", "l_code")
    files = []
    for dp, _dn, fn in os.walk(base):
        files += [os.path.join(dp, f) for f in fn if f.endswith(".json")]

    hit = 0
    nojoin = 0
    bad = 0
    dist = Counter()
    for f in files:
        try:
            y = load(f)
        except Exception:
            bad += 1
            continue
        r = by.get(y.get("strategy_id"))
        if not r:
            nojoin += 1
            continue
        eg = grade_of(r)
        dist["미발행" if eg is None else eg] += 1
        # ★기존 grade 는 손대지 않는다 — 그 값이 "발행 시점의 판정"이라는 사실이 근거다.
        y["essence_grade"] = eg
        y["essence_regrade"] = {
            "ref": REF,
            "applied_at": stamp,
            "basis": "essence_score.R (v9.21 권위 등급) — bt_result.rds 재채점",
            "grade_at_emit": y.get("grade"),          # 발행 시점 판정(불변 보존, 대조용 사본)
            "proxy_grade": r.get("proxy_grade"),
            "metric_type": r.get("metric_type"),
            "structural_drawdown": bool(r.get("structural_drawdown")),
            "port_t": r.get("port_t"), "net_ir": r.get("net_ir"),
            "calmar": r.get("calmar"), "mdd": r.get("mdd"),
            "note": ("판정 축 병기 — 기존 `grade` 는 발행 시점 기록으로 불변. "
                     "MDD 는 등급을 접지 않는다(2026-08-24): 구조 낙폭은 structural_drawdown 라벨로만 남는다."),
        }
        hit += 1
        if apply_:
            save_atomic(f, y)
    print("[apply] ① L-code 원본: 조인 %d / 전체 %d (미조인 %d · 판독실패 %d)"
          % (hit, len(files), nojoin, bad))
    print("        권위 등급 분포: " + " · ".join("%s %d" % kv for kv in sorted(dist.items())))

    # ── ② module_catalog ─────────────────────────────────────────────────────
    mcp = os.path.join(R, "06_Registry", "module_catalog.json")
    mc = load(mcp)
    mods = mc["modules"]
    mhit = 0
    mdist = Counter()
    for k, v in mods.items():
        r = by.get(v.get("strategy_id") or k)
        if not r:
            continue
        eg = grade_of(r)
        mdist["미발행" if eg is None else eg] += 1
        meta = v.get("meta")
        if not isinstance(meta, dict):
            meta = {}
            v["meta"] = meta
        # ★신규 등재가 쓰는 자리와 같은 필드(run_alpha_search 6c meta.essence_grade).
        #   backfill 과 신규가 다른 자리에 쌓이면 소비자가 둘 다 봐야 한다 = 드리프트 경로.
        meta["essence_grade"] = eg
        meta["essence_regrade_ref"] = REF
        meta["essence_regrade_at"] = stamp
        mhit += 1
    print("[apply] ② module_catalog: 조인 %d / 전체 %d" % (mhit, len(mods)))
    print("        권위 등급 분포: " + " · ".join("%s %d" % kv for kv in sorted(mdist.items())))
    if apply_:
        mc["last_updated"] = stamp
        mc["essence_regrade"] = {
            "ref": REF, "applied_at": stamp, "n_annotated": mhit,
            "note": "meta.essence_grade 병기. top-level grade 는 불변(발행 시점 기록).",
        }
        save_atomic(mcp, mc)

    print()
    print("[apply] " + ("★반영 완료 — 다음: 값-단위 검증 + corpus 캐시 재생성. "
                        "롤백 = git checkout (두 경로 모두 추적됨)."
                        if apply_ else
                        "dry-run 종료 — 실제 반영은 --apply. 아무것도 쓰지 않았다."))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
