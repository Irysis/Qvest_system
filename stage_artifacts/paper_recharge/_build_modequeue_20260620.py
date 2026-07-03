#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json, io
TODAY="20260620"
route=json.load(open(f"stage_artifacts/paper_recharge/alpha_search_route_{TODAY}.json",encoding="utf-8"))
papers=route["papers"]
mq={"date":TODAY,"optimizer":[],"risk":[],"regime":[]}
for p in papers:
    r=p["route"]
    if r not in ("optimizer","risk","regime"): continue
    item={"title":p["title"],"id":p["id"],"source":"arxiv","reason":p["reason"]}
    if r=="optimizer":
        item["memo"]="α̂ 고정 A/B (PG2) 대상 — 가중/배분법"
    else:
        item["memo"]="분석 flag — risk/regime 진단 소비"
    mq[r].append(item)
op=f"stage_artifacts/paper_recharge/mode_queue_{TODAY}.json"
with io.open(op,"w",encoding="utf-8") as fh:
    json.dump(mq,fh,ensure_ascii=False,indent=1)
print("WROTE",op,"opt",len(mq["optimizer"]),"risk",len(mq["risk"]),"regime",len(mq["regime"]))

# curated history: no new curated today (all 15 already processed). bump last_run only.
cr=json.load(open("stage_artifacts/paper_recharge/curated_routed.json",encoding="utf-8"))
before=len(cr["processed"])
cr["last_run"]=TODAY
with io.open("stage_artifacts/paper_recharge/curated_routed.json","w",encoding="utf-8") as fh:
    json.dump(cr,fh,ensure_ascii=False,indent=2)
print("curated processed",before,"new today 0; last_run ->",TODAY)
