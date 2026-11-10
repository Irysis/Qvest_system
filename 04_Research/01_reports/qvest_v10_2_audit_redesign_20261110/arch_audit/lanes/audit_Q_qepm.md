# 감사 레인 Q — QEPM 프로세스 · 사용자 지시 리서치(/advisor) (2026-11-10)

범위: QEPM 요소가 살아 있는 경로 어디에 구현돼 있는지, P/L 우상향 목적 대비 격차, /advisor 흐름의 실재성, 동결 WT 체인의 재고와 비용.
방법: 코드 · 등록부 · 측정 기록 읽기, 훅 기동 시간 실측, 시험 실행 시간 실측, 건식 시나리오 시험 1건(신규). 실제 측정 · 에이전트 스폰 · 발송은 하지 않았다.

## 1. 배선 지도

```
/advisor (도훈만 · disable-model-invocation) ─┐
/qvest ④ ────────────────────────────────────┴→ Skill(qvest-advisor)
  ① input.md(원문 · 추출 6종 · hypothesis_index lookup · FQ · data_pipeline_queue 읽기)
  ② Agent 병렬: alpha-hypothesis · (alpha-research) · risk-research · optimizer-research
       └ 각 정의의 '★어드바이저 모드' 블록 → 04_Research/advisor/<날짜>_<slug>/<역할>.md
  ③ memo.md(13절) → 도훈 승인(채팅 또는 도훈이 친 --measure)
  ④ refresh_barrier.sh status=free → engine.R → measure_<k>.R → run_paper_replication(...)
       → essence_score(등급 v3.4 · 행동 카드 · MC8 · 팩터 알파) → authoritative_remeasure.json
       → [러너] module_catalog 등재(B 이상 · 방어형) · L-code · 텔레그램 '[1계층] 알파 서칭' 1통
       → A: rf_a_eligibility → judge_request.eligible.json / .held.json (Judge 스폰은 도훈 지시)
       → QVEST_NO_LEDGER_OPEN=1 이면 L1 소비 기록 없음
  ⑤ trials.jsonl(계보 N 원천)
```

## 2. QEPM 요소 × 살아 있는 경로

| 요소 | 1계층 라운드(P1~P3 · round_core) | 강화 사슬 도구 상자(reinforce_program.json · rf_cell_engine.R) | 2계층 | /advisor | 동결과 함께 사라진 것 |
|---|---|---|---|---|---|
| 알파 — 신호 | 충실구현 엔진 · P1 상설 자격 | B1 multifactor(rank-Z 결합 · 기저 w0 = 0.5) · B7 방어 슬리브(ic_bad as-of) | 모듈 풀(B+) 소비 | alpha-hypothesis/-research 자문(측정 없음) | alpha_package 의 IC·ICIR·harvey-t·portfolio-α t 를 한꺼번에 내는 표준 산출 |
| 알파 — 비용 인지 | 15bps 판 등급 · 논문 기준판 병기 | B6 집행 주기 · 회전 통제(rf_rebalance.R) | — | 15bps 판 인용 | 손실함수 안의 회전 벌점(Jensen-Kelly) — 측정된 살아 있는 구현 없음(미확인 아님: 블록 어휘에 없음) |
| 알파 — 불확실성 | P2R05 분포 표적(registered · 측정 전) | 없음 | 없음 | 없음 | μ̃ = μ̂ − k·SE 선택(07-05 robust FAIL 이후 미재시도) |
| 리스크 — Σ | 없음(라운드는 Σ 를 만들지 않음) | B2 비중 카탈로그의 ctx Σ = trailing **표본 공분산**(`portfolio/weight_catalog.R:637 stats::cov`) · 축소 변형 `gen:qepm_MVO__shr_*`(lw_nls 만 active) | 미확인 | risk-research 진단 자문 | **요인 구조 Σ = BΩB′ + D** · 국면 조건부 상관 · stress Σ — 살아 있는 경로 0 |
| 리스크 — 꼬리 | 행동 카드(LT 20/20 위기 · dd_capture · CDaR 진단) | B5 오버레이(dd_brake 등) · B2 `qepm:CVaR_LP` · `qepm:CDaR_LP` · `qepm:Protection_ES` | — | 행동 카드 인용(이번 정정) | EVT 꼬리 · 꼬리 의존(공동 급락) 진단을 구성 입력으로 쓰는 경로 |
| 리스크 — 혼잡 · 집중 | 헌장 §4 '집중'(깊은 위기 한 종목 기여) 판정 · 유효 종목 수 기록 | 없음 | — | risk-research 자문 | crowding_score_per_factor(훅 미등록 · 산출자 0) · sector HHI |
| 구성 — 목적함수 · 제약 | P3R01~R03(HRP · NCO · MRE · CVaR 등) | B2 카탈로그 58종(qepm_registry 14 · lean 23 · 논문 어댑터 12 · 생성 9) · 고정 축 강제 = rf_axes.R(MC5 Σw≤1) | 배분 규칙 | optimizer 자문 · portfolio_spec 초안 | α̂ − λ/2·x′Σx − φ·TC 를 **요인 Σ 와 비용으로** 푸는 통합 최적화(카탈로그 MVO 는 표본 Σ · 비용 항 없음 — 미확인: 카탈로그 각 방법의 TC 항 유무 전수 대조는 안 함) |
| 구성 — 회전 통제 | — | B6(interval · band · cap · rank_buffer) | — | — | schedule density 의무(forge) |
| 귀속 | 행동 카드 MC8(선택/크기/노출 방어) · 등급 v3.3 팩터 알파(FF3·C4·FF5·FF6 NW-t) | 같은 계약 | FR 등급 | auth 인용 | Brinson factor/selection/**cost/residual** 4축 분해(attribution_quarterly_trigger 미등록 · 산출자 0) |
| 피드백 | round.sh close → round_outcomes.jsonl(★파일 아직 없음 — v10.2 11-10 신설 · 닫힌 라운드 0) · L-code · hypothesis_index | 사슬 걸음 채택/기각 · selection_regrade | 원장 L2 | L-code(러너) · trials.jsonl | 귀속 결과가 다음 설계 입력이 되는 기계 경로(설계는 사람 · LLM 이 교훈을 읽는다) |

판독: QEPM 의 **역할 분리 · 자문**은 /advisor 로, **옵티마이저 방법론**은 비중 카탈로그(B2 · P3)로 살아 있다. 사라진 것은 (a) 요인 구조 리스크 모형 (b) 리스크 모형을 입력으로 쓰는 구성 (c) 비용 · 잔차 귀속의 표준 산출, 세 가지다.

## 3. P/L 우상향 목적 대비 격차 (이 시스템의 기록으로 확인되는 것만)

1. **방어가 전부 노출(β) 방어로 귀속된다** — P2R03 시변 노출 층 7종 β 짝 깊은 위기 과반 0/14 · P2R04 방어적 보유 0/8 · P3R03 구성 10칸 = 노출 방어(β 짝 10/10 미통과 · 빠른 급락 0/20) · "구성 레버 포화 → P3 구성 라운드 중단"(`research_programs.json` 판정 원문). 헌장 §4 '현금 기계' 형태. 구성 층의 Σ 가 trailing 표본 공분산뿐이라 구성 처방이 할 수 있는 일이 사실상 '변동성 · β 낮은 쪽으로 기울기'다(추정 — 기전 가설이며 측정으로 분리하지 않았다). 위기 조건부 공분산 · 하방 β · 꼬리 의존을 구성 입력으로 넣는 칸은 블록 어휘 · 카탈로그 어디에도 없다.
2. **낙폭 경로(CDaR · 회복)는 진단만 되고 처방 표적이 아니다** — 행동 카드가 CDaR 을 낸다(`behavior_card.R:19` · auth `grade_v3.cr.cdar`). 처방 쪽 CDaR 목적함수 `qepm:CDaR_LP` 는 09-06/07 두 차례 시간 초과로 미측정이었고(run_all_hooks.sh 1194행 주석 · 솔버 수리 09-07) 이후 측정 기록은 hypothesis_index lookup cdar 3건(REGISTERED 1 · 판정 기록 없음). 헌장 §4 '지표 게이밍'(수중 기간)을 막을 처방 칸이 비어 있다.
3. **귀속이 비용 · 잔차를 나누지 않는다** — 살아 있는 귀속은 MC8(선택/크기/노출)과 팩터 알파뿐. 15bps 판과 논문 기준판 차이가 '비용'으로 병기되지만 회전 · 슬리피지 · 잔차 분해는 없다. 처방 루프가 '알파는 있는데 비용에 먹혔다'와 '알파가 없다'를 구분할 수 없다.
4. **피드백 원장이 비어 있다** — round_outcomes.jsonl 은 11-10 에 생긴 계약이고 아직 한 줄도 없다(파일 부재). 귀속 → 다음 설계의 기계 경로는 이 원장부터 시작이다.

## 4. /advisor 흐름 — 끝까지 도는가

정적 대조 결과(신규 시험 `08_Tests/scenarios/test_scn_advisor_dryrun.R` 37/37):
- 참조 경로 29건 실재(퇴역 `grade_a_queue.json` 은 금지 목록에만 — 예외 처리) · 스폰 대상 4종 정의 · 산출 파일명 일치 · 측정 블록 인자 ⊆ 러너 형식 인자 · 환경변수 러너 판독.
- 장난감 계보 보행: 첫 판 chain/1 → 둘째 판 sweep/2 → 충실구현 A 관문 회계 요건 = chain → **둘째 판부터 A → Judge 경로가 구조적으로 닫힌다**(등급 v3.4 선택 현실 점검 제출 단계가 절차에 없음 → 경과 규정 DSR).

고친 낡은 사실(스킬 · 에이전트 · 스타일 — 사실 정정만):
| 파일 | 낡은 것 | 정정 |
|---|---|---|
| qvest-advisor/SKILL.md §③10 | 'Grade A PORT_t 문턱' 하나 | v3: A 하한 2.0(floors.port_t) + 정규화 · 노치 2.95 병기 |
| SKILL §③13 · §④ 블록 주석 · 금지 절 · 운영 쓰기 | '강화 원장 auto-open' · '강화 이관' | L1 소비 기록(개설 즉시 parked) · 이관처 = pr_enqueue |
| SKILL §④ 운영 쓰기 ③(신설) | (없음) | 억제의 대가: 레인 선택기 `rf_next_paper_pick.py::_consumed` 가 소비로 못 봄 → 중복 측정 위험 |
| SKILL §④ 시행 회계(신설 1줄) | (없음) | v3.4 스윕 = 선택 현실 점검 · 절차에 제출 단계 없음 → sweep 판 A 경로 구조 보류 |
| SKILL §④ 보고 | ① 등급·CAGR·SR·MDD·n_max | lean-loop ① (위기 방어 · 하락 포착 · 상승 포착 · 귀속 — auth grade_v3.cr · mc8) |
| SKILL §④ 분기 A | '통과분의 후보별 요청'(퇴역 경로) | judge_request.eligible.json |
| alpha-research.md | 기본 유니버스 KR_top342(K200∪KQ150) · mandate 훅 | (사료) 표기 + 현행 epoch all_hyg_px1000_2000_v1 |
| optimizer-research.md | WeightCatalogGrow 주간 · '강화 격자 arm' | 예약 작업 Disabled(실측) · B2 블록 · P3 소비 · Σ = 표본 공분산 |
| qvest-attribution-style | graduation HARD 3종 · DSR sweep HARD · 분기 자동 귀속 | 등급 v3.4 요약 · 훅 미등록 · 살아 있는 귀속 3종 |
| qvest-alpha/risk/opt-style | '훅 차단 · 훅 강제' | 미등록 · 동결 경로 한정 · 강제 = R 계약 |

못 고친 것(소유 밖 · 패치 제안):
- P1 `02_Infrastructure/alpha_search/run_paper_replication.R:936` — 어드바이저 측정도 표제가 `[1계층] 알파 서칭 — 충실구현` 으로 나간다. `measurement_tags$lane == "advisor"` 면 표제를 `[어드바이저]`(또는 qvest-telegram §0 이 정하는 표제)로. 현재 텔레그램 독자는 /advisor 측정을 레인 충실구현으로 오인한다.
- P2 `06_Registry/reinforce_program.json::fixed_axes` — `universe = "K200_KQ150"` · `start_date = "2005-01-01"`(구 축). rf_cell_engine.R:37·64 는 **셀 스펙**의 fixed_axes 를 읽고, 확인한 라운드 사양(P0R01 · P2R05)은 자기 fixed_axes + `universe = all_hyg` 를 직접 쓴다 — 등록부 값이 셀 스펙에 복사되는 경로(P4 사슬 등)가 있는지는 미확인. 있으면 구 시작일 2005 가 실린다. 강화 사슬 레인과 교차 확인 · writer 경유 재등록 대상.
- P3 동결 검사 2건 · 어드바이저 계약 1건이 지금 red — 원인 = 다른 세션의 `02_Infrastructure/ops/rf_l2_auto.R` 수정 중(l2_judge_request.json 발행 줄 변경). 내 편집과 무관(편집 전 140/140 · 74/74 → 그 파일 수정 뒤 139/140 · 72/74). 그 세션이 문서(reinforce SKILL §2-8) 와 시험을 함께 맞춰야 한다.

## 5. 동결 WT 체인 — 재고와 비용

재고: `dead_Q_qepm.tsv` 56행(certain 40 · probable 16 · decide 49 · keep 7). ★폴더 이름만 worktask 인 살아 있는 것: `worktask/constraint_defaults.json`(등급 숫자 정본) · `windowing.R` + `lockbox_paths.R`(Judge 의 judge_oos_helper.R 가 source) · `test_qepm_advisor_contract.R` · `qepm/R/orchestration/state_machine.R`(telegram_listener.py 가 source). (가)안을 고르면 이것들을 먼저 옮겨야 한다.

비용 실측:
| 항목 | 실측 |
|---|---|
| 등록 훅(Write 마다) | discovery_graduation_gate 168ms · worktask_constraint_enforcer 161ms(빠른 길) — 빈 bash 기동 152ms 이므로 순수 판정 비용은 ~10ms, 대부분 프로세스 기동. 같은 이벤트 훅은 병렬이라 벽시계 기여는 작지만 Write 1회당 bash 2개를 더 띄운다. 해당 경로 쓰기 땐 621ms · 1031ms |
| 야간 시험(동결 체인 전용) | sequence_gate 3s · constraint_enforcer_v10 16s · agent_role_guard 10s · ast_spec_gate 33s · wt_lifecycle_e2e 29s · wt_inflight_lock 3s · freeze 2종 6s = **약 100s**(backtest_contract_audit 21s 는 살아 있는 기억 레인 보호라 제외) |
| 세션 문맥 | 동결 스킬 · 명령 · 워크플로 · forge 설명 ≈ 1.3K자(worktask 220 · 명령 72 · forge 209 · dossier 약 520 · multi-track 약 280) — 프로젝트 전체 설명 10.6K자의 약 12% |
| 디스크 · 동기화 | qepm/ 1.1GB(추적 파일 7,728) — mailbox/worktask 210MB · research 789MB(OneDrive 동기화 부하) |
| 부팅 | 동결 체인이 부팅 8줄에 기여하는 줄 미확인(boot 스크립트는 이 레인 밖) |

## 6. 처분 선택지 (결정 = 도훈)

| 안 | 내용 | 근거 | 비용 · 위험 |
|---|---|---|---|
| (가) 완전 삭제 | WT 스킬 · 명령 · 워크플로 · forge · 스텁 3 · 전용 훅 2(등록) + 미등록 15 · worktask/ 비활성 모듈 · 시험 7 삭제. QEPM = /advisor + 3엔진 프로그램 | 동결 47일 · 재상정 0 · 살아 있는 소비자 0(위 keep 7 제외) | qepm/mailbox 는 hypothesis_index 원천(wt_inflight) — 지우면 과거 negative 색인 일부 소실 → mailbox 는 99_Archive 이동 · 색인 원천 경로 갱신 필요. 동결 봉쇄 시험이 사라지면 봉쇄 회귀 감시도 사라짐(대상이 없으니 불필요) |
| (나) 동결 유지 · 배선 분리 | 등록 훅 2개 settings 에서 해제 · 동결 전용 시험 6개 SUITES 제외 · 스킬/워크플로/forge 를 목록에서 숨김(skillOverrides) · 파일은 보존 | 되살릴 여지 보존 + 비용 대부분 회수(Write 당 bash 2 · 야간 ~100s · 문맥 1.3K자) | 봉쇄 검사(freeze 2종)는 남겨야 진입로 재개방을 잡는다 · 파일 드리프트(사료가 낡아 감) |
| (다) v10.2 형태로 재편 | 리스크 · 옵티마이저 규율을 P3 구성 엔진 / 강화 사슬의 블록으로: ① 요인 구조 Σ(KR FF 요인 `build_kr_factor_returns.R` 위 BΩB′+D) 를 비중 카탈로그 ctx 의 Σ 공급자로 ② 위기 조건부 Σ · 하방 β 를 구성 입력으로(β 짝 대조를 넘는 '선택 방어'를 노리는 칸) ③ CDaR_LP 를 사슬 한 걸음으로 실제 측정 ④ 비용 · 잔차 귀속을 행동 카드 옆 표준 산출로 | §3 격차 1~3 이 정확히 사라진 QEPM 요소 자리 · P3R03 '구성 레버 포화'는 표본 Σ 위에서의 포화 | 사전등록 · 시행 예산(trial_budget.R) · 선택 현실 점검 대상 칸이 늘어난다 · 새 Σ 공급자는 PIT(as-of 요인 수익 · C11) 검증 필요 |

**권고 = (나) + (다)의 ①③ 을 먼저**: WT 체인은 배선만 끊어 비용을 회수하고(삭제는 mailbox 색인 원천 이전 뒤 (가)로), QEPM 의 살아 있어야 할 부분은 체인이 아니라 블록으로 되살린다. 근거 — 이 시스템이 오늘 P/L 우상향에서 막히는 지점(방어 = β 노출뿐 · 낙폭 경로 무처방)은 WT 체인 부재가 아니라 리스크 모형 · 낙폭 목적함수 부재이고, 그것은 기존 사슬 · 카탈로그 배선(ctx Σ 공급자 · B2 칸)에 꽂힌다.

## 7. 에이전트 5종 · 스타일 4종 — 현행 헌장 · PIT · 축 · 등급과 어긋나는 곳(정정하지 않은 것 = 제안)

- 어드바이저 모드 블록 4종 어디에도 **행동 카드 기대 방향 사전 선언**(lean-loop 라운드 1단계 '기대 방향(행동 카드 지표) · 반증 조건')이 없다. 메모 §4 반증 조건에 '위기 하락 포착 · 상승 포착 · MC8 귀속의 기대 방향'을 넣는 것은 규칙 추가라 제안으로 둔다.
- 메모 13절에 τ_D(2022-12-31) 언급이 없다 — 어드바이저 메모 · 자문 에이전트는 '처방 담당'인가? lean-loop 정보 경계 대상 목록에 어드바이저가 없다. 자문이 설계를 고르면 처방과 같으므로 τ_D 적용을 명시하자는 제안(결정 = 도훈).
- risk-research 진단 범위에 β 짝(같은 β 현금 사본) · MC8 크기/노출 짝이 없다 — 이 시스템이 방어 주장을 기각하는 주 판정인데 자문 단계에서 예고하지 않는다(제안).
- 5종 모두 'Research Philosophy 7 Principles'(05-14)를 의무로 싣지만 투자철학 헌장(10-13 · 비대칭 · 위기 방어)은 싣지 않는다(제안: 헌장 링크 1줄).
- optimizer-research 목적함수 `1′x = 0`(활성) vs 고정 축 롱온리 Σw ≤ 1 잔여 현금(MC5) — 어드바이저 모드 허용 절은 '실투형 = Σw=1' 이라 적는다. MC5 이후 Σw ≤ 1 이 정본(CLAUDE.md 축 표) — 사실 정정 후보지만 contract 시험이 그 문구를 읽는지 확인 못 해 남겼다(미확인).
- alpha-research 'model: opus = 현행 Opus 5' · 'Opus 4.8 native' 주석 — 세션 모델 정본은 CLAUDE.md(opus-5-5). 판정 무관 · 미정정.
- forge.md Work Dir `C:/Users/99922/...` — 현 메인 경로는 G:/OneDrive(메모리 카드 11-07). 동결 파일이라 미정정.
