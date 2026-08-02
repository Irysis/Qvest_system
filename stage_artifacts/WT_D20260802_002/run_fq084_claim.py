import json, io, sys
P = r"C:\Users\99922\OneDrive\Quant_Module_Moltbot\06_Registry\alpha_frontier_queue.json"
d = json.load(io.open(P, encoding="utf-8"))
hit = 0
for e in d["entries"]:
    if e.get("id") == "FQ-084":
        e["owner"] = "alpha-research WT-D20260802_002 (2026-08-02)"
        e["status"] = "in_flight"
        e["next_action"] = ("착수됨 — 공매도(F1) 실파일 0건으로 외국인 단독 설계로 축소. "
                            "게이트 = FA_share_3m(|외국인 순매수|/거래대금, 방향불변) 상위 50%. "
                            "base = cleanT1 production_parity_verified 패널(신호 불변). "
                            "대조군 4종(유동성 matched / size matched / size-neutral gate / random placebo) 필수. "
                            "사전등록: stage_artifacts/WT_D20260802_002/preregistration.json")
        e["scope_note"] = ("공매도 축 미포함 — F1_short_interest_lending 실파일 0건(KRX OPEN API 404 / MDC 로그인 게이트). "
                           "논문 원안(net arbitrage = 외국인 + 공매도)의 절반만 검정한다. 반쪽 결과를 전체 검증으로 인용 금지.")
        hit += 1
if hit != 1:
    sys.exit("FQ-084 entry not found exactly once: %d" % hit)
d["updated"] = "2026-08-02"
with io.open(P, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print("FQ-084 claimed: in_flight")
