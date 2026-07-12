## run_ramp_r10_telegram.R — R10 판정 텔레그램 v7 보고 (원칙 9 실측 시각화 의무)
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/tg_chart_pack.R")
source("02_Infrastructure/telegram/telegram_notify.R")
RUNTAG <- "20260713"; OUTDIR <- "stage_artifacts/ramp_r10"; dir.create(OUTDIR, recursive=TRUE, showWarnings=FALSE)

TAB <- as.data.table(read_parquet(sprintf("outputs/ramp/r10_weighting_gates_%s.parquet", RUNTAG)))
PAIRED <- as.data.table(read_parquet(sprintf("outputs/ramp/r10_weighting_paired_%s.parquet", RUNTAG)))
bestpr <- readRDS(sprintf(".cache/_ramp_r10_bestpr_%s.rds", RUNTAG))

pget <- function(m) TAB[model==m]
base <- pget("base"); ws <- pget("W_stock"); wsq <- pget("W_stock_sqrt"); wf_ <- pget("W_factor"); wb <- pget("W_both")

## ── 차트 1: config 서열 sweep (paired cap-w vs base, hline 2.0) ──
pc <- PAIRED[basis=="act_bm"]
sweep_lab <- c("W_stock\n(종목 z-비례)","W_factor\n(팩터 성과비례)","W_both","W_stock_sqrt\n(완만화)")
sweep_val <- c(pc[model=="W_stock",paired_t], pc[model=="W_factor",paired_t],
               pc[model=="W_both",paired_t], pc[model=="W_stock_sqrt",paired_t])
p_sweep <- tg_chart_sweep(sweep_lab, sweep_val, OUTDIR,
  title="R10 비중 변형 vs P-pure EW — paired NW-t (cap-w active)",
  value_label="paired NW-t (문턱 2.0)", hline=2.0, hline_label="KILL 문턱",
  highlight="W_stock_sqrt\n(완만화)", filename="r10_sweep_paired.png")

## ── 차트 2: W_stock(최고 cap-w 헤드라인) 표준 3종 ──
rds <- readRDS(sprintf(".cache/_ramp_r10_%s.rds", RUNTAG))
PRl <- rds$PR
BENCH <- unique(as.data.table(rds$PR[["base"]])[,.(date, benchmark_ret)])
ws_pr <- merge(as.data.table(PRl[["W_stock"]])[,.(date, ret_net)], BENCH, by="date")
p_pack <- tg_chart_pack(ws_pr, OUTDIR,
  title="R10 W_stock (종목 점수-비례 틸트)",
  metrics_note=sprintf("cap-w PORT_t %.2f · oos %+.2f · calmar %.2f · paired vs EW %+.2f (canonical)",
    ws$port_t_capwt, ws$oos_retention, ws$calmar, pc[model=="W_stock",paired_t]),
  prefix="wstock_")

charts <- c(p_sweep, p_pack)
cat("charts:\n"); cat(charts, sep="\n"); cat("\n")

## ── 텔레그램 v7 브리핑 ──
tg_agent_brief(
  agent = "Q-Lead",
  title = "RAMP R10 · P-pure 비중 고도화 (동일가중 vs 점수-비례) — 개선 방향성만, 자본 판정 불변",
  sections = list(
    list(type="summary", emoji="📌",
      body="P-pure 전략의 종목 비중을 '동일가중'에서 '점수 비례'로 바꿔봤습니다. 성과는 소폭 올랐지만 우연과 구별될 만큼은 아니어서 동일가중을 그대로 유지합니다."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "시도: 25개 종목에 똑같이 나눠 담던 것을, 신호 점수가 높은 종목에 더 실어봤습니다",
        "방법: 과거 20년(220개월) 데이터로 모의 운용(백테스팅), 거래비용까지 반영했습니다",
        "결과: 신호 강도(다중검정 t값)가 2.61에서 2.93으로 올랐지만 합격선 2.95엔 못 미쳤습니다",
        "의미: 방향은 맞지만 통계적으로 확실하진 않아, 실제 자본 배분 방식은 그대로 둡니다")),
    list(type="kv", emoji="📊", heading="핵심 비교 (벤치 대비 다중검정 t값)",
      kv=list(
        "동일가중 기준"=sprintf("%.2f", base$port_t_capwt),
        "종목 점수비례"=sprintf("%.2f", ws$port_t_capwt),
        "기준대비 검정"=sprintf("%.2f (문턱 2.0)", pc[model=="W_stock",paired_t]),
        "팩터 성과비례"=sprintf("%.2f (악화)", wf_$port_t_capwt),
        "유효 종목수"=sprintf("25 → %.0f개", rds$CONC[model=="W_stock", n_eff][1])) ),
    list(type="bullet", emoji="🚩", heading="주의",
      items=c(
        "어느 변형도 paired NW-t 2.0 문턱 미달 (최고 1.78) → 사전등록 KILL 발동",
        "소형주 농축 아님: 소형(OTHER) 비중 0.906→0.912 거의 불변",
        "팩터를 성과순으로 가중하면 오히려 악화 = 팩터 모멘텀 타이밍 무효 재확인")),
    list(type="bullet", emoji="➡️", heading="판정과 다음",
      items=c(
        "판정: 비중 축 소진 — P-pure는 동일가중 유지 확정 (자본 판정 불변)",
        "돈 관점: 실제 자본 배분 규칙은 바뀌지 않습니다 (참고 지식만 적립)",
        "잔존 lever: 점수-비례는 방향성 양(+)의 가장 순한 레버 — 비-수익 패널서 재적용 가치"))
  ),
  charts = charts
)
cat("R10_TELEGRAM_DONE\n")
