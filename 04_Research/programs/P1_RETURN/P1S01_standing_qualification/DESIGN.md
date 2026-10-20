# P1S01 설계 — P1 상설 자격(표준 구성 · round_core v1 상설 판 · 판 1)

> 이 문서는 **사고 기록**만 담는다. 코어가 승계하는 항목은 다시 쓰지 않는다:
> PIT C1~C15 · τ_D(판정 규칙의 시험 창 열 사용 금지 검사) · 측정 기계 · 핀 · 등록 조건 ①~⑧ · 칸 평가.
> 규칙 문장 · 표 = `round_spec.json` 선언에서 생성(`round.sh <dir> check`). 상설 판 고유 규칙(레인 스캔 · 항목 R2 · 원장 · 보고 · Superfan) = `standing_rules.md`(`round.sh <dir> standing-check` 가 사양에서 생성 — 손으로 고치지 않는다).
> 근거 결정: 도훈 10-20 `L1-SPEED-PLAN-20261020` · `L1-SPEED-LEVERS-20261020`(구조 레버 4종 중 'P1 상설 자격 등록') · 계획서 §10 · WP5.

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
- 측정 = 엔진 신호 1회(기저 캐시: 같은 엔진 md5 · 같은 데이터 판본이면 재사용) + 표준 구성. DNN 엔진은 GPU 임대 규칙(WP3) 아래서.

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

## 9. 결정 대기(원 세션 · 필요하면 도훈)
1. **방향 층 정책**: 기본 = `engine_native` 만(정본 커넥터 as-of IC 정렬 · 엔진 부호 층 제외 — 1801 교훈 · 안전한 기본값). 대안 = C13 표준 as-of 정렬(`factor_db_asof`) 허용 — 팩터 DB 를 쓰는 레인 엔진(현재 8개)이 들어온다. 고정 방향 재표현(1801 재구현처럼 등록부 정적 부호로 되돌림)은 지금 정적 판정으로는 `orientation_layer` 로 묶여 제외된다 — 인계에 '방향 고정' 기계 표식을 싣는 레인 변경이 대안.
2. **구판 엔진 소급**: 인계 기록 없는 37개(10-14 전)는 입구 밖. 소급하려면 라우터 v5 재분류 · 감사 재실행으로 인계 기록을 만든 뒤(레인 경로) 스캔이 받는다.
3. **인계에 engine_md5 싣기**: 검증기 `.v1001_handoff` flags 에 엔진 md5 한 줄(레인 파일 변경) — 그 전에는 파일 시각 > 인계 시각으로 본다(main 작업 트리 기준 · worktree 사본은 체크아웃 시각이라 판정 불가).
4. **스캔 주기 · 예약 작업**: 아침 체인 · 레인 틱 뒤 `round.sh <P1S01> scan` → `standing-measure` → `standing-report --send` 연결 = 예약 작업 = 도훈 권한(지금은 세션이 부른다).
5. **등록부 재료 소비 표식**: 상설 판정 엔진의 P1 재료 큐 항목을 소비로 옮기는 것은 쓰기 잠금(WP3) 뒤(지금 상설 코드는 등록부를 읽기만 한다).

## 10. 등록 순서(원 세션 — 이 에이전트는 등록하지 않는다)
- 전제: P2R05 종료 또는 WP3 쓰기 잠금 배포 · v1 출시(코어 매니페스트 고정 — 상설 판은 판정 경로 핀을 오래 쥔다) · WP2 핫패스 병합 · 재핀 뒤. 그 전에 등록하면 핀이 곧 깨져 새 판이 필요하다.
- `round.sh <dir> standing-check` → `check` → `draft` → 초안 md + `standing_rules.md` 로 철학 P1 · 판단 T1 · 격리 교차 점검 동시 → `reviewed` → `register`(조건 ①~⑧ · 사양 tests = 상설 · 흐름 시험) → 커밋 → `scan`(시드 + 입구 통과 엔진) → `standing-measure` → `standing-report --send`.

## 11. 근거 문헌
- P1R01 사전등록(`stage_artifacts/programs/P1_RETURN/P1R01_engine_qualification/prereg.json` · md5 5d577e5d) — 규칙 · 문턱 원천.
- β-통제 알파 t(Newey & West 1987, *Econometrica* 55(3) — NW lag 3) = `contracts/beta_controlled_alpha.R` · 문턱 2.0 = 정본 `tier_graduation.grade_b_min_portfolio_alpha_t`(다중검정 맥락 — Harvey, Liu & Zhu 2016, *RFS* 29(1)).
- 상승 포착 0.55 = 투자철학 헌장(`00_Lawbook/specs/investment_philosophy_charter.md` · 도훈 10-13).
- 위기 정의(보고 전용 하락노출) = Lunde & Timmermann (2004), *JBES* 22(3) 20/20 — 행동 카드(`contracts/behavior_card.R`).
