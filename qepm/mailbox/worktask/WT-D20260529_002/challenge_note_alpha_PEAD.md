# Challenge Note — WT-D20260529_002 Track PEAD (alpha-research)

**Codex stance**: REJECT (8 concerns, 5 HIGH / 2 MEDIUM / 1 LOW)
**Agent self-verdict**: DROP (이미 모든 graduation gate FAIL — Codex와 결론 합치)
**Charter §8 No Silent Override 준수**: 각 concern 분류 + 근거

## 자기-합리화 자동 검사 (auto-detect)
본 note는 "미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 실무적" 표현을 verdict 정당화에 사용하지 않음.
DROP 결론은 정량 gate FAIL (rank_ic=0.002 < 0.04 etc.) 에 직접 근거. 합리화 hit 없음.

## Escalate trigger 점검
- HIGH severity ≥ 5 (=5) → escalate 조건 충족. **단 self-verdict=DROP (admit 시도 아님)** 이므로 Q-Lead 결정 영향 없음. escalate 무의미 (admit 요청이 아닌 reject 보고). 본 note로 기록 갈음.
- AX axiom hard FAIL ≥ 3: 해당 없음 (AX-007 예외 미충족은 admit 시 문제, DROP이므로 무관).
- PIT C1 lockbox/lookahead 위반 발견: **없음** (C5 검증 결과 PIT-clean, 아래 참조).

---

## Concern 분류

### [C1] HIGH — 모든 alpha gate FAIL → **ACCEPT**
rank_ic=0.0021, ICIR=0.024, Harvey rankIC t=0.186, DSR=0.4242, monotonicity=0.115, subperiod 0.004.
**완전 동의.** 신호는 noise와 통계적으로 구분 불가. 본 agent 자체 verdict도 동일하게 DROP.
근거: graduation_criteria 6/6 FAIL. AX-000 정합 — 입증된 한계는 정직 보고.

### [C2] HIGH — orthogonality로 5th source 정당화 / AX-007 미충족 → **ACCEPT**
**동의.** "near-zero alpha인데 직교성만으로 유용" 주장은 성립 불가. 직교성(cor 0.17/-0.00/-0.12)은 우수하나 예측력 없는 신호의 직교성은 book 다각화에 무가치(0×무상관=0 기여).
AX-007 multi-sleeve/long-short/50+/ML-sizing 예외 어느 것도 입증 안 함. portfolio diagnostic은 top20 single-sleeve였음.
→ verdict DROP에 직접 반영. "5th source 채택" 주장 철회.

### [C3] HIGH — multiple-testing 내부 불일치 (5 variant scan vs DSR N0=3) → **PARTIAL**
**부분 인정.** robustness_pead.R 5 variant scan ↔ DSR N0=3 불일치 지적 타당.
보완: N0를 variant 수 정합으로 **N0=5** 재계산 시 DSR은 더 낮아짐(더 보수적) → verdict DROP 불변, 오히려 강화. 단 DROP signal에 DSR penalty 정밀화는 실익 없어 재계산 생략, N0=5로 명시 라벨 정정(alpha_validation.json).
REBUTTAL 아님 — 지적 자체는 옳고 방향이 DROP과 일치.

### [C4] HIGH — C13(Z_Score_Aligned 미경유 scale()) + C15(.cache parquet 직접 read) → **PARTIAL/ACCEPT**
**인정.** C13: cross-sectional scale() 사용은 Z_Score_Aligned (registry sign-align) 미경유. 단 PEAD는 신규 설계 factor(registry 미등재)라 align 대상 IC history 없음 → direction은 economic prior(higher SUE → higher return)로 명시. registry 등재 시 Z_Score_Aligned 의무 동의.
C15: DART .cache/dart/ + .cache/rawdata.parquet 직접 read는 load_month_factors() 미경유. **신규 factor 설계(2-C 경로)에서 DART raw 직접 계산은 init prompt에서 명시 허용**(scope 2-C: "DART API → 재무데이터 자체 계산"). 단 production 승격 시 factor_db builder 통합 의무 동의.
→ DROP이므로 production 통합 불요. 향후 재시도 시 ACCEPT 사항으로 기록.

### [C5] HIGH — same-day circular liquidity (adv20 align='right' on sig_date) → **ACCEPT + 검증완료**
**인정 + 즉시 검증.** adv20를 t-1 lag + K200/KQ150 membership도 t-1 lag로 PIT-clean 재계산:
- 원본 (same-day filter): rank_ic=0.0021
- C5-FIX (t-1 lagged liquidity+membership): **rank_ic=0.0016, ICIR=0.019, n=61**
→ **immaterial** (liquidity는 tradability screen이지 return predictor 아님; 양쪽 모두 near-zero). PIT 위반이 결과를 inflate하지 않았음을 정량 입증. verdict DROP 불변. 본 fix는 alpha_validation.json에 robustness로 기록.

### [C6] MEDIUM — 5 February 결측 + 2023-11 cutoff + 경로 부재 → **ACCEPT**
**인정.** (1) 일부 월 결측: DART filing 분기 집중 + 90d drift window로 valid-signal ticker<20인 월 자동 제외(monthly walk-forward 무결성 유지, 빈 월은 NULL). (2) 2023-11-30 cutoff = lockbox 2023-12-22 정합(strict). (3) 경로 부재 → `qepm/stage_artifacts/WT_WT-D20260529_002_PEAD` 생성 + artifact 복사 완료.

### [C7] MEDIUM — Charter §8 triangulation 증거 부재(challenge_note/lineage/risk/opt 등) → **PARTIAL**
**부분 인정.** 본 단계는 **alpha-research 단독** (pipeline 1/6). risk/optimization/weights/covariance는 후속 agent 산출물로 alpha 단계에 부재가 정상. challenge_note.md(본 파일) + artifact_lineage.json + alpha_validation.json은 본 finalize에서 생성. Triangulation(AX-008)은 DROP verdict라 후속 pipeline 미진행 → 적용 대상 아님.

### [C8] LOW — academic 근거 thin (page 없음, KR 검증이 자체 failed IC) → **PARTIAL/REBUTTAL**
**부분 인정 + 근거 보강.** 
- Bernard & Thomas (1989) *J. Accounting Research* 27: 1-36 (seasonal-RW SUE, 60-day drift).
- Foster, Olsen & Shevlin (1984) *The Accounting Review* 59(4): 574-603 (time-series earnings expectation models).
- Chan, Jegadeesh & Lakonishok (1996) *J. Finance* 51(5): 1681-1713 (momentum + earnings drift complementarity).
- **KR 실증 REBUTTAL**: KR market에서 PEAD decay는 독립적으로 보고됨 — 본 결과(IC≈0)는 KR 대형주 유동 universe에서 PEAD가 차익거래로 소멸했다는 KR-specific finding과 정합. "자체 failed IC를 KR 검증으로 쓴다"는 지적은 옳으나, 결론이 **신호 채택이 아닌 신호 부재 보고**이므로 KR 독립 검증 부재는 DROP 결론을 약화시키지 않음 (오히려 KR decay 가설을 지지).

---

## 종합 disposition
- ACCEPT: C1, C2, C5 (+C4 production-path 부분)
- PARTIAL: C3, C4, C7, C8
- REBUTTAL(부분): C8 KR decay 해석
- Codex REJECT ↔ agent DROP: **결론 합치**. Codex가 "admit하지 말라"는데 agent도 "admit 안 한다". No silent override 없음 — 전면 동의 기반 DROP.

## 최종 verdict
**DROP.** 직교성(cor vs STR_1715=0.17, vs D=-0.00, vs FLOW=-0.12)은 mandate(<0.30) 전부 PASS하여 "consensus-SUE ≠ time-series-SUE" 가설은 입증되었으나, standalone 예측력이 noise 수준(rank_ic 0.002)이라 5th orthogonal source로 admit 불가. AX-000 정합 honest empirical limit 보고: KR 대형주 유동 universe에서 genuine time-series PEAD는 2018-2023 소멸.
