setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
options(stringsAsFactors = FALSE, warn = 1)
set.seed(20260809)
p0 <- readRDS("stage_artifacts/FQ182/p0.rds")
D  <- as.data.frame(p0$D)
D$Date <- as.Date(D$Date)

mom_skew <- function(x){ x <- x[is.finite(x)]; n <- length(x); m <- mean(x); s <- sqrt(mean((x-m)^2)); sum(((x-m)/s)^3)/n }
bowley   <- function(x, p=0.25){ x <- x[is.finite(x)]; q <- as.numeric(quantile(x, c(p,0.5,1-p))); ((q[3]-q[2])-(q[2]-q[1]))/(q[3]-q[1]) }

# CRRA certainty-equivalent of exposure w on daily return vector r (rest in cash, rf=0)
ce_crra <- function(r, w, gamma){
  z <- 1 + w*r
  if(any(z <= 0)) return(NA_real_)
  if(abs(gamma-1) < 1e-9){ ce <- exp(mean(log(z))) - 1 } else {
    u <- (z^(1-gamma) - 1)/(1-gamma)
    ce <- ((1-gamma)*mean(u) + 1)^(1/(1-gamma)) - 1
  }
  ce
}
wstar_crra <- function(r, gamma, wmax = 3, grid = 0.001){
  ws <- seq(0, wmax, by = grid)
  ce <- vapply(ws, function(w) { v <- ce_crra(r, w, gamma); if(is.na(v)) -Inf else v }, numeric(1))
  ws[which.max(ce)]
}

# ---- sample variants -------------------------------------------------------
d_all <- D[is.finite(D$fwd1), ]
maxday <- d_all$Date[which.max(d_all$fwd1)]
cat("[input] n_fwd1 =", nrow(d_all), " sd =", sprintf("%.6f", sd(d_all$fwd1)),
    " max fwd1 =", sprintf("%.5f", max(d_all$fwd1)), " on signal-date", format(maxday), "\n")

variants <- list(
  full       = rep(TRUE, nrow(d_all)),
  excl_live  = d_all$Date <= as.Date("2026-06-30"),
  excl_top1  = d_all$Date != maxday,
  excl_2026  = format(d_all$Date, "%Y") != "2026"
)

thrs <- c(-0.20, -0.30)
gammas <- c(2, 5, 10)

out <- list()
for(vn in names(variants)){
  dv <- d_all[variants[[vn]], ]
  for(th in thrs){
    on  <- dv$dd252 <= th
    r_on  <- dv$fwd1[on]
    r_off <- dv$fwd1[!on]
    for(grp in c("ON","OFF")){
      r <- if(grp=="ON") r_on else r_off
      mu <- mean(r); sg <- sd(r); sk <- mom_skew(r); bw <- bowley(r)
      m3 <- mean((r-mu)^3)
      row <- data.frame(variant=vn, thr=th, grp=grp, n=length(r),
                        mean_d=mu, sd_d=sg, skew=sk, bowley=bw, m3=m3,
                        mean_ann=mu*252, sd_ann=sg*sqrt(252), sharpe_ann=mu/sg*sqrt(252))
      for(g in gammas){
        row[[paste0("ce_w1_g",g)]]  <- ce_crra(r, 1, g)*252
        row[[paste0("wstar_g",g)]]  <- wstar_crra(r, g)
        # Taylor-3 marginal utility components at w=1
        row[[paste0("mu_term_g",g)]]   <- mu
        row[[paste0("var_pen_g",g)]]   <- -g*sg^2
        row[[paste0("skew_bon_g",g)]]  <- (g*(g+1)/2)*m3
        row[[paste0("dU_dw1_g",g)]]    <- mu - g*sg^2 + (g*(g+1)/2)*m3
      }
      out[[length(out)+1]] <- row
    }
  }
}
res <- do.call(rbind, out)
write.csv(res, "stage_artifacts/FQ182/synth_alloc_moments.csv", row.names = FALSE)

cat("\n===== ON/OFF moments (fwd1) =====\n")
pr <- res[, c("variant","thr","grp","n","mean_ann","sd_ann","sharpe_ann","skew","bowley")]
pr[,5:9] <- round(pr[,5:9], 4)
print(pr, row.names = FALSE)

cat("\n===== CRRA: certainty equivalent at w=1 (annualized) and optimal exposure w* =====\n")
pc <- res[, c("variant","thr","grp","ce_w1_g2","wstar_g2","ce_w1_g5","wstar_g5","ce_w1_g10","wstar_g10")]
pc[,4:9] <- round(pc[,4:9], 4)
print(pc, row.names = FALSE)

cat("\n===== Taylor-3 marginal utility at w=1, gamma=5 (mu / -g*sd^2 / +g(g+1)/2*m3) =====\n")
pt <- res[, c("variant","thr","grp","mu_term_g5","var_pen_g5","skew_bon_g5","dU_dw1_g5")]
pt[,4:7] <- signif(pt[,4:7], 3)
print(pt, row.names = FALSE)

# ---- mean difference significance: paired block bootstrap ------------------
cat("\n===== mean difference ON-OFF: block bootstrap (blk=60, B=2000) =====\n")
blkboot_diff <- function(dv, th, stat, B=2000, blk=60){
  n <- nrow(dv); nb <- ceiling(n/blk)
  base_on <- dv$dd252 <= th
  base <- stat(dv$fwd1[base_on]) - stat(dv$fwd1[!base_on])
  vals <- numeric(B)
  for(b in 1:B){
    st <- sample.int(n-blk+1, nb, replace=TRUE)
    idx <- as.vector(sapply(st, function(s) s:(s+blk-1)))[1:n]
    dd <- dv[idx, ]
    on <- dd$dd252 <= th
    if(sum(on) < 30 || sum(!on) < 30){ vals[b] <- NA; next }
    vals[b] <- stat(dd$fwd1[on]) - stat(dd$fwd1[!on])
  }
  vals <- vals[is.finite(vals)]
  c(base = base, se = sd(vals), ratio = base/sd(vals), p_le0 = mean(vals <= 0))
}
mb <- list()
for(vn in names(variants)){
  dv <- d_all[variants[[vn]], ]
  for(th in thrs){
    a <- blkboot_diff(dv, th, mean)
    s <- blkboot_diff(dv, th, sd)
    k <- blkboot_diff(dv, th, mom_skew)
    mb[[length(mb)+1]] <- data.frame(variant=vn, thr=th,
      mean_diff_ann = a["base"]*252, mean_ratio = a["ratio"], mean_p_le0 = a["p_le0"],
      sd_diff_ann = s["base"]*sqrt(252), sd_ratio = s["ratio"],
      skew_diff = k["base"], skew_ratio = k["ratio"], skew_p_le0 = k["p_le0"])
  }
}
mbd <- do.call(rbind, mb)
mbd[,3:10] <- round(mbd[,3:10], 4)
print(mbd, row.names = FALSE)
write.csv(mbd, "stage_artifacts/FQ182/synth_alloc_boot.csv", row.names = FALSE)
cat("\n[done]\n")
