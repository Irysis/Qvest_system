# 자동 스폰 배선 설계안 — 미승격 전략 개선 루프의 기계화 (도훈 결정용 제안서)

- **작성**: 2026-08-16, Q-Lead. 도훈 승인 라운드 (2026-08-16 "① 자동 스폰 배선 설계라운드 진행해줘").
- **범위**: QEPM 미승격 전략(screen_route 라벨)의 ①개선-여지 자동 평가 첨부 ②개선 라운드 자동 개시 ③재설계 재진입 루프 닫기. **구현 아님 — 설계·결정 재료.**
- **근거**: 6축 배관 지도화 (읽기 전용, 6 에이전트, 도구 호출 218회 — 라벨 발급·드레인 도구·평가기·트리거 표면·거버넌스 레일·소비 계약). 인용 수치는 전부 코드/원장 실측.
- **불변 전제**: governor admit·book_state 쓰기·실주문은 어떤 안에서도 수동 (헌법 CLAUDE.md "자본게이트 book confirm+실주문 2버튼만 수동" — 역으로 그 앞 전 구간은 자동화 허용 영역이 헌법에 명시되어 있음).

> **★구현 상태 (2026-08-16 갱신)**: 도훈 결정 — **D1 = L1 채택, D3 = P0부터** (2026-08-16). **P0 루프 닫기 수리 4건 구현 완료 + 위반 주입 테스트 25/25 PASS** (`08_Tests/hooks/test_p0_loop_closure.R`, 배터리 등재):
> ① hypothesis_index 원천 (g) `overlay_ab_results` 등재 — 재빌드 실측 1,233 entries에 `OVL_` 19건 유입, 스테일 감시 포함
> ② `drain_verdict()` dv_v1 판정 코드화 + `--verdict-batch --write`로 기존 19건 스탬프 — **양성 대조: 07-10 STR_AS_ 16건 전건 INFERIOR = 세션 수기 판정(L-OVL-20260710_153559) 재현**, 스키마 다른 LH 계열 2건은 INDETERMINATE(억지 판정 금지)
> ③ `close_round()` frontier 선언↔실기록 대조 — 부재 FQ-id 비차단 경고 + `frontier_update_verified` 구조 필드. ★도입 당일 위반 주입 T3b가 실결함 검거(id 추출 정규식 상한이 긴 id 절단 → `FQ-[0-9]+`로 수리)
> ④ `st_record_disposition()` + CLI `--dispose=` — 처분 원장 기록 배관 (원자 쓰기 + 기록 후 재읽기 확인)
> 미착수 잔여: Layer 1 enrichment 어댑터 · Layer 2 auto_spawn_queue · Layer 3 `/improve-drain` 스킬 + 부트 주입 (다음 구현 라운드). **D2(소비자 0 라벨 2종 처분)는 미결 — 도훈 결정 대기.**

---

## 0. 요약과 결정 요청

**현행 루프의 병목은 "판단"이 아니라 "전달"이다.** 라벨 발급(자동) → 큐 반영(수동) → 개선-여지 평가(부재) → 드레인 실측(수동 개시) → 판정(세션 수기) → 지식 환류(단선) 체인에서, 기계화 가능한 칸이 5개 비어 있고 그 중 2개 라벨(FR_RCMA·TURNOVER_REVIEW)은 소비자 코드 자체가 0건이다.

**권고: L1 (평가·적재 무인 + 개시는 세션) 채택.** 무인 영역은 Rscript 기계 실측까지로 하고, LLM 리서치 라운드의 개시는 부트 주입 + 전용 스킬 소비로 남긴다. 근거는 이 시스템 자신의 전례 3건이다:
- 성공 전례: 주간 cleaner의 "크론 적재 + 세션 소비" (claim 선점 프로토콜까지 완비, `weekly_cleaner_sweep.R` 설계 주석 "무인 LLM 호출은 권한/판단 리스크로 배제")
- 부정 전례 1: 훅의 LLM 라운드 자동 스폰(codex_round_auto_trigger)은 v8.2에서 폐지
- 부정 전례 2: 크론 무인 루프(RAMP_AutoLoop)는 엔지니어링 결함(트리거 오설정 매시간 발화 + 전역 `taskkill //F //IM Rscript.exe`가 타 태스크 R 강제 종료)으로 rc 0xC000013A → Disabled 57일 — 사인은 무인화 개념이 아니라 구현 결함이나, 무인 실행의 위험 표면을 실증

**도훈 결정 3건**: (D1) 자동화 수준 L0/L1/L2 택일 — 권고 L1. (D2) 소비자 없는 라벨 2종 처분 — FR_RCMA는 "register_module 유도 라벨"로 재정의 또는 발급 중단, TURNOVER_REVIEW는 기록 전용 명시 유지. (D3) L1 채택 시 구현 우선순위 — §6의 P0(루프 닫기 수리 4건)부터.

---

## 1. 현행 실태 (as-is 실측 지도)

### 1.1 체인의 각 칸과 상태

| 칸 | 상태 | 실측 근거 |
|---|---|---|
| 라벨 발급 | **자동** | `hurdle_gate.R:1642-1665` — screen_pass 판정 + 4-route 분기, `hurdle_result.json` 기록 |
| 발급 시 컨텍스트 | **경로 의존** | alpha-search 런은 `strategy_manifest.json`에 재현 충분 컨텍스트(factor_engine_path·execution config·bt_result_path·authoritative essence, `run_alpha_search.R:788-882`). 레거시 `run_all.R` 호출자 수십 건은 `hurdle_result.json`뿐 — NAV 경로·config 부재로 자동 평가 불가 |
| 권위측정 사다리 | **자동 (전례!)** | screen_pass ∧ route 매칭 시 같은 런에서 `.authoritative_remeasure()` 자동 실행 (`run_alpha_search.R:325-345`) — "라벨이 후속 측정을 자동 트리거"하는 구조가 이미 가동 중 |
| 큐 반영 | **수동** | overlay·standalone 큐 빌더 둘 다 수동 Rscript 전량 재생성. overlay 큐는 2026-07-10 이후, standalone 큐는 2026-08-02 이후 신규 라벨 미반영 |
| 개선-여지 평가 | **부재** | 라벨에 우선순위 근거 없음. 원재료는 전부 실재 (§2.1) |
| 드레인 실측 | **도구 완비·개시 수동** | `overlay_candidate_drain.R` — 후보 1건당 5시나리오+비용변형+strict-PIT ≈10회 계약 측정, 후보당 수 초 (16건이 2분 창 내 완료 실측). PIT 3종 stop() fail-closed·원자 쓰기 — **무인 실행 안전 구조 실증**. 단 배치 모드 없음·status 재검사 없음(재실행 시 덮어씀) |
| 판정 | **세션 수기** | 결과 JSON에 verdict 필드 부재 — 07-10 "SURVIVOR 0/INFERIOR 16" 판정은 세션이 paired NW-t vs null max-t 비교로 수행, L-code에만 기록 |
| 지식 환류 | **단선** | 드레인 결과 디렉토리는 hypothesis_index 원천 목록에 부재 (자동 환류 0). `close_round()`의 frontier_update는 서술 문자열일 뿐 큐를 쓰지 않음 (FQ-167/168 병렬 충돌 실사고의 근원) |
| 처분 원장 | **공백** | standalone 큐 미처분 50건에 `dispositions.json = {}` (처분 기록 0건) |

### 1.2 라벨별 소비자 실태 (`standalone_track_queue.R:60-67` 성문 + 교차 실측)

| 라벨 | 소비자 | 실측 |
|---|---|---|
| OVERLAY_CANDIDATE | ✅ 큐→드레인 체인 실재 | 17건 전원 measured (FQ-006, 전량 INFERIOR로 done_negative) |
| STANDALONE_TRACK | △ 부팅 상태라인만 | backlog 50건 처분 0 |
| FR_RCMA | **0건** | `regime_module_admission.R`·`register_module.R`에 screen_route 문자열 0건 — 라벨이 코드에 도달하지 않음 |
| TURNOVER_REVIEW | **0건** (설계상 기록 전용) | 발급 실적 0건 |

교훈 성문: FR_RCMA 무조건 첨부는 "판별력 0"으로 v8.3 폐지, DPL_FEATURE는 "소비자 0 = 죽은 주소"로 발급 중단 (`hurdle_gate.R:1655-1662` 주석). **소비자 실재 확인 없는 라벨 발급 금지가 이 설계의 제1원칙.**

---

## 2. 설계 — 3층 구조

### Layer 1: 개선-여지 평가 자동 첨부 (label enrichment)

**평가기 2종은 함수 단위로 실재하며 standalone 호출 선례가 있다** — 신규 개발이 아니라 어댑터 작성이다:

- **국면조건부 성과**: `compute_rcma(asof_date)` (`regime_module_admission.R:89`, 6기준 walk-forward PIT 셀 판정) — `.RCMA_FUNC_ONLY <- TRUE` source 패턴으로 모드 밖 호출 실증 (`run_wf_ensemble.R:22,108`). 단 입력이 fr_eligible 풀 전체라 **실패 전략 1건용 어댑터 신설 필요**: 전략 NAV(bt_result의 DAILY_NAV_DT) − 벤치 → 국면 라벨(`.cache/unified_regime_signal_daily.parquet`, t-1 shift) 조인 → per-regime IR/t/n_months. per-regime 산출 스키마는 `build_module_performance.R:163-166`이 이미 정의 (210모듈에 실사용, 2026-08-16 신선). "벤치 상승 구간 상회" 스코어 = 확장/상승 국면 셀의 IR·t.
- **dual-basis 진단**: `canonical_screen_bt(diag_dual_basis=TRUE, size_dt=)` — diag_ew_universe(EW-유니버스 대비 PORT_t NW3 등)·diag_cap_tier(MEGA/MID 분해) append 필드 이미 구현 (`canonical_screen_bt.R:89-228`), metric_type="canonical_screen_diag" 비바인딩. score 패널이 있는 alpha-search 런에서 즉시 가용.

**삽입점 (권장)**: alpha-search 러너의 `.authoritative_remeasure()` 직후 — 라벨→자동 후속측정의 기존 전례 위치에 enrichment를 잇는다. 산출은 manifest·큐 엔트리에 `improvement_potential` 블록으로:

```json
"improvement_potential": {
  "per_regime": {"EXPANSION": {"ir":..., "t":..., "n_months":...}, "CRISIS": {...}},
  "ew_universe_port_t_nw3": ..., "cap_tier": {...},
  "score": ..., "score_version": "ip_v1",
  "basis": "canonical_screen_diag",  // 자본게이트 주장 차단 라벨
  "pin_tag": "...", "regime_label_gate": {...}
}
```

- **pin_cache 의무 배선**: 두 평가기 모두 현재 pin 강제가 없음(grep 0건, 호출자 책임 방치) — enrichment 어댑터가 `read_pinned()` 경유를 강제하고 pin_tag를 블록에 기록 (§7 정합).
- 레거시 호출자(manifest 부재)는 `improvement_potential: {available:false, reason:"manifest 부재"}`로 정직 표기 (억지 산출 금지 — diag_cap_tier의 available=FALSE 패턴 승계).
- **큐 반영 자동화**: enrichment 완료 시 같은 런에서 큐 빌더 함수 호출(전량 재생성 idempotent 구조라 안전) — "라벨 발급→큐 미반영" 공백 제거.

### Layer 2: 스폰 정책 (누가 라운드를 받을 자격인가)

신설 `06_Registry/auto_spawn_queue.json` (cleaner_pending_v2 스키마 계열: pending/claimed/done + owner + claim 선점 — `cleaner_claim.R` atomic claim 패턴 재사용, stale 6h 재점유):

자격 = 전부 충족:
1. `improvement_potential.score ≥ 문턱` (초기 문턱은 보수적으로, §5 판별력 검증 루프로 조정)
2. **소비자 실재 route만** (현행 기준 OVERLAY_CANDIDATE; D2 결정에 따라 확장)
3. hypothesis_index 대조 — 동일 (전략, 개선축) config의 FAIL/측정 완료 기록 부재 (차별점 없는 재탕 차단, INV-7)
4. `dohoon_decision` 플래그 부재 (큐 consume_rule 승계)
5. capacity: 동시 pending 상한 (제안: 5) + 후보당 재적재 금지 — (id, config) 신원 기반, TG single-dispatch lock TTL 패턴 승계
6. 드레인류 기계 실측 후보는 `status ≠ measured` 검사 (현행 드레인 러너의 덮어쓰기 구멍 봉합)

**판정 계층 코드화 (신설)**: 드레인 결과에 `verdict` 필드 — paired NW-t vs null max-t(N에 따른) 비교를 코드로 이관, SURVIVOR/INFERIOR/INDETERMINATE 3치 + 근거 수치 동반. 세션 수기 판정의 재현 불가능성 제거.

### Layer 3: 라운드 개시 (spawn mechanism)

4방식의 전례 실측에 근거한 배정:

| 방식 | 전례 | 판정 | 이 설계에서의 역할 |
|---|---|---|---|
| (a) 훅 직접 실행 | 라우터 per-hook 30s 예산, timeout=fail-closed | 장시간 작업 불가 | 사용 안 함 |
| (a') 훅 detach 스폰 | `_spawn_distill_async` (nohup+start_new_session+flag 중복 억제) 현역 | Rscript 한정 가능 | **enrichment 자동 실행** (라벨 발급 훅 뒤 detach) — 대안: 같은 런 인라인(권장, 더 단순) |
| (b) 크론 무인 | RAMP_AutoLoop 사후: 트리거 오설정·전역 taskkill·팝업 → Disabled. 단 드레인 러너는 무인 안전 구조 실증 | **Rscript 기계 실측만** | 주간 스윕 확장: 신규 라벨 enrichment 일괄 + 자격 판정 + auto_spawn_queue 적재 + (L2 결정 시) 드레인 배치 실행 |
| (c) 크론 적재 + 세션 소비 | 주간 cleaner 확립 전례 (claim 프로토콜 완비) | **성공 패턴** | **LLM 라운드(재설계·모드 진입)의 유일 경로** |
| (d) 부트 주입 | boot 카나리아·bootstrap WARN 표면 다수 | 성공 패턴 | `[auto-spawn] pending N건 — /improve-drain 권장` 주입 |
| 훅 LLM 스폰 | codex_round_auto_trigger v8.2 폐지 | 부정 전례 | 사용 안 함 |

**핵심 분할 — "자동 스폰"의 대상을 둘로 쪼갠다**:
- **기계 실측 (드레인·enrichment)**: 무인 가능·안전 구조 실증 (fail-closed PIT·원자 쓰기·후보당 수 초) → L1에서 크론 무인까지 허용
- **LLM 리서치 라운드 (오버레이 재설계·FR/RAMP 진입·QEPM 가설 재설계)**: 적재+세션 소비만 — "무인 LLM 호출 배제" 설계 노트·codex 폐지 전례·판단 리스크

세션 소비 진입점: 신설 스킬 `/improve-drain` (가칭) — auto_spawn_queue를 claim하고, 라벨 유형별로 (i) 드레인 결과 verdict 리뷰→다음 단계 결정 (ii) 오버레이 재설계 WT (iii) FR/RAMP 진입 (iv) kr-inverse-pattern-miner 경유 QEPM 재설계를 분기.

---

## 3. 루프 닫기 수리 4건 (P0 — 어느 수준을 택해도 선행 필요)

자동화 이전에, 개선 라운드가 끝나도 지식이 다음 라운드에 도달하지 않는 단선 4곳:

1. **드레인 산출물 → hypothesis_index 원천 등재**: `06_Registry/overlay_ab_results/`를 인덱스 빌더 원천 (g)로 추가 — 현재 자동 환류 0 (method_registry 사건과 동형: 큐를 드레인해도 소비면이 닫혀 있으면 다음 Step 0 lookup에 안 보임)
2. **verdict 필드 코드화** (§2 Layer 2) — 판정의 세션 수기 의존 제거
3. **close_round frontier_update 선언↔실기록 대조**: close_round가 frontier_update 서술 시 큐 실기록 존재를 검사(경고 레벨부터) — FQ-167/168 "선언이 거짓이 됨" 재발 방지
4. **standalone dispositions 처분 배관**: 50건 backlog에 처분 기록 경로 (auto_spawn_queue 자격 판정 결과를 dispositions.json에 기록)

---

## 4. 하드 가드 (전 수준 공통)

1. **자본 경계**: 자동 경로에서 `book_state.json`·`05_Production/` 쓰기 도달 불가 배선 + governor 함수 호출 금지 (기존 성문 `portfolio_governor.R:197,721` 승계)
2. **dohoon_decision 제외** + 큐 CLAIMED/UNCLAIMED 선점·재읽기 확인 (consume_rule 승계)
3. **vintage pinning**: 자동 A/B·enrichment는 `read_pinned()` 경유 + pin_tag 기록 의무 — 평가기 코드에 현재 부재하므로 어댑터 층에서 강제
4. **중복·재발 방지**: (id, config) 신원 TTL lock (TG 패턴) + status 검사 + hypothesis_index 대조
5. **내구 기록**: 자동 개시·실패·스킵 사유 전부 JSONL (`auto_spawn_log.jsonl`) — "무인 stdout은 아무도 안 읽는다" (`paper_research_dispatch.R:703` 성문)
6. **capacity**: 동시 상한 + RAM 80% 규칙 + **전역 taskkill 금지** (RAMP_AutoLoop 사인 — 프로세스 종료는 자기 PID 트리만)
7. **kill switch**: `06_Registry/auto_spawn_config.json` `{enabled: false}` 단일 플래그 전 계층 정지
8. **감시 편입**: 신설 예약 태스크는 `Qvest_` 접두 의무 (noLayer4 감시 사각 재발 방지) + scheduler_task_health 시야 확인
9. **tier 라벨**: 모든 자동 산출물에 `tier: screen_diagnostic`·`metric_type: canonical_screen_diag` — 자본게이트 주장 원천 차단 (드레인 러너 기존 패턴 승계)
10. **Stage Gate artifact 작성 금지**: 자동 스폰 에이전트는 게이트 산출물을 쓰지 않음 (메인 직접 원칙 승계)

**위반 주입 테스트 계획 (도입 게이트)**: ①자격 미달 라벨 주입 → 스폰 0 확인 ②dohoon_decision 주입 → 차단 ③중복 (id,config) 주입 → 1회만 ④pin_tag 부재 산출물 주입 → 거부 ⑤kill switch on → 전 계층 무동작 ⑥measured 후보 재드레인 시도 → 스킵 ⑦verdict 코드가 07-10 실측 16건 재판정 시 세션 수기 판정(INFERIOR 16)과 일치 — 양성 대조.

---

## 5. 평가기 판별력 검증 루프 (라벨 남발 재발 방지)

FR_RCMA 폐지 사유("판별력 0")의 재발을 막으려면 enrichment 스코어 자체가 검증 대상이다: 분기마다 `improvement_potential.score` 상위/하위 후보의 실제 개선 성공률(드레인 SURVIVOR율·재설계 라운드 게이트 통과율)을 대조 — 판별력 부재 시 스코어 개정 또는 첨부 중단. 이 검증이 없으면 "우선순위 근거"가 다시 죽은 주소가 된다.

---

## 6. 결정 매트릭스 (D1)

| 수준 | 내용 | 기계화되는 칸 | 잔존 수동 | 리스크 |
|---|---|---|---|---|
| **L0** (현행) | 변경 없음 | — | 전부 | 라벨→소비 전환 누수 지속 (실측: 소비 1/17, 처분 0/50, 신규 라벨 큐 미반영) |
| **L1** (권고) | P0 수리 4건 + Layer 1 enrichment + Layer 2 큐·자격 + 개시는 (c)+(d) 세션 소비 | 평가·적재·판정·환류 | LLM 라운드 개시·판정 리뷰·자본 | enrichment 오작동 → 우선순위 오염 (§5 검증 루프로 완화) |
| **L2** | L1 + 크론 무인 드레인 배치 (Rscript 한정) | + 기계 실측 실행 | LLM 라운드 개시·자본 | 무인 실측의 침묵 실패 (가드 5·8로 완화) — LLM 무인 개시는 L2에도 불포함 |

구현 규모 추정 (파일 단위): P0 4건 = 기존 파일 수정 4곳 (hypothesis_index.R 원천 추가, drain.R verdict 블록, close_round.R 대조 경고, standalone_track_queue.R 처분 함수). Layer 1 = 신설 어댑터 1파일 (`improvement_potential.R`) + run_alpha_search.R 삽입 ~20행 + 큐 빌더 호출 2행. Layer 2 = 신설 큐 1스키마 + 자격 판정 함수 1파일. Layer 3 = 스킬 1종 + bootstrap 주입 ~10행 + (L2 시) 주간 스윕 확장. 위반 주입 테스트 7종.

---

## 7. next_probe · 부활 조건

- **next_probe ①**: D1~D3 결정 수신 시 P0 수리 4건부터 구현 라운드 착수 (위반 주입 7종 동반).
- **next_probe ②**: verdict 코드화의 양성 대조 — 07-10 드레인 16건을 신설 verdict 코드로 재판정, 세션 수기 판정과 전건 일치 확인 (불일치 시 판정 규약 자체를 재설계).
- **부활 조건**: 훅 직접 LLM 스폰·완전 무인 LLM 라운드는 본 설계에서 배제하나 영구 판결 아님 — headless 실행의 권한·판단 리스크가 해소되는 하네스 변경(예: 판정 없는 순수 탐색 라운드의 sandbox 분리) 시 재검토.
- **소비면**: 본 제안서 = 도훈 결정 재료 (D1~D3). 승인 시 구현 WT, 기각 시에도 P0 수리 4건은 독립 위생 수리로 분리 제안 (자동화와 무관하게 루프 단선은 실재).

## 부록: 근거 파일

`02_Infrastructure/hurdle_gate.R:1642-1686` · `02_Infrastructure/alpha_search/run_alpha_search.R:325-345,788-882` · `02_Infrastructure/regime/overlay_candidate_{queue,drain,ab_lh}.R` · `02_Infrastructure/portfolio/standalone_track_queue.R:60-67` · `02_Infrastructure/portfolio/regime_module_admission.R:89` · `04_Research/factor_rotation/run_wf_ensemble.R:22,108` · `02_Infrastructure/regime/build_module_performance.R:63-67,163-166` · `02_Infrastructure/contracts/{canonical_screen_bt,register_module,close_round}.R` · `02_Infrastructure/tools/hypothesis_index.R` · `02_Infrastructure/hooks/pipeline/stage_dispatch.py:153-224` · `02_Infrastructure/ops/weekly_cleaner_sweep.R` · `02_Infrastructure/data/pin_cache.R` · `06_Registry/{overlay_candidate_queue,standalone_track_queue,alpha_frontier_queue}.json` · 워크플로우 전체 산출: 세션 `w3t5m1r8j.output`
