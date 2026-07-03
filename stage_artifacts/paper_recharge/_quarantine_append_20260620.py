#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json, io, os
TODAY="20260620"
qp=f"stage_artifacts/paper_recharge/auto_quarantine_{TODAY}.json"
v=json.load(open("stage_artifacts/paper_recharge/auto_verify_2606_08569.json",encoding="utf-8"))
rec={"paper_id":v["paper_id"],"strategy_name":v["strategy_name"],
     "gate_decision":v.get("gate_decision"),"gate_failed_layers":v.get("gate_failed_layers"),
     "grade":v.get("grade"),"oos_retention":v.get("oos_retention"),"port_t":v.get("port_t"),
     "reason":"양방향 long-only 모두 KR alpha 부재(A: IR -0.62/FF3 alpha -3.4%·t -1.60 음의 알파; B: Grade F structural-drawdown MDD 66.7%·oos 0.26). robustness_pass=false(A oos 1.31은 ~0.2 Sharpe·음IR series의 공허한 retention; screen_pass=FALSE라 forge PORT_t 미산출). 논문 자체 보고한 시장간 부호불안정(SSE↔SP500) KR서 재현. 충실구현(논문 binomial p-index eq.6-8, 폴백無) 확인.",
     "verify_json":"stage_artifacts/paper_recharge/auto_verify_2606_08569.json"}
arr=[]
if os.path.exists(qp):
    try: arr=json.load(open(qp,encoding="utf-8"))
    except: arr=[]
if not isinstance(arr,list): arr=[]
arr.append(rec)
with io.open(qp,"w",encoding="utf-8") as fh:
    json.dump(arr,fh,ensure_ascii=False,indent=1)
print("WROTE",qp,"n=",len(arr))
print("decision",rec["gate_decision"],"failed",rec["gate_failed_layers"])
