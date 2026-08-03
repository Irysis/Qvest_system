# =============================================================================
# finalize_charts.R — WT-D20260803_005 (FQ-131) Step E
#   ① 반증 테스트 3 (정렬방향 시변이 부호전환의 원인인가) 실측
#   ② 차트 4종 (텔레그램 첨부)
#   ③ verdict panel(창별 판정) parquet — 본 라운드의 score 객체
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/finalize_charts.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
CH  <- file.path(OUT, "charts"); dir.create(CH, showWarnings = FALSE, recursive = TRUE)
say <- function(fmt, ...) cat(sprintf(paste0("[wt005E] ", fmt, "\n"), ...))

P1R <- readRDS(file.path(OUT, "persistence_results.rds"))
P2R <- readRDS(file.path(OUT, "persistence_results2.rds"))
DBR <- readRDS(file.path(OUT, "dualbasis_results.rds"))
META<- readRDS(file.path(OUT, "pool_meta.rds"))
PR <- P1R$PR; TG <- P1R$TG; GRIDS <- P1R$grids; POOL <- P1R$pool

# ── ① 반증 테스트 3: IC-direction 시변이 판정 부호전환을 만드는가 ───────────
DS <- META$dir_stat
say("dir_stat 커버 factor: %d (풀 %d 중 %d)", nrow(DS), length(POOL),
    length(intersect(DS$Factor_Name, POOL)))
P <- merge(PR$primary, DS[, .(Factor_Name, n_dir_flips)], by = "Factor_Name")
FLIP <- P[, .(n_pairs = .N, n_factors = uniqueN(Factor_Name),
              p_persist = mean(sign(t_k) == sign(t_next))),
          by = .(dir_stable = n_dir_flips == 0L)]
print(FLIP)
falsif3 <- if (nrow(FLIP) == 2L) {
  d <- FLIP[dir_stable == TRUE, p_persist] - FLIP[dir_stable == FALSE, p_persist]
  say("★ 반증3: 정렬방향 전환 0회 factor p=%.3f vs >=1회 p=%.3f (Δ %+.3f) — Δ가 크지 않으면 '부호전환 = 정렬 아티팩트' 기전 기각",
      FLIP[dir_stable == TRUE, p_persist], FLIP[dir_stable == FALSE, p_persist], d)
  list(p_stable = FLIP[dir_stable == TRUE, p_persist],
       p_flipping = FLIP[dir_stable == FALSE, p_persist], delta = d,
       verdict = if (abs(d) < 0.10) "REJECTED_alignment_artifact" else "SUPPORTED")
} else list(verdict = "INSUFFICIENT_COVERAGE")

# ── ② 차트 ─────────────────────────────────────────────────────────────────
E <- DBR$era2
png(file.path(CH, "wt005_era_dualbasis.png"), width = 1150, height = 640)
par(mfrow = c(1, 2), mar = c(6, 4.5, 4, 1))
for (g in c("primary", "rob36")) {
  Eg <- E[grid == g]
  W <- GRIDS[[g]]$W
  bp <- barplot(rbind(Eg$pos_cap, Eg$pos_ew), beside = TRUE,
    names.arg = format(Eg$to, "~%y.%m"), col = c("#cf222e", "#1f6feb"),
    ylim = c(0, 1), ylab = "PORT_t > 0 인 factor 비율",
    main = sprintf("창 %d개월 — 판정 양수비율\n(빨강 cap-w 벤치 / 파랑 EW-유니버스 벤치)", W),
    las = 2, cex.names = 0.85)
  abline(h = 0.5, lty = 2)
  text(bp, rbind(Eg$pos_cap, Eg$pos_ew), sprintf("%.2f", rbind(Eg$pos_cap, Eg$pos_ew)),
       pos = 3, cex = 0.75)
}
mtext(sprintf("WT-005 era 공통성분 — 285 factor 판정 부호는 cap-w 벤치에서 era 라벨(일치율 %.2f), EW에서는 아님(%.2f)",
      mean(DBR$era_share$agree_cap), mean(DBR$era_share$agree_ew)), outer = TRUE, line = -1.5, cex = 0.95)
dev.off()

B <- P2R$bin_ci
png(file.path(CH, "wt005_persistence_bins.png"), width = 1150, height = 620)
par(mar = c(5, 4.5, 4, 1))
grids <- c("primary", "rob36", "rob24"); cols <- c("#1f6feb", "#8250df", "#9a6700")
bins <- c("[0,0.5)", "[0.5,1)", "[1,2)", "[2,inf)")
plot(NA, xlim = c(0.6, 4.4), ylim = c(0.2, 0.95), xaxt = "n",
     xlab = "현재 창의 |PORT_t|", ylab = "다음 창 부호 유지 확률",
     main = "WT-005 (b) 게이트 관문 — |t| 가 클수록 판정이 오래 가는가")
axis(1, at = 1:4, labels = bins)
abline(h = 0.5, lty = 1, col = "grey40")
nullm <- vapply(P1R$nulls, function(x) mean(x[is.finite(x)]), numeric(1))
abline(h = nullm["primary"], lty = 3, col = "grey20")
for (i in seq_along(grids)) {
  S <- B[grid == grids[i]]; S <- S[match(bins, S$bin)]
  xx <- (1:4) + (i - 2) * 0.15
  arrows(xx, S$lo, xx, S$hi, angle = 90, code = 3, length = 0.05, col = cols[i], lwd = 2)
  points(xx, S$p, pch = 19, col = cols[i], cex = 1.4)
  lines(xx, S$p, col = cols[i], lwd = 2, lty = if (i == 1) 1 else 2)
}
legend("topleft", bty = "n", lwd = 2, col = c(cols, "grey40", "grey20"),
       lty = c(1, 2, 2, 1, 3),
       legend = c("primary W=60m (사전등록)", "W=36m", "W=24m",
                  "동전던지기 0.5", sprintf("상수-알파 잡음 귀무 %.3f", nullm["primary"])))
text(4 - 0.15, B[grid == "primary" & bin == "[2,inf)", p] - 0.06,
     sprintf("primary 최강 판정 = %.3f\n(CI %.2f~%.2f, 0.5 포함)",
             B[grid=="primary" & bin=="[2,inf)", p], B[grid=="primary" & bin=="[2,inf)", lo],
             B[grid=="primary" & bin=="[2,inf)", hi]), cex = 0.85, col = "#cf222e")
dev.off()

GS <- P2R$gate_sim
png(file.path(CH, "wt005_gate_sim.png"), width = 1150, height = 620)
par(mar = c(5, 4.5, 4, 1))
plot(NA, xlim = c(-0.1, 3.1), ylim = c(-1.6, 1.8), xlab = "자격 문턱 tau (창 k 의 PORT_t >= tau 로 선발)",
     ylab = "선발분의 다음 창 PORT_t 평균",
     main = "WT-005 운용 게이트 시뮬 — 문턱을 올리면 다음 창이 좋아지는가")
abline(h = 0, lty = 1, col = "grey40")
g3 <- list(primary = GS$primary, rob36 = GS$rob36, rob24 = GS$rob24)
for (i in seq_along(g3)) {
  S <- g3[[i]]
  if (i == 1L) { arrows(S$tau, S$lo, S$tau, S$hi, angle = 90, code = 3, length = 0.05,
                        col = cols[i], lwd = 2) }
  lines(S$tau, S$mean_t_next, col = cols[i], lwd = 2, lty = if (i == 1) 1 else 2)
  points(S$tau, S$mean_t_next, pch = 19, col = cols[i])
}
legend("topleft", bty = "n", lwd = 2, col = cols, lty = c(1, 2, 2),
       legend = c("primary W=60m (사전등록, CI 표시)", "W=36m", "W=24m"))
Sp <- GS$primary
text(2.0, Sp[tau == 2, mean_t_next] - 0.35,
     sprintf("primary tau=2: %+.3f\n(선발 %d건, 다음창 양수 %.0f%%)",
             Sp[tau == 2, mean_t_next], Sp[tau == 2, n_sel], 100 * Sp[tau == 2, share_pos_next]),
     cex = 0.85, col = "#cf222e")
dev.off()

Pp <- PR$primary
png(file.path(CH, "wt005_scatter.png"), width = 1150, height = 620)
par(mar = c(5, 4.5, 4, 1))
plot(Pp$t_k, Pp$t_next, pch = 16, col = adjustcolor("#1f6feb", 0.35), cex = 0.7,
     xlab = "창 k 의 PORT_t", ylab = "창 k+1 의 PORT_t",
     main = sprintf("WT-005 판정 전이 (primary W=60m, %d쌍, 285 factor x 3 전이)", nrow(Pp)))
abline(h = 0, v = 0, col = "grey50"); abline(0, 1, lty = 3, col = "grey60")
fit <- lm(t_next ~ t_k, data = Pp); abline(fit, col = "#cf222e", lwd = 2)
q <- c(sum(Pp$t_k > 0 & Pp$t_next > 0), sum(Pp$t_k > 0 & Pp$t_next <= 0),
       sum(Pp$t_k <= 0 & Pp$t_next > 0), sum(Pp$t_k <= 0 & Pp$t_next <= 0))
legend("topleft", bty = "n", cex = 0.95,
  legend = c(sprintf("기울기 b = %+.3f (클러스터 t %+.2f)", coef(fit)[2], P1R$lm$primary["t"]),
             sprintf("유지 %d + %d = %d쌍 (%.1f%%)", q[1], q[4], q[1]+q[4],
                     100*(q[1]+q[4])/sum(q)),
             sprintf("반전 %d + %d = %d쌍 (%.1f%%)", q[2], q[3], q[2]+q[3],
                     100*(q[2]+q[3])/sum(q))))
dev.off()
say("차트 4종 저장 — %s", CH)

# ── ③ verdict panel parquet (본 라운드의 score 객체) ───────────────────────
VP <- rbindlist(lapply(names(TG), function(nm) {
  TT <- TG[[nm]]$t
  rbindlist(lapply(seq_len(nrow(TT)), function(k) {
    x <- TT[k, ]
    data.table(grid = nm, window_k = k, from = TG[[nm]]$from[k], to = TG[[nm]]$to[k],
               Factor_Name = colnames(TT), port_t = as.numeric(x),
               verdict_sign = sign(as.numeric(x)))
  }))
}))
VP <- VP[is.finite(port_t)]
EWG <- readRDS(file.path(OUT, "ew_basis_grids.rds"))
VPE <- rbindlist(lapply(names(EWG$TG_ew), function(nm) {
  TT <- EWG$TG_ew[[nm]]$t
  rbindlist(lapply(seq_len(nrow(TT)), function(k) data.table(grid = nm, window_k = k,
    Factor_Name = colnames(TT), port_t_ew = as.numeric(TT[k, ]))))
}))
VP <- merge(VP, VPE, by = c("grid", "window_k", "Factor_Name"), all.x = TRUE)
setorder(VP, grid, window_k, -port_t)
write_parquet(VP, file.path(OUT, "alpha_scores.parquet"))
say("alpha_scores.parquet = verdict panel %d행 (grid x window x factor x PORT_t[cap-w, EW])", nrow(VP))

saveRDS(list(falsif3 = falsif3, flip_tab = FLIP, verdict_panel_rows = nrow(VP)),
        file.path(OUT, "finalize_bits.rds"))
say("완료")
