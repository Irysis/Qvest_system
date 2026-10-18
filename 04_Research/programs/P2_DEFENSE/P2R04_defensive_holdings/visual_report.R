## P2R04 시각 보고 — ① 누적 수익(엔진별 · 방어 틸트 4종 vs 같은 배치 RX0 vs KOSPI200 · 정보 경계 표시) ② 위기 방어 과반 비율(① 위기 개선 · ③ 깊은 위기 β 짝 ·
##   크기 × β 짝 · ④ 빠른 급락 β 짝) ③ 증분 β 통제 알파(± 1.96 SE). 수치 = 계약 산출만(AX-008): 누적 = 측정 산출물 02_nav(nav_net) · 벤치 = 05_benchmark_returns ·
##   ② ③ · 표 = evaluation_visible.json(평가 계약값 그대로 · 보는 창). 사람 쪽 보고용 — 철학 P2 · 판단 Superfan 에게는 이 차트를 주지 않는다(① 은 전기간).
##   P2R03 visual_report.R 와 같은 틀(장치 이름 · 판정 어휘 · 크기 × β 짝 막대만 다름). 글꼴 = 현대하모니 M(도훈 10-15).
##   실행: Rscript visual_report.R → stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings/visual/
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2); library(ragg); library(systemfonts) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
RD  <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings")
SA  <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings")
OUT <- file.path(SA, "visual"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
TAU <- as.Date("2022-12-31")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
num <- function(x) if (is.null(x) || !length(x)) NA_real_ else suppressWarnings(as.numeric(x[[1]]))
fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
FAM <- if (is.na(fM)) "" else { systemfonts::register_font(name = "HDHM", plain = fM); "HDHM" }
th <- theme_minimal(base_family = FAM, base_size = 12) +
  theme(legend.position = "bottom", legend.title = element_blank(), panel.grid.minor = element_blank(),
        plot.title = element_text(size = 15), plot.subtitle = element_text(size = 10, colour = "#555555"),
        plot.caption = element_text(size = 8.5, colour = "#777777"), strip.text = element_text(size = 12))
ENG <- c(E2 = "E2 · DNN 원형(동일가중)", E3 = "E3 · B6_36(DNN+3팩터 · 버퍼 2배)")
DEV <- c(H1 = "H1 하방β(D04)", H2 = "H2 저변동(D03)", H3 = "H3 β 비대칭(D07)", H4 = "H4 퀄리티(Q08)")
PAL <- c("RX0(기준 · 엔진 자체 구성)" = "#111111", setNames(c("#1f77b4", "#2ca02c", "#ff7f0e", "#9467bd"), DEV), KOSPI200 = "#a0a0a0")
VLAB <- c(pass = "통과", exposure_only = "노출(β) 방어뿐", slow_only = "느린 약세만", defense_but_strength_or_path = "방어 O · 강세/알파/경로 미달",
          not_decisive = "결정적 미달", beta_unmeasured = "β 짝 미측정", fast_unmeasured = "빠른 급락 미측정", selection_unmeasured = "선택 귀속 미측정",
          untested = "미시험")
VPAL <- c("통과" = "#2ca02c", "노출(β) 방어뿐" = "#ff7f0e", "느린 약세만" = "#bcbd22", "방어 O · 강세/알파/경로 미달" = "#17becf",
          "결정적 미달" = "#d62728", "β 짝 미측정" = "#7f7f7f", "빠른 급락 미측정" = "#7f7f7f", "선택 귀속 미측정" = "#7f7f7f", "미시험" = "#c7c7c7")
ev  <- fromJSON(file.path(RD, "results/evaluation_visible.json"), simplifyVector = FALSE)
art <- function(code) fromJSON(file.path(RD, "results", paste0(code, ".json")))$artifacts

## ① 누적 수익(전기간 · 사람용)
N <- rbindlist(lapply(names(ENG), function(e) rbindlist(lapply(c("RX0", names(DEV)), function(d) {
  f <- file.path(art(sprintf("P2R04_%s_%s", e, d)), "02_nav.csv"); if (!file.exists(f)) return(NULL)
  x <- fread(f)[, .(date = as.Date(date), v = nav_net)]
  x[, `:=`(engine = ENG[[e]], who = if (d == "RX0") names(PAL)[1] else DEV[[d]])] }))))
B <- rbindlist(lapply(names(ENG), function(e) fread(file.path(art(sprintf("P2R04_%s_RX0", e)), "05_benchmark_returns.csv"))[
  , .(date = as.Date(date), v = benchmark_nav, engine = ENG[[e]], who = "KOSPI200")]))
NB <- rbind(N, B); NB <- NB[is.finite(v) & v > 0]; NB[, v := v / v[1], by = .(engine, who)]
NB[, who := factor(who, levels = names(PAL))]
g1 <- ggplot(NB, aes(date, v, colour = who, linewidth = who == names(PAL)[1])) + geom_line() +
  scale_linewidth_manual(values = c(`TRUE` = 0.85, `FALSE` = 0.45), guide = "none") +
  geom_vline(xintercept = TAU, linetype = "dashed", colour = "#888888") + facet_wrap(~engine, ncol = 1) +
  scale_y_log10() + scale_colour_manual(values = PAL) + guides(colour = guide_legend(nrow = 2)) +
  labs(title = "P2R04 누적 수익 — 방어 틸트 4종 vs 같은 배치 RX0 vs KOSPI200",
       subtitle = "순수익(15bps) · 로그 축 · 점선 = 정보 경계 2022-12-31(판정은 그 왼쪽 · 오른쪽은 사람용 참고)",
       caption = "수치 = 측정 산출물 02_nav(nav_net) · 05_benchmark_returns(benchmark_nav)", x = NULL, y = "누적(시작 = 1)") + th
ggsave(file.path(OUT, "p2r04_cum_pnl.png"), g1, width = 7.4, height = 8.6, dpi = 150, device = ragg::agg_png)

## 칸 표(보는 창 평가값 그대로 · 판정 칸 8)
C <- rbindlist(lapply(Filter(function(z) identical(z$role, "judge"), ev$cells), function(z) {
  R <- z$rules %||% list(); A <- z$alpha_non_loss %||% list(); NI <- z$non_inferiority %||% list(); BA <- R$beta_asym %||% list()
  SB <- z$size_beta %||% list(); SD <- R$selection$decomposition %||% list(); HO <- z$holdings_overlap %||% list()
  RM <- z$regime_months %||% list(); FD <- z$construction$factor_direction %||% list(); RP <- z$reference_points %||% list()
  data.table(engine = ENG[[z$engine]], dev = z$device, device = DEV[[z$device]], factor = z$device_factor$id %||% NA_character_,
             verdict = VLAB[[z$verdict %||% "untested"]] %||% z$verdict, tested = isTRUE(z$tested),
             crisis = num(R$crisis$share), n_crisis = num(R$crisis$n_pair), deep = num(R$deep$share), n_deep = num(R$deep$n_pair),
             beta_deep = num(R$beta_deep$share), n_beta_deep = num(R$beta_deep$n_pair),
             size_beta = num(SB$share), n_size_beta = num(SB$n_pair), beta_variant = num(SB$beta_variant),
             fast = num(R$fast$share), n_fast = num(R$fast$n_pair), slow = num(R$slow$share), n_slow = num(R$slow$n_pair),
             beta_ratio = num(BA$ratio), beta_ratio_rx0 = num(BA$ratio_rx0),
             bull_share = num(R$bull$share), n_bull = num(R$bull$n_pair), uc_median = num(R$bull$uc_median), cycle = num(R$cycle$share), n_cycle = num(R$cycle$n_pair),
             sel_label = as.character(R$selection$label %||% NA)[1], sel_decomp = num(SD$share), n_sel_decomp = num(SD$n_pair),
             market_deep = num(RP$market$deep$share), market_deep_rx0 = num(RP$market_rx0$deep$share),
             da = num(A$d_alpha), se = num(A$se), alpha_t = num(A$t), S = num(NI$S), S_rx0 = num(NI$S_rx0),
             name_overlap = num(HO$name_overlap_mean), m_crisis = num(RM$crisis$mean), m_bull = num(RM$bull$mean), m_other = num(RM$other$mean),
             dir_ic = num(FD$ic_inferred), dir_registry = num(FD$registry_fallback), dir_default = num(FD$default_fallback), dir_n = num(FD$n_sig),
             conc = as.character(z$concentration$status %||% NA)[1], attr = as.character(z$attribution$label %||% NA)[1])
}), fill = TRUE)
C[, device := factor(device, levels = DEV)]; C[, verdict := factor(verdict, levels = names(VPAL))]
fwrite(C, file.path(OUT, "p2r04_cells.csv"))

## ② 위기 방어 과반 비율(보는 창)
MAJ <- num(fromJSON(file.path(SA, "prereg.json"), simplifyVector = FALSE)$final_selection_rule$majority_share)
RL <- c("① 위기 개선(vs RX0)", "③ 깊은 위기 vs β 짝", "깊은 위기 vs 크기 × β 짝(기록)", "④ 빠른 급락 vs β 짝")
C2 <- melt(C[, setNames(list(engine, device, crisis, beta_deep, size_beta, fast), c("engine", "device", RL))],
           id.vars = c("engine", "device"), variable.name = "rule", value.name = "share")
g2 <- ggplot(C2, aes(device, share, fill = rule)) + geom_col(position = position_dodge(0.84), width = 0.8, na.rm = TRUE) +
  geom_hline(yintercept = MAJ, linetype = "dashed", colour = "#444444") +
  geom_text(aes(y = 0.03, group = rule, label = ifelse(is.na(share), "미측정", ifelse(share == 0, "0", ""))),
            position = position_dodge(0.84), size = 2.8, family = FAM, colour = "#555555") +
  facet_wrap(~engine, ncol = 1) + scale_y_continuous(limits = c(0, 1)) +
  scale_fill_manual(values = setNames(c("#9ecae1", "#3182bd", "#bdbdbd", "#08519c"), RL)) + guides(fill = guide_legend(nrow = 2)) +
  labs(title = "위기 방어 — 더 덜 빠진 위기의 비율(보는 창)",
       subtitle = sprintf("점선 = 과반 문턱 %.2f · β 짝 = RX0 를 같은 β 로 낮추고 나머지는 현금으로 둔 사본(그걸 넘어야 '무엇을 드느냐'의 방어)", MAJ),
       caption = "수치 = evaluation_visible.json rules.crisis · beta_deep · fast · size_beta(평가 계약) · 위기 = KOSPI200 Lunde-Timmermann 20/20", x = NULL, y = "비율") +
  th + theme(axis.text.x = element_text(angle = 20, hjust = 1))
ggsave(file.path(OUT, "p2r04_crisis_defense.png"), g2, width = 7.6, height = 8.0, dpi = 150, device = ragg::agg_png)

## ③ 증분 β 통제 알파(보는 창)
g3 <- ggplot(C[is.finite(da)], aes(device, 100 * da, colour = verdict)) + geom_hline(yintercept = 0, colour = "#444444") +
  geom_pointrange(aes(ymin = 100 * (da - 1.96 * se), ymax = 100 * (da + 1.96 * se)), size = 0.45, na.rm = TRUE) +
  facet_wrap(~engine, ncol = 1) + scale_colour_manual(values = VPAL, drop = TRUE) +
  labs(title = "증분 β 통제 알파 — 변형 − RX0(보는 창 · 연율 %)", subtitle = "점 = 추정 · 막대 = ± 1.96 SE · 색 = 판정",
       caption = "수치 = evaluation_visible.json alpha_non_loss(계약 beta_controlled_alpha)", x = NULL, y = "%/년") +
  th + theme(axis.text.x = element_text(angle = 20, hjust = 1))
ggsave(file.path(OUT, "p2r04_incremental_alpha.png"), g3, width = 7.4, height = 7.6, dpi = 150, device = ragg::agg_png)
cat("visual ok:", OUT, "· 칸", nrow(C), "· 판정", ev$verdict_label %||% ev$verdict, "\n")
