# RAMP Gate 4 — 순수팩터 추출 보고서
- generated_at: 2026-06-18T11:16:15+0900 | source_version: ramp_v1.0_gate3_4 | as_of: 2026-06-18

## 4.1 통계적 잠재팩터 (PCA)
- **PC1 분산설명률 = 76.0%** (KR 베타/market 1st eigenmode 지배 — 예상대로, 부풀림 없음).
- top-10 누적 분산설명 = 92.8%. PC2~ 각 <5% (구조는 잔차 PC에).
- scree: PC1=76.0%, PC2=4.9%, PC3=4.1%, PC4=2.7%, PC5=1.5%, PC6=1.0%, PC7=0.9%, PC8=0.7%, PC9=0.5%, PC10=0.5%
- factanal(5f, varimax): **failed** (수렴 실패 시 PCA+hclust 가 latent 경로 — 정직표기).

## 4.2 순수팩터 FWL 직교화
- controls X = sector dummies + log_mktcap + beta(252d) + vol(252d) + liquidity(log 20d ADV).
- z_pure = z − X(X'X)⁻¹X'z. 직교성 assert |cor(z_pure, X)| < 0.05.
- 검증 factor set: 316개 (★factor_db 전체 Coverage=TRUE — 풀 sweep, 도훈 mandate).
- 직교성 pass rate: 100.0% (OLS 잔차는 설계열에 구조적 직교 — FWL 정상 작동 증거).

## 4.4 잔차-α 후보 (잠재팩터 미포착)
- PC1~5 회귀 후 unexplained var>0.5 + dedup-unique 전략: **18개** (신규-α 후보 풀).
- 상위 예시: STR_AS_20260612_215216_185168, STR_AS_20260612_230800_193887, STR_AS_20260612_211102_178289, STR_AS_20260613_100537_268904, STR_AS_20260613_022129_218429
