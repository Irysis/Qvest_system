# round_core — 1계층 공통 판정 코어

도훈 10-20 결정 `L1-SPEED-PLAN-20261020`(1계층 리서치 속도 극대화)의 WP1 이다.

**목적**: 라운드마다 판정 코드를 복사·확장하지 않는다. 라운드는 사양(`round_spec.json`) · 사고 기록(`DESIGN.md`) · 꼭 필요한 고유 규칙(`round_ext.R`)만 쓰고, 나머지는 공통 코어와 실행기가 한다.

**배경**: P2R04 의 라운드 전용 코드는 약 570KB, P2R05 는 약 1MB 였다. 교차 점검 필수 지적 17건 가운데 11건이 같은 규칙이 여러 곳에 적혀 생긴 문구 표류였다.

## 원칙 (보증 불변)

- **보증 장치는 그대로다.** PIT · 사전등록 → 커밋 → 측정 · τ_D · β 짝 · MC8 · 격리 교차 점검 · Superfan 을 바꾸지 않는다. 판정 규칙의 내용 · 수 · 설계 재량도 현행대로다.
- **규칙은 한 번만 선언한다**(`v1/rules.R`). 같은 선언에서 사전등록 문장 · 판정 실행 · DESIGN 표를 생성한다.
  - 수치 문턱은 근거(`basis`)나 정본 참조(`value_ref`)가 없으면 거부한다.
  - 미측정(NA)은 통과로 접지 않는다.
- **수치는 R 계약 산출만 쓴다**(AX-008).
  - 계약 파일은 읽기만 한다.
  - 진행 중 라운드(P2R05)의 핀 51개 파일은 그 라운드가 끝날 때까지 수정하지 않는다.
- **판은 불변이다.** 출시된 판은 고치지 않고, 바꿀 일이 생기면 새 판(v2)을 만든다.
  - 라운드는 판과 매니페스트 md5 를 핀으로 건다(`rc_core_manifest`).
  - *v1 은 아직 개발 중이며 출시 전이다.*
- **속도 조치는 결과 동일 실증이 채택 조건이다**(`PERFORMANCE.md`). 실행 시간은 `.cache/round_core/perf/<round>.jsonl` 에 남는다.

## 사용 (P1 라운드 예)

```r
source("04_Research/programs/_lib/round_core/v1/load.R")
rc_init_p1("04_Research/programs/P1_RETURN/P1R03_<이름>", "P1R03_<이름>", engines = list(...), purpose = "...", hypothesis = "...")
```

```bash
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> check      # 규칙 문장 · 핀
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> draft      # prereg_draft.json + .md(점검자 · 감독용)
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> reviewed 1 <점검 파일> ok
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> register   # 등록 조건 ①~⑧ → 커밋
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> measure    # 배리어 · 사전 점검 · 지문 · 재측정 → 평가 자동 연쇄
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> report --next "..."   # 기본 dry-run · --send
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> close --note "<해석>" --p2 <id> --t2 <id>
```

## 모듈 (v1)

| 파일 | 내용 |
|---|---|
| `v1/load.R` | 단일 진입 |
| `v1/util.R` | 경로 · md5 · 원자적 JSON · 과반 · 안전 호출 · τ_D 가림/누출 검사 · 참조 해석 · 실행 시간 기록 |
| `v1/rules.R` | 규칙 선언(threshold · all_of · any_of · report) — 검사 · 해석 · 판정 · 문장 · 표 |
| `v1/metrics.R` | 지표 공급자(β-통제 알파 · 증분 알파 · 집중 · S) — 계약 호출 |
| `v1/spec.R` | 라운드 사양 검사 |
| `v1/p1.R` | P1 엔진 자격 판정 · 표준 구성 칸 사양(P0R01 C0 선례 · 정본 대조) · 라운드 골격 |
| `v1/pins.R` | 핀 계산 · 대조 단일 함수(코어 매니페스트 · 운영 파일 · 엔진 · 패키지 · R 판) |
| `v1/cell_eval.R` | 칸 평가(rk_eval_cell 이관) + 내용 주소 캐시 · 원자료 1회 적재 |
| `v1/register.R` | 초안 · 점검 기록(drafts.json — 점검본 사본 없음) · 등록 조건 ①~⑧ · 종료 기록 |
| `v1/driver.R` | 단계 실행(check · precheck · plan · draft · reviewed · register · evaluate · report · close) |
| `v1/measure_cell.R` · `v1/fingerprint.sh` | 칸 측정(정본 셀 워커) · 데이터 지문 |
| `round.sh` | 셸 진입 — 측정 파이프라인 · 샤딩 평가 |
| `templates/DESIGN_p1.md` | 사고 기록 템플릿(코어 승계 항목은 다시 쓰지 않는다) |

## 검증
- `08_Tests/programs/test_round_core_v1.R`: 규칙 · 사양 · P1R01 결과 동일. 원래 evaluate.R 격리 사본과 바이트 동일한지 본다.
- `08_Tests/programs/test_round_core_v1_flow.R`: 격리 흐름. 등록 거부 7종 · 등록 → 판정 → 종료 · R2 · 캐시 키 · 핀 · 표준 구성을 본다.

## 다음
- P2/P3 판정 헬퍼(위기 · β 짝 · 과반 · 사이클 · 짝 평가 골격) 이관과 P2R04 · P2R03 · P3R03 결과 동일 재판정.
- 측정 서버 `ms_submit` 연결(WP2).
- P1 상설 자격(WP5).
- v1 출시(RELEASES.json).
