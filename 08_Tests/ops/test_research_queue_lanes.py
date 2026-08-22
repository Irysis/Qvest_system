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

    print("== C 정렬 계약: 측정 백로그가 신규 적재보다 앞에 오는가 ==")
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
    if lanes and lanes[0] == "method_measure":
        ok("정렬 1순위 = method_measure (등재만 쌓이는 재발 방지)")
    else:
        ng("정렬 계약", "lanes=%s" % lanes[:4])
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("== t_summary: PASS=%d FAIL=%d ==" % (P, F))
sys.exit(1 if F else 0)
