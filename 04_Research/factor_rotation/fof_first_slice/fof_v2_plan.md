# Factor-Allocation Portfolio v2 — 연구 플랜 (2026-06-30, 도훈 mandate)

## 0. 목표 · 가설 · 제약

**최종목표**: 팩터의팩터 시그널 기반 **팩터-배분 포트폴리오** (25종 long-only).

**핵심 가설 (직전 실측에서 도출)**: 벽은 *팩터 배분*이 아니라 **롱온리 25종 *번역***이다. 신호블렌딩(Σ wf·zf → top-25 select once)은 flat/hand-pick/viability 가중 무관 ~0.73에 수렴(Momentum rank-IC NW-t 8.04인데 book port_t 0.73). → **C = 포트폴리오 블렌딩**(팩터 sleeve별 자체 top-N → sleeve 간 capital 배분, HRP)이 *번역 메커니즘 자체*를 바꿔 살아있는 시그널을 더 잘 monetize하는지 시험. (학술: AQR integrated-vs-mixed — 보통 integrated 우세이나 mixed는 factor-purity/HRP 분산 이점, **KR 25종 미검증**.)

**제약 (불변)**: 25종 long-only HARD · KOSPI200∪KQ150 · Σw=1 · [0,0.20] · 15bps · PIT C1~C15 · load_month_factors C13/14/15 · 실측-only(canonical_screen_bt) · governor 정지(book_state 수동+도훈).

**정직한 prior**: LOW-MODERATE. 번역갭이 깊고 학술상 integrated 우세 + 25종 hard 하 sleeve당 소수종목(coarse). 최빈 결과 = mixed ≈ integrated(~0.73-1.3)이나, HRP 분산이 MDD/calmar는 개선 가능. **테스트 정당성 = 인프라 READY(저비용) + 국소화된 벽 직접 공략 + 미검증.** ⚠ pre-2008 확장은 *강한* 숫자 나오나 비-배포(value/quality 당시 살아있음·현재 死) — forward 판정은 recent 구간.

---

## Stage 0 — 기간 토대 (병렬, 저비용 ~1h)
**작업**: ① RAWDATA/factor_db 최소일자 검증(PowerShell python로 segfault 우회 — `pq.ParquetFile('.cache/RAWDATA.parquet').metadata` / factor_db_*.parquet ls). ② ≥2002-08이면 sig_dates 연장 → 293m(2002-08~2026, +36m, ~8min). 유니버스 pre-2005 = 현 K200∪KQ150 고정 **mock + PIT-caveat 명시**(또는 backfill 보류).
**산출**: 확장 forward 패널(293m) 또는 확정 257m + 정직 caveat 라벨.
**게이트**: 유니버스 PIT 리스크 과대 시 → 257m 유지(확장 차단 정직 보고). pre-2002=value 부재·pre-1995=infeasible.
**재활용**: `build_monthly_forward_returns()` · `_bo_fwdgic.rds` (sig_dates만 연장).

## Stage A — Shumulvey 22-family HRP 프로토타입 (즉시, 빌드 0, ★결정적 cheap-kill)
**작업**: `shumulvey_index_returns_broad.parquet`(5542d × 22 family, 2004-2026, READY) → 22×22 corr → `hclust(1-|corr|, ward.D2)` dendrogram → K=4~6 sleeve cut. **C 포트폴리오 블렌딩**: sleeve별 top-N(canonical_screen_bt) → `hrp_core.R::calc_hrp_weights` sleeve 간 capital → 25종 resolution(Σ N_s=25, sleeve당 max 50%).
**A/B**: integrated(Σz→top25, 현 baseline ~0.73) vs **mixed(sleeves→HRP→25)**. canonical_screen_bt · paired-NW-t(lag3) · 25종 hard.
**산출**: integrated vs mixed port_t/SR/MDD/calmar + dendrogram + 2차트. ~반나절(인프라 READY).
**★cheap-kill 게이트**: mixed−integrated paired-NW-t. <1 → C 포트폴리오블렌딩 무효력, 확대(11/316) 착수 금지. >2 ∧ SR_lift>0 → Stage B 확대. [1,2] → MDD/calmar 보강증거 확인.
**재활용**: hrp_core.R · multi_sleeve_builder.R(strategy_dirs→factor_sleeve 치환) · ep_multisleeve.R · canonical_screen_bt.R.
**신규(소)**: `run_ramp_shumulvey_hrp.R`(~80줄) + sleeve→25종 resolver.

## Stage B — 11-group / pure-factor HRP (Stage A 통과 시, ~1일)
**작업**: `factor_group_scores.parquet`(11 family group_z) → canonical_screen_bt 루프(11×, 2-3h)로 군별 portfolio-return → HRP(11-group). vs Stage A(shumulvey 22) — 순수팩터 그룹핑이 smart-beta 지수 대비 추가가치? viability map 통합(살아있는 sleeve 선택/가중, causal).
**산출**: 11-group HRP vs shumulvey 22 vs integrated. dendrogram 비교.
**게이트**: 11-group이 shumulvey 대비 substantial? 아니면 shumulvey 충분.
**신규**: `factor_sleeve_allocator.R`(~300줄) + `hrp_sleeve_wrapper.R`.

## Stage C — 검증 · viability 통합 · 확장기간 (Stage B 통과 시, 1-2일)
**작업**: 확장기간(Stage 0) 적용 · HRP 변형(cov method: sample/LW/gerber · max-sleeve-w) · regime-conditional sleeve weight(PIT lag-3) · viability 인과 통합. **anti-static-tilt**(정적틸트 대조 + paired-NW-t + placebo) · graduation HARD(PORT_t 2.95 cap-w · oos_retention 0.7 · calmar 0.64) 전부 **25종 hard**.
**산출**: 최종 factor-allocation 포트 + graduation verdict + book-marginal ΔIR.
**게이트**: HARD 3종 통과 시 자본후보(governor 정지·도훈 수동). 미달 시 screen-tier(FR/오버레이 입력).

---

## 거버넌스 · 디시플린
- RAMP frame(QEPM 6-agent 호출 금지·book_state 수동·governor 정지). metric_type 라벨(canonical_screen advisory, admission은 forge authoritative).
- 모든 A/B = paired-NW-t 유의검정(SR 비율비교 금지). 정적틸트 대조 필수. 결론 성급 마감 금지.
- ⚠ pre-2008 강한 숫자 = 비-배포 주의(forward 판정 recent).

## 결정 게이트 요약
| 게이트 | 통과조건 | 실패 시 |
|---|---|---|
| Stage 0 | 데이터 ≥2002-08 + 유니버스 PIT 수용 | 257m 유지 |
| **Stage A (핵심)** | mixed−integrated paired-t >1, SR_lift>0 | C 종결(번역=배분불가 확정) |
| Stage B | 11-group이 shumulvey 초과 | shumulvey로 확정 |
| Stage C | PORT_t 2.95·oos 0.7·calmar 0.64 | screen-tier |

**권고 착수**: Stage 0(~1h 검증·확장) + **Stage A(~반나절, 결정적 cheap-kill)** 동시. Stage A가 mixed>integrated를 못 보이면 C 포트폴리오블렌딩도 번역갭을 못 뚫는 것으로 저비용 확정.
