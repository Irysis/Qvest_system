# run_R3_capw_native.R — R3 lane: cap-w-NATIVE family tilt (P2 of R2).
# 핵심질문: 벽이 EW->cap-w basis 아티팩트인가, 아니면 cap-w family 알파 부재인가?
#   R2 mom_residual/oracle는 translatability를 EW-universe fwd_ret 또는 full-OOS one-hot에서 추정.
#   여기선 신호 = 각 family one-hot의 *cap-w 실현 월별 active* (canonical_screen_bt 산출).
#   walk-forward IS-only(expanding, 연간 refit)로 cap-w 양성 family만 tilt, mega-cap 디커플 family drop.
#   cap-w-native tilt가 momentum(1.277) 넘으면 R2=basis 아티팩트, 못넘으면 cap-w family 알파 부재 확정.
#   beats_momentum = paired_vs_mom_t > 1.0.
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(data.table); library(arrow); library(jsonlite)})
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
W6 <- "04_Research/method_frontier/wt006_exog_forecast"
fams <- .fams  # value,quality,momentum,low_vol,size,dividend
oos  <- .oos_dates
n    <- length(oos)

# ---------- (1) per-family cap-w 실현 월별 active 시계열 (신호 원천) ----------
# score = family z one-hot -> canonical top-25 EW long-only -> active = ret_net - benchmark_ret (cap-w KOSPI200 벤치)
cat("[R3] building per-family cap-w active series...\n")
fam_active <- list()
for(fk in fams){
  sc <- .FAM[, .(Date, Ticker, score = get(fk))]
  a  <- .active_series(.canon(sc))          # data.table(date, active, ret_net)
  fam_active[[fk]] <- a[, .(date, active)]
  setnames(fam_active[[fk]], "active", fk)
}
# wide: date x family cap-w active
CA <- Reduce(function(x,y) merge(x,y,by="date",all=TRUE), fam_active)
setorder(CA, date)
CA <- CA[date %in% oos]
cat(sprintf("[R3] CA rows=%d  fams=%s\n", nrow(CA), paste(fams,collapse=",")))
# full-sample cap-w one-hot 평균 active (진단 — oracle 방향 확인용)
fullmean <- sapply(fams, function(fk) mean(CA[[fk]], na.rm=TRUE))
cat("[R3] full-sample mean cap-w active per family (x1e4):\n"); print(round(fullmean*1e4,2))

# ---------- (2) walk-forward IS-only translatability (expanding, 연간 refit) ----------
# 각 refit date r 에서 trans_f = mean(cap-w active_f over months < r). PIT: 과거 실현 active만.
BURN <- 36L                                   # tilt 시작 전 최소 36m 히스토리
refit_pos <- seq(BURN + 1L, n, by = 12L)      # 연간 refit
# refit 시점별 trans 벡터
trans_at <- lapply(refit_pos, function(r){
  cut <- oos[r]
  hist <- CA[date < cut]
  setNames(sapply(fams, function(fk) mean(hist[[fk]], na.rm=TRUE)), fams)
})
names(trans_at) <- as.character(oos[refit_pos])
# 각 OOS date i 에 적용할 trans = 가장 최근 refit_pos <= i (없으면 NULL=pure momentum)
trans_for_date <- function(i){
  rp <- refit_pos[refit_pos <= i]
  if(length(rp)==0) return(NULL)
  trans_at[[length(rp)]]
}

# momentum-timing theta base (baseline 레시피와 동일)
mom_all <- .mom_theta[date %in% oos]          # data.table(date, family, theta)
mom_wide <- dcast(mom_all, date ~ family, value.var="theta")

# theta 빌더: mult 적용 후 renormalize
build_theta <- function(mult_fun){
  out <- vector("list", n)
  for(i in seq_len(n)){
    d  <- oos[i]
    mw <- mom_wide[date==d]
    if(nrow(mw)==0) next
    base <- setNames(as.numeric(mw[, ..fams]), fams); base[is.na(base)] <- 0
    tr <- trans_for_date(i)                   # NULL 이면 pure momentum
    mult <- mult_fun(tr)                      # named vec over fams (>=0)
    raw  <- base * mult
    if(sum(raw) <= 0) raw <- base             # 안전장치: 전부 drop되면 momentum fallback
    th <- raw / sum(raw)
    out[[i]] <- data.table(date=d, family=fams, theta=as.numeric(th[fams]))
  }
  rbindlist(out)
}

# ---- 변형 A: capw_drop — trailing cap-w 음성 family drop, momentum 가중 유지 ----
mult_drop <- function(tr){
  if(is.null(tr)) return(setNames(rep(1,length(fams)),fams))
  setNames(ifelse(tr > 0, 1, 1e-4), fams)
}
# ---- 변형 B: capw_tilt_k — 음성 drop + 양성은 magnitude(z)로 exp-tilt ----
mult_tilt <- function(k) function(tr){
  if(is.null(tr)) return(setNames(rep(1,length(fams)),fams))
  pos <- tr; pos[pos < 0] <- NA
  if(sum(is.finite(pos)) < 2) return(setNames(ifelse(tr>0,1,1e-4),fams))
  z <- (pos - mean(pos,na.rm=TRUE)) / (sd(pos,na.rm=TRUE) + 1e-9)
  m <- exp(k * z); m[is.na(m)] <- 1e-4         # 음성 family drop
  setNames(m, fams)
}
# ---- 변형 C: momval2_pit — momentum+value만, trailing cap-w trans 비례(walk-forward) ----
mult_momval_pit <- function(tr){
  keep <- c("momentum","value")
  m <- setNames(rep(1e-4,length(fams)), fams)
  if(is.null(tr)){ m[keep] <- 1; return(m) }
  w <- pmax(tr[keep], 1e-6); m[keep] <- w      # 음성이면 바닥값(momentum쪽 우세)
  m
}

cat("[R3] evaluating walk-forward PIT variants...\n")
variants_pit <- list(
  capw_drop     = build_theta(mult_drop),
  capw_tilt_k1  = build_theta(mult_tilt(1)),
  capw_tilt_k2  = build_theta(mult_tilt(2)),
  momval2_pit   = build_theta(mult_momval_pit)
)

# ---------- (3) ORACLE ceiling (look-ahead — full-sample cap-w one-hot 평균 active) ----------
# momentum+value 2-family cap-w-optimal 정적배분 (full-sample cap-w active 비례) — 천장 probe
mv_oracle_w <- pmax(fullmean[c("momentum","value")], 0)
mv_oracle_w <- mv_oracle_w / sum(mv_oracle_w)
theta_mv_oracle <- rbindlist(lapply(oos, function(d)
  data.table(date=d, family=fams, theta=ifelse(fams=="momentum", mv_oracle_w["momentum"],
                                        ifelse(fams=="value", mv_oracle_w["value"], 0)))))
theta_mv_eq <- rbindlist(lapply(oos, function(d)
  data.table(date=d, family=fams, theta=ifelse(fams %in% c("momentum","value"), 0.5, 0))))
# oracle drop: full-sample 양성 family만 momentum 가중 (look-ahead)
pos_full <- names(fullmean)[fullmean > 0]
theta_drop_oracle <- rbindlist(lapply(oos, function(d){
  mw <- mom_wide[date==d]; base <- setNames(as.numeric(mw[, ..fams]), fams); base[is.na(base)]<-0
  m <- ifelse(fams %in% pos_full, 1, 1e-4); raw <- base*m; th <- raw/sum(raw)
  data.table(date=d, family=fams, theta=as.numeric(th[fams]))
}))
variants_oracle <- list(
  momval2_oracle_capwopt = theta_mv_oracle,
  momval2_oracle_eq      = theta_mv_eq,
  drop_oracle_fullpos    = theta_drop_oracle
)

# ---------- (4) 실측 ----------
eval_all <- function(vlist, tag){
  rbindlist(lapply(names(vlist), function(nm){
    m <- eval_theta(vlist[[nm]], nm)
    data.table(tier=tag, variant=nm, port_t=m$port_t, ew_uni_t=m$ew_uni_t, oos_ret=m$oos_ret,
               net_sr=m$net_sr, calmar=m$calmar, turnover=m$turnover,
               paired_vs_mom_t=m$paired_vs_mom_t, paired_vs_static_t=m$paired_vs_static_t,
               lag1_port_t=m$lag1_port_t, n=m$n_months)
  }))
}
res_pit    <- eval_all(variants_pit, "PIT_walkforward")
res_oracle <- eval_all(variants_oracle, "ORACLE_lookahead")
res <- rbind(res_pit, res_oracle)
res[, beats_mom := paired_vs_mom_t > 1.0]
res[, base_mom_port_t := .BASELINE_MOM_PORT_T]

cat("\n===== R3 capw_native RESULTS (baseline momentum port_t=1.277) =====\n")
print(res)

# best PIT (port_t 최대) = 1급 판정
best_pit <- res_pit[which.max(port_t)]
cat(sprintf("\n[R3] best PIT variant = %s  port_t=%.3f  paired_vs_mom=%.3f  lag1=%.3f\n",
            best_pit$variant, best_pit$port_t, best_pit$paired_vs_mom_t, best_pit$lag1_port_t))

# 산출물 저장: best PIT theta parquet + results
best_theta <- variants_pit[[best_pit$variant]]
write_parquet(best_theta, file.path(W6,"theta_R3_capw_native.parquet"))
fwrite(res, file.path(W6,"R3_capw_native_results.csv"))
saveRDS(list(results=res, fullmean_capw_active=fullmean, best_pit_variant=best_pit$variant,
             trans_at=trans_at), file.path(W6,"R3_capw_native.rds"))

# lag1 자가검증: base port_t가 lag1보다 높으면 동월누출 의심
leak_flag <- best_pit$port_t > best_pit$lag1_port_t + 0.30
cat(sprintf("[R3] lag1 self-check: base %.3f vs lag1 %.3f -> leak_suspect=%s\n",
            best_pit$port_t, best_pit$lag1_port_t, leak_flag))

# ---------- (5) 핵심질문 판정 ----------
best_all <- res[which.max(port_t)]
beats <- best_pit$paired_vs_mom_t > 1.0
oracle_best <- res_oracle[which.max(port_t)]
verdict <- if(beats) "BASIS_ARTIFACT: cap-w-native tilt beats momentum -> R2 loss was EW->cap-w basis gap" else
  if(oracle_best$paired_vs_mom_t <= 1.0) "CAPW_FAMILY_ALPHA_ABSENT: even oracle cap-w-native family selection cannot beat momentum -> no exploitable cap-w family alpha at family-allocation layer (confirms R2 oracle 1.248<1.277)" else
  "PARTIAL: oracle beats but PIT cannot recover -> estimation-limited, not basis artifact"

summary <- list(
  lane="R3 capw_native (P2)", date=as.character(Sys.Date()),
  baseline_momentum_port_t=.BASELINE_MOM_PORT_T,
  best_pit=as.list(best_pit), best_oracle=as.list(oracle_best),
  beats_momentum=beats, wall_broken=(best_pit$port_t >= 2.95),
  leak_suspect=leak_flag, verdict=verdict,
  fullmean_capw_active_x1e4=round(fullmean*1e4,3)
)
write_json(summary, file.path(W6,"R3_capw_native_summary.json"), pretty=TRUE, auto_unbox=TRUE)
cat("\n[R3] VERDICT:", verdict, "\n[R3] done.\n")
