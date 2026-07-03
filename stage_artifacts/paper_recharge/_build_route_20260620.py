#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json, io, sys
TODAY="20260620"
disc=json.load(open(f"stage_artifacts/paper_recharge/mcp_discovery_{TODAY}.json",encoding="utf-8"))
cand=disc.get("candidates",[])

# routing decisions keyed by index -> (route, kr_feasible, reason, factor)
# factor = None or dict(name,def,novel,kr_feasible,verdict,confidence)
R={}
def f(name,defn,novel,krf,verdict,conf):
    return {"name":name,"def":defn,"novel":novel,"kr_feasible":krf,"verdict":verdict,"confidence":conf}

R[0]=("skip",False,"멀티에이전트/다체계 일반이론(power·response 함수→거시질서). 종목신호·포트구성법 아님",None)
R[1]=("risk",False,"현재 추세강도로 미래 변동성·상관 예측(2차다항) — 공분산/리스크 forecasting. 추세=모멘텀 기존팩터 중복이라 신규팩터 아님",None)
R[2]=("skip",False,"투자은행 리스크계산 무결성 실시간 이상탐지(EQAF) — 운영리스크/데이터품질, 포트 risk model 아님",None)
R[3]=("skip",False,"RAG+지식그래프 LLM 이코노미스트 에이전트 — LLM 프레임워크",None)
R[4]=("optimizer",False,"팩터모델 성과가 test-asset 구성(선택·가중·보유·리밸)에 의존 — 포트 구성/가중 discipline. optimizer 구성민감도 소스",None)
R[5]=("skip",False,"DeFi 리스크 감독 에이전트 — crypto/탈중앙금융",None)
R[6]=("risk",False,"S&P 다일누적수익 tempered Skew-t 적합 — 꼬리분포 모델링(횡단면 종목신호 아님)",None)
R[7]=("skip",False,"CAP slope=Bayes 정리, weight-of-evidence/Somers' D — 신용스코어 보정 방법론(주식 아님)",None)
R[8]=("risk",False,"꼬리별(상/하단) 보장 conformal 예측구간 — uncertainty-aware 커버리지(risk/예측불확실성 방법)",None)
R[9]=("skip",False,"Agentic AI POMDP 모델검증 — LLM 에이전트 거버넌스",None)
R[10]=("skip",False,"skew-elliptical t 옵션 포트 SR/Return-VaR 최대화 — 옵션/파생 포트(KR 미적용)",None)
R[11]=("regime",False,"Transformer 1-step 지수 예측(VN30/S&P) + SDA 증강 — 지수레벨 타이밍 소스(저확신, 배포룰 아님)",None)
R[12]=("skip",False,"LLM-추론 베이지안 상태필터로 Agentic AI 리스크 정량화 — LLM 에이전트",None)
R[13]=("optimizer",False,"declining CVaR glidepath 목표수익형 TDF — CVaR-제약 포트 구성법(optimizer)",None)
R[14]=("optimizer",False,"Schur complement 댐핑 1파라미터로 HRP↔min-variance 보간 — 포트 배분(optimizer 강적합)",None)
R[15]=("skip",False,"fractional Gaussian 합성우도 추정 + Godambe 부분집합 설계 — 추정이론(직접 포트응용 부재)",None)
R[16]=("optimizer",False,"drift 모호성+학습 하 평균-분산 최적화 — robust/ambiguity MVO(optimizer)",None)
R[17]=("optimizer",False,"15개 딥/통계 TS 모델 equity 벤치 + 제약 quadratic 포트 layer + deployment-adjusted acceptability — 단일알파 아님, 구현/optimizer discipline",None)
R[18]=("risk",False,"단일 외생충격→다변량 스트레스 시나리오 역설계(reverse stress test) — risk 스트레스",None)
R[19]=("optimizer",False,"BAVAR-BLED(베이지안VAR+타원형 Black-Litterman) TD3 DRL 배분, regime/heavy-tail 대응 — 배분방법(optimizer)",None)
R[20]=("regime",False,"성장-방어 슬리브 위 연속 현금-오버레이(slow-tail+V-shape 크래시 브레이크, walk-forward) — 오버레이/타이밍(regime)",None)
R[21]=("alpha",False,"횡단면 위상 이상치 점수 intraday 수익예측(S&P 10종목) — 횡단면이나 intraday tick/Takens 임베딩 필수 → KR 일별 RAWDATA로 불가",
       f("xsec_topological_anomaly_score","종목별 intraday bar Takens delay 임베딩→BallMapper 그래프→decoder-conditional VAE 점수(시장+peer 조건부 위상 이상치)",True,False,"infeasible","medium"))
R[22]=("alpha",True,"p-index=δ목표수익을 만기T(1주~1개월)에 보장하는 1달러당 다운사이드 보험료(유럽형 put 공정가 합성, 옵션시장데이터 불요). p-ratio efficiency로 종목 efficient/inefficient 분류 후 momentum/contrarian 결합. 가격+과거σ+무위험금리(FRED/ECOS)로 PIT 합성가능",
       f("p_index_fair_downside_insurance","종목별 fair-price put-insurance 비용: K=S0*(1+δ) 유럽형 put 공정가(Black-Scholes: S, K, r=FRED, σ=과거실현변동성, T=1주~1개월). p-ratio=실현성과 대비 보험공정가 효율(efficient/inefficient). 횡단면 랭킹. 부호 시장간 불안정(SSE↔SP500 역전) → empirical 양방향",True,True,"testable","medium"))
R[23]=("risk",False,"Structural Matrix AR(SMAR): 수익·실현변동성·거래량 공동동학+횡단면의존(MDH 식별) — 공동위험/spillover 구조모델(risk)",None)
R[24]=("risk",False,"주가 정보네트워크(Pearson vs MI, MST/PMFG, 인니시장) — 의존구조/네트워크 방법론. 종목 수익예측력 미입증이라 중심성 신호는 불확실",
       f("price_network_centrality","상관/상호정보 네트워크(MST·PMFG) 종목 중심성(degree/eigenvector) — 일별 가격으로 합성가능하나 본 논문은 시장구조/커뮤니티 분석에 그쳐 종목 수익예측 미입증",True,True,"uncertain","low"))
R[25]=("skip",False,"PandaAI neuro-symbolic LLM 에이전트(regime 모델링+제약 alpha 생성) — LLM 에이전트 프레임워크",None)
R[26]=("risk",False,"ReSGA 대형 tail risk 모델(retrieval-enhanced self-grouping AE, 153 characteristics)로 VaR/ES 학습 — risk 모델. 횡단면 ES 정렬이 종목신호인지(vol/tail 인접) 불확실",
       f("resga_predicted_ES_sort","153 firm characteristics→예측 Expected Shortfall 횡단면 정렬(저ES 롱). 모델 자체는 risk이며 저ES=저변동성/꼬리 인접이라 D계열 중복 의심",True,True,"uncertain","low"))
R[27]=("optimizer",False,"Anticipatory 포트 최적화: enlarged filtration/horizon forecast/market impact enriched 최적화 + 과적합 분리 — optimizer 이론",None)
R[28]=("skip",False,"미국 종합채권지수 딥러닝 예측(fractional differencing) — 채권/고정수익(KR 미적용)",None)
R[29]=("skip",False,"PortBench: 상관인지 LLM 포트관리 벤치마크 — LLM 벤치/데이터셋",None)
R[30]=("risk",False,"거시시나리오 forward-looking 스트레스(SVaR, GPR-HS+SACS) — risk 스트레스",None)
R[31]=("alpha",False,"실적발표일 주가방향 멀티모달 DL(FinBERT 뉴스감성+15 fundamentals+3 technical) — 횡단면 종목방향이나 핵심 novelty=뉴스감성(대체데이터 금지). 비감성부는 fundamentals/technical 중복",
       f("ea_day_multimodal_direction","실적발표일 방향예측 멀티모달: FinBERT 뉴스감성+펀더멘털+기술지표. 뉴스감성=alt-data(금지), 잔여신호=기존 V/Q/T 중복",True,False,"infeasible","medium"))

papers=[]
fc_all=[]
counts={"alpha":0,"optimizer":0,"risk":0,"regime":0,"skip":0}
for i,x in enumerate(cand):
    route,krf,reason,fac=R[i]
    counts[route]+=1
    rec={"title":str(x.get("title","")).strip(),"id":x.get("arxiv_id"),"source":"arxiv",
         "route":route,"kr_feasible":krf,"factor_candidate":fac,"reason":reason}
    papers.append(rec)
    if fac:
        fc_all.append({"id":x.get("arxiv_id"),"name":fac["name"],"verdict":fac["verdict"],"route":route})

n_testable=sum(1 for c in fc_all if c["verdict"]=="testable")
out={"date":TODAY,"counts_by_route":counts,"n_papers":len(papers),"n_arxiv":len(papers),
     "n_curated":0,"n_factor_candidates":n_testable,"n_factor_flags_total":len(fc_all),
     "factor_candidates_all":fc_all,"papers":papers}
op=f"stage_artifacts/paper_recharge/alpha_search_route_{TODAY}.json"
with io.open(op,"w",encoding="utf-8") as fh:
    json.dump(out,fh,ensure_ascii=False,indent=1)
print("WROTE",op)
print("counts",counts,"total",sum(counts.values()))
print("factor flags",len(fc_all),"testable",n_testable)
for c in fc_all: print("  ",c["id"],c["name"],c["verdict"],c["route"])
