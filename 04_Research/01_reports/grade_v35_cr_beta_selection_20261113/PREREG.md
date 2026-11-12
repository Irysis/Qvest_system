# 등급 v3.5 — 위기 복원력 '강함' 가점의 선택 방어 = 시가총액 × β 짝 · 사전등록

- 등록 2026-11-13 08:4x · 등록 시점 HEAD `700296710` · 기계 판독본 = `prereg.json`(같은 폴더)
- 결정: 도훈 11-13 08:24 `GRADE-CR-NOTCH-BETA-SELECTION-20261113` = (가) "β까지 맞춰 수정"
- 근거: 철학 Superfan P2 C-20261113-012(코드 경로 논증) · 헌장 §5 빈칸 14(CHARTER-GAPS-4 · 도훈 11-10)
- 이 문서는 새 규칙을 실제 저장 기록에 돌리기 **전에** 설계 · 재채점 범위 · 보고 항목을 고정한다(measurement-graduation §3b). 결과를 본 뒤에는 바꾸지 않는다.

## 1. 재도출 — 지금 가점이 주어지는 경로

| 위치 | 하는 일 |
|---|---|
| `contracts/grade_v3.R:672-676` | CR 이 strong 일 때만 `.gv3_mc8()` 로 MC8 짝 대조를 잰다 |
| `contracts/matched_controls.R:416` | 판정 플라시보 = 크기 분위 안 무작위 뽑기(레그 Σw = 1) × 평균 노출 Ē. **β 는 맞추지 않는다** |
| `contracts/matched_controls.R:438` | 그 플라시보의 5% 분위를 위기 과반에서 이기면 `selection_defense` |
| `contracts/grade_v3.R:144` | 라벨이 `selection_defense` 가 아니면 `not_selection` → 가점 없음 |
| `contracts/grade_v3.R:146-147` | **노출 경로가 고정이면 곧바로 `selection` → 가점** — 철학 P2 가 짚은 분기 |
| `contracts/grade_v3.R:148-151` | 노출이 변하면 크기 × 노출 경로 짝(× E_k)의 과반 승 → `selection` → 가점 · 아니면 타이밍 증거 |

- **오판 기전**: 같은 크기 분위 안에서 β 가 낮은 종목만 들면, 위기에서는 β 만큼 덜 빠진다. 무작위 플라시보는 평균 β(≈ 1)를 들므로 이 전략이 분위를 이긴다. 그러면 `selection_defense` → 노출 고정 → `selection` → '강함' 가점이 된다. 정적 β 축소가 '종목 선택 방어'로 셈해진다.
- **저장된 계약 산출의 사례**: P1R03 보는 창 진단 패킷(`diagnosis_packet.R` 산출 · 철학 P2 R-20261113-002 표 ②)에서 저β 다섯 엔진(β 0.50~0.72 · 노출 1.00 고정)이 모두 MC8 `selection_defense` 였다.
- **저장 기록 전수(2026-11-13 08:3x · 구 계약 산출만 읽음)**: 권위 기록 3,195건(grade_v3 3,173 · v3.3 3,049 · v3.4 124). CR strong 29건 → 가점 유지(`cr_notch_basis = strong`) 7건(모두 MC8 `selection_defense`) · 보통으로 내림 22건(크기 방어 20 · 타이밍 미증거 2).

## 2. 새 규칙 v3.5 — 설계 고정

### 2.1 크기 × β 플라시보(MC8 β 블록 · `size_beta_placebo_v1`)

- 귀무 = 기존 크기 분위 플라시보 경로 P_j(레그 Σw = 1)를 **현금으로 전략 β 까지 낮춘 사본**(헌장 빈칸 14 '크기 바스켓을 변형 β 로 낮춘 현금 사본'의 분포판).
  - 정적판: 배율 = Ē × ρ_j · 경로판(노출이 변할 때만): 배율 = E_k(t) × ρ_j
  - ρ_j = min(β_leg / β_j, 1)
  - β_leg = 전략 레그의 β. 레그는 보유 기록(분위에 놓인 보유 · 리밸마다 합 1)을 바스켓과 같은 엔진(`.mc_basket_returns` · 매수후보유 · 결측 0)으로 재현한다.
  - β_j = 플라시보 레그 j 의 β.
  - 둘 다 월간 수익 · 절편 있는 OLS 기울기 · 같은 달 · 벤치 = 측정 벤치(`behavior_card.R::.bc_beta` — 행동 카드 β 와 같은 추정기 · 최소 6개월).
  - 상한 1 = 현금 사본만, 차입 없음(헌장 빈칸 14 '현금 사본' · round_core P2 C-017 `rc_p2_size_beta_plan` 의 '차입 없음'과 같다).
- 보고용 결정론 계열: `size_beta_matched` = 크기 바스켓 × Ē × ρ_b(ρ_b = min(β_leg / β_basket, 1)) · `size_beta_path` = 바스켓 × E_k × ρ_b.
- 위기 판정은 기존과 같다. 위기마다 전략 낙폭 포착률이 β 맞춘 플라시보 포착률 분포의 alpha 분위보다 작으면(− tol) '넘음'이다. 창(전체 · 보는 창 · 시험 창)별 비율을 낸다.
- β_j 가 비유한이거나 0 이하인 경로는 뺀다. 남은 경로 × alpha < 1 이거나 β_leg 가 비유한 · 0 이하이면 상태 = `unmeasured` · 비율 = NA 다(fail-closed).
- 기존 라벨 `label`(규칙 `nested_majority_placebo_v2` · 크기 × 노출 짝)은 **그대로 둔다** — 소비자(round_core `RC_P2_MC8_LABELS` · 보고)의 어휘를 바꾸지 않는다. 새 필드만 더한다.
  - `share_beats_size_beta` · `share_beats_size_beta_path` · `median_placebo_p_size_beta` · `label_size_beta`
  - `label_size_beta` 어휘: `selection_defense` | `size_beta_unseparated` | `size_beta_unmeasured` | (구 라벨이 선택 방어가 아니면 구 라벨 그대로)
- 새 숫자 없음: alpha · n · 시드 = `matched_controls.json`(0.05 · 200 · 20261013) · 과반 = `behavior_card.json::majority_share` · β 추정기 = 행동 카드와 같은 함수 · 상한 1 = 정의(현금 사본).

### 2.2 등급 노치(`grade_v3.json::cr_notch.selection_control = "size_beta"`)

CR strong 일 때 노치 근거는 다음 순서로 정한다. 새로 생기는 것은 ② 와 ④ 의 β 경로 조건뿐이다.

1. MC8 라벨 ≠ `selection_defense` → `not_selection` → 보통(그대로)
2. **새 조건** — `share_beats_size_beta` 비유한 → `beta_unresolved`(보통) · ≤ 과반 → `beta_not_separated`(보통 · 헌장의 '크기 × β 미분리')
3. 노출 경로 고정 → `selection` → 강함
4. 노출이 변함: `share_beats_size_exposure_path` > 과반 **이고** `share_beats_size_beta_path` > 과반 → `selection`(강함). 못 쟀으면 `timing_unresolved`. 그 밖은 타이밍 → 증거 (a)(b)(c) 규칙 그대로(`timing_evidence` 강함 · `timing_no_evidence` 보통).

- **강화만 한다**: v3.4 에서 '강함'이 되던 조건은 모두 남고 조건이 더해진다. '강함'으로 가는 새 길은 없다.
- 그래서 같은 입력이면 v3.5 등급 ≤ v3.4 등급이다(노치 순서 C→B · B→A · 팩터 알파 노치의 경우를 나눠 확인 — 구현 검사 Z 절). 규칙만으로 생기는 소급 승격은 없다.
- `selection_control` 이 없으면(구 설정 사본) `size_exposure` = v3.2~v3.4 의미 그대로다(재현용).
- `strong_requires = mc8_selection_defense`(v3.1 형식)에서도 `size_beta` 면 ② 를 요구한다.

### 2.3 PIT · τ_D

- β 는 평가 창의 통계다(평균 노출 Ē 와 같은 자리). 전략의 결정에 쓰이지 않는다. 플라시보 구성(분위 = 집행일 전 거래일 시가총액)은 그대로다.
- 보는 창 진단 패킷(`diagnosis_packet.R::dp_build`)은 입력을 τ_D 로 자른 뒤 MC8 을 부른다. 그래서 보는 창 판의 β 는 τ_D 이전 달만 쓴다.
- 전기간 카드(등급 쪽)는 전기간 β 를 쓴다(등급 = 전기간).

## 3. 재채점 범위(사전 고정)

- **규칙**: 저장 권위 기록(`stage_artifacts/**/authoritative_remeasure.json` · `WT_` 제외 · 재채점 도구 규칙 그대로) 중 아래를 모두 만족하는 것만 v3.5 로 다시 채점한다.
  - `grade_scheme = grade_v3`
  - `grade_v3.rules_version ∈ {v3.3, v3.4}`
  - `grade_v3.cr_notch_basis = "strong"`
- 나머지는 v3.5 채점 = v3.4 채점이다(가점 유지가 없는 기록은 바뀌는 분기를 지나지 않는다). 다시 채점하지 않고 판 표식도 그대로 둔다.
  - 기계화: `grade_v3.json::rules_version_compatible_unless = {v3.3: cr_notch_strong, v3.4: cr_notch_strong}`
  - 기존 재채점 계기(요인 md5 · 선택 점검 설정)는 그대로 둔다.
- **등록 시점 스냅숏 = 7건**(경로 = `prereg.json::scope_snapshot`).
  - 이 등록과 교체 사이에 측정된 기록도 규칙에 걸리면 포함하고 '등록 뒤' 로 따로 보고한다.
  - 교체 뒤 측정분은 처음부터 v3.5 다.
- **시점**: RAWDATA 2026-03-30 수정주가 기준 단절 수리(세션 `rawdata-seam-0330`) 뒤에 한 번 쓴다. MC8 이 RAWDATA 를 다시 읽으므로 두 번 재채점하지 않기 위해서다. 수리가 오늘 안에 끝나지 않으면 현 RAWDATA 로 쓰고 그 사실을 보고에 적는다.
- **쓰기**: `programs/grade_v3_backfill.R --write`(원본 gz 보관 · 임시 파일 → 이름 바꾸기). 규칙 변경 수혜 표식(`gv3b_benefit_mark`)이 자동으로 붙는다(기대 0건).

## 4. 비교 · 보고(사전 고정)

- **표 T1**: 범위 기록의 등급 전이(구 → 신) 건수 — A · B · C · F · 띠 · 노치 근거
- **표 T2**: 전체 권위 기록의 A · B · C · F 분포 전후(범위 밖은 규칙상 불변 — 표 T4 로 확인)
- **표 T3**: 범위 기록마다
  - 구 근거 → 신 근거
  - MC8 크기 × 노출 짝 비율 · 크기 × β 짝 비율(정적 · 경로)
  - 노출 고정 여부 · β_leg · 플라시보 β 비 중앙
- **표 T4(실데이터 음성 대조)**: CR strong 인데 이미 보통인 22건 + 범위 밖 무작위 30건(시드 20261113)을 v3.5 로 드라이런했을 때 등급이 같아야 한다(52/52). 하나라도 다르면 출시를 멈추고 원인을 찾는다.
- 수혜 표식 건수(기대 0) · A → B 로 내려간 기록이 있으면 A 자격 관문 · BOOK 영향을 따로 적는다.
- 차트: 등급 분포 전후 막대 + 범위 기록 전이.
- 보고 대상 = 도훈(텔레그램 · 프로페셔널 퀀트 톤 · IS/OOS 용어). 철학 · 판단 Superfan 에게는 코드 차이 · 합성 대조 · 익명 건수만 준다(재채점 표는 정보 경계상 열지 않는 파일 — 규약 §13-2).

## 5. 출시 조건(검사)

| id | 대조 | 기대 |
|---|---|---|
| N1 | 음성 — 크기 분위 안 저β 종목만(위기 비대칭 없음 · 합성) | v3.4 강함 → v3.5 보통(`beta_not_separated`) |
| P1 | 양성 — β 는 플라시보와 같고 위기에만 덜 빠지는 종목(선택 방어 주입) | v3.5 강함(`selection`) |
| P2 | 양성 — 저β + 진짜 비대칭(하락 β < 상승 β) | v3.5 강함 |
| T1 | 저β + 노출 타이밍(노출 변함) | `selection` 아님(타이밍 → 증거 없으면 보통) |
| M1 | 돌연변이 — ρ 를 무시(β 배율 1) | N1 이 강함으로 뒤집힘 → 검사가 잡는다 |
| M2 | 돌연변이 — 노치 근거에서 ② 를 뺌 | N1 이 강함으로 뒤집힘 → 검사가 잡는다 |
| M3 | 돌연변이 — 상한 1 제거 | 고β 전략의 짝이 차입으로 커져 쉬워짐 → 검사가 잡는다 |
| R | 회귀 — 기존 검사(matched_controls · grade_v3 · fa_notch · behavior_card · backfill mark) | 전부 통과. 구 의미 검사는 `selection_control = size_exposure` 를 명시해 유지 |
| Z | 단조성 — 같은 입력에서 v3.5 등급 ≤ v3.4 등급(노치 경우 전수) | 위반 0 |
| T4 | 실데이터 음성 대조(위 §4) | 52/52 동일 |

## 6. 출시 절차 · 조율

- 핀 파일 5개(`grade_v3.R` · `grade_v3.json` · `matched_controls.R` · `matched_controls.json` · `essence_score.R`)는 스크래치 사본에서 만들고 시험한 뒤 한 번에 원자 교체한다. 무인 레인이 계약을 읽는 중이라 중간 상태를 운영 경로에 두지 않는다.
- round_core 핀(`RC_PIN_FILES_DEFAULT`)이 이 파일들을 묶는다. 교체 뒤 상설 판은 R2 불일치로 새 판 등록이 필요하고, 교체 전 등록 라운드는 측정 전에 멈춘다. 교체 시점은 세션 `l1-next-round` 와 맞춘다.
- 문서: CLAUDE.md 등급 절 · `lean-loop.md` · `measurement-graduation.md` §0 의 현행 판 표기 · 결정 기록부 구현 메모 · `CHANGELOG_constitution.md`.
- 감독: 판단 Superfan T4(의무) + 철학 Superfan(백그라운드) · 판단 원장 `record --kind harness_change` 1건.
