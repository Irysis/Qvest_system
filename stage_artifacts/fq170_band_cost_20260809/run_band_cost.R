## FQ170 관문 — argmax-추종 밴드 vs top-25, **net(15bps)** 판정
## 사전등록: preregistration.json (측정 전 작성, 규칙 고정)
## ★자본 자격 주장 없음 (R4). 기전 라운드.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
## ★루트 2개를 **명시 분리**한다 (2026-08-09 실사고: setwd(main) 후 상대 source 로
##  main 의 구판 계약을 불러 `series=` 인자가 없다고 죽었다 — 이 세션이 내내 다룬 앵커 갈림).
##  DATA_ROOT = 패널(.rds, gitignore 라 main 에만 존재) · CODE_ROOT = 이 브랜치의 계약 코드.
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT  <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
cat(sprintf("[앵커] DATA=%s\n[앵커] CODE=%s\n", DATA_ROOT, CODE_ROOT))
stopifnot("series" %in% names(formals(required_effect)))   # 구판 계약이면 즉시 정지

PRE <- fromJSON(file.path(OUT, "preregistration.json"), simplifyVector = FALSE)
cat(sprintf("[prereg] 규칙 %d개 고정 확인\n", length(PRE$decision_rules_fixed_before_results)))

B   <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P   <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X <- merge(as.data.table(B), ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
X <- merge(X, liq[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
X <- X[is.na(adv) | adv >= 2e8]
cat(sprintf("[입력 실측] %d행 · %d개월 · %s ~ %s · %d종목\n",
            nrow(X), uniqueN(X$Date), min(X$Date), max(X$Date), uniqueN(X$Ticker)))

COST <- 0.0015   # 15bps one-way, delta-based
W    <- 1/25

# 보유집합 시계열 → EW 총수익 + delta-based 비용
arm_series <- function(hold) {                  # hold: named list Date -> character vector
  ds <- sort(names(hold)); n <- length(ds)
  out <- data.table(Date = as.Date(ds), gross = NA_real_, cost = NA_real_, turn = NA_real_)
  for (i in seq_len(n)) {
    cur <- hold[[ds[i]]]
    prv <- if (i == 1L) character(0) else hold[[ds[i-1]]]
    dw  <- sum(abs(W * (unique(c(cur,prv)) %in% cur) - W * (unique(c(cur,prv)) %in% prv)))
    out[i, `:=`(cost = COST * dw, turn = dw)]
  }
  out
}

mats <- list(
  list(tag="M26_Revenue_Mom", col="M26_Revenue_Mom", shape="MONOTONE_TOP"),
  list(tag="M01_PATHQ",       col="M01_PATHQ",       shape="MONOTONE_TOP"),
  list(tag="Q01_EB",          col="Q01_EB",          shape="HUMP"),
  list(tag="D03_EWMA",        col="D03_EWMA",        shape="INVERTED"),
  list(tag="z_neutral",       col="z_neutral",       shape="HUMP"))

rows <- list()
for (m in mats) {
  D <- X[!is.na(get(m$col))]
  D[, nmo := .N, by = Date]; D <- D[nmo >= 125L]
  D[, rk := frank(-get(m$col), ties.method="first"), by = Date]
  D[, q  := cut(frank(get(m$col), ties.method="first"),
                breaks = quantile(seq_len(.N), probs = seq(0,1,length.out=11L)),
                include.lowest = TRUE, labels = FALSE), by = Date]
  # argmax 를 **본 라운드가** 동일 프레임에서 재산출 (사전등록 design)
  D[, univ := mean(Ret_1m), by = Date]
  pr <- D[, .(ex = mean(Ret_1m) - univ[1]), by = .(Date, q)][, .(ann = mean(ex)*12*100), by = q][order(q)]
  a  <- pr$q[which.max(pr$ann)]
  band <- intersect(c(a-1L, a), 1:10)

  hold_top <- list(); hold_bnd <- list(); rr <- list()
  for (dt in sort(unique(D$Date))) {
    S <- D[Date == dt]
    tp <- S[rk <= 25L][order(rk)]
    bd <- S[q %in% band][order(rk)][seq_len(min(25L, .N))]
    if (nrow(tp) < 20L || nrow(bd) < 20L) next
    k <- as.character(as.Date(dt))
    hold_top[[k]] <- tp$Ticker; hold_bnd[[k]] <- bd$Ticker
    rr[[k]] <- data.table(Date = as.Date(dt), g_top = mean(tp$Ret_1m), g_bnd = mean(bd$Ret_1m))
  }
  R  <- rbindlist(rr)
  ct <- arm_series(hold_top); cb <- arm_series(hold_bnd)
  R  <- merge(R, ct[, .(Date, c_top = cost, t_top = turn)], by="Date")
  R  <- merge(R, cb[, .(Date, c_bnd = cost, t_bnd = turn)], by="Date")
  R[, `:=`(n_top = g_top - c_top, n_bnd = g_bnd - c_bnd)]
  R[, `:=`(d_gross = g_bnd - g_top, d_net = n_bnd - n_top)]

  bar <- required_effect(nrow(R), t_threshold = 2.0, series = R$d_net)
  rows[[length(rows)+1L]] <- data.table(
    material = m$tag, shape = m$shape, argmax = a, band = paste(band, collapse="-"),
    n_months = nrow(R),
    turn_top = mean(R$t_top), turn_bnd = mean(R$t_bnd),
    gross_ann = mean(R$d_gross)*12*100, net_ann = mean(R$d_net)*12*100,
    cost_drag_ann = (mean(R$d_gross) - mean(R$d_net))*12*100,
    t_net = .nw_t_mean(R$d_net, lag=3L),
    bar_ann = bar$required_annual*100, nw_src = bar$nw_inflation_source,
    nw_factor = bar$nw_inflation)
}
S <- rbindlist(rows)
num <- c("turn_top","turn_bnd","gross_ann","net_ann","cost_drag_ann","t_net","bar_ann","nw_factor")
S[, (num) := lapply(.SD, function(z) round(z,3)), .SDcols = num]
print(S[])

# ── 사전등록 판정 규칙 적용 ───────────────────────────────────────────────────
tr <- S[shape != "MONOTONE_TOP"]; nc <- S[shape == "MONOTONE_TOP"]
r1_tr <- sum(tr$net_ann > 0 & tr$t_net >= 2.0)
r1_nc <- all(nc$net_ann < 0)
r3    <- any(nc$net_ann > 0 & nc$t_net >= 2.0)
cat(sprintf("\n=== 사전등록 판정 ===\nR1 treatment 충족 %d/3 (>=2 필요) · negative control 전부 음 %s\n",
            r1_tr, r1_nc))
verdict <- if (r3) "R3_SHAPE_CLAIM_REJECTED" else if (r1_tr >= 2 && r1_nc) "R1_DIRECTION_SUPPORTED" else "R2_CONFIG_SCOPED_NEGATIVE"
cat(sprintf("판정: %s\n", verdict))
cat("★R4: 자본 자격 주장 없음 — PORT_t/oos/calmar 미측정, 졸업 후보 제시 없음\n")

fwrite(S, file.path(OUT, "band_cost_summary.csv"))
write_json(list(round_id = PRE$round_id, verdict = verdict,
                r1_treatment_hits = r1_tr, r1_negctrl_all_negative = r1_nc,
                results = S), file.path(OUT, "result.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = NA)
cat(sprintf("\n[저장] %s\n", file.path(OUT, "result.json")))
