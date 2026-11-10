# 레인 W — 팩터 DB 수리(11-08~11-10) × v10.2 소비자 배선 감사 (읽기 전용 · 2026-11-10)

방법: grep · 파일 읽기 · git log 만. R/Python 실행 없음(예외: 처음에 `python --version` 1회를 실수로 실행 — 파일 접근 없음). `.cache/factor_db*` 미접촉.
경로는 저장소 루트 `G:/OneDrive/Quant_Module_Moltbot/` 기준 상대 경로.

## 0. 요약 판정

- 수리 쪽(접근자 · 결합용 뷰 · 대응표 · FF 빌더 · 체인 [5c][6e][6f][6g])은 구현 · 시험이 되어 있다.
- 소비 쪽(v10.2 생성기 · 판정기 · 원장)은 거의 전부 **옛 기본값(`direction = "ic_asof"`)으로 묵시 호출**한다. `direction = "defensive"` · `"registry"` 를 명시하는 운영 소비자는 결합용 뷰 빌더 하나뿐이다. 결합용 뷰를 읽는 운영 소비자는 **0곳**이다.
- 판 표식(재무 v1|v2 · 팩터 DB 빌드 해시 · 방향 등록부 판)이 측정 산출물에 기계적으로 실리지 않는다. 그래서 "인용 전 재측정" 표식(FUND-V2-PRIOR-GRADES-REMEASURE-ON-CITE)을 **읽는 코드가 0곳**이다.

## 1. 수리 항목 × 소비자 표

| 수리 | 소비자 | 쓰임(파일:행) | 판정 |
|---|---|---|---|
| ③ direction 인자 | 셀 엔진 팩터 적재 | `02_Infrastructure/reinforcement/rf_cell_engine.R:278` `load_month_factors(d, factor_names = fs$id)` — 인자 없음 = ic_asof | 낡음 |
| ③ direction_defensive | 셀 엔진 B7 방어 슬리브 | `rf_cell_engine.R:425` `.load_factor(...)` → 같은 278행 경로(ic_asof). `direction = "defensive"` 아님 | 빠짐 |
| ③ | 슬리브 선정 통계 | `rf_sleeve.R:248-283`(ic_bad = `factor_ic_monthly` IC). IC 는 **저장 원값** 기준이다(`factor_db_builder.R` compute_all_factor_ic_monthly 안 `cor(Raw_Value, Fwd_Ret)`). 처치는 ic_asof 정렬 z 를 쓴다 | 빠짐(부호 기준 불일치 위험 · 칸 영향 미확인) |
| ③ | 무작위 β 짝 대조 β 팩터 | `rf_cell_engine.R:431` 같은 ic_asof 경로 | 낡음 |
| ③ | 오버레이 R05 꼬리 위험 | `reinforcement/overlay_arms/pg2_risk_overlay.R:335`(ic_asof) | 낡음 |
| ③ | P2R04 방어 틸트 · P2T0 · P2R05 | `04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/register.R:632-633` 은 결함을 서술만 한다 · `P2T0_rl_probe/probe.R:1001`(ic_asof) · `P2R05.../round_rules.R:113` | 낡음(재측정 대상 — DIRECTION_POLICY §6-6) |
| ③ | ML 특성 패널 | `02_Infrastructure/ml_pipeline/build_charpanel.R:108`(ic_asof · 시점 간 학습) | 낡음 |
| ③ | 충실구현 레인 프롬프트 | `02_Infrastructure/ops/rf_replication_auto.sh:767-774`(registry 안내 11-10 추가) | 정상 |
| ③ | 충실도 감사 축 | `06_Registry/rf_fidelity_axes.json:14`(registry 요구 · 위반 = 발견) | 정상(LLM 감사만 · 결정론 사전검사 없음 — `ops/rf_preaudit.py` 에 direction 검사 0) |
| ③ | 상설 판 입구 | `04_Research/programs/_lib/round_core/v1/standing.R:14,291-295` — `load_month_factors` 호출 = `factor_db_asof` 로 분류하고 direction 인자는 보지 않는다. `P1S01.../round_spec.json:37-39` orientation_admit = engine_native 만 | **충돌**(프롬프트대로 registry 를 쓴 엔진도 dynamic_sign 으로 제외) |
| ④ 결합용 뷰 | 전 소비자 | `fc_load_month` 호출 = `factor_combinable.R`(정의) · 시험뿐(grep) | 빠짐 |
| ④ | 상설 판 정적 검사 | `standing.R:14` RC_STANDING_FDB_CALLS 에 `fc_load_month(s)`·`fc_daily` 없음 → 결합용 뷰(ic_asof 포함)를 쓴 엔진이 engine_native 로 **통과** | 빠짐 |
| ④ | C15 스캐너 | `02_Infrastructure/validation/c15_load_path_scan.R:38,42`(패턴 `factor_db`) — `.cache/factor_combinable/fc_*.parquet` 직접 읽기를 못 잡는다 | 빠짐 |
| ④ | 처방 도구 상자 | `02_Infrastructure/programs/rx_round.R:145-150` "팩터 DB 정렬 z-점수"만 안내 · 표 '방향' 열 = 등록부 `direction`(115) — 엔진 값은 ic_asof(41% 반대) | 낡음/오도 |
| ② 두 방향 | 처방 도구 상자 표 | `rx_round.R:112-118` direction_defensive · category 범위 · direction_economic_basis 를 안 싣는다 | 빠짐 |
| ⑤ 대응표 | `load_daily_factors` | 커넥터 내부 · `daily_refresh.sh` [6g](27일 주기) | 정상(단, 총부채 27팩터는 일간 과거 달 미재계산 — 대응표 재측정 시 mismatch → 정렬 거부 가능 · 미확인) |
| ⑥ FF 요인 | 등급 v3.3 | `contracts/grade_v3.R:482-507`(meta md5 일치 때만) · `essence_score.R:604-605`(factor_md5 · vintage · epoch 기록) | 정상(기록) · 소비 측 대조 없음 |
| ⑥ | A 자격 관문 · 재채점 | `factor_md5` 를 읽는 코드 = essence_score.R · grade_v3.R 뿐 | 빠짐(요인 판 바뀐 기록 탐지 없음) |
| ① 재무 v2 | 시드 엔진 | `04_Research/strategies/RP_AUTO_2002_06975/engine.R:316` fundamental_merged.parquet 직접(원값) — P1S01 시드 E2 · E3(`P1S01.../specs/*.json:17-19`) · E3 는 V10 추가 | 판 무표식 |
| ①②⑧ 판 표식 | 라운드 지문 | `round_core/v1/fingerprint.sh:14-17` 크기 · mtime 만(fundamental_merged · registry · build_hash · IC · 월 파일). `fundamental_source.json` · `factor_direction_audit.json` · 대응표 · `kr_factor_returns` meta · fc_meta 없음 | 부분 |
| 〃 | 상설 원장 | `standing.R:551-557` 은 `fp_same` 불리언만 기록하고 지문 내용은 안 남긴다. `rc_standing_fingerprint`(533) 는 stderr 를 버린다(stat 실패 = 빈 문자열 → fp_same FALSE) | 빠짐 |
| 〃 | authoritative_remeasure | `alpha_search/run_paper_replication.R:397-411,515-525,818-828` fdb_md5 = `data_cutoff` 를 줄 때만. round_core · 레인은 data_cutoff 를 안 쓴다(grep 0) | 빠짐 |
| 〃 | 결과 원장 | `round_core/v1/outcomes.R:54-61` epoch 만 · 판 표식 없음 | 빠짐 |
| 〃 | 2계층 풀 | `contracts/defensive_score.R:165-200` ds_pool_eligible · `register_measured_module.R`(epoch · vintage grep 0) | 빠짐 |
| ⑦ 별칭 해제 | dedup=TRUE 소비자 | 셀 엔진은 dedup 미사용(기본 FALSE) · 결합용 뷰 기본 dedup | 정상(시험 `test_factor_dedup_consumption.R`) |
| ⑧ 총부채 수리 | 결정 등록 | README 의 `FACTOR-DB-TOTALDEBT-ZERO-REPAIR-20261110` 이 `06_Registry/decision_register.json` 에 없다(grep 0) | 빠짐 |
| 자체 엔진 레인 | 생성기 | 코드 없음(grep '자체 엔진' = 문서 · bootstrap 문구뿐) | 빠짐 |

## 2. Q1 — 접근 경로 · direction 값

- 운영 소비자는 거의 전부 `load_month_factors(...)` 를 direction 없이 부른다(= `ic_asof`). 위 표의 셀 엔진 · 슬리브 · β 대조 · 오버레이 · P2T0 · build_charpanel 과 `ops/rf_factor_autoregister.R:82` · `_lib/fdb_partcache_prefetch.R:17` 이 그렇다.
- 명시 호출은 `factor_combinable.R:188`(registry) 하나다. 시험 `08_Tests/factor_db/test_load_daily_factors.R:113-164` · `test_factor_combinable.R` 만 defensive · registry 를 쓴다.
- 방어 틸트 · 방어 블록(B7 · P2R04 계열)은 `direction = "defensive"` 를 쓰지 않는다. 방식 = 기대수익 IC as-of 정렬 z(+ IC 36개월 전 등록부 direction 대체).
  - P2R04 는 대체 경로를 로그 파싱으로 꼬리표만 단다: `P2R04.../evaluate.R:333-370` 이 커넥터 `factor_db_connector.R:759,801` 의 로그 문구에 묶여 있다.
- 셀 사양 어휘에 direction 필드가 없다. `.load_factor`(`rf_cell_engine.R:274-285`) 는 `fs$kind/id` 만 읽는다. 그래서 처방이 방향을 고를 길이 없다.
- 결합 · ML 입력: `build_charpanel.R:108` · P2T0 probe 는 결합용 뷰를 쓰지 않는다. 셀 엔진 결합(`rf_cell_engine.R:340-367`)은 자체 rank-Z 다. 결측은 inner merge(334행)로 종목을 탈락시킨다 — 뷰의 missing="zero" 와 다르다.

## 3. Q2 — 판 표식

- 필드는 **부분적으로만** 있다.
  - FF 요인 판: `grade_v3.R` 이 `fa.factor_md5` · `factor_vintage` · `factor_epoch` 를 쓰고 `essence_score.R:604-605` 가 authoritative_remeasure 에 싣는다. 읽는 곳은 없다.
  - 팩터 DB 빌드 해시: 커넥터가 `attr(result, "factor_db_build_hash")` 를 붙인다(`factor_db_connector.R:449-455`). 산출물에 옮기는 소비자는 grep 상 `rf_base_cache.R:69-83`(캐시 키)뿐이다. fdb_md5 는 data_cutoff 경로에서만 쓴다.
  - 라운드 `*.fp_start/fp_end` 는 파일 크기 · mtime 이다. 예: `P2R04_E3_RX0.fp_start` 1~3행 fundamental_merged 30,270,202 바이트(v1 추정 · 미확인). v1|v2 · 방향 판을 사후에 추정할 재료는 되지만 그 자체가 표식은 아니다.
- **재무 원천(v1|v2) · 방향 등록부 판(감사 표 md5) · 대응표 판을 적는 필드는 없다.**
- 확인하는 쪽:
  - A 자격 관문 `reinforcement/rf_runner_gates.R:637-720` 은 vintage_flag(pit_c11 · 전표본 선정 계보) · accounting 만 본다. 재무 · 방향 · 총부채 표식이 없다.
  - 상설 판 입구 `standing.R:353-399` 에 판 검사가 없다.
  - 재료 큐: `06_Registry/research_programs.json` 에 해당 필드 0. `programs/program_registry.R` grep 0.
  - 2계층 풀: 없음.

## 4. Q3 — 낡은 등급 소비 차단

- **기계적으로 가리는 곳이 없다.** `FUND-V2-PRIOR-GRADES-REMEASURE-ON-CITE-20261109` · `FUND-V2-SWITCH-EXECUTED-20261109` 영향 목록(`fundamentals_v2/affected_strategies_20261109.json`) · DIRECTION_POLICY §6-6/7 을 읽는 코드는 grep 0 이다(decision_register 자신만).
- 표식이 사람 글에만 있고 코드는 안 읽는 곳:
  - (a) 상설 판 스캔: 시드 E2 · E3 가 v1 재무 엔진(RP_AUTO_2002_06975)이다. 측정 때 v2 로 다시 재므로 결과는 v2 이지만, 입구가 레인 측정(handoff artifacts)의 판을 보지 않는다.
  - (b) 재료 선택(등록부 큐).
  - (c) 진단 패킷: `contracts/diagnosis_packet.R:78-87` 은 산출물을 판 확인 없이 읽는다.
  - (d) 칸 평가: `round_core/v1/cell_eval.R:68,83` 이 `essence_grade` 를 판 확인 없이 읽는다.
  - (e) 2계층 풀: `ds_pool_eligible`.
  - (f) A 관문 재평가: v3.3 A 3칸은 "보류 파일 안 씀 — 재측정 때 관문" 이다(메모리 카드). 관문 자체에 v1 검출은 없다.
  - (g) 결과 원장: 아직 없다(`06_Registry/round_outcomes.jsonl` 미생성). 생기면 판 표식 없이 교훈이 쌓인다.
  - (h) 처방 도구 상자: 과거 칸 수치를 직접 넣지는 않는다(`rx_round.R` 가림). 해당 약함.

## 5. Q4 — 자체 엔진 레인

- 생성기는 **없다**. 설계에만 있다: `04_Research/01_reports/qvest_v10_2_audit_redesign_20261110/README.md:103,109,168`. CLAUDE.md:31 은 [무인] 파이프라인에 있는 것처럼 쓴다.
- 가장 가까운 블록은 셀 엔진 사양이다.
  - 구성: `base_signal`(`rf_cell_engine.R:99-194` · mom_12_1 | engine | engine_blend) + `factors: [{kind: "db", id}]`(267-338) + `base_weight`(360-367 · 0 이면 팩터 평균만) + 표준 선정 · 비중 · 25종 · LIQ.
  - 한계 ①: base_weight 0 이어도 `PANEL` 은 `!is.na(.base_sig)`(258)를 요구한다. 그래서 커버리지가 기저 신호(모멘텀)에 묶인다.
  - 한계 ②: 팩터마다 inner merge(334)다.
  - 한계 ③: direction · 결합용 뷰 kind 가 없다.
- 붙이려면 다음이 필요하다.
  1. 셀 엔진에 `factors[].kind = "fc"`(fc_load_months · direction 필수 · missing 규칙) 또는 `base_signal.kind = "family_composite"`(category → id 목록 · dedup · direction · 기저 신호 없이 패널 정의)를 둔다.
  2. 가족 정의 정본: 등록부 `category` + 제외 규칙(custom · lifecycle · alias)을 등록부 · 설정 파일에 사전 고정하고 md5 핀을 건다.
  3. 상설 판 입구가 이 엔진을 받는 orientation 어휘(`registry_fixed` 등)와 정적 검사가 필요하다. `standing.R:13-16`.
  4. 가족당 시행 1회 회계: `trial_budget.R` · `rc_standing_nf_prior` 의 family_root = category.
  5. 생성 함수 핀(`rc_p1_cell_spec` 같은 방식)이 필요하다.

## 6. Q5 — 문서 낙후 (`파일:행 — 현재 요지 — 무엇이 틀렸나`)

- `.claude/rules/pit.md:33` — C13 "Z_Score_Aligned only" — registry · defensive 보기(C13 해석 확장 FACTOR-COMBINABLE-VIEW · TWO-VIEWS)와 결합용 뷰 부호표가 없다.
- `.claude/rules/pit.md:35` — C15 "load_month_factors 경유" — load_daily_factors · fc_load_month(결합용 뷰 parquet 직접 읽기 금지 포함)가 없다.
- `.claude/rules/pit.md:25` — C4 "현 구현 data_collector_dart.R:840 정합 · xlsx Q4 +45d 수리 항목" — 재무 v2(실제 공시일 · 늦은 날 다음 거래일 · 정정 검사)로 바뀌었다. 행 번호도 낡았다(메모리 카드는 :1212). v1 의 정정본 · 늦은 제출 C4 누출 사실이 빠졌다.
- `02_Infrastructure/docs/rules/factor-db.md:9,11` — C13 · C15 같은 낙후. 마지막 수정 07-26(git log).
- `factor-db.md:13` — 일간 접근자 "월간 ic_sign 경로 재사용"(전 구간 부호) — 날마다 as-of 부호 + 대응표 · direction 3모드로 바뀌었다.
- `factor-db.md:41` — 등록 373 — 현재 수 미확인. 방향 필드(direction_economic · stored_sign · direction_defensive) · 야간 동기화 [6f] · 결합용 뷰 · emission_guard v1.3 · 별칭 해제가 없다.
- `.claude/skills/research-program/SKILL.md:59` — 자체 엔진 레인을 "등록부 방향"이라고만 쓴다 — 결합용 뷰 · direction 모드 · 사전등록에 방향 모드 기록 규칙이 없다. 재무 v1 등급 인용 전 재측정 절차도 없다(grep '재측정' 110 · 138행만).
- `.claude/skills/alpha-search/SKILL.md:49` — "재무 지연(연간 익년 3/31·분기 45일+)" — v2 원천 · direction="registry" 안내(레인 프롬프트엔 있음)가 없다.
- `.claude/skills/reinforce/SKILL.md:39-40` — 도구 상자 · 픽커 설명 — B7 방어 슬리브가 방어 방향을 안 쓴다는 사실 · direction 모드 언급이 없다.
- `CLAUDE.md:31` — [무인] 파이프라인에 "자체 엔진 레인 → 상설 판(P1 자격) → 엔진 풀" — 생성기 코드가 없고 P1S01 은 미등록(research_programs.json grep 0)이다. 현재형 서술이 과장이다.
- `.claude/rules/lean-loop.md:12` — 생성기 셋 — 같은 과장(자체 엔진 레인 미구현).
- `02_Infrastructure/programs/rx_round.R:147` — 처방 에이전트에게 보이는 글 "팩터 값 = 정렬 z-점수" + 표 방향 열 = 등록부 direction — 실제 값은 ic_asof 라 41% 팩터에서 표와 반대다.
- `02_Infrastructure/factor_db/DIRECTION_POLICY.md:84`(§6-11) — 규칙 문서 갱신을 스스로 미결로 적어 두었다(위 항목과 같다).

## 7. Q6 — 시험

있음(배터리 `08_Tests/hooks/run_all_hooks.sh` 편입):

| 시험 | 배터리 행 | 대상 |
|---|---|---|
| `08_Tests/factor_db/test_load_daily_factors.R` | :384 | 월간 · 일간 direction 3모드 + 돌연변이 |
| `test_factor_combinable.R` | :380 | 결합용 뷰 |
| `test_factor_direction_basis.py` | :387 | 등록부 방향 |
| `test_direction_sync.py` | :391 | 야간 동기화 |
| `test_factor_dedup_consumption.R` | :817 | 별칭 해제 |
| `test_emission_guard.R` | :179 | emission_guard |
| `08_Tests/data/test_kr_factor_returns.R` | :370 | FF 요인 빌더 |
| `08_Tests/data/test_build_fundamental_merged_v2.py` | :377 | 재무 v2 병합 |
| `08_Tests/contracts/test_grade_v3_fa_notch.R` | :1903 | 팩터 알파 노치 |
| `08_Tests/programs/test_round_core_v1_standing.R` | :1926 | 상설 판 — B8 = factor_db_asof 허용 대안만 · 72-73 · 153-155 |

그 밖(배터리 편입 미확인): `test_rebuild_factor_subset.R` · `test_build_hash_provenance.R`.

배선은 있는데 시험이 없는 곳:

1. 셀 엔진 · 슬리브가 쓰는 direction(어느 모드로 읽는지 단정하는 시험 없음 — `test_rf_cell_engine_smoke.R` · `test_rf_sleeve.R` 에 direction grep 0).
2. 슬리브 선정 통계(원값 IC)와 처치 값(정렬 z) 부호 일관성.
3. 상설 판 정적 검사가 `direction = "registry"` 호출 · `fc_load_month` 호출을 어떻게 분류하는지.
4. C15 스캐너의 결합용 뷰 parquet 직접 읽기 탐지.
5. 판 표식(재무 원천 · 빌드 해시)이 authoritative_remeasure · 상설 원장에 실리는지.
6. P2R04 `p2_parse_direction_lines` 가 묶인 커넥터 로그 문구(`factor_db_connector.R:759,801`)의 형식 고정.
7. 일일 체인 [5c] · [6e] · [6f] · [6g] 순서 · rc 처리(블록 단위 시험 없음 · 미확인).

## 8. 고칠 곳 목록 (우선순위)

| # | 파일:행 | 무엇을 | 왜 | 위험 |
|---|---|---|---|---|
| P0-1 | `rf_runner_gates.R:690-720` + 새 표식 원천 | A 관문 · 2계층 풀(`defensive_score.R:165`) · 상설 입구에 '판 표식' 검사 추가 — 산출물 측정 시각 < 전환 시각(FUND-V2 11-09 11:40 · 방향 수리 · 총부채 수리 재계산 완료 시각)이면 보류(fail-closed) | Q3 — 인용 전 재측정이 사람 기억에만 걸려 있다. v3.3 A 3칸이 관문을 타면 막을 장치가 없다 | 오래된 B 기록 대량 보류 → 2계층 풀 축소(의도된 효과지만 보고 필요) |
| P0-2 | `run_paper_replication.R:818-828` | measurement_regime 에 항상 `factor_db_build_hash`(build_hash.txt) · `fundamental_source.active` · 방향 감사 표 md5 · 대응표 md5 · 측정 시각을 싣는다(data_cutoff 무관) | Q2 — 표식이 없으면 P0-1 이 mtime 추정에 기대야 한다 | 키 추가뿐 · 골라 쓰기 쓰기라 빠뜨리면 조용히 사라진다(파일 주석 829-833 의 선례) |
| P0-3 | `standing.R:14,291-295` + P1S01 사양 | 정적 검사가 direction 인자 값을 읽어 `registry` · `defensive`(고정 부호)를 별도 분류하고, `fc_load_month(s)`/`fc_daily` 를 FDB_CALLS 에 넣는다. P1S01 은 미등록이므로 **등록 전에** orientation_admit 결정 | 레인 프롬프트(registry 권장)와 상설 입구(dynamic_sign 제외)가 서로를 상쇄한다. 결합용 뷰 ic_asof 는 통과하는 구멍이 있다 | 생성 함수 · 규칙이 바뀌면 판 핀이 바뀐다 — 등록 전이라 지금이 쌈 |
| P1-4 | `rf_cell_engine.R:274-285` · `rf_spec_axes.R` · `rx_round.R:145-150` | 팩터 사양에 `direction`(ic_asof|registry|defensive · 기본 = 현행) 필드. 도구 상자 표에 direction_defensive · 실제 정렬 모드 표기 | 처방이 방어 방향을 고를 수 없고, 도구 상자 표기와 실제 값이 41% 어긋난다 | 기본값 유지로 과거 칸 재현은 불변이어야 한다(기저 캐시 키 `rf_base_cache.R` 에 direction 포함 필요) |
| P1-5 | `rf_cell_engine.R:425,431` · `rf_sleeve.R:292~` | B7 슬리브 처치 값 = `direction = "defensive"`(또는 선정 통계와 같은 원값 부호), β 짝 β 팩터 = registry 고정 | 선정은 원값 IC(ic_bad)인데 처치는 기대수익 IC 정렬 z — 방어 팩터 부호가 처치에서 뒤집힐 수 있다(칸 영향 미확인 · 먼저 확인) | 규칙 변경 = 새 칸(B7 주석 59-60 규약) · 기존 B7 칸 해석 재검토 |
| P1-6 | `fingerprint.sh:14-17` · `standing.R:551-557` | 지문에 `06_Registry/fundamental_source.json` · `factor_direction_audit.json` · `factor_daily_monthly_parity.json` · `.cache/kr_factor_returns*` meta · fc_meta 추가. 상설 원장에 지문 본문 또는 md5 저장 | 측정 중 판 교체 탐지 + 사후 판 판독 | 지문이 바뀌면 같은 판 비교(`same_fp`)가 옛 결과와 어긋남 — 새 측정부터 |
| P1-7 | `outcomes.R:54-61` | 결과 원장 레코드에 판 표식(P0-2 와 같은 키) | 다음 설계가 v1 · 방향 수리 전 교훈을 구분해야 한다 | 원장 미생성 — 지금 바꾸면 비용 0 |
| P1-8 | `c15_load_path_scan.R:38,42` | `factor_combinable` 경로 · `fc_*.parquet` 직접 읽기도 검출(양성 대조 포함) | 결합용 뷰의 PIT 가드(신호일 < as-of 멈춤 · 부호표)를 우회할 수 있다 | 낮음 |
| P2-9 | `build_charpanel.R:108` · `P2T0_rl_probe/probe.R:1001` | 시점 간 학습 입력 → `fc_load_months(direction = "registry")` 또는 registry | 학습 창과 채점 창의 부호가 갈린다(레인 프롬프트 · fidelity 축이 스스로 금지한 형태) | P2T0 는 라운드 산출물이라 재측정 판 |
| P2-10 | 새 생성기(Q4) | 가족 단위 엔진: category → id(등록부 · 사전 고정 · md5 핀) · 결합용 뷰 · direction 명시 · 기저 신호 없는 패널 | v10.2 로드맵 3번 | 총부채 재계산 완료 뒤 착수(설계 README:168) |
| P2-11 | `06_Registry/decision_register.json` | `FACTOR-DB-TOTALDEBT-ZERO-REPAIR-20261110` 등록 + 영향 27팩터 목록 첨부(FUND-V2 ④ 형식) | README:4 가 결정 ID 를 인용하는데 등록부에 없다 · P0-1 의 시각 원천 | 없음 |
| P2-12 | 문서(§6) | pit.md C4 · C13 · C15 / factor-db.md 9 · 11 · 13 · 41 / SKILL 3종 / CLAUDE.md:31 · lean-loop:12 / rx_round.R:147 | 낙후 · 과장 | 헌법 문서는 도훈 확인 범위(CLAUDE.md 버전 표기 단일 출처) |
| P2-13 | `P2R04.../evaluate.R:336-339` | 커넥터 로그 문구 파싱 → 커넥터 attr(방향 원천 집계) 사용 또는 문구 고정 시험 | 커넥터 문구가 바뀌면 꼬리표가 조용히 0 이 된다 | 낮음 |

## 9. 미확인

- B7 슬리브 부호 불일치가 실제 칸에서 처치를 뒤집었는지 — 팩터별 as-of IC 부호 대 ic_bad 부호 대조가 필요하다(실행 금지라 못 함).
- 총부채 수리 뒤 대응표 재측정 결과 — 27팩터 중 일간 대응 팩터가 mismatch 로 바뀌었는지(`run_factor_subset_repair.sh` 의 대응표 단계 결과 미열람).
- `kr_factor_returns` 가 총부채 수리로 md5 가 바뀌는지(FF OP · INV · B/M 이 TotalDebt 를 쓰는지 빌더 미열람).
- `QM_ROOT_POSIX` 가 메인 PC(G:) 측정 환경에 설정돼 있는지. `fingerprint.sh:7` 기본값은 `/c/Users/99922/...` 이다. 미설정이면 stat 실패 문자열끼리 비교한다.
- `fdb_partcache`(`factor_db_connector.R:311-330`) 무효화 키 = 월 파일 크기 · mtime · 열이다. direction 은 정렬 뒤 단계라 무관하다고 판단했지만 실행 확인은 없다.
- 등록부 팩터 수(factor-db.md:41 의 373 대비 현재).
- `test_rebuild_factor_subset.R` · `test_build_hash_provenance.R` 의 배터리 편입 여부.
- `register_measured_module.R` 이 epoch 를 다른 경로(모듈 meta)로 싣는지 — grep 0 만 확인했다.
