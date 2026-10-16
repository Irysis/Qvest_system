## P3R03 시각 보고 — ① 누적 수익(엔진별 · KOSPI200 대비 · 정보 경계 표시) ② 위기 하락 포착 중앙값(변형 vs 같은 배치 RX0) ③ 증분 β 통제 알파(± 1.96 SE)
##   수치 = 계약 산출만(AX-008): 누적 = 측정 산출물 02_nav(nav_net) · 벤치 = 05_benchmark_returns(benchmark_nav) · ② ③ = evaluation.json(평가 계약값 그대로)
##   글꼴 = 현대하모니 M(도훈 10-15). 실행: Rscript visual_report.R → stage_artifacts/programs/P3_CONSTRUCTION/P3R03_advanced_construction/visual/
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2); library(ragg); library(systemfonts); library(patchwork) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RD  <- file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction")
OUT <- file.path(ROOT, "stage_artifacts/programs/P3_CONSTRUCTION/P3R03_advanced_construction/visual"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
TAU <- as.Date("2022-12-31")
fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
FAM <- if (is.na(fM)) "" else { systemfonts::register_font(name = "HDHM", plain = fM); "HDHM" }
th <- theme_minimal(base_family = FAM, base_size = 12) +
  theme(legend.position = "bottom", legend.title = element_blank(), panel.grid.minor = element_blank(),
        plot.title = element_text(size = 15), plot.subtitle = element_text(size = 10, colour = "#555555"),
        plot.caption = element_text(size = 8.5, colour = "#777777"), strip.text = element_text(size = 12))
ENG <- c(E2 = "E2 · DNN 원형", E3 = "E3 · B6_36(DNN 계보)")
MTH <- c(RX0 = "동일가중(RX0 · 기준)", HRP = "HRP", NCO = "NCO", MRE = "Michaud 재표집", CVR = "CVaR LP", ERC = "ERC")
PAL <- c("동일가중(RX0 · 기준)" = "#222222", HRP = "#1f77b4", NCO = "#ff7f0e", "Michaud 재표집" = "#2ca02c", "CVaR LP" = "#d62728", ERC = "#9467bd", KOSPI200 = "#9e9e9e")
ev <- fromJSON(file.path(RD, "results/evaluation.json"), simplifyVector = FALSE)
art <- function(code) fromJSON(file.path(RD, "results", paste0(code, ".json")))$artifacts

## ① 누적 수익
N <- rbindlist(lapply(names(ENG), function(e) rbindlist(lapply(names(MTH), function(m) {
  d <- fread(file.path(art(sprintf("P3R03_%s_%s", e, m)), "02_nav.csv"))[, .(date = as.Date(date), v = nav_net)]
  d[, `:=`(engine = ENG[[e]], who = MTH[[m]])] }))))
B <- rbindlist(lapply(names(ENG), function(e) fread(file.path(art(sprintf("P3R03_%s_RX0", e)), "05_benchmark_returns.csv"))[
  , .(date = as.Date(date), v = benchmark_nav, engine = ENG[[e]], who = "KOSPI200")]))
NB <- rbind(N, B); NB[, v := v / v[1], by = .(engine, who)]
NB[, who := factor(who, levels = names(PAL))]
g1 <- ggplot(NB, aes(date, v, colour = who)) + geom_line(linewidth = 0.55) +
  geom_vline(xintercept = TAU, linetype = "dashed", colour = "#888888") + facet_wrap(~engine, ncol = 1) +
  scale_y_log10() + scale_colour_manual(values = PAL) +
  labs(title = "P3R03 누적 수익 — 구성 5종 vs 같은 배치 RX0 vs KOSPI200",
       subtitle = "순수익(15bps) · 로그 축 · 점선 = 정보 경계 2022-12-31(판정은 그 왼쪽 · 오른쪽은 사람용 참고)",
       caption = "수치 = 측정 산출물 02_nav(nav_net) · 05_benchmark_returns(benchmark_nav)", x = NULL, y = "누적(시작 = 1)") + th
ggsave(file.path(OUT, "p3r03_cum_pnl.png"), g1, width = 7.2, height = 8.2, dpi = 150, device = ragg::agg_png)

## ② ③ 평가값
C <- rbindlist(lapply(ev$cells, function(z) data.table(
  engine = ENG[[z$engine]], method = MTH[[z$method]], verdict = z$verdict,
  cap_v = as.numeric(z$decisive$a_median$variant), cap_r = as.numeric(z$decisive$a_median$rx0),
  da = as.numeric(z$alpha_non_loss$d_alpha), se = as.numeric(z$alpha_non_loss$se),
  conc = as.character(z$concentration$status), attr = as.character(z$attribution$label))))
C[, method := factor(method, levels = MTH[-1])]
C[, mark := ifelse(verdict == "pass", "통과", ifelse(verdict == "mild_only", "완만한 위기만", "결정적 미달"))]
C2 <- rbind(C[, .(engine, method, kind = "변형", v = cap_v)], unique(C[, .(engine, method, kind = "RX0(기준)", v = cap_r)]))
g2 <- ggplot(C2, aes(method, v, fill = kind)) + geom_col(position = position_dodge(0.75), width = 0.7) +
  geom_text(aes(label = sprintf("%.2f", v)), position = position_dodge(0.75), vjust = -0.3, size = 3.2, family = FAM) +
  facet_wrap(~engine, ncol = 1) + scale_fill_manual(values = c("변형" = "#1f77b4", "RX0(기준)" = "#9e9e9e")) +
  labs(title = "위기 하락 포착 중앙값 — 낮을수록 방어(보는 창)", subtitle = "변형 vs 같은 배치 동일가중 RX0 · 위기 = KOSPI200 Lunde-Timmermann 20/20",
       caption = "수치 = evaluation.json decisive.a_median(평가 계약)", x = NULL, y = "하락 포착 중앙값") + th
g3 <- ggplot(C, aes(method, 100 * da, colour = mark)) + geom_hline(yintercept = 0, colour = "#444444") +
  geom_pointrange(aes(ymin = 100 * (da - 1.96 * se), ymax = 100 * (da + 1.96 * se)), size = 0.5) +
  facet_wrap(~engine, ncol = 1) + scale_colour_manual(values = c("통과" = "#2ca02c", "완만한 위기만" = "#ff7f0e", "결정적 미달" = "#d62728")) +
  labs(title = "증분 β 통제 알파 — 변형 − RX0(보는 창 · 연율 %)", subtitle = "점 = 추정 · 막대 = ± 1.96 SE · 색 = 판정",
       caption = "수치 = evaluation.json alpha_non_loss(계약 beta_controlled_alpha · NW lag 3)", x = NULL, y = "%/년") + th
ggsave(file.path(OUT, "p3r03_crisis_capture.png"), g2, width = 7.2, height = 7.5, dpi = 150, device = ragg::agg_png)
ggsave(file.path(OUT, "p3r03_incremental_alpha.png"), g3, width = 7.2, height = 7.5, dpi = 150, device = ragg::agg_png)
fwrite(C, file.path(OUT, "p3r03_cells.csv"))
cat("visual ok:", OUT, "\n")
