# diag_size_confound.R — A_size 셀(계약금액/시총)의 소형주 틸트 교란 진단 (WT-D20260802_018)
#   질문: covered names 내 IC +0.08(t~1.9)이 계약 정보인가, 1/Size 틸트인가?
#   방법: 같은 단면에서 ① pure 1/Size IC ② size-잔차화 magnitude IC (score ~ log(1/Size) 회귀 잔차)
#   지위: 기전 진단 — 셀 선택 아님 (사전등록 primary 불변)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"
panelA <- as.data.table(read_parquet(file.path(OUTD, "panel_A.parquet")))
Rg <- as.data.table(read_parquet(file.path(OUTD, "grid_returns.parquet"))); Rg[, Date := as.Date(Date)]
Lg <- as.data.table(read_parquet(file.path(OUTD, "grid_liq.parquet")));    Lg[, Date := as.Date(Date)]
MEM <- as.data.table(read_parquet(file.path(OUTD, "grid_universe_size.parquet"))); MEM[, Date := as.Date(Date)]

ym_of <- function(d) format(d, "%Y%m")
me <- Rg[, .(Date = max(Date)), by = .(ym = ym_of(Date))]
S <- merge(me, panelA[, .(ym, Ticker, w_amt)], by = "ym")
S <- merge(S, MEM, by = c("Date", "Ticker"))               # member + Size
S <- merge(S, Lg, by = c("Date", "Ticker"), all.x = TRUE)
S <- S[!is.na(adv) & adv >= 2e8 & is.finite(w_amt) & w_amt > 0 & is.finite(Size) & Size > 0]
S[, sc_size := w_amt / Size]
S[, inv_size := 1 / Size]
M <- merge(S, Rg, by = c("Date", "Ticker"))
M <- M[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1]

tstat <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8) return(c(NA, NA, NA))
  c(mean(x), mean(x) / sd(x) * sqrt(length(x)), length(x)) }
ics <- M[, .(
  ic_size    = if (.N >= 8) cor(sc_size, Ret_1m, method = "spearman") else NA_real_,
  ic_invsize = if (.N >= 8) cor(inv_size, Ret_1m, method = "spearman") else NA_real_,
  ic_resid   = if (.N >= 8) {
    r <- resid(lm(rank(sc_size) ~ rank(inv_size)))
    cor(r, Ret_1m, method = "spearman")
  } else NA_real_, n = .N), by = Date]
a <- tstat(ics$ic_size); b <- tstat(ics$ic_invsize); c3 <- tstat(ics$ic_resid)
cat(sprintf("[진단] covered 단면 (n=%d개월, 평균 %d종)\n", nrow(ics), round(mean(ics$n))))
cat(sprintf("  ① 계약금액/시총 IC          : mean %+.4f  t %+.2f\n", a[1], a[2]))
cat(sprintf("  ② pure 1/Size IC (소형주 틸트): mean %+.4f  t %+.2f\n", b[1], b[2]))
cat(sprintf("  ③ size-잔차화 magnitude IC   : mean %+.4f  t %+.2f\n", c3[1], c3[2]))
cat(sprintf("  단면 상관 rank(score)~rank(1/Size) 평균: %.3f\n",
            M[, .(cr = cor(rank(sc_size), rank(inv_size))), by = Date][, mean(cr)]))
suppressPackageStartupMessages(library(jsonlite))
write_json(list(ic_size = a, ic_invsize = b, ic_resid = c3),
           file.path(OUTD, "diag_size_confound.json"), auto_unbox = FALSE, digits = 5)
