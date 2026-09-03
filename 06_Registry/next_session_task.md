# 다음 세션 인계 — 2026-09-03 (오버레이 중첩 배선 완료 · 무인 루프 정지)

## 지금 상태 한 줄

**무인 리서치 루프는 도훈 지시로 정지돼 있다** — 예약작업 `Qvest_ReinforceAutoLoop` = **Disabled**,
`06_Registry/reinforce_auto_config.json::enabled = false`. 재개는 **둘 다** 되돌려야 한다.

## 이번 세션에 바뀐 것 — 오버레이 중첩 (v10.2)

도훈 질문에서 출발했다: "B등급 전략 위에 새 팩터가 추가되고 오버레이가 중첩되는 형태인가?"
실측 답은 **절반만 그랬다** — 팩터는 `.dedup_factors` 로 누적되는데 **오버레이는 승계 자체가 없었다.**
`reinforce_auto_parallel.R` 의 carry 병합 블록에 `weighting`·`universe` 줄은 있고 `overlay` 줄이 없었다.
그래서 승격된 자식은 부모의 위험 통제를 벗은 채 B1/B2/B3 를 돌았고, 자식 B5 는 부모 오버레이를
**덮어쓰고** 처음부터 다시 깎았다. 세대를 넘겨도 오버레이는 항상 1층이었다.

배선 3곳:
1. **엔진** `rf_cell_engine.R` — `SPEC$overlay` 가 단수 객체뿐 아니라 **층 리스트**를 받는다.
   층마다 노출을 계산해 **곱으로 합성**(`.ov_compose`, 스칼라×벡터 혼합 가능 · 결측 티커는 1).
   `n_min` 은 층들의 최댓값. 고정 축(Σw≤1·롱온리)은 합성 뒤에도 불변.
2. **승계** 두 러너(`reinforce_auto_parallel.R`·`reinforce_auto_run.R`) —
   carry 의 오버레이가 B1/B2/B3 로 전달되고, B5 는 `.ov_stack(carry, cell)` 로 **얹는다**.
   B4 는 B5 승자 스펙(이미 중첩판)을 그대로 쓰고, B5 를 뺀 칸도 부모 오버레이는 기저로 남긴다
   (안 그러면 "B5 제외" 가 두 겹 처치가 되어 LOO 대조가 깨진다).
3. **제외 목록** — `.done_arms` 가 `s$overlay$arm_id` 로 뽑고 있었다. 중첩판은 리스트라 NULL 이 나와
   제외가 통째로 비었을 것이다. `.ov_arm_ids` 로 층 전부를 뽑고, **carry 에 이미 깔린 팔도 제외**한다
   (같은 팔을 또 뽑으면 `.ov_stack` 중복 제거로 그 칸이 무처치가 되어 측정 0으로 탄다).

**정본 헬퍼**: `02_Infrastructure/reinforcement/rf_spec_sig.R` —
`.ov_layers` / `.ov_stack` / `.ov_arm_ids`. 두 러너가 공유한다.
★`.ov_stack` 은 **단층이면 구판 단수 형태를 그대로** 돌려준다 — 시그니처(`toJSON`)가 바뀌면
기존 263 측정이 전부 미측정으로 되살아나 격자가 같은 칸을 다시 태운다. 검사 B1 이 이걸 지킨다.

**실측(스모크)**: 같은 기저·같은 위기에서 단독 평균노출 0.836(dd_brake) / 0.887(dbeta_tilt) →
**중첩 0.806**, 날짜 안 비중 sd 0.0044(횡단면 비대칭 보존), Σw 최대 1.000000.

## 같이 고친 것 — 텔레그램 순위 줄 붕괴 (도훈 3연속 적발)

서술기 `.delta_of` 가 `carry 대비 바뀐 축`을 적었다. 세 번 다 여러 위가 **글자까지** 같아졌다:

| 회차 | 블록 | 기전 |
|---|---|---|
| 8-31 | B5 | 서술이 3축뿐 — **오버레이가 아예 없었다** |
| 9-03 ① | B4 | 결합 칸의 처치는 축 값이 아니라 **부분집합**. LOO 로 뺀 축이 carry 와 같으면 차집합이 빈다 |
| 9-03 ② | B1 | 칸들이 팩터를 **누적**해 공통 접두가 길다. 원문은 nchar 62/94/142/194/238 로 다 다른데 **앞에서 48자를 자르니** 구분자가 통째로 날아갔다 |

공통 기전 하나 — **그 비교군을 가르는 값이 서술에 안 남았다.**

**수리 = 기준을 고정 참조에서 비교군으로 옮긴 것**
- 기준 = `carry 팩터 ∪ 그 블록 전 칸이 공유하는 팩터`. carry 가 없으면 비중·유니버스도
  **블록 안에서 갈릴 때만** 적는다.
- 누적형은 개수를 앞세운다 — `1종 · D60_Leverage` / `3종 · 막 Q35_CashBased_OpProf`.
  잘려도 맨 앞이라 살아남는다.
- 결합 칸은 부분집합 — `비중 제외(LOO) · 팩터+유니버스+오버레이` (`.rf_combo`).
- 라벨이 id 와 같으면 id 만 — `D16_Coskewness (D16_Coskewness)` 는 30자에 정보 0인데
  48자 예산에서 구분자를 밀어낸다.

**★진짜 교훈은 검사 쪽이다.** 세 번 다 **그때 검사가 안 보던 블록**에서 났다.
`rf_auto_notify` 는 entry 의 마지막 블록만 렌더하므로, 1차 수리 후 검사는 고쳐진 B4 만
초록으로 확인하고 B1 붕괴를 놓쳤다. → `QVEST_RF_FORCE_BLOCK` 이음매 신설(평시 무영향),
`test_rf_notify_rank_distinct.R` 이 25칸 완주 entry 의 **다섯 블록 전부**를 렌더해
순위 줄이 서로 다른지 잰다(+ 중복 주입 양성 대조). 최근 entry 6건도 함께 훑는다.

## 낡은 검사 3종 수리

- `test_rf_carry_treatment` — RHS 리터럴(`SPEC$overlay <- CELL$overlay`)을 박고 있었다.
  지키려는 불변(무처치 판정이 overlay 대입 뒤)은 멀쩡한데 중첩 도입으로 검사만 빨개졌다.
- `test_rf_send_verdict` — "5칸 있다"로 골라 **미측정** entry 를 집었다. 거기서 FALSE 는
  결함이 아니라 정답이다(보고할 것이 없어 `rf_notify_table` 이 NULL). "측정된 5칸"으로 바꿨다.
- `test_rf_block_lcode` — **폐지된 규칙**(강화 레인 근거 논문 의무, 2026-09-03 해제)을
  강제하고 있었다. 오래 skip 상태라 규칙이 없어진 뒤에도 아무도 못 봤다.
  대신 `research_mode=reinforcement`(레인 식별)를 잰다. ★충실구현·2계층의 근거 의무는 불변.

## 진행 중이던 것 (세션 종료 시점)

`RP_20260903_160341_combo` — 멈추기 전에 뜬 tick 의 B4 다섯 칸이 20:27 기동해 약 85분
100% CPU 로 돌다가 22:0x 에 **정상 완료**했다. 원장 반영 확인: 측정 0/5 → **5/5**, 탄 칸 없음.
구판 코드(중첩 이전)로 로드된 워커라 결과는 **단층 오버레이** 측정이고, 그게 이 세대의 의도와 맞다.
entry 는 `active 5/25` 로 남아 있다 — 재개하면 6번째 시도부터 이어간다.
★참고: `attempts_used` 는 **사전등록 시점**에 오른다. tick 중간에 워커를 죽이면
그 칸들은 측정 0인 채 예산만 먹는다(이번엔 끝까지 둬서 피했다).

## 재개 절차

1. `06_Registry/reinforce_auto_config.json::enabled` → `true` (`_disabled_note` 삭제)
2. `Enable-ScheduledTask -TaskName Qvest_ReinforceAutoLoop` (관리자 PowerShell)
3. 첫 tick 후 확인: 승격 entry 의 B5 칸 스펙에 `overlay` 가 **리스트**로 들어가는지
   (`.cache/rf_parallel/spec_B5_*__<base_id>.json`) — 이게 중첩이 실제로 도는 유일한 증거다.

## 검사

`08_Tests/reinforcement/` 24개 전부 통과 — skip 0.
신설 2종: `test_rf_overlay_stack.R`(13) · `test_rf_notify_rank_distinct.R`(14, 전 블록 스윕 포함).

★`test_rf_block_lcode` 는 이번에 skip 이 풀렸다. 오래 skip 이던 검사가 살아나면
그 안의 단언이 **폐지된 규칙**을 강제하고 있을 수 있다 — 이번이 그랬다.

## 이전 세션 사료

2026-09-01 "측정 축 전환(n_max 3→25)" 인계문은 이 파일이 덮어썼다 — 그 내용은 git 이력과
`memory/feedback-satisfying-the-constraint-is-not-receiving-the-setting.md` 카드에 있다.
