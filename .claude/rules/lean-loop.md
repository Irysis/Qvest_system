# Lean Loop (Level 0 — v9 루프 정본)

**발효**: 2026-08-23 (도훈 결정 — 요청 "검증에 매몰된 하네스를 걷어내고 초기 Qvest의 신속성·창의성 회복" → 전수 점검 플랜 `~/.claude/plans/qvest-encapsulated-wave.md` 승인 + 결정 4항 선택. 롤백 태그 `pre-v9-lean-loop`).
**원칙**: 루프가 **기본 상태**다. 세션은 인프라가 아니라 라운드로 시작해 라운드로 끝난다.
**적용 범위**: alpha-search 레인의 모든 lean 라운드. 자본 층(지명 후 `/worktask` 이하)은 `measurement-graduation.md`가 규율한다.

## 입력

- **큐 상단 1건** — `/qvest` 부팅 `Queue:` 줄의 최상단 항목(미소비 논문 또는 frontier `open`). 재검색·재정렬으로 고르지 않는다.
- **고정 축**(논문이 명시하지 않은 것만 여기서 채운다): long-only(w ≥ 0) · ≤25종 · K200∪KQ150 · 2005-01-01~ · 15bps(v2.4 delta) · weight ∈ [0, 0.20] · Σw = 1 · PIT C1~C15.
- **논문 명시값 우선**: 종목수·비중방법·리밸 주기·유니버스 필터를 논문이 적었으면 **그대로 복제**한다. 고정 축과 충돌할 때만 고정 축이 이기고, 그 사실을 L-code에 적는다.
- ★`parked_reason = dohoon_decision` 항목은 **세션 임의 착수 금지**. 큐에서 건너뛰고 다음 항목으로 간다.

## 6단계

1. **읽기** — 논문/가설 1건에서 ①신호 정의 ②비중 방법 ③유니버스 ④리밸 주기 ⑤저자 주장 성과를 뽑는다. 요약 문서를 따로 만들지 않는다.
2. **구현** — factor engine 1파일. 신호는 논문 사양 그대로, 시점은 t-1 규약. 이 단계의 하드 게이트는 `detect_lookahead` 하나다.
3. **실행** — `run_alpha_search(name, idea, engine, n_holdings=<논문값>, weight_method="<논문값>")`. **`deep=FALSE`가 기본**(측정·판정·교훈만 돈다). `deep=TRUE`는 **지명된 후보 1건에만**.
4. **판정** — `hurdle_result.json`의 값만 인용한다(손계산·재구성 금지). **Grade A = CAGR ≥ 16% ∧ SR ≥ 0.8 ∧ score ≥ 40 ∧ hard_fail 없음.** B/C/F는 그 파일의 판정을 그대로 쓴다. PIT 위반은 등급 무관 절대 기각.
5. **교훈** — **의미있는 실패만** L-code로 적립한다. 의미있는 실패 = 기전이 특정되는 실패(어느 축이 왜 꺼졌는지). "점수가 낮았다"는 적립 대상이 아니다.
6. **다음** — 큐 다음 항목으로. 한 세션에 논문 여러 편을 도는 것이 정상이다.

## 예산 (라운드 1건)

| 축 | 상한 |
|---|---|
| 시간 | ≤40분 |
| 토큰 | ≤120K |
| 하네스 파일 쓰기 | **0** (훅·테스트·계약·룰·부팅 스크립트) |

초과하면 라운드를 접고 상태를 1줄로 남긴다. 하네스 결함은 **그 라운드를 실제로 막을 때만** 최소 수리하고, 그 외에는 태스크로 분리한다.

## 연속성 계약 — 적용 지점은 L-code 발행 1곳

- 계약은 `run_alpha_search.R::.write_lcode`(스키마 `02_Infrastructure/axiom/lcode_schema.R` v3)에서만 검사된다: **next_probes ≥ 2**(B/C/F) + **부활 조건 `live_trigger`**. 미충족은 `[L-CODE WARN]` 후 발행(차단 아님).
- **턴 종료는 자유다** — "여기까지 하고 대기 중"으로 끝내도 위반이 아니다. Stop 차단 훅 0(`02_Infrastructure/docs/rules/continuity-firewall.md` = SUSPENDED).
- `close_round()`는 **선택**이다. 호출하지 않아도 라운드는 완결된다.
- `02_Infrastructure/docs/rules/answer-principles.md`의 리서치 연속성 6항 중 **3호(next_probe ≥ 2)만** lean 라운드에 적용되고, 그 검사 지점이 위의 L-code 발행이다.

## 지명 → 자본 계층

Grade A 또는 도훈 지명이 나왔을 때만 층을 올린다:

`/worktask` → 6-agent(alpha-hypothesis → alpha → risk → optimizer → forge → judge) → dossier → **forge-authoritative 수치**로 HARD 3종 판정 → governor.

- HARD 3종 값 정본 = `02_Infrastructure/worktask/constraint_defaults.json::tier_graduation`. **재보정은 도훈 권한**.
- `qepm/mailbox/governor/book_state.json` 쓰기 = **도훈만**. 자동화 금지.
- 지명 전에는 QEPM 에이전트를 스폰하지 않는다.

## 하지 않는 것 (lean 라운드)

아래는 착수 관문·판정 의무로 **부과되지 않는다**. 필요하면 쓰는 선택 도구일 뿐이다.

- `hypothesis_index` 중복 차단 · 3단 착수 게이트 · `research_ev_map` 죽은 계급 조회
- 사전등록 · 검정력 계약(`required_effect_size`·`cluster_power`) · 착수 크기산술 관문
- 무신호 대조 · β-통제 α 병기 · `DISTRIBUTION_TARGET` 요건 3종
- FF3/FF5/Fama-MacBeth 회귀(= `deep=TRUE`에서만) · 권위 재측정 · `register_module`
- `close_round()` 의무 호출 · L4 `claude -p` 검증자 · 세션의 `auto_alpha_gate` 실행
- 텔레그램 5섹션 양식(러너 1회 발송으로 족하다) · 부팅 WARN 즉시 수리 · 지명 전 QEPM 스폰

★면제되지 않는 것: PIT · 고정 축 · `dohoon_decision` 항목 임의 착수 금지 · `book_state` 수동.

## 보고 형식 (3줄)

```
① <전략명> · Grade <A/B/C/F> · CAGR x% · SR x · MDD x%  (출처: hurdle_result.json)
② 기전 1줄 — 무엇이 켜졌고 무엇이 꺼졌나
③ 다음 — <next_probe 1건> · 큐 다음 항목 <id>
```

서사·표·재측정 블록은 붙이지 않는다. 상세는 L-code와 산출물 경로가 갖고 있다.

## 참조

`pit.md`(C1~C15) · `measurement-graduation.md`(자본 층) · `02_Infrastructure/docs/rules/answer-principles.md`(3호) · `.claude/skills/alpha-search/SKILL.md`(절차) · `CLAUDE.md`(고정 축·게이트 2층)
