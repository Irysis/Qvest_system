# -*- coding: utf-8 -*-
"""test_research_queue_lanes.py — 리서치 큐 레인 술어 양방향 검사 (2026-08-22 신설).

배선 배경 (도훈 결정 2026-08-22):
  ① "route=alpha 항목을 alpha-research 로"  ② "등재→측정 칸 지금 배선"

★이 검사가 지키는 두 계약:
  A. **이중 소비 금지** — 두 alpha 레인이 같은 논문을 각각 태우지 않을 것.
     ★해소 방식은 '구성상 서로소'가 **아니다**(초판의 오해). `alpha_pending()` 의 폴백이
     `route==alpha ∧ kr_feasible` 만으로 참이라 술어상 겹친다. 실제 해소는 **선점**:
     소비 기록을 공용 원장(alpha_search_queue_done.json)에 남기면 양쪽이 감산한다.
     ⇒ 검사도 '겹치지 않는다'가 아니라 '기록하면 양쪽에서 빠진다'를 잰다(A-5).
  B. **측정 큐가 자기 발화 조건을 잃지 않을 것** — measurement_status 가 채워지면 빠지고,
     blocked_by_capability 는 애초에 안 들어온다(매 런 실패하며 토큰 태우는 것 방지).

★양방향: 잡아야 할 것을 잡는지 + 잡지 말아야 할 것을 안 잡는지 둘 다 잰다.
"""
import io
import json
import os
import sys
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "ops"))
import research_pool_predicates as R  # noqa: E402

P = F = 0


def ok(m):
    global P
    P += 1
    print("  PASS  %s" % m)


def ng(m, d):
    global F
    F += 1
    print("  FAIL  %s :: %s" % (m, d))


def route_file(stage, date, papers):
    with io.open(os.path.join(stage, "alpha_search_route_%s.json" % date),
                 "w", encoding="utf-8") as fh:
        json.dump({"date": date, "papers": papers}, fh, ensure_ascii=False)


def registry(root, methods):
    d = os.path.join(root, "06_Registry")
    os.makedirs(d, exist_ok=True)
    with io.open(os.path.join(d, "method_registry.json"), "w", encoding="utf-8") as fh:
        json.dump({"methods": methods}, fh, ensure_ascii=False)


tmp = tempfile.mkdtemp()
try:
    stage = os.path.join(tmp, "stage")
    os.makedirs(stage, exist_ok=True)

    print("== A-1 양성 대조: KR 가능 + 팩터 미추출 논문이 alpha-research 로 가는가 ==")
    route_file(stage, "20260801", [
        # KR 가능한데 팩터가 아직 없음 → 가설 설계 필요 = QEPM 코어의 일
        {"id": "arxiv:2601.00001", "title": "mechanism only", "route": "alpha",
         "kr_feasible": True, "factor_candidate": None},
        # 팩터가 이미 있음 → 바로 백테 가능 = 경량 레인(alpha-search)
        {"id": "arxiv:2601.00002", "title": "testable factor", "route": "alpha",
         "kr_feasible": True, "factor_candidate": {"verdict": "testable"}},
        # 라우터가 KR 불가로 판정 → 가장 비싼 에이전트에 보내면 안 된다(초판 결함)
        {"id": "arxiv:2601.00004", "title": "not kr feasible", "route": "alpha",
         "kr_feasible": False, "factor_candidate": None},
    ])
    ar = {x["paper_id"] for x in R.alpha_research_pending(stage)}
    ok("KR가능+팩터부재 1건만") if ar == {"2601.00001"}         else ng("alpha-research 레인", "got=%s" % ar)

    print("== A-2 위반 주입: 팩터 보유분(경량 레인 소관)을 가져가지 않는가 ==")
    ok("factor_candidate 보유 → 제외") if "2601.00002" not in ar         else ng("팩터 보유분 제외", "경량 레인과 중복 처리")

    print("== A-3 위반 주입: kr_feasible=False 를 비싼 레인에 보내지 않는가 (초판 결함 회귀) ==")
    # ★초판은 'is_testable 여집합'이라 **이것만** 남았다 — 품질 순서가 뒤집힌 배선이었다.
    ok("KR 불가 판정분 제외") if "2601.00004" not in ar         else ng("품질 역전 회귀", "라우터가 KR 불가로 본 것을 QEPM 코어에 배분")

    print("== A-4 위반 주입: route!=alpha 는 안 잡는가 ==")
    route_file(stage, "20260802", [
        {"id": "arxiv:2601.00003", "title": "risk paper", "route": "risk",
         "kr_feasible": True, "factor_candidate": None}])
    ar2 = {x["paper_id"] for x in R.alpha_research_pending(stage)}
    ok("route=risk 는 alpha 레인에 없음") if "2601.00003" not in ar2         else ng("route 필터", "risk 논문이 alpha 레인에 유입")

    print("== A-5 이중 소비 해소: 공용 원장 기록이 경량 레인에서도 빠지게 하는가 ==")
    # ★두 레인은 술어상 겹친다(alpha_pending 의 폴백). 해소는 **선점** — 공용 원장에 남기면
    #   alpha_pending 이 감산하므로 같은 논문을 두 번 태우지 않는다.
    before_search = set(R.alpha_pending(stage).keys())
    with io.open(os.path.join(stage, "alpha_search_queue_done.json"),
                 "w", encoding="utf-8") as fh:
        json.dump({"processed": ["2601.00001"]}, fh)
    after_search = set(R.alpha_pending(stage).keys())
    after_ar = {x["paper_id"] for x in R.alpha_research_pending(stage)}
    if "2601.00001" in before_search and "2601.00001" not in after_search        and "2601.00001" not in after_ar:
        ok("공용 원장 기록 → 양 레인 모두에서 제거 (선점 성립)")
    else:
        ng("선점 해소", "search: %s→%s · ar=%s"
           % ("2601.00001" in before_search, "2601.00001" in after_search, after_ar))

    print("== B-1 양성 대조: measurement_status 빈 method 가 측정 큐에 뜨는가 ==")
    registry(tmp, [
        {"method_id": "M_NEED", "paper_id": "2601.10001", "verdict": "implemented"},
        {"method_id": "M_DONE", "paper_id": "2601.10002", "verdict": "implemented",
         "measurement_status": "측정 완료 — PORT_t 1.2 (미달)"},
        {"method_id": "M_BLOCKED", "paper_id": "2601.10003",
         "verdict": "blocked_by_capability", "blocker": "데이터 부재"},
    ])
    mm = {x["method_id"] for x in R.method_measure_pending(tmp)}
    ok("미측정 1건 포착") if mm == {"M_NEED"} else ng("측정 큐", "got=%s" % mm)

    print("== B-2 위반 주입: 측정 완료분을 다시 올리지 않는가 ==")
    ok("measurement_status 기입분 제외") if "M_DONE" not in mm \
        else ng("완료분 제외", "측정했는데 계속 큐에 남으면 무한 재측정")

    print("== B-3 위반 주입: blocked_by_capability 를 측정 큐에 넣지 않는가 ==")
    ok("blocked 제외 (매 런 실패 토큰낭비 방지)") if "M_BLOCKED" not in mm \
        else ng("blocked 제외", "구현 불가건을 측정하라고 올림")

    print("== B-4 위반 주입: 빈 문자열 measurement_status 를 '기입됨'으로 오인하지 않는가 ==")
    registry(tmp, [{"method_id": "M_EMPTY", "paper_id": "2601.10004",
                    "verdict": "implemented", "measurement_status": "   "}])
    mm2 = {x["method_id"] for x in R.method_measure_pending(tmp)}
    ok("공백만 있는 값은 미기입으로 처리") if "M_EMPTY" in mm2 \
        else ng("공백 처리", "공백을 기입으로 읽으면 영영 측정 안 됨")

    print("== E. 중단된 승격이 고아가 되지 않는가 ==")
    # ★2026-08-22 실사고: paper_promotion 이 wt_create → alpha-hypothesis 까지 하고 세션 한도로
    #   끊기면 alpha_hypothesis.json 만 남는다. 그러면 qepm_dossier(패키지 요구)도
    #   paper_promotion(이미 WT 참조)도 제외해 **어느 레인에도 안 잡히는 고아**가 된다.
    #   실측 3건(08-13 건은 9일 방치). 세션 한도·타임아웃마다 재발할 구조라 흡수가 필수다.
    def mkwt(root, name, files, phase, upd=""):
        d = os.path.join(root, "qepm", "mailbox", "worktask", name)
        os.makedirs(d, exist_ok=True)
        for f in files:
            io.open(os.path.join(d, f), "w", encoding="utf-8").write("{}")
        with io.open(os.path.join(d, "status.json"), "w", encoding="utf-8") as fh:
            json.dump({"current_phase": phase, "updated_at": upd}, fh)
        return d

    tmp2 = tempfile.mkdtemp()
    try:
        mkwt(tmp2, "WT-D20260822_900", ["alpha_hypothesis.json"], "SPEC_APPROVED", "2026-08-22")
        got = {x["wt_id"]: x for x in R.qepm_dossier_pending(tmp2)}
        if "WT-D20260822_900" in got and got["WT-D20260822_900"]["next_agent"] == "alpha-research":
            ok("가설만 있는 WT 흡수 → next=alpha-research")
        else:
            ng("고아 흡수", "got=%s" % list(got))

        print("== E2 위반 주입: 종결된 WT 는 흡수하지 않는가 ==")
        mkwt(tmp2, "WT-D20260822_901", ["alpha_hypothesis.json"], "ABORTED", "2026-08-22")
        got = {x["wt_id"] for x in R.qepm_dossier_pending(tmp2)}
        ok("ABORTED 제외") if "WT-D20260822_901" not in got             else ng("종결 제외", "중단·폐기된 WT 를 되살린다")

        print("== E3 정렬: 중단된 최신 승격이 legacy 보다 앞서는가 ==")
        mkwt(tmp2, "WT-D20260401_001", ["alpha_hypothesis.json", "alpha_package.json"],
             "ALPHA_DONE", "2026-04-01")
        os.makedirs(os.path.join(tmp2, "06_Registry"), exist_ok=True)
        io.open(os.path.join(tmp2, "06_Registry", "module_catalog.json"),
                "w", encoding="utf-8").write('{"modules": []}')
        st2 = os.path.join(tmp2, "stage"); os.makedirs(st2, exist_ok=True)
        q = R.research_queue_pending(st2, tmp2)
        dq = [x["wt_id"] for x in q if x["lane"] == "qepm_dossier"]
        if dq and dq[0] == "WT-D20260822_900":
            ok("중단 승격이 선두 (legacy 4월 건보다 앞)")
        else:
            ng("정렬", "선두=%s — 방금 끊긴 라운드가 뒤로 밀린다" % (dq[:2] or "없음"))
    finally:
        shutil.rmtree(tmp2, ignore_errors=True)

    print("== D. 승격 게이트: grade 통과분만 올리는가 ==")
    # ★2026-08-22 실측 결함: 라우터가 가치를 판정해도 QEPM 으로 올라가는 코드가 0 이었다
    #   (러너 4종 wt_create 0건 · grade B 3건 승격 0건). 이 게이트가 그 칸이다.
    def cat(root, mods):
        d = os.path.join(root, "06_Registry"); os.makedirs(d, exist_ok=True)
        with io.open(os.path.join(d, "module_catalog.json"), "w", encoding="utf-8") as fh:
            json.dump({"modules": mods}, fh, ensure_ascii=False)

    cat(tmp, [
        {"strategy_id": "STR_AS_B1", "grade": "B", "meta": {"strategy_idea": "b one"}},
        {"strategy_id": "STR_AS_A1", "grade": "A", "meta": {"strategy_idea": "a one"}},
        {"strategy_id": "STR_AS_C1", "grade": "C", "meta": {"strategy_idea": "c one"}},
        {"strategy_id": "STR_AS_F1", "grade": "F", "meta": {"strategy_idea": "f one"}},
    ])
    got = {x["strategy_id"] for x in R.promotion_pending(tmp)}
    ok("grade A·B 만 승격 대상 (%d건)" % len(got)) if got == {"STR_AS_B1", "STR_AS_A1"}         else ng("등급 필터", "got=%s" % got)

    print("== D2 위반 주입: 오염 라벨이 붙은 등급을 신뢰하지 않는가 ==")
    cat(tmp, [
        {"strategy_id": "STR_AS_B2", "grade": "B", "grade_contaminated": True, "meta": {}},
        {"strategy_id": "STR_AS_B3", "grade": "B", "label_contaminated": True, "meta": {}},
        {"strategy_id": "STR_AS_B4", "grade": "B", "meta": {}},
    ])
    got = {x["strategy_id"] for x in R.promotion_pending(tmp)}
    ok("오염 라벨 2건 제외 → 청정 1건만") if got == {"STR_AS_B4"}         else ng("오염 제외", "got=%s — 등급 자체를 신뢰할 수 없는 건을 승격")

    print("== D3 위반 주입: 이미 WT 가 참조하는 전략을 중복 승격하지 않는가 ==")
    wt = os.path.join(tmp, "qepm", "mailbox", "worktask", "WT-D20990101_001")
    os.makedirs(wt, exist_ok=True)
    with io.open(os.path.join(wt, "request.json"), "w", encoding="utf-8") as fh:
        json.dump({"discovery_of": "STR_AS_B4", "note": "already promoted"}, fh)
    got = {x["strategy_id"] for x in R.promotion_pending(tmp)}
    ok("WT 참조분 제외 → 승격 0건") if not got         else ng("중복 승격 방지", "got=%s — 같은 전략으로 WT 를 또 만든다" % got)

    print("== D4 양성 대조: 참조가 사라지면 다시 대상이 되는가 (과잉 배제 방지) ==")
    with io.open(os.path.join(wt, "request.json"), "w", encoding="utf-8") as fh:
        json.dump({"note": "unrelated"}, fh)
    got = {x["strategy_id"] for x in R.promotion_pending(tmp)}
    ok("참조 없음 → 재대상화") if got == {"STR_AS_B4"}         else ng("과잉 배제", "got=%s" % got)

    print("== C 정렬 계약: 이어붙이기가 새로 쌓기보다 앞에 오는가 ==")
    registry(tmp, [{"method_id": "M_NEED", "paper_id": "2601.10001",
                    "verdict": "implemented"}])
    os.makedirs(os.path.join(stage), exist_ok=True)
    with io.open(os.path.join(stage, "mode_queue_20260801.json"), "w",
                 encoding="utf-8") as fh:
        json.dump({"date": "20260801", "optimizer": [
            {"id": "2601.20001", "title": "opt paper", "screen_priority": "⭐⭐"}],
            "risk": [], "regime": []}, fh, ensure_ascii=False)
    q = R.research_queue_pending(stage, tmp)
    lanes = [x["lane"] for x in q]
    # 계약: 진행 중인 것을 잇는 레인(qepm_dossier · paper_promotion)이
    #   새로 쌓는 레인(method_measure · alpha · opt/risk/regime)보다 항상 앞.
    _ADVANCE = ("qepm_dossier", "paper_promotion")
    _ACCUM = ("method_measure", "alpha", "optimizer", "risk", "regime")
    first_accum = next((i for i, l in enumerate(lanes) if l in _ACCUM), len(lanes))
    last_adv = max((i for i, l in enumerate(lanes) if l in _ADVANCE), default=-1)
    if last_adv < first_accum:
        ok("이어붙이기 레인이 전부 앞선다 (선두=%s)" % (lanes[0] if lanes else "-"))
    else:
        ng("정렬 계약", "lanes=%s — 새로 쌓기가 이어붙이기를 앞질렀다" % lanes[:5])
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("== t_summary: PASS=%d FAIL=%d ==" % (P, F))
print('{"test":"research_queue_lanes","pass":%d,"fail":%d,"total":%d,"skipped":0}' % (P, F, (P)+(F)))
sys.exit(1 if F else 0)
