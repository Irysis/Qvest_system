# 팩터 방향 정책 — 기대수익 방향 · 방어 방향 (2026-11-09)

결정: decision_register **FACTOR-DIRECTION-STORAGE-REPAIR-20261109**(저장값 기준) · **FACTOR-DIRECTION-TWO-VIEWS-20261109**(도훈 'C안' — 두 방향 분리).
근거 표: `06_Registry/factor_direction_audit.json`(schema v2 · 팩터마다 판정 · 근거 · 같은 양 무리 `two_views.groups`).
writer: `factor_db/apply_direction_basis.py`(등록부 두 사본에 쓰는 유일한 길 · 원자적 · 멱등). 판독기: `factor_db/direction_code_parser.py`.

## 1. 등록부 필드(엔트리마다 · 저장 Raw_Value 기준)

| 필드 | 뜻 |
|---|---|
| `direction` | **기대수익 방향**(저장값 기준) — 소비자가 저장값에 곱한다 |
| `direction_economic` | 같은 방향을 definition 이 말하는 양 기준으로 |
| `direction_economic_basis` | `literature`(문헌 · 인용 필수) · `literature_mixed_defensive_tiebreak`(문헌이 갈리거나 없음 → 방어 방향과 같게) · `code_and_definition`(코드 주석 · 정의로 Q 판정) · `registry_original`(문헌 검토 전 — 등재자가 쓴 값) |
| `direction_economic_evidence` | 인용(DOI 는 Crossref 로 확인한 것만) |
| `stored_sign` · `direction_basis` | 저장값 = stored_sign × (definition 의 양) · `stored_raw_value` |
| `direction_defensive` | **방어 방향**(저장값 기준) — 위기 하락 노출↓ · 상승 참여↑ 쪽이 높게. 위험 · 유동성 범위 계열만 |
| `direction_defensive_definition` · `_reason` | 같은 방향의 definition 기준 값 · 이유 |
| `direction_history` · `direction_defensive_history` · `definition_history` | 바뀐 이력 |

범위 계열(방어 방향을 두는 category) = defense · risk · regime · liquidity · leverage · size (158개 · 2026-11-09).

## 2. 누가 어느 방향을 쓰나

| 소비자 | 방향 |
|---|---|
| `load_month_factors` · `load_daily_factors` 기본(`ic_asof`) | 그 시점까지 36개월 IC 부호 → 모자라면 `direction`(기대수익) |
| `direction = "registry"` | `direction`(기대수익) |
| `direction = "defensive"` | `direction_defensive` — 없는 팩터는 명시 요청이면 오류, 아니면 빼고 attr `dropped_no_defensive` |
| 결합용 뷰 `fc_load_month(direction = ...)` | 저장 = 저장 원값 방향(v1.1) · 읽을 때 부호표 `s_reg` · `s_ic` · `s_def` 를 곱한다 |
| FF5 · 스마트베타 추적기 | `direction`(기대수익) |

수동 반전(NEGATE_FACTORS · FLIP_SIGN)은 금지 그대로다(C13). 부호는 등록부와 as-of IC 에서만 온다.

## 3. 판정 규칙

1. 판단에 성과 · IC 를 쓰지 않는다 — 정의 · 코드 · 문헌만(C1 · C14 방화벽).
2. 기대수익 방향 = 그 양에 대한 문헌. 문헌이 갈리거나 없으면 **동률 규칙**: 기대수익 = 방어(definition 기준).
3. **같은 양 일관성**: 같은 양(또는 정확히 반대 부호) 팩터는 두 방향 모두 같다(부호 반영) — `two_views.groups` · 상설 검사 B8.
4. 방어 방향 = 투자철학(위기 하락 노출↓ · 강세 참여): 위험 · 크래시 노출 · 비유동성 · 국면 스트레스는 낮을수록, 상승 참여 지표는 높을수록.

## 4. 자동 반영 — 새 팩터 · 코드 변경이 들어오는 길

| 길 | 처리 |
|---|---|
| `add_factor.R`(충실구현 레인 · 수동 등재) | 등재 순간 `direction_economic = direction` · `registry_original` · `stored_sign = 1` · `stored_raw_value` 를 쓴다(템플릿 · 엔진 패널 = 정의 그대로 저장) |
| 그 밖 모든 길(세션이 고친 `compute_*.R` · 등록부를 다시 쓰는 R 도구 · 손 편집) | **야간 동기화** `daily_refresh.sh [6f]` = `apply_direction_basis.py --sync` |

야간 동기화가 하는 일(매일 · 결과 `.cache/factor_direction_pending.json`):
- 감사 표에 없는 새 엔트리 → 감사 표 자동 등재 + 필드 채움. **소비자 `direction` 은 바꾸지 않는다**. 위험 · 유동성 계열이면 **방어 판정 대기**(판정 전에는 방어 보기에서 빠진다 = 안전한 기본값).
- 등록부 `direction` ≠ 감사 표(손 편집 · 다른 도구) → 고치지 않고 경보(`DR_FAILED` → [7] 텔레그램). 감사 표가 정본이다.
- 빌더 부호 드리프트(판독기 재도출 ≠ 감사 시점) → 경보(뜻 판정이 필요해 자동 수리하지 않는다).
- 두 사본 불일치 → 엔트리 합집합으로 맞춤. 같은 이름 다른 값이면 경보 · 쓰지 않음.
- 서식이 다르면 같은 뜻으로 정규화 · 읽은 뒤 파일이 바뀌면 쓰지 않음(다음 밤).

그 밖에: 결합용 뷰 증분 `[6e]`(첫 전체 빌드 뒤 · 빌드 잠금) · 일간 · 월간 대응표 월 1회 `[6g]`.
상설 검사: `test_factor_direction_basis.py`(B1~B8 + 돌연변이 4) · `test_direction_sync.py`(14) · `test_load_daily_factors.R`(26) · `test_factor_combinable.R`(29) — `run_all_hooks.sh` SUITES.
새 등재는 2일 동안 B1 · B5 에서 경고만(야간 동기화 대기) — 넘으면 실패(동기화가 죽은 것).

## 5. 사람(Q)이 할 일

- **방어 판정 대기 해소**: `.cache/factor_direction_pending.json::pending_defensive` → 감사 표의 그 팩터에 `defensive_definition` · `defensive_reason`(문헌 · 정의) 기록 → `python -I factor_db/apply_direction_basis.py --dry-run` 확인 → 실행 → 상설 검사.
- **기대수익 방향을 바꾸려면 감사 표로**: 감사 표 `direction_economic` · `economic_basis` · `economic_evidence` · `change_decision` · `change_reason` → writer. 등록부를 손으로 고치면 야간 동기화가 충돌로 잡는다.
- **빌더 부호를 바꾸면**(compute_*.R 의 음수화 추가 · 제거) 같은 작업 단위에서 감사 표 `stored_sign` · `code_negated_at_audit` · `stored_expr` 를 고친다(상설 검사 B3 가 잡는다).

## 6. 따로 처리할 과제(잊지 말 것 · 2026-11-09)

각 항목은 끝나면 지운다(이 문서가 목록 정본 · 메모리 카드 project-factor-direction-storage-repair-20261109 가 가리킨다).

**팩터 DB**
1. 일간 빌더 정의를 월간에 맞추기 — 일간 · 월간 대응표 mismatch 201개(지금은 접근자가 정렬 거부). 일간 R19 합성도 같은 부호 결함(`factor_db_daily_phase9.R`).
2. 정의 문구 ≠ 코드 38개(판정표 summary.defects) — D05(252일 대 약 21거래일) · D08 · D11 · D15 · D19/D20(등가중 표기 · 실제 지수가중) · D25/D26(종목 10% 대 시장 5%) · D30 · D31 · D33 · L12(Pástor–Stambaugh 감마) · L13 · L14 · L21 · L25 · L37 · L40 · RE_*_z(횡단면이라 적었으나 시장 공통 시계열) 등. L35 는 2026-11-09 수리.
3. 구성 결함 — Amihud 류(L01 · L09 · L11 · L14 · L25)가 거래대금이 아니라 주식 수로 나눔(주가 수준 효과 섞임) · L24 규모 의존 · R05 평균 0 근처 발산 · XF_LL02 정규화 안 된 금액.
4. XF_RI02 ↔ IN01 중복 선언(dedup — 수리 뒤 같은 양 부호만 반대).
5. `compute_custom.R::.save_registry` — 한 사본만 · 통째로 다시 쓰는 휴면 writer(호출처 없음) — 고치거나 지우기.

**측정 · 등급**
6. 영향 라운드 재측정 — D03 · D04 · D07 쓴 24칸(P0R01 6 · P2R01 1 · P2R04 15 · P2R05 2) + 재무 v1 정정값 누출(V10 · Q08 쓴 현 축 라운드 전부) + **이번 기대수익 방향 47개 변경을 쓴 칸 찾기**(IC 36개월 전 대체 · registry 모드). 재측정 전에는 그 판정 인용 금지.
7. v3.3 A 3개(P2R03_E3_RX0 · P2R04_E3_RX0 · P2R03_E3_L2) — 11-10 재채점에서 팩터 알파 노치로 B → A(최소 t 4.46~4.47 · FF6). 재무 v1 위 측정이라 **보류**: 재무 v2 팩터 DB 로 재측정(run_paper_replication — A 자격 관문이 그때 정식으로 돈다) → Judge. 그 전에는 A 인용 금지(FUND-V2-PRIOR-GRADES-REMEASURE-ON-CITE). 재채점 기록 = `04_Research/01_reports/l1_prescription_redesign_20261013/s0_grade_v3/v33_backfill_20261110/`.
8. 정정 텔레그램(prep_send) — 영향 라운드 방어 판정.
9. 앞서 쌓인 것: F-Score 재측정 · 11-10 아침 점검 · FF5 추적기 CMA 부호 · QMJ · P2R05 재핀.

**시험 · 문서**
10. 시험 총계 기준선 재승격 — 이 작업 관련 시험은 11-10 에 전부 통과 · 집계됨(깨진 2건 수리 · 요약 줄 없던 6건 · 재무 v2 4건 편입). 기준선은 배터리의 다른 실패(11-10 밤 107 — r_portability 35 · map_freshness_content 11 등 다른 작업분)가 0 이 된 뒤에만 올릴 수 있다(suite_totals_watch 가 fail > 0 이면 승격 거부).
11. 규칙 문서 갱신(factor-db.md · pit.md — 세션 경계에서): 두 방향 · 야간 동기화 · 결합용 뷰 v1.1 · emission_guard v1.3 낡은 별칭.

**판단 재검토 후보(판정표 · Q 덮어쓰기)**
12. 확인 못 한 인용 — Bollerslev, Li & Zhao 2020 의 부호(D58 · R14) · Akbas 외 · Lesmond 외 1999 · Goyenko 외 2009 · Bekaert 외 2007 · 상방 베타 무프리미엄 요약(D06 · D26).
13. 해석이 갈릴 수 있는 것 — R17 시장 레버리지(Penman 외 2007 은 B/M 통제 뒤 반대) · 거래량 추세 무리 G30(Q 가 방어를 '급증 = 급락 위험'으로 덮어씀) · RE05 · MA02/MA03(위기 종류에 따라) · L37(코드가 횡단면 수준).

## 7. 사고 기록

2026-11-09 20:46~20:50 — 야간 동기화 끝까지 시험(add_factor.R)을 임시 폴더에서 돌린다는 것이 `~/.Renviron` 의 QM_ROOT 가 넘긴 값을 덮어 **운영 등록부 · custom_factors.json 에 시험 팩터 `L_TMP_E2E` 가 들어갔다**. 그 사이 돌던 전체 재빌드가 202312 를 지으며 2,542행을 넣었다. 수습: `remove_custom_factor` 로 등록부 두 사본 · 스펙에서 제거(나머지 바이트 동일 확인) · 202312 에서 그 행만 제거(나머지 행 동일 확인) · 202401 은 영향 없음 확인. 교훈: R 로 임시 루트 시험을 돌릴 때는 `R_ENVIRON_USER` 를 빈 파일로 지정한다.
