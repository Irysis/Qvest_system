# Weight Method Selected — WT-D20260425_001 (MEGA_03)

## Selected Method
**ms_hrp_rg** (net_score=4.2511, IR=4.285, n_rebal=95)

## AX-002 L-209 Resolution
| Item | MEGA_02 | MEGA_03 |
|------|---------|---------|
| Declared | MinCVaR_Score_0.3 | Rolling MinCVaR QP |
| Actual path | InvVol proxy 99.3% | QP solve.QP() 100% |
| proxy_pct | 99.3% | **0%** |
| L-209 flag | FAIL | **RESOLVED** |

## Sprint 5대 의무 달성
1. Rolling MinCVaR QP: InvVol 완전 제거 (proxy_pct=0%)
2. Regime-Σ: sample LW + 30% regime-cor blend (4 regime)
3. QIS 2022: kappa=sqrt(n/T) shrinkage 실험 완료
4. Kelly f=N/A (baseline 선택): alpha confidence HIGH 반영
5. AX-008 triangulation: QP code + PIT log + constraint report

## 10-Method Comparison (net_ir objective)
| Method | Score | IR | n_names | n_rebal |
|--------|-------|-----|---------|---------|
| ms_hrp_rg | 4.2511 | 4.285 | 20.0 | 95 |
| ms_rollmincvar_qis | 3.9794 | 4.030 | 15.0 | 92 |
| ms_mvo_rg | 3.9787 | 4.029 | 15.0 | 92 |
| ms_rollmincvar_rg | 3.9729 | 4.023 | 15.0 | 92 |
| ms_rollmincvar_nls | 3.9729 | 4.023 | 15.0 | 92 |
| ms_cvarlp_rg | 3.9729 | 4.023 | 15.0 | 92 |
| ms_mega02_baseline | 3.7738 | 3.822 | 20.0 | 95 |
| ms_rollmincvar_rg_k05 | 3.6535 | 3.712 | 17.7 | 94 |
| ms_rollmincvar_rg_k075 | 3.6006 | 3.661 | 17.7 | 94 |
| ms_rollmincvar_rg_k10 | 3.5415 | 3.604 | 17.7 | 94 |

## Constraint Satisfaction
- n_names: 20 / 20 (PASS)
- sum_weights: 1.0000 (PASS)
- max_weight: 0.1500 ≤ 0.15 (PASS)
- HHI: 0.0778 ≤ 0.15 (PASS)
- long_only: PASS

## PIT Compliance
- C1: expanding window (>=36m), no full-sample stat
- C2: regime label from rd_idx-1 (t-1 lag)
- C9: score_dates[score_dates <= rebal_date] strictly enforced
