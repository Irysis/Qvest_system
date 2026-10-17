# 충실구현 레인 재설계 — 모든 방법론 · 계산 시간 상한 없음 · 포트폴리오 구성 (2026-10-17)

결정: `decision_register` **REPLICATION-ALL-METHODS-20261017**(도훈 10-17 — "1. 대표칸만 / 2. 논문당 계산 시간 상한 없음 / 3. 포트폴리오 구성이 가능하다면 구현하여 성과 측정").
배경: 음수 CAGR 충실구현 5편 점검(`../negative_cagr_omission_audit_20261017/README.md`) — 넷이 논문 방법론의 시험이 아니었다(주결과 4방법 중 1칸 · Variant II 미구현 · ρ=1 한 칸 · TFT 를 닫힌 해로 · 종목별 LSTM 을 공통 1개로).
설정 정본: `06_Registry/rf_replication_variants.json`(숫자 · 문구를 코드에 박지 않는다).

## 1. 규칙

| 규칙 | 내용 | 막는 것 |
|---|---|---|
| 방법 = 변형 | 주결과(본문 성과 표 · 그림)의 방법 · 모델 · 구성법 **전부**를 엔진 하나의 변형으로. 스위치 `.RP_VARIANT` · 기본값 = 대표 | A1 칸 선택 |
| 대표 | `headline_variant` = 논문이 스스로 꼽은 방법 · 측정 **전** FIDELITY 에 고정 · 권위 등급 = 대표 등급(chain/1) | 측정 뒤 최고 고르기 |
| 나머지 변형 | 같은 계약 · `selection_type = sweep` · `n_trials = 변형 수`(DSR 대상) · 산출 `<대표>/variants/<run>/` | 선정 편향 |
| 격자 | 수치 격자(J×K · ρ · 창 길이 · 하이퍼파라미터)는 논문 대표 칸만 | — (결정 1) |
| 미명시 | 보충 후 신고(constants source=supplement) · 생략은 J1 데이터 없음 · J2 포트폴리오 무관 · J3 PIT · J4 측정 축만 | A2 이중 기준 |
| 핵심 모델 | 아키텍처 · 학습 절차 · 손실 · 재학습 · 앙상블 그대로 · 간이 대체 금지 · 딥러닝 = venv torch(CUDA · 실행 때마다 재서 프롬프트에 싣는다) | A3 계산량 · 편의 |
| 계산 시간 | 구현 에이전트 시간 상한 0(= 없음 · 구판 3000초) · 생존 실행은 나이로 회수하지 않는다(claim 당 1회 `claim_live_long` · Superfan warn) | — (결정 2) |
| 포트폴리오 없는 논문 | 레인 표준 구성 = FACTORS(예측값) + top_n_long · ew · 하네스 종목수 상한(설정이 constraint_defaults 에서 읽는다) · `construction_source = lane` · 절차 근거 Gu-Kelly-Xiu (2020) §2.4.2 | — (결정 3) |
| 측정 뒤 보유 대조(P4) | 변형별 `claims{long_short · n_names · net_exposure · weighting}` ↔ `04_holdings.csv` · 어긋나면 `implementation_suspect` 꼬리표(판정 아님) · 문턱 = 실측 실패 2건 사이 값(설정 basis) | U 신고서 밖 어긋남 |

## 2. 흐름(무인 레인)

```
구현자 프롬프트('모든 방법론' 절 · 자가 감사 = 축 정본) → 사전검사 P9(변형 · 대표 · 스위치 · 기본값 · claims) · P10(생략 코드) · P11(레인 구성)
 → 충실도 감사(측정 전 · 전 변형 코드 · '신고로 면제되지 않는 차이' = misdeclared) → 대표 측정(권위)
 → 나머지 변형 측정(sweep · 기저 캐시 시드 끔) → 변형별 행동 카드 · 보유 대조 → variants_summary.json → 보고 1통(변형별 한 줄)
```

## 3. 바뀐 파일

- 계약: `02_Infrastructure/alpha_search/run_paper_replication.R` — `engine_vars`(이름 있는 길이 1 원자값 · RAWDATA 등 덮기 거부 · `measurement_regime.engine_vars` 기록 · NULL = 구판 비트 동일).
- 검증기: `02_Infrastructure/ops/rf_replication_verify.R` — 변형 계획 · 대표 먼저 · 변형 측정 · 보유 대조 · 꼬리표 · 보고 섹션 · 요청 기록 · 폴백 후보에서 변형 판 제외.
- 레인: `02_Infrastructure/ops/rf_replication_auto.sh` — 프롬프트 절 · 칸 선택 허용 문구 삭제 · 시간 상한 설정화 · 생존 claim 처리 · `QVEST_RP_VARIANTS_CFG`(검사 격리).
- 사전검사: `02_Infrastructure/ops/rf_preaudit.py` + `06_Registry/rf_preaudit.json`(필수 키 3 · P9~P11).
- 감사: `06_Registry/rf_fidelity_axes.json`(signal · timing · portfolio · undeclared focus) · `02_Infrastructure/ops/rf_fidelity_fanout.sh`(판정 정의).
- 감시: `06_Registry/superfan_components.json`(replication_lane warn 패턴 `claim_live_long`).
- 문서: `CLAUDE.md` · `.claude/rules/lean-loop.md`(축 · 예산) · `.claude/rules/python-policy.md`(torch CUDA 재실측) · `.claude/agents/judge.md`(engine_vars 재현) · `.claude/skills/alpha-search/SKILL.md`.

## 4. 검사

| 검사 | 결과 |
|---|---|
| `08_Tests/ops/test_rf_preaudit.py` | 75/0(신규 15 — P9~P11 양성 · 음성 · 검사기 뮤테이션) |
| `08_Tests/ops/test_rf_verify_variants.R`(신규) | 31/0(계획 · 보유 대조 양성 · 경계 · 뮤테이션 · 설정 문턱 · 보고 · 배선 · engine_vars 주입 실행 · 거부) |
| `08_Tests/ops/test_replication_lane.sh` | 89/0(C4 생존 claim 유지 · C4b 설정 회수 · C4c 구판 claim · C5 시간 상한) |
| `08_Tests/ops/test_rf_clean_lane.sh` · `08_Tests/reinforcement/test_rf_fidelity_audit.R` · `08_Tests/programs/test_superfan_watch.R` | 107/0 · 67/0 · 33/0 |
| `08_Tests/contracts/test_replication_exec_golden.R` | 7/0 · SKIP 4 — 10-17 퀀티 OHLCVS 적재로 03-30~ 행이 개정돼 비트 대조 미측정(차이 첫 날 2026-07-01 ≥ 개정 가능 경계 03-30 · 경계 앞 5,217일 비트 동일 = 하네스 코드 동일 · 판별기 양성 대조 ③c) |

## 5. 하지 않은 것 · 남은 것

- P5 후반(논문 스스로 음수 성과를 보고한 규칙의 재료 제외)은 결정 3 범위 밖이라 넣지 않았다(2601.10732 형태 — 꼬리표 · 제외 여부는 도훈 결정).
- 측정 뒤 보유 대조의 weighting(ew · vw)은 실측만 병기한다(실측 실패 사례가 없어 문턱 근거가 없다).
- 재측정 4편(2411.13555 · 2507.01964 · 2604.16773 · 2412.12516 — 도훈 '6. 4번 해결 후 재측정 승인')은 이 규칙으로 처음부터 재구현한다(측정 축 `all_hyg_px1000_2000_v1`).
