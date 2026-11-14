# K200 일간 위험 브리핑 — H1 본 모형 교체 배포 기록 (2026-11-14)

- 결정: 도훈 `K200-RISK-H1-REPLACE-P3-20261114` (decision_register · 11-14 15:36) — "즉시 교체 — 다음 아침 브리핑부터 H1 본 모형 · 이상 입력 점검 포함 · P3 는 비교용"
- 근거: 사전등록 `K200RISK-PREREG-v1-20261113` 판정(커밋 9799b31e8) — H1 `DR_newsvk` OOS 942일 로그 점수 +0.0663/일(t 3.98 · Holm 통과 · 관문 A·B·C 통과)
- 첫 운영 발송: **2026-11-16(월) 07:10 아침 체인**(주말은 morning_run.sh 가 브리핑을 건너뛴다) · 기준일 = 2026-11-13 종가
- 되돌리기 지점: git 태그 `pre-k200-h1-20261114`

## 1. 무엇이 바뀌었나

| 파일 | 상태 | 역할 |
|---|---|---|
| `04_Research/decision_framework/bearish_forecast_v3/03_models/h1_dr_newsvk.py` | 새 파일 | H1 모형 · 적합 — 연구 `scripts/common.py` · `31_challenger_dr.py` 코드를 그대로 옮김 |
| `.../03_models/h1_guard.py` · `h1_guard_config.json` | 새 파일 | 입력 · 출력 점검(차단 B1~B7 · 경고 W1~W6) · 문턱은 `604` 가 자료에서 계산 |
| `.../scripts/602_h1_daily_inference.py` | 새 파일 | H1 일간 추론 + 점검 → `H1_daily.parquet` · `H1_latest.json` · `H1_guard_latest.json` · `H1_guard_log.jsonl` |
| `.../scripts/603_k200_brief.py` | 새 파일 | 발송 원천 결정(H1 · P3 대체 · 보류) + 본문 · 차트 + `brief_meta.json` + `k200_brief_log.jsonl`(H1 · P3 나란히 기록) |
| `.../scripts/604_h1_guard_calibrate.py` | 새 파일 | 점검 문턱 계산(손으로 친 수치 없음) |
| `02_Infrastructure/ops/morning_steps/k200_risk_brief.sh` | 새 파일 | [6/6] 단계 정본(6a P3 601 · 6a' · 6h H1 602 · 6b 603 · 6b' 613(P3 대체 때만) · 6c 발송) · 시험 모드 `K200_BRIEF_SANDBOX` |
| `02_Infrastructure/ops/morning_briefing.sh` | **원자 교체** | [6/6] 블록(58줄)을 새 단계 호출(12줄)로 — 1~130행 동일 |
| `02_Infrastructure/ops/morning_steps/p3_brief_send.R` | **원자 교체** | `brief_meta.json` 의 사진 · 설명을 따름(없으면 구 방식) · `K200_BRIEF_ROOT` · `K200_BRIEF_DRYRUN` 시험 손잡이 |
| `.../03_models/daily_predictions/H1_fits.json` · `H1_daily.parquet` | 초기화 | 연구 적합 기록 162개로 시작 · 2026-01-26~11-12 이력 195행(운영 코드로 생성) |

P3(601 · 600 · 613 · `p1_hansen_skewt.py` 등)는 코드를 바꾸지 않았다 — 매일 산출 · `P3_daily.parquet` 기록은 전과 같다.
교체 절차: 스크래치 사본 작성 → 임시 폴더 시험(H1 · P3 대체 · 보류 세 경로 + 전체 단계) → 같은 폴더 `.swap` 파일 → `bash -n` · 범위 대조 → `mv -f`.

## 2. 아침 [6/6] 흐름

```
6a  P3 601 (비교 기록)  →  6a' P3 실현값  →  6h H1 602 --live (점검)  →  6b 603 원천 결정
      H1 통과/경고       → H1 본문 + dist.png + trend.png(60거래일 σ · V-KOSPI200 · VaR 대비 실현)
      H1 차단 · P3 정상  → "⚠️ 오늘은 P3 대체 발송" 줄 + 구 P3 브리핑 + 9분면(613)
      둘 다 불가         → "⛔ 수치 보류" + 사유
      603 자체 실패      → 구 P3 브리핑(600) 그대로(메타 없음 → 발송기 구 방식)
6c  p3_brief_send.R (정체 차단 그대로 · 사진은 brief_meta.json 목록)
```
9분면 대시보드는 H1 에서 보내지 않는다 — 축(λ)이 H1 에서는 21거래일 재추정 창 상수라 일간 국면 판독이 되지 않는다(재설계는 후속 과제).

## 3. 점검 규칙과 대조 결과

- 차단: B1 기준일 · B2 벤치 값(가격제한폭 ±30% → 로그수익 [−35.67, +26.24]%) · B3 V-KOSPI200 존재 · 범위(이전 이력 최저 × 0.5 ~ 최고 × 2) · B4 특징 · B5 적합 · **B6 물리 한계(VaR 1% ≥ 100·ln 0.7)** · **B7 V-KOSPI 급변 + 지수 정지(|Δlog VK| > 0.385 = 99.9% 분위 ∧ |r| < EWMA σ)**
- 경고: W1 σ/EWMA(λ 0.94) 역사 범위 [0.338, 2.278] 밖 · W2 σ 전일 대비 [0.295, 2.499] 밖 · W3 학습 범위 밖 입력(σ 영향 ≥ 10% 일 때만 본문 표시) · W4 V-KOSPI 전일과 같은 값 · W6 과거 실현 수익 개정
- 대조 `h1_guard_controls.json`: **38/38 기대대로**
  - 막음: 운영 P3 사고 기록 2026-07-31 · 08-03 · 08-04 · 08-06 · 08-07(σ 20.9~44.5% · VaR 1% −68~−113% → B6) · 실제 자료 오류 2019-04-10 · 04-11(V-KOSPI 12.67→30.40→12.29 → B7) · 주입 오류(V-KOSPI ×100 · 결측 · ×1.9 + 지수 정지 · 벤치 +40% · 기준일 불일치)
  - 통과: 평상일(2026-11-13) · 실제 급락 2024-08-01~09(08-05 KOSPI200 −9.6%) · 2026-07-27~08-10 사고 기간의 H1(σ 4.0~9.1%) · 앞뒤 평상 P3 행(07-27 · 08-12) · 실제형 충격 주입(V-KOSPI ×1.9 + 지수 −8% → σ 11.7% · W1 경고만)
- 운영 코드 = 연구 대조: 2026-01-26~11-11 194일 σ 최대 차이 5.8e-6 %p(연구 적합 기록의 ν · λ 반올림 왕복 차 — 최적화 허용오차 수준)
- PIT 경계: 점검 문턱은 2026-11-13 까지 자료로 고정했다(`h1_guard_config.json` inputs). 운영 사용은 그 뒤 날짜뿐이고 예측값에는 들어가지 않는다(발송 여부만 정한다). 과거 재생 대조(2019 · 2024 · 2026-07)는 검출기 시험이지 성과 측정이 아니다.

## 4. 확인 · 되돌리기

- 매일 기록: `.../03_models/daily_predictions/k200_brief_log.jsonl`(발송 원천 · H1 · P3 σ · VaR 5%) · `H1_guard_log.jsonl`(점검 결과)
- 시험 실행(발송 없음): `K200_BRIEF_SANDBOX=<폴더> K200_SENDER=<발송기 경로> bash 02_Infrastructure/ops/morning_steps/k200_risk_brief.sh` — `<폴더>/daily_predictions` 에 P3 · H1 파일 사본을 먼저 넣는다
- 되돌리기: 태그 `pre-k200-h1-20261114` 의 `morning_briefing.sh` · `p3_brief_send.R` 두 파일을 같은 절차(사본 → `bash -n` → `mv -f`)로 되돌리면 구 P3 단일 브리핑. 새 파일은 남아도 호출되지 않는다.
