# 등급 v3.5 재채점 결과 — 사전등록 §4 · 부록 1 §4 표
- 생성 2026-11-15 09:57 · 드라이런 `d2f`(v3.4 계약 = 교체 전 커밋 사본 · v3.5 = 운영) · 쓰기 직전 전수 `d2f` · 쓰기 뒤 전수 `post`
- 데이터 시점: 두 드라이런 같은 데이터 시점 — 요인 md5 3dd806e4f9ff · RAWDATA 426228082@2026-11-15T00:14:45
- 채점 오류 0건
- 드라이런 대상 218건 = 위기 방어 가점 범위 12(등록 시점 7 · 등록 뒤 5) ∪ 팩터 수익률 갱신 163(범위와 겹침 8) ∪ 실데이터 음성 대조 52

## T4 실데이터 음성 대조 — 같은 입력에서 v3.4 = v3.5(기준 = 같은 데이터 시점 v3.4 · 부록 1 §2)
- 52/52 동일(강함인데 이미 보통 22 · 무작위 30)
- 범위 밖 기록의 규칙 효과(v3.4 ≠ v3.5 · 교체 전 저장분 v3.3 · v3.4): 0건
- 교체 뒤 v3.5 로 측정된 기록 7건(요인 낡음으로 대상에 듦 · 저장 등급이 이미 v3.5 — 재채점 규칙 효과 없음 · 저장 = v3.5 지금 7/7): v3.4 계약이었다면 달랐을 기록 1건 — stage_artifacts/replication/20261114_170108_24820
- 규칙 효과 오름: 0건(기대 0 — 조건만 추가)

## T1′ 위기 방어 가점 범위 12건 — 저장 → v3.4(지금) → v3.5(지금)

### 등록 시점 7

| 기록 | 전략 | 저장 | v3.4 | v3.5 | 띠 | 근거 v3.4 → v3.5 | 시가총액·노출 일치 | 시가총액·β 일치 | 노출 | 보유 β | ρ 중앙 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `stage_artifacts/replication/20260902_221014_39768` | RF_PAR_B4_24_LOO | F | F | F | F | selection → beta_not_separated | 70% | 30% | 변함 | 0.40 | 0.61 |
| `stage_artifacts/replication/20260902_221014_39768/remeasure_close_t1_5562284e` | RF_PAR_B4_24_LOO | F | F | F | F | selection → beta_not_separated | 60% | 30% | 변함 | 0.40 | 0.61 |
| `stage_artifacts/replication/20260913_220554_33700` | RF_PAR_B4_24_LOO | B | B | B | B | selection → beta_not_separated | 70% | 20% | 변함 | 0.54 | 0.72 |
| `stage_artifacts/replication/20260921_131648_5708/remeasure_close_t1_5562284e` | RF_PAR_B2_6_minvar | B | B | C | C | selection → beta_not_separated | 60% | 10% | 고정 | 0.54 | 0.75 |
| `stage_artifacts/replication/20261113_064917_20128` | P1R03_FCROW_C0 ※ | B | B | C | C | selection → beta_not_separated | 100% | 41% | 고정 | 0.39 | 0.52 |
| `stage_artifacts/replication/20261113_071646_38276` | P1R03_FRISK_C0 ※ | B | B | C | C | selection → beta_not_separated | 94% | 41% | 고정 | 0.40 | 0.52 |
| `stage_artifacts/replication/20261113_072517_8920` | P1R03_TOTAL_C0 ※ | B | B | B | B | selection → beta_not_separated | 88% | 41% | 고정 | 0.38 | 0.52 |

### 등록 뒤 5(사전등록 뒤 측정)

| 기록 | 전략 | 저장 | v3.4 | v3.5 | 띠 | 근거 v3.4 → v3.5 | 시가총액·노출 일치 | 시가총액·β 일치 | 노출 | 보유 β | ρ 중앙 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `stage_artifacts/replication/20261113_095002_12004` | P1R03_FRISK_C0 ※ | B | B | C | C | selection → beta_not_separated | 94% | 41% | 고정 | 0.40 | 0.53 |
| `stage_artifacts/replication/20261113_095303_25704` | P1R03_FCROW_C0 ※ | B | B | C | C | selection → beta_not_separated | 100% | 41% | 고정 | 0.39 | 0.52 |
| `stage_artifacts/replication/20261113_100658_23944` | P1R04_IDEFE_C0 † | F | F | F | F | selection → beta_not_separated | 94% | 18% | 고정 | 0.36 | 0.47 |
| `stage_artifacts/replication/20261113_101007_37992` | P1R04_ILIQU_C0 † | B | B | C | C | selection → beta_not_separated | 94% | 35% | 고정 | 0.38 | 0.52 |
| `stage_artifacts/replication/20261113_101537_39336` | P1R03_TOTAL_C0 ※ | B | B | B | B | selection → beta_not_separated | 88% | 41% | 고정 | 0.38 | 0.52 |

- ※ = 같은 칸의 더 늦은 재측정으로 대체된 P1R03 측정 — 인용 대상 아님
- † = 중단된 측정(판정에 쓰지 않음 · 99_Archive 의 aborted_measure 기록 · 예: P1R04 11-13 10:04~10:31)
- 규칙 효과(v3.4 → v3.5): 그대로 6 · 내림 6
- 데이터 갱신 효과(저장 → v3.4): 그대로 12

## T5 팩터 수익률 갱신 재채점(규칙 무관) 155건 — 저장 → 같은 규칙 버전(지금)

- 교체 전 저장분 148건 = v3.4 계약(지금) · 교체 뒤 v3.5 측정분 7건 = v3.5 계약(지금)

| 앞 | 뒤 | 건수 |
|---|---|---|
| A | A | 3 |
| B | B | 52 |
| C | C | 27 |
| F | F | 72 |

- 교체 전 저장분 v3.4(지금) = v3.5(지금): 147/147

## T2 전체 권위 기록 분포

| 등급 | 재채점 전 | 재채점 뒤 | 변화 |
|---|---|---|---|
| A |     6 |     6 | +0 |
| B | 1,323 | 1,317 | -6 |
| C |   942 |   948 | +6 |
| F | 1,025 | 1,025 | +0 |

- 같은 기록 집합(쓰기 직전 전수 3,296건)끼리 비교 · 그 뒤 새로 측정된 기록 1건은 빼고 셌다(현행 판으로 측정 · 재채점 대상 아님)

- 쓰기 전후 등급이 바뀐 기록 6건 — 원인별:
  - rules_version · 내림 1
  - factor_md5_changed+rules_version · 내림 5
- 새 수혜 표식(등급이 측정 때보다 오른 기록): 0건

## A 등급 · Judge · BOOK 영향
- A 에서 내려간 기록: 0건
- 그중 BOOK 등록부에 이름이 있는 기록: 0건
- Judge 트리거(judge_request.eligible.json)가 있는데 새 등급이 A 가 아닌 기록: 0건

## 그림
- `charts/01_grade_distribution.png` · `charts/02_cr_strong_attribution.png` · `charts/03_transition_by_cause.png`
- 원자료: `data/regrade_table_d2f.csv` · `data/dryrun_v34_d2f.csv` · `data/dryrun_v35_d2f.csv` · `data/census_d2f.csv` · `data/census_post.csv`
