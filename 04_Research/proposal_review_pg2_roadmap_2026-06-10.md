# 외부 제안 검토 #2 — "STR_1715 3층 개선 로드맵 (8-Phase)" (2026-06-10)

**검토 대상**: 도훈 전달 외부 분석 — PG2(STR_1715_AR_on_M4_R05) 강화 8-Phase 로드맵 (Baseline Lock → Forensic Decomposition → SC Refactor → Dynamic Tilt → Shadow → Governor Rationalization → Integrated Admission → Governance).
**관계**: 제안 #1(Sharpe 2.5 System, `04_Research/factor_rotation/proposal_review_sharpe25_system_2026-06-10.md`)의 PG2-특화 후속. E7(슬리브 틸트)·E4(overlay robust화)의 구체 설계도 성격.

## 0. 사실검증 (제안 주장 vs 실측 — 첫 제안과 달리 production 문서 기반이라 정확도 높음)

| 제안 주장 | 검증 | 결과 |
|---|---|---|
| 4층 product 구조 w_final = w_base × β^M4 × β^AR × β^R05 | README L16 | ✅ 정확 |
| L2 sizing = Iter31 linear_tilt | README L18 | ✅ (Q 메모리 "Iter5"는 sleeve blend 버전 — 제안이 더 정확) |
| R05가 regime_t 조건부 → M4 정보 중복 가능 | README `β_R05(regime_t)` + "3-layer cumulative DoF monitoring 의무" | ✅ 근거 있음 — README 스스로 모니터 의무 명시 |
| OOS 27m SR 2.99 / CAGR 115% | 실측(진단용): last 27m SR 2.86 / CAGR 103%, last 21m 2.92/115% | ✅ 근사 일치 (정의 차이 내) |
| R05 DSR N=5 +1.448 / N=37 −3.596 | README + capability 메모리 | ✅ 정확 |
| M4 β=0.75 예시 | README: M4 = 1.0/0.7/0.4 | ⚠️ 수치 부정확 (구조 논지는 유효) |
| admit 255m Sharpe 1.9536 / MDD −24.81% | README | ✅ |

## 1. 수렴 — 이미 보유/완료 (4건)

1. **Phase 0 Baseline Lock**: 재현성은 Cycle 9에서 입증(실제 overlay 스케줄 재구성 cor=1.0). live 기준선 = C3 예측구간 [0.39, 3.16] 등록 완료. **단 제안이 모르는 우리 측 발견 1건을 Phase 0에 추가**: backtest_harness 리밸 경로 매도 수수료 누락(고회전 net 과소계상) + 마켓임팩트 부재 — turnover reconcile 항목과 정확히 맞물림(역량평가 §6).
2. **Phase 7 Governance**: 신규 strategy_id shadow + 직접 덮어쓰기 금지 + governor 수동 + live monitoring — 기존 거버넌스 그대로. T+30 POST_DEPLOY_AR review(**~06-12 예정**)가 Phase 5와 자연 결합.
3. **Admission 기준**: ΔIR≥0.05·DSR post-hoc N 민감도·cost-corrected — measurement-graduation §3/§4 + selection_type 기구현 (제안이 우리 기준을 정확히 차용).
4. **"Tilt 먼저 금지, 분해 먼저" + bounded tilt + smoothing + 국면은 bounds 조절로만**: 우리 4중 실측(regime 직접신호 무익) 및 C2 교훈(admission=품질게이트)과 정합. 제안 §3.4의 "regime은 예측신호가 아니라 bounds 장치"는 우리 기각 실측을 우회하는 영리한 절충.

## 2. 기각·수정 — 실측이 제안을 앞서거나 반박 (3건)

| # | 제안 | 수정 | 근거 |
|---|---|---|---|
| 1 | SC3: Value를 Phase 2 검증 후 5~10% satellite로 | **이미 추월** — 로드맵에 묶지 말 것 | 전종목 value sleeve **+0.127 검증 완료**(25% blend, cor 0.005, 2017+ 생존). 정식 forge만 잔존 — 독립 트랙 즉시 진행 |
| 2 | Phase 1 진단·게이트가 rank-IC/ICIR/Harvey-t 중심 | 진단 테이블로만 채택, **의사결정 지표는 PORT_t + 실현 기여 분해**(Brinson/Carhart) | rank-IC advisory 강등 실증(16후보: FLOW 거짓탈락+NN/TECH 거짓통과, `measurement-graduation §3`) |
| 3 | OOS 27m(SR 2.86~2.99) 성과를 분석 축으로 | 분해는 하되 **admission 근거 사용 금지** | C3 규약: 27m Sharpe SE ±0.6+ → PASS_LOW_INFO 영역. 제안도 "짧다" 인정 — 일관 적용 |

## 3. 신규 채택 — 이 제안의 실질 기여 (4건)

1. **★ Phase 1 Forensic Decomposition (최우선)**: 7팩터/4-family(Earnings 65 / Quality / ResidMom / Distress 각 11.7) attribution — **우리가 체계적으로 한 번도 안 한 것** (book 통째 측정만 해옴. research_philosophy ⑦ Attribution이 헌법에 있으나 미실행 상태). 산출물 채택: Factor IC Table(진단) + Family Attribution + Redundancy Matrix(score corr vs **return corr** 구분 — 좋은 설계) + Drawdown Attribution + OOS 27m 원천 분해 + Core/Defense ablation(ΔSR·ΔMDD). **E7(슬리브 틸트)의 전제조건**.
2. **Phase 5 Governor 중복 진단**: trigger overlap 실측 P(M4∩R05), P(AR∩R05), P(3중) + combine 4종 비교(product/clipped-floor/severity-weighted/hierarchical) + missed-upside·cash path·β smoothness 지표. **E4(레버②)를 "R05 target-vol 교체"에서 "combine 구조 재설계 포함"으로 확장 채택.** README의 DoF 모니터 의무 이행이기도 함. worst-case β=0.09 가능성은 사실(product 구조) — 단 "실제 발생했는가"를 beta path 실측으로 먼저.
3. **Rank-invariant 원칙 명문화**: Tilt = 상대비중 변경 가능 / Governor = scalar only(rank_corr(w_final, w_base,dynamic)=1.0) / invariant 기준점을 dynamic base로 이동. E7 설계 원칙으로 채택.
4. **M0~M4 ablation + S2−S1 순수기여 분리**: E7 shadow test 프레임으로 채택 (tilt가 governor 덕에 좋아 보이는 착시 차단).

## 4. 통합 로드맵 (우리 자산 반영 수정판)

```
Track A (독립·즉시):  전종목 value 정식 forge WT → judge → governor admit(도훈)   [제안 SC3 추월분]
Track B (PG2 정밀화): B0 Baseline lock + 수수료결함 수리
                    → B1 Forensic decomposition (4-family attribution)          [제안 Phase 1]
                    → B2 Governor overlap 진단 (+T+30 AR review 06-12 결합)      [제안 Phase 5 — 순서 앞당김]
                    → B3 SC2 4-family refactor (B1 결과 조건부)                  [제안 Phase 2]
                    → B4 E7 sleeve tilt shadow (chain 규율·bounded·국면=bounds만) [제안 Phase 3~4]
                    → B5 통합 admission (M0~M4 ablation, ΔIR≥0.05, C3 holdout)   [제안 Phase 6]
```
- 순서 변경 근거: B2(governor 진단)를 B3(refactor)보다 앞 — T+30 review 일정(06-12) + 진단은 비파괴적·refactor는 B1 결과 의존.
- B4 사전확률 정직 표기: 모듈-레벨 국면 로테이션 4중 기각 전례. 슬리브-레벨이 다른 이유(Core⊥value cor 0.03, 슬리브는 상호 직교적) + tilt 신호 6항 중 미답 축(valuation/crowding) 포함이 재도전 근거. 기각이어도 "타이밍 전 레벨 전멸" L-code 확정 가치.
- n_trials: B4 tilt 신호 조합·bounds는 **사전등록 grid = sweep** (DSR 적용). B1~B2는 진단(게이트 무관).

## 5. 첫 실무 과제 (제안 결론 동의 + 1건 추가)

제안의 "L1 Alpha를 4-family로 완전 분해하고 family별 IC·성과·MDD·OOS 기여 확인"에 동의. **추가**: 동일 사이클에서 **수수료 결함 수리**(Phase 0)와 **governor trigger overlap 실측**(Phase 5 진단부)을 병행 — 셋 다 비파괴 진단이라 병렬 가능, 모두 production 데이터 기존재.

## Change log
- 2026-06-10: 신규. 제안 #2(8-Phase PG2 로드맵) 검토 — 사실검증(구조·수치 대부분 실재), 수렴 4/기각 3/채택 4, Track A·B 통합 로드맵.
