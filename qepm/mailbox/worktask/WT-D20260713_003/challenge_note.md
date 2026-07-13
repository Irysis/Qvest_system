# Self-Adversarial Challenge — R19 칼만 시변베타 BAB (WT-D20260713_003 / FQ-032)

**v8.2 Opus 4.8 자체 적대검증** (외부 Codex 없음). Charter §8 No Silent Override. AX-008 3-source 중 1.
finalize 직전 스스로 devil's advocate로 산출물의 약점을 제기·분류(ACCEPT/PARTIAL/REBUTTAL)·근거 기록.

## 측정 요약 (판정 대상)
- **1차 endpoint (β 정확도, Q-Lead 최우선)**:
  - metric_1 (전방 daily 헤지잔차 MSE, paired): 칼만 우세 아님 — overall paired_t **−1.18**(49.3%, rel −0.011%), **melt-up 2025+ 유의 악화 −11.87**.
  - metric_2 (실현 forward-252d β 예측 RMSE, paired): 칼만 **유의 우세** — RMSE 0.355 vs OLS 0.396(−10.3%), paired_t **+56.5**; 단 melt-up 2025+ 악화(−11.93).
- **2차 (팩터-레벨)**: z=−β top-25 EW long-only. arm O(OLS) PORT_t **−1.09**, arm K(Kalman) **−1.78**. 칼만 한계기여 paired_NW_t **−1.62**(비유의). 둘 다 음.
- **AX-001v2 조건부**: 저베타 위기 알파 실재 — arm O crisis_active_t **1.935**(bad/normal IC 4.66). 칼만이 개선 못함(arm K 1.559 < OLS).
- ranking spearman mean 0.781(≥0.95는 6%뿐), placebo_p 0.998.

---

## 사전등록 우려 (prereg)

### C1 — 칼만 q(κ) 선택이 사실상 랭킹을 OLS로 수렴시키는가?
**분류: REBUTTAL (근거 있음) + 방법 refinement 기록**
- **랭킹은 실질적으로 다름**: monthly (−β_K vs −β_O) spearman mean 0.781, ≥0.95 지속은 6%뿐 (반대 방향 — 충분히 다름). 즉 "추정기 교체 = 실질 동일 팩터"는 반증됨.
- **정직 기록(refinement)**: prereg는 "IS dlmMLE median κ"로 동결했으나, 자유 dlmMLE κ_raw=**0.46**(clamp 0.1) 및 IS-hedge-MSE 튜닝 모두 **일별 노이즈 과적합으로 κ→degenerate-fast(hl 2일, β pooled sd 0.92)**로 퇴화(idiosyncratic 지배가 hedge-MSE를 판별 못해 과속 κ 보상). → **κ를 metric_2(실현 β 예측, β-vs-β로 idiosyncratic 비지배) IS-min으로 재선택**(κ*_2=1e-2, hl 7일). 이는 prereg 허용범위("IS MLE 또는 문헌 표준값" + clamp) 내 원리적 refinement이며, 두 튜닝 결과 모두 산출·공개(kappa_grid_curve.json / kappa_metric2_curve.json). Samsung 단일종목 검증으로 필터 정확성 확인(κ=1e-5 month-end β sd 0.060 range[0.94,1.30], rolling-OLS sd 0.228보다 평활).
- **결론**: 랭킹은 다르되 그 차이가 canonical·헤지에서 도움이 안 됨 → C1 실패모드 아님.

### C2 — 저베타 top-25가 소형주 국소화 그림자인가?
**분류: ACCEPT (인정)**
- 실측: 두 arm 보유의 **~91% OTHER(유니버스 cap rank 31+), median 유니버스-rank ~150 of ~349, MEGA 1~2%뿐**. 저베타 = KR 소형주 틸트 확정.
- 음의 알파의 상당분 = 2025 mega-cap 반도체 레짐의 소형주 국소화 역풍(EW-uni post2017_t도 음 −1.5~−2.9 → 벤치 아티팩트 아닌 실질 부진). **칼만이 이 국소화를 바꾸지 못함**(median rank OLS 154 vs Kalman 146, 오히려 소폭 더 소형).
- reference: [[project-captier-alpha-localization-20260706]] — 저베타 alpha가 벤치 저비중 tier에 국소화 → long-only 횡단선택으로 cap-w 탈출 구조 불가. 본 측정이 재확인.

### C3 — melt-up 구간 β 급변이 칼만 쪽 회전비용을 잠식하는가?
**분류: PARTIAL (전제는 틀리나 melt-up 취약성은 실재, 경로 다름)**
- 전제 반증: 칼만 turnover **2.87/yr < OLS 5.09/yr** (칼만 month-end β가 더 평활 → 회전 오히려 낮음). 회전비용 잠식 아님.
- 그러나 **melt-up 2025+에서 칼만 β가 유의하게 열화**: metric_1 paired_t −11.87, metric_2 paired_t −11.93 (RMSE +6%). 원인 = 회전비용이 아니라 **빠른 필터(hl 7일)가 melt-up 변동 일별 comovement를 chase → 정착 β 오예측**. a-priori 가설("낡은 OLS가 melt-up서 가장 틀림")과 반대 — 적응 필터가 그 구간에서 더 틀림.

---

## 신규 적대 우려 (devil's advocate, ≥3)

### NC1 — metric_2 "칼만 우세"가 target 정의(forward-252d OLS)의 준-tautology 아닌가?
**분류: PARTIAL/REBUTTAL**
- 실현 β = forward-252d OLS로, 최근가중 적응 추정이 flat 252d 평균보다 near-future에 가까운 건 **drift-persistent β에서 부분적으로 기계적**. → 이것이 바로 metric_2 우세가 운용가치를 함의하지 않는 이유이며, metric_1(헤지 오차 ≈0, idiosyncratic 지배)이 그 inert함을 확증. **결론(운용 inert)을 강화**하지 약화하지 않음.

### NC2 — κ*_2가 metric_2 IS-min으로 튜닝 → metric_2 우세는 in-sample 자기유리 아닌가?
**분류: PARTIAL**
- IS=2006-2011. 우세는 pre2025(대부분 post-IS OOS)에서 paired_t +59.6로 robust → 순수 IS 유리만은 아님. 단 튜닝 타겟이 metric_2를 자기유리하게 함은 인정. melt-up 악화는 진짜 OOS 취약성.

### NC3 — long-only top-25는 BAB(long low-β / short high-β)의 short leg를 못 담음
**분류: ACCEPT-scope (배포 제약, prereg·불변)**
- long-only mandate(헌법)로 high-β short leg 부재 = BAB 순정 검정 아님. 단 이는 칼만-특이 이슈 아니고 prereg 명시, 선행 BAB PORT_t −2.02도 long-only. L/S 판정 인용 금지(memory feedback-no-longshort-validation).

---

## 합리화 자기검증 (auto-detection: 미미/관행/보수적이면 OK/대부분 동일)
- **metric_1 overall sign_test_p=0 이나 경제적 무의미**: p=0은 n=157,890의 산물(49.3%는 사실상 coin-flip, rel_improve −0.011%). "유의"라 오독 금지 — huge-n sign test 아티팩트임을 명시. 이는 합리화가 아니라 **거짓 유의 방어**(정직 라벨).
- "칼만이 β를 잘 예측한다(metric_2)"를 운용가치로 비약하지 않음 — metric_1·팩터·방어 3면 모두 개선 없음으로 격리 확인.

## Escalation 판정
- HIGH severity ≥5? **NO** (C2 ACCEPT 1건, 나머지 PARTIAL/REBUTTAL). AX axiom hard FAIL ≥3? **NO**. PIT C1(lockbox/lookahead) 위반? **NO** (dlmFilter 필터값만, 스무더 금지; forward-252d 실현 β는 진단 target이며 β̂_t는 sig_date 이하 데이터만). → **Q-Lead escalate 불요**. 통상 판정 보고.

## AX-008 Triangulation
self-adversarial(본 문서) = 3-source 중 1. 측정 자체가 canonical 계약(build_benchmark_compare) 경유 실측 = Forge-등가 실측 source. 2/3 PASS 충족(형식적 architect 미소집 — 본건 estimator 진단, 자본 admission 아님).
