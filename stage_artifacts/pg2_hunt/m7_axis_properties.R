## m7 — next_probe ②: MSM_Crisis_Prob 만 양방향 실패한 이유 + **전략-무관 성질이 순위를 예측하는가**
## ★설계 주의(순환 회피): "ON월 슬리브 active 가 좋아서 좋은 라벨" 은 **거의 항등식**이다 —
##   파킹 수익 = ifelse(on, r, bm) 이므로 파킹 active = ifelse(on, r-bm, 0). 평균 채널은 산술.
##   ⇒ 대신 **전략을 전혀 보지 않고 라벨+벤치만으로 계산되는 성질**이 m1 순위를 예측하는지 묻는다.
##   맞으면 **새 라벨을 재기 전에 거르는 규칙**이 생긴다(예측적·비순환).
## ★사전등록: 1급 = 각 성질과 m1 `d_rnd` 의 **Spearman rho**.
##   FALSIFIER: 모든 성질에서 |rho| < 0.5 → "전략-무관 성질로는 예측 불가" 로 판정하고 그렇게 보고한다.
##   ★Spearman 고정 이유 = n17 에 이상치(Cash_Pct 발화율 86~100%) 존재, Pearson 은 그 2점이 지배.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/report_guard.R")
say <- function(fmt, ...) say_guarded(fmt, ..., prefix = "[m7] ")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
inc <- bm_load_incumbent(); inc[, m := mi(date)]
R1 <- fread(file.path(OUT,"m1_label_ranking.csv"))
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
L0 <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime)); RATE <- mean(L0$on)
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1)); dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
AX <- c("MSM_Crisis_Prob","FRED_MRS","KTRI_Score","VEA_Score","Regime_Score","Regime_Score_smooth","Cash_Pct")
MO <- U[!is.na(.dd)][order(.dd)][, lapply(.SD, function(x) x[.N]), by=.(m = mi(.dd)), .SDcols=AX][, m_apply := m + 1L]
f2 <- list.files(".", pattern="^regime_jump_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
JJ <- as.data.table(read_parquet(f2)); jd <- names(JJ)[which(tolower(names(JJ)) %in% c("date","ym"))[1]]
JJ[, .dd := as.Date(as.character(get(jd)))]
JM <- JJ[!is.na(.dd)][order(.dd)][, .(v = last(JM_State)), by=.(m = mi(.dd))][, m_apply := m + 1L]
CM <- Reduce(intersect, list(L0$m, MO$m_apply, JM$m_apply))
MOc <- MO[m_apply %in% CM][order(m_apply)]; JMc <- JM[m_apply %in% CM][order(m_apply)]

say("=== ① MSM_Crisis_Prob 분포 진단 (유일한 양방향 실패 축) ===")
say("  %-22s %8s %8s %8s %8s %8s %7s", "axis","평균","중앙","표준편차","고유값","최빈비중","0근방%")
for (a in AX) { v <- suppressWarnings(as.numeric(MOc[[a]])); v <- v[is.finite(v)]
  if (!length(v)) next
  say("  %-22s %8.4f %8.4f %8.4f %8d %7.1f%% %6.1f%%", a, mean(v), median(v), sd(v),
      length(unique(v)), 100*max(table(v))/length(v), 100*mean(abs(v - min(v)) < 1e-9)) }

say("=== ② 전략-무관 성질 (라벨 + 벤치만 사용 — 슬리브 미참조) ===")
BM <- inc[m %in% CM][order(m)]
mkl <- function(v, dir) { th <- if (dir=="low") quantile(v, RATE, na.rm=TRUE) else quantile(v, 1-RATE, na.rm=TRUE)
  o <- if (dir=="low") v <= th else v >= th; o[is.na(o)] <- FALSE; o }
LABS <- list(); LABS[["mega_spread"]] <- L0[m %in% CM][order(m)]$on
for (a in AX) for (d in c("low","high")) { v <- suppressWarnings(as.numeric(MOc[[a]]))
  if (all(!is.finite(v))) next; LABS[[paste0(substr(a,1,14),"_",d)]] <- mkl(v, d) }
dom <- names(sort(table(JMc$v), decreasing=TRUE))[1]
LABS[["jump_JM_dom"]] <- JMc$v == dom; LABS[["jump_JM_inv"]] <- JMc$v != dom
props <- rbindlist(lapply(names(LABS), function(k) { on <- LABS[[k]]
  rl <- rle(on); onblk <- rl$lengths[rl$values]
  data.table(label = k,
    on_rate    = mean(on),
    n_episode  = length(onblk),                       ## ★에피소드 수 (카드: 개월수 아닌 에피소드가 묶는다)
    run_len    = if (length(onblk)) mean(onblk) else NA_real_,
    ac1        = suppressWarnings(cor(head(as.numeric(on),-1), tail(as.numeric(on),-1))),
    bm_gap     = mean(BM$benchmark_ret[on]) - mean(BM$benchmark_ret[!on]),
    bm_volrat  = sd(BM$benchmark_ret[on]) / sd(BM$benchmark_ret[!on]),
    inc_gap    = mean(BM$active[on]) - mean(BM$active[!on]))  ## PG2 자신의 active (슬리브 아님)
}))
P <- merge(props, R1[, .(label, d_rnd, n_improve)], by="label")
setorder(P, d_rnd)
say("  %-22s %8s %6s %6s %7s %8s %8s %8s", "label","d_rnd","ON%","에피","런길이","bm격차","bm변동비","PG2격차")
for (i in seq_len(nrow(P))) say("  %-22s %+8.4f %5.1f%% %6d %7.2f %+8.4f %8.2f %+8.4f",
  substr(P$label[i],1,22), P$d_rnd[i], 100*P$on_rate[i], P$n_episode[i], P$run_len[i],
  P$bm_gap[i], P$bm_volrat[i], P$inc_gap[i])

say("=== ③ 사전등록 판정 — 전략-무관 성질이 순위를 예측하는가 (Spearman) ===")
cand <- c("on_rate","n_episode","run_len","ac1","bm_gap","bm_volrat","inc_gap")
res <- rbindlist(lapply(cand, function(k) { x <- P[[k]]; ok <- is.finite(x) & is.finite(P$d_rnd)
  ct <- suppressWarnings(cor.test(x[ok], P$d_rnd[ok], method="spearman"))
  data.table(prop=k, rho=unname(ct$estimate), p=ct$p.value, n=sum(ok)) }))
res <- res[order(-abs(rho))]   ## ★setorder 는 표현식 불가 — abs(rho) 를 컬럼으로 찾다 죽는다
for (i in seq_len(nrow(res))) say("  %-10s rho **%+.3f** (p %.4f, n %d)%s", res$prop[i], res$rho[i], res$p[i], res$n[i],
  if (abs(res$rho[i]) >= 0.5) "  ★예측력" else "")
BEST <- res[1]
say("  ⇒ %s", if (abs(BEST$rho) >= 0.5)
  sprintf("**예측 가능 — 최강 성질 = %s (rho %+.3f)**. 새 라벨 사전 선별 규칙 후보", BEST$prop, BEST$rho) else
  "**FALSIFIER 발동 — 전략-무관 성질 7종 전부 |rho|<0.5. 라벨 품질은 라벨만 보고는 예측 불가**")
say("=== ④ MSM 이 왜 예외인가 — 최강 성질 위에서의 위치 ===")
b <- BEST$prop
say("  %s 분위: MSM_low %.1f%% · MSM_high %.1f%% (17종 중)",
    b, 100*mean(P[[b]] <= P[[b]][P$label=="MSM_Crisis_Pro_low"], na.rm=TRUE),
    100*mean(P[[b]] <= P[[b]][P$label=="MSM_Crisis_Pro_high"], na.rm=TRUE))
fwrite(P, file.path(OUT,"m7_axis_properties.csv"))
say("=== m7 완료 ===")
