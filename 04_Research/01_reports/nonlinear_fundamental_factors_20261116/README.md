# 비선형 재무 팩터(NLFF) — AutoML 판 (2026-11-16)

도훈 지시(11-16): "AutoML 을 써서 비선형 재무 팩터 구현해 봐." · "새 패키지 설치해도 돼." · "auto-sklearn, tpot, automl 패키지도 활용해봐." · RET = 시장 대비 초과 수익 · "캐시데이터 이용하는거면 극단치 제어도 해야겠네" · "AutoML의 모델 선택 지표를 순위 IC로 바꿔줘" · "권장안대로 진행"(엔진별 표적 · auto-sklearn 재적합 상한 · 극단치 시험 상대 기준 · 전체 실행 준비).
상태: **코드 · 설정 · 엔진 3종(FLAML · auto-sklearn · TPOT) 스모크 완료. 전체 실행은 하지 않았다**(같은 PC 팩터 DB 전체 재빌드와 겹치지 않게). 성과 지표(IC · 수익률)는 계산 · 보고하지 않았다 — 실행 기록에 남는 검증 IC 는 학습 창 안(τ_D 이전) 모델 선택 값이며 동작 확인용이다. 측정은 나중에 시스템 표준 계약이 한다.

## 1. 질문

재무 지표 사이의 비선형 관계(상호작용 · 문턱 · 포화)를 쓰면 선형 결합으로는 안 보이는 정보가 나오는가?
이 폴더는 그 질문을 잴 **재료(월말 팩터 값)**만 만든다. 모델은 사람이 고르지 않는다. AutoML 이 모델 패밀리를 고르고, 하이퍼파라미터를 찾고, 앙상블을 짠다. 판정은 이 폴더 밖, 측정 계약의 일이다.

## 2. 표적 4개 → 팩터 4개(+ 선형 대조 4개)

| 표적 | 정의 | 과제 | 재학습 | 팩터(Raw_Value) | 방향 |
|---|---|---|---|---|---|
| earn | 1년 뒤 TTM 지배주주 순이익 변화 ÷ 현재 총자산. 단면 순위로 (−1, 1) 변환 | 회귀 | 매년 12월 · 확장 창 · 분기 표본 | `NLFF_EARN` = 예측 순위 | 클수록 좋음 |
| val | 같은 달 로그 시가총액에서 단면 평균을 뺀 값(적정가치) | 회귀 | 3개월마다 · 12개월 이동 창 · 월 표본 · 종목 5묶음 교차 적합 | `NLFF_VAL` = 추정 − 실제(저평가일수록 +) | 클수록 좋음 |
| dist | 향후 12개월 안 관리종목 지정(0→1) | 이진 | 매년 12월 · 확장 창 · 분기 표본 | `NLFF_DIST` = 지정 확률 | **작을수록 좋음** |
| ret | 향후 12개월 **KOSPI200 대비 초과 수익**(종목 단순 수익 − 같은 구간 KOSPI200 단순 수익). 단면 순위로 (−1, 1) 변환 | 회귀 | 매년 12월 · 확장 창 · 분기 표본 | `NLFF_RET` = 예측 순위 | 클수록 좋음 |

**ret 표적(11-16 변경)**: 벤치 = 공표 KOSPI200(`.cache/benchmark.parquet::BM_Ret` · 등급 벤치와 같은 지수). 구간 = 결정일 다음 거래일 ~ 종목 끝일(12번째 다음 월말 이전 마지막 거래일 · 상장폐지면 마지막 거래일)이고, 벤치도 같은 시작 · 끝일로 복리한다(`nlff_data.bench_logcum` · `_bench_at` — 벤치 값이 7일 넘게 비면 표적 없음). 실현 시점 · 엠바고는 종전 ret 와 같다(실현일 = 지평 끝 월말).
- 표적을 표본월 단면 순위로 바꾸므로, 같은 날짜 안에서는 벤치 수익이 모든 종목에 같은 상수라 순위가 원수익 순위와 거의 같다(다른 것은 끝일이 다른 상장폐지 종목뿐).
- 다만 날짜를 모아 학습할 때(순위가 아닌 값 표적 · 선형 대조 진단 등)는 시장 전체 변동이 표적에서 빠진다 — 강세장 · 약세장 해의 표적 수준 차이가 모델에 들어가지 않는다.

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

**재학습 주기(현행 유지 · Q 판단 11-16)**: VAL 3개월 · EARN · DIST · RET 1년.
- VAL: 표적이 그 달 시가총액이라 지평 0 — 엠바고로 잃는 표본이 없다. 시장이 재무 정보에 매기는 가격 체계는 금리 · 국면 따라 빨리 변하고 재무 정보는 분기마다 도착한다. Bartram & Grinblatt 2018(JFE 'Agnostic Fundamental Analysis Works' https://doi.org/10.1016/j.jfineco.2017.11.006)은 매달 횡단면을 다시 추정한다.
- EARN · DIST · RET: 미래 표적이라 분기 재학습은 새 표본을 한 분기 코호트만 더한다(확장 창 전체의 ≈ 1/(4 × 연수)) — 정보는 거의 안 늘고 AutoML 선택 잡음(재학습마다 다른 패밀리 · 설정)만 커진다.

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

(위 = 공용 venv `.venv_qvest_ml` 의 FLAML 코어 판 · 공용 venv 에는 그 뒤로 아무것도 설치하지 않았다.)

**엔진 전용 환경 3개(11-16 · 공용 venv 무접촉 · 모두 PyPI 공식 · 판 고정 · 설치 전 `--dry-run`)** — 판 목록 전부 = `env/freeze_*.txt`.

| 환경 | 파이썬 | 핵심 패키지(고정 판) | 이유 · 확인 |
|---|---|---|---|
| `.venv_nlff_automl`(Windows · 드라이버 + FLAML) | 3.12.10 | `FLAML[automl]==2.8.0` · `xgboost==2.1.4` · lightgbm 4.7.0 · scikit-learn 1.9.1 · numpy 2.5.4 · pandas 3.1.1 · pyarrow 26.0.1(14개) | `flaml[automl]` 추가 의존은 `xgboost<3` 를 요구 → 이 환경에서만 2.1.4(공용 레인 영향 없음). 나머지 판은 공용 venv 와 같게 고정(입력 패널 동일성 — §10). 3.12 = 공용 3.15 보다 바퀴(wheel) 지원이 넓다 |
| `.venv_nlff_tpot`(Windows · TPOT 작업기) | 3.12.10 | `TPOT==1.1.0` · `xgboost==3.4.1` · dask/distributed 2026.8.0 · optuna 5.1.0 · ConfigSpace 1.2.2 · `setuptools==75.8.0` · `py-spy==0.4.1`(진단) | TPOT 1.1.0 은 `xgboost>=3` 를 요구해 `flaml[automl]`(`xgboost<3`)과 한 환경에 못 든다(pip 해석 실패 실측) → 분리. `setuptools<81` = stopit 이 `pkg_resources` 를 쓴다(81 에서 제거). py-spy = 스모크 중 느린 재적합 진단용 |
| WSL Ubuntu 24.04 `~/venvs/nlff_autosklearn`(auto-sklearn 작업기) | 3.9.25(uv 사용자 영역 설치) | `auto-sklearn==0.15.0` · smac 1.2 · pyrfr 0.8.3(소스 빌드 · `swig==4.3.1` PyPI 판) · scikit-learn 0.24.2 · numpy 1.23.5 · scipy 1.10.1 · pandas 1.5.3 · distributed 2024.8.0 · `setuptools==75.8.0` · `py-spy==0.4.1`(진단 시도 — WSL ptrace 권한이 없어 쓰지 못함)(46개) | auto-sklearn 은 공식적으로 리눅스 전용(SMAC · pyrfr) · 0.15.0 이 마지막 판이고 `scikit-learn<0.25` 를 요구 → 0.24.2 바퀴가 있는 마지막 파이썬 = 3.9. numpy 2.x 는 sklearn 0.24 와 ABI 가 안 맞아 1.23.5. `setuptools<81` = auto-sklearn 이 `pkg_resources` 를 쓴다. WSL · 배포판은 이미 있던 것(`wsl -l -v` = Ubuntu · docker-desktop) · 시스템 설정 · 배포판 변경 없음 · gcc/g++ 은 이미 있었다 |

설치하지 않은 것:
- 공용 venv 의 `flaml[automl]`: xgboost를 2.1.4로 내린다(전용 환경에만 설치).
- catboost: FLAML 기본 목록에 있지만 미설치면 빠진다(`flaml[automl]` 도 catboost 는 넣지 않는다 — 엔진 목록은 종전과 같다).

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
- **선택 지표(11-16 변경 · 도훈 '순위 IC로')**: earn · val · ret = **시간순 검증 구간의 월별 단면 Spearman 순위 IC 평균**(`nlff_automl.ic_mean` · 외부 엔진 = 같은 정의 `nlff_ic.ic_mean`). 검증 행을 날짜로 묶어 달마다 표적 순위 ↔ 예측 순위 상관 → 종목 수 < 30 인 달 제외 → 동일 가중 평균. dist = AUC(종전).
  - 문턱 30 근거: Spearman 표준오차 ≈ 1/√(n−1) 가 n = 30 에서 0.19 · 정규 근사가 표본 수십부터 맞다(Fieller, Hartley & Pearson 1957 Biometrika 44 https://doi.org/10.2307/2332878). IC 정의 = Grinold & Kahn 2000 ch.6.
  - 바뀐 곳 전부: FLAML `metric`(사용자 함수 · 손실 = 1 − IC · 검증 날짜는 클로저 · 길이 단정) · auto-sklearn `metric`(`make_scorer` · 날짜는 환경 변수가 가리키는 파일 · 길이 단정) · TPOT `scorers`(sklearn `make_scorer`) · Caruana 앙상블 선택 기준 · 선형 대조 능형 벌점 선택.
  - **선택 = IC · 적합 = 기본 손실**: IC 는 어느 엔진도 학습 손실로 직접 최적화하지 않는다(나무 · 선형 학습기는 제곱 오차 등 기본 손실로 적합). IC 는 패밀리 · 하이퍼파라미터 · 앙상블 가중을 고를 때만 쓴다.
  - 검증 IC 값은 학습 창 안(재학습일 − 엠바고 이전 실현 표본)이고 2023년 이후 자료는 들어가지 않는다. 실행 기록의 값은 동작 확인용이며 성과로 인용하지 않는다.
- **검증 분할**(`nlff_automl.time_split`):
  - 검증 = 재학습 창 표본월 중 시간순 마지막 20%.
  - 학습 부분 = 검증 첫 달보다 앞서고, 표적도 그 전에 실현된 표본(정화).
  - 모든 표적에 같은 규칙을 쓴다(지평 0인 val 포함).
- **최종 재적합**: 고른 설정을 재학습 창 전체(실현일 ≤ 재학습일 − 1개월)로 다시 적합한다. FLAML `retrain_full` · AutoGluon `refit_full`과 같은 뜻이다.
- **워커**: `--workers` ≤ 4(코드에서 거부). OMP · MKL · OpenBLAS · loky 스레드도 같은 수로 묶는다. GPU는 쓰지 않는다.

이 설정은 측정 전에 문헌 · 라이브러리 기본값으로 정했다. 2023년 이후 성과는 계산조차 하지 않았다(τ_D = 2022-12-31). 외부 엔진의 예산 · 설정은 §13.

## 7. 재학습 일정 · PIT 논증

| 장치 | 내용 | 코드 단정 |
|---|---|---|
| 입력 as-of | 결정일 t의 값 = `Factor_Date ≤ t` 마지막 행 + 묵은 값 거르기 | `asof_dense`: 쓰인 모든 값의 `Factor_Date ≤ t` 아니면 중단 · 스모크마다 **미래 행 잘라내기 불변성 자가 시험**(원천을 `Factor_Date ≤ t`로 자른 뒤 다시 만든 입력이 비트 단위로 같아야 함 → 통과) |
| 표적 방향 | 지평 > 0 표적의 실현일 > 결정일 | `nlff_run` 표적 단정 · `build_chunk` earn 단정 |
| 걸어가는 학습 | 재학습일 R의 학습 표본 = 표적 실현일 ≤ R − 1개월(엠바고) ∧ 결정일 ≤ R − 1개월. 그 모델이 R ~ 다음 재학습 전까지의 달을 예측 | `time_split`: 학습 표본 실현일 ≤ R − 1개월. 예측 전 `max(실현일) ≤ cut < 예측 첫 달` |
| AutoML 검증 | 재학습 창 안 시간순 마지막 20%. 학습 부분은 실현일 < 검증 첫 달(정화) | `time_split`: 학습 Date < 검증 Date · 학습 실현일 < 검증 첫 달. **양성 대조**: 엠바고 위반을 주입하면 단정이 발화함을 확인함 |
| 표적 순위 | earn · ret 순위는 **재학습마다 그때 실현된 표본끼리만** 매긴다(아직 실현 안 된 동료 값이 순위에 섞이지 않게) | `nlff_run` 재학습 루프의 `rank_reg` 절 |
| 단면 전처리 | 순위 · 결측 0 · 평균 차감은 같은 달 단면 안. 입력 범위 판정은 그 재학습의 학습 창 표본만 | 전 표본 통계 없음 |
| ret 벤치(11-16) | 초과 수익의 KOSPI200 구간 수익 = 결정일 다음 거래일 ~ 종목 끝일 · 실현일 = 지평 끝 월말(종전 ret 와 같음) | 표적 방향 단정(실현일 > 결정일) 그대로 · 벤치 7일 넘게 비면 표적 없음 |
| 유니버스 | 유동성 · 종가는 t−1, 표식은 그날(측정 계약과 같은 식) | 묶음 계산 = 통째 계산 동일성 확인(2009~2012 · 40,144행 일치) |
| val 자기 기억 | 종목 5묶음 교차 적합. 자기 묶음은 빼고 학습한 모델로 예측 | `ticker_fold` |

재학습 일정:
- earn · dist · ret: 매년 12월 말에 재학습하고, 1~12월(그 12월 포함)을 예측한다. 확장 창, 분기 표본(3 · 6 · 9 · 12월). 표본월 12개(3년) 미만이면 팩터를 내지 않는다.
- val: 3 · 6 · 9 · 12월 말에 재학습한다. 12개월 이동 창, 월 표본, 하한 6개월.

알려진 PIT 경계(기록):
- 동전주 바닥은 수정 종가 기준이다. 측정 축 전체의 경계와 같다(constraint_defaults `price_floor._source`).
- 묵은 값 경계의 달 뺄셈 방식이 R `seq`와 다르다. pandas는 달 끝을 잘라 맞추고, R은 다음 달로 넘긴다. 기간 말은 분기 말이라 실제 차이는 거의 없지만, 비트 단위 일치는 검증하지 않았다.

## 8. 산출 팩터 형식

- **팩터 파일(11-16 · 엔진별)**: `.cache/nl_fundamental_factors/<engine>/NLFF_<T>.parquet`(engine = `flaml` · `autosklearn` · `tpot`) · 선형 대조 = `.cache/nl_fundamental_factors/linear/NLFF_<T>_LIN.parquet`(엔진 무관 · 한 번만)
  - 열: `Date`(월말 거래일, datetime64[s]) · `Ticker` · `Factor_Name` · `Raw_Value` — 엔진마다 같은 형식 · 같은 `Factor_Name`(폴더가 엔진을 가른다)
  - 위생 멤버 행만 들어간다.
  - 스모크는 `.cache/nl_fundamental_factors/smoke/<engine>/` · `smoke/linear/`에 쓴다(`smoke/` 바로 아래 8개 파일 = 11-16 오전 FLAML 코어 판 첫 스모크 · 옛 표적 · 사료).
  - 엔진 하나가 어느 재학습에서든 실패하면 그 엔진 파일은 쓰지 않는다(부분 산출 없음 · 기록 `failed_engines`).
- **실행 기록**: `<태그>_log.json`(태그 = `smoke_<엔진>` · `run_<엔진>_<시작>_<끝>`)
  - 재학습마다 엔진별 시행 수, 패밀리별 최선 검증 손실(FLAML = 1 − IC), 고른 모델, 앙상블 가중, 고른 설정, 학습 · 검증 표본 수, 시간, 최대 메모리(외부 엔진 = 작업기 프로세스 나무 합)
  - 검증 손실은 τ_D 이전 학습 창 안의 값이다.
- **방향**: 값은 원시 점수다. 순위 정렬 · 부호 정리는 소비 쪽 정본 접근자의 `direction`으로 한다(C13). DIST는 작을수록 좋다.

## 9. 실행법

### 9-A. 전체 실행(준비만 · 아직 실행하지 않음 · 도훈 11-16 '권장안대로 진행')

`bash run_full.sh [END=2026-10] [WORKERS=4]` — 순서 FLAML → TPOT → auto-sklearn · 엔진 하나가 끝나면 다음 · 한 엔진의 한 표적이 실패(종료 코드 ≠ 0 · 엔진 실패 = 3)하면 그 엔진의 남은 표적만 멈추고 다음 엔진으로 간다.

| 엔진 | 표적(설정 `engines.<e>.targets`) | 드라이버 · 작업기 | 워커 | 로그 | 산출 폴더 |
|---|---|---|---|---|---|
| FLAML | earn · val · dist · ret | 공용 `.venv_qvest_ml`(작업기 없음) | 4 | `logs/full_flaml_<t>.log` · `run_flaml_<t>_2000-01_<END>_log.json` | `.cache/nl_fundamental_factors/flaml/` + 선형 대조 `linear/` |
| TPOT | earn · dist · ret | `.venv_nlff_automl` → `.venv_nlff_tpot` | 4(dask 워커) | `logs/full_tpot_<t>.log` · `run_tpot_<t>_…_log.json` | `.cache/nl_fundamental_factors/tpot/` |
| auto-sklearn | earn · dist · ret | `.venv_nlff_automl` → WSL `~/venvs/nlff_autosklearn` | 4(dask 워커 · WSL) | `logs/full_autosklearn_<t>.log` · `run_autosklearn_<t>_…_log.json` | `.cache/nl_fundamental_factors/autosklearn/` |

- 실행 단위 = 엔진 × 표적(`nlff_run.py --engine E --targets T`). 단위마다 메타 `NLFF_meta_<t>.json`(재학습별 시행 수 · 고른 모델 · 재적합 대체 경로 여부)을 산출 폴더에 쓴다.
- **재개**: 단위 단위로만 된다 — 산출 parquet 과 메타가 둘 다 있으면 그 단위를 건너뛴다. 단위 안(재학습 중간)에서는 재개하지 않는다(끊기면 그 엔진 × 표적을 처음부터). 다시 돌리려면 그 두 파일을 지운다.
- 전제: 같은 PC 의 팩터 DB 전체 재빌드 · 무거운 레인이 끝난 뒤(§11). 엔진은 동시에 돌리지 않는다(순차).
- `--engine all` 도 설정의 엔진별 표적 목록을 따른다(그 엔진 목록에 없는 표적은 건너뛴다).

### 9-B. 스모크 · 수동

```
cd 04_Research/01_reports/nonlinear_fundamental_factors_20261116
# FLAML 판(공용 venv · 코어) — 종전 그대로
../../../.venv_qvest_ml/Scripts/python.exe nlff_run.py --smoke --engine flaml
# 엔진 선택(드라이버 = 전용 환경 · TPOT 은 .venv_nlff_tpot · auto-sklearn 은 WSL 작업기를 하위 프로세스로 부른다)
../../../.venv_nlff_automl/Scripts/python.exe nlff_run.py --smoke --engine autosklearn
../../../.venv_nlff_automl/Scripts/python.exe nlff_run.py --start 2000-01 --end 2026-10 --workers 4 --engine all
```

손잡이:
- `--start` / `--end`: 출력 달
- `--workers`: 1~4
- `--budget`: FLAML 시행 수. 기본 = 설정 60, 스모크 = 8
- `--smoke`
- `--history YYYY-MM`: 학습 이력 시작. 기본 = 측정 축 시작
- `--targets earn,val,dist,ret`
- `--no-linear`
- `--engine flaml|autosklearn|tpot|all`(쉼표 목록 가능): 엔진마다 같은 행렬 · 같은 표적 · 같은 시간순 분할(드라이버가 한 번 만들어 모든 엔진에 넘긴다)

## 10. 스모크 결과

### 10-A. 11-16 오후 — 엔진 3종 · 새 표적(ret 초과 수익 · val 윈저) · 선택 지표 IC · 극단치 자가 시험

공통: 2012-01 ~ 03 · 이력 2009-01~ · 워커 4 · 같은 입력 패널(126,314행 → 위생 멤버 40,144행 × 입력 204 · 입력 PIT 자가 시험 통과). 모두 rc 0 · 엔진 실패 없음 · 엔진마다 4개 팩터 × 3,695행. 기록 = `smoke_<엔진>_log.json` · `smoke_<엔진>_stdout.txt`.

| 엔진(환경) | 예산(스모크) | 총 시간 | 최대 메모리 | earn 2011-12 | val 2011-12 | val 2012-03 | dist 2011-12 | ret 2011-12 |
|---|---|---|---|---|---|---|---|---|
| FLAML 2.8.0(공용 venv · 코어) | 시행 8 | 60 s | 1.86 GB | lgbm 0.96 · rf 0.04 | lgbm 1.0 | lgbm 0.80 · xgboost 0.20 | lgbm 0.02 · rf 0.98 | lgbm 1.0 |
| FLAML 2.8.0[automl](`.venv_nlff_automl`) | 시행 8 | 58 s | 1.84 GB | lgbm 0.96 · rf 0.04 | lgbm 1.0 | lgbm 0.84 · xgboost 0.16 | lgbm 0.02 · rf 0.98 | lgbm 1.0 |
| TPOT 1.1.0(`.venv_nlff_tpot`) | 개체 4 × 세대 2 = 평가 8 · 시간 상한 10 분 | 40.5 분 | 작업기 1.34 ~ 1.55 GB(드라이버 1.84) | HistGradientBoosting(513 s) | RandomForest(816 s) | RandomForest(819 s) | HistGradientBoostingClassifier(54 s) | HistGradientBoosting(173 s) |
| auto-sklearn 0.15.0(WSL · `~/venvs/nlff_autosklearn`) | 시행 26(하한) · 상한 600 s | 112 분(탐색 240 ~ 540 s · 나머지 = 앙상블 재적합) | 작업기 나무 2.5 ~ 4.28 GB(드라이버 1.85) | RandomForest 외 8개 앙상블(664 s) | RandomForest 외 5개(791 s) | ExtraTrees 외 4개(1,054 s) | GradientBoosting 외 8개(962 s) | LibSVM_SVR 외 10개(3,213 s) |

- auto-sklearn: 5회 모두 시행 26 이 시간 상한 전에 끝났고, **앙상블 표적 = 시간순 검증 표적 단정 5/5 통과**(`ensemble_targets_equal_time_val`). 비용은 탐색보다 **앙상블 재적합**(`refit` · val 은 5묶음 × 앙상블 구성원)이 크다 — ret 은 재적합만 ≈ 50 분(구성원에 `criterion = "mae"` 숲 등 · §12-B).
- FLAML 두 판의 차이는 xgboost 판(공용 3.4.1 · 전용 2.1.4)뿐이다 — xgboost 가 앙상블에 든 val 2012-03 만 값이 다르다(오전 실측: 그 달만 최대 차 0.028 · 나머지 달 차 0).
- TPOT 이 고른 파이프라인은 모두 앞단에 `RFE(ExtraTrees)` 특성 선택이 붙었다(기록 `best_pipeline`). 평가 수 = 개체 × 세대(스모크 8 실측) · 그중 점수가 난 평가 7(earn · val · ret) · 5(dist) — 나머지는 평가 시간 상한 · 실패.
- TPOT 의 val 이 느린 이유 = 5묶음 재적합의 RandomForest 가 탐색 공간 고정값 `n_jobs = 1` 로 단일 코어였다(py-spy 로 확인 · 2,637 s) → 재적합에서만 `n_jobs` 를 워커 수로 올려 816 s(결과 불변 — 나무 결과는 `n_jobs` 와 무관).
- **극단치 자가 시험**(earn 2011-12 · 종목 A000070 · 원 입력 · 원 표적 × 1e6 · 37행): 다른 종목 예측의 날짜별 Spearman — **제어 켬 최소 0.976 · 평균 0.977 / 제어 끔(원값) 최소 0.003 · 평균 0.024 / 진단: 그 종목을 아예 뺐을 때 최소 0.986**. 재구성 설계 행렬 = 본 실행과 같음. 미리 정한 문턱(최소 ≥ 0.99)은 **넘지 못했다(pass = False · 기록 그대로)**. 다만 그 종목을 빼기만 해도 0.986 이라, 스모크 표본(학습 1,732행)에서 종목 하나가 바뀔 때의 기본 민감도가 이미 0.99 아래다 — 1e6 배 주입의 영향(0.977)은 그 기본 민감도와 같은 크기이고, 제어를 끄면 일치도가 0 근처로 무너진다(시험이 극단치를 잡아내는 힘 = 확인). 문턱은 결과를 본 뒤 Q 가 바꾸지 않았다.
  - **재판정(상대 기준 · 도훈 11-16 '권장안대로 진행')**: 판정 = 주입 일치도(최소) ≥ 같은 종목을 뺐을 때 일치도(최소) − 0.01 → 0.976458 ≥ 0.985698 − 0.01 = 0.975698 → **통과**(여유 0.00076 — 얇다). 코드 · 설정에 반영(`outlier_control.selftest_margin` · 기록 `rule` · `pass`) 뒤 FLAML 스모크 재실행(공용 venv · 67 s · 같은 값 · `pass = True` · `smoke_flaml_stdout.txt`).

### 10-B. 11-16 오전 — FLAML 코어 판 첫 스모크(옛 표적 · 옛 선택 지표 r2 · 사료 · `smoke_log.json` · `smoke_stdout.txt`)

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

## 11. 전체 실행 비용 추정(2000-01 ~ 2026-10 · 워커 4)

### 11-A. 엔진별(11-16 오후 · 스모크 실측 바탕 · 추정)

**재추정(도훈 11-16 '권장안대로 진행' 반영 · 엔진별 표적 · auto-sklearn 재적합 상한)**

| 엔진 | 재학습 수 | 1회(추정) | 소계 | 메모리 |
|---|---|---|---|---|
| FLAML | 171(earn · dist · ret 각 ≈ 22 + val ≈ 105) | earn 계열 1.5 ~ 2 분 · val 3 ~ 5 분 | **≈ 8 ~ 11 h** | ≈ 3 ~ 4 GB |
| TPOT | 66(earn · dist · ret) | 탐색 ≈ 60 분(평가 60 이 상한 60 분에 먼저 닿는다고 봄) + 재적합(상한 없음 · 1 파이프라인) | **≈ 66 ~ 90 h** | 작업기 ≈ 1.5 ~ 3 GB |
| auto-sklearn | 66(earn · dist · ret) | 탐색 ≤ 60 분 + 재적합 ≤ 60 분(상한 · 넘으면 대체 경로) → 1회 ≤ 약 2 h | **≈ 70 ~ 135 h**(위쪽 끝 = 66 × 2 h 상한) | 작업기 나무 ≈ 3 ~ 4.3 GB(WSL) |
| **합계(순차)** | | | **≈ 145 ~ 235 h(약 6 ~ 10 일)** | |

- 비용 자원 = 같은 PC 의 CPU 4코어(병목) — 재빌드 · 레인과 겹치면 늘어난다. 외부 엔진은 시간 상한이 먼저 닿으므로 부하가 크면 시간은 비슷하고 시행 수가 준다(§12-D).
- 아래 표는 val 포함 · 재적합 상한 없음 가정의 이전 추정(사료).

재학습 수(표적 공통): earn · dist · ret 각 ≈ 22 회 + val ≈ 105 회 = **≈ 171 회**.

| 엔진 | 1회 시간 근거(스모크 실측) | 1회 추정(전체 예산) | 소계 | 메모리 |
|---|---|---|---|---|
| FLAML(시행 60) | 아래 11-B(오전 탐침) · IC 지표는 시간 영향 미미(스모크 44 s → 58 s · 극단치 자가 시험 포함) | earn 계열 1.5 ~ 2 분 · val 3 ~ 5 분 | **≈ 8 ~ 11 h** | ≈ 3 ~ 4 GB |
| TPOT(평가 60 · 상한 60 분) | 평가 8 · 상한 10 분에서 탐색 40 ~ 770 s(val 은 상한에 닿음) · val 5묶음 재적합 ≈ 50 s | 전체 표본(1만 ~ 12만 행)에선 평가 60 이 60 분 상한에 먼저 닿는다고 보면 ≈ 60 분 + 재적합 | **≈ 170 ~ 210 h** | 작업기 ≈ 1.5 ~ 3 GB |
| auto-sklearn(시행 60 · 상한 3600 s) | 시행 26 · 상한 600 s 에서 탐색 ≈ 240 ~ 600 s · 앙상블 재적합이 탐색보다 길다(스모크 재적합 385 ~ 2,976 s · 학습 창 1.7천 ~ 1.2만 행) | 탐색 ≈ 30 ~ 60 분 + 재적합(스모크에서 이미 6 ~ 50 분 · 표본이 10배면 MAE 숲 · SVR 은 제곱 이상으로 늘어난다 → **상한 없음**) | **≥ 250 h · 상한을 정할 수 없음**(§12-B 를 정하기 전엔 추정 불가) | 작업기 나무 ≈ 3 ~ 4.3 GB(WSL) |
| **합계(순차)** | | | **≥ 430 h(18 일 이상)** — auto-sklearn 재적합 상한이 정해지기 전엔 위쪽 끝이 없다 | |

- 비용 자원 = CPU 4코어(같은 PC 팩터 DB 재빌드 · 레인과 겹친다) — 병목 자원이다. 세 엔진을 동시에 돌리면 12코어 · 메모리 합 ≈ 10 GB 로, 같은 PC 정책(RAM 80%)에 걸린다.
- TPOT · auto-sklearn 은 시간 상한이 먼저 닿으면 시행 수가 기계 부하에 따라 달라진다(재현성 약함 · §12).
- 줄이는 손잡이(측정 전 · 사람 결정): val 재학습 12개월(105 → 27회 · 외부 엔진 소계 ≈ 1/3) · 외부 엔진 시간 상한 축소 · 표적 일부만.

### 11-B. FLAML 판(11-16 오전 추정 · 시행 60 · 워커 4)

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

**11-16 오후(엔진 3종 · 표적 · 지표 · 극단치) 추가분**
- A. **극단치 자가 시험이 미리 정한 문턱(0.99)을 못 넘었다**(제어 켬 0.976 · 제어 끔 0.003 · 종목 빼기 진단 0.986). 시험은 극단치를 잡아내는 힘이 있고(제어 끔 붕괴), 제어 켬의 영향은 종목 하나 빼기와 같은 크기다. → **도훈 11-16 '권장안대로 진행'**: 상대 기준(종목 빼기 일치도 − 0.01)으로 고정 · 재판정 통과(여유 0.00076 — 얇아서 전체 실행 첫 스모크마다 다시 볼 값).
- B. **auto-sklearn 앙상블 재적합에 시간 상한이 없다.** 탐색 때는 실행당 상한(기본 = 전체의 1/10)이 있지만 `refit()` 에는 없다. 스모크 ret 에서 탐색 237 s · 재적합 ≈ 2,976 s(학습 창 2.8천 행)였다. 후보 중 scikit-learn 0.24 의 `criterion = "mae"` 숲(random_forest · extra_trees — 기본 탐색 공간에 있음)은 표본 수의 제곱으로 느려져 전체 실행(표본 1만 ~ 12만)에선 사실상 끝나지 않을 수 있다. → **도훈 11-16 '권장안대로 진행'**: (1) 재적합 상한(= 탐색 예산) + 넘으면 탐색 모델(학습 부분만)로 고정(§13). 남은 위험: TPOT 재적합에는 상한이 없다(지시 범위 밖 · 1 파이프라인이라 작지만 `RFE(ExtraTrees)` 는 표본이 크면 길 수 있다).
- C. **auto-sklearn 메타학습 초기점이 IC 지표에선 꺼진다**(메타학습 자료가 기본 지표에만 있음) — 회귀 표적의 auto-sklearn 은 '메타학습 없는 SMAC' 이다. dist(AUC)만 메타학습을 쓴다.
- D. **시간 상한이 시행 수를 정할 수 있다**(TPOT · auto-sklearn). FLAML 은 시행 수 고정 · 시간 무제한이라 기계 부하와 무관하지만, 두 외부 엔진은 상한(기본값)에 닿으면 실제 시행 수가 부하에 따라 달라진다 — 재현성이 약하다. 실제 시행 수는 기록 `n_trials`.
- E. **TPOT 1.1.0 파이프라인 안의 내부 교차검증**: 일부 구성요소(예: 학습기를 변환기로 쓰는 단계)는 학습 부분 안에서 sklearn 기본 KFold 를 쓸 수 있다. 학습 부분 안이라 미래 정보는 없지만 시간 순서는 아니다(선택용 검증은 시간순 그대로). 스모크에서 고른 파이프라인 = `RFE(ExtraTrees)` + 부스팅/숲(내부 교차검증 단계 없음).
- F. **엔진 결과 고르기 = 시행 수 가산**(§13). 엔진 3 × 표적 4 산출을 잰 뒤 엔진을 고르면 선택 현실 점검 대상.
- G. **WSL 작업기는 같은 PC 메모리를 쓴다**(vmmemWSL). auto-sklearn 작업기 나무 최대 4.28 GB(dist 스모크) — 프로세스당 4 GB 정책 경계.
- H. 분모가 극히 작은 비율(작은 기저 성장률 등)의 행별 NA 처리는 하지 않았다(§14 — 분모 열이 입력에 없고 생산자 코드는 범위 밖). 순위 변환이 크기 영향은 묶는다.

**11-16 오전(FLAML 코어 판) 기록**

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

## 13. 엔진 3종 — 시간순 분할 · 앙상블 · 예산 · 시행 회계(11-16)

공통 원칙(FLAML 판과 같음): 드라이버(`nlff_run.py`)가 입력 · 표적 · 시간순 분할(`time_split` · 마지막 20% 표본월 · 정화 · 엠바고)을 한 번 만들고, 엔진은 그 행렬만 받는다. 엔진이 분할을 다시 하지 않는다. 외부 엔진은 `nlff_automl.fit_external` → 작업기 `nlff_engine_worker.py`(파이썬 3.9 호환) — 행렬을 `.cache/nl_fundamental_factors/_xfer/<엔진>_<표적>_<재학습일>/` 에 `.npy` 로 쓰고(WSL 은 `/mnt/g/...` 로 같은 파일을 읽는다) 예측을 돌려받은 뒤 지운다.

| 엔진 | 시간순 분할 처리 | 앙상블 | 예산(측정 전 고정) | 선택 지표 |
|---|---|---|---|---|
| FLAML 2.8.0 | `X_val`/`y_val` 직접 전달(holdout) | 내장 스태킹 끔(sklearn 기본 KFold) → 공통 Caruana(시간순 검증 예측 · 크기 50) | `max_iter` 60 · 스모크 8 | IC(사용자 함수) · dist AUC |
| auto-sklearn 0.15.0 | `resampling_strategy = PredefinedSplit`(학습 부분 −1 · 검증 0 · 행 순서 = [학습, 검증]) · 분할이 정확히 하나 · 색인 일치 단정 · 무작위 행 줄이기(`dataset_compression` subsample) 끔 | **내장 앙상블(Caruana · 크기 50 = 기본) 사용** — 앙상블 표적(`load_targets_ensemble`)이 시간순 검증 표적과 순서 · 길이까지 같은지 매 재학습 단정(다르면 그 엔진 중단). **음성 대조**: `resampling_strategy = "holdout"`(기본 무작위)으로 바꾼 사본에서 단정이 발화함을 확인(합성 자료) | SMAC `runcount_limit` 60 · 시간 상한 3600 s(기본) · 실행당 기본(1/10) · 스모크 26(= 초기 설계 하한 · 아래) · 메타학습 초기점 25 · 실행당 메모리 3072 MB(기본) · **최종 재적합 상한 = 탐색 시간 예산과 같은 3600 s(스모크 600 s · 도훈 11-16 '권장안대로 진행')** | IC(`make_scorer`) · dist AUC |
| TPOT 1.1.0 | `cv = PredefinedSplit`(기본 `cv=10` 은 뒤섞은 KFold) · `validation_strategy = "none"`(기본 · 무작위 train_test_split 안 씀) · 학습 뒤 `cv_gen` 분할 색인 단정 | 없음(최선 파이프라인 1개 · 라이브러리 기본) — 파이프라인 안 스태킹 단계가 있으면 그 단계는 학습 부분 안에서만 적합 | 개체 10 × 세대 6 = 평가 60(스모크 4 × 2 = 8 · 실측 평가 수 = 개체 × 세대) · 시간 상한 60 분(기본) · 평가당 10 분(기본) | IC(sklearn `make_scorer`) · dist AUC |

- **엔진별 실행 표적(도훈 11-16 '권장안대로 진행')**: FLAML = earn · val · dist · ret · TPOT · auto-sklearn = earn · dist · ret(val 제외 — 재학습 171회 중 약 105회가 3개월 주기 val). 설정 `engines.<e>.targets` · `--engine all` 도 따른다. 외부 엔진의 val 은 없다 — 엔진 비교는 earn · dist · ret 에서만.
- **auto-sklearn 최종 재적합 시간 상한(도훈 11-16 '권장안대로 진행')**: 상한 = 그 재학습의 탐색 시간 예산(`time_left_s`)과 같은 크기. 근거 — 탐색 예산은 '재학습 1회에 쓸 만한 계산'으로 이미 정한 값이고, 재적합은 같은 앙상블 구성원을 표본 1.25배(학습 부분 → 창 전체)로 한 번씩 다시 적합하는 일이라 정상이면 탐색보다 짧다. 상한을 같게 두면 재학습 1회 비용이 탐색 예산의 2배로 묶인다.
  - 구현: 재적합을 fork 한 자식 프로세스에서 하고 상한 안에 끝나면 그 예측, 넘거나 실패하면 자식을 죽이고 **탐색 때 학습 부분으로 적합한 앙상블**(`automl_.models_`)로 예측한다. 그 모델이 학습 부분만으로 적합됐는지는 합성 자료에서 확인했다(학습 부분 재적합과 예측 차 0 · 전체 재적합과는 다름).
  - 양방향 확인(합성 자료): 상한 0.01 s → 대체 경로(`refit_fallback = true` · 사유 'time_cap 초과') · 상한 600 s → 정상 재적합(`false`).
  - 기록: 실행 기록 `engines.autosklearn.refit_fallback` · `refit_fallback_reason` · `refit_s` · 드라이버 요약 `refit_fallbacks` · 산출 메타 `NLFF_meta_<t>.json`. 대체 경로를 탄 재학습의 팩터는 '창 전체 재적합 없음'(최근 20% 표본월 미학습)이다 — 측정 계약이 메타로 구별할 수 있다.
- 최종 재적합: 세 엔진 모두 고른 모델(앙상블)을 재학습 창 전체(실현일 ≤ 재학습일 − 1개월)로 다시 적합한다(auto-sklearn `refit` · TPOT = 파이프라인 복제 후 `fit` · val 은 종목 5묶음마다).
- TPOT 재적합은 단일 프로세스라 탐색 공간이 학습기에 박아 둔 `n_jobs = 1` 을 워커 수로 올린다(나무 학습기 결과는 `n_jobs` 와 무관 · 시간만 준다).
- **auto-sklearn 메타학습**: 사용자 지표(IC)에는 메타학습 자료가 없어(`metalearning/files/monthly_spearman_ic_*` 없음 경고) 메타학습 초기점이 비활성 — 초기점은 SMAC 기본 초기 설계로 대신된다. dist(AUC)만 메타학습 초기점을 쓴다. SMAC 은 초기 설계 크기(메타학습 25 + 기본 1 = 26)보다 작은 `runcount_limit` 을 거부한다(스모크 26 의 이유).
- **auto-sklearn 시간 상한**: 시행 60 이 시간 상한 3600 s 보다 먼저 끝나지 않으면 시행 수가 60 보다 적을 수 있다 — 실제 시행 수는 기록 `n_trials`.
- **엔진별 결과 = 시행 회계상 별도 변형이다.** 엔진 3종 × 표적 4개의 산출을 측정 계약으로 잰 뒤 엔진을 고르면 그 선택은 시행 수를 늘린다(엔진 수만큼 가산) — 선택 현실 점검(`contracts/selection_reality_check.R` · 등급 v3.4) 대상이다. 엔진 고르기는 측정 전에 정하거나, 고른다면 세 엔진 산출 전부를 시행 집합으로 등록한다. 엔진 선택에 2023년 이후 성과를 쓰지 않는다(τ_D).

## 14. 극단치 제어(11-16 · 규칙 고정 · 모든 통계는 날짜별 단면 안에서만)

| 대상 | 규칙 | 근거 · 상태 |
|---|---|---|
| 입력 특성 | 날짜별 단면 순위 → (−1, 1)(`rank_centered`) | 종전부터 있음(확인). 순위는 단조 변환에 불변 — 1% / 99% 윈저를 먼저 해도 결과는 꼬리 1% 의 순서를 동점으로 바꾸는 것뿐이고 영향 크기는 이미 [−1, 1] 로 묶여 있다 → 윈저는 순위 안에 포함되므로 따로 두지 않았다. 순위 [−1, 1] 을 고른 근거 = Gu, Kelly & Xiu 2020 · Kelly, Pruitt & Su 2019(정규 점수보다 꼬리가 더 묶인다) |
| 분모 부호 · 작은 분모 | 생산자(`build_fundamental_caches.R::fc_derive`)가 이미 처리: `sdv` = 분모 > 0 일 때만 · `sda` · `gr` = 분모 절댓값(부호 뒤집힘 없음 · 이익 성장률 등) · `dA_X` = 1년 전 총자산 > 0 일 때만(`nlff_data`) | 확인. 가격 배수형(P/E · P/B)은 입력에 없다(순수 재무). 분모가 0 에 가까운 비율(작은 기저의 성장률 등)은 값이 커도 순위 꼬리 하나로 묶인다 — 따로 NA 로 바꾸지 않았다(분모 열이 입력에 없어 '극히 작음' 문턱을 행마다 판정할 수 없고, 생산자 코드는 이 작업 범위 밖) |
| 결측 | 결측 = 0(단면 중앙 순위) + 행 결측 비율 1열 · 항목별 결측 지시 변수는 넣지 않음 | 종전부터 있음. Gu, Kelly & Xiu 2020 = 중앙값 채움 · 지시 변수 203개는 입력 차원을 2배로 만들고, '중앙 순위 0 과 결측 0' 의 구별은 결측 비율 열이 맡는다 |
| 표적 earn · ret | 표본월 단면 순위(−1, 1) — 재학습마다 그때 실현된 표본끼리 | 종전부터 있음(엔진 공통 — 드라이버가 만든 표적을 모든 엔진이 쓴다) |
| 표적 val | 같은 날짜 단면 1% / 99% 윈저(로그 시가총액) → 단면 평균 차감 · 팩터 = 추정 − 실제(같은 윈저 척도) | **추가**(설정 `targets.val.winsor_q`). 순위가 아닌 이유 = 팩터가 '추정 − 실제' 차이라 크기 척도가 필요. 1/99 = Kothari, Leone & Wasley 2005 관행 문턱 |
| 표적 dist | 0/1 — 제어 불필요 | — |
| 가격제한 밖 수익 | 상장 첫날: 결정일 t 의 위생 멤버는 20일 평균 거래대금(t−1)이 있어야 하므로 t 전에 이미 상장돼 있다 → 상장 첫날 수익은 표적 구간(t 다음 날 ~)에 들어올 수 없다. 거래정지 해제 직후: 결정일 t 에 정지 중이면 위생 필터로 빠지지만, t 뒤 구간 안에서 정지 · 해제가 일어나면 그 수익은 표적에 들어간다(보유자가 실제로 겪는 수익 · 기록) | 확인 · 기록. 상장 전 행은 RAWDATA 에서 이미 지워져 있다(11-16 RAWDATA-PRELISTING-EXCLUDE) |
| 학습 손실 | 회귀 엔진은 위 순위 · 윈저 표적으로 적합 · Huber 류는 엔진 기본 후보 안에만 있다(FLAML `sgd` · auto-sklearn `sgd` · TPOT `SGDRegressor` 의 loss 후보에 `huber` 포함) — 새 패밀리 추가 없음 | 확인 |

**자가 시험(양성 대조 1건 · 스모크마다 · `nlff_run.outlier_selftest`)**: 학습 표본이 가장 많은 종목 하나의 원 입력 203개 · 원 표적(earn)을 1e6 배로 키운 뒤 같은 절차(단면 순위 → 설계 행렬 → 같은 FLAML 설정으로 재적합 → 예측)를 다시 돌려, 다른 종목 예측의 날짜별 Spearman 일치도를 잰다(예측끼리의 일치도 · 성과 지표 아님). 대조 팔 = 극단치 제어를 끈 판(원값 입력 + 원값 표적). 재구성한 설계 행렬이 본 실행과 같은지도 단정한다. 결과는 §10.

## 파일

- `nlff_config.json` — 설정 정본(v4 + 11-16 '권장안대로 진행' — engines.<e>.targets · autosklearn refit_cap_s · outlier_control.selftest_margin: automl(선택 지표 IC) · engines(auto-sklearn · TPOT 예산 · 환경) · outlier_control · targets(ret 초과 수익 · val 윈저) · linear_control · output · smoke)
- `nlff_data.py` — 입력 as-of 패널 · 표적(ret = KOSPI200 대비 초과 수익 · `bench_logcum`) · 위생 유니버스 · PIT 자가 시험
- `nlff_automl.py` — 시간순 분할 단정 · 선택 지표 `ic_mean` · FLAML 탐색(사용자 지표) · Caruana 앙상블 · 재적합 · 선형 대조 · 외부 엔진 어댑터 `fit_external`
- `nlff_engine_worker.py` — 외부 엔진 작업기(auto-sklearn = WSL · TPOT = `.venv_nlff_tpot` · 파이썬 3.9 호환)
- `nlff_ic.py` — 외부 엔진용 선택 지표(피클 가능 모듈 · 날짜 = 환경 변수 파일)
- `run_full.sh` — 전체 실행 스크립트(준비만 · 미실행 · 엔진 × 표적 단위 · 재개 = 단위 건너뛰기)
- `nlff_run.py` — 걸어가는 학습 드라이버(손잡이 `--engine` · 출력 · 실행 기록 · 극단치 자가 시험 `outlier_selftest`)
- `env/freeze_venv_nlff_automl.txt` · `env/freeze_venv_nlff_tpot.txt` · `env/freeze_wsl_nlff_autosklearn.txt` — 전용 환경 판 목록(설치 직후)
- `smoke_flaml_log.json` · `smoke_flaml_stdout.txt`(공용 venv · 상대 기준 재판정 뒤) · `smoke_flaml_log_venv_nlff_automl.json` · `smoke_tpot_log.json` · `smoke_tpot_stdout.txt` · `smoke_autosklearn_stdout.txt`(+ `smoke_autosklearn_log.json` — 끝까지 돈 경우) — 11-16 오후 스모크 기록
- `smoke_log.json` · `smoke_stdout.txt` — 11-16 오전 FLAML 코어 판 첫 스모크(옛 표적 · 사료)
- `probe_b60_log.json` · `probe_stdout.txt` — 시행 60 비용 탐침 기록(오전)
