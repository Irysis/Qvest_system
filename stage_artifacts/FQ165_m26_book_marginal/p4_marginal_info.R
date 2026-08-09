## ============================================================================
## FQ-165 P4 — "왜 북 한계기여가 없는가" 의 기전을 **가장 검정력 높은 자**로 규명.
## 포트폴리오 ΔIR 은 개입 규모에 잡음이 비례해 검정력이 낮다(P3-B). 종목 수준 회귀는
## 월당 수백 관측이라 훨씬 강하다.
##   질문: score_eff 를 통제한 뒤 M26 의 증분 예측력이 **북이 뽑는 상위 점수 영역**에도 있는가.
##   설계: Fama-MacBeth (월별 횡단면 회귀 → 계수 시계열 NW3 t), 표본을 3중으로 좁힌다.
##         (i) 유동성 적격 전체  (ii) score_eff 상위 50  (iii) 상위 20
##   ★분할이 아니라 **표본 정의 자체**(북이 실제로 선택하는 영역)이며 사전등록 D4 기전분리의 일부.
## 부수: placebo 교체와 실제 교체의 종목수준 edge 대조 (P3-C 의 대조군).
## ============================================================================
suppressMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen = 999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/FQ165_m26_book_marginal"
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")
P1 <- readRDS(file.path(OUT, "p1_base.rds")); MO <- P1$MO; n_m <- length(MO)
TOPN <- 20L; LAM <- 1.5; UB <- 0.20; UBCR <- 0.10

nw_t <- function(x, L=3){ x <- x[is.finite(x)]; n <- length(x); m <- mean(x); e <- x-m
  s <- sum(e^2)/n; for (l in 1:L){ ga <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s+2*(1-l/(L+1))*ga }
  m/sqrt(s/n) }
zcs <- function(v){ s <- sd(v, na.rm=TRUE); if(!is.finite(s)||s<1e-12) return(rep(0,length(v)))
  z <- (v-mean(v,na.rm=TRUE))/s; z[!is.finite(z)] <- 0; z }

## ── 월별 결합 패널 (적격 + M26 + 실현수익) ───────────────────────────────────
PAN <- rbindlist(lapply(seq_len(n_m), function(k) {
  m <- MO[[k]]; tk <- intersect(names(m$score), m$elig); if (length(tk) < 30L) return(NULL)
  d <- data.table(k = k, dd = m$dd, Ticker = tk,
                  score = m$score[tk], m26 = m$m26[tk], ret = m$ret[tk])
  d[is.finite(ret)] }))
PAN[, score_rank := frank(-score, ties.method="first"), by = k]
cat(sprintf("[P4-0] 결합 패널 rows=%d · months=%d · M26 결측 %.3f · 월평균 적격 %.1f 종목\n",
            nrow(PAN), uniqueN(PAN$k), mean(!is.finite(PAN$m26)), nrow(PAN)/uniqueN(PAN$k)))

fmb <- function(dt, label) {
  co <- dt[is.finite(m26) & is.finite(ret), {
    if (.N < 15) .(b_m26 = NA_real_, b_sc = NA_real_, n = .N) else {
      f <- lm(ret ~ zcs(m26) + zcs(score))
      .(b_m26 = coef(f)[2], b_sc = coef(f)[3], n = .N) }
  }, by = k]
  co <- co[is.finite(b_m26)]
  ## 단변량(통제 없음) 도 병기 — 통제로 사라지는지 확인
  cu <- dt[is.finite(m26) & is.finite(ret), {
    if (.N < 15) .(u_m26 = NA_real_) else .(u_m26 = coef(lm(ret ~ zcs(m26)))[2]) }, by = k]
  cu <- cu[is.finite(u_m26)]
  data.table(sample = label, n_months = nrow(co), avg_n = mean(co$n),
    m26_uni_ann_pct = mean(cu$u_m26)*12*100, m26_uni_t = nw_t(cu$u_m26),
    m26_ctl_ann_pct = mean(co$b_m26)*12*100, m26_ctl_t = nw_t(co$b_m26),
    score_ctl_ann_pct = mean(co$b_sc)*12*100, score_ctl_t = nw_t(co$b_sc))
}

FM <- rbindlist(list(
  fmb(PAN,                      "(i) 유동성 적격 전체"),
  fmb(PAN[score_rank <= 100L],  "(ii) score_eff 상위 100"),
  fmb(PAN[score_rank <= 50L],   "(iii) score_eff 상위 50"),
  fmb(PAN[score_rank <= 20L],   "(iv) score_eff 상위 20 (북이 실제 보유)")))
cat("\n===== [P4-A] Fama-MacBeth: M26 증분 예측력이 상위 점수 영역에도 있는가 =====\n")
print(FM[, .(sample, n_months, avg_n = round(avg_n,1),
             uni_ann = round(m26_uni_ann_pct,3), uni_t = round(m26_uni_t,3),
             ctl_ann = round(m26_ctl_ann_pct,3), ctl_t = round(m26_ctl_t,3),
             score_ctl_t = round(score_ctl_t,3))])
cat("  uni = M26 단독 계수 · ctl = score_eff 통제 후 M26 계수 (둘 다 z 표준화, 연환산 %).\n")

## ── P4-B. placebo 대조가 붙은 종목수준 교체 edge ─────────────────────────────
elig_scores <- function(m){ sc <- m$score; tk <- intersect(names(sc), m$elig)
  if (length(tk) < 5L) tk <- names(sc); sc[tk] }
sel_blend <- function(w, get = function(m) m$m26) function(m) { sc <- elig_scores(m); tk <- names(sc)
  b <- zcs(sc) + w*zcs(get(m)[tk]); names(b) <- tk
  o <- order(-b); b[o][seq_len(min(TOPN,length(o)))] }
edge_of <- function(get) {
  e <- sapply(seq_len(n_m), function(k) { m <- MO[[k]]; s <- elig_scores(m)
    b <- names(s[order(-s)][seq_len(min(TOPN,length(s)))])
    a <- names(sel_blend(0.30, get)(m))
    dr <- setdiff(b,a); ad <- setdiff(a,b)
    if (!length(dr) || !length(ad)) return(NA_real_)
    mean(m$ret[ad], na.rm=TRUE) - mean(m$ret[dr], na.rm=TRUE) })
  e[is.finite(e)] }
set.seed(9165)
e_real <- edge_of(function(m) m$m26)
e_plc  <- sapply(1:12, function(s) mean(edge_of(function(m) { v <- m$m26
  if (!length(v)) return(setNames(numeric(0), character(0))); setNames(sample(unname(v)), names(v)) })))
cat(sprintf("\n===== [P4-B] 교체 edge 종목수준 (F_A w=0.30) =====\n"))
cat(sprintf("  실제 M26 : 연 %+.3f%% (NW3 t %+.3f, n=%d)\n", mean(e_real)*12*100, nw_t(e_real), length(e_real)))
cat(sprintf("  placebo  : 연 %+.3f%% (12 draw 중앙, 범위 %+.3f ~ %+.3f)\n",
            median(e_plc)*12*100, min(e_plc)*12*100, max(e_plc)*12*100))
cat(sprintf("  실제 − placebo 중앙 = 연 %+.3f%%p  → 실제 교체가 무작위 교체보다 %s\n",
            (mean(e_real)-median(e_plc))*12*100,
            ifelse(mean(e_real) > median(e_plc), "덜 손해", "더 손해")))

## ── P4-C. 북이 보유하는 종목의 M26 분포 (왜 걸릴 게 없는가) ──────────────────
dist <- PAN[is.finite(m26), {
  q <- ecdf(m26)(m26)
  .(top20_m26_pctile = mean(q[score_rank <= 20L]), all_pctile = mean(q))
}, by = k]
cat(sprintf("\n[P4-C] 북 보유 20종의 M26 분위 평균 = %.4f (유니버스 평균 0.5 기준) · 월 %d개\n",
            mean(dist$top20_m26_pctile, na.rm=TRUE), nrow(dist)))
d1_hit <- PAN[is.finite(m26), {
  thr <- quantile(m26, 0.10, names=FALSE)
  .(n_top20_in_D1 = sum(score_rank <= 20L & m26 <= thr)) }, by = k]
cat(sprintf("       북 보유 20종 중 M26 하위1분위(D1) 해당 = 월평균 %.2f 종목 (%.1f%%)\n",
            mean(d1_hit$n_top20_in_D1), mean(d1_hit$n_top20_in_D1)/20*100))

fwrite(FM, file.path(OUT, "p4_fmb_by_region.csv"))
saveRDS(list(FM=FM, e_real=e_real, e_plc=e_plc, dist=dist, d1_hit=d1_hit, PAN=PAN),
        file.path(OUT, "p4_marginal_info.rds"))
cat("\n[saved] p4_fmb_by_region.csv / p4_marginal_info.rds\n")
