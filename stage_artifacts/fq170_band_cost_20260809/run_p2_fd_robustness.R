## P2 — fD 견고성 (t 2.177 은 문턱 바로 위다)
## 사전등록 규칙 (측정 전 고정, 이 주석이 정본):
##  Q1 견고: 나쁜구역 정의 3변형({10} / {9,10} / {8,9,10}) 전부에서 t_M1 >= 2.0 ∧ 부호 양
##           ∧ 두 부분창(pre2015 / post2015)에서 부호 일치  → ROBUST
##  Q2 부분: 전표본 3변형 중 >=2 가 t>=2.0 이나 창 부호가 갈림     → PARTIAL
##  Q3 취약: 그 외                                                  → FRAGILE (문턱-근접 단일관측으로 강등)
##  Q4 draw 확장: 20→50 draw 로 대조군을 다시 만들어 판정이 유지되는지 확인
##  Q5 자본 자격 주장 금지
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/required_effect_size.R"))

B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X <- merge(as.data.table(B), ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
X <- merge(X, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
X <- X[is.na(adv) | adv >= 2e8]
D <- X[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)]
D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
D[, rk   := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
D[, q10D := cut(frank(D03_EWMA, ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
                include.lowest=TRUE, labels=FALSE), by=Date]
cat(sprintf("[입력 실측] %d행 · %d개월\n", nrow(D), uniqueN(D$Date)))

COST <- 0.0015; W <- 1/25
run_cell <- function(Dsub, badset, ndraw, seed0) {
  ds <- sort(unique(Dsub$Date))
  SL <- lapply(ds, function(dt) Dsub[Date==dt][order(rk)])
  SL <- SL[sapply(SL, nrow) >= 60L]
  if (length(SL) < 24L) return(NULL)
  cost_seq <- function(h) sapply(seq_along(SL), function(i) {
    cur <- h[[i]]; prv <- if (i==1L) character(0) else h[[i-1]]
    u <- unique(c(cur,prv)); COST*sum(abs(W*(u %in% cur) - W*(u %in% prv))) })
  net_of <- function(h) sapply(seq_along(SL), function(i) mean(SL[[i]][Ticker %in% h[[i]]]$Ret_1m)) - cost_seq(h)
  hb <- lapply(SL, function(S) S[seq_len(25L)]$Ticker)
  nb <- net_of(hb)
  hf <- lapply(SL, function(S) S[!(q10D %in% badset)][seq_len(min(25L,.N))]$Ticker)
  kv <- sapply(SL, function(S) sum(S[seq_len(25L)]$q10D %in% badset))
  nf <- net_of(hf)
  M <- matrix(NA_real_, length(SL), ndraw)
  for (d in seq_len(ndraw)) {
    set.seed(seed0 + d)
    h <- lapply(seq_along(SL), function(i) {
      S <- SL[[i]]; b <- S[seq_len(25L)]$Ticker; k <- kv[i]
      if (k <= 0L) return(b)
      c(setdiff(b, sample(b, k)), head(setdiff(S$Ticker, b), k)) })
    M[, d] <- net_of(h)
  }
  dm <- nf - rowMeans(M)
  list(n = length(SL), k = mean(kv), ann = mean(dm)*12*100, t = .nw_t_mean(dm, lag=3L))
}

VARS <- list(v10=c(10L), v910=c(9L,10L), v8910=c(8L,9L,10L))
WINS <- list(full=NULL, pre2015=as.Date("2015-01-01"), post2015=as.Date("2015-01-01"))
rows <- list()
for (vn in names(VARS)) for (wn in names(WINS)) {
  Dsub <- if (wn=="full") D else if (wn=="pre2015") D[Date < WINS[[wn]]] else D[Date >= WINS[[wn]]]
  nd <- if (wn=="full") 50L else 20L         # Q4: 전표본은 50 draw
  r <- run_cell(Dsub, VARS[[vn]], nd, 20260809L + 7000L + 100L*match(vn,names(VARS)) + match(wn,names(WINS)))
  if (is.null(r)) next
  rows[[length(rows)+1L]] <- data.table(bad_zone=vn, window=wn, n_months=r$n, k=round(r$k,2),
                                        ann=round(r$ann,3), t_M1=round(r$t,3), ndraw=nd)
}
R <- rbindlist(rows); print(R[])

full <- R[window=="full"]
q1_t <- all(full$t_M1 >= 2.0 & full$ann > 0)
sign_ok <- all(sapply(names(VARS), function(v) {
  z <- R[bad_zone==v & window %in% c("pre2015","post2015")]
  nrow(z)==2L && all(sign(z$ann) == sign(z$ann[1])) }))
verdict <- {
  if (q1_t && sign_ok) "Q1_ROBUST"
  else if (sum(full$t_M1 >= 2.0) >= 2L) "Q2_PARTIAL"
  else "Q3_FRAGILE"
}
cat(sprintf("\n=== 사전등록 판정 ===\n전표본 3변형 t>=2.0 전건 %s · 부분창 부호일치 %s\n판정: %s\n★Q5: 자본 자격 주장 없음\n",
            q1_t, sign_ok, verdict))
fwrite(R, file.path(OUT,"p2_fd_robustness.csv"))
write_json(list(verdict=verdict, results=R), file.path(OUT,"p2_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
