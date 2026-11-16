# 비선형 재무 팩터(NLFF) — AutoML 판 (2026-11-16)

도훈 지시(11-16): "AutoML 을 써서 비선형 재무 팩터 구현해 봐." · "새 패키지 설치해도 돼."
상태: **코드 · 설정 · 스모크 완료. 전체 실행은 하지 않았다**(같은 PC 팩터 DB 전체 재빌드와 겹치지 않게). 성과 지표(IC · 수익률)는 계산하지 않았다. 측정은 나중에 시스템 표준 계약이 한다.

## 1. 질문

재무 지표 사이의 비선형 관계(상호작용 · 문턱 · 포화)를 쓰면 선형 결합으로는 안 보이는 정보가 나오는가?
이 폴더는 그 질문을 잴 **재료(월말 팩터 값)**만 만든다. 모델은 사람이 고르지 않는다. AutoML 이 모델 패밀리를 고르고, 하이퍼파라미터를 찾고, 앙상블을 짠다. 판정은 이 폴더 밖, 측정 계약의 일이다.

## 2. 표적 4개 → 팩터 4개(+ 선형 대조 4개)

| 표적 | 정의 | 과제 | 재학습 | 팩터(Raw_Value) | 방향 |
|---|---|---|---|---|---|
| earn | 1년 뒤 TTM 지배주주 순이익 변화 ÷ 현재 총자산. 단면 순위로 (−1, 1) 변환 | 회귀 | 매년 12월 · 확장 창 · 분기 표본 | `NLFF_EARN` = 예측 순위 | 클수록 좋음 |
| val | 같은 달 로그 시가총액에서 단면 평균을 뺀 값(적정가치) | 회귀 | 3개월마다 · 12개월 이동 창 · 월 표본 · 종목 5묶음 교차 적합 | `NLFF_VAL` = 추정 − 실제(저평가일수록 +) | 클수록 좋음 |
| dist | 향후 12개월 안 관리종목 지정(0→1) | 이진 | 매년 12월 · 확장 창 · 분기 표본 | `NLFF_DIST` = 지정 확률 | **작을수록 좋음** |
| ret | 향후 12개월 누적 로그 수익. 단면 순위로 (−1, 1) 변환 | 회귀 | 매년 12월 · 확장 창 · 분기 표본 | `NLFF_RET` = 예측 순위 | 클수록 좋음 |

선형 대조 `NLFF_<T>_LIN`도 같이 만든다. 회귀는 능형 회귀, 이진은 L2 로지스틱이다. 나중에 측정 계약이 비선형 증분을 잴 때 짝으로 쓴다. AutoML 결과와는 섞지 않는다.
표적 근거 문헌은 `nlff_config.json::targets.*.desc`에 있다. 앞선 에이전트 초안을 그대로 재사용했다: Chen-Cho-Dou-Lev 2022 · Bartram-Grinblatt 2018 · Geertsema-Lu 2023 · Campbell-Hilscher-Szilagyi 2008 · Gu-Kelly-Xiu 2020.

## 3. 입력

- **재무 입력 203개 + 행 결측 비율 1개**(`nlff_data.feature_spec`).
  - 분기 캐시 `Kind=derived` 223항목 가운데, 규모가 있는 수준값 26개와 중복 3개를 뺀 비율 · 성장 · 변화 · 점수 항목
  - 원화 변화량 `d_X`를 1년 전 총자산으로 나눈 `dA_X` 25개
  - 규모 원계정의 부호 보존 로그 8개
  - 연간 캐시 `AccountingBeta`
  - 가격 · 수익 입력은 없다(순수 재무).
- 출처:
  - `.cache/fundamental_quarterly.parquet`(TTM) · `.cache/fundamental_annual.parquet`. 둘 다 읽기 전용이다.
  - 정의는 `build_fundamental_caches.R::fc_derive()`를 따른다.
- 시점 스냅샷은 `fund_access.R::fa_latest`와 같은 규칙이다.
  - 결정일 t의 값 = `Factor_Date ≤ t`인 마지막 행(항목마다 따로).
  - 묵은 값 거르기: `Period_Date ≥ t − 15개월`(분기) / `24개월`(연간).
  - `Factor_Date`는 생산자가 C4 규칙(법정기한 + 45일 · 공개일 바닥)으로 계산한 값을 그대로 쓴다. 엔진 안에서 고정 시차를 쓰지 않는다.
- 측정 축: `constraint_defaults.json::measurement_axis`의 활성 epoch(`all_hyg_px1000_2000_v1`)에서 값을 읽는다. 식은 `measurement_axis.R::ma_membership`과 같다.
  - 관리 · 정지 · 불성실공시 표식이 0
  - 20일 평균 거래대금 ≥ 2e8(t−1)
  - 전날 수정 종가 ≥ 1,000원
  - 2000-01 이후
- 전처리는 모두 **월별 단면 안에서만** 한다.
  - 입력 = 같은 달 위생 멤버 사이의 순위를 (−1, 1)로 변환
  - 결측 = 0(단면 중앙 순위 · Gu-Kelly-Xiu 2020)
  - 입력 범위(결측 아닌 비율 ≥ 20%)는 재학습마다 그 학습 창 표본으로만 정한다.
  - 전 표본 통계는 쓰지 않는다.

## 4. AutoML 도구와 근거

**선택: FLAML 2.8.0**(Microsoft · PyPI 공식 배포판).

- **문제 정식화**: CASH(Combined Algorithm Selection and Hyperparameter optimization). 모델 패밀리 선택과 하이퍼파라미터 탐색을 한 문제로 푼다.
  - Thornton, Hutter, Hoos & Leyton-Brown 2013, *Auto-WEKA*, KDD — https://arxiv.org/abs/1208.3719
- **FLAML**: Wang, Wu, Weimer & Zhu 2021, *FLAML: A Fast and Lightweight AutoML Library*, MLSys — https://proceedings.mlsys.org/paper_files/paper/2021/file/1ccc3bfa05cb37b917068778f3c4523a-Paper.pdf
  - 학습기 선택: 추정 비용 대비 개선(ECI)으로 다음에 시도할 패밀리를 고른다.
  - 하이퍼파라미터: 비용 절약 탐색 CFO(Wu, Wang & Huang 2021, AAAI — https://arxiv.org/abs/2005.01571).
- **앙상블**: Caruana 탐욕 선택(복원 추출).
  - Caruana, Niculescu-Mizil, Crew & Ksikes 2004, *Ensemble Selection from Libraries of Models*, ICML — https://www.cs.cornell.edu/~caruana/ctp/ct.papers/caruana.icml04.icdm06long.pdf
  - 크기 50 = auto-sklearn 기본값(Feurer et al. 2015, NeurIPS — https://papers.nips.cc/paper/5872-efficient-and-robust-automated-machine-learning).
  - "패밀리별 최선 설정 → 가중 앙상블 → 전체 재적합" 구조는 AutoGluon(Erickson et al. 2020 — https://arxiv.org/abs/2003.06505)과 같다.

**왜 FLAML인가**

1. **기존 환경을 건드리지 않는다.** 설치 모의 해석 결과 `flaml==2.8.0` 단독 설치는 numpy만 요구했고, 이미 충족돼 있었다. 다른 패키지는 하나도 바뀌지 않았다.
   - 반대로 `flaml[automl]` 추가 의존은 `xgboost<3`을 요구해 3.4.1 → 2.1.4로 내릴 뻔했다. 그래서 추가 의존 없이 설치했다. lightgbm · xgboost · sklearn은 venv에 이미 있다.
   - AutoGluon은 torch · sklearn · pandas 판 고정 범위가 넓어 공유 venv에 위험해 고르지 않았다.
2. **검증 구간을 직접 줄 수 있다**(`X_val`/`y_val`). 시간순 검증 구간을 우리가 정하고, FLAML은 그 구간만 쓴다.
3. **시행 수로 예산을 고정할 수 있다**(`max_iter`, `time_budget = −1`). 기계 부하가 달라도 같은 탐색을 한다.

**FLAML 내장 앙상블을 쓰지 않은 이유**

FLAML의 `ensemble=True`는 sklearn `StackingRegressor`의 기본 KFold로 메타 학습기를 맞춘다. 이 방식은 시간 순서를 지키지 않는다. 그래서 끄고, `nlff_automl.py`가 시간순 검증 구간 예측으로 Caruana 선택을 직접 한다.

## 5. 설치 기록

| 패키지 | 판 | 이유 | 확인 |
|---|---|---|---|
| `FLAML` | **2.8.0**(고정) | AutoML(CASH + CFO 탐색) | `pip install --dry-run flaml` → "Would install FLAML-2.8.0" 하나뿐. 설치 전후 `pip freeze` 차이 = `FLAML==2.8.0` 한 줄. numpy 2.5.4 · pandas 3.1.1 · pyarrow 26.0.1 · torch 2.15.0+cu132 · lightgbm 4.7.0 · xgboost 3.4.1 · scikit-learn 1.9.1은 그대로 |

설치하지 않은 것:
- `flaml[automl]`: xgboost를 2.1.4로 내린다.
- catboost: 필요 없음. FLAML 기본 목록에 있지만 미설치면 빠진다.

## 6. 탐색 공간 · 예산 · 검증 지표(측정 전 고정 · `nlff_config.json::automl`)

- **패밀리**: FLAML 기본 목록(`estimator_list = "auto"`). CPU 판에서는 `lgbm · rf · xgboost · extra_tree · xgb_limitdepth · sgd`다. 사람이 고르지 않았다.
- **탐색 공간**: 각 학습기의 FLAML 기본 `search_space()` 그대로다.
  - 덧붙인 고정값은 재현성용뿐이다. 탐색 차원이 아니고 결과를 보고 고른 값도 아니다.
    - rf · extra_tree · sgd의 `random_state`
    - LightGBM의 `deterministic · force_row_wise · random_state`
  - LightGBM은 행/열 방향 다중 스레드를 실행 시간 측정으로 고르기 때문에, 고정하지 않으면 실행마다 결과가 미세하게 달라졌다.
- **시행 예산**: `max_iter = 60`.
  - 근거: Bergstra & Bengio 2012, JMLR 13 §2.1 — https://www.jmlr.org/papers/v13/bergstra12a.html — 무작위 시행 60회면 상위 5% 구간을 95% 확률로 맞힌다(1 − 0.95^60 ≈ 0.954).
  - 시간 예산은 쓰지 않는다(`time_budget = −1`).
  - 표본 키워 가며 탐색(`sample = True`)은 FLAML 기본값이다.
- **검증 지표**: FLAML 기본값(회귀 `r2` · 이진 `roc_auc`). Caruana 선택은 같은 지표를 쓴다(회귀는 같은 구간에서 r2와 순서가 같은 MSE, 이진은 AUC).
- **검증 분할**(`nlff_automl.time_split`):
  - 검증 = 재학습 창 표본월 중 시간순 마지막 20%.
  - 학습 부분 = 검증 첫 달보다 앞서고, 표적도 그 전에 실현된 표본(정화).
  - 모든 표적에 같은 규칙을 쓴다(지평 0인 val 포함).
- **최종 재적합**: 고른 설정을 재학습 창 전체(실현일 ≤ 재학습일 − 1개월)로 다시 적합한다. FLAML `retrain_full` · AutoGluon `refit_full`과 같은 뜻이다.
- **워커**: `--workers` ≤ 4(코드에서 거부). OMP · MKL · OpenBLAS · loky 스레드도 같은 수로 묶는다. GPU는 쓰지 않는다.

이 설정은 측정 전에 문헌 · 라이브러리 기본값으로 정했다. 2023년 이후 성과는 계산조차 하지 않았다(τ_D = 2022-12-31).

## 7. 재학습 일정 · PIT 논증

| 장치 | 내용 | 코드 단정 |
|---|---|---|
| 입력 as-of | 결정일 t의 값 = `Factor_Date ≤ t` 마지막 행 + 묵은 값 거르기 | `asof_dense`: 쓰인 모든 값의 `Factor_Date ≤ t` 아니면 중단 · 스모크마다 **미래 행 잘라내기 불변성 자가 시험**(원천을 `Factor_Date ≤ t`로 자른 뒤 다시 만든 입력이 비트 단위로 같아야 함 → 통과) |
| 표적 방향 | 지평 > 0 표적의 실현일 > 결정일 | `nlff_run` 표적 단정 · `build_chunk` earn 단정 |
| 걸어가는 학습 | 재학습일 R의 학습 표본 = 표적 실현일 ≤ R − 1개월(엠바고) ∧ 결정일 ≤ R − 1개월. 그 모델이 R ~ 다음 재학습 전까지의 달을 예측 | `time_split`: 학습 표본 실현일 ≤ R − 1개월. 예측 전 `max(실현일) ≤ cut < 예측 첫 달` |
| AutoML 검증 | 재학습 창 안 시간순 마지막 20%. 학습 부분은 실현일 < 검증 첫 달(정화) | `time_split`: 학습 Date < 검증 Date · 학습 실현일 < 검증 첫 달. **양성 대조**: 엠바고 위반을 주입하면 단정이 발화함을 확인함 |
| 표적 순위 | earn · ret 순위는 **재학습마다 그때 실현된 표본끼리만** 매긴다(아직 실현 안 된 동료 값이 순위에 섞이지 않게) | `nlff_run` 재학습 루프의 `rank_reg` 절 |
| 단면 전처리 | 순위 · 결측 0 · 평균 차감은 같은 달 단면 안. 입력 범위 판정은 그 재학습의 학습 창 표본만 | 전 표본 통계 없음 |
| 유니버스 | 유동성 · 종가는 t−1, 표식은 그날(측정 계약과 같은 식) | 묶음 계산 = 통째 계산 동일성 확인(2009~2012 · 40,144행 일치) |
| val 자기 기억 | 종목 5묶음 교차 적합. 자기 묶음은 빼고 학습한 모델로 예측 | `ticker_fold` |

재학습 일정:
- earn · dist · ret: 매년 12월 말에 재학습하고, 1~12월(그 12월 포함)을 예측한다. 확장 창, 분기 표본(3 · 6 · 9 · 12월). 표본월 12개(3년) 미만이면 팩터를 내지 않는다.
- val: 3 · 6 · 9 · 12월 말에 재학습한다. 12개월 이동 창, 월 표본, 하한 6개월.

알려진 PIT 경계(기록):
- 동전주 바닥은 수정 종가 기준이다. 측정 축 전체의 경계와 같다(constraint_defaults `price_floor._source`).
- 묵은 값 경계의 달 뺄셈 방식이 R `seq`와 다르다. pandas는 달 끝을 잘라 맞추고, R은 다음 달로 넘긴다. 기간 말은 분기 말이라 실제 차이는 거의 없지만, 비트 단위 일치는 검증하지 않았다.

## 8. 산출 팩터 형식

- **팩터 파일**: `.cache/nl_fundamental_factors/NLFF_<T>[_LIN].parquet`
  - 열: `Date`(월말 거래일, datetime64[s]) · `Ticker` · `Factor_Name` · `Raw_Value`
  - 위생 멤버 행만 들어간다.
  - 스모크는 `.cache/nl_fundamental_factors/smoke/`에 쓴다.
- **실행 기록**: `<태그>_log.json`
  - 재학습마다 FLAML 시행 수, 패밀리별 최선 검증 손실, 고른 모델, 앙상블 가중, 고른 설정, 학습 · 검증 표본 수, 시간, 최대 메모리
  - 검증 손실은 τ_D 이전 학습 창 안의 값이다.
- **방향**: 값은 원시 점수다. 순위 정렬 · 부호 정리는 소비 쪽 정본 접근자의 `direction`으로 한다(C13). DIST는 작을수록 좋다.

## 9. 실행법

```
cd 04_Research/01_reports/nonlinear_fundamental_factors_20261116
../../../.venv_qvest_ml/Scripts/python.exe nlff_run.py --smoke                     # 2012-01~03 · 이력 2009~ · 시행 8
../../../.venv_qvest_ml/Scripts/python.exe nlff_run.py --start 2000-01 --end 2026-10 --workers 4 --budget 60
```

손잡이:
- `--start` / `--end`: 출력 달
- `--workers`: 1~4
- `--budget`: FLAML 시행 수. 기본 = 설정 60, 스모크 = 8
- `--smoke`
- `--history YYYY-MM`: 학습 이력 시작. 기본 = 측정 축 시작
- `--targets earn,val,dist,ret`
- `--no-linear`

## 10. 스모크 결과(2026-11-16 · `smoke_log.json` · `smoke_stdout.txt`)

설정: 2012-01 ~ 03 · 이력 2009-01~ · 시행 8 · 워커 4. 끝까지 돌았다(rc 0).

| 항목 | 값 |
|---|---|
| 입력 패널 | 126,314행(전 종목 재무) → 위생 멤버 40,144행 × 입력 204 |
| 입력 PIT 자가 시험 | 통과(2010-02 · 2012-03 · 279행) |
| 시간 | 44 s(입력 26 s · 가격 6 s · 학습 5회 ≈ 9 s) |
| 최대 메모리 | 1.87 GB |
| 출력 | 8개 팩터 × 3,695행 |

AutoML이 고른 모델(시행 8 — FLAML은 lgbm → rf 순서로 시작하므로 짧은 예산에서는 둘만 시도됨):

| 표적 · 재학습일 | 최선 단일 | Caruana 앙상블 가중 |
|---|---|---|
| earn 2011-12 | lgbm | lgbm 0.74 · rf 0.26 |
| val 2011-12 | lgbm | lgbm 1.0 |
| val 2012-03 | lgbm | lgbm 0.92 · xgboost 0.08 |
| dist 2011-12 | lgbm | lgbm 0.02 · rf 0.98 |
| ret 2011-12 | lgbm | lgbm 0.84 · rf 0.16 |

**비용 탐침**(`probe_b60_log.json` · `probe_stdout.txt`):
- 설정: 이력 2006~ · 시행 60(전체 판 예산) · earn · val · 2012-01 한 달.
- earn 2011-12: 학습 12,139 · 검증 3,682 → **xgb_limitdepth** 최선. 앙상블 = xgb_limitdepth 0.54 · sgd 0.32 · lgbm 0.14. 6개 패밀리를 모두 시도했다. 25.8 s.
- val 2011-12: xgb_limitdepth 0.9 · xgboost 0.1. 198.6 s(탐색 + 5묶음 교차 재적합).
- 최대 메모리 3.26 GB. 이 측정은 가격 패널 묶음화 전이며, 묶음화 뒤 스모크 최대 메모리는 2.72 → 1.87 GB로 줄었다.

**재현성**:
- 같은 입력으로 두 번 돌리면 탐색 결과(설정 · 손실 · 가중)는 같다.
- 출력 값 차이는 최대 1.1e−16이다. rf 나무 평균의 부동소수 합산 순서에서 생긴다.

## 11. 전체 실행 비용 추정(2000-01 ~ 2026-10 · 시행 60 · 워커 4)

| 표적 | 재학습 수 | 1회 시간(추정) | 소계 |
|---|---|---|---|
| earn · dist · ret | 각 ≈ 22회(확장 창 하한 3년 + 지평 1년 → 2003~2004년 말부터) | 학습 표본 1.6만 → 26 s(실측). 2022년 무렵 ≈ 10만 ~ 12만 → 약 3 ~ 4분(행 수에 대략 비례 가정). 평균 ≈ 1.5 ~ 2분 | ≈ 1.5 ~ 2.5 h |
| val | ≈ 105회(3개월마다 · 2000-09~) | 1.2만 행 → 199 s(실측). 최근 멤버 수 증가로 ≈ 2만 행 → 약 5분 | ≈ 6 ~ 9 h |
| 입력 · 가격 패널 | 1회 | 약 1 ~ 2분 | — |
| **합계** | | | **≈ 8 ~ 11시간**(범위 6 ~ 15 h) · 최대 메모리 ≈ 3 ~ 4 GB(추정 · 2000~ 전 기간 입력 약 42만 행 × 204 float32) |

- val이 비용의 대부분이다(탐색 105회 + 5묶음 재적합).
- 비용 자원 = CPU 4코어다. 팩터 DB 재빌드와 동시에 돌리면 둘 다 느려지므로 **재빌드가 끝난 뒤 실행을 권한다**.
- 측정 전에 val 재학습 주기를 12개월로 바꾸면 val 시간은 약 1/4로 준다. 이 결정은 설정을 바꾸는 것이므로 사람이 측정 전에 내린다.

## 12. 한계 · 문제점

1. **전체 실행을 안 했다.** 비용 · 메모리는 추정이다. 특히 2000~ 전 기간 메모리는 4 GB 정책 한도에 가까울 수 있으니, 첫 실행에서 `peak_rss_gb`를 볼 것.
2. **스모크 예산 8로는 lgbm · rf만 시도된다**(FLAML 탐색 순서). 6개 패밀리 전부를 쓰는 동작은 시행 60 탐침에서만 확인했다.
3. **분기 표본 표적의 첫 몇 년은 학습 표본이 작다**(earn 첫 재학습 ≈ 1만 행). 이른 해 팩터는 잡음이 크다. 측정 계약이 실효 시작(MC3 B안)으로 다룬다.
4. **dist 표적 = 관리종목 지정만 본다.** 위생 멤버는 이미 관리종목이 아니다. 상장폐지 직행(관리 지정 없이 폐지)은 사건으로 잡히지 않는다.
5. **ret 표적**: 상장폐지 종목은 마지막 거래일까지의 수익만 쓴다(폐지 수익 결측).
6. **val = 시가총액 수준을 맞히는 모델이다.** 저평가 신호가 아니라 규모 · 유동성 잔차를 잡을 수 있다. 측정 계약의 크기 · β 짝 대조(MC8)와 같이 읽어야 한다.
7. **FLAML 기본 탐색 공간은 데이터 크기에 맞춰 범위를 정한다**(예: `n_estimators` 상한 = 표본 수 기반). 재학습마다 공간이 조금씩 다르지만, 모두 그 시점 학습 표본에서 나온 값이라 PIT 문제는 없다.
8. **팩터 DB 등록 · 결합용 뷰 편입은 하지 않았다**(`.cache/factor_db/` 무접촉). 소비하려면 측정 계약 쪽 적재 경로가 필요하다.
9. 앞선 초안의 `nlff_models.py`(GKX NN3 · 고정 LightGBM · 동일 가중)는 지시에 따라 지웠다. 모델 고정 부분은 AutoML로 대체했다. `nlff_data.py`는 재사용했고, 바꾼 것은 세 가지다:
   - earn 표적에서 같은 기간 행이 여럿이면 `Factor_Date`가 가장 이른 행을 고르도록 순서를 고정
   - 가격 패널을 종목 묶음 단위로 계산(메모리 절약 · 결과 동일 확인)
   - 지평 끝 달력을 한 번만 계산

## 파일

- `nlff_config.json` — 설정 정본(v2: automl · linear_control · output · smoke)
- `nlff_data.py` — 입력 as-of 패널 · 표적 · 위생 유니버스 · PIT 자가 시험
- `nlff_automl.py` — 시간순 분할 단정 · FLAML 탐색 · Caruana 앙상블 · 재적합 · 선형 대조
- `nlff_run.py` — 걸어가는 학습 드라이버(손잡이 · 출력 · 실행 기록)
- `smoke_log.json` · `smoke_stdout.txt` — 스모크 기록
- `probe_b60_log.json` · `probe_stdout.txt` — 시행 60 비용 탐침 기록
