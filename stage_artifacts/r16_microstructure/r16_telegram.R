## R16 텔레그램 v7 판정 보고 (실측 시각화 의무, 원칙 9)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUTDIR <- "stage_artifacts/r16_microstructure/charts"; if(!dir.exists(OUTDIR)) dir.create(OUTDIR, recursive=TRUE)
STAGE <- "stage_artifacts/r16_microstructure"

scores_long <- as.data.table(read_parquet(file.path(STAGE,"scores_long.parquet")))
returns_dt  <- as.data.table(read_parquet(file.path(STAGE,"returns_dt.parquet")))
bench_dt    <- as.data.table(read_parquet(file.path(STAGE,"bench_dt.parquet")))
liq_dt      <- as.data.table(read_parquet(file.path(STAGE,"liq_dt.parquet")))
size_dt     <- as.data.table(read_parquet(file.path(STAGE,"size_dt.parquet")))
for (d in list(scores_long,returns_dt,bench_dt,liq_dt,size_dt)) d[, Date := as.Date(Date)]

## 서열 (cap-w PORT_t, 실측 summary_main.csv)
summ <- fread(file.path(STAGE,"summary_main.csv"))
lab_map <- c(VSHK_P="VSHK_P 거래량지속", TOD_DT="TOD_DT 회전율추세", AMT_ASY="AMT_ASY 매수압력",
             VPRC_CORR="VPRC_CORR Kyle-λ변화", ILLIQ_VOL="ILLIQ_VOL 유동성위험")
ord <- summ[order(-capw_PORT_t)]
c1 <- tg_chart_sweep(labels=unname(lab_map[ord$factor]), values=ord$capw_PORT_t, out_dir=OUTDIR,
        title="R16 마이크로스트럭처 5종 — cap-w PORT_t (자본 문턱 2.95)", value_label="cap-w PORT_t",
        hline=2.95, hline_label="자본", highlight="AMT_ASY 매수압력", filename="sweep_capw.png")
## EW-uni 서열 (dual-basis)
c2 <- tg_chart_sweep(labels=unname(lab_map[ord$factor]), values=ord$EWuni_PORT_t, out_dir=OUTDIR,
        title="R16 — EW-유니버스 PORT_t (dual-basis 진단, 비바인딩)", value_label="EW-uni PORT_t",
        hline=2.0, hline_label="비유의선", highlight="VPRC_CORR Kyle-λ변화", filename="sweep_ewuni.png")

## 최선 cap-w 팩터(AMT_ASY) 표준 3종
sc <- scores_long[factor=="AMT_ASY", .(Date,Ticker,score)]
cs <- canonical_screen_bt(sc, returns_dt[,.(Date,Ticker,Ret_1m)], bench_dt[,.(Date,BM_Ret)],
        top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8, size_dt=size_dt,
        diag_dual_basis=FALSE, run_id="AMT_ASY", strategy_id="R16_AMT_ASY")
pr <- as.data.table(cs$period_returns)
pack <- tg_chart_pack(pr, out_dir=OUTDIR, title="R16 최선 cap-w 팩터 AMT_ASY(매수압력)",
        metrics_note="cap-w 1.16 · EW-uni 1.70 · rank-IC t -1.97(역부호) · net-SR 0.31 (canonical_screen · HARD 0/5)",
        prefix="AMT_")
charts <- c(c1, c2, pack)

tg_agent_brief(
  agent = "Alpha",
  title = "R16 거래량·마이크로스트럭처 신규 팩터 5종 — 실선택 신호 있으나 자본 문턱 미달",
  sections = list(
    list(type="summary", emoji="📌",
      body="거래량 파생 새 팩터 5종 22년 검증 — 랜덤보다 나은 선택력은 있으나 전부 자본 문턱(cap-w 2.95) 미달. 새 자본 배정 없음, 지식만 적립."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "시도: 거래량·거래대금·회전율에서 파생한 새 팩터 5종을 직접 설계",
        "방법: 매달 팩터 상위 25종목 동일비중 매수 백테스팅(15bps·유동성 필터)",
        "결과: 5종 모두 자본 문턱 cap-w 2.95 미달(최고 매수압력 1.16)",
        "이유: 랜덤보다 나은 선택력은 있으나 대형주 벤치마크 장벽이 이득 흡수",
        "구조: 상위 25종목 95~98% 소형주 쏠림 = 소형주 국소화 벽·2017후 감쇠",
        "의미: 실제 돈 없음. 가격충격 변화 팩터만 동일가중 기준 생존=재분류 후보 보존")),
    list(type="kv", emoji="📊", heading="핵심 수치 (5종 서열 · cap-w 기준)",
      kv=list(
        "매수압력 최고"   = "cap-w 1.16 / EW 1.70 (AMT_ASY, 최고)",
        "가격충격 변화"   = "cap-w 0.86 / EW 1.85 · 2017후 t 1.90 (VPRC, 유일 EW생존)",
        "거래 지속성"     = "cap-w 0.44 · 정보계수 t -3.01 (VSHK, 유의하나 역부호)",
        "유동성위험·회전율" = "0.68 / -1.56 (ILLIQ·TOD, 미달)",
        "게이트 종합"     = "HARD 0/5 · DSR 최고 0.471 · 2017후 cap-w 전부 음")),
    list(type="bullet", emoji="🚩", heading="주의 · 정직",
      items=c(
        "월셔플 귀무 평균 -1.3 → 단측 유의는 '랜덤보다 나음'이지 양의 알파 아님",
        "양측 유의확률 0.52~0.98 = 통상 유의성 부재",
        "사전등록 부호와 역방향 결과 = 매도측 신호이지 매수편입 대상 아님, 정직 보고",
        "낙오 후보 하나는 착수 전 중복탐지(과거 반증)로 제외 = 재측정 방지",
        "크기 함정 검정: 5종 모두 크기-프록시 아님(크기 통제 정보계수 미미)")),
    list(type="bullet", emoji="➡️", heading="판정 · 다음",
      items=c(
        "판정: 구성-국한 부정(자본) — 신호 존재하나 문턱 미달, 프론티어 열림",
        "다음①: 가격충격변화(유일 동일가중 생존)를 상대기준 재측정·로테이션 소비",
        "다음②: 거래지속 역부호를 매도측 배제 오버레이로 소비(엄격 시점검증 대조)",
        "다음③: 마이크로스트럭처 × 비수익 내부자 데이터 결합(FQ-019, 백필 후)"))
  ),
  charts = charts,
  footer = "📚 L-AR-20260713_133212 · FQ-029 · prereg_sha256 8e9258a7 · n_trials 5(sweep) · vintage RAWDATA 323edc95"
)
cat("R16_TELEGRAM_DONE charts=", length(charts), "\n")
