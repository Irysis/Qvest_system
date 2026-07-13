# Self-Adversarial Challenge — TE 재추정 진단 (task #47, 2026-07-13)

risk-research agent 자체 적대검증 (Opus 4.8 native, v8.2 — 외부 Codex 없음). finalize 직전 자기비평 ≥3건 + 분류.
AX-008 3-source 중 1개 (Forge·Architect와 함께 2/3 필요 — 본 건은 진단이라 정식 forge/judge 미경유, 진단재료로 한정).

## 자기비평 + 분류

### C1 — 추정기 선택 method-shopping 우려 [REBUTTAL]
**self-concern**: EWMA λ0.97 권고가 5개 추정기 중 cherry-pick 아닌가? walk-forward가 PIT-clean한가?
**근거 3축**:
- L-code/규율: R2-C method_shopping_log 상한 5 이내(expand_const/roll36/ewma94/ewma97/regime_cond = 5).
- 학술: EWMA(RiskMetrics) + χ² 분산 CI = 표준 추정기, 자체합성 없음.
- 정량: 각 추정기 t시점 예측은 엄격 past-only(t-1까지), 257 out-of-sample 대조. EWMA97이 분산비(1.10)·오경보율(3.3%) 양 지표 모두 지배. λ0.94/0.97 둘 다 보고(3.3~4.5%) — 단일 λ 과적합 회피.
**처리**: REBUTTAL 유지. 단 PARTIAL — λ 최종 선택은 monitoring 튜닝 대상으로 도훈에 위임(리포트 §3 ⓑ에 "EWMA λ0.97 또는 trail36" 병기).

### C2 — 최대기여월(2026-06) recon 불일치 오염 우려 [PARTIAL ACCEPT]
**self-concern**: 단일 39% 기여월이 rds 0.0724 vs recon 0.0582 불일치를 안고 있어 분해가 오염되지 않나?
**처리**: PARTIAL ACCEPT. authoritative TE(0.3324, monitoring 정확 재현)는 rds-basis, 가법 분해는 recon-basis로 분리 사용. recon-basis에서 2026-06 active는 오히려 약간 악화(-0.276 vs -0.261) → 분해가 그 달을 과소평가하진 않음. 정성 결론(지배월·melt-up×overlay) basis 무관 불변. §4 caveat로 명시 + live_book_series 정합 권고. 판정 변경 없음.

### C3 — "구조적 과소추정" 과잉주장 우려 [REBUTTAL]
**self-concern**: 모든 추정기 분산비>1인데, active vol이 원래 예측불가라 어떤 모델도 소용없는 것 아닌가?
**근거**: 리포트에 이미 명시 — 모든 과거기반 추정기가 10~29% 과소(국면전환+두꺼운 꼬리, 완전제거 불가). 주장은 좁고 실측적: *상수*가 차악이고 EWMA가 오경보율을 절반으로(6.1→3.3%)라는 상대개선. 완벽예측 주장 아님. self-rationalization 스캔("미미/관행/보수적이면 OK") 미사용.
**처리**: REBUTTAL 유지.

### C4 — 벤치 구성(삼성·하이닉스) 성분 미분리 [ACCEPT — 데이터 한계]
**self-concern**: task 4번째 성분(벤치 집중)을 ①melt-up과 분리 식별 못함.
**처리**: ACCEPT(정직 한계). BM 구성비 미보유 → ④를 BM vol 2배(0.225→0.414) proxy로만 제시, ①과 얽힘을 §1-C에 명시. 은폐 아닌 명시적 데이터 한계. 정적 holdings Σ로도 지배성분(오버레이 타이밍) 못 담으므로 시계열 추정기 선택은 정당.

### C5 — 역할경계 침범(weight/optimizer scope) 우려 [REBUTTAL]
**self-concern**: EWMA 권고가 optimizer/weight scope 침범 아닌가?
**처리**: REBUTTAL. 권고는 monitoring의 TE 예측 baseline(위험 진단 예측치) 교체이지 weight/exposure bound 아님. book/weight 무변경·monitoring-side·실행=도훈 명시(§3, §5). alpha_vector·비중 무수정. risk scope 내.

## 자동 escalate trigger 점검
- HIGH ≥5: 미해당 (self-concern 5건 중 ACCEPT 1·PARTIAL 1·REBUTTAL 3, 모두 진단범위).
- AX axiom hard FAIL ≥3: 미해당.
- PIT hard violation: 없음 (rolling/EWMA past-only, 진단은 realized recon 기술 attribution).
- **Σ PD violation**: 미해당 — 본 건은 스칼라 TE 예측이지 NxN Σ 행렬 산출 아님(양정치성 대상 없음).
- CVaR hard breach: 미해당.
→ **Q-Lead escalate 불요**. 진단 재료로 정상 종결.

## self-rationalization 스캔
"영향미미/관행적/보수적이면 OK/이미반영" 등 회피표현을 근거로 사용한 곳 없음. "보수(trail12)"는 시나리오 라벨(conservative estimate)이지 합리화 아님. 통과.
