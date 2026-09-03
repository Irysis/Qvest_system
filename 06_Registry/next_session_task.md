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

## 같이 고친 것 — 텔레그램 순위 줄 중복 (도훈 2회 적발)

`.delta_of` 는 "carry 대비 바뀐 축"을 적는데, **B4(결합) 칸의 처치는 축이 아니라 부분집합**이다.
LOO 로 뺀 축이 마침 carry 와 같은 값이면 여러 칸이 글자까지 같아진다 —
실측으로 1·3·4위가 전부 `GR02_Earnings_Growth (GR02_Earnings_Growth) · 비중` 이었다.
`.rf_combo(code)` 신설 → 격자의 `combo.use` + 라벨로 적는다:
`오버레이 제외(LOO) = 구 3축 전체결합 · 팩터+비중+유니버스`.
8-31 의 B5 건(오버레이가 서술에 없어 네 칸이 동문)과 **같은 병**이다 —
그 블록의 처치를 구분하는 축이 서술에서 빠졌다.

**재발 방지** = `test_rf_notify_rank_distinct.R` — 실제 발송 텍스트를 가로채 순위 줄 서술이
서로 다른지 잰다(+ 양성 대조). 서술 경로가 또 바뀌어도 이 검사는 낡지 않는다.

## 진행 중이던 것 (세션 종료 시점)

`RP_20260903_160341_combo` — B4 다섯 칸이 20:27 기동, 82분째 100% CPU 로 **실제 계산 중**이었다.
멈추기 전에 뜬 tick 이라 **구판 코드**(중첩 이전)로 로드됐다 — 결과는 단층 오버레이 측정으로 일관된다.
B4 는 마지막 블록이라 끝나면 25/25 exhausted 로 자연 종료된다.
★죽이면 그 5칸은 `attempts_used` 만 오르고 측정 0으로 탄다(사전등록 시점에 카운트가 오른다).

## 재개 절차

1. `06_Registry/reinforce_auto_config.json::enabled` → `true` (`_disabled_note` 삭제)
2. `Enable-ScheduledTask -TaskName Qvest_ReinforceAutoLoop` (관리자 PowerShell)
3. 첫 tick 후 확인: 승격 entry 의 B5 칸 스펙에 `overlay` 가 **리스트**로 들어가는지
   (`.cache/rf_parallel/spec_B5_*__<base_id>.json`) — 이게 중첩이 실제로 도는 유일한 증거다.

## 검사

`08_Tests/reinforcement/` 24개 전부 통과(`test_rf_block_lcode` 만 skip).
신설 2종: `test_rf_overlay_stack.R`(13) · `test_rf_notify_rank_distinct.R`(6).

## 이전 세션 사료

2026-09-01 "측정 축 전환(n_max 3→25)" 인계문은 이 파일이 덮어썼다 — 그 내용은 git 이력과
`memory/feedback-satisfying-the-constraint-is-not-receiving-the-setting.md` 카드에 있다.
