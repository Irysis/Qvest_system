## BU1 — 필터를 **합성체 수준**에 걸어 D03-직교 base 만들기
## 사전등록(측정 전 고정, 이 주석이 정본):
##  BS2 진단: 개별 |rho(D03)| 0.186 인데 합성체는 0.392 — 평균화가 공통 성분을 증폭한다.
##  ⇒ 개별이 아니라 **합성체 |rho(D03)| < 0.20** 을 만족하는 최대 부분집합을 탐욕적으로 찾는다.
##     절차(사전 고정): 13종 전체에서 시작 → 제거 시 합성체 |rho| 가 가장 크게 떨어지는 팩터를
##     하나씩 뺀다 → |rho| < 0.20 도달 또는 잔여 3종에서 중단.
##  ⇒ 그 base 로 2x2 재측정.
##   BV1 가법 회복: |상호작용| <= 0.25 ∧ (4) > 2.137 → 합성 증폭이 기전이었고 결합이 산다
##   BV2 선별 수준 겹침: 여전히 상호작용 <= -0.30 → 겹침은 신호가 아니라 **선별 수준**
##   BV3 직교화 불가: |rho| < 0.20 을 3종 이상으로 못 만들면 부차군은 구조적으로 D03 축이다
##  ★양성 대조 (1)=1.292 · (3)=2.137 재현 필수. 커버리지 명시. 자본 자격 주장은 >=2.95 시에만.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

S <- fread(file.path(OUT, "az1_shape_census.csv"))
SEC <- grep("^M0[12]", S[shape=="MONOTONE_TOP"]$Factor_Name, value=TRUE, invert=TRUE)
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
U <- merge(B[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
ds <- sort(unique(U$Date)); smp <- ds[seq(1, length(ds), by=12L)]

## 샘플 월의 팩터 행렬 캐시
CACHE <- list()
for (i in seq_along(smp)) {
  dt <- smp[i]
  z <- try(load_month_factors(dt, factor_names=SEC), silent=TRUE); if (inherits(z,"try-error")) next
  W <- dcast(as.data.table(z)[!is.na(Z_Score_Aligned)], Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  m <- merge(W, U[Date==dt, .(Ticker, d03=D03_EWMA)], by="Ticker")
  CACHE[[length(CACHE)+1L]] <- m
}
comp_rho <- function(fs) {
  v <- sapply(CACHE, function(m) {
    f <- intersect(fs, names(m)); if (length(f) < 1L) return(NA_real_)
    zc <- rowMeans(as.matrix(m[, f, with=FALSE]), na.rm=TRUE)
    abs(suppressWarnings(cor(zc, m$d03, method="spearman", use="complete.obs"))) })
  median(v, na.rm=TRUE)
}
cur <- SEC; path <- data.table(n=length(cur), rho=round(comp_rho(cur),3), dropped="")
while (length(cur) > 3L && tail(path$rho,1) >= 0.20) {
  best <- NULL; bv <- Inf
  for (f in cur) { v <- comp_rho(setdiff(cur, f)); if (is.finite(v) && v < bv) { bv <- v; best <- f } }
  if (is.null(best)) break
  cur <- setdiff(cur, best)
  path <- rbind(path, data.table(n=length(cur), rho=round(bv,3), dropped=best))
}
print(path)
cat(sprintf("\n[직교 합성군] %d종 · 합성체 |rho(D03)| = %.3f\n", length(cur), tail(path$rho,1)))
if (tail(path$rho,1) >= 0.20) {
  cat("★BV3 — 합성체 |rho|<0.20 도달 실패. 부차군은 구조적으로 D03 축이다\n")
  write_json(list(verdict="BV3_ORTH_IMPOSSIBLE", path=path, final=cur),
             file.path(OUT,"bu1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA); quit(status=0)
}

acc <- list()
for (i in seq_along(ds)) {
  dt <- ds[i]
  z <- try(load_month_factors(dt, factor_names=cur), silent=TRUE)
  zc <- if (inherits(z,"try-error")) NULL else
        as.data.table(z)[!is.na(Z_Score_Aligned), .(zc=mean(Z_Score_Aligned)), by=Ticker]
  m <- U[Date==dt, .(Ticker, m26=M26_Revenue_Mom, q)]
  m <- if (is.null(zc)) m[, zc:=0] else merge(m, zc, by="Ticker", all.x=TRUE)[is.na(zc), zc:=0]
  m[, base_plain := scale(m26)[,1]][, base_orth := (scale(m26)[,1]+scale(zc)[,1])/2]
  acc[[length(acc)+1L]] <- m[, .(Date=dt, Ticker, q, base_plain, base_orth)]
}
A <- rbindlist(acc)
mk <- function(bc, band) A[, {
  o <- order(-get(bc)); tk <- .SD$Ticker[o]; qq <- .SD$q[o]
  keep <- tk[seq_len(min(25L-band, .N))]; pool <- tk[qq %in% 3:4 & !(tk %in% keep)]
  sel <- c(keep, head(pool, band))
  .(Ticker=.SD$Ticker, score=ifelse(.SD$Ticker %in% sel, 1000-frank(-.SD[[bc]], ties.method="first"), -1e6))
}, by=Date, .SDcols=c("Ticker","q",bc)]
run <- function(Sc, lab) {
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L, cost_bps_oneway=15,
        liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8, run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) return(NULL)
  data.table(arm=lab, coverage=round(r$selected_ret_coverage,4),
             PORT_t=round(r$portfolio_alpha_t_nw_lag3,3), alpha_ann=round(r$alpha_annualized*100,3))
}
R <- rbindlist(list(run(mk("base_plain",0L),"1_plain"), run(mk("base_orth",0L),"2_orth"),
                    run(mk("base_plain",12L),"3_plain_band"), run(mk("base_orth",12L),"4_orth_band")))
print(R[])
g <- function(k) R[arm==k, PORT_t]
inter <- g("4_orth_band") - g("2_orth") - g("3_plain_band") + g("1_plain")
cat(sprintf("\n양성대조 (1) %.3f/1.292 · (3) %.3f/2.137\n상호작용 = %+.3f (BQ1/BS2: -0.801) · 최종 %.3f\n",
            g("1_plain"), g("3_plain_band"), inter, g("4_orth_band")))
ok <- abs(g("1_plain")-1.292)<=0.05 && abs(g("3_plain_band")-2.137)<=0.05
verdict <- { if (!ok) "BV0_POSITIVE_CONTROL_FAILED"
             else if (min(R$coverage)<0.95) "BV_INVALID_COVERAGE"
             else if (abs(inter)<=0.25 && g("4_orth_band")>2.137) "BV1_ADDITIVE_RECOVERED"
             else if (inter<=-0.30) "BV2_SELECTION_LEVEL_OVERLAP" else "BV4_PARTIAL" }
cat(sprintf("판정: %s\n★자본 자격 주장은 PORT_t>=2.95 시에만\n", verdict))
fwrite(R, file.path(OUT,"bu1_combine.csv"))
write_json(list(verdict=verdict, interaction=inter, n_orth=length(cur), orth=cur,
                comp_rho=tail(path$rho,1), path=path, results=R),
           file.path(OUT,"bu1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
