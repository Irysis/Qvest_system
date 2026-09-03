# 1계층 루프 — 팩터전략 리서치 (Level 0 · v10 루프 정본)

**발효**: 2026-08-29 (도훈 지시 — 2계층 재편. 구 v9 lean loop 2026-08-23 은 git 사료 `pre-v10-2layer`).
**원칙**: 루프가 기본 상태다. 세션은 인프라가 아니라 라운드로 시작해 라운드로 끝난다.
**적용 범위**: 1계층(팩터전략 리서치) 전 라운드. 2계층 = `strategy-rotation` SKILL. BOOK = `/book`.
**페르소나**: `02_Infrastructure/docs/rules/quant-identity.md` — 최정상급 퀀트 · 냉소는 방법론을 향한다 · 리서치는 지난하다.

## 입력

- **큐 상단 1건** — `/qvest` 부팅 `Queue:` 줄의 최상단(미소비 논문 또는 frontier `open`). 재검색·재정렬로 고르지 않는다. 단 **강화 원장 L1 에 active entry 가 있으면 그 강화가 우선**이다(새 논문은 그 다음).
- ★`parked_reason = dohoon_decision` 항목은 세션 임의 착수 금지.
- 데이터가 없으면 "구현 불가"가 아니다 — `data_pipeline_queue.json` 적재 → 파이프라인 구축(도훈 승인) → 재개.

## 축 2층 (v10 — 고정 축이 단계별로 다르다)

| 단계 | 축 |
|---|---|
| **충실구현 라운드(최초)** | **논문 그대로** — 롱숏·종목수·비중방법·리밸 전부 복제. 유일한 변경 = 유니버스 K200∪KQ150(PIT 시변 멤버십). 유동성 필터 = 논문 우선(`paper_faithful`). 비용 = 논문 명시값 병기 + **등급은 15bps 순비용 판** |
| **강화 프로세스(그 이후)** | **실투형** — long-only(w≥0) · ≤25종 · K200∪KQ150 · 2005-01-01~ · 15bps(v2.4 delta) · Σw=1 · **비중 상한 없음(v10 폐지)** |
| 공통 | **PIT C1~C15 — 계층·단계 무관 절대** |

## 라운드 6단계 (충실구현)

1. **읽기** — 논문 1건에서 ①신호 정의 ②비중 방법 ③유니버스 ④리밸 주기 ⑤저자 주장 성과. 원문 링크 확보(필수 — 러너가 거부한다).
2. **구현** — engine 1파일 (`FACTORS(Date,Ticker,Score)` 또는 `PORTFOLIO(Date,Ticker,Weight,Leg)`). 논문 명시값 그대로, t-1 규약. 하드 게이트 = `detect_lookahead`.
3. **실행** — `run_paper_replication(name, idea, engine, portfolio_spec=<논문값>, source_paper=list(url=...))` (`02_Infrastructure/alpha_search/run_paper_replication.R`).
4. **판정** — **권위 등급**(`authoritative_remeasure.json::essence_grade`)만 인용(손계산·재구성 금지). Grade A = PORT_t ≥2.95 ∧ OOS retention ∧ SR ≥0.8 ∧ CAGR ≥16% ∧ Calmar ≥0.64. 계약 미경유 = 등급 미발행(NA — 실패가 아니라 미측정). ★MDD 는 등급을 접지 않는다(위험 축 = Calmar 하나). PIT 위반은 등급 무관 절대 기각.
5. **교훈** — 의미있는 실패(기전이 특정되는 실패)만 L-code 적립(mode=`paper_replication`).
6. **분기** —
   - **Grade A** → **Judge(PIT 전담) 스폰**(`judge_request.json` 발행됨) → PASS → BOOK 등록 후보(도훈 confirm) / FAIL → 결과 무효·수리·재측정.
   - **미달(B/C/F)** → **강화 프로세스**(`Skill(reinforce)` — 원장 `reinforce_ledger_l1.json` open 자동). 논문당 최대 25회(격자 5블록×5), 축 = 멀티팩터/비중방법론/유니버스/리스크오버레이/결합. 매 시도 = QEPM(alpha→risk→optimizer→forge→등급) + L-code. ★근거 논문은 **의무 아님**(도훈 2026-09-03 해제) — 있으면 기록하고 없으면 `evidence=none` 으로 남긴다. 25회 소진 → exhausted → 큐 다음 논문.
   - **논문 3편 소비마다** Q-Lead 가 논문 간 아이디어 결합 기회를 검토·기록(`rf_record_combination_review` — 착수 무관 의무).

## 예산 (라운드 1건)

| 축 | 상한 |
|---|---|
| 시간 | ≤40분 (충실구현) — 강화 시도는 QEPM 단위라 별도 |
| 토큰 | ≤120K |
| 하네스 파일 쓰기 | **0** (훅·테스트·계약·룰·부팅 스크립트) |

초과하면 라운드를 접고 상태 1줄. 하네스 결함은 그 라운드를 실제로 막을 때만 최소 수리.

## 연속성 계약

- L-code 발행 1지점: **next_probes ≥ 2**(B/C/F) + 부활 조건 `live_trigger`. 미충족 = WARN 후 발행(차단 아님).
- 턴 종료는 자유다. Stop 차단 훅 0.
- 강화 시도는 원장(`rf_append_attempt`)이 사전 등록을 강제한다 — 원장 밖 강화는 없다.

## 하지 않는 것 (1계층 라운드)

사전등록·검정력 계약·무신호 대조·β-통제 α·FF 회귀·`register_module`·`close_round()` 의무 —
전부 선택 도구이지 부과 의무가 아니다. 부팅 WARN 즉시 수리 금지 · Grade A 전 Judge 스폰 금지 ·
BOOK 자동 등록 금지.
★면제되지 않는 것: PIT · 축 2층 · `dohoon_decision` 임의 착수 금지 · 하드코딩 금지(수치는 격자·등록부에서 온다).
★2026-09-03 해제: **강화 레인 근거 논문 의무** — 원장이 더는 거부하지 않는다(충실구현은 불변).

## 보고 형식 (3줄)

```
① <전략명> · Grade <A/B/C/F> · CAGR x% · SR x · MDD x% · n_max <최대 보유종목수>  (출처: authoritative_remeasure.json — 권위 등급 · 15bps 판)
② 기전 1줄 — 무엇이 켜졌고 무엇이 꺼졌나 (+ 논문 기준 성과 병기)
③ 다음 — <next_probe 1건 또는 강화 n/25 축> · 큐 다음 항목 <id>
```

텔레그램 표제 = `[1계층] 알파 서칭 — …` / `[1계층·강화 n/25] …` (qvest-telegram SKILL 정본).

## 참조

`pit.md`(C1~C15) · `.claude/skills/reinforce/SKILL.md`(강화) · `.claude/agents/judge.md`(PIT 검증) ·
`.claude/skills/alpha-search/SKILL.md`(절차) · `02_Infrastructure/book/book_registry.R`(BOOK) · `CLAUDE.md`(v10 헌법)
