# RAMP Gate 3 — 전략풀 인벤토리 + Dedup 보고서
- generated_at: 2026-06-18T11:16:15+0900 | source_version: ramp_v1.0_gate3_4 | as_of: 2026-06-18

## 풀 규모
- catalog sim_result NAV: 264 | batch_434 NAV: 416 | union with NAV: 680
- min_obs(36m) 통과 + zero-var 제거 후 행렬: 5303 days x 479 strategies
- 제외: 72 (사유 분포는 gate3_summary.json)

## batch_434 SEGV-안전 처리
- summary `_result.rds`는 메인 프로세스 정상 읽힘(소형). NAV는 `out_dir/03_period_returns.csv`(ret_net, metric_type=backtested)에서 추출 — 무거운 `bt_result.rds`(세그폴트 위험) 미접근.
- item-manifest(미실행) 21 + nav 부재 22 SKIP (gate3_summary.json 사유).

## 유사도 + Dedup
- 유사도 차원: return/rank/drawdown corr (실측). turnover/holdings = **unavailable**(NAV-only 정직표기).
- near-replica dedup(return_corr>0.95): 343 제거 → unique 136 (71.6% 중복)
- family clusters: 12 (hclust(ward.D2) on (1-return_corr), k=12)

## 정직 — KR 베타지배
- offdiag return_corr median = 0.808 (대부분 강상관 — 1st eigenmode/market 지배).
- config family_rule(return>0.90 OR dd>0.80)은 연결성분 **1개**(거대단일성분 경향) — drawdown_corr이 KR long-only서 거의 universal>0.80. 실제 클러스터는 return-corr hclust 채택.

## SDS(측정) 구성요소
- dedup 감축 71.6% | meta completeness 100.0% | overlay inferred 100.0% | 유사도 3/4 live
