# Qvest v8.3 — 알파 발굴 중심 아키텍처 재편 SOT

**발효**: 2026-07-10 (도훈 mandate — "실제 알파를 발굴하기 위한 목적으로 아키텍처 재편")
**전임 SOT**: `qvest_v8_1_sot.md` (v8.1 설계, retain) + `qvest_v8_0_upgrade_plan.md` (retain). 본 문서는 **발굴 퍼널 재배선**만 담당 — 4-Mode 헌법 · 6-agent · 게이트 권위 · Production Constraints는 불변.
**진단 근거**: 2026-07-10 5축 병렬 아키텍처 조사 (진입점/에이전트/게이트/지식엔진/산출흐름 — workflow wf_4b93f998, 원자료 세션 transcript). 마찰점 F1~F10, 재편 move M1~M11.

---

## 0. 한 문장 요약

> **인입은 마르고(논문 큐 고갈 + 무인 라인 침묵 정지), 선별은 벽 이전 지표(IC-first)에 갇혀 있고, 판정은 단일 cap-w 벤치라 아티팩트에 취약하며, screen-tier 회수와 지식 환류는 라벨에서 끊긴다. v8.3은 이 4개 절단면을 잇는다.**

---

## 1. 재편 원칙 5개

| # | 원칙 | 근거 실측 |
|---|---|---|
| P1 | **벽-정합 측정**: 후보 선별의 1급 지표 = canonical PORT_t (IC는 advisory). 실측을 alpha 단계로 전진 배치 | IC→PORT_t 전이 벽 — rank-IC 강해도 실현 net active 전이 안 됨, 16/16 admission FAIL. PORT_t 첫 의무 지점이 4번째 에이전트(forge)였음 |
| P2 | **dual-basis 진단**: cap-w HARD 판정은 불변이되, 기각 전 EW-유니버스 대비 + cap-tier(MEGA/MID) 분해 확인 의무 | post-2017 "감쇠"의 상당부분 = mega-cap cap-w 벤치 아티팩트(EW-대비 post2017_t 0.41→2.04 생존 실측). MID(11-30) t=3.02 生 / MEGA(top-10) t=0.59 死 |
| P3 | **프론티어 자원배분**: '다음에 뭘 시도할지'를 세션 기억이 아닌 상설 큐(`06_Registry/alpha_frontier_queue.json`)가 보유. EV순 + 소유 세션 표기 | 비-논문 가설(비-return/overlay/재분류)의 상설 큐 부재 → 병렬 세션 중복 실행 실사고 2건(07-05/07-06) + 저EV churn |
| P4 | **회수 우선**: 이미 실측 완료된 screen-tier 재고(overlay 큐 16건 등)와 revival 발화가 가장 싼 발굴 소스 — 라벨에서 끊긴 소비 배관을 잇는다 | OVERLAY_CANDIDATE 17건 중 1건만 소비 · FR 회수 4주 정지 · DPL_FEATURE 소비자 0 · revival 3건 발화했으나 세션 미도달 |
| P5 | **불변 경계**: Graduation HARD 3종(PORT_t 2.95·oos 0.7·calmar 0.64) · cap-w 게이트 권위 · 6-agent(슬림화 재제안 금지, 도훈 07-05) · Production Constraints(INV-7) · governor 수동 — 손대지 않는다 | 재편은 측정·소싱·환류 배선이지 기준 완화가 아님 |

---

## 2. 진단 — 마찰점 F1~F10 (요지)

| # | 마찰점 | 핵심 근거 |
|---|---|---|
| F1 | alpha 단계 selection_objective가 IC-계열만 허용 — 전이 안 되는 지표로 후보 선별 강제 | `02_Infrastructure/worktask/schema.json` selection_objective enum · `role_objective_guard.sh` · `prompts/alpha_research_init.md` Step 4 (canonical_screen_bt 0회) + stale 졸업기준(rank_ic 0.04/DSR 무조건 — measurement-graduation §3와 충돌) |
| F2 | 벤치 monoculture — cap-w KOSPI200 단일 basis, EW-대비·cap-tier 진단 전무 (인프라+프롬프트 grep 0) | `contracts/canonical_screen_bt.R` benchmark_id 하드코드 · essence oos도 cap-w 단일 |
| F3 | alpha-search의 PORT_t 실측 사다리가 proxy **총수익** 스크린에 gated — active alpha 실재 후보가 실측 못 받고 탈락 가능 | `alpha_search/run_alpha_search.R` remeasure 조건(B+ ∨ screen_pass) · `hurdle_gate.R` screen_pass = 총수익 SR/CAGR |
| F4 | 무인 인입 체인 침묵 정지 — 헤드리스 claude 월 지출한도(07-08~) + 실패 무경보 + 라우터 좌초(실패일 다운로드 17편 영구 미라우팅) | `.cache/scheduler_logs/paper_router_20260708.log` · `ops/paper_router_run.sh` |
| F5 | 비-논문 프론티어 상설 큐 부재 — 최고 EV 후보(비-return)가 세션 기억 의존 | 상설 큐는 논문 파이프뿐. 잔여 프론티어는 MEMORY.md에만 |
| F6 | in-flight 가설 미인덱싱 + lookup 훅 미강제 + 인덱스 stale — 병렬 중복 소각 3중 결손 | `tools/hypothesis_index.R` 원천 4계층 전부 완료 산출물 · hooks grep hypothesis_index=0 |
| F7 | 지식 주입면 stale — inject의 frontier axis가 settled-negative(DPL·regime-conditional·ML sizing)를 프론티어로 광고, strategic_truths에 07-05 이후 확립사실 부재 | `hooks/axiom_context_inject.sh` · `prompts/strategic_truths.md` |
| F8 | screen_route 하류 소비 단절 — overlay 큐 1/17 소비, FR_RCMA 무조건 첨부(판별력 0), DPL_FEATURE 죽은 주소 | `06_Registry/overlay_candidate_queue.json` · `hurdle_gate.R` screen_route 분기 |
| F9 | Distilled 파생 인덱스가 주간 재작성마다 frontier/live_trigger/revival_spec/expiry 소실 + revival 발화 last-mile 단절 | `axiom/cluster_extractor.py` vs `axiom/distilled.R` 스키마 드리프트 · `.cache/failure_revival_flags.json` 소비면 stdout뿐 |
| F10 | 조준 계기판 형해화 — gap vector 빈 껍데기(n_strategies=0, 실 book 미반영) · grade_a_catalog v53 proxy A 39건 착시(essence 권위 A 0건) · FR 레지스트리 회수 4주 정지 | `.cache/portfolio_gap_vector.json` · `04_Research/grade_a_catalog.json` |

Dead-end 배선 전체 목록·보존 대상 목록은 조사 원자료(workflow 산출) 참조. **보존/강화 확정**: 측정 프리미티브(canonical_screen_bt·essence 통계 규율·holdout_falsification), 게이트 이빨(discovery_graduation_gate fail-closed·overlay_pit_guard), 지식엔진 골격(lcode_emit v2·Distilled 카드·revival 레지스트리), register_module floor, DART insider backfill 라인.

---

## 3. 재편 이행 — move별 상태 (2026-07-10)

| Move | 내용 | 상태 | 파일 |
|---|---|---|---|
| M1 | alpha 단계 목적함수 PORT_t-정합 (enum+guard+프롬프트, stale 졸업기준 §3 정합화) | **구현 (본 세션)** | `worktask/schema.json` · `hooks/role_objective_guard.sh` · `prompts/alpha_research_init.md` |
| M2 | canonical_screen_bt에 diag_ew_universe + diag_cap_tier 비파괴 추가 + judge/alpha "기각 전 확인" 지시 | **구현 (본 세션)** — cap-w HARD 권위 불변, 진단 병기만 | `contracts/canonical_screen_bt.R` · `agents/judge.md` · `prompts/alpha_research_init.md` |
| M3 | alpha-search 실측 트리거를 proxy 총수익에서 분리(active-basis 경로 추가) | staged — M2 diag 실사용 관찰 후 | `alpha_search/run_alpha_search.R` · `hurdle_gate.R` |
| M4 | 인입 체인: 라우터 백로그 합류 + 침묵 정지 경보화 + reboot locale 수리 | **구현 (본 세션)**. 근본 원인(구독 월 한도)은 외생 변수 — 경보 배선으로 감지, 아키텍처 결정 대상 아님(2026-07-18) | `ops/paper_router_run.sh` · `ops/alpha_search_queue_run.sh` · MorningReboot |
| M5 | 상설 프론티어 큐 신설 + 소비 규약 | **레지스트리 구현 (본 세션)**: `06_Registry/alpha_frontier_queue.json`. 부팅 노출(research_pool_status 확장)은 staged | `06_Registry/alpha_frontier_queue.json` |
| M6 | hypothesis_index in-flight 원천 + stale 자동 재빌드 | **구현 (본 세션)** | `tools/hypothesis_index.R` |
| M7 | 주입면 갱신: inject frontier axis 현행화(settled-neg 3종 제거) + revival flags 주입 + strategic_truths 확립사실 3건 | **구현 (본 세션)** | `hooks/axiom_context_inject.sh` · `prompts/strategic_truths.md` |
| M8 | screen-tier 회수: DPL_FEATURE 발급 중단·FR_RCMA 조건부화(경량) / overlay 큐 generic 드레인 러너 | **경량부 구현 (본 세션)** / 드레인 러너 staged | `hurdle_gate.R` / (staged) `regime/overlay_candidate_*.R` |
| M9 | cluster_extractor 스키마 보존 + revival last-mile(주입 도달) | **구현 (본 세션)** | `axiom/cluster_extractor.py` · `hooks/axiom_context_inject.sh` |
| M10 | gap vector 실 book 연결 + grade_a_catalog v53 34건 격리 + FR 회수 재개 | staged — 생성 경로·소비자 11파일 선행 조사 필요 | `.cache/portfolio_gap_vector.json` · `04_Research/grade_a_catalog.json` |
| M11 | stale 문서/스텁 청소(qlead.md Scout 잔재 등) | staged (저우선) | 조사 원자료 3절 목록 |
| M12 | **적대검증 파생 (2026-07-10 신설)**: ① canonical_port_t 라벨 provenance 기계 검증(현재 프롬프트-레벨만 — validator/audit에 canonical 산출 아티팩트 존재·값 대조 배선) ② IS-only 선택 기계 배선(canonical_screen_bt date_cutoff 파라미터 + iteration 로그 audit — 선택통계=게이트통계 일치에 따른 다중검정 인플레 방지) ③ pre-existing: graduation gate의 DSR alpha-fallback을 forge-only로 축소 검토 ④ diag_ew_universe 유니버스 규격 검증(호출자 패널 패딩 방지) ⑤ 경보 heredoc 이스케이프 계층 | staged | `worktask_artifact_validator.sh` · `contracts/canonical_screen_bt.R` · `hooks/discovery_graduation_gate.sh` |

각 move의 실제 변경 내역·검증 결과는 본 세션 구현 보고(에이전트 4건) 기준 — 미landing 항목이 있으면 본 표를 갱신할 것 (표가 사실과 다르면 표를 고친다, 낙관 기재 금지).

---

## 4. Frontier Queue 규약 (`06_Registry/alpha_frontier_queue.json`)

**목적**: "다음에 뭘 시도할지"의 SOT. 세션 기억·임기응변 소싱을 대체.

**소비 규칙 (의무)**:
1. 새 발굴 리서치(WT/alpha-search/discovery) 착수 전: ① `hypothesis_index` lookup(기존 의무) → ② 본 큐에서 후보 확인, 착수 시 `owner`에 세션 표기 + `status=in_progress`.
2. 완료 시: `status` 갱신(`done_negative`/`done_positive`/`blocked`) + `result_ref`(L-code/보고서 경로) 기입.
3. 신규 프론티어 발견 시(연구 부산물 포함) 엔트리 추가 — EV 근거·벽 회피 논리(`wall_check`)·데이터 게이트 필수 기입.
4. 도훈 결정 필요 항목은 `status=dohoon_decision`으로 분리 — 세션이 임의 착수 금지.

**엔트리 스키마**: `id, lane(non_return|recovery|reclassify|overlay|pipeline|mandate), title, hypothesis, ev_rationale, wall_check(확립된 벽 중 무엇을 왜 피하는가), data_gate, owner, status, next_action, source_refs`.

---

## 5. 운영 제약 — 도훈 결정 대기 (정직 기록)

> D1(헤드리스 claude 월 지출한도)은 2026-07-18 삭제(도훈 지시) — 한도는 Anthropic 구독 외생 변수라 아키텍처 결정 대상 아님. 무인 실패 감지 경보 배선(paper_router/alpha_search_queue)은 유지. D2~D4 번호는 참조 안정성 위해 유지.

| # | 사안 | 내용 |
|---|---|---|
| D2 | **비-return 신규 데이터 취득** | 공매도/대차잔고(KRX 포털 스크레이핑) · DART 담보/질권·감사의견(document.xml 파서 확장) · QuantiWise crowding(로그인) — hypothesis_index 700 전수 기준 진짜 0-coverage lane. frontier 큐 FQ-003/004/005 |
| D3 | **mid-cap 국소 알파 활용 프레임** | 알파가 MID tier에 국소인데 게이트 basis는 cap-w — 벤치-상대(배포성) vs 절대수익(SR 2.5) 관점 정리 필요. 게이트 변경이 아니라 소비 경로(overlay/RAMP/벤치-상대 구성) 설계 논의 |
| D4 | grade_a_catalog v53 착시 34건 격리 (M10) | milestone_commit.sh 등 소비자 11파일 확인 후 실행 — 승인 시 다음 세션 |

---

## 5.5 적대검증 기록 (v8.2 Self-Adversarial 규약, 2026-07-10)

4렌즈 반박-프레임 병렬 검증(게이트 게이밍 / 계약 비파괴 / 파이프라인 회귀 / 헌법 정합) — **CRITICAL 0, 전 렌즈 MINOR_FINDINGS**.
- **불변 조건 전건 실측 확인**: HARD 3종·cap-w 권위(essence/graduation/governor diff 0) · INV-2(active axiom diff 0) · 역할경계(hook 5케이스: optimizer의 canonical_port_t 교차 사용 block) · M2 비파괴(기존 필드 bit-identical, 회귀 10/10).
- **same-turn 수리 완료**: judge.md DPL_FEATURE 잔재 → TURNOVER_REVIEW / CLAUDE.md 헤더·봉투-레버 목록 07-10 실측 동기 / measurement-graduation §3·§5·§6 3-표면 모순 해소(DPL·uncertainty settled 반영) / FQ-001·003·007 사실관계 정정(FQ-003: KRX 스크레이핑 사멸 실측 반영 — data.go.kr API 경로) / 텔레그램 사전 1:1 동기 2건(ICIR·TO) / hypothesis_index 원자적 쓰기+파싱 폴백 / inject revival settled-lane 필터 / canonical 주석 정직화+discovery 브릿지 diag off / router backlog_expiring 경보.
- **staged로 이월**: M12 (①~⑤ — 위 표).
- 재빌드 비용 정정: hypothesis_index stale 자동 재빌드 실측 2~4초(mailbox 191 WT 기준 3.8s).

## 6. 같은 mandate 동반 변경

- **텔레그램 v7 (비전공자 가독화, 전문용어 유지)**: `.claude/skills/qvest-telegram/SKILL.md` v7 + `telegram_notify.R` 동기화(`.METRIC_MEANING` 자동 용어풀이 footer + "쉬운 설명" 섹션 warn-level). dry_run 15/15 PASS.

## Change log
- 2026-07-10 v1.0: 신설 (도훈 mandate). 5축 조사 → F1~F10 진단 → M1~M11 재편, 본 세션 구현분 M1·M2·M4·M5(레지스트리)·M6·M7·M8(경량)·M9.
