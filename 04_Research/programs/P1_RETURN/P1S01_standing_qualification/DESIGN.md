# P1S01 설계 — P1 상설 자격(표준 구성 · round_core v1 상설 판 · 판 1)

> 이 문서는 **사고 기록**만 담는다. 코어가 승계하는 항목은 다시 쓰지 않는다:
> PIT C1~C15 · τ_D(판정 규칙의 시험 창 열 사용 금지 검사) · 측정 기계 · 핀 · 등록 조건 ①~⑧ · 칸 평가.
> 규칙 문장 · 표 = `round_spec.json` 선언에서 생성(`round.sh <dir> check`). 상설 판 고유 규칙(레인 스캔 · 항목 R2 · 원장 · 보고 · Superfan) = `standing_rules.md`(`round.sh <dir> standing-check` 가 사양에서 생성 — 손으로 고치지 않는다).
> 근거 결정: 도훈 10-20 `L1-SPEED-PLAN-20261020` · `L1-SPEED-LEVERS-20261020`(구조 레버 4종 중 'P1 상설 자격 등록') · 계획서 §10 · WP5.
> **11-11 등록 판**: 10-20 판 사양을 v10.2 사다리 루프 순서 1(설계 `04_Research/01_reports/qvest_v10_2_audit_redesign_20261110/README.md` §4)로 등록한다. 등록 전 재핀 · 입구 수리 반영 = §12(규칙 문턱 · 판정 규칙 불변).

## 1. 질문 · 가설
- **질문**: 충실구현 레인이 낸 엔진 가운데 어느 것이 표준 구성(롱온리 ≤25종 EW · 15bps · 활성 측정 축 `all_hyg_px1000_2000_v1`)에서 **수익 엔진 자격**을 갖는가 — 엔진마다 라운드를 열지 않고, 한 번 등록한 규칙으로.
- **규칙(P1R01 승계)**: 보는 창 β-통제 t(α) ≥ `tier_graduation.grade_b_min_portfolio_alpha_t`(2.0) ∧ 보는 창 상승 포착 ≥ 0.55. 위기별 하락노출(시장 대비) · 시험 창 α 는 **보고 전용**(판정 아님).
- **기대 방향**: 레인 엔진 대다수는 미달(수익 엔진은 드물다 — P1R01 3종 중 2 · 1계층 1차 라운드). 시드 E2 · E3 은 활성 epoch 에서도 자격 유지 예상(같은 사양의 보는 창 결과를 본 상태 — 7절 노출).
- 판정은 엔진마다 독립이고 **선택이 없다**(자격 목록 = P4 수익 엔진 후보 · P4 에서 고를 때 시행 수로 센다).

## 2. 왜 지금 · 무엇과 다른가
- **병목 = 처리량**: 라운드 1.4개/일 · 레인 1편씩 · 엔진이 P1 라운드를 기다린다(계획서 '속도를 정하는 세 시계'). 상설 판은 엔진 1개 = 라운드 1개의 의식(설계 → 교차 점검 → 등록 → 커밋)을 판 1번으로 줄인다.
- **R2 는 그대로**: 규칙 · 입구 규칙 · 생성 함수 핀은 등록본에 고정되고, 항목 칸 사양은 등록된 생성 함수가 재량 없이 만든다(측정 · 판정 직전 다시 만들어 md5 대조). 규칙이 바뀌면 새 판(P1S02 …)을 등록한다 — 옛 판정은 남는다.
- **P1R01 과 다른 점**: P1R01 = 고정 3칸(P0R01 공유 측정 · 구 epoch `all_hyg_2000_v1` · NA → 미달로 접는 코드). P1S01 = 같은 규칙을 판으로 등록 · 칸은 레인 인계마다 생성 · **활성 epoch** · 미측정은 **미시험**(코어 기본값 — 재측정 대상이지 엔진 실패가 아니다. P1R01 3칸은 모두 측정돼 결과 차이 없음).
- 같은 epoch 비교 원칙: P1R01 의 E2 · E3 자격은 구 epoch 판정이다. P4 가 활성 epoch 수치로 조립하려면 같은 epoch 자격이 필요하다 → 시드 재측정(3절).

## 3. 후보 → 선정 → 제외
### 3-1. 시드(등록본 고정 칸 · reference · 시행 수 무가산 · 2계층 풀 미등재)
| 시드 | 사양 | 근거 |
|---|---|---|
| `P1S01_E2_C0` | 생성 함수 `rc_p1_cell_spec`(RP_AUTO_2002_06975 엔진) — 활성 축 출력 = P2R04 E2 RX0 사양(시험 I1) | P1R01 자격 엔진 · 같은 epoch 재판정 |
| `P1S01_E3_RX0` | P0R01_E3_C0 사양 그대로 + 측정 축만 활성(= P2R04 E3 RX0 · 시험 I2) | P1R01 자격 엔진(B6_36 계보 최고 칸) · 같은 epoch 재판정 |

- **결정(설계)**: E2 · E3 을 **다시 잰다**. 이유 — ① 등급 · 자격 비교는 같은 epoch 안에서만(CLAUDE.md 축 표) ② 기저 신호 캐시가 같은 엔진 md5 · 같은 데이터 판본이면 공유돼 E3 몫은 증분 비용 ③ 같은 사양이 P2R03 · P2R04 RX0 로 활성 축에서 이미 여러 번 측정됐다(측정 위험 낮음). 등록 **뒤** 새로 잰다(R2) — 이미 본 RX0 측정을 빌려 쓰지 않는다.
- **E3 은 엔진 단독이 아니다**: 2002.06975 엔진 + DB 팩터 3종(as-of IC 정렬) · entropy 비중 · 순위 버퍼(B6_36). 입구 규칙(3-2)의 대상이 아니라 P1R01 승계 기준선이다 — P4 후보로 쓸 때 '방향 층 = 정본 커넥터 as-of 정렬 포함'을 함께 본다.
- **E1 제외**: 엔진 파일이 없는 내장 모멘텀(문헌 기준선) · 구 epoch t(α) −2.07 미달 · P4 후보 아님.
- 회계: 시드 n_family = 계보 2002.06975 앞선 사전등록 최댓값 260(P2R04) 그대로 — 무가산. `standing-check` 가 등록 직전 지금 최댓값과 다르면 경고한다(P2R05 가 먼저 등록되면 시드 사양을 다시 만든다).
  - **11-11 재핀**: P2R05 가 11-06 먼저 등록돼(사전등록 md5 11-06 9ed7b23f → 11-08 환경 재핀 2회 뒤 지금 정본 bf45f4e7 · 계보 회계 264 는 불변) `standing-check` 가 경고했다 → 등록된 생성 함수(`rc_p1_cell_spec` · `rc_standing_seed_respec`)로 시드 사양을 다시 만들어 **회계 두 필드만**(`n_family_at_registration` 260 → 264 · `n_trials_basis` 문장) 바꿨다. 회계 밖 필드는 바이트 동일(대조 스크립트로 단정). 시드는 여전히 무가산(reference).

### 3-2. 레인 산출 → 자격 큐 입구(스캔 규칙 · 기계 판정 · 성과 수치를 읽지 않는다)
- 원천 = `04_Research/strategies/RP_AUTO_*` × 등록부 인계 기록(검증기 `.v1001_handoff` 가 쓰는 kind = engine 항목 — 재료 큐 · 소비 기록 · 미분류 보류) × `FIDELITY.json` · `fidelity_audit.json` · `lane_provenance.json` · 레인 측정 보유(`04_holdings.csv`).
- 한 디렉터리의 **모든** 실패 사유를 모은다(사유 코드 전문 = `standing_rules.md` 3절). 통과 + 처음 보는 엔진(md5)만 인계 시각 순으로 넣는다.

| 사유 | 왜 제외하나(기전) |
|---|---|
| `implementation_suspect` · `audit_not_passed` | 1801.01777 사례 — 1차 A 는 미신고 동적 부호 층(감사 misdeclared)에서 나왔고 재구현은 F · A 원천 미분리. 감사가 받지 않은 구현의 자격은 논문 엔진의 자격이 아니다. 꼬리표를 못 읽어도 제외(실패 = 닫힘) |
| `dynamic_sign`(방향 층) | 신호 방향을 데이터가 시점마다 다시 정하는 층 — 자격 t(α) 가 엔진 기전이 아니라 부호 타이밍에서 나올 수 있다(1801). 판정 = R 파서 토큰(주석 · 문자열 제외): 정본 커넥터 `load_month_factors`/`load_daily_factors`(as-of IC 3단 부호) → `factor_db_asof` · `align_factor_direction`/`compute_rolling_ic_all` 호출 또는 부호 층 식별자 → `orientation_layer`. **기본 = engine_native 만**(9절 결정 대기 1) |
| `long_leg_absent`(순방향 층) | 보는 창 신호일 중 롱 레그(비중 > 0)가 없는 날 = 시계열 방향 · 현금 타이밍. 표준 구성(상위 25 · 롱온리)은 그날 엔진이 숏하려는 종목을 사거나(가중치 = 점수) 비게 된다 — 롱온리로 쓸 수 없는 신호다. 실례: 2411.13555 보는 창 394/1124일 |
| `combination` | 단일 논문 엔진이 아니다 — 결합은 P4 · 결합 규칙(SKILL §2-0)과 도훈 확인 |
| `not_routed` | 라우터 v5 가 P1(수익) 재료로 분류한 것만(10-14 '재료 배정 기본값 P1 폐지') |
| `no_handoff` | v10.01 인계(10-14~) 전 엔진 — 구 측정 축 · 감사 · 꼬리표 미기록. 소급 여부 = 9절 결정 대기 2 |
| `engine_changed_since_handoff` | 인계(감사 · 측정) 뒤 엔진이 바뀌면 감사가 덮지 않는다. 인계 engine_md5 가 있으면 md5 로, 없으면 파일 시각 > 인계 시각(9절 결정 대기 3 — 인계에 md5 싣기) |
| `pit_static` · `engine_parse_failed` · `output_contract_unknown` · `paper_meta_missing` · `no_engine` · `long_leg_unverifiable` | 측정 · 판정 전제 결손 — 실패 = 닫힘 |

- **성과 무관**: 입구 표에는 등급 · PORT_t · CR 열이 없고, 인계 등급 · PORT_t · CR 을 바꿔도 입구 판정이 같다(시험 B6 · B7 음성 대조). 기저 미달(F)도 재료다(10-14) — 표준 구성의 롱 레그 성과는 충실구현 롱숏 성과와 다르다.
- **미리보기(10-20 · main 읽기 전용 · 쓰기 없음)**: 46 디렉터리 · 입구 통과 **1**(RP_AUTO_CLEAN_1908_01112 · Mnemonic DL · adapted · engine_native · 롱 레그 0/95). 제외 사유(중복 계수): no_handoff 37 · dynamic_sign 9 · not_routed 6 · combination 4 · audit_not_passed 2 · implementation_suspect 2 · long_leg_absent 1(2411.13555) · no_engine 1. 대안 정책(C13 as-of 정렬 허용)이어도 지금 통과는 같은 1건 — 정책 선택의 실익은 앞으로 들어올 엔진에 있다.
- **입구 수리(11-10 · 코드 `v1/standing.R` · 커밋 `838f7147a` · 설계 README §5-4 ④ — 정적 코드 감사에서 나왔다 · 성과 무관)**:
  - 방향 층을 호출마다 `direction` 인자로 가른다. 등록부 방향 문자열 상수(`"registry"` | `"defensive"`)로만 커넥터 · 결합용 뷰(`fc_load_month(s)` · `fc_daily`)를 부르는 엔진 = `factor_db_static` — **engine_native 를 허용하면 함께 허용**한다. 인자 없음 · `"ic_asof"` · 판정 불가 값 = `factor_db_asof`(종전처럼 `dynamic_sign`).
  - 왜: 등록부 방향은 측정 전에 선언된 고정 기대수익 방향이다(C13 · `factor_db/DIRECTION_POLICY.md`) — 데이터가 시점마다 부호를 다시 정하는 층이 아니다. 10-20 판 정적 판정은 이 경우도 '부호가 움직인다'로 뺐고(§9-1 이 예고한 '고정 방향 재표현' 사례), 결합용 뷰 호출은 검사 목록에 없어 통과했다(양쪽 결함). 1801 교훈(부호 타이밍이 t(α) 를 만든다)이 겨누는 층 가운데 **직접 호출 · `$` · `::` 형태**의 부호 층(`align_factor_direction` · `compute_rolling_ic_all` · 부호 층 식별자)은 여전히 제외된다.
  - 한계(11-11 격리 교차 점검 v1 권고 R-2): 부호 층 함수를 간접으로 쓰는 형태(함수 값 `lapply(…, align_factor_direction)` · `do.call('align_factor_direction', …)` · `match.fun(…)` · 별칭 대입)는 정적 판정이 놓친다(탐침 4/4 통과). 지금 레인 엔진 가운데 두 함수를 쓰는 것은 1603.00751 · 1801.01777 둘이고 둘 다 직접 호출이라 잡힌다(현재 영향 0). 간접 형태는 충실도 감사(`audit_not_passed` · 미신고 동적 부호 = misdeclared)가 받치고, 코어 판정 수리(두 이름을 커넥터처럼 모든 기호 토큰 · 문자열 호출까지)는 판 2 · 코어 v2 몫이다.
  - 팩터 DB 수리 전 레인 측정(`contracts/factor_db_vintage.R::fdv_stale`)은 입구에서 빼지 않고 열 `factor_db_vintage = stale` 표식만 남긴다 — 상설 측정이 지금의 팩터 DB 위에서 새로 잰다. 낡은 측정의 소비는 A 자격 관문 · P4 기저 풀이 막는다.
  - 규칙 문서 `standing_rules.md` 는 11-11 `standing-check` 가 이 코드에서 다시 생성했다(손으로 고치지 않음).
- **미리보기(11-11 13:27 · 등록 전 dry-run · 쓰기 없음 · 사유 코드만)**: 51 디렉터리 · 입구 통과 **1**(RP_AUTO_CLEAN_1908_01112 · engine_native · `factor_db_vintage = stale` 표식). 제외 사유(중복 계수): no_handoff 40 · dynamic_sign 11 · not_routed 7 · audit_not_passed 4 · combination 4 · implementation_suspect 4 · no_engine 4 · long_leg_absent 1. 인계 기록이 있는 11편 중 `dynamic_sign` 은 `factor_db_asof`(2202.10721 · 2412.12350 · 2601.10732) 또는 `orientation_layer`(1603.00751 · 1801.01777). 미리보기 뒤 입구 규칙은 바꾸지 않았다.

## 4. 처치 = 표준 구성(생성 함수 핀)
- `rc_p1_cell_spec` — P0R01 C0 선례를 복사하고 엔진 · 논문 · 시행 회계 · 측정 축만 바꾼다. 고정 축(종목 수 · 비용 · 유동성 · 롱온리)은 정본과 대조(다르면 멈춤).
- 등록 핀 = 함수 본문 md5(`80f8311f…`) · 선례 md5(`080cfea8…`) · 정본 고정 축(측정 축 `all_hyg_px1000_2000_v1` · 25 · 15bps · 2억 · 롱온리). 하나라도 바뀌면 넣기 · 측정 · 판정을 멈춘다(새 판 등록).
- 항목 칸 사양은 원장에 넣을 때의 입력(엔진 · 논문 · 계보 · n_family · 근거 문장)으로 언제든 다시 만들 수 있다 — 측정 · 판정 직전 다시 만들어 md5 를 대조한다(손으로 만든 사양은 md5 가 맞아도 거부 — 시험 D6).

## 5. 판정 규칙(`round.sh <dir> check` 출력 그대로)
- 수익 엔진 자격 = [보는 창 β-통제 t(α): t_alpha_vis >= 2 (02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t · 미측정 = 미시험) ∧ 보는 창 상승 포착: uc_vis >= 0.55 (근거: 투자철학 헌장 — 강세 참여 ≥ 55%(P1R01 rules.qualify.uc_floor 승계) · 미측정 = 미시험)] 모두 (미측정 = 미시험)
- 시험 창 유지(사람 쪽 보고)(보고 전용 — 판정 아님): 'qualify' 참인 칸만 alpha_ann_test > 0 (근거: P1R01 rules.test_window 승계 — 자격 엔진만 · 판정 아님)
- 보고 열(판정 아님 · 보는 창): 위기 하락노출 중앙 · 최악 · 위기 수(`dd_capture_*_vis` · 칸 평가 기록) — 위기별 값은 `results/<code>/visible/diagnosis_packet.md`.
- `[check] P1S01_standing_qualification · 칸 2 · 핀 파일 22 · 코어 v1/563cdfc3` · `[draft] v1 통과`(10-20 worktree 미리보기 — 코어 매니페스트는 WP1-b 모듈 · v1 출시로 바뀌므로 등록은 main 에서 draft 를 다시 만든다).

## 6. 예산 · 시행 회계
- 칸 = 시드 2 + 레인 인계마다 1(규칙상 상한 없음 · `scan --max N` 은 운영 상한).
- family_root = paper_key · n_family = max(계보 앞선 사전등록 · 상설 원장 회계 최댓값, 레인 측정 수(대표 + 변형 — REPLICATION-ALL-METHODS)) + 1. 같은 논문의 재구현 엔진은 앞선 상설 항목 위에 +1(시험 H3).
- 측정 = 엔진 신호 1회(기저 캐시: 같은 엔진 md5 · 같은 데이터 판본이면 재사용) + 표준 구성. ~~DNN 엔진은 GPU 임대 규칙(WP3) 아래서.~~ → 11-11 정정(격리 교차 점검 S-2 · 판단 T1 note C-20261111-004): 상설 측정 경로(standing.R · round.sh · standing_board_run.sh · rf_cell_worker.R)는 GPU 임대를 잡지 않는다 — torch 엔진(2002.06975 DNN)은 CUDA 가 있으면 레인(gpu1)과 같은 GPU 를 함께 쓴다(RTX 4080 SUPER 16 GB · 11-11 13:4x 레인 THGNN 약 4.2 GB 사용 · 속도만 나눈다 · RAM 여유 약 11.8 GB = 셀 워커 1개 정점 약 7.5 GB). 임대를 붙이는 것은 판 2 · 코어 v2 몫.

## 7. 노출(τ_D) — 사양 `exposures` 와 같다
- Q 는 시험 창(2023~) 성과를 본 상태다 — 판정 규칙은 보는 창 열만(코어 검사) · 시험 창 α 는 보고 전용.
- Q 는 시드와 같은 사양(E2 · E3 × 활성 epoch — P2R03 · P2R04 RX0)의 보는 창 결과를 본 상태다 — 규칙 · 문턱은 P1R01 승계 고정(재량 없음).
- 레인 산출(재료 큐 인계 · 감사 판정)을 본 상태다 — 입구 규칙은 성과 수치를 읽지 않는다.
- 방향 층 정책은 엔진 코드의 정적 특성으로만 정했다 — 성과와 무관.
- 원장 · `results/standing_visible.json` = 보는 창 값만(Superfan · 처방 레인 열람 가능). 사람 쪽 판정 파일 `results/standing/<code>.verdict.json` 은 시험 창 열 포함(처방 · 리뷰 레인 열람 금지).

## 8. 결론 범위 · 남길 것
- 자격 목록 = P4 수익 엔진 후보(활성 epoch · 같은 epoch 비교만). 자격 ≠ 권위 등급 · Judge · BOOK(측정이 A 면 러너 §11 A 자격 관문이 Judge 트리거를 따로 낸다 — 기존 경로).
- 미달 = 표준 구성에서 이 규칙 미달 — 논문 기전 전체의 기각이 아니다. 입구 제외 = 판정 아님(새 판에서 다시 볼 수 있다).
- 원장(추가 전용 · md5 사슬)이 판정 단일 출처다. 보고 = 통과 엔진마다 push 1통 · 미달 · 미시험 = 일 요약 1통(무음). Superfan = 등록 때 T1 · P1 1회 · 통과 즉시 T2 · P2 · 미달 일 묶음(규약 §11-1 · §12).
- **11-11 등록 전 기록 — 통과 목록을 P4 가 받는 규칙(판정 전 · 판단 T1 R-20261111-001 · 철학 P1 R-20261111-002 반영)**
  - 첫 강화 사슬의 단독 기저 = **2002.06975 계보 밖** 상설 자격 엔진(새 계보 — research-program SKILL §0-1 ② · 설계 README §1-2 ① · §1-3). 시드 E2 · E3(같은 계보 두 구성 · 헌장 빈칸 17)는 엔진 결합(blend) 블록의 상대로만 쓴다. 계보 밖 자격이 0 이면 다음 일은 공급이다(레인 순서 · §9-2 인계 소급 · factor_db_asof 엔진의 등록부 방향 재검증 — 전수 · 기계 규칙으로, 미리보기 이름으로 고르지 않는다).
  - 기저는 **상설 판 통과 행만**(standing_qualified = TRUE) 받는다 — 등급 경로(전 기간 권위 등급) 기저는 τ_D 문제라 쓰지 않는다(철학 C-20261111-016 · 결정 P4-BASE-POOL-GRADE-PATH-TAU-20261111).
  - 사슬 판 등록 전에 기저 풀(round_core v1/p4.R) 정정이 먼저다: ① 상설 행을 칸(code) 단위로 · 처치가 든 칸(E3 꼴)은 맨 엔진 행에 합치지 않는다(T1 C-20261111-001) ② 등급 경로의 형태(결정 대기). 출시된 v1 을 다시 열지 않고 코어 v2(판 라우팅 포함 · T1 C-20261111-002 대안 (a)) 또는 v1 정정 + 이 판의 새 판(P1S02)으로 — 어느 쪽이든 이 판의 이미 판정한 항목은 원장에 남는다.
  - 사슬 1호 채택 규칙에는 집중(N4 `worst_name_contrib_deep_vis`)을 필수로 싣고, 기저의 진단 패킷 판독(집중 · 현금 날 · MC8 귀속 · 하락/상승 β · 강세 구간별 참여 · CDaR)을 사슬 판 철학 P1 의 입력으로 준다(철학 C-20261111-013 · 014 의 판 2 이전 완화).

## 9. 결정 대기(원 세션 · 필요하면 도훈)
1. **방향 층 정책**: 기본 = `engine_native` 만(정본 커넥터 as-of IC 정렬 · 엔진 부호 층 제외 — 1801 교훈 · 안전한 기본값). 대안 = C13 표준 as-of 정렬(`factor_db_asof`) 허용 — 팩터 DB 를 쓰는 레인 엔진(현재 8개)이 들어온다. 고정 방향 재표현(1801 재구현처럼 등록부 정적 부호로 되돌림)은 지금 정적 판정으로는 `orientation_layer` 로 묶여 제외된다 — 인계에 '방향 고정' 기계 표식을 싣는 레인 변경이 대안.
2. **구판 엔진 소급**: 인계 기록 없는 37개(10-14 전)는 입구 밖. 소급하려면 라우터 v5 재분류 · 감사 재실행으로 인계 기록을 만든 뒤(레인 경로) 스캔이 받는다.
3. **인계에 engine_md5 싣기**: 검증기 `.v1001_handoff` flags 에 엔진 md5 한 줄(레인 파일 변경) — 그 전에는 파일 시각 > 인계 시각으로 본다(main 작업 트리 기준 · worktree 사본은 체크아웃 시각이라 판정 불가).
4. **스캔 주기 · 예약 작업**: 아침 체인 · 레인 틱 뒤 `round.sh <P1S01> scan` → `standing-measure` → `standing-report --send` 연결 = 예약 작업 = 도훈 권한(지금은 세션이 부른다).
   - ✅ 11-11 해소: 도훈 `CHAIN-AUTOMATION-STANDING-BOARD-AND-TICK-20261110` → 예약 작업 `Qvest_StandingBoard`(매시 37분 · 11-11 08:16 등록) = `ops/data_selfheal_tick.sh` → `ops/standing_board_run.sh --send`(scan → 대기 있음 ∧ 배리어 열림이면 standing-measure → standing-report) → `ops/chain_tick.sh`.
5. **등록부 재료 소비 표식**: 상설 판정 엔진의 P1 재료 큐 항목을 소비로 옮기는 것은 쓰기 잠금(WP3) 뒤(지금 상설 코드는 등록부를 읽기만 한다).
- 11-11 상태: 1 = 기본값 유지(engine_native + 11-10 수리의 factor_db_static · `factor_db_asof` 허용은 미결 — 바꾸면 새 판) · 2 · 3 · 5 = 미결(이번 판 범위 밖 · 막지 않는다).
6. **(11-11 새) 판 2 후보 — 코어 변경이 필요한 것**(등록 전 감독 · 점검 지적 · 판정 규칙 불변): 원장 보는 창 열 확장(유효 종목 수 · 깊은 위기 한 종목 기여 · 현금 날 · MC8 귀속 · 노출 평균 · 하락/상승 β · 강세 구간별 참여와 강세 수 · CDaR · Calmar · 팩터 방향 값 · 학습 난수 꼬리표 — 철학 C-013 · C-014) · 부호 층 간접 호출 판정(격리 R-2) · 처치 경로 · 팩터 DB 접근 파일 핀(R-3 나머지) · torch 엔진 GPU 임대(S-2) · 크기 짝 선택 알파 보고 열(철학 N3) · q_uc 문턱의 정본 참조(`behavior_card.json::uc_floor` — 철학 N4).
7. **(11-11 새) 도훈 결정 `P4-BASE-POOL-GRADE-PATH-TAU-20261111`**: 기저 풀 등급 경로(전 기간 권위 등급 B 이상)가 사슬 기저를 시험 창 정보로 고른다(철학 C-016 · pit.md C1 2026-09-23 D-E · lean-loop τ_D) — (가) 보는 창 S 띠로 · (나) 상설 통과만 · (다) 꼬리표. CLAUDE.md 파이프라인 문구('기저 풀 = 상설 통과 ∪ 등급 B 이상')와 닿는다.

## 10. 등록 순서(원 세션 — 이 에이전트는 등록하지 않는다)
- 전제: P2R05 종료 또는 WP3 쓰기 잠금 배포 · v1 출시(코어 매니페스트 고정 — 상설 판은 판정 경로 핀을 오래 쥔다) · WP2 핫패스 병합 · 재핀 뒤. 그 전에 등록하면 핀이 곧 깨져 새 판이 필요하다.
- `round.sh <dir> standing-check` → `check` → `draft` → 초안 md + `standing_rules.md` 로 철학 P1 · 판단 T1 · 격리 교차 점검 동시 → `reviewed` → `register`(조건 ①~⑧ · 사양 tests = 상설 · 흐름 시험) → 커밋 → `scan`(시드 + 입구 통과 엔진) → `standing-measure` → `standing-report --send`.
- **11-11 전제 상태**(v10.2 사다리 루프 원칙 5 '막지 않는다' — 설계 README §2-1 · §6 'Q 가 진행하는 것'): P2R05 = 등록본 보존 · 뒤로(측정 시작 때 재핀 · 사전등록 내용 불변) · WP3 쓰기 잠금 = 10-20 배포 · 코어 v1 = 11-11 출시 기록(`_lib/round_core/RELEASES.json` · 매니페스트 e70ac0af) · WP2 측정 서버 = 미연결(상설 측정은 정본 셀 워커를 직접 부른다 — round_core README '다음' 절: 서버가 생기면 상설 측정도 그쪽을 먼저 쓴다) · 재핀 = §12. 등록은 이 세션(v10.2 순서 1)이 하고, 측정은 매시 틱이 잇는다(손으로 겹쳐 돌리지 않는다 — 틱 자체 잠금).

## 11. 근거 문헌
- P1R01 사전등록(`stage_artifacts/programs/P1_RETURN/P1R01_engine_qualification/prereg.json` · md5 5d577e5d) — 규칙 · 문턱 원천.
- β-통제 알파 t(Newey & West 1987, *Econometrica* 55(3) — NW lag 3) = `contracts/beta_controlled_alpha.R` · 문턱 2.0 = 정본 `tier_graduation.grade_b_min_portfolio_alpha_t`(다중검정 맥락 — Harvey, Liu & Zhu 2016, *RFS* 29(1)).
- 상승 포착 0.55 = 투자철학 헌장(`00_Lawbook/specs/investment_philosophy_charter.md` · 도훈 10-13).
- 위기 정의(보고 전용 하락노출) = Lunde & Timmermann (2004), *JBES* 22(3) 20/20 — 행동 카드(`contracts/behavior_card.R`).

## 12. 11-11 등록 전 재핀 기록(규칙의 뜻 불변 · 결과 열람 없음)
| 항목 | 10-20 판 | 11-11 등록 판 | 왜 · 성격 |
|---|---|---|---|
| 시드 회계 `n_family_at_registration` | 260(P2R04) | 264(P2R05 · 11-06 등록) | 규칙(§3-1 · '계보 앞선 사전등록 최댓값 그대로 · 무가산')의 기계 적용 — `standing-check` 경고 · 등록된 생성 함수로 재생성 · 회계 밖 필드 바이트 동일 |
| 입구 방향 층 | engine_native 만 · 등록부 방향 호출도 `dynamic_sign` · 결합용 뷰 미검사 | engine_native + factor_db_static(등록부 방향 상수) · 결합용 뷰 검사 · 낡은 판 = 표식만 | 11-10 코드 수리(§3-2 · 커밋 `838f7147a` · 정적 감사) — 등록 전 반영 · 철학 P1 · 격리 점검에 보인다 |
| 규칙 문서 `standing_rules.md` | 10-20 생성 | 11-11 `standing-check` 재생성 | 위 수리의 문장 반영(사양에서 생성) |
| 생성 함수 핀 · 정본 고정 축 | fn 80f8311f · 선례 080cfea8 · all_hyg_px1000_2000_v1 · 25 · 15bps · 2억 · 롱온리 | 같음(`standing-check` 일치) | 재핀 없음 |
| 행동 카드 설정 사본 | md5 6a2a1d21 | 같음(정본 `06_Registry/behavior_card.json` 과 md5 동일) | 재핀 없음 |
| 판정 규칙 · 문턱 | t(α) ≥ 2.0 · uc ≥ 0.55 · 시험 창 α = 보고 전용 | 같음 | 불변 |
| 노출 고지 | 4줄 | + 2줄(11-10 전수점검 등급 분포 열람 · 입구 수리와 11-11 미리보기) | 공개 — 규칙 불변 |
| 판정 경로 핀(코어 · 계약 · 설정 파일) | 10-20 worktree 미리보기 | 11-11 `draft` 가 다시 계산(코어 v1 매니페스트 e70ac0af · 등급 v3.4 · 팩터 DB 판 표식 반영 판) | 측정 시작 때의 운영 판 — 등록 뒤 바뀌면 그 판은 멈춘다(새 판) |
| 초안 v1 → v2 | v1(13:33 · 029bcae4) | v2 — 13:48 다른 세션 커밋 `e66d9f0aa`(run_paper_replication.R · L-code 다음 탐침 문구 두 줄 · 측정 무영향)로 v1 핀 1건이 어긋남(격리 점검 F-1) | 재핀(규칙 불변) |
| 핀 범위 `pins.files` | 기본 18 + 엔진 + 칸 사양 2 + 행동 카드 사본 = 22 | + 4(rf_base_cache.R · replication_harness.R · backtest_result_contract.R · validation/lookahead_detector.R) = 26 | 격리 점검 R-3 일부 — 모든 상설 항목 측정 · 입구 pit_static 이 거친다. 제외 = 시드 E3 처치 경로(factor_db_connector.R · weight_catalog.R · rf_rebalance.R)와 결합용 뷰(factor_combinable.R): 7일 변경 1~4회라 판 전체 정지(R-1)가 잦아진다 · E3 는 등록 직후 첫 측정 틱에서 재므로 등록 ~ E3 측정 사이 이 파일들의 git 변경 유무를 첫 판정 때 기록한다 |
| 방향 층 허용 표기 | `orientation_admit: [engine_native]`(코드가 factor_db_static 으로 넓혀 읽음) | `[engine_native, factor_db_static]` 명시 | 실효 집합 불변(미리보기 51 · 통과 1 그대로) — 등록 문서만 읽어도 받는 범위가 읽히게(철학 N1 · T1 N2) |
| 결론 범위 · 노출 | 4줄 · 6줄 | 10줄 · 8줄 | 감독 지적 반영(사양 `changes_after_superfan` · `changes_after_review`) — 판정 규칙 불변 |
