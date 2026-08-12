## M1+M3 — filter-minus-random(월별 k 일치) 정식 검정 + 희석 비용 곡선
## 사전등록: preregistration_m1.json (측정 전 작성)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
PRE <- fromJSON(file.path(OUT,"preregistration_m1.json"), simplifyVector=FALSE)
cat(sprintf("[prereg] 규칙 %d개 고정\n", length(PRE$decision_rules_fixed_before_results)))

B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X <- merge(as.data.table(B), ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
X <- merge(X, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
X <- X[is.na(adv) | adv >= 2e8]
D <- X[!is.na(M26_Revenue_Mom) & !is.na(Q01_EB) & !is.na(D03_EWMA)]
D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
D[, rk   := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
D[, q5Q  := cut(frank(Q01_EB, ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=6L)), include.lowest=TRUE, labels=FALSE), by=Date]
D[, q10D := cut(frank(D03_EWMA, ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)), include.lowest=TRUE, labels=FALSE), by=Date]
D[, `:=`(bad_fQ = q5Q %in% c(1L,5L), bad_fD = q10D %in% c(9L,10L))]
D[, bad_fB := bad_fQ | bad_fD]
cat(sprintf("[입력 실측] %d행 · %d개월\n", nrow(D), uniqueN(D$Date)))

COST <- 0.0015; W <- 1/25; NDRAW <- 20L
ds <- sort(unique(D$Date)); ds <- ds[sapply(ds, function(dt) nrow(D[Date==dt]) >= 60L)]
SL <- lapply(ds, function(dt) D[Date==dt][order(rk)]); names(SL) <- as.character(ds)
KEY <- names(SL)

cost_seq <- function(h) sapply(seq_along(KEY), function(i) {
  cur <- h[[i]]; prv <- if (i==1L) character(0) else h[[i-1]]
  u <- unique(c(cur,prv)); COST*sum(abs(W*(u %in% cur) - W*(u %in% prv))) })
net_of <- function(h) sapply(seq_along(KEY), function(i) mean(SL[[i]][Ticker %in% h[[i]]]$Ret_1m)) - cost_seq(h)

h_base <- lapply(SL, function(S) S[seq_len(25L)]$Ticker)
n_base <- net_of(h_base)

# 필터 arm + 그 arm 의 월별 k 에 **일치**하는 무작위 통제
make_filter <- function(bc) lapply(SL, function(S) S[get(bc)==FALSE][seq_len(min(25L,.N))]$Ticker)
k_of <- function(bc) sapply(SL, function(S) sum(S[seq_len(25L)][[bc]]))
rand_matched <- function(kv, seed0) {
  M <- matrix(NA_real_, length(KEY), NDRAW)
  for (d in seq_len(NDRAW)) {
    set.seed(seed0 + d)
    h <- lapply(seq_along(KEY), function(i) {
      S <- SL[[i]]; b <- S[seq_len(25L)]$Ticker; k <- kv[i]
      if (k <= 0L) return(b)
      c(setdiff(b, sample(b, k)), head(setdiff(S$Ticker, b), k))
    })
    M[, d] <- net_of(h)
  }
  M
}

rows <- list()
for (nm in c("fQ","fD","fB")) {
  bc <- paste0("bad_", nm)
  kv <- k_of(bc); hf <- make_filter(bc)
  nf <- net_of(hf)
  RM <- rand_matched(kv, 20260809L + 1000L * match(nm, c("fQ","fD","fB")))
  nr <- rowMeans(RM)
  dm <- nf - nr                                  # ★M1 사전등록 판정량
  bar <- required_effect(length(dm), t_threshold=2.0, series=dm)
  rows[[length(rows)+1L]] <- data.table(
    arm=nm, k_mean=mean(kv),
    filter_vs_base=mean(nf - n_base)*12*100,
    random_vs_base=mean(nr - n_base)*12*100,
    M1_filter_minus_random=mean(dm)*12*100,
    t_M1=.nw_t_mean(dm, lag=3L),
    bar_ann=bar$required_annual*100,
    draw_sd=sd(colMeans(RM - n_base)*12*100))
}
R <- rbindlist(rows)
R[, (setdiff(names(R),"arm")) := lapply(.SD, function(z) round(z,3)), .SDcols=setdiff(names(R),"arm")]
cat("\n=== M1: filter - matched random (사전등록 판정량) ===\n"); print(R[])

# ── M3: 희석 비용 곡선 (고정 k) ──────────────────────────────────────────────
cat("\n=== M3: 희석 비용 곡선 (무작위 k종 교체) ===\n")
cur <- list()
for (k in c(3L,6L,12L,18L)) {
  M <- rand_matched(rep(k, length(KEY)), 20260809L + 5000L + k)
  ann <- mean(rowMeans(M) - n_base)*12*100
  cur[[length(cur)+1L]] <- data.table(k=k, net_ann=round(ann,3), per_swap=round(ann/k,4))
}
C <- rbindlist(cur); print(C[])
rel <- sd(C$per_swap)/abs(mean(C$per_swap))
cat(sprintf("per-swap 상대 산포 = %.3f (문턱 0.25)\n", rel))

hit <- R[M1_filter_minus_random > 0 & t_M1 >= 2.0]
n4  <- all(R$random_vs_base < 0)
verdict <- if (nrow(hit) > 0) "N1_SHAPE_FILTER_SUPPORTED" else "N2_CONFIG_SCOPED_NEGATIVE"
cat(sprintf("\n=== 사전등록 판정 ===\nM1 통과 %d/3 · N4 희석비용 재현(모두 음) %s\n판정: %s\n", nrow(hit), n4, verdict))
cat(sprintf("N3 희석 상수화: %s (상대산포 %.3f)\n",
            if (rel <= 0.25) "채택 가능" else "상수화 금지 — 라운드마다 무작위 통제 의무", rel))
cat("★N5: 자본 자격 주장 없음\n")

fwrite(R, file.path(OUT,"m1_filter_vs_random.csv")); fwrite(C, file.path(OUT,"m3_dilution_curve.csv"))
write_json(list(round_id=PRE$round_id, verdict=verdict, m1=R, m3=C,
                per_swap_rel_sd=rel, dilution_reproduced=n4),
           file.path(OUT,"m1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
