# Weekly Digest — 2026-W29 (증류일 2026-07-18)

**커버 범위**: 2026-07-12 ~ 07-18 (직전 digest `weekly_digest_20260711.md` 이후)
**기계 스윕**: `.cache` 스크래치 29건 삭제 (RAMP R1/R2 probe·run 로그, hygiene_manifest 기록)
**지식 델타**: 신규 L-code 61건 · hypothesis_index 866→905 (+39) · git 257 commits (전량 auto-commit + task #62 cherry-pick)
**실측 라벨 규약**: 아래 수치는 각 L-code/run 산출물의 기록값 전재 (measurement-graduation §1, `metric_type` 병기). 재구성·추정 없음.

---

## ★ 이번 주 최중대 — 저장 패널 동월 look-ahead 사고 확정 (07-14)

**가설/사건**: 밸류 팩터 재검증(Z6 라운드)에서 R26→R27 PORT_t가 이상 급등(2.08× 부풀림) → 원인 추적.
**결론**: 저장 268m alpha 패널(`alpha_scores_str1715_268m.parquet`)이 **전기간 동월 vintage**(~1개월 look-ahead)로 구성됨 — production 코드 경로는 T-1로 clean. 판정 이중 반전: R26 병합결함 과소 → R27 3.807 과대 → **R29 clean 재빌드 1.0~1.7 = FAIL**.
**수치·출처** (`metric_type=canonical_screen`, [[project-stored-panel-samemonth-lookahead]]): 부풀림 배수 2.08×. clean 재산출 후 자본 게이트 FAIL. 단 **밸류 신호 자체는 진짜**(EW-universe 6.39). book 6.130 재산출은 도훈 결정 대기.
**교훈(제도화)**: placebo/lag-stress는 candidate 무결성만 시험 — **base 패널 vintage 오염은 못 잡는다**. 검거 도구 = vintage-swap 통제 + window-matched control. → 규칙 `measurement-graduation` **§7b 신설**(07-14): incumbent base = `05_Production` 현행 코드 파생 신호만 권위, 파생 저장 패널 소비 금지, `production_parity_verified` 라벨 의무. [[feedback-production-code-as-baseline]]

---

## 실험별 결론 (시간순)

### 1. 선별-규율 → construction chain 완결 (07-12~13)
- **R8 band escalation** (L-RAMP-20260712_175852, `canonical_screen`): R7 'EW-real 미달' 판정 정정 — EW-oos 0.5064 ∈ [0.5,0.7) band에 §3 보강증거 escalation 적용 → e1 trailing PORT_t 1.46>0 PASS · e2 placebo p=0.000 PASS · e3 book-marginal FAIL = 2/3 **band_escalated**(D3형 벤치-상대 배포성 재료 자격 회복). 자본 게이트 cap-w 3/3 HARD FAIL 불변.
- **R10~R16 construction chain** (L-AR-20260713_133212 외): 챔피언 구성 확정(반기 진입·분기 순위퇴출·수준충원) cap-w **2.937**·oos **+0.048**. **cap-w ~2.94 / oos ~+0.12 천장이 construction-invariant** — 진입·퇴출·충원 3축 어떤 조합도 이 천장 못 넘김. R16 마이크로스트럭처 5종 = config-scoped negative(3-게이트가 AMH_D 중복 자동 차단). 메타: market-data 파생도 동일 벽 = 재료가 아니라 long-only 횡단선택의 cap-w 전이. [[project-selection-discipline-arc-r4r5r6]]

### 2. 밸류 팩터 아크 R26~FQ-046 (07-14)
- **가설**: 밸류 신호를 신규 소비 형태로 자본 게이트 통과시킬 수 있는가.
- **결론**: 신호 실재·직교(팩터 max|cor| **0.46**, EW-uni **6.59** judge-생존)이나 **소비 형태 5종 전수 자본 미달**. 기전 2개: ① 25종 슬롯 제약이 직교 밸류를 실현 중복으로 만듦(active corr **0.98** — "북이 이미 밸류다"가 아니라 슬롯제약×전이벽) ② 2024+ value-vs-mega 역전(lockbox oos **−1.19**). judge **REJECT·RETAIN**. value_z = OVERLAY_CANDIDATE 보존, 부활 = 스타일 로테이션 반전. tier-조건부가 cap-w 벽을 screening 관통한 첫 실증. [[project-value-factor-arc-20260714]]

### 3. 지각제출 × 심각사건 아크 R22~R24 (07-13)
- **결론**: 극단 지각제출(top-decile) → 심각사건 lift **10x** · 27개 독립회사 LOO 전생존 = 부실 지문 지식 강건 확립. **단 사고가 전부 소형주**(중대형 극단지각 0사고) = 배포 유니버스 밖 국소 → 자본 캡. 교훈: union 희석·월중복계상(episode-level이 정답)·양방향 goalpost 규율. 소비 = monitoring tripwire. P2 coverage = FQ-038(쿼터 대기). [[project-latefiling-severe-event-arc]]

### 4. insider 재료 밤샘 라인 R9~R37 (07-15)
- **결론**: pool-선별 자본 게이트 KILL(102-풀 중복)이나 **순매수 클러스터 monitoring 전환 시 유효**(per-holding SAFE · mid-cap 강건 · 대형주 genuine death 검정력 1.0). tripwire 배선(`filing_delay_watch` Part C, monitoring-only·자본 아님). "소비면 전환 전략" 실증(R24/R25 지각·감사와 동형) · tercile≠분위 함정 자기교정. cohort-path = 분산 아티팩트. WT_D20260715_001~016 연쇄. [[project-insider-monitoring-line-20260715]]

### 5. rawdata Ret 무결성 방화벽 R42~R46 (07-15)
- **결론**: stored Ret = 참값 · recompute(Close/shift-1) = Close-hole artifact(R45가 R44 판정 반전). 물리불가 오염 343건 거의 전량 non-index microcap · 라이브 factor 무영향(현 북 유니버스 필터가 이미 배제). **Ret winsorize 방화벽 부재 → R44 `ret_sanity_firewall` 배선**. factor_db = stored Ret 직접소비(오염 아님 확인). 잔여 근본수리 = 4월 이음매 microcap KRX 백필(245 구멍·armed). [[reference-rawdata-ret-firewall-20260715]]

### 6. 텍스트 난독화 Phase A = screen-tier (07-12)
- **결론** (L-AR-20260712_152759, `canonical_screen`): 사전등록 composite NULL(placebo p 0.716) · m1 문장길이만 Size-무관 실신호(cap-w **2.35**<2.95·소형 국소화·2019+ 감쇠). ★합성-희석 교훈: m1 빼면 composite 부호 반전 = 다지표 합성이 유일 신호를 죽임(단일지표 분해 의무). m1 = OVERLAY_CANDIDATE feature 보존. text_cache 4,490건 재사용 자산. [[project-text-obfuscation-phasea-screen-tier]]
- **m1 overlay drain** (L-AR-20260712_175553, `canonical_screen`): 4 arm 전부 paired NW-t<2.0(best 1.27) = screen-tier, feature 보존. PIT C5 가드 4종 통과.

### 7. 인프라·거버넌스 (07-14~17)
- **Continuity Firewall 구축** (07-15 도훈 mandate): 종결 프레이밍 ∧ 계속-산출물 결측 턴을 Stop hook **block**(warn→강제속행). 4레이어(차단 이빨 + 독립 semantic 판정 `continuity_gate.py` + 건설적 종료계약 `close_round.R` + 자가발전 `continuity_cases.json`). 배터리 12/12·훅 E2E GREEN. 판정 자체는 불차단(AX-000·INV-7 정합). [[project-continuity-firewall-20260715]]
- **forward-returns 터미널월 liq 공백 수리** (07-14, cherry-pick 2ef34ffb): `build_monthly_forward_returns`가 마지막 sig_date 드롭 → 터미널월 NA-passthrough가 liq 필터 무력화. 러너측 LIQ_DT 보충(함수 무변경)·과거월 parity max|Δ|=0(n=80229). [[reference-forward-returns-terminal-month-liq-gap]]
- **무인 스케줄러 지도 + 반복 캐시알림 수리** (07-17): 같은 알림 4원인(미배선 producer·elestock corp_code 버그로 insider incremental 영구실패·on_demand SLA 잔존·dedup 부재) 전부 수리. DART_Insider_Backfill 258/258 완료(no-op). ★StopIfGoingOnBatteries=True → 장시간 작업 임의 kill 실측. [[project-scheduler-cache-freshness-repair-20260717]]
- **외부 alpha 동향 갱신** (07-17): alpha decay hyperbolic(post-2015 가속) · crowding=tail-only · LLM=인프라 컨센서스 · transformer AP — 외부도 비-return/텍스트 원천 방향으로 우리 posterior와 수렴. [[reference_alpha_trends_2024_2026]]

---

## Axiom 후보 현황 (step 3.5 promote 진단 집계)

- **pending 48건** (전량 미승격). 실패 축 히스토그램: external 42 · independence 41 · falsification 31 · mechanism 19 · rigor 3. → 승격을 막는 지배 결측은 **external(외적 타당성)·independence(독립성)** = "다른 유니버스/기간에서도 성립하나"와 "기존 팩터와 독립인가"가 대다수 후보의 미충족 축.
- **near-miss 3건** (1축만 미달 — 초안 정제 대상, 도훈 confirm 건별):
  1. `CAND_...distress_smallcap_wall` (external 미달, score 0.80): distress-fingerprint 비-return 재료(포렌식·지각·감사/going-concern/정정)가 배포 유니버스 long-only 자본 레버로 무효 — R24/R25/R9 3연속 독립 라운드 동일 벽. **negative 규칙 후보.**
  2. `CAND_...quality_profitability_positive` (independence 미달, score 0.94): ew_survivor·benchmark_artifact·cap_tier_trap 태그, supporting 3건. ⚠라벨이 "positive"인데 quality_profitability는 기존 AX-004 negative 계열 — **극성 재확인 필요**(오분류 의심, 아래 처리).
  3. `CAND_...legacy_value_conditional` (falsification 미달, score 0.83): value 조건부, supporting 14건(L-132/135/142). DIST-QPM-006과 중복 가능성 점검 필요.

---

## 후속 — 증류 완료 결과 (10:05 최종 정합, task #89)

- **near-miss 정제 → proposed 초안 [완료]**: ① `DIST-AR-018`(distress 소형벽, negative) **proposed** — 5체크 적대검증 PASS, frontier 3건(FQ-038 중대형 표본·재료별 개별 필터·공매도 교차)+live_trigger+expiry 2027-07-18. 원 후보 부활조건 중 '유니버스/벤치 재정의'는 제약-완화성으로 제외(INV-7). ② `DIST-QPM-015`(value 조건부) **proposed** — falsification_draft 9건+ 실값(무형조정 반증·accrual·crowding·AND-gate·축교체) 확인, DIST-QPM-006(EP standalone)과 상보 명기. ③ `DIST-AR-022`(quality_profitability "positive") **expired** — 클러스터 오귀속 확정(supporting 3건 이질: dual-basis 스크린/챔피언십 재검증/timing-luck·polarity 오라벨), 개별 지식은 L-code Ledger 보존, 근본원인 chip task_07f3ac0e. **approval queue 3건 노출**(AR-018·JG-001·QPM-015, `list_proposed()` 확인) — 활성화는 도훈 `approve_proposed()` 배치 승인 게이트(INV-6).
- **continuity 신어 후보 6건 [완료]**: 6건 전부 실블록이었음(pending 캡처는 `_capture_pending`이 block 시에만 발동). violation 1건 승격("고EV 프론티어 소진…마지막 정교화" = exhaustion_verdict 신어, 07-15 03:55) + pass 2건 승격(진행-중 중간보고·브리핑 텍스트 = 오탐 방지 few-shot) + 3건 중복 dismiss. `next_probe_markers += ['다음 큐','남은 큐']`(오탐 4건 공통 결측 어휘 기계 수리). 승격 후 게이트 스모크: 동형 신어 재차단 확인. 케이스 라이브러리 8→11건.
- **잔재 삭제 [완료]**: sweep 29건 + 수동 13건(hygiene root_unauthorized 7 + `.bak_20260713` 편집백업 6 — 전건 참조0 검증) — `06_Registry/distill_manifest_20260718.json` 기록. 보존-deferred: OPTIMIZER_DONE(WT 계약 아티팩트 동명)·live-hygiene 롤백 .bak 2건·`.cache/_*` 106건(활성러너 참조)·스테일 워크트리 2본·pin/rawdata 백업 일체.
- **hypothesis_index 재수확 [완료]**: 905→**950** 엔트리(07-13 stale 해소 — 이번 주 L-code 반영·wt_inflight 117·parse_fail 0).
- **L-code 갭 [해당 없음]**: W29 라운드 전수 emit 확인(alpha R26~R40·ramp R33~R47 무결성 라인·RAMP R9~R15·judge) — 신규 발행 0건(재발행 금지 준수).
- **미해소 상위 대기**(도훈 결정): axiom proposed 3건 배치 승인 · book 6.130 재산출 · 공매도 QW export(FQ-003, 최고 EV 비-return lane) · G2 캐리 실주문. (월 지출한도 D1은 2026-07-18 삭제 — 한도는 Anthropic 구독 외생 변수, 아키텍처 관리 대상 아님. 무인 실패 감지 경보는 유지)
