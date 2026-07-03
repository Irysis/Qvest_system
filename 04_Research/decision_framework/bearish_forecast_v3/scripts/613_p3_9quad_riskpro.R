#!/usr/bin/env Rscript
#==============================================================================
# 613_p3_9quad_riskpro.R — P3 9-Quadrant Risk Manager Pro Dashboard
#
# 도훈 mandate 2026-05-27:
# 리스크 전문가 관점 원포인트 차트:
#   - Main 9-Quadrant (KTRI 점 규칙) + 60d trail
#   - NOW badge 확장: σ/λ/μ/ν/VaR + Risk Score + decision rule
#   - 우측 sidebar: VaR/P(-5%)/Risk Score 60d timeline (sparkline)
#   - 하단: 현재 cell historical stats + recommended action box
#==============================================================================

# ── UTF-8 locale 가드 (2026-06-25) ───────────────────────────────────────────
# 스케줄러(Task Scheduler)는 LC_ALL/LANG=C 로 Rscript 를 띄운다. 이 스크립트의 한글
#   리터럴(zone명 "위기" 등)은 UTF-8 바이트로 보존되나, C locale 에선 ragg 렌더 백엔드가
#   이를 UTF-8 로 해석하지 못해 폰트가 있어도 □(tofu)로 깨진다(실측: C 실행=tofu / UTF-8=정상).
#   런타임 LC_CTYPE 를 UTF-8 로 강제하면 "unknown"-encoding UTF-8 바이트가 정상 매핑된다.
local({
  if (grepl("utf-?8", Sys.getlocale("LC_CTYPE"), ignore.case = TRUE)) return(invisible())
  for (loc in c("English_United States.utf8", "Korean_Korea.utf8",
                "English_United States.1252", "C.UTF-8", "en_US.UTF-8")) {
    if (nzchar(suppressWarnings(tryCatch(Sys.setlocale("LC_CTYPE", loc),
                                         error = function(e) "")))) break
  }
})

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(dplyr)
  library(ggplot2)
  library(scales)
  library(patchwork)
})

# ── 한글 폰트 (Malgun Gothic) — ragg/systemfonts 경유 렌더 (2026-06-25) ──────
# 미설정 시 ggplot 기본 sans(Arial)에 한글 글리프가 없어 모든 한글이 □(tofu)로 깨진다(실측:
#   9-Quadrant zone명·NOW/ACTION 라벨·하단 cell 통계 전부 tofu). ggsave 백엔드(ragg)는
#   systemfonts 로 폰트 해석 → family 명을 Malgun Gothic 으로 지정하면 정상 렌더.
# geom_text/geom_label/annotate 는 theme base_family 를 상속하지 않으므로 geom default 도 강제.
.KOR_FONT <- "Malgun Gothic"
{
  .fams <- tryCatch(unique(systemfonts::system_fonts()$family), error = function(e) character(0))
  if (length(.fams) && !(.KOR_FONT %in% .fams)) {
    .alt <- .fams[grepl("Malgun|Nanum|Gulim|Dotum|Batang|AppleGothic|Gothic A", .fams, ignore.case = TRUE)]
    if (length(.alt)) .KOR_FONT <- .alt[1]
  }
}
update_geom_defaults("text",  list(family = .KOR_FONT))
update_geom_defaults("label", list(family = .KOR_FONT))
cat(sprintf("[riskpro] 한글 폰트 family = %s\n", .KOR_FONT))

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
args <- commandArgs(trailingOnly = TRUE)
src_path <- if (length(args) >= 1) args[1] else file.path(
  PROJECT_ROOT,
  # ⑤ 2026-06-01 도훈: stale all_predictions(5/25 고정) base 은퇴 → P3_daily(full history + daily fresh) 단일 소스.
  "04_Research/decision_framework/bearish_forecast_v3/03_models/daily_predictions/P3_daily.parquet"
)

# σ 임계 SIGMA_LOW/SIGMA_HIGH 와 XLIM 은 데이터 구동(아래 P3 load 후 terciles) — 고정 1.0/1.8 은
#   σ 스케일 드리프트로 S_Low 행(잠재폭발/평온/안정강세)이 항상 0관측(현 σ min 1.11)→하단 셀
#   수익/변동 'n/a' 로 표시되던 버그 수리(2026-06-29 도훈).
LAM_BEAR   <- -0.10
LAM_BULL   <-  0.10
YLIM <- c(-0.5, 0.5)

# ── 1. Load P3 ──────────────────────────────────────────────────────────────
dat <- as.data.table(read_parquet(src_path))
dat[, Date := as.Date(Date)]
setorder(dat, Date)
daily_path <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v3/03_models/daily_predictions/P3_daily.parquet")
if (file.exists(daily_path)) {
  daily <- as.data.table(read_parquet(daily_path))
  daily[, Date := as.Date(Date)]
  new_rows <- daily[!Date %in% dat$Date]
  if (nrow(new_rows) > 0) {
    common_cols <- intersect(names(dat), names(daily))
    dat <- rbindlist(list(dat[, ..common_cols], new_rows[, ..common_cols]), use.names = TRUE)
    setorder(dat, Date)
  }
}

# ── σ 분위 구동 임계 (2026-06-29 도훈) ───────────────────────────────────────
# 고정 1.0/1.8 은 P3 σ 스케일(현 분포 ~1.1~5.4, median 2.9)에 미달 → 90/99 가 S_High 한 행에 몰리고
#   S_Low 행(잠재폭발/평온/안정강세)은 관측 0 → 하단 셀 수익/변동이 'n/a'. 경험분포 terciles 로 전환해
#   3개 σ 국면이 항상 채워지게 한다(λ 는 절대 임계 −0.10/+0.10 유지 — 이미 3행 모두 관측).
.sig_q <- as.numeric(stats::quantile(dat$sigma, c(1/3, 2/3), na.rm = TRUE))
SIGMA_LOW  <- round(.sig_q[1], 2)
SIGMA_HIGH <- round(.sig_q[2], 2)
if (!is.finite(SIGMA_LOW) || !is.finite(SIGMA_HIGH) || SIGMA_LOW >= SIGMA_HIGH) {
  SIGMA_LOW <- 1.0; SIGMA_HIGH <- 1.8   # degenerate fallback (구 고정값)
}
XLIM <- c(0, max(5, ceiling(max(dat$sigma, na.rm = TRUE))))
cat(sprintf("[riskpro] σ tercile 임계: S_Low<%.2f | S_Mid | S_High>=%.2f (XLIM up=%.1f)\n",
            SIGMA_LOW, SIGMA_HIGH, XLIM[2]))

dat[, sigma_bin := cut(sigma, breaks=c(-Inf, SIGMA_LOW, SIGMA_HIGH, Inf),
                       labels=c("S_Low","S_Mid","S_High"), right=FALSE)]
dat[, lam_bin := cut(lam, breaks=c(-Inf, LAM_BEAR, LAM_BULL, Inf),
                     labels=c("L_Bear","L_Neutral","L_Bull"), right=FALSE)]
dat[, sigma_plot := pmin(pmax(sigma, XLIM[1]), XLIM[2])]
dat[, lam_plot   := pmin(pmax(lam, YLIM[1]), YLIM[2])]

# fwd 22d
dat[, y_cum := cumsum(ifelse(is.na(y_actual), 0, y_actual))]
dat[, fwd22 := shift(y_cum, n = -22, type = "lag") - y_cum]
dat[Date > (max(Date) - 22), fwd22 := NA_real_]

# Risk score (expanding z + clip ±3 + composite + VaR_05)
expanding_z <- function(x, min_obs=60L) {
  n <- length(x); out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i < min_obs) next
    v <- x[1:i]; m <- mean(v, na.rm=TRUE); s <- sd(v, na.rm=TRUE)
    if (is.na(s) || s == 0) next
    out[i] <- (x[i] - m) / s
  }
  out
}
clip_z <- function(z, cap=3) pmin(pmax(z, -cap), cap)
dat[, z_sigma   := clip_z(expanding_z(sigma))]
dat[, z_lam     := clip_z(expanding_z(lam))]
dat[, z_mu      := clip_z(expanding_z(mu))]
dat[, z_inv_nu  := clip_z(expanding_z(1 / pmax(nu, 1)))]
dat[, z_var05   := clip_z(expanding_z(var_05))]
dat[, risk_raw  := 0.7*z_sigma + 0.5*(-z_lam) + 0.3*(-z_mu) + 0.3*z_inv_nu + 0.4*(-z_var05)]
dat[, risk_score := pmin(pmax(3.0 + risk_raw, 1.0), 5.0)]

zone_map <- list(
  S_Low_L_Bear     = list(zone="잠재 폭발",      fill="#FFE0B2", action="모니터링 강화"),
  S_Low_L_Neutral  = list(zone="평온",          fill="#E3F2FD", action="표준 운용"),
  S_Low_L_Bull     = list(zone="안정 강세",      fill="#E8F5E9", action="표준 운용"),
  S_Mid_L_Bear     = list(zone="약세 진행",      fill="#FBE9E7", action="defensive +10%"),
  S_Mid_L_Neutral  = list(zone="보통",          fill="#FAFAFA", action="표준 운용"),
  S_Mid_L_Bull     = list(zone="강세 진행",      fill="#F1F8E9", action="표준 운용"),
  S_High_L_Bear    = list(zone="위기",          fill="#FFCDD2", action="defensive +30%, hedge ON"),
  S_High_L_Neutral = list(zone="혼란",          fill="#FFE0B2", action="size cap 60%, hedge ON"),
  S_High_L_Bull    = list(zone="급등 (Vol Risk)", fill="#DCEDC8", action="cap 60%, FOMO 경계")
)

tbl <- dat[!is.na(sigma_bin) & !is.na(lam_bin),
           .(n = .N, avg_fwd22 = mean(fwd22, na.rm=TRUE), vol_fwd22 = sd(fwd22, na.rm=TRUE),
             breach_5pct = mean(fwd22 < -5, na.rm=TRUE),
             breach_10pct = mean(fwd22 < -10, na.rm=TRUE),
             avg_risk = mean(risk_score, na.rm=TRUE)),
           by = .(sigma_bin, lam_bin)]
all_grid <- as.data.table(expand.grid(
  sigma_bin = factor(c("S_Low","S_Mid","S_High"), levels=c("S_Low","S_Mid","S_High")),
  lam_bin   = factor(c("L_Bear","L_Neutral","L_Bull"), levels=c("L_Bear","L_Neutral","L_Bull"))
))
tbl2 <- merge(all_grid, tbl, by=c("sigma_bin","lam_bin"), all.x=TRUE)
tbl2[, key := paste(as.character(sigma_bin), as.character(lam_bin), sep="_")]
tbl2[, zone := sapply(key, function(k) zone_map[[k]]$zone)]
tbl2[, fill := sapply(key, function(k) zone_map[[k]]$fill)]
sigma_centers <- c(S_Low=(0+SIGMA_LOW)/2, S_Mid=(SIGMA_LOW+SIGMA_HIGH)/2, S_High=(SIGMA_HIGH+XLIM[2])/2)
lam_centers <- c(L_Bear=(-0.5+LAM_BEAR)/2, L_Neutral=(LAM_BEAR+LAM_BULL)/2, L_Bull=(LAM_BULL+0.5)/2)
tbl2[, x := sigma_centers[as.character(sigma_bin)]]
tbl2[, y := lam_centers[as.character(lam_bin)]]
tbl2[, lbl := zone]

# Trail 252d + last 60d
trail_all <- tail(dat[!is.na(sigma) & !is.na(lam)], 252)
trail_old <- head(trail_all, max(0, nrow(trail_all)-60))
trail_old[, t_idx := seq_len(.N)]
trail <- tail(trail_all, 60)
trail[, t_idx := seq_len(.N)]
latest <- tail(trail, 1)

latest_key <- sprintf("%s_%s", as.character(latest$sigma_bin), as.character(latest$lam_bin))
now_zone <- zone_map[[latest_key]]$zone
now_action <- zone_map[[latest_key]]$action

# 5d direction
recent5 <- tail(trail, min(5, nrow(trail)))
ds5 <- if (nrow(recent5) >= 2) recent5$sigma[nrow(recent5)] - recent5$sigma[1] else 0
dl5 <- if (nrow(recent5) >= 2) recent5$lam[nrow(recent5)] - recent5$lam[1] else 0
dir5 <- if (ds5 >= 0 & dl5 <= 0) "Risk-Off tilt" else if (ds5 <= 0 & dl5 >= 0) "Risk-On tilt" else "Mixed"

date_labels <- trail[c(1, nrow(trail))]
date_labels[, anchor_lbl := format(Date, "%y/%m/%d")]
ref_date <- as.character(latest$Date)

# Current cell historical stats
now_stats <- tbl2[key == latest_key]

# ── 2. Main 9-Quadrant ───────────────────────────────────────────────────────
p_main <- ggplot() +
  annotate("rect", xmin=0, xmax=SIGMA_LOW,  ymin=YLIM[1], ymax=LAM_BEAR,  fill=zone_map$S_Low_L_Bear$fill,    alpha=0.7) +
  annotate("rect", xmin=0, xmax=SIGMA_LOW,  ymin=LAM_BEAR, ymax=LAM_BULL, fill=zone_map$S_Low_L_Neutral$fill, alpha=0.7) +
  annotate("rect", xmin=0, xmax=SIGMA_LOW,  ymin=LAM_BULL, ymax=YLIM[2],  fill=zone_map$S_Low_L_Bull$fill,    alpha=0.7) +
  annotate("rect", xmin=SIGMA_LOW, xmax=SIGMA_HIGH, ymin=YLIM[1], ymax=LAM_BEAR,  fill=zone_map$S_Mid_L_Bear$fill,    alpha=0.6) +
  annotate("rect", xmin=SIGMA_LOW, xmax=SIGMA_HIGH, ymin=LAM_BEAR, ymax=LAM_BULL, fill=zone_map$S_Mid_L_Neutral$fill, alpha=0.6) +
  annotate("rect", xmin=SIGMA_LOW, xmax=SIGMA_HIGH, ymin=LAM_BULL, ymax=YLIM[2],  fill=zone_map$S_Mid_L_Bull$fill,    alpha=0.6) +
  annotate("rect", xmin=SIGMA_HIGH, xmax=XLIM[2], ymin=YLIM[1], ymax=LAM_BEAR,  fill=zone_map$S_High_L_Bear$fill,    alpha=0.55) +
  annotate("rect", xmin=SIGMA_HIGH, xmax=XLIM[2], ymin=LAM_BEAR, ymax=LAM_BULL, fill=zone_map$S_High_L_Neutral$fill, alpha=0.5) +
  annotate("rect", xmin=SIGMA_HIGH, xmax=XLIM[2], ymin=LAM_BULL, ymax=YLIM[2],  fill=zone_map$S_High_L_Bull$fill,    alpha=0.5) +
  geom_vline(xintercept=c(SIGMA_LOW, SIGMA_HIGH), linetype="dashed", color="gray45", linewidth=0.6) +
  geom_hline(yintercept=c(LAM_BEAR, LAM_BULL), linetype="dashed", color="gray45", linewidth=0.6) +
  # 옛 192d — 단순 회색 (시간 영향 X, 도훈 mandate 2026-05-27)
  geom_point(data=trail_old, aes(sigma_plot, lam_plot),
             color="gray70", alpha=0.30, size=1.3) +
  # 60d trail 선 (빨강)
  geom_path(data=trail, aes(sigma_plot, lam_plot), color="#B71C1C", linewidth=0.7, alpha=0.5) +
  # 60d 점 (빨강 + alpha gradient — 오늘 가까울수록 진하게)
  geom_point(data=trail, aes(sigma_plot, lam_plot, alpha=t_idx),
             color="#B71C1C", size=1.9) +
  scale_alpha_continuous(range=c(0.25, 1.0), guide="none") +
  geom_point(data=head(trail, 1), aes(sigma_plot, lam_plot), shape=21, fill="#FDD835", color="#424242", size=5, stroke=1.2) +
  geom_point(data=latest, aes(sigma_plot, lam_plot), shape=21, fill="#FDD835", color="#424242", size=5, stroke=1.2) +
  geom_text(data=tbl2, aes(x, y, label=lbl), size=3.2, fontface="bold", color="gray30", alpha=0.7) +
  geom_segment(data=date_labels, aes(x=sigma_plot, y=lam_plot,
               xend=sigma_plot+0.12, yend=lam_plot-0.025), color="gray30", linewidth=0.4) +
  geom_label(data=date_labels, aes(sigma_plot, lam_plot, label=anchor_lbl),
             size=2.4, fontface="bold", color="black", fill=scales::alpha("white", 0.85),
             linewidth=0.2, label.padding=unit(0.12,"lines"),
             nudge_x=0.12, nudge_y=-0.025, hjust=0) +
  annotate("label", x=XLIM[1]+0.1, y=YLIM[2]-0.01,
           label=sprintf("NOW: %s\nσ=%.2f%%  λ=%+.3f  μ=%+.2f%%  ν=%.1f  VaR05=%.2f%%\nRisk Score: %.2f / 5.0",
                         now_zone, latest$sigma, latest$lam, latest$mu, latest$nu,
                         latest$var_05, latest$risk_score),
           hjust=0, vjust=1, size=3.6, fontface="bold",
           color="#B71C1C", fill=scales::alpha("white", 0.9), linewidth=0.3) +
  annotate("label", x=XLIM[2]-0.1, y=YLIM[1]+0.01,
           label=sprintf("ACTION: %s\nP(-5%%) = %.2f%%  |  P(-10%%) = %.2f%%",
                         now_action,
                         latest$p_minus_5pct*100, latest$p_minus_10pct*100),
           hjust=1, vjust=0, size=3.5, fontface="bold",
           color="#1B5E20", fill=scales::alpha("#E8F5E9", 0.95), linewidth=0.3) +
  coord_cartesian(xlim=XLIM, ylim=YLIM, clip="off") +
  labs(title=sprintf("P3 Risk Manager 9-Quadrant (data: %s)", ref_date),
       subtitle=sprintf("5D: σ %+.2f%% | λ %+.3f | %s   ·   현 cell historical: n=%s, Fwd22 평균 %s, P(-10%%) = %s",
                        ds5, dl5, dir5,
                        ifelse(is.na(now_stats$n[1]), "0", as.character(now_stats$n[1])),
                        ifelse(is.na(now_stats$avg_fwd22[1]), "—", sprintf("%+.2f%%", now_stats$avg_fwd22[1])),
                        ifelse(is.na(now_stats$breach_10pct[1]), "—", sprintf("%.1f%%", now_stats$breach_10pct[1]*100))),
       x=expression(bold("σ (변동성, %)")*"  (calm" %<-% "" %->% "stress)"),
       y=expression(bold("λ (비대칭)")*"  (bear" %<-% "" %->% "bull)")) +
  theme_minimal(base_size=11, base_family=.KOR_FONT) +
  theme(plot.title=element_text(face="bold", size=13),
        plot.subtitle=element_text(size=10, face="bold", color="gray30"),
        panel.grid.major=element_line(color="gray90", linewidth=0.3),
        panel.grid.minor=element_blank())

# ── 3a. 4D Risk Radar (z-score, all risk-positive direction) ────────────────
radar_df <- data.table(
  axis = factor(c("σ\n변동성", "-λ\n약세편향", "1/ν\n꼬리두께", "-μ\n하락드리프트"),
                levels = c("σ\n변동성", "-λ\n약세편향", "1/ν\n꼬리두께", "-μ\n하락드리프트")),
  z_val = c(latest$z_sigma, -latest$z_lam, latest$z_inv_nu, -latest$z_mu)
)
radar_df[, norm := pmin(pmax(z_val, -3), 3) + 3]  # [-3,3] → [0,6]

p_radar <- ggplot(radar_df, aes(x = axis, y = norm, group = 1)) +
  geom_hline(yintercept = c(2, 4, 6), color = "gray85", linewidth = 0.3) +
  geom_polygon(fill = "#B71C1C", alpha = 0.35, color = "#B71C1C", linewidth = 1) +
  geom_point(color = "#424242", fill = "#FDD835", size = 3, shape = 21, stroke = 1.2) +
  coord_polar(start = -pi/4, clip = "off") +
  scale_y_continuous(limits = c(0, 7), breaks = c(2, 4, 6),
                     labels = c("low", "mid", "high")) +
  labs(title = "4D Risk Radar",
       subtitle = "z-score (3=risk↑)") +
  theme_minimal(base_size = 9, base_family = .KOR_FONT) +
  theme(plot.title = element_text(face = "bold", size = 10, hjust = 0.5),
        plot.subtitle = element_text(size = 8, hjust = 0.5, color = "gray30"),
        axis.text.x = element_text(face = "bold", size = 8),
        axis.text.y = element_text(size = 7, color = "gray60"),
        axis.title = element_blank(),
        panel.grid.major = element_line(color = "gray90", linewidth = 0.3),
        plot.margin = margin(2, 2, 2, 2))

# ── 3. Sidebar timelines (60d sparklines) ───────────────────────────────────
trail60 <- trail
trail60[, idx := seq_len(.N)]
trail60[, breach_5pct_show := p_minus_5pct * 100]

# VaR_05 timeline
p_var <- ggplot(trail60, aes(idx, var_05)) +
  geom_line(color="#B71C1C", linewidth=0.8) +
  geom_point(data=tail(trail60,1), aes(idx, var_05), shape=21, fill="#FDD835", color="#424242", size=3) +
  geom_hline(yintercept=median(trail60$var_05), linetype="dashed", color="gray50", alpha=0.6) +
  labs(title="VaR 5% (60d)", y="VaR (%)", x=NULL) +
  scale_y_reverse(labels=function(x) sprintf("%.1f", x)) +  # y축 역순(도훈 2026-06-01): 손실 클수록(더 음수) 위로
  theme_minimal(base_size=9, base_family=.KOR_FONT) +
  theme(plot.title=element_text(face="bold", size=10),
        axis.text.x=element_blank(),
        panel.grid.minor=element_blank())

# P(-5%) timeline
p_bear <- ggplot(trail60, aes(idx, breach_5pct_show)) +
  geom_area(fill="#FFAB91", alpha=0.5) +
  geom_line(color="#C62828", linewidth=0.8) +
  geom_point(data=tail(trail60,1), aes(idx, breach_5pct_show), shape=21, fill="#FDD835", color="#424242", size=3) +
  labs(title="P(-5% 폭락) (60d, %)", y="확률 (%)", x=NULL) +
  scale_y_continuous(labels=function(x) sprintf("%.2f", x)) +
  theme_minimal(base_size=9, base_family=.KOR_FONT) +
  theme(plot.title=element_text(face="bold", size=10),
        axis.text.x=element_blank(),
        panel.grid.minor=element_blank())

# Risk Score timeline
p_rs <- ggplot(trail60, aes(idx, risk_score)) +
  geom_ribbon(aes(ymin=1, ymax=risk_score), fill="#FFCDD2", alpha=0.5) +
  geom_line(color="#B71C1C", linewidth=0.9) +
  geom_point(data=tail(trail60,1), aes(idx, risk_score), shape=21, fill="#FDD835", color="#424242", size=3.5) +
  geom_hline(yintercept=c(2, 3, 4), linetype="dotted", color="gray60", alpha=0.5) +
  labs(title="Risk Score (60d)", y="Score (1~5)", x="(60d ago) ⟵ trail ⟶ (today)") +
  scale_y_continuous(limits=c(1, 5), breaks=1:5) +
  theme_minimal(base_size=9, base_family=.KOR_FONT) +
  theme(plot.title=element_text(face="bold", size=10),
        axis.text.x=element_blank(),
        panel.grid.minor=element_blank())

# ── 4. Cell stats (bottom strip) — 가독성·직관성 개선 (2026-06-26 도훈) ──────
#   변경: ① pastel fill + 진한 글씨(red-on-red 가독성 붕괴 해소) ② 존명을 타일 안에
#   넣어 축 라벨 연결 불필요 ③ 현재 국면 = 두꺼운 금색 테두리 + ★ + 빨강 글씨로 한눈에
#   ④ 위험순(왼=위험·오=양호) 정렬로 직관화 ⑤ 하단 subtitle = 현재 상황 1줄 평문 요약.
all_cell_stats <- tbl2[!is.na(zone), .(zone, n, avg_fwd22, vol_fwd22, breach_5pct, breach_10pct)]
all_cell_stats[, avg_pm := ifelse(is.na(avg_fwd22), "n/a", sprintf("%+.2f%%", avg_fwd22))]
all_cell_stats[, vol_pm := ifelse(is.na(vol_fwd22), "n/a", sprintf("%.1f%%", vol_fwd22))]
all_cell_stats[, n_str  := ifelse(is.na(n), "0", as.character(n))]
all_cell_stats[, is_now := (zone == now_zone)]
# 위험순 정렬: 평균 수익 낮은(위험)→높은(양호) = 왼→오. 관측 없는 셀(NA)은 오른쪽 끝.
setorder(all_cell_stats, avg_fwd22, na.last = TRUE)
all_cell_stats[, zone_f   := factor(zone, levels = zone)]
all_cell_stats[, zone_lbl := ifelse(is_now, paste0("★ ", zone), zone)]

p_stats <- ggplot(all_cell_stats, aes(x = zone_f, y = 1)) +
  geom_tile(aes(fill = avg_fwd22), width = 0.95, height = 1.1,
            alpha = 0.55, color = "white", linewidth = 0.7) +
  # 현재 국면 셀 강조 — 두꺼운 금색 테두리
  geom_tile(data = all_cell_stats[is_now == TRUE], aes(x = zone_f, y = 1),
            width = 0.95, height = 1.1, fill = NA, color = "#F9A825", linewidth = 3.2) +
  # 존명 (상단, 현재=빨강 굵게)
  geom_text(aes(label = zone_lbl, y = 1.34, color = is_now),
            fontface = "bold", size = 3.5) +
  scale_color_manual(values = c(`FALSE` = "#1A1A1A", `TRUE` = "#B71C1C"), guide = "none") +
  # 수익(평균) — 진한 글씨
  geom_text(aes(label = sprintf("수익 %s", avg_pm), y = 0.98),
            fontface = "bold", size = 3.2, color = "#263238") +
  # 변동 + n (하단)
  geom_text(aes(label = sprintf("변동 %s · n=%s", vol_pm, n_str), y = 0.66),
            size = 2.8, color = "#546E7A") +
  scale_fill_gradient2(low = "#E53935", mid = "#FFF59D", high = "#2E7D32", midpoint = 0,
                       guide = "none", na.value = "gray85") +
  coord_cartesian(ylim = c(0.40, 1.58), clip = "off") +
  labs(title = "과거 유사 국면 → 향후 22일 성과 (수익=평균·변동=표준편차)   ◀ 향후수익 낮음   높음 ▶",
       subtitle = sprintf("★ 현재 '%s' (Risk %.1f/5) — 향후22일 평균 %s · 폭락(-10%%) %s   →   %s",
                          now_zone, latest$risk_score,
                          ifelse(is.na(now_stats$avg_fwd22[1]), "n/a", sprintf("%+.2f%%", now_stats$avg_fwd22[1])),
                          ifelse(is.na(now_stats$breach_10pct[1]), "n/a", sprintf("%.0f%%", now_stats$breach_10pct[1]*100)),
                          now_action),
       y = NULL, x = NULL) +
  theme_minimal(base_size = 9, base_family = .KOR_FONT) +
  theme(plot.title = element_text(face = "bold", size = 11),
        plot.subtitle = element_text(face = "bold", size = 11, color = "#B71C1C"),
        axis.text = element_blank(),
        axis.ticks = element_blank(),
        panel.grid = element_blank())

# ── 5. Layout (patchwork) — radar 제거 (도훈 mandate 2026-05-27) ───────────
right_col <- p_var / p_bear / p_rs + plot_layout(heights = c(1, 1, 1))
layout <- (
  (p_main | right_col) + plot_layout(widths = c(2.5, 1))
) / p_stats + plot_layout(heights = c(3.2, 1.35))

out_dir <- file.path(
  PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v3/03_models/morning_brief",
  ref_date
)
if (!dir.exists(out_dir)) dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)
out_path <- file.path(out_dir, "p3_9quad_riskpro.png")
ggsave(out_path, layout, width=14, height=9.6, dpi=140)
cat(sprintf("[riskpro] saved → %s\n", out_path))
cat(sprintf("[riskpro] NOW: %s | Risk Score: %.2f/5 | Action: %s\n",
            now_zone, latest$risk_score, now_action))
cat(sprintf("[riskpro] σ=%.2f%%  λ=%+.3f  μ=%+.2f%%  ν=%.1f  VaR05=%.2f%%  P(-5%%)=%.2f%%  P(-10%%)=%.3f%%\n",
            latest$sigma, latest$lam, latest$mu, latest$nu, latest$var_05,
            latest$p_minus_5pct*100, latest$p_minus_10pct*100))
cat(sprintf("[riskpro] 5D direction: σ %+.2f%% | λ %+.3f → %s\n", ds5, dl5, dir5))
