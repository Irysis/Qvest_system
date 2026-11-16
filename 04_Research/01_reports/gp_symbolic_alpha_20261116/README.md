# 유전 프로그래밍(기호 회귀) 비선형 알파 팩터 — 설계 · 스모크 (gpa_v2 · 2026-11-16)

도훈 지시(11-16): 기본 데이터(시가 · 고가 · 저가 · 종가 · 거래량 · 재무제표)에 사칙연산 · 로그 · 제곱근 · 시계열 연산을 조합해 살아남은
수식을 해석 가능한 비선형 알파 팩터로 만든다 — "설계와 짧은 구간 시험까지". 같은 날 설계 변경 5건을 반영했다:
걸어가는 재진화 · 시장 대비 초과 수익 표적 · 극단치 제어 · **가격 단말 = 로그 캐시(PIT 수리)** · **재무 단말 = 규모 없는 비율**(+ memmap 구현).
**전체 실행 · 측정 계약 · 팩터 DB 쓰기 · 커밋 · 텔레그램은 하지 않았다.** 이 문서에 성과 수치는 없다(스모크 동작 확인 로그만).

| 파일 | 역할 |
|---|---|
| `gp_config.json` | 모든 고정값(단말 · 문법 · 예산 · 적합도 · 선택 · 창 · 자원) — 측정 전 고정 · 판 `gpa_v2` |
| `gp_data.py` | 일별 패널(T × N float32 · `.npy` memmap) · 위생 멤버 · 재무 비율 as-of · 표적 · 벤치 · CD91 · 표준 팩터 · 자식 프로세스 적재 |
| `gp_ops.py` | 연산자(시계열 = 열 묶음 계산) · 정규화(동치 · 퇴화) · 해시 · 부분식 캐시 평가기 |
| `gp_fitness.py` | 탐색 적합도(상위 25종 롱온리 · 15bps · CAPM α IR) · 진단 |
| `gp_engine.py` | DEAP 강타입 GP 1회 진화(결정적 교차) · 시행 원장 |
| `gp_run.py` | 걸어가는 재진화 · 기계적 선택 · 적용 · 팩터 파일 · 안정성 |
| `gp_selftest.py` | PIT · 극단치 · 결정성 자가 시험 T1~T7 |
| `gp_memtest.py` | 전체 규모(1998~2025 · 전 종목) memmap 메모리 · 평가 시간 측정 |
| `trial_budget_rc.txt` | `programs/trial_budget.R rc` 출력 |

---

## 1. 도구 — DEAP 1.4.3 (gplearn 아님)

| 요구 | gplearn 0.4 | DEAP 1.4 |
|---|---|---|
| 패널(종목 × 날짜) 연산 | 함수가 1차원 배열 원소별(`make_function` 은 길이 10 의 1차원 배열로 닫힘 검사) — 같은 날 단면 순위 · 같은 종목 과거 창은 평탄화 + 색인 해킹 | 원시 함수가 임의 객체를 받는다 — (T, N) 행렬 그대로 |
| 창 길이 | 상수 자리가 실수 상수 — 'ts_mean(x, 37.3)' 을 못 막는다 | **강타입 GP**(`PrimitiveSetTyped` · Montana 1995) — 형 W(창) 자리에 고정 후보만 |
| 적합도 | `make_fitness(y, y_pred, w)` 1차원 | 평가 함수 자유(월말 표본 · 포트폴리오 · 원장) |
| 시행 회계 | 내부 평가를 꺼내는 지점 없음 | 평가 호출이 우리 코드 — 고유 수식마다 원장 1행 |

근거: Fortin, De Rainville, Gardner, Parizeau & Gagné (2012), "DEAP: Evolutionary Algorithms Made Easy", *JMLR* 13:2171-2175, https://jmlr.org/papers/v13/fortin12a.html ·
Montana (1995), "Strongly Typed Genetic Programming", *Evolutionary Computation* 3(2):199-230, https://doi.org/10.1162/evco.1995.3.2.199 ·
gplearn https://gplearn.readthedocs.io/en/stable/reference.html · AutoAlpha 도 gplearn 이 초기 개체 · 탐색 공간 탐색에 비효율이라고 적었다(Zhang et al. 2020 §4.4, https://arxiv.org/abs/2002.08245).
**DEAP 수리 2건**: ① `gp.generate` 는 기본형이 없는 형(W)에서 IndexError → `gp_engine._generate` 가 그 형이면 단말을 고른다. ② `gp.cxOnePoint` 가 공통 형 **집합**(set of classes)에서 `random.choice` 를 해 **프로세스마다 결과가 달랐다**(같은 씨앗 · 같은 데이터에서 해시 씨앗만 바꾸자 고유 수식 133 vs 140 — 재현 · 감사 실패) → `gp_engine.cx_one_point` 가 형 이름순 목록에서 고른다. T7 로 고정 확인.

**설치**(새 전용 venv `.venv_gp_alpha` · Python 3.12.10 · PyPI 공식 `--index-url https://pypi.org/simple` · `pip install --dry-run` 먼저 · 판 고정 · `.venv_qvest_ml` · `.venv_nlff_automl` 무접촉):
`deap==1.4.3 numpy==2.2.6 bottleneck==1.5.0 pyarrow==20.0.0 pandas==2.3.1 psutil==7.0.0 python-dateutil==4.0.0 pytz==2026.6 tzdata==2026.6`.

## 2. 단말 · 연산자 · 문법 (고정)

### 2-1. 가격 · 거래 단말 = 로그 캐시 (gpa_v2 · PIT 수리)

원천 = `.cache/rawdata_log.parquet`(생산자 `02_Infrastructure/data/build_rawdata_log.R` · 밤 갱신 [1y2] 가 매일 다시 만듦 · RAWDATA 와 같은 (Date, Ticker) 키 — 적재기가 키 일치를 검사하고 어긋나면 멈춘다).

| 단말 | 정의(생산자) | 쓰는 이유 · 처리 |
|---|---|---|
| `LogRet` | log1p(Ret) | 일 로그 수익 · 날짜별 1/99 윈저 |
| `LogBMRet` | log1p(BM_Ret) | 벤치 일 로그 수익 — 날마다 전 종목 같은 값(시계열 상관 · 공분산의 짝으로만 의미 · 아래 퇴화 규칙) |
| `LogSize` | log 시가총액 | 크기(실제 원 금액 — 수정 계수 없음) |
| `LogFloatCap` | log(시총 × 유동비율) | 유동 시총(유동비율 없는 초기 구간은 NA) |
| `LogAmount` | log1p(수정 종가 × 수정 거래량) | 실제 거래대금(수정 계수 상쇄) |
| `LogHL` | log(고가 / 저가) | 장중 범위 · 날짜별 윈저 |
| `LogCO` | log(종가 / 시가) | 장중 수익 · 날짜별 윈저 |
| `LogGap` | log(시가 / 전 거래일 종가) | 갭 · 날짜별 윈저 |

**뺀 것**: `open high low close`(수정주가 **수준** — 그 뒤 분할 · 증자의 수정 계수가 거꾸로 들어 있어 미래 정보 · 생산자 머리 주석과 같은 판단) · `LogVol`(수정 **거래량 수준** — 같은 문제. 예: 나중에 50:1 분할한 종목은 과거 거래량이 50배로 적힌다. 거래대금 `LogAmount` 는 가격 × 수량에서 계수가 상쇄되므로 남긴다) · 원 RAWDATA `ret · cap · amount`(위 로그 단말로 대체).
위생 · 유니버스 · 표적 수익은 그대로 RAWDATA(§3). 표준 팩터도 로그 캐시로 다시 만들었다(§5).

### 2-2. 재무 단말 = 규모 없는 비율 (gpa_v2 · 크기 쏠림 처치 (가))

분자 · 분모 각각 `fa_latest` 규칙(Factor_Date ≤ t 인 마지막 행 · 기간 말이 t − 15개월보다 오래면 NA) · **시가총액 = 결정일 t 의 RAWDATA Size**(PIT) · 분모 ≤ 0 이면 NA · 날짜별 단면 1/99 윈저.
원 단위 수준(매출 · 자본 …)은 크기 대리라 뺐고, **주당 값**(EPS · BPS …)은 수정 주식 수가 수정주가 수준과 같은 문제를 가져 쓰지 않는다.

| 단말 | 식 | 묶음 | 근거 |
|---|---|---|---|
| `fr_ep` | 지배주주 순이익(TTM) ÷ 시총 | 가치 | Basu (1977), *J. Finance* 32(3), https://doi.org/10.1111/j.1540-6261.1977.tb01979.x |
| `fr_bm` | 자본(BookEquity) ÷ 시총 | 가치 | Fama & French (1992), *J. Finance* 47(2), https://doi.org/10.1111/j.1540-6261.1992.tb04398.x |
| `fr_sp` | 매출(TTM) ÷ 시총 | 가치 | Barbee, Mukherji & Raines (1996), *Financial Analysts Journal* 52(2), https://doi.org/10.2469/faj.v52.n2.1980 |
| `fr_cfp` | 영업현금흐름(TTM) ÷ 시총 | 가치 | Lakonishok, Shleifer & Vishny (1994), *J. Finance* 49(5), https://doi.org/10.1111/j.1540-6261.1994.tb04772.x |
| `fr_opp` | 영업이익(TTM) ÷ 시총 | 가치(이익 수익률) | Loughran & Wellman (2011), *JFQA* 46(6), https://doi.org/10.1017/S0022109011000445 (원 논문은 EV 분모 — 여기는 시총 근사) |
| `fr_levm` | 총부채 ÷ 시총 | 레버리지(시장) | Bhandari (1988), *J. Finance* 43(2), https://doi.org/10.1111/j.1540-6261.1988.tb03952.x |
| `fr_gpa` | 매출총이익(TTM) ÷ 총자산 | 수익성 | Novy-Marx (2013), *JFE* 108(1), https://doi.org/10.1016/j.jfineco.2013.01.003 |
| `fr_opa` | 영업이익(TTM) ÷ 총자산 | 수익성 | Ball, Gerakos, Linnainmaa & Nikolaev (2015), *JFE* 117(2), https://doi.org/10.1016/j.jfineco.2015.02.004 |
| `fr_roa` | 순이익(TTM) ÷ 총자산 | 수익성 | Fama & French (2006), *JFE* 82(3), https://doi.org/10.1016/j.jfineco.2005.09.009 |
| `fr_cfoa` | 영업현금흐름(TTM) ÷ 총자산 | 수익성(현금) | Ball, Gerakos, Linnainmaa & Nikolaev (2016), *JFE* 121(1), https://doi.org/10.1016/j.jfineco.2016.03.002 |
| `fr_acc` | (순이익 − 영업현금흐름) ÷ 총자산 | 발생액 | Sloan (1996), *Accounting Review* 71(3), https://www.jstor.org/stable/248290 |
| `fr_leva` | 총부채 ÷ 총자산 | 레버리지(장부) | Fama & French (1992) 장부 레버리지 |
| `fr_ag` | 총자산 성장률(재무 캐시 `AssetGrowth` · 4분기 전 대비) | 투자 | Cooper, Gulen & Schill (2008), *J. Finance* 63(4), https://doi.org/10.1111/j.1540-6261.2008.01370.x · Fama & French (2015) CMA |

### 2-3. 연산자 · 문법

문헌 기준점: Kakushadze (2016) "101 Formulaic Alphas" 부록 A(rank · delay · correlation · covariance · delta · decay_linear · ts_min/max · ts_rank · stddev · abs · log), https://arxiv.org/abs/1601.00991 ·
AlphaGen — Yu et al. (KDD 2023) 표 4(Abs · Log · + − × / · Ref · Mean · Std · Max · Min · Delta · WMA · Cov · Corr · 최대 20 토큰 · 상호 IC 0.7 거름 기준선), https://arxiv.org/abs/2306.12964 ·
AutoAlpha — Zhang, Li, Jin & Li (2020)(두 알파 유사도 < 0.7 = 다양), https://arxiv.org/abs/2002.08245.

| 묶음 | 연산자 | 비고 |
|---|---|---|
| 단면 단항 | `neg abs slog ssqrt cs_rank cs_zscore` | slog = sign·log1p\|x\| · ssqrt = sign·√\|x\| · cs_rank = 그날 백분위(동률 평균) · cs_zscore = 그날 1/99 윈저 뒤 z |
| 이항 | `add sub mul div` | div 분모 \|y\| < 1e-10 → NA |
| 시계열 단항 (x, d) | `ts_mean ts_std ts_rank ts_min ts_max ts_delta ts_delay ts_decay_linear` | 창 = t, t−1, …, t−d+1 · 유효 관측 ≥ ⌈0.75 d⌉ |
| 시계열 이항 (x, y, d) | `ts_corr ts_cov` | 두 계열 모두 유한한 날만 · float64 |
| 단말 P | 로그 8(§2-1) + 재무 비율 13(§2-2) = 21 | |
| 단말 W | `5 10 20 60 120 250` | 1주 · 2주 · 1달 · 1분기 · 반년 · 1년 — AlphaGen 10~50일을 포함하고 월간 보유(≈21일) · 연간 모멘텀 창(Jegadeesh & Titman 1993)까지 |

- **깊이 ≤ 5**(창 인자 제외) · **노드 ≤ 20**(창 포함 — AlphaGen 최대 20 토큰) · 초기 깊이 1~3(반반 생성).
- 뺀 것: 실수 상수 · sign · 조건식 · vwap(없음) · 산업 중립화(1판 범위 밖) · 거듭제곱(mul 중첩만).

**동치 · 퇴화 정규화(`gp_ops.canon`) — 실효 시행 수를 줄이는 장치**
- 동치: 교환 법칙(add · mul · ts_corr · ts_cov) · `neg(neg x)=x` · `abs(abs x)=abs(neg x)=abs x` · `slog(neg x)=neg(slog x)` · `rank(rank x)=rank(z x)=rank x` · `z(z x)=z x` · `rank(slog x)=rank x` · `ts_rank(ssqrt x, d)=ts_rank(x, d)` · **뿌리의 단조 증가 변환 제거**(cs_rank · cs_zscore · slog · ssqrt — 순서가 같으면 상위 25종 · 순위 IC 가 같다) · `neg(단조 x)=neg x`.
- 퇴화(무효 · 시행으로 세지 않음 · 세대 요약에 개수만): `sub(x,x) · div(x,x) · ts_corr(x,x,d) · ts_cov(x,x,d)`.
- **로그 단말 위 이중 변환(gpa_v2 판단 — 넣었다)**:
  `slog(Log*)` = 퇴화 — 수준형(LogSize · LogFloatCap · LogAmount ≈ 20~35)은 '로그의 로그'로 좁은 범위에서 거의 선형이고, 수익률형(LogRet · LogCO · LogGap · LogHL — 대부분 \|x\| < 0.3)은 log1p\|x\| ≈ \|x\| 라 거의 항등이다.
  `ssqrt(LogSize · LogFloatCap · LogAmount)` = 퇴화 — 같은 이유(좁은 범위에서 거의 선형).
  `ssqrt(수익률형 로그)` 는 **남긴다** — √\|r\| 는 꼬리를 눌러 분포 모양을 실제로 바꾼다(항등이 아니다).
  근거: 근사 항등 표기는 같은 수식을 다른 해시로 세어 실효 시행 수와 원장을 부풀린다. 정확한 동치가 아니므로 '같은 해시로 모으기'가 아니라 '문법에서 제외'로 처리했다.
- **행 상수 단말**: `LogBMRet` 만으로 된 수식(예 `ts_mean(LogBMRet, 20)`) · `cs_rank/cs_zscore(LogBMRet …)` = 퇴화(그날 모든 종목이 같은 값 → 순위가 전부 동률).
- 해시 = 정규화 문자열 SHA-1 앞 16자. **보유 지문(`hold_hash`)** = 학습 · 검증 월마다 상위 25종 집합 해시 — 표기가 달라도 같은 포트폴리오를 낸 수식을 묶는다(선택 단계 중복 제거).

## 3. PIT (절대)

1. **연산자**: 시계열 = 뒤쪽 창(t 포함 과거) · 미래 shift 없음(창 후보가 양수뿐) · 단면 = 그 날짜 행만 · 시계열 연산은 종목(열) 묶음으로 나눠 계산(열마다 독립 — 값 동일, T1 확인).
2. **신호일 · 보유**: 월말 m 종가까지 정보 → 다음 달 첫 거래일 ~ 마지막 거래일 일별 Ret 복리(RAWDATA)가 표적. 마지막 월말의 다음 달이 패널 안에서 완결되지 않으면 무효(`_month_end_index` — 중간에서 자른 패널의 마지막 행을 월말로 오인하지 않는다).
3. **재무**: Factor_Date ≤ t 마지막 행(`fund_access.R::fa_latest` 규칙) · 15개월 묵은 값 버림 · 시총 = 그날 Size.
4. **위생 멤버(t)** = 관리 · 정지 · 불성실공시 표식(t) 아님 ∧ 20일 평균 거래대금(종가 × 거래량 · t−1 까지) ≥ 2e8 ∧ 전날 수정 종가 ≥ 1,000원 — `contracts/measurement_axis.R::ma_adv20_l1 · ma_close_l1` + `factor_z_standard.R::corp_action_member` 와 같은 정의. 동전주 바닥은 측정 축 epoch 정의 그대로 RAWDATA 수정 종가를 쓴다(축의 기록된 PIT 경계 — 단말에는 쓰지 않는다). 차이 1: 계약은 종목 행 순서로 늦추고 여기는 거래일 격자로 늦춘다(측정은 계약이 다시 한다).
5. **전처리** = 날짜별 단면 안에서만. 6. **무위험** = 월말 m 의 CD91 / 12(보유 시작 전 값 · 2001-01 전 없음 → α 계산에서 그 달 제외).
7. **창 진화**: 해 Y 진화 패널은 Y-12-31 에서 잘린다 · 적합도 월 = 표적이 Y 안에서 완결되는 신호 월.

**자가 시험(`gp_selftest.py` · 결과 `.cache/gp_alpha_factors/smoke_v2_20261116/selftest.json` · 전부 통과 · 68초)**

| 시험 | 내용 | 결과 |
|---|---|---|
| T1 연산자 | 20 연산자 × 창 3종: τ 뒤 행을 무작위로 바꿔도 τ 이전 비트 동일 · 단면 6종: 다른 날 행을 다 바꿔도 그날 동일 · **돌연변이 양성 대조**(x[t+1] · 중심 창) · 열 묶음 계산 = 한 번 계산(10 시계열 연산) | 46/46 · 돌연변이 2/2 적발 · 10/10 비트 동일 |
| T2 무작위 수식 | 문법 생성기 200식 · 2008-06-30 뒤 모든 단말을 로그정규 잡음으로 교란 | 위반 0/200 |
| T3 적재기 잘림 | `build_panel(end=2009-12-31)` 새 적재 vs 2011 말 패널 `slice_to(2009-12-31)` — 단말 21 + 표적 원 Ret · 위생 · 표적 · 벤치 · 무위험 · 표준 팩터 4 | 32/32 동일 |
| T4 걸어가는 재진화 잘림 | 해 2009 진화(30 × 2세대)를 두 패널로: 원장(해시 · 적합도 51행) · 선정 5식 동일 · 적용 해 2010 의 1 · 7 · 12월 말 신호를 (그 월말까지 자른 패널) vs (2010 말 패널) | 동일 · 15/15 |
| T5 표적 방향 | 신호 = 표적 자신 → 순위 IC 1.0 · 지난달 수익(STREV) → \|IC\| 0.03 · 손 대조 1건 | 통과(오차 < 1e-6) |
| T6 극단치 주입 | 한 종목: 시총 · 유동 시총 · 거래대금 × 1e6(로그 + log 1e6) · 재무 분자 × 1e6(비율 × 1e6 → 적재기처럼 윈저) · 하루 가격 글리치 × 1e6(그날 LogRet · LogGap + log 1e6 · 다음 날 −) → 무작위 40식의 **다른 종목** 월말 순위 상관(월 중앙값) | 중앙값 0.99997 · p10 0.989 · 최솟값 0.972 · ≥ 0.99 비율 87.5% |
| T7 프로세스 간 결정성 | 해시 씨앗(PYTHONHASHSEED 0 · 1) 다른 두 프로세스의 같은 씨앗 진화 원장 지문 | 동일(46행 · 지문 일치) |

## 4. 극단치 제어 (모든 통계 = 날짜별 단면 안)

1. **보호 연산자**: div 분모 \|y\| < 1e-10 → NA(1 로 바꾸지 않는다) · slog = sign·log1p\|x\| · ssqrt = sign·√\|x\| · 거듭제곱 연산자 없음(mul 중첩만 · mul 출력 단면 윈저가 상한 · float64 곱 뒤 float32 범위 밖 = NA) · 모든 노드 출력의 비유한값 → NA.
2. **입력**: 재무 비율 13 = 날짜별 1/99 윈저(적재 때) · 수익률형 로그 단말(LogRet · LogHL · LogCO · LogGap) = 날짜별 1/99 윈저(표적은 윈저 전 원 Ret) · 로그 수준 단말은 로그가 이미 꼬리를 누른다(윈저 없음) · 변화율은 `ts_delta` · `div` · `mul` 출력의 날짜별 1/99 윈저 · cs_zscore 는 윈저 뒤 평균 · 표준편차.
3. **수식 출력**: 순위로만 쓴다(상위 25종 · 합성 = 백분위 평균) · **커버리지 하한 60%**(학습 월 평균 · 위생 멤버 중 신호가 유한한 비율) 미달 = 무효. 근거: 정상 수식은 통과하고(스모크 커버리지 미달 0/825), 과반이 비는 수식은 '값이 있는 종목 중 상위'라는 표본 선택을 섞는다. 문헌 문턱이 아니라 설계 고정값이다.
4. **적합도 강건성**: 월 최대 단일 종목 기여 비율(max\|w r\| / Σ\|w r\|)의 평균 · 최댓값을 원장에 기록 — **선택 규칙에 넣지 않는다**(사전 고정 · 문헌 문턱이 없는 상한은 근거 없는 자유도).
5. **표적 위생**: 표적 종목 = 월말 m 위생 멤버뿐. **상장 첫날 수익**: 멤버가 되려면 t−1 까지 20일 거래대금이 있어야 하므로(상장 후 ≥ 21거래일) 보유 달 안에 상장 첫날이 올 수 없다 — 표적에 상장 첫날 수익 0건(구조적). 다음 달 행이 없는 보유 종목(상장폐지 등) = 0(현금) 근사.
6. 자가 시험 = T6.

## 5. 표적 · 적합도

- **표적** = 시장 대비 초과 수익. 종목별 (R_i − R_m) 은 같은 날 상수라 순위 IC 를 바꾸지 않으므로 **포트폴리오 수준**으로: 월말 m 위생 멤버 중 신호 상위 25종 동일가중 롱온리 · 다음 달 보유 · 편도 15bps × \|Δw\| 합 차감 → r_p − 같은 달 공표 KOSPI200(`.cache/benchmark.parquet` · `BM_Src = quantiwise_iks200` · 등급 벤치와 같은 지수).
- **β 함정 — 고정 선택 = CAPM α 정보 비율**: (r_p − rf) = α + β(r_KOSPI200 − rf) + ε 를 평가 창 안에서 추정, α_t = (r_p − rf) − β̂(r_b − rf) 의 평균 / 표준편차 × √12. '단순 초과 IR + β ≤ 1.2' 는 쓰지 않는다(하나만 고정 — 절차 변형을 늘리지 않는다).
  근거: (i) β 상한 아래 β(예 1.15)의 강세장 기여를 그대로 알파로 세고, 상한값 1.2 에 문헌 근거가 없다. (ii) `measurement-graduation.md` §2 — PORT_t 는 α + (β−1)E[r_bm] 을 섞어 β ≠ 1 양방향으로 왜곡한다. (iii) 투자철학 · MC8 · 등급 v3.5 CR 노치는 β 를 낮춰 얻는 방어를 실력으로 세지 않는다. (iv) rf = 0 이면 β < 1 포트의 α 가 (1 − β)·rf 만큼 부푼다.
  비용: α IR 은 β 가 낮고 초과 수익이 작은 수식도 고를 수 있다(등급은 PORT_t · Calmar) — 초과 IR · β 를 원장에 함께 남긴다.
- **진화 적합도**(학습 월) = α IR − 0.005 × 노드 수 − 1.0 × max(0, ρ_std − 0.7). 복잡도 벌점 = parsimony pressure(Poli, Langdon & McPhee 2008, *A Field Guide to Genetic Programming* §11.3, http://www.gp-field-guide.org.uk) — 20 노드 식이 0.1 을 잃는 크기. ρ_std = 표준 팩터 4종과의 월별 단면 스피어먼 평균 절댓값 최대 · 0.7 = AutoAlpha · AlphaGen 다양성 기준.
- **표준 팩터(로그 캐시 직접 · 월말 · gpa_v2)**: MOM12_1 = Σ LogRet(t−251 … t−21)(Jegadeesh & Titman 1993, https://doi.org/10.1111/j.1540-6261.1993.tb04702.x) · STREV = Σ LogRet(t−20 … t)(Jegadeesh 1990, https://doi.org/10.1111/j.1540-6261.1990.tb05110.x) · SIZE = LogSize(Banz 1981, https://doi.org/10.1016/0304-405X(81)90018-0) · LOWVOL = −std(LogRet, 60)(Ang, Hodrick, Xing & Zhang 2006, https://doi.org/10.1111/j.1540-6261.2006.00836.x). 로그 수익 합 = 실제 누적 수익(수정주가 수준 비율을 쓰지 않는다). 팩터 DB 는 읽지 않는다.
- **보조 기록(선택에 안 씀)**: 단순 초과 IR · β · 연 α · 순위 IC 평균 · t · 회전율 · 최대 단일 종목 기여 · 커버리지 · 표준 팩터별 ρ.
- ★이 적합도는 **탐색 목적함수(metric_type = proxy)** 다. 파이썬 포트 수익 구성은 `python-policy.md` §4(보고 · 판정용 포트 수익은 R 경유)와 긴장 관계 — 수식 순위 매기기에만 쓰고 보고 · 등급 · 등록에 쓰지 않는다. 권위 측정 = 산출 팩터 → `run_paper_replication` → essence.

## 6. 걸어가는 재진화 (walk-forward)

**왜**: 고정 분할로 고른 수식을 2000~ 전 기간에 적용하면 그 기간 보유를 이후 데이터로 고른 셈(pit.md C1).

1. 해마다 말 Y(2007 … 2025)에 Y 까지 자른 패널로 진화 → 기계적 선택 → **Y+1 의 12개 월말 신호에만** 적용(첫 적용 해 2008 · 마지막 2026).
2. 창 안 분할(시간순): **검증 = 마지막 36 신호 월** · **엠바고 1개월**(López de Prado 2018, *Advances in Financial Machine Learning* 7장) · **학습 = 그 앞 전부**. 36개월 근거: 등급 v3.3 팩터 노치 관측 하한 36개월 · Lo (2002, https://doi.org/10.2469/faj.v58.n4.2453) 근사로 36개월 연율 IR 표준오차 ≈ 0.58.
3. **최소 학습 창 = 8년(2000-01 ~ 2007-12)**: 검증 36 + 엠바고 1 + 학습 ≥ 59개월(학습 IR 표준오차 ≈ 0.45).
4. **절차 변형 2개(사전 고정)**: `EXP` = 확장 창 · `ROLL8` = 고정 8년(학습 59 · 검증 36). 8년 = 최소 창과 같게 두어 첫 해 두 절차가 같은 입력에서 출발하고 차이가 **기억 길이만**에서 나오게.
5. 2023년 이후 해에도 같은 절차가 기계적으로 돈다 — τ_D 는 '설정 · 규칙을 2023~ 성과로 고르지 않는다'로 지킨다. 원장 행 `post_tauD = (Y > 2022)` — **처방 에이전트 · 교훈 카드 · 판단 Superfan 은 post_tauD 행과 2023~ 적용 해 팩터 값을 읽지 않는다.**
6. **기계적 선택(고정)**: 학습 α IR > 0 ∧ 검증 α IR > 0 ∧ 커버리지 ≥ 60% ∧ 표준 팩터 \|ρ\| < 0.7 → 검증 α IR 내림차순(동률 = 짧은 식 · 해시) → 보유 지문 중복 제거 → 이미 고른 것과 \|ρ\| < 0.7 → **k = 5** · 합성 = 백분위 순위 동일가중(절반 이상 값이 있는 종목만).
7. **이어 받기**: 직전 해 선정 수식 + 명예의 전당 = 다음 해 초기 개체의 **20%**(과거 선택물 — PIT 안전). 고정 예산에서 평가 수는 줄지 않는다(출발점만 좋아진다). 씨앗 = 20261116 + Y.
8. **해석 보고**: `selected_<변형>.jsonl`(선정 수식 · 구조 설명 · 골격 · 표준 팩터 ρ) · 안정성 = 해 사이 같은 수식 · 같은 골격(단말 → P/F · 창 → W) 유지율(`summary.json::stability`). 사람 해석 1줄은 전체 실행 뒤.

## 7. 탐색 예산 (고정)

개체 300 · 세대 15 · 토너먼트 7 · 교차 0.6 · 변이 0.3(부분 트리 70% / 노드 치환 30% — W 끼리 바꾸는 노드 치환이 창 길이 탐색) · 명예의 전당 50.
근거: 토너먼트 7 = Koza (1992, *Genetic Programming*, MIT Press) · gplearn 기본(1000 × 20)의 약 1/3 개체는 계산 상한(§10) 때문. 시행 회계가 절차 단위(§8)라 예산은 선택 현실 점검의 요구 t 를 바꾸지 않는다.

## 8. 시행 회계 — 측정 단위 = 절차

- **선택 현실 점검(`contracts/selection_reality_check.R`)의 시행 집합 = 절차 변형** — `EXP` · `ROLL8`(+ 측정 뒤 설계를 바꿔 다시 돌리면 판마다 +1).
  근거: 절차의 해마다 신호는 그 해 이전 데이터로만 고른 수식에서 나온다 → 측정 수익 계열은 절차 내부 탐색에 대해 표본 밖(선택을 포함한 전체 절차를 바깥 표본으로 평가하는 중첩 검증 — Varma & Simon 2006, *BMC Bioinformatics* 7:91, https://doi.org/10.1186/1471-2105-7-91). 스누핑 보정(White 2000, *Econometrica* 68(5), https://doi.org/10.1111/1468-0262.00152 · Romano & Wolf 2016)이 필요한 선택 = 측정 뒤 절차 변형을 고르는 일.
  남는 위험: ① 문법 · 예산 · k · 문턱은 사람이 정했다(측정 전 · 2005~2010 스모크 동작만 봄) ② **gpa_v1 → v2 변경은 2005~2010 스모크에서 본 선정식의 크기 쏠림(§10)과 가격 수준 단말의 PIT 경계 때문** — 전체 기간 측정 전이라 측정 시행은 늘지 않지만 판 표식(`gpa_v2`)으로 남긴다 ③ 2008~2022 는 설계자가 서사 지식으로 아는 기간(τ_D 는 수치 튜닝만 막는다).
- **원장의 모든 수식 = 절차 내부 계산** — 재현 · 감사용으로 전부 기록, 점검 시행 집합에는 넣지 않는다.

**선택 현실 점검 입력 형식(계약 판독)**: `src_check_dirs(dirs, candidate_dir)` 는 시행마다 **산출 폴더**의 `03_period_returns.csv`(`date · ret_net`) · `05_benchmark_returns.csv`(`date · benchmark_ret`)로 순 활성 수익을 만든다(후보 날짜 기준 · 없는 날 = 0). 통계량 = NW t(lag 3 · PORT_t 와 같은 식) · 정상 부트스트랩 2,000 · Romano-Wolf 단계적 조정 p ≤ 0.05(`grade_v3.json::selection_bias` sb1). 관문 `src_gate(check, port_t, cfg, expected = list(n_trials, ids))` 는 기대 시행 집합이 없으면 통과 아님(fail-closed) · 분산 0 칸 · 날짜 안 겹치는 칸 거부 · 지문 재계산.
→ **저장할 것**: `GPA_EXP` · `GPA_ROLL8`(해마다 이어 붙인 합성) → 표준 계약 측정 1회씩 → 산출 폴더 2개 · `trial_set.json = {n_trials: 2, ids: ["GPA_EXP", "GPA_ROLL8"], design_version: "gpa_v2", registered_before_measure: true}` → `src_check_dirs(c(exp_dir, roll_dir), candidate_dir)` + `src_gate(..., expected = list(n_trials = 2, ids = ...))`.

**원장 형식(`trial_ledger_<변형>.jsonl`)**: 고유 수식마다 1행 `type=trial · variant · evo_year_end · post_tauD · train_from/to · val_from/to · gen · origin(init/inherited/offspring) · hash · expr(정규화) · expr_raw · skeleton · nodes · depth · status · fitness · train{…} · val{…}(n_months · hold_hash · coverage · turnover · max_single_contrib_mean/max · excess_ir · beta · alpha_ir · alpha_ann · rank_ic_mean · rank_ic_t) · std_corr_max · std_corr{4} · eval_ms` + 세대마다 `type=gen_summary(… n_unique_total · n_seen_total · n_degenerate_total · n_over_limit_total · cache_mb · elapsed_s)` · 선정 = `selected_<변형>.jsonl`. 같은 해시는 다시 평가하지 않는다(해마다 1행). 실효 시행 지표 = 고유 해시 · 고유 보유 지문 · 퇴화 제외 수.

**`programs/trial_budget.R rc`(계획값 · `trial_budget_rc.txt`)**

| 닮은 절차 상관 ρ(입력) | K = 1 | K = 2 (EXP · ROLL8) | K = 5 | K = 10 | 기대 t 2.5 에서 최대 변형 수 |
|---|---|---|---|---|---|
| 0.50 | 1.645 | 1.946 | 2.205 | 2.385 | 13 |
| 0.80 | 1.645 | 1.837 | 1.986 | 2.141 | 45 |
| 0.95 | 1.645 | 1.759 | 1.813 | 1.918 | 200 |

→ 절차 단위면 요구 t ≈ 1.8~1.95(< A 하한 PORT_t 2.0). 대조: 원장 수식을 독립 시행으로 세면 n_eff 10³ · 10⁴ · 10⁵ 에서 요구 t 3.88 · 4.41 · 4.89.

## 9. 산출

`.cache/gp_alpha_factors/<run>/GPA_<변형>.parquet`(합성 · 해마다 이어 붙임) · `GPA_<변형>_<적용 해>_<순번>_<해시>.parquet`(개별 수식 · 그 해 12개월만) — 열 `Date(월말 거래일) · Ticker · Factor_Name · Raw_Value`. 패널 사본(`<run>/panel/*.npy`)은 실행 뒤 지운다(재현 = 원천에서 다시 적재).

## 10. 스모크 (gpa_v2 · `.cache/gp_alpha_factors/smoke_v2_20261116/` · 이전 판 = `smoke_20261116/`)

설정(`gp_config.json::smoke`): 종목 400(2004-12-30 위생 멤버 중 무작위 — 그날까지 정보로) · 적재 2003-01 ~ 2011-12 · 적합도 2005-01~ · 최소 창 4년 · 검증 12개월 · 진화 해 말 2008 · 2009 · 2010(적용 2009~2011) · EXP · ROLL3 · 개체 60 · 세대 4 · 전당 15 · 워커 1.

| 항목 | 값 |
|---|---|
| 총 시간 | 60초(자식 적재 8초 · EXP 31초 · ROLL3 21초) · 진화 1회 6~12초 |
| 메모리 | 부모 사유 메모리 최대 1.62 GB(작업 집합 최대 1.00 GB) · 자식 적재 정점 2.00 GB · 단말 21 · 75 MB(memmap) |
| 원장 | 해마다 고유 117~151식(본 개체 177~193) · 퇴화 제외 3~6/해 · 상태 ok 825 · 커버리지 미달 0 |
| 적용 산출 | 변형마다 합성 1 + 개별 14~15 파일 |
| 안정성(같은 수식 / 같은 골격) | EXP 0~0.2 / 0~0.2 · ROLL3 0~0.2 / 0~0.6(작은 예산 — 동작 확인만) |
| 자가 시험 | T1~T7 전부 통과(§3) |

**표준 크기 팩터(SIZE)와의 \|ρ\| 분포 — 전(gpa_v1 · 원 단위 재무 + 수정주가 수준) · 후(gpa_v2)**

| | 표본 | 10% | 25% | 중앙 | 75% | 90% | \|ρ\| ≥ 0.5 비율 |
|---|---|---|---|---|---|---|---|
| 평가한 전 수식 · 전 | 790 | 0.06 | 0.19 | 0.51 | 0.79 | 0.90 | 50% |
| 평가한 전 수식 · 후 | 825 | 0.02 | 0.06 | 0.15 | 0.27 | 0.39 | 6% |
| 선정 수식 · 전 | 30 | 0.09 | 0.17 | 0.37 | 0.53 | 0.62 | 40% |
| 선정 수식 · 후 | 29 | 0.02 | 0.09 | 0.24 | 0.30 | 0.39 | 0% |

(전 판 SIZE 는 log 시총(RAWDATA) · 후 판은 LogSize — 같은 양. 전 판 실행은 DEAP 교차 비결정성 수리 전이라 한 번의 실현값이다.)

선정 수식 예(gpa_v2 스모크 · 동작 확인용 · 성과 미보고):
- `add(fr_bm,fr_sp)` — 장부가 대비 + 매출 대비 가치(두 가치 비율의 합)
- `div(fr_opp,fr_ag)` — 이익 수익률 ÷ 자산 성장률(싸고 덜 투자하는 기업 — 가치 × 투자 상호작용)
- `ts_min(LogGap,10)` — 최근 10일 중 가장 큰 하락 갭(갭 하락 꼬리)
- `ts_decay_linear(ts_min(mul(fr_bm,fr_cfp),120),5)` — 장부가 × 현금흐름 가치 곱의 반년 최저(지속적으로 싼 종목)
- `mul(fr_sp,ts_std(fr_opa,10))` — 매출 대비 가치 × 영업수익성의 최근 변동(실적 발표 전후 수익성 변화가 있는 싼 종목)
- `ts_corr(mul(add(LogAmount,fr_acc),ssqrt(fr_gpa)),neg(slog(fr_levm)),250)`

**전체 규모 memmap 측정(`gp_memtest.py` · 1998-01 ~ 2025-12 · 전 종목 T 6,904 × N 3,604 = 24.9M 칸 = EXP 마지막 해 규모)**: 단말 21 = 2,088 MB(디스크 memmap) · 자식 적재 정점 사유 3.79 GB · 적재 76초 · 부모(평가) 사유 최대 2.02 GB(작업 집합 최대 2.92 GB — memmap 페이지 포함 · 되돌릴 수 있는 공유 페이지) · 무작위 25식 평가 + 적합도 평균 3.8초 · 중앙 3.0초 · 최대 11.3초 → **4 GB 상한 안**. 수리 전(같은 프로세스 적재 · 열 묶음 없음)은 적재 정점 4.64 GB · 평가 정점 4.44 GB 였다.

**전체 실행 비용 추정**(칸당 ≈ 0.15 초/백만 칸 · 위 측정 기준):

| | 패널 칸(백만 · 해 말 2007 → 2025) | 고유 평가/진화 | 진화 1회 | 19회 |
|---|---|---|---|---|
| EXP(1998~ 이력) | 5.2 → 24.9(평균 ≈ 14.5) | ≈ 2,700(본 개체 4,050 × 고유율 0.65~0.75) | 0.6 → 2.8 시간 | ≈ 31 시간 |
| ROLL8(창 + 2년 이력) | 5.2 → 6.8(평균 ≈ 5.9) | ≈ 2,700 | ≈ 0.65 시간 | ≈ 13 시간 |
| 합 | | | | **≈ 44 시간(워커 1 · 순차)** · 부분식 캐시로 20~30% 줄 수 있음 · 두 변형은 독립이라 워커 2 면 ≈ 31 시간(메모리 ≈ 2 × 2 GB — 상한 4 GB 경계) · 이어 받기는 고정 예산에서 평가 수를 줄이지 않는다 |

## 11. 문제점 · 결정 대기

1. **(해소 · 결정 반영)** 크기 쏠림 — 재무 비율 단말로 SIZE \|ρ\| 중앙 0.51 → 0.15(전 수식) · 0.37 → 0.24(선정). 남은 크기 경로: `mul(LogFloatCap, …)` 처럼 로그 수준을 곱하는 수식 — 표준 팩터 벌점(0.7)만 막는다.
2. **(해소)** memmap · 자식 프로세스 적재 · 시계열 열 묶음 계산으로 EXP 마지막 해 규모 4 GB 안(§10).
3. **(해소)** DEAP 교차의 프로세스 간 비결정성(§1 수리 ②).
4. **동치 정규화는 문법 수준** — `x − (x − y) = y` 같은 대수 항등은 못 잡는다(보유 지문이 같은 포트폴리오만 묶는다). 보강 = sympy 단순화(새 의존성).
5. **β 추정 창 = 평가 창 전체** — 시변 β 는 못 본다. α IR 이 저β · 작은 초과 수익 수식을 고를 수 있다.
6. **표적 근사**: 다음 달 행 없는 보유 종목 = 0 · 비용 = \|Δw\| 단순식 · 위생 늦춤이 거래일 격자 기준. 권위 측정은 계약.
7. **동전주 바닥은 수정 종가 수준**(측정 축 epoch 정의 · 기록된 PIT 경계) — 단말에서는 뺐지만 유니버스 판정에는 남아 있다(계약과 같게).
8. **스모크 종목** = 2004 말 멤버만(이후 상장 없음 · 스모크 한정). `LogFloatCap` 은 초기 구간 유동비율이 없어 NA 가 많다(커버리지 하한이 거른다).
9. **설계 반복의 시행 비용**: 전체 결과를 본 뒤 단말 · 문법 · 예산 · 규칙을 고치면 새 절차 변형(+1) — `trial_set.json` · 판 표식.
10. **파이썬 포트 수익**: 적합도 내부 계산은 python-policy §4 의 R 경유 규칙 밖 — 탐색 전용(proxy).
