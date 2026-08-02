#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""위반 주입 테스트 — distilled 재등재 supersede (2026-08-02).

대상: 02_Infrastructure/axiom/cluster_extractor.py::supersede_subsumed
      (+ build_distilled 배선 — 재등재 지점에서 실제로 도는지)

왜 있나(실사고): distilled 백로그 pending_5axis 가 07-17 49건 → 08-02 89건. 완전 중복은
  0건인데 **부분집합 쌍이 30건** — 같은 클러스터가 supporting L-code 성장 시 새 dist_id 로
  재등재되면서 구 카드가 회수되지 않았다. 08-02 에 엄격 기준으로 9건 수동 회수(89→80).
  수동이라 다음 harvest/cluster 사이클에 다시 쌓인다 → 엔진에 배선.

★검사 설계 원칙 — 오탐 제거와 검사 사망은 겉보기가 같다:
  이 파일의 절반은 **돌연변이 축(M*)** 이다. 각 게이트를 하나씩 무력화해 "막고 있던 판정이
  실제로 뒤집히는지"를 매 실행 실측한다. 그 대조가 없으면 "회수 0건"이 건강인지 계측
  사망인지 구별할 수 없다(현 저장소 실측: 08-02 이후 추가 회수 대상 0건 — 즉 정상 경로만
  돌리면 이 검사는 **아무것도 안 해도 초록**이다. M 축이 유일한 생존 지문).

축:
  A  진부분집합 ∧ 전 필드 동일        → supersede 발화 (+ 사유 형식/파일 보존)
  B  family/polarity/type/mode 상이   → 회수 안 함 (오탐 통제)
  C  구 카드 전용 L-code 존재         → 회수 안 함 + 경고 (지식 손실 0)
  D  distilled/promoted/quarantined   → 건드리지 않음 (활성 카드 자동 회수 금지)
  G  빈 멤버·체인·멱등                 → ∅⊂N 공허 회수 차단 / superseded_by 가 회수 대상을
                                        가리키지 않음 / 재실행 무변경
  M  돌연변이(검사 사망 통제)          → 로직·게이트를 끄면 A/B/C/D 가 뒤집히는가
실행: "$QVEST_PY" 08_Tests/axiom/test_distilled_supersede.py
"""
import glob
import json
import os
import re
import shutil
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))


def _proj_root() -> str:
    """self-first 앵커 + 표지 검증. env-first 로 잡으면 worktree 에서 돌린 검사가
    main 의 코드를 검사한다(08-02 실사고: 러너 4종 env-first → 17건 은폐)."""
    marker = os.path.join("02_Infrastructure", "axiom", "cluster_extractor.py")
    for c in (os.path.dirname(os.path.dirname(_HERE)),
              os.environ.get("CLAUDE_PROJECT_DIR", ""),
              os.environ.get("QM_ROOT", ""), os.getcwd()):
        if c and os.path.isfile(os.path.join(c, marker)):
            return os.path.abspath(c)
    raise SystemExit("PROJECT_ROOT 해석 실패 — 표지 '%s' 를 가진 후보 없음" % marker)


ROOT = _proj_root()
sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "axiom"))
import cluster_extractor as ce  # noqa: E402

CK = ce._cluster_key
_fail = []
_pass = 0


def check(cond, msg):
    global _pass
    if cond:
        _pass += 1
        print("  PASS — %s" % msg)
    else:
        _fail.append(msg)
        print("  FAIL — %s" % msg)


# ────────────────────────── 픽스처 ──────────────────────────
def wdist(dd, dist_id, members, status="pending_5axis", mode="test_mode",
          pol="negative", typ="empirical", family="test_family", **extra):
    d = {
        "schema_version": "distilled_v1", "dist_id": dist_id,
        "cluster_key": CK(list(members)), "candidate_id": "CAND_seed_%s" % dist_id,
        "status": status, "statement_refined": None, "retry_condition": None,
        "refined_at": None, "refined_by": None, "promoted_to_axiom": None,
        "created_at": "2026-07-01T00:00:00+00:00",
        "updated_at": "2026-07-01T00:00:00+00:00",
        "research_mode": mode, "polarity": pol, "type": typ,
        "metric_type": "backtested", "supporting_l_codes": list(members),
        "cluster_members_count": len(members),
        "scope_draft": {"market": "KR", "factor_family": family},
    }
    d.update(extra)
    with open(os.path.join(dd, dist_id + ".json"), "w", encoding="utf-8") as fh:
        json.dump(d, fh, indent=2, ensure_ascii=False)
    return d


def wcand(cd, tag, members, mode="test_mode", pol="negative",
          typ="empirical", family="test_family"):
    c = {"candidate_id": "CAND_%s" % tag, "research_mode": mode, "polarity": pol,
         "type": typ, "metric_type": "backtested", "statement_draft": "[draft] %s" % tag,
         "supporting_l_codes": list(members), "cluster_members_count": len(members),
         "scope_draft": {"market": "KR", "factor_family": family}}
    with open(os.path.join(cd, "CAND_%s.json" % tag), "w", encoding="utf-8") as fh:
        json.dump(c, fh, indent=2, ensure_ascii=False)


def load(dd, dist_id):
    with open(os.path.join(dd, dist_id + ".json"), encoding="utf-8") as fh:
        return json.load(fh)


def mkdirs(tmp, tag):
    cd = os.path.join(tmp, tag, "cand")
    dd = os.path.join(tmp, tag, "dist")
    os.makedirs(cd)
    os.makedirs(dd)
    return cd, dd


# 08-02 수동 회수 9건의 사유 형식 — 이력 검색(`superseded_by=`) 일관성 계약.
REASON_RE = re.compile(
    r"^superseded_by=(DIST-\S+) — 같은 클러스터\(family/polarity/type/mode 동일\)의 "
    r"supporting L-code 진부분집합\. 지식 손실 0 검증 통과"
    r"\(구 카드 L-code 전량이 \1에 포함\)\.")


# ────────────────────────── A: 발화 + 배선 ──────────────────────────
def axis_A(tmp):
    print("\n[A] 진부분집합 ∧ 전 필드 동일 → supersede (build_distilled 배선 경유)")
    cd, dd = mkdirs(tmp, "A")
    wdist(dd, "DIST-XX-001", ["a1", "a2"])                    # 구 카드(고아 — CAND 없음)
    wdist(dd, "DIST-XX-002", ["a1", "a2", "a3"])              # 신 카드
    wcand(cd, "grown", ["a1", "a2", "a3"])                    # 성장 클러스터만 live CAND
    idx = os.path.join(tmp, "A", "idx.json")
    # ★배선 단언: supersede_subsumed 를 직접 부르지 않는다 — 재등재 지점(build_distilled)이
    #   실제로 호출하는지가 이 축의 본체다(모듈만 초록이고 소비자가 안 부르는 상태 차단).
    ce.build_distilled(cd, dd, idx)
    o, n = load(dd, "DIST-XX-001"), load(dd, "DIST-XX-002")
    check(o["status"] == "expired", "A1 구 카드 status=expired")
    check(o.get("superseded_by") == "DIST-XX-002", "A2 superseded_by=신 카드 id")
    m = REASON_RE.match(o.get("expire_reason") or "")
    check(bool(m), "A3 expire_reason 이 08-02 수동 회수와 동일 형식")
    check(o.get("expired_at"), "A4 expired_at 기록")
    check(os.path.isfile(os.path.join(dd, "DIST-XX-001.json")),
          "A5 카드 파일 보존(삭제 금지 — 이력 유지)")
    check(sorted(o.get("supporting_l_codes") or []) == ["a1", "a2"],
          "A6 구 카드 supporting_l_codes 원형 보존")
    check(n["status"] == "pending_5axis", "A7 신 카드 무변경")
    # 인덱스가 회수를 반영했는가 (소비면 도달)
    ix = json.load(open(idx, encoding="utf-8"))
    st = {e["dist_id"]: e["status"] for e in ix["entries"]}
    check(st.get("DIST-XX-001") == "expired", "A8 통합 인덱스에 expired 반영")


# ────────────────────────── B: 오탐 통제 ──────────────────────────
def axis_B(tmp):
    print("\n[B] 정체성 상이 → 회수 안 함 (family/polarity/type/mode 각각)")
    cd, dd = mkdirs(tmp, "B")
    wdist(dd, "DIST-XX-010", ["b1", "b2"], family="famA")
    wdist(dd, "DIST-XX-011", ["b1", "b2", "b3"], family="famB")
    wdist(dd, "DIST-XX-012", ["c1", "c2"], pol="negative")
    wdist(dd, "DIST-XX-013", ["c1", "c2", "c3"], pol="mixed")
    wdist(dd, "DIST-XX-014", ["d1", "d2"], typ="empirical")
    wdist(dd, "DIST-XX-015", ["d1", "d2", "d3"], typ="methodological")
    wdist(dd, "DIST-XX-016", ["e1", "e2"], mode="mode_a")
    wdist(dd, "DIST-XX-017", ["e1", "e2", "e3"], mode="mode_b")
    res = ce.supersede_subsumed(dd, verbose=False)
    for did, lbl in (("DIST-XX-010", "family"), ("DIST-XX-012", "polarity"),
                     ("DIST-XX-014", "type"), ("DIST-XX-016", "research_mode")):
        check(load(dd, did)["status"] == "pending_5axis",
              "B %s 상이 → 회수 안 함" % lbl)
    check(len(res["superseded"]) == 0, "B5 회수 0건")
    _ = cd


# ────────────────────────── C: 지식 손실 0 ──────────────────────────
def axis_C(tmp):
    print("\n[C] 구 카드 전용 L-code 존재 → 회수 안 하고 경고")
    cd, dd = mkdirs(tmp, "C")
    wdist(dd, "DIST-XX-020", ["k1", "kX"])                    # kX 는 신 카드에 없음
    wdist(dd, "DIST-XX-021", ["k1", "k2", "k3"])
    res = ce.supersede_subsumed(dd, verbose=False)
    check(load(dd, "DIST-XX-020")["status"] == "pending_5axis",
          "C1 지식 손실 시 회수 안 함")
    check(len(res["superseded"]) == 0, "C2 회수 0건")
    lossy = [(a, b, l) for a, b, l in res["warn_lossy"]
             if a == "DIST-XX-020" and b == "DIST-XX-021"]
    check(len(lossy) == 1, "C3 경고 발행(warn_lossy 1건)")
    check(bool(lossy) and lossy[0][2] == ["kX"], "C4 경고가 손실 L-code 지목(kX)")
    _ = cd


# ────────────────────────── D: 활성/격리 카드 보호 ──────────────────────────
def axis_D(tmp):
    print("\n[D] distilled/promoted/quarantined → 건드리지 않음")
    cd, dd = mkdirs(tmp, "D")
    wdist(dd, "DIST-XX-030", ["p1", "p2"], status="distilled",
          statement_refined="승인 정제문", refined_at="2026-07-01T00:00:00+0900")
    wdist(dd, "DIST-XX-031", ["p1", "p2", "p3"])
    wdist(dd, "DIST-XX-032", ["q1", "q2"], status="promoted",
          promoted_to_axiom="AX-999")
    wdist(dd, "DIST-XX-033", ["q1", "q2", "q3"])
    wdist(dd, "DIST-XX-034", ["r1", "r2"], status="quarantined_evidence")
    wdist(dd, "DIST-XX-035", ["r1", "r2", "r3"])
    # 승계 카드가 격리분이면 그 근거로 남의 카드를 회수하지 못한다(오염 전파 차단)
    wdist(dd, "DIST-XX-036", ["s1", "s2"])
    wdist(dd, "DIST-XX-037", ["s1", "s2", "s3"], status="quarantined_evidence")
    # 저술 지식 보유(proposed 초안) → 회수 금지 + 경고
    wdist(dd, "DIST-XX-038", ["t1", "t2"], status="proposed",
          statement_refined="초안 정제문", frontier=["미탐색 인접경로"])
    wdist(dd, "DIST-XX-039", ["t1", "t2", "t3"])
    # status=distilled 인데 저술 지식이 없는 경계 — status 게이트 단독 실효 확인용
    wdist(dd, "DIST-XX-040", ["u1", "u2"], status="distilled")
    wdist(dd, "DIST-XX-041", ["u1", "u2", "u3"])
    res = ce.supersede_subsumed(dd, verbose=False)
    check(load(dd, "DIST-XX-030")["status"] == "distilled", "D1 distilled 무변경")
    check(load(dd, "DIST-XX-030").get("statement_refined") == "승인 정제문",
          "D2 distilled 정제문 보존")
    check(load(dd, "DIST-XX-032")["status"] == "promoted", "D3 promoted 무변경")
    check(load(dd, "DIST-XX-034")["status"] == "quarantined_evidence",
          "D4 quarantined 무변경")
    check(load(dd, "DIST-XX-036")["status"] == "pending_5axis",
          "D5 승계 후보가 quarantined 면 회수 안 함(오염 전파 차단)")
    check(load(dd, "DIST-XX-038")["status"] == "proposed",
          "D6 저술 지식(proposed 초안) 보유분 회수 안 함")
    check(any(a == "DIST-XX-038" for a, _b, _f in res["warn_authored"]),
          "D7 저술 지식 보유분 경고 발행")
    check(load(dd, "DIST-XX-040")["status"] == "distilled",
          "D8 distilled(저술 지식 없음)도 status 게이트로 보호")
    check(len(res["superseded"]) == 0, "D9 회수 0건")
    _ = cd


# ────────────────────────── G: 구조 가드 ──────────────────────────
def axis_G(tmp):
    print("\n[G] 빈 멤버 / 체인 / 멱등")
    cd, dd = mkdirs(tmp, "G")
    wdist(dd, "DIST-XX-050", [])                              # 멤버 0건 — ∅⊂N 공허 회수 차단
    wdist(dd, "DIST-XX-051", ["v1", "v2"])
    wdist(dd, "DIST-XX-052", ["h1", "h2"])                    # 체인 A ⊂ B ⊂ C
    wdist(dd, "DIST-XX-053", ["h1", "h2", "h3"])
    wdist(dd, "DIST-XX-054", ["h1", "h2", "h3", "h4"])
    res = ce.supersede_subsumed(dd, verbose=False)
    check(load(dd, "DIST-XX-050")["status"] == "pending_5axis",
          "G1 멤버 0건 카드는 회수 대상 아님(∅⊂N 공허 회수 차단)")
    a, b, c = (load(dd, "DIST-XX-052"), load(dd, "DIST-XX-053"),
               load(dd, "DIST-XX-054"))
    check(a["status"] == "expired" and b["status"] == "expired",
          "G2 체인 중간·하단 회수")
    check(c["status"] == "pending_5axis", "G3 체인 최상위 생존")
    check(a.get("superseded_by") == "DIST-XX-054" and
          b.get("superseded_by") == "DIST-XX-054",
          "G4 superseded_by 가 회수 대상이 아닌 최대 superset 를 가리킴")
    check(len(res["superseded"]) == 2, "G5 회수 2건")
    # 멱등: 재실행 시 추가 회수 0 + 기록 불변
    snap = {k: load(dd, k) for k in ("DIST-XX-052", "DIST-XX-053", "DIST-XX-054")}
    res2 = ce.supersede_subsumed(dd, verbose=False)
    check(len(res2["superseded"]) == 0, "G6 재실행 추가 회수 0건(멱등)")
    check(all(load(dd, k) == v for k, v in snap.items()),
          "G7 재실행 시 카드 내용 불변")
    _ = cd


# ────────────────────────── M: 돌연변이 (검사 사망 통제) ──────────────────────────
def _mutate(attr, value):
    """ce 모듈 속성을 임시 교체하는 컨텍스트."""
    class _Ctx:
        def __enter__(self):
            self.old = getattr(ce, attr)
            setattr(ce, attr, value)

        def __exit__(self, *a):
            setattr(ce, attr, self.old)
    return _Ctx()


def axis_M(tmp):
    print("\n[M] 돌연변이 — 게이트를 끄면 판정이 뒤집히는가 (검사 사망 통제)")

    # M1: supersede 패스 자체를 끈 build_distilled → A 축이 발화하지 않아야 한다.
    #     (A 축의 PASS 가 정말 이 로직에서 온 것인지의 대조. 안 뒤집히면 A 는 공허하다.)
    cd, dd = mkdirs(tmp, "M1")
    wdist(dd, "DIST-XX-001", ["a1", "a2"])
    wdist(dd, "DIST-XX-002", ["a1", "a2", "a3"])
    wcand(cd, "grown", ["a1", "a2", "a3"])
    with _mutate("supersede_subsumed",
                 lambda *a, **k: {"superseded": [], "warn_lossy": [], "warn_authored": [],
                                  "skipped_protected": [], "warn_recheck": []}):
        ce.build_distilled(cd, dd, os.path.join(tmp, "M1", "idx.json"))
    check(load(dd, "DIST-XX-001")["status"] == "pending_5axis",
          "M1 로직 제거 시 A 축 미발화 — A 의 PASS 는 이 로직에서 온 것")

    # M2: 정체성 게이트 무력화 → B 축(family 상이)이 회수돼야 한다.
    cd, dd = mkdirs(tmp, "M2")
    wdist(dd, "DIST-XX-010", ["b1", "b2"], family="famA")
    wdist(dd, "DIST-XX-011", ["b1", "b2", "b3"], family="famB")
    with _mutate("_dist_identity", lambda d: None):
        ce.supersede_subsumed(dd, verbose=False)
    check(load(dd, "DIST-XX-010")["status"] == "expired",
          "M2 정체성 게이트 제거 시 B 축 회수됨 — B 를 막던 것이 그 게이트임")

    # M3: 구 카드 전용 L-code 를 지우면 C 축이 회수돼야 한다.
    #     (= C 를 막던 것이 '지식 손실 0' 검증이었음의 대조)
    cd, dd = mkdirs(tmp, "M3")
    wdist(dd, "DIST-XX-020", ["k1", "kX"])
    wdist(dd, "DIST-XX-021", ["k1", "k2", "k3"])
    _orig_members = ce._dist_members
    with _mutate("_dist_members",
                 lambda d: frozenset(x for x in _orig_members(d) if x != "kX")):
        ce.supersede_subsumed(dd, verbose=False)
    check(load(dd, "DIST-XX-020")["status"] == "expired",
          "M3 손실 L-code 제거 시 C 축 회수됨 — C 를 막던 것이 손실 검증임")

    # M4: status 보호 게이트 무력화 → D8(distilled, 저술 지식 없음)이 회수돼야 한다.
    cd, dd = mkdirs(tmp, "M4")
    wdist(dd, "DIST-XX-040", ["u1", "u2"], status="distilled")
    wdist(dd, "DIST-XX-041", ["u1", "u2", "u3"])
    with _mutate("_SUPERSEDE_PROTECTED", ()):
        with _mutate("_SUPERSEDE_AUTO_STATUSES", ("pending_5axis", "proposed", "distilled")):
            ce.supersede_subsumed(dd, verbose=False)
    check(load(dd, "DIST-XX-040")["status"] == "expired",
          "M4 status 게이트 제거 시 distilled 회수됨 — D8 을 막던 것이 그 게이트임")

    # M5: 저술 지식 게이트 무력화 → D6(proposed + 정제 초안)이 회수돼야 한다.
    cd, dd = mkdirs(tmp, "M5")
    wdist(dd, "DIST-XX-038", ["t1", "t2"], status="proposed",
          statement_refined="초안 정제문", frontier=["미탐색 인접경로"])
    wdist(dd, "DIST-XX-039", ["t1", "t2", "t3"])
    with _mutate("_SUPERSEDE_AUTHORED_FIELDS", ()):
        ce.supersede_subsumed(dd, verbose=False)
    check(load(dd, "DIST-XX-038")["status"] == "expired",
          "M5 저술 지식 게이트 제거 시 proposed 초안 회수됨 — D6 을 막던 것이 그 게이트임")
    _ = cd


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="dist_supersede_")
    try:
        for fn in (axis_A, axis_B, axis_C, axis_D, axis_G, axis_M):
            fn(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    total = _pass + len(_fail)
    print("\n" + "=" * 74)
    if _fail:
        print("실패 %d건:" % len(_fail))
        for m in _fail:
            print("  - %s" % m)
    print("PASS %d / FAIL %d / TOTAL %d" % (_pass, len(_fail), total))
    # run_all_hooks.sh 집계용 요약 라인 — 없으면 러너가 UNREPORTED(=1 fail)로 계상한다.
    print(json.dumps({"test": "distilled_supersede", "pass": _pass,
                      "fail": len(_fail), "total": total}))
    return 1 if _fail else 0


if __name__ == "__main__":
    sys.exit(main())
