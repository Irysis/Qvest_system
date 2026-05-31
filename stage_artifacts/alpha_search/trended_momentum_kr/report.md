# Trended Momentum (KR) — Alpha-Searching lean-lane PoC

idea_id: trended_momentum_kr
Paper: Cai, Li, Keasey (2024) "Trended Momentum" SSRN 4740445
Run: AS_TRENDMOM_KR_20260531 · Lane: Alpha-Searching (lean, risk/optimizer SKIP, build_bt_result 경유 실측)

## STEP 1 스펙 + precondition
- PRET = cumulative return t-11..t-1 (12m skip last month) → Close[t-21]/Close[t-252]-1.
- TC = R^2 of regression of DAILY price on date-sequence, 11m formation, >=200 days → cor(date_idx,Close)^2 over 231 거래일, valid>=200.
- Sort: PRET 5분위 → (독립) TC 5분위, "trended momentum" = top PRET ∩ top TC quintile. long leg.
- 비중: 논문 EW/VW 둘 다 보고, 단일 지정 없음 → EW long leg 가정 (Σw=1, w∈[0,0.20]).
- Holding 논문 6개월(t+1..t+6 overlapping); 본 PoC 월간 리밸(다이제스트 지정).
- Universe KOSPI200∪KOSDAQ150, cost 15bps.
- precondition: 비중=규칙(EW), optimizer 불요 → lean 적격 PASS.

## STEP 2 PIT
- C1 Date<=sig_date 스냅샷만 / C2 신호=월말,집행=익월첫일 / C10 LIQ=직전20일 거래대금>=2e8 / C14 미래데이터 미접근.
- max25 / long-only / w∈[0,0.20] / Σw=1.
- PIT#1 detect_lookahead: CLEAN, 0 violations (280 lines).
- 빌드: 292월 valid, 평균 18.8종목, 회전율 0.74/월, 2002-02~2026-05 (24.3y, 292월).

## STEP 3 측정 (계약 경유, 자체합성 없음)
- Return.portfolio (drift-aware) net 일별 → apply.monthly(Return.cumulative) → 공통 월말키 정렬 → build_bt_result(af=12) → essence_score.

본질 5지표 (backtested):
- PORT_t (NW lag-3) = 2.933  (A임계 2.95, 근소 미달, p≈0.0034 유의)
- OOS retention(65/35) = 0.745 (>=0.7 PASS)
- net Sharpe = 0.859 (>=0.8 PASS)
- CAGR = 23.7% (>=16% PASS)
- Calmar = 0.442 (<0.64 미달)
- net IR = 0.65 ; MDD = 53.6% (>45% mdd_hard → hard_fail)
검증 진단: ann.vol 31.0%, beta 0.99, cor 0.71, hit 56.8%, alpha_ann 14.3%, TE 21.9%.
DSR 미적용 (1논문/1알파, n_trials=1, SOT §3.5).

## STEP 4 등급 + caveat
등급: F (hard_fail: MDD 53.6% > 45%). 알파 유효(PORT_t 2.93·IR 0.65·CAGR 23.7%·beta 0.99)이나 drawdown으로 standalone 부적격 → S5-on-reject 강화 후보.

Caveat:
1. KR 미검증 → 이번이 KR 첫 실측. 논문상 이머징은 최고 TC만 유의. 알파 존재 실측되나 beta 0.99·MDD 53.6%로 단독 long-only 부적격.
2. 비중 가정: 논문 EW/VW 둘 다, 단일 지정 없음 → EW 가정 (VW/inverse-vol 미측정).
3. Holding nuance: 논문 6개월 overlapping vs 본 PoC 월간리밸 — 구조 미재현.
4. OOS = 65/35 chronological proxy (정식 lockbox 아님, judge#2 재검 필요).
5. 구현 한계: 거래일 근사(21/252/231), gross=net 저장(net Sharpe/CAGR는 일별 net 차감 후라 정확, Annualized_Turnover=NA).
6. 계약 진단 버그: build_benchmark_compare keyed+unkeyed merge가 order-sensitive 지표(beta/cor/hit) 오정렬(저장 beta=-0.008/cor=-0.29/hit=0.068). 등급 대상(PORT_t/IR/Sharpe)은 order-invariant라 무영향(manual 일치 검증). 본 리포트 진단치 정정. → 계약 후속 fix 권고.

## 결론
lean lane이 계약-실측 등급(F, MDD hard_fail) 산출 실증. 전 수치 Return.portfolio+계약 실측(자체합성 없음). 알파 유효하나 drawdown으로 standalone 부적격 → S5 강화 회부 후보.

## 산출물
run_all.R / measure.R / sim_result.rds / bt_result.rds / essence_grade.json / report.md
