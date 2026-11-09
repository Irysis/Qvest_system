# 재무 v2 재측정 — 등급 v3.3 A 3칸 (2026-11-10)

## 왜
- 등급 v3.3 재채점(11-10 · `l1_prescription_redesign_20261013/s0_grade_v3/v33_backfill_20261110/`)에서 현 측정 축 B → A 3칸이 나왔다:
  P2R03_E3_RX0 · P2R03_E3_L2 · P2R04_E3_RX0(팩터 조정 알파 노치 · 네 모형 알파 최소 t 4.46~4.47 FF6).
- 세 칸은 재무 v1(결함 — 2015~ 총부채 0 행 · ≤2014 순이익 낡음) 위에서 잰 값이다. decision_register
  FUND-V2-PRIOR-GRADES-REMEASURE-ON-CITE-20261109 ③ = 풀 · BOOK · 라운드 재료 · 인용 전에 v2 팩터 DB 로 다시 잰 값만 쓴다.
- 도훈 11-10 '지금 재측정'.

## 사전 점검(측정 전 · 결정론)
| 항목 | 결과 |
|---|---|
| 사양 md5 = 사전등록 | P2R03_E3_RX0 712f200c4d14 · P2R03_E3_L2 bff0b57ec721 · P2R04_E3_RX0 c3d30464fb2c — 셋 다 일치 |
| 코드 변경(10-18 측정 이후) | 기저 엔진(RP_AUTO_2002_06975/engine.R · md5 6b6a8e1a144b) · 셀 엔진 · 셀 작업자 = 변경 없음 · 러너 · 하네스 = 11-09 6c990e7f9 롱숏 결합 선택지(기본 daily = 구판 비트 동일 · 이 셀들은 롱온리) |
| 재무 입력 | `.cache/fundamental_merged.parquet` = 11-09 11:40 전환 때 v2 로 다시 씀(fundamental_source.json active = v2) — 기저 엔진이 직접 읽는다 |
| 캐시 | 기저 신호 캐시 키 = 엔진 md5 · RAWDATA · 벤치 · 팩터 DB build_hash · 재무 병합 · 분기 · ECOS · 수급 · 컨센서스 도장 → 미스(재학습). DNN 월별 캐시 키 = 학습 행렬 · 표적 · 예측 입력 · 종목 바이트 해시 → 특성이 바뀐 달은 재학습(v1 예측 재사용 불가) |
| 환경 | R 4.6.2(정본 경로 직접) · venv Python 3.15.2 · torch 2.15.0+cu132 · RTX 4080 SUPER 16 GB · 갱신 배리어 free · 여유 RAM 15.9 GB |

## 절차(`run.sh`)
라운드 `measure.sh` 의 칸 측정과 같은 순서 — 배리어 대기 → 시작 지문(`fingerprint.sh` equality · record) → 정본 셀 작업자
`02_Infrastructure/ops/rf_cell_worker.R <spec> 1 <code> <result.json>` → 끝 지문. 순서 = P2R03_E3_RX0(DNN 재학습) → P2R03_E3_L2 → P2R04_E3_RX0(같은 기저 · 캐시 적중 예상).

원 라운드와 다른 점(측정 사양 · 계약은 같다):
1. 결과 = 이 폴더 `results/`(닫힌 라운드의 results · 판정 기록 보존 · 새 측정 폴더 = `stage_artifacts/replication/<새 run_id>`).
2. 카탈로그 · 팩터 등재 없음(`QVEST_RP_REGISTER=0` — 세 칸 모두).
3. DNN 작업자 4(`PYTHON_CPU_COUNT=5` → min(8, 5 − 1)) — 메인 PC 32 GB 에서 작업자 8 은 추산 25~33 GB(project-main-pc-ram-benchmark). 달마다 독립 학습 · 시드 · 내용 주소 캐시라 작업자 수는 결과와 무관.
4. GPU 할당기 = `PYTORCH_CUDA_ALLOC_CONF=roundup_power2_divisions:2`(10-18 measure_now_vram.sh 와 같다).

## 경과 · 상태(11-10 08:00 — 중지 · 결과 없음)
| 시각 | 일 |
|---|---|
| 06:45 | 1차(`run.sh`) 시작 · P2R03_E3_RX0 기저 캐시 미스 → DNN 262개월 재학습(작업자 4 · GPU · 첫 달부터 재학습 = v2 입력 반영 확인) |
| 07:14 | 아침 체인(morning_run → ensure_data_current.sh) 자가 복구 리프레시가 갱신 배리어를 잡음 · 07:17:44 벤치마크 · 지수 11-09 로 다시 씀 |
| 07:28 | P2R03_E3_RX0 rc 1 — DNN 작업자 `ArrayMemoryError`(117 MiB) · 리프레시의 퀀티 Excel 단계와 겹쳐 커밋 한도 · 데이터 지문 다름(벤치마크) · DNN 31개월은 내용 주소 캐시에 남음 |
| 07:55 | 도훈 지시 **"DNN은 스탑해"** — 원 세션이 1차(둘째 칸 배리어 대기 중)를 멈춤. 함께 받은 지시 = "팩터 DB의 총부채(TotalDebt) 수리해 0으로 나와" → 지금 팩터 DB 위에서 잰 값은 인용 불가 |
| 07:57 | 이 세션이 중지 소식을 받기 전 2차(`run2.sh` · 재개형 · 배리어 12시간 · 작업자 3 · 신호 기록)를 띄움 |
| 07:58 | 중지 전달을 받고 2차를 멈춤(첫 칸 배리어 대기 중 · DNN 시작 전) · 감시 잔여(tail 3) 정리 |

- 세 칸 모두 **재측정 결과 없음**. 1차 실패 파일 = `results/attempt1/`(ok = false · DNN 러너 rc 1 · 지문 시작 ≠ 끝). 빈 측정 폴더 `stage_artifacts/replication/20261110_064537_38436`(1차가 만들고 비어 있음 · 커밋 안 함).
- **재개 조건** = 팩터 DB 총부채(TotalDebt) 0 수리 · 재계산 끝(원 세션이 알림). 재개 = `run2.sh` 를 다시 띄운다(재개형 — ok 칸 건너뜀 · 배리어 free 대기 · 작업자 3). DNN 예상 5~6시간(1차 실측: 작업자 4 로 달마다 약 5.2분 · 남은 약 231개월) → **00:03 일일 체인 · 아침 체인(07:10)과 겹치지 않게** 띄운다(07:28 실패 = 리프레시와 겹침). 끝나면 `compare.py` 로 원 측정과 대조.
- 참고(그대로 유효): 원 측정(10-18) = P2R03_E3_RX0 · P2R04_E3_RX0 S 0.777 · PORT_t 2.769 · DSR 0.531 · P2R03_E3_L2 PORT_t 2.716 · DSR **0.507**(스윕 관문 0.5 바로 위) · 세 칸 FF6 최소 t 4.46~4.47 · 시험 창 Calmar 1.47~1.60 vs 0.85 — 재측정에서 DSR 이 0.5 아래면 A 관문에서 막힌다.

## 해석에 넣을 것
- 원 측정(10-18)은 노트북(torch 2.12.1+cu126 · RTX 4080 Laptop) · 데이터 끝 2026-10-16. 이번은 메인 PC(torch 2.15.0+cu132) · 데이터 끝 2026-11-06.
  ⇒ 이번 값의 변화는 재무 v2 · 팩터 DB 재계산(XF 수리 · 방향 · 별칭) · 기간 3주 · 환경(GPU · torch)이 섞여 있다. 목적은 '인용 가능한 현행 값'이지 v2 효과 분리가 아니다.
- 선정 = 스윕(누적 시도 216 · DSR 관문) — A 는 DSR 관문도 통과해야 한다. A 자격 관문(run_paper_replication §11)이 측정 안에서 돈다 → `judge_request.eligible.json`(Judge 트리거) 또는 `held.json`.
