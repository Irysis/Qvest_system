# PORT_t 챔피언십 — 발굴 표 + 재검증 큐 (2026-07-10)

**상태**: Mine 완료 / 재검증 5슬롯 + 종합 = 월 지출한도로 무산출(전부 null) — 한도 해소 시 아래 재검증 큐(R1~R3+조건부)부터 재개. 도훈 mandate '최상급 PORT_t 밀어붙여' 이행 기록.

발굴 완료. 최종 챔피언 표를 정리합니다.

## 챔피언 전수 발굴 결과 (PORT_t ≥ 3.0, 역대 전 basis·전 tier)

루트: `C:/Users/99922/OneDrive/Quant_Module_Moltbot/` (아래 경로는 루트 상대). 스캔 범위: `.cache/lcode_corpus.json`(256 L-code) · `06_Registry/hypothesis_index.json`(866 entries) · `research_ev_map`(flat rows 256) · `stage_artifacts/`+`04_Research/` 전체 6,336 파일 regex 실측 추출(98 파일 hit). b434/alpha_search 06-12~13 배치에서 PORT_t≥3 관측 **0건**(b434 오염은 라벨 이슈로 PORT_t 미기록) — 챔피언 풀에 b434 오염 없음.

### A. 챔피언 표 (관측치 상위, 중복 클러스터 통합)

| # | id | 관측 PORT_t | basis | metric_type | 측정 창 | kill/미채택 사유 | 원본 경로 | 오염 플래그 | 재검증 가치 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Shu-Mulvey ext_m5_roll (RAMP)** | **7.72** (V2 cv 7.65, TE4 8.59) | pt_capwt (인덱스/팩터군 배분 레벨) | backtested | 2009-2026 208m, 인과 rolling re-tune | MINY=5 GFC-훈련 의존 · cost 5bps idealized(≠KR 15bps) · IR idealized · **25종목 전이 시 전부 음수 PORT_t 실측**(non-deployable) · governor 정지 | `stage_artifacts/l_code/ramp/l_code_RAMP_SHUMULVEY_FINAL_20260619.json` · `04_Research/ramp/reports/shumulvey_faithful_replication_20260619.md` | 없음 (basis 라벨 주의: idealized) | **중상** — MINY5/5bps는 재측정 판별형. 단 25종 전이 실패는 이미 실측 → forensic만 유효 |
| 2 | **bare book (오버레이 無 STR_1715)** | **7.236** | cap-w active vs K200 | backtested (weighted_screen contract) | 269m 2004-02~2026-06 | 미채택 사유가 게이트 FAIL이 아님 — "오버레이 없음 레퍼런스"로만 취급, MDD 40.7%(graduation HARD 아님·calmar 1.118 PASS), **oos_retention 미측정** | `04_Research/factor_rotation/predictive_overlay_ab/VERDICT.md` | label-suspect(하네스=weighted_screen, canonical 아님) | **최상** — kill 사유 자체가 부재. oos·DSR 1회 측정으로 판별 |
| 3 | MEGACAP_ANCHOR_CAPRELAX base | 6.6996 (oos 0.7358) | cap-w canonical | canonical_screen | 268m | **cap>0.20 relax = envelope 위반(INV-7 재도전 금지)** + 앵커 marginal 소멸(6.69 vs base 6.66) + relax 단조 악화 실측 | `stage_artifacts/l_code/qepm_legacy/l_code_STR_MEGACAP_ANCHOR_CAPRELAX_20260706.json` | envelope-외 | 없음 (INV-7) |
| 4 | **production book BASE (현직 챔피언)** | **6.272** (oos 0.553 · calmar 1.922) | cap-w active | canonical_screen (carrier parity cor 1.0000) | 268m | 없음 — 현직. 단 oos 0.553=band → book 신규 graduation 주장엔 구속 | 동일 L-code (`L-QPM-20260706_083113`) | 없음 | 기준선 재고정 필수 (vintage 민감: 동일 book이 6.21 frozen/6.17 재현/6.13 NOL4/6.02(257m)/5.998 corrected(247m)/5.47 recon-cache/4.925 IS-168m로 산포 — §7 pin_cache) |
| 5 | **book+value sleeve blend w=0.15 (corrected)** | **6.218** (book 5.998 대비 ΔPORT_t +0.22) | cap-w active, corrected alignment | backtested | 247m | dSR −0.037(음) + ΔIR +0.036 < 0.05 게이트 → DEFER. **PORT_t 기준으론 개선이었음** | `04_Research/composition_search/value_sleeve_combination/corrected/blend_result_corrected.json` · `04_Research/pg2_forensics/realized_ym_offset_report.md` | 없음 | **높음** — kill이 SR/ΔIR 목적함수 기준. PORT_t-mandate로 재판정 가능 |
| 6 | x-attn allliq (WT-D20260705_001) | 6.06 (seed0 ad-hoc 5.14, 3-seed ~4.3) | 광역 allliq 유니버스 EW | backtested (alpha_validation) | ~196m | UNIVERSE_MECHANISM_MISMATCH — deployment 유니버스 forge 2.36 실측 · pre-2018-only(3.50→0.41→−0.31) · seed 불안정·oos −0.19 | `stage_artifacts/WT-D20260705_001/alpha_validation.json` · `stage_artifacts/l_code/judge_gate/l_code_WT-D20260705_001.json` | 유니버스≠배포 | 없음 (deployment 실측 존재) |
| 7 | **O3_MIDBAND_FLOOR (overlay combine 변형)** | **5.679** (INC 5.255, ΔPORT_t +0.424 · dSR +0.029 · 전 게이트 비열등) | cap-w active, forge-authoritative | backtested (build_bt_result+audit) | 267m FULL (06-12) | **실측 부정 아님** — governor+도훈 confirm 3건 선행 대기로 정지 → 07-02 Layer4 제거 재편으로 stale. caveat: 밴드상수(0.25/0.5) full-sample 유래 · BM 캐시 드리프트 | `04_Research/composition_search/cycle2_trackF/trackF_comparison.json` · `trackF_recommendation.md` | 설계상수 오염 caveat | **높음(조건부)** — 07-05 `pg2_overlay_beyond_r05m4` 16변형 그리드에 동일 공식 포함 여부 선확인 필요(포함이면 종결) |
| 8 | DPL IS 앙상블 (ENS_config5/K16/K8 등) | 8.60 / 8.21 / 8.03 / 6.34 / 6.14 | cap-w active | backtested, **IS-only** | 228m IS | OOS SR 0.75~0.89 ≪ PG2 1.52 실측 — **settled-negative, 재제안 금지** (06-26) | `stage_artifacts/WT_DPL_GPU_SWEEP/ens_eval_contract.json` 외 | IS-only | 없음 |
| 9 | megacap anchor discovery C2 → forge | 4.76 (재현 4.75, forge 4.53 oos 0.894·calmar 0.571 FAIL) | **벤치-상대**(cap-w active) | canonical→backtested | 268m | 벤치허깅(TE 축소) — 총수익 SR 1.142→1.044 하락·book-marginal paired NW-t −1.52 실측 | `stage_artifacts/WT-D20260706_001/alpha_validation.json` · `l_code_WT-P20260706_001_megacap_anchor_forge.json` | basis=벤치상대 de-rate | 없음 (cycle5 실측 종결) |
| 10 | 잔차모멘텀 judge Gate C | 4.90 | cap-w active full-sample | backtested | 268m | R05-dominated·IS-dominated NON-DECISIVE — book 자체 알파, sleeve 기여 아님 | `stage_artifacts/WT_D20260606_001/judge_verdict.json` | book-carried | 없음 |
| 11 | E2E-gate broad | 4.87 → deployment 2.36 | 광역 broad 유니버스 | backtested | ~196m | oos FAIL + 마이크로캡 + deployment 전이 실측 2.36 | `04_Research/factor_rotation/fof_first_slice/factor_of_factors_precise_definition.md` | 유니버스 | 없음 (6방법 全 oos FAIL 실측) |
| 12 | IPCA K6 / KNS / BMA (superfactor) | 4.22 / 3.78·3.72(oos reten −0.08·−0.17) / 3.06 | 광역 allclean/allliq EW | canonical_screen | 196m 2010-2026 | 全 oos_retention FAIL·2022+ 사멸·마이크로캡 — KNS/전종목/shrinkage 재시도 금지 등재 | `04_Research/factor_rotation/fof_first_slice/_kns_contract_*.txt` 등 | 유니버스 | 없음 |
| 13 | insider nflow band (역사 파서) | 3.8055 (band, raw 1.13) | cap-w, top-25 | backtested | **n_signal_months=16** contiguous_run | 표본 극소(16개월) — 백필 진행중(타 세션 소유, 무간섭) | `stage_artifacts/insider_graduation_harness/reports/graduation_gate_result.json` | 저표본 | **보류** — 백필 완료 후 자동 해소형. 본 토너먼트 무간섭 |
| 14 | smartbeta allstock D2 loser-penalty | 3.703 | cap-w active | backtested | 276m | **lag1 스트레스 KILL 실측**(3.703→2.857, MDD 완화 소멸) — vol-target 아암만 lag1-robust 생존 | `06_Registry/overlay_candidate_queue.json` · `04_Research/01_reports/architecture_audit_20260703.md` | 없음 | 없음 (lag1 실측) |
| 15 | RAMP_03 MOMCONS book-결합 | 3.37 pt_capwt (당시 book 2.64 대비 전지표↑, cor −0.037) | pt_capwt | backtested | 2005-2026 | 06-20 당시 RAMP-book(SR 1.36) 기준 — 현행 book(6.27)으로 교체돼 stale. 07-05 ortho-sleeve 스택 11군 실측 FAIL과 family 중첩 의심 | `stage_artifacts/l_code/ramp/l_code_RAMP_03_MOMCONS_IC_20260620.json` | stale-baseline | 중(조건부) — 07-05 R1 11군에 momentum-consensus 포함 여부 선확인 |
| 16 | fwd consensus level | 3.51 | cap-w canonical | canonical_screen | 297m | oos 0.253(<0.5 무조건 FAIL)·2017+ flat 실측. screen_route=DPL_FEATURE | `stage_artifacts/l_code/alpha_research/l_code_WT-D20260705_003_fwd_consensus_level.json` | 없음 | 없음 |
| 17 | RAMP graduation M_regdd | 3.66 (pt_EWuni; cap-w 2.37) | **EW-uni 진단**(cap-w 아님) | backtested | 257m | cap-w authoritative 2.37 미달·oos 0.15·calmar 0.37 | `stage_artifacts/l_code/ramp/l_code_RAMP_GRADUATION_20260618.json` | basis=EW-uni | 없음 |
| 18 | D45 defense swap | 5.509 (recon base 5.466) | cap-w active, recon-vs-recon | backtested | 269m | 07-03 방어팩터 전수 + book swap 4안 CLOSED(도훈 confirm — 현 {Q07/M08/Q25} 확정최적) | `stage_artifacts/pg2_defense_optimize/c3_swap_D45_marginal.json` | 없음 | 없음 (settled) |
| 19 | 금일 확정 제외군: 5축 joint 3.282(OOS −1.63)·drain probes(P3 multisleeve tail 4.28/base 4.806·P5 flow incumbent 4.52 IS)·V02_EP EW 4.40(cap-w 2.52)·다축직교 EW 4.10(cap-w 2.08) | — | EW-basis 다수 | canonical_screen | 07-10 | 금일 확정 — 임무 지시로 재검증 제외 | `stage_artifacts/WT-D20260710_00{1,2,3}/` · `stage_artifacts/P5_flow_persistence/` · `l_code_P3_MULTISLEEVE_TAIL_20260710.json` | EW-basis 병기 | 제외 |

기타 3.0~3.7 잔여(모두 kill 실측·재검증 무가치): pg2_composite B_split_75 3.691(paired-t 0.98 비유의), trackV/trackD/trackW IS·bench-상대 산포(3.0~5.3, anchor 계열 oos 0.17~0.19 FAIL), FLOW proxy 3.55→forge 2.35(measurement-graduation 원전 사례), value_sleeve WT-D20260611 IS 3.26(retention −0.05).

### B. 재검증 지정 (상위 6 + 조건부 2)

| 순위 | 후보 | 재검증 스펙 (1줄) |
|---|---|---|
| R1 | **book BASE 6.272 (기준선)** | pin_cache 고정 단일 canonical carrier로 재측정해 토너먼트 기준선 고정 — vintage 산포(5.47~6.27) 제거, pin tag 기록 |
| R2 | **bare book 7.236** | 동일 pinned 하네스에서 exposure=1.0(오버레이 全제거) vs noLayer4 book A/B — oos_retention v2·calmar·DSR(chain)·paired NW-t 측정하면 "미측정 oos"라는 유일 미지수가 판별됨 (kill 사유 부재 후보) |
| R3 | **blend w=0.15 6.218** | 현행 noLayer4 book·현행 pin으로 value sleeve 5~20% grid 재측정 — PORT_t-목적함수 기준 ΔPORT_t + paired NW-t + lag1 스트레스로 "SR-기각이 PORT_t-챔피언을 죽였는가" 판별 |
| R4 | **Shu-Mulvey 7.72 forensic** | transfer-loss 분해: 인덱스→25종 이산화를 단계별(15bps 재과금→MINY8→GFC-제외→25종 컷)로 재측정해 pt 7.72가 어느 단계에서 죽는지 특정 — idealized caveat 2종(5bps·MINY5)은 재측정 판별형 |
| R5 | **O3_MIDBAND 5.679 (조건부)** | 선확인: 07-05 `pg2_overlay_beyond` 16변형 그리드에 동일 공식(g<0.25 pass-through + floor 0.5) 포함 여부 — 미포함 시에만 noLayer4 book 이식 clean+lag1+IS/OOS 재측정 (INV-7 차별점: forge-authoritative 전 게이트 비열등 PASS 이력 보유) |
| R6 | **caprelax 관측의 clean 성분 6.66** | cap=0.20 유지(envelope 안) book 구성이 6.66을 기록한 조건(268m carrier)을 R1 기준선과 동일 pin에서 대조 — 챔피언 수치가 구성이 아닌 창/캐시 차이인지 확정 |
| 조건부-1 | insider band 3.81 | 타 세션 백필 완료 후 n_signal_months 16→230월 확장 재측정 (본 토너먼트 무간섭) |
| 조건부-2 | RAMP_03 MOMCONS 3.37 | 07-05 R1 sleeve-stack 11군에 momentum-consensus IC-가중 포함 여부 확인 — 미포함 시에만 현행 book 대비 book-marginal ΔIR 1회 |

### C. 핵심 발견 (토너먼트 설계에 직결)

1. **PORT_t 관측 최상단은 전부 "book 자체 또는 book의 무-오버레이/blend 변형"** — 신규 알파가 아님. 역대 신규-알파 최고는 광역-유니버스 아티팩트(x-attn 6.06, E2E 4.87)로 deployment 전이 시 전멸.
2. **오버레이는 PORT_t를 구조적으로 깎는다**(bare 7.24 → book_L5 5.14, 메커니즘: 현금화가 강세장 active 수익 축소) — "최상급 PORT_t" mandate와 "MDD 방어" 배포책이 목적함수 충돌. bare book의 oos_retention이 유일한 미측정 미지수.
3. **book 측정치의 vintage 산포가 ±0.8**(5.47~6.27) — 재검증 전 pin_cache 기준선 고정(R1)이 선행돼야 나머지 비교가 유효.
4. PORT_t-기준 기각이 아니었던 후보 2건(blend 6.218=SR-기각, O3 5.679=절차 정지)이 실질 도전자.

---

# 최종 결론 (2026-07-10 재개 후 재검증 완료 — pin tag fq011_20260710_222924)

**최상급 PORT_t = 현 운용 북 (pinned 6.130). 도전자 전멸.**

| 후보 | 종전 | 재검증 | 판정 |
|---|---|---|---|
| bare book | 7.236 (kill 부재) | 6.344 — IKS001 벤치버그 아티팩트 (벤치-격리 4경로 수렴 입증) · oos_v2 0.613 FAIL · MDD 40.7 위반 | 강등 |
| value blend w=0.15 | 6.218 (+0.22) | dPORT_t -0.067 · paired NW-t -2.946 유의 음 — stale-baseline 아티팩트 | 기각 강화 |
| production book | 산포 5.47~6.27 | **6.130 (pin 고정)** · oos_v2 0.500 band (247m 창 0.746 병기) | **현직 확정** |

**오버레이 경제학 (첫 정량화)**: PORT_t 비용 +0.214 (paired t 0.767, 비유의) ↔ 구매한 것: MDD 40.7→23.3 (-17.4p) · calmar 1.118→1.943 · abs_SR 1.678→1.897. 순이득 구조 실측 확증.

**메타 규칙 (신설)**: 07-02 IKS200 벤치 수정 이전의 고-PORT_t 기록은 인용 전 재베이스 의무 — 역대 챔피언 2개가 전부 그 버그 산물이었음. Step 0: RAMP_03 = R1 family 중첩 제외 / O3_MIDBAND = 잔여(저순위, base 구판).

L-code: FQ011_CHAMPIONSHIP_REVAL_20260710 · 산출: stage_artifacts/fq011_port_t_championship/
