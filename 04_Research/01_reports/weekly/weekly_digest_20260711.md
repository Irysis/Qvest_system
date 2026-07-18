# Weekly Digest — 2026-W28 (2026-07-04 ~ 2026-07-11)

**생성**: 2026-07-11 /cleaner (첫 주간 다이제스트 — W27 마커는 미소비로 W28 스윕이 대체). [정정 2026-07-17: 괄호 안 계보 서술은 오류 — W27 digest(`weekly_digest_20260705.md`)는 2026-07-05 10:31 실존·소비 완료(git 6538dea6), 본 W28은 두 번째 다이제스트. 원문은 정직 기록 원칙으로 보존.] 전 수치 = 해당 런 실기록 인용, metric_type 병기. 원천: `.cache/cleaner_pending.json` W28 + L-code corpus(주간 신규 46건) + 각 WT/stage_artifacts.

## 0. 주간 헤드라인

1. **아키텍처 v8.3 "알파 발굴 중심 재편" 발효** (07-10, 도훈 mandate): alpha 단계 canonical PORT_t 1급화(M1)·dual-basis 진단 계약화(M2)·상설 frontier 큐(M5)·hypothesis_index in-flight(M6)·주입면 현행화(M7/M9)·인입 경보화(M4)·novelty triage(v8.3.1). SOT `02_Infrastructure/docs/qvest_v8_3_alpha_discovery_sot.md`.
2. **텔레그램 v7** (비전공자 3장치, 전문용어 유지) 발효 — dry_run 15/15, 이후 전 브리핑 적용.
3. **리서치 결론(주 후반 집중)**: 봉투내 기존데이터 return-파생 탐색이 공간축·시간축·packaging·마이크로튜닝·계기 5종에서 **전부 실측 소진**. 최상급 PORT_t = 현 book(pinned 6.130) 확정, 역대 상위 기록 2개는 측정 아티팩트로 판명.
4. **Axiom 엔진 실가동 주간**: revival 발화→소비 루프 첫 완주(FQ-007 3장), 규율이 거짓 성공을 차단한 실증 5건.

## 1. 실험별 결론 (07-10~11 — 본 세션 오케스트레이션분)

| 실험 | 가설 1줄 | 결론 | 핵심 수치 (metric_type / 출처) | 후속 |
|---|---|---|---|---|
| WT-D20260710_001 | MID tier 집중 다축 composite가 2.95 돌파? | screen-tier FAIL (구조적 천장) | cap-w PORT_t 2.08·post17 −0.88 / EW 4.10 (canonical_screen / `stage_artifacts/WT-D20260710_001/alpha_validation.json`) | 재시도 금지(다축·mid 집중) |
| WT-D20260710_002 | 기각 8종 중 EW-생존자 분리? | 1종만(V02_EP) — 벤치아티팩트는 factor-specific | EP cap-w 2.52/EW 4.40·OTHER 98.6% / 퀄리티 양basis 음 (canonical_screen / `dual_basis_raw.json`) | EP→RAMP R3-B 재라우팅(진행중) |
| WT-D20260710_003 | 5축 joint packaging이 천장 돌파? | VALIDATED_NEGATIVE | 승자 IS 3.282→OOS −1.634·DSR 0.457 FAIL·역대조군=baseline (canonical_screen, n26 / `finalize_results.json`) | packaging 방화벽 카드(DIST-AR-009 proposed) |
| WT-D20260710_004 | 전이 벽에 샘플링 성분(신호나이)? | Stage A KILL — 성분 없음 | 3독립축 contrast NW-t −0.32~+0.63·score_eff stale최강(NW-t 5.77) (canonical_screen / `alpha_stageA_diagnostics.json`) | B1-VETO만 도훈 크롤 승인 대기 |
| WT-D20260710_004 B1 | fresh 자사주 경계치환 | power-insufficient 종결 | paired −0.46/+0.66·control 구분불가 (canonical_screen, n2 / `alpha_b1_promote_results.json`) | 종결 |
| WT-D20260710_005 | 정정공시 빈도 = 거버넌스 신호? | VALIDATED_NEGATIVE + 기전 규명 | paired −1.33~−4.63·spearman(정정,Size) +0.30 — 크기 proxy(최다=삼성·하이닉스) (canonical_screen, n7 / `stage_artifacts/WT-D20260710_005/alpha_validation.json`) | H-d LLM 텍스트만 이월 |
| WT-H20260710_001 | 7팩터 형성-파라미터 미세조정 여지? | 포화 (SATURATED) | 승자 IS 5.505(DSR 1.0)→OOS −0.963·production paired 0.79 (canonical_screen, n25 / `validate.json`) | 종결. vendor-locked 2필드는 미검 scope 명기 |
| fleet-1 (7 프로브) | 비중복 7방향 동시 스크린 | 생존 0 (측정 5 kill·결측 1·재탕 1) | 최량 양성 1.02 ≈ null 기대 1.16 — ★좌편향(체계적 희석) 발견 (canonical_screen / `l_code_PROBE_FLEET_20260710.json`) | 종결 |
| fleet-2 드레인 | overlay 재고 16건 소비 | 전멸 (INFERIOR 16) | 전 128 시나리오 max paired −1.199 ★복제 4군 적발(N_eff 8) (backtested monthly-agg / `06_Registry/overlay_ab_results/`) | FQ-006 폐쇄·dedup 감사 chip |
| insider 예비 | CMP 역사(2010-15) 방향성 | DEAD_PRELIM (EV 하향) | placebo 70pct·EW −1.82·book paired −3.36 (canonical_screen, 93m power-라벨 / L-code INSIDER_CMP_PRELIM) | 크롤 완료 후 standalone 보류 권고 |
| 챔피언십+FQ-011 | 역대 최고 기록 재검증 | **도전자 전멸 — 현직 = book 6.130(pin)** | bare 7.236=IKS001 버그(교정 6.344·oos 0.613 FAIL)·blend +0.22=stale-baseline(paired −2.946) (backtested / `stage_artifacts/fq011_port_t_championship/`) | 벤치-재베이스 메타규칙 신설 |
| research-level v2 | 갭 구조 분해 | **binding 갭=SR 단일** | CAGR 45.2·MDD 23.3 기충족·구조레버 합=갭의 ~2%·★라이브 캐리 ≈+2.3%p/yr(조건부) (backtested / `06_metrics_noL4_clean_ann12.csv`) | 결정 패키지 G1~G5 |
| RAMP R3 | tail sleeve 무오버레이 + EP EW-sleeve | **진행 중** | — | 완료 시 판정 |

## 2. 주 전반부(07-04~06) 요지 (기존 L-code·메모리 기록 — 재요약만)

- Axiom 엔진 v2 완결(3층 Ledger/Distilled/Law·599→220 증류·INV-6/7)·DIST 10건 승인·revival 브리지 DURABLE·AX-003/004/005/007 Distilled 강등 (push 532a4ebf 계열).
- 실측 negative: uncertainty selection/sizing 2세션 robust FAIL·TE net-sink·조건부 교집합·CMA composite·상관-회복 lane·cap-tier 국소화 양측 증명·리스크 오버레이 look-ahead FALSIFIED→PIT 제도화(C5).
- 비-DART·봉투내·수익파생 횡단 alpha 소진 종착 선언(07-06) → 본 주 후반이 이를 5계기 축으로 재확증.

## 3. Axiom 후보 현황 (의무 절 — W28 스윕 집계)

- **pending CAND 40건**. 실패축 히스토그램: independence 35 · external(oos) 34 · falsification 28 · mechanism 21 · rigor 3 — 여전히 emit 입력 결측이 승격 병목이나, 07-10 emit분(17건)은 4필드 1급 충전으로 개선 방향.
- **near-miss 2건**: ① `CAND_20260711_alpha_research_quality_profitability_positive_...112721_223505` (independence 1축 미달) — ⚠ **라벨 의심**: supporting L-code(EW-생존자·챔피언십 reval)가 quality_profitability "positive"로 클러스터링된 것은 harvester family 추론 오류 가능성(b434-형 라벨 주의) → **자동 승격 제안 보류, 검토 플래그**. ② `CAND_..._qepm_legacy_value_conditional_L-132_135_142` (falsification 미달) — 기존 DIST-QPM-006이 동일 계열 커버 → 중복, 승격 불요.
- **자동초안(본 세션)**: DIST-AR-007(momentum 클러스터)·DIST-AR-008(EW-생존자) pending→proposed 정제 (아래 ④). 잔여 pending_5axis 백로그는 차주 이월(정직 기록).
- **도훈 승인 대기(proposed)**: DIST-AR-009(재조합 방화벽, 07-10) + DIST-JG-001(07-04, polarity 이슈 — 원문 확인 권장) + 본 세션 신규 2건.

## 4. 미적립 학습 점검 (③)

주간 학습은 L-code 46건으로 적립 완료 — 추가 emit 대상 없음. 비-emit 기록 2건: (a) scheduler_alert summary 100자 초과로 텔레그램 미발송 결함(수리 완료된 router 경보와 별개 표면 — chip task_88929630) (b) alpha_search 20260612-13 bt_result 복제 4군(chip task_d4720851 감사 대기).

## 5. 삭제 판정 (④) — 이번 주 무아카이브 삭제 0건

- 기계 스윕 삭제 0건(hygiene 0·cache-scratch 0·temp-logs 0).
- 세션 판정: 삭제 후보로 지목됐던 `stage_artifacts/paper_recharge/` 일회성 스크립트(~30건)·`mcp_discovery_*` 일별 대형본은 **stage_artifacts 내부 = 절대 보존 구역**이라 삭제 불가(deferred 기록). `.trash_20260703`·`C:\qm_trash\20260704`는 보존 시한(2026-08-04) 미도래.
- manifest: `06_Registry/distill_manifest_20260711.json`.

## 6. 확정 지식 (주간 — 메모리/SOT 반영 완료)

1. binding 갭 = SR 단일, 신호로도 구조로도 미폐쇄(구조레버 합 = 갭의 ~2%) — 잔여는 새 정보원·결정 사안.
2. 오버레이 경제학: PORT_t 비용 +0.214(paired 0.767 비유의) ↔ MDD −17.4%p·abs_SR 개선 = 순이득 (첫 정량화).
3. 최적화된 book 위 return-파생 구조 = 체계적 희석(marginal paired-t 좌편향).
4. 메타규칙 2건: novelty triage(v8.3.1 — 재료/기전/그리드 신규성 선언 의무) · 07-02 벤치수정 이전 고-PORT_t 기록 재베이스 의무.
