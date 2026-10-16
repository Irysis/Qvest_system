# 1계층 루프 — 목표 역산형 리서치 프로그램 (Level 0 · v10.01 루프 정본)

**발효**: 2026-10-13 (도훈 지시 — 1계층 처방 재설계 D1~D16. 구 v10 루프(충실구현 → 고정 격자 강화)는 git 사료 · 롤백 태그 `pre-v10.01-prescription-20261013`).
**원칙**: 루프가 기본 상태다. 세션은 인프라가 아니라 라운드로 시작해 라운드로 끝난다.
**절차 정본**: `.claude/skills/research-program/SKILL.md` · 설계 = `04_Research/01_reports/l1_prescription_redesign_20261013/README.md`.
**철학**: 남들 다 깨질 때 덜 잃고(위기 하락 포착↓) 강세를 충분히 따라가(상승 포착 ≥0.55) 복리를 지킨다 — 비대칭이 필요조건(정적 노출 축소로는 안 된다).

## 입력 — 등록부가 정한다

- 부팅 `Programs:` 줄 = `06_Registry/research_programs.json`(writer `programs/program_registry.R`). 재검색·재정렬로 고르지 않는다.
- 순서: ① blocked 프로그램의 **선행 조건(측정 계약 MC1~MC8)** — 이것이 라운드를 여는 일이다(D7 제한적 예외 · 등록부 `pr_mc_set` 로 계상) ② ready/active 프로그램 라운드 ③ 재료 확보 = 큐 논문 충실구현(무인 레인 · 세션은 `/alpha-search`).
- ★`parked_reason = dohoon_decision` 항목은 세션 임의 착수 금지. 데이터가 없으면 `data_pipeline_queue.json` 적재 → 파이프라인(도훈 승인) → 재개.

## 축 — 등급은 같은 측정 축(epoch) 안에서만 비교한다

| 단계 | 축 |
|---|---|
| 충실구현 | **논문 그대로**(롱숏·종목수·비중·리밸). 등급 = 15bps 순비용 판(논문 기준 병기) |
| 처방·조립 | long-only(w≥0) · ≤25종 · 15bps(v2.4 delta) · 비중 상한 없음 · LIQ 2e8 |
| 측정 축(10-13 전환) | epoch `all_hyg_2000_v1` — 전 종목+위생(D11·MC1 · 계약 주입) · 2000-01-01~(D15·MC3 ✅ B안 — 실효 시작 = 신호 폭 ≥ 보유 × 2 첫 신호일 · A 관문 창 이탈 = 실효 시작 기준) · Σw≤1(MC5 ✅ · 현금은 오버레이 층) · 월간(주간 신호면 주간 — MC4 ✅ 하네스 · 셀 엔진 주간 신호는 미구현). 구 축 `k200kq150_2005_v1` 산출물과 등급 비교 금지 |
| 공통 | **PIT C1~C15 절대** · 정보 경계 τ_D = 2022-12-31(아래) |

## 라운드 (모든 프로그램 공통 — 세부 = SKILL §2)

1. **사전등록**(측정 전 · 파일) — 가설 · 기대 방향(행동 카드 지표) · 반증 조건 · 변형 수 상한 · 최종 후보 선택 규칙. `pr_record_round` 로 등록(결과 뒤 변경 = writer 거부). 설계안이 정해지면 **철학 Superfan P1**(투자철학 정렬 · 백그라운드 · 기다리지 않음 — 10-16 도훈 지시) 의견을 반영해 등록한다.
2. **측정** — 정본 계약만(`run_paper_replication` → essence). 손계산 금지(AX-008).
3. **행동 카드** — `contracts/matched_controls.R::mc_card(dir)`(행동 카드 `behavior_card.R` · 위기 = Lunde-Timmermann 20/20 첫 통과 구간 + MC8 크기·노출 짝 대조 · 귀속 = 선택/크기/노출 방어/방어 없음 · 판정은 무작위 짝 플라시보의 분위). 방어 주장 = 귀속 라벨과 함께(크기 방어 · 노출 방어를 '실력'으로 쓰지 않는다 · CR '강함' 등급 노치도 선택 방어 동반 시만).
4. **판정** — 사전등록한 반증 조건으로. 판정 직후 **철학 Superfan P2**가 방향 판정(향함 · 중립 · 역행)을 남기고 보고에 1줄로 실린다(규약 `00_Lawbook/specs/superfan_protocol.md` §11). 권위 등급(`authoritative_remeasure.json::essence_grade`)만 인용 — **등급 v3**(종합점수 S = Calmar 6 : PORT_t 4 가중 기하평균 + 하한 + 위기 복원력 노치 + τ_D OOS · 2026-10-13 MC7 승격). MDD 직접 문턱 없음(Calmar 와 CR 노치로만 닿는다).
5. **보고** — 리서치 1단위 = 1통 `prep_send`(`programs/program_report.R` · 발송 규칙 = qvest-telegram SKILL §0).
6. **교훈** — 기전이 특정되는 실패만 L-code · next_probes ≥2 · 교훈 카드엔 τ_D 이전 수치만.

Grade A → A 자격 관문(`run_paper_replication` §11 · `rf_a_eligibility`) — 통과 = 산출물 `judge_request.eligible.json`(Judge 트리거) · 보류 = `judge_request.held.json`(사유 코드 · 스폰 없이 도훈 보고) → Judge(PIT 전담) → PASS → BOOK 후보(도훈 confirm). 미달 = 그 프로그램의 다음 라운드(고정 격자 강화는 퇴역).

## 정보 경계 τ_D = 2022-12-31 (R4 · D6 — 절대)

분석가 · 처방 담당 · 팩터 정의자 · 리뷰어 · 최종 후보 선택 규칙 · 교훈 카드는 2022-12-31 까지의 성과·위기만 본다. 2023-01~ = 강건성 시험 구간 — 등급 · 철학 감독관 · Judge · BOOK(사람 쪽 판정)에만 쓴다. 2026-06~07 KOSPI200 급락은 실제 사건(재상정 금지).

## 예산

- 프로그램 라운드 = **목표 축** 예산(R7): 리뷰어가 K회 연속 "S·위기 방어 개선이 잡음 이내"로 판독하면 종료 · 논문당 총 상한 별도. 충실구현 1편 ≤40분 · ≤120K 토큰.
- 하네스 파일 쓰기(훅·테스트·계약·룰·부팅) = 0 — 예외는 등록부에 계상된 측정 계약(MC) 작업뿐. 하네스 결함은 그 라운드를 실제로 막을 때만 최소 수리.

## 하지 않는 것

고정 격자 강화 러너 부활 · 결과를 본 뒤 사전등록 수정 · τ_D 이후 성과를 처방 입력으로 쓰기 · Grade A 전 Judge 스폰 · BOOK 자동 등록 · 부팅 WARN 즉시 수리.
★면제되지 않는 것: PIT · 축 · `dohoon_decision` 임의 착수 금지 · 하드코딩 금지(수치는 등록부·논문에서 온다 · 처방 레인 근거 논문 의무는 해제 — `evidence` 기록).

## 보고 형식 (3줄 · 세션 응답)

```
① <대상> · Grade <A/B/C/F> · 위기 방어 <강함/보통/약함> · CAGR x% · Calmar x · 위기 하락 포착 x · 상승 포착 x  (출처: authoritative_remeasure.json · behavior_card.json)
② 기전 1줄 — 무엇이 켜졌고 무엇이 꺼졌나 (+ 논문 기준 성과 병기)
③ 다음 — <프로그램 다음 라운드 또는 MC 항목> · 큐 다음 재료 <id>
```

## 참조

`pit.md`(C1~C15) · research-program SKILL(절차) · `.claude/agents/judge.md`(PIT 검증) · `.claude/skills/alpha-search/SKILL.md`(충실구현) · `02_Infrastructure/book/book_registry.R`(BOOK) · `CLAUDE.md`(v10.01 헌법)
