## _r7_charts_telegram.R — R7 실측 차트팩 + 텔레그램 v7 판정 보고 (원칙 9 의무)
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=QM); setwd(QM)
source("02_Infrastructure/telegram/tg_chart_pack.R")
source("02_Infrastructure/telegram/telegram_notify.R")

r7 <- readRDS(".cache/_ramp_r7_20260712.rds")
TAB <- as.data.table(r7$TAB); PR <- r7$PR; E2 <- r7$E2; PAIRED <- as.data.table(r7$PAIRED)
outdir <- "stage_artifacts/r7_ewbasis"; if(!dir.exists(outdir)) dir.create(outdir, recursive=TRUE)

## ── 차트 1: E1 라벨교체 paired NW-t 서열 (hline=2.0) ──
ps <- PAIRED[kind=="labelswap_vs_capwrepro"]
c1 <- tg_chart_sweep(
  labels = sub("Epure_EW_","E1 ",ps$model), values = ps$paired_t,
  out_dir = outdir, title = "R7 E1 라벨교체 효과 (EW선별 vs cap-w선별, paired NW-t)",
  value_label = "paired NW-t (>0 = EW라벨 우위)", hline = 2.0, hline_label = "kill 문턱",
  filename = "e1_paired_sweep.png")

## ── 차트 2: 8-arm cap-w PORT_t 서열 (hline=2.95 graduation) ──
armt <- TAB[grepl("^capwrepro_|^Epure_EW_", model), .(model, port_t_capwt)]
armt[, lab := sub("capwrepro_","cap-w선별 ",sub("Epure_EW_","EW선별 ",model))]
c2 <- tg_chart_sweep(
  labels = armt$lab, values = armt$port_t_capwt,
  out_dir = outdir, title = "R7 8-arm cap-w PORT_t (선별라벨×창×K)",
  value_label = "cap-w PORT_t (다중검정 t값)", hline = 2.95, hline_label = "자본 졸업",
  highlight = "cap-w선별 W36_K20", filename = "arm_capwt_sweep.png")

## ── 차트 3: E2 cap-tier 비중 (알파 국소화) ──
ws <- E2$cap_tier$weight_share_avg
c3 <- tg_chart_sweep(
  labels = c("MEGA (시총 1-10위)","MID (11-30위)","OTHER (31위+ 소형지수주)"),
  values = c(ws$MEGA, ws$MID, ws$OTHER)*100,
  out_dir = outdir, title = "R7 E2 R6최선전략 보유 cap-tier 비중 (전기간 평균)",
  value_label = "평균 보유비중 (%)", highlight = "OTHER (31위+ 소형지수주)",
  filename = "e2_captier_wshare.png")

## ── 차트 4: E2 basis별 post-2017 대조 (감쇠=cap-w 아티팩트 시각화) ──
c4 <- tg_chart_sweep(
  labels = c("cap-w PORT_t(전기간)","EW-uni PORT_t(전기간)","cap-w post2017 SR","EW post2017 SR","cap-w oos유지율","EW oos유지율"),
  values = c(2.61, 3.92, -0.11, 0.49, -0.08, 0.51),
  out_dir = outdir, title = "R7 E2 dual-basis 대조 (cap-w vs EW-유니버스)",
  value_label = "지표값 (basis별)", hline = 0, filename = "e2_dualbasis.png")

## ── 차트 5~7: 최선 특성화 대상(capwrepro_W36_K20=R6 best) 표준 3종 ──
pr <- as.data.frame(PR[["capwrepro_W36_K20"]])
std <- tg_chart_pack(pr, out_dir = outdir,
  title = "R6최선 팩터배분(Ppure W36 K20)",
  date_col="date", ret_col="ret_net", bm_col="benchmark_ret", bm_label="KOSPI200(cap-w)",
  metrics_note = "cap-w PORT_t 2.61·oos -0.08·calmar 0.45 (자본미달) | EW-uni 3.92·EW post17 SR +0.49",
  prefix = "best_")

charts <- c(c1, c2, c3, c4, std)
cat("charts:\n"); cat(paste(charts, collapse="\n"), "\n")

## ── 텔레그램 v7 판정 보고 ──
tg_agent_brief(
  agent = "Q-Lead",
  title = "RAMP R7 팩터 선별 기준 교체 실험 — 성과 개선 실패, 알파의 소형주 국소화 확인",
  sections = list(
    list(type="summary", emoji="📌",
      body="팩터 선별 잣대를 동일가중 벤치로 바꿔도 성과는 안 늘었고, 대신 이 전략 알파가 소형주에 90% 몰려있음을 확인했습니다."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "시도: 팩터(종목 고르는 신호)를 '어느 잣대로 잘했다고 볼지'를 대형주중심에서 동일가중으로 바꿔 다시 골라봤습니다",
        "방법: 과거 20년(2005~) 데이터로 4가지 설정을 모의 운용(백테스팅)하고 기존 방식과 짝지어 비교했습니다",
        "결과: 잣대를 바꿔도 실제 성과는 안 늘었습니다(오히려 최강 설정은 2.61→1.99로 하락) — 병목이 '잣대'가 아니었습니다",
        "의미: 진짜 병목은 이 전략이 소형주에 90% 몰려있는데 성과를 대형주 지수와 비교당하는 구조 — 실제 돈은 넣지 않습니다"),
      relaxed=FALSE),
    list(type="kv", emoji="📊", heading="핵심 수치 (R6최선전략)",
      kv=list("cap-w 다중검정 t값"="2.61 (자본기준 2.95 미달)",
              "EW-uni 다중검정 t값"="3.92 (대형주벤치 제거시)",
              "cap-w post2017 SR"="-0.11 (부진)",
              "EW post2017 SR"="+0.49 (실은 양호)",
              "소형주(OTHER) 보유비중"="90.6%")),
    list(type="bullet", emoji="🚩", heading="주의",
      items=c(
        "라벨교체 4설정 전부 짝비교 t값 <2.0 (최대 +1.23) → 선별잣대 축 소진",
        "EW기준서 초과수익은 실재하나 표본외 유지율 0.51<0.7 → 배포 결정기준도 미달",
        "소형주 90% 집중 = 대형자금 담기엔 수용력(capacity) 제약",
        "vintage 무오염 확인: R6 재현 완전일치(Δ0)·April-gap 백필이 패널기간 벤치 불변")),
    list(type="bullet", emoji="➡️", heading="다음 / 판정",
      items=c(
        "판정: 실제 자본 배정 안 함 — 참고용(스크린 등급)으로만 보관합니다",
        "선별 잣대 교체 갈래 종결 — 병목은 잣대 아닌 소형주 국소화 × 벤치 불일치",
        "남은 탐색: 실현성과 정렬 선별 × 비-수익 데이터(공시 내부자거래 등)",
        "교훈코드 L-RAMP-20260712_161537 적립 (누적 시도 20회)"))
  ),
  charts = charts
)
cat("TG_DONE\n")
