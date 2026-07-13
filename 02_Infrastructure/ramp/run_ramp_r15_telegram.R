## run_ramp_r15_telegram.R — R15 텔레그램 v7 판정 보고 (실측 시각화 의무, 원칙 9)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
RUNTAG <- "20260713"; OUTDIR <- "stage_artifacts/ramp_r15"
if(!dir.exists(OUTDIR)) dir.create(OUTDIR, recursive=TRUE)
TAB <- as.data.table(read_parquet(sprintf("outputs/ramp/r15_fill_gates_%s.parquet", RUNTAG)))
PAIRED <- as.data.table(read_parquet(sprintf("outputs/ramp/r15_fill_paired_%s.parquet", RUNTAG)))
bestpr <- readRDS(sprintf(".cache/_ramp_r15_bestpr_%s.rds", RUNTAG))
g <- function(m,c) TAB[model==m, get(c)]

## ── 서열 라벨(간결) ──
lab_map <- c(base_F1_level36fill="기본 F-1(수준)", armL1_fresh_fill="L-1 신선",
             armL2_nofill_shrink="L-2 무충원", armL3_consist_fill="L-3 일관성")
mods <- c("base_F1_level36fill","armL3_consist_fill","armL1_fresh_fill","armL2_nofill_shrink")

## ── 차트 1: cap-w 이중 서열 (2차 endpoint, hline 2.95) ──
capw_vals <- sapply(mods, function(m) g(m,"port_t_capwt"))
c1 <- tg_chart_sweep(labels=unname(lab_map[mods]), values=unname(capw_vals), out_dir=OUTDIR,
        title="R15 충원 규율 — cap-w PORT_t (자본 문턱 2.95)", value_label="cap-w PORT_t",
        hline=2.95, hline_label="자본", highlight="기본 F-1(수준)", filename="sweep_capw.png")

## ── 차트 2: oos 이중 서열 (1차 endpoint, hline 0.7) ──
oos_vals <- sapply(mods, function(m) g(m,"oos_retention"))
c2 <- tg_chart_sweep(labels=unname(lab_map[mods]), values=unname(oos_vals), out_dir=OUTDIR,
        title="R15 충원 규율 — 표본외 유지율 oos (합격 0.7)", value_label="oos_retention",
        hline=0.7, hline_label="합격", highlight="기본 F-1(수준)", filename="sweep_oos.png")

## ── 차트 3~5: 최선 cap-w arm(L-3 일관성) 표준 3종 vs BM ──
pr <- bestpr$period_returns
pack <- tg_chart_pack(pr, out_dir=OUTDIR, title="R15 최선 대안 L-3(일관성-fill)",
        metrics_note="cap-w 2.890 · oos +0.079 · EW-uni oos 0.675 (weighted_screen_bt · HARD 0/5)",
        prefix="L3_")

charts <- c(c1, c2, pack)

## ── 텔레그램 v7 발송 ──
tg_agent_brief(
  agent = "Q-Lead",
  title = "RAMP R15 충원(fill) 규율 실험 — 기본 방법이 이미 최적 확인",
  sections = list(
    list(type="summary", emoji="📌",
      body="포트폴리오 빈자리를 어떤 팩터로 메울지 4가지 규칙을 22년치로 비교 — 현재 기본 규칙이 이미 최적임을 확인, 새 자본 배정 없음."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "시도: 팩터를 교체할 때 빈자리를 무엇으로 채우는지 4가지 방법(과거3년 수준/최근 신선함/안 채우기/일관성)을 비교",
        "방법: 진입·퇴출 규칙은 챔피언 전략에 고정하고 '충원 방법만' 바꿔 257개월 모의 운용(백테스팅)",
        "결과: 어떤 충원 방법도 기존 기본(과거3년 성과 상위로 채우기)을 넘지 못함",
        "의미: 챔피언 전략이 이미 최선의 충원을 쓰고 있었음을 확인 — 실제 돈은 넣지 않습니다")),
    list(type="kv", emoji="📊", heading="핵심 수치 (이중 서열)",
      kv=list(
        "기본안"      = "cap-w 2.937 (F-1 챔피언 기준)",
        "최선 대안"   = "cap-w 2.890 (L-3 일관성, 하회)",
        "표본외 유지" = "oos +0.079 (L-3 최고, 기준 +0.048)",
        "자본 문턱"   = "cap-w 전부 2.95 미만 = 미달",
        "기준 대비"   = "쌍대 t −0.38 (유의차 없음)")),
    list(type="bullet", emoji="🚩", heading="주의",
      items=c(
        "충원은 분기당 팩터 ~2개만 바꾸는 저빈도 다이얼 — 전 방법 pool 94~96% 동일(검정력 한계 정직 병기)",
        "IS 구간 승자(무-fill)는 전체구간 최악 — 챔피언십 규율이 잡음 승자를 자본 격리",
        "선별·퇴출·충원 = construction 3대 축 모두 동일 천장 수렴 (수익-파생 재료 소진 지대)")),
    list(type="bullet", emoji="➡️", heading="판정 · 다음",
      items=c(
        "판정: config-scoped negative — 이 충원 규율 실험엔 실제 자본 배정 없음(참고 지식만 적립·종결 아님)",
        "다음①: 검증된 챔피언 구성을 비-수익 데이터(DART 임원 매매)에 이식 (insider 백필 완료 후)",
        "다음②: L-3(일관성-fill)의 EW-기준 이득을 배포성 결정재료로 재분류 검토"))
  ),
  charts = charts,
  footer = "📚 L-RAMP-20260713_112544 · FQ-028 · config_hash 7f5855e1dc0ce7e4 · n_trials 계보 30"
)
cat("R15_TELEGRAM_DONE charts=", length(charts), "\n")
cat(paste(charts, collapse="\n"), "\n")
