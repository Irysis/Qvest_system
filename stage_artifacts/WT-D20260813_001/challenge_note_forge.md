# Forge Self-Adversarial Challenge — WT-D20260813_001 (q90 pinball LGBM)

발효: 2026-08-22 · agent: forge v6.1 Pure Function · AX-008 3-source 중 1 (self-adversarial)

finalize 직전, 본 forge_package 를 스스로 적대적으로 검증한다. 외부 Codex 호출 없음 (v8.2 Codex Round 제거).

## 실측 요약 (forge-authoritative, metric_type=backtested, monthly basis, 198개월)

| 지표 | 값 | HARD 게이트 | 판정 |
|---|---|---|---|
| PORT_t (NW lag-3, mean active) | 0.8366 | ≥2.95 | FAIL |
| oos_retention (median 55/65/75) | -0.8550 | ≥0.7 | FAIL |
| calmar | 0.2122 | ≥0.64 | FAIL |
| ann_SR | 0.5781 | — | — |
| ann_CAGR | 0.1420 | — | — |
| ann_MDD | 0.6694 | — | — |
| ann_turnover (one-way) | 5.3007 | (11.0 이내) | 통과 |
| beta-controlled t(alpha) | 1.2066 (α_ann 8.69%, β 0.814) | — | 비유의 |
| no_signal_gate | INDISTINGUISHABLE_FROM_NO_SIGNAL (diff NW-t 0.972) | — | 신호 기여 미실증 |

OVERALL = **FAIL** (예상 — upstream alpha research_verdict = NOT_SUPPORTED).

## 자가 제기한 약점 (≥3건 의무)

### C1. [측정 결함 — 실제로 발생, 수리 후 재측정] daily-length NAV × monthly annualization_factor 로 CAGR 62배 축소
초회 run4 이전 실행에서 build_metrics 가 CAGR 0.66% · calmar 0.0099 를 냈다. 원인: contract `build_metrics` 는 `nav_xts <- xts(nav_tbl$nav_net)` 를 쓰는데, 내가 daily NAV(4053행)를 sim_result 에 넣었고 frequency="monthly"(annualization_factor=12)라 `(final/initial)^(12/4053)-1` = 0.66% 로 붕괴했다. **독립 검산**(python daily→monthly 재집계)에서 진짜 CAGR = 14.52%(monthly 복리)·daily ann mean 19.3% 를 확인해 결함을 검출. 수리 = sim_result$DAILY_NAV_DT 를 **월말 last NAV(198행)** 로 교체 → CAGR 0.142·calmar 0.2122(=0.142/0.669 정합). ⇒ **contract 는 무수정(Pure Function 경계 준수), 입력 정합만 수리**. 이 결함이 없었다면 calmar 0.0099 로 **더 극단적 FAIL 을 오보고**할 뻔했다 — 방향은 FAIL 로 같았으나 수치는 fabrication 급 오차였다.

### C2. [측정 basis 약점] PORT_t = mean(r − r_bm) 는 α 와 (β−1)·E[bm] 를 섞는다
forge PORT_t 0.8366 은 롱온리 β=0.814(벤치 미달 노출)를 포함한다. β<1 이므로 여기서는 β 기여가 PORT_t 를 **끌어내리는** 방향(measurement-graduation §2 의 β>1 과대표시와 반대). β-통제 t(alpha)=1.207(α_ann 8.69%)이 PORT_t 0.837 보다 오히려 크나 **둘 다 |t|<2.0 비유의**. ⇒ 알파 존재를 주장할 근거 없음. §2 준수로 β-통제 α 병기 완료.

### C3. [신호 기여 미실증] 무신호 대조와 구별 불가 — 그러나 대조 성분 주의
no_signal_gate verdict = INDISTINGUISHABLE_FROM_NO_SIGNAL (diff NW-t 0.972 < 1.96). 단 이 라운드에서는 **전략 t(alpha)=+1.201 vs 대조 t(alpha)=−0.959** 로 전략이 대조보다 우세하다(부호 반대). 즉 "신호가 대조보다 나쁘다"가 아니라 "차이가 유의 문턱에 못 미친다"(diff_ann +7.29%/yr 인데 NW-t 0.972). 대조군은 freq=1(월간 리밸)로 구축했는데 weights.csv 는 월간 스케줄이라 정합. ★약점: 대조 corr 0.598 로 두 계열이 상당히 다른데도(대형주 노출 상이) diff 가 유의하지 않은 것은 **표본 노이즈(198개월) + 활성 vol 큼** 탓 — 창-도달가능성 관점에서 이 창에서 diff 유의는 어렵다. 처분 = '신호 기여 미실증'(효과없음 단정 아님).

### C4. [schedule fidelity 자기검증] weights.csv as-is 소비 확인
run_all.R 은 alpha_scores.parquet 을 holdings 결정에 **일절 사용하지 않았다**(진단조차 미로드). holding_month 199개(effective 198, 2010-03~2026-08) 를 그대로 exec 스케줄로 소비. 종목수 25 고정·Σw=1·max 0.0455·long-only 전부 재검증 PASS. fabrication label(ProductionSchedule[N]m 류) 미기재. ⇒ Schedule Fidelity Mandate 준수.

### C5. [3-package 불변] hash audit
alpha/risk/opt md5sum start==end (17d1..f283 / 0ba2..367b / 137a..bc44) 3종 전부 일치. Pure Function 경계 준수.

### C6. [divergence 진단] alpha canonical vs forge realized
alpha_package diagnostics canonical_port_t_nw_lag3 = 0.9256 (EW top-25, no semicap, canonical_screen_bt) vs forge realized PORT_t = 0.8366 (실제 weights.csv semicap50, share-based rounding + 15bps delta cost). |divergence| = 0.089pp < 0.6 → **NEGLIGIBLE**. FABRICATION_SUSPECTED 아님. 차이는 semicap50 적용 + 이산 주수 반올림 + 실비용의 정상적 감쇠로 설명 가능.

## 잔여 warning (비차단)
- audit_bt_result: 18 checks PASS=15 FAIL=0 WARN=3, integrity=WARNING (critical FAIL 아님).
- table.Drawdowns "Only 14 available" — 월간 198행에서 drawdown episode 14개, 정상.
- forge_package.no_signal_gate_note = {} (게이트가 실행됐으므로 note 불필요, %||%(NULL) 직렬화 잔재 — harmless).

## 결론
q90 pinball 표적 형태는 이 config(EW top-25 semicap50, weights.csv 스케줄)에서 자본 게이트 HARD 3종을 전부 미달하며, 무신호 대조 대비 신호 기여도 이 창에서 유의하게 실증되지 않는다. upstream NOT_SUPPORTED 를 forge 실측이 확증한다. 판정 라운드이지 편입 후보 아님. (alpha 측 next_probe: C2 expectile 표적 · FQ-237 선별 목적함수 · 소비 마디 교체.)
