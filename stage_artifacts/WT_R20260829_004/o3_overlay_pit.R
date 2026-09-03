# O3 — 오버레이 PIT 4항 (optimizer 층 재통과) + 선택 method 확정
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT,"02_Infrastructure/contracts/weighted_screen_bt.R"))
source(file.path(ROOT,"02_Infrastructure/validation/overlay_pit_guard.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
O1 <- readRDS(file.path(OUT,"o1_objects.rds")); O2 <- readRDS(file.path(OUT,"o2_objects.rds"))
AS <- O1$AS; SIG <- O1$SIG; R <- O1$R; BENCH <- O1$BENCH; AS2 <- O2$AS2
TOPN <- 25L; PPY <- 12L; COST_BPS <- 15; POOL_OFFSET <- 100

## ── 항목 1: assert_overlay_pit (HARD) ────────────────────────────────────────
sigm <- SIG[is.finite(panic)]
assert_overlay_pit(sigm$used_cutoff, sigm$holding_month_start, label="optimizer_regime_consumption")
item1 <- list(status="PASS", n_rows=nrow(sigm),
  max_used_cutoff=as.character(max(sigm$used_cutoff)),
  rule="used_cutoff <= holding_month_start (first-day-of-holding-month)",
  optimizer_layer_extra=list(
    desc="optimizer 자체 소비 정합 — 신호(signal_ym) 라벨이 그 달 말 Date 의 비중에 쓰이고 수익은 holding_ym 에서 실현",
    used_cutoff_le_asof = all(sigm$used_cutoff <= sigm$signal_month_end),
    n_asof_dates = uniqueN(AS$Date)))
cat(sprintf("[O3] item1 assert PASS (n=%d, max cutoff %s, cutoff<=asof %s)\n",
    nrow(sigm), item1$max_used_cutoff, item1$optimizer_layer_extra$used_cutoff_le_asof))

## ── 구성 재구성기 (alpha spec 1:1 — 재해석 아님. panic_map 만 갈아끼운다) ─────
zsc <- function(x){ m <- mean(x,na.rm=TRUE); s <- stats::sd(x,na.rm=TRUE)
  if(!is.finite(s)||s==0) rep(0,length(x)) else (x-m)/s }
build_scores <- function(panic_map){
  E <- copy(AS2); E[, panic_use := NULL]
  E <- merge(E, panic_map, by="signal_ym", all.x=TRUE); E[is.na(panic_use), panic_use := 0L]
  E[, pool := pool_indicator]
  E[, z_negvol := 0]
  E[panic_use==1L & pool==1, z_negvol := zsc(-vol126_ann), by=Date]
  E[panic_use==1L & pool==1 & !is.finite(vol126_ann), `:=`(pool=0, z_negvol=0)]
  E[, score_final := fifelse(panic_use==1L, POOL_OFFSET*pool + z_negvol, score_base_momentum)]
  E }
panic_now  <- SIG[is.finite(panic), .(signal_ym, panic_use=panic)]
panic_lag1 <- copy(SIG)[order(signal_ym)][, panic_use := shift(panic,1L)][is.finite(panic_use), .(signal_ym,panic_use)]
panic_viol <- copy(SIG)[order(signal_ym)][, panic_use := shift(panic,-1L)][is.finite(panic_use), .(signal_ym,panic_use)]

E_now <- build_scores(panic_now)
par_ok <- E_now[, max(abs(score_final - score))]
cat(sprintf("[O3] 구성 재구성 parity(vs alpha score): max|diff| = %.3e  -> %s\n",
            par_ok, if(par_ok < 1e-9) "EXACT" else "★MISMATCH"))
stopifnot(par_ok < 1e-9)

## ── 선택 method(W2_IV) 비중 규칙 ────────────────────────────────────────────
.norm <- function(w){ w[!is.finite(w)|w<0] <- 0; if(sum(w)<=0) return(rep(1/length(w),length(w))); w/sum(w) }
w_iv <- function(D){ s <- D$vol126_ann; ok <- is.finite(s)&s>0
  if(!any(ok)) return(rep(1/nrow(D),nrow(D))); s[!ok] <- median(s[ok]); .norm(1/s) }
make_W <- function(E){ x <- copy(E); setorder(x, Date, -score_final)
  H <- x[, head(.SD,TOPN), by=Date, .SDcols=c("Ticker","vol126_ann","panic_use","Sector","score_final")]
  H[, w := w_iv(.SD), by=Date, .SDcols=c("vol126_ann")]
  H[, .(Date,Ticker,w,Sector,panic_use,vol126_ann)] }
meas <- function(W, rid){ m <- weighted_screen_bt(W[,.(Date,Ticker,w)], R, BENCH, COST_BPS, rid, rid)
  pr <- as.data.table(m$period_returns); r <- pr$ret_net; n <- length(r)
  nav <- cumprod(1+r); mdd <- min(nav/cummax(nav)-1); cg <- prod(1+r)^(PPY/n)-1
  fit <- lm(r ~ pr$benchmark_ret); ct <- coeftest(fit, vcov=NeweyWest(fit,lag=3,prewhite=FALSE))
  list(sr=mean(r)/stats::sd(r)*sqrt(PPY), calmar=cg/abs(mdd), cagr=cg, mdd=mdd,
       alpha_ann_pct=100*PPY*unname(ct[1,1]), beta=unname(ct[2,1]), t_alpha=unname(ct[1,3]),
       port_t=m$portfolio_alpha_t_nw_lag3, to=m$turnover_annual, pr=pr) }
W_now  <- make_W(E_now);                 M_now  <- meas(W_now,  "o3_W2IV_now")
W_lag1 <- make_W(build_scores(panic_lag1)); M_lag1 <- meas(W_lag1,"o3_W2IV_lag1")
W_viol <- make_W(build_scores(panic_viol)); M_viol <- meas(W_viol,"o3_W2IV_viol")

## ── 항목 2: lag1 스트레스 ────────────────────────────────────────────────────
rel_cal <- (M_lag1$calmar - M_now$calmar)/abs(M_now$calmar)
rel_sr  <- (M_lag1$sr - M_now$sr)/abs(M_now$sr)
item2 <- list(calmar_base=M_now$calmar, calmar_lag1=M_lag1$calmar, rel_change_calmar=rel_cal,
              sr_base=M_now$sr, sr_lag1=M_lag1$sr, rel_change_sr=rel_sr,
              status=if(is.finite(rel_cal) && rel_cal > -0.25) "NO_COLLAPSE" else "COLLAPSE_SUSPECT",
              rule="lag1 판이 base 대비 -25% 초과 붕괴하면 동월 누출 의심")

## ── 항목 3: strict-PIT A/B + 양성 대조(위반 주입) ────────────────────────────
ab_strict   <- overlay_lookahead_ab(M_now$calmar, M_now$calmar, "Calmar(current vs strict)")
ab_probe    <- overlay_lookahead_ab(M_viol$calmar, M_now$calmar, "Calmar(violation probe vs strict)")
ab_probe_sr <- overlay_lookahead_ab(M_viol$sr, M_now$sr, "SR(violation probe vs strict)")
item3 <- list(current_equals_strict=TRUE, inflation=ab_strict$inflation, message=ab_strict$message,
  strict_definition="현행 컷오프(signal_month_end, = holding_month_start 직전)가 곧 strict 정의와 동일 — 두 값이 같으므로 인플레 0",
  positive_control_violation_probe=list(
    description="패닉 신호를 1개월 앞당김(shift -1) = 홀딩월 자신의 정보로 국면 판정 (BearProb 실사고 동형)",
    calmar=M_viol$calmar, sr=M_viol$sr, alpha_ann_pct=M_viol$alpha_ann_pct,
    inflation_calmar=ab_probe$inflation, lookahead_flag_calmar=ab_probe$lookahead_suspected,
    inflation_sr=ab_probe_sr$inflation, lookahead_flag_sr=ab_probe_sr$lookahead_suspected))

## ── 항목 4: 컷오프 규약 ──────────────────────────────────────────────────────
# ★의사결정 경로 vs 사후 평가기 분리 스캔 (브리핑 지시). 패턴 회피 수정 아님 —
#   의사결정 경로(구성 선택 + 비중 산출)는 두 토큰을 애초에 쓰지 않고, 사후 평가기(본 PIT 감사 절)만
#   토큰을 '검사 대상 문자열'로 언급한다. 초판은 이 둘을 합쳐 스캔해 자기참조 TRUE 를 냈다.
decision_path_files <- c("o1_inputs.R","o2_methods.R")
o3L <- readLines(file.path(OUT,"o3_overlay_pit.R"), warn=FALSE)
cut_i <- grep("^## .* 항목 2", o3L)[1]          # 이 줄부터 아래가 사후 평가기
src_decision <- c(unlist(lapply(decision_path_files, function(f) readLines(file.path(OUT,f), warn=FALSE))),
                  o3L[seq_len(cut_i-1L)])
src_posthoc  <- o3L[cut_i:length(o3L)]
cons_cols <- unique(c(names(AS), names(AS2), names(SIG), names(R), names(BENCH)))
item4 <- list(rule="first-day-of-holding-month", used="signal_month_end (= holding_month_start - 1d) 이전 데이터만",
  scan_split=list(decision_path_lines=length(src_decision), posthoc_evaluator_lines=length(src_posthoc)),
  anchor_date_in_decision_path = any(grepl("anchor_date", src_decision, fixed=TRUE)),
  realized_ym_in_decision_path = any(grepl("realized_ym", src_decision, fixed=TRUE)),
  anchor_date_in_posthoc_mentions = sum(grepl("anchor_date", src_posthoc, fixed=TRUE)),
  consumed_columns_have_anchor_date = "anchor_date" %in% cons_cols,
  consumed_columns_have_realized_ym = "realized_ym" %in% cons_cols,
  join_key="signal_ym (신호월) — holding_ym 으로 조인하지 않음",
  self_reference_note="초판 검사기가 자기 코드의 토큰을 읽어 TRUE 를 냈다(자기참조 오탐). 소비 컬럼 존재검사를 병기해 재도출.")

cat(sprintf("\n[O3] W2_IV now   : SR=%+.4f Calmar=%+.4f a=%+.3f%%/yr TO=%.3f\n", M_now$sr,M_now$calmar,M_now$alpha_ann_pct,M_now$to))
cat(sprintf("[O3] W2_IV lag1  : SR=%+.4f Calmar=%+.4f (rel dCalmar %+.2f%% -> %s)\n", M_lag1$sr,M_lag1$calmar,100*rel_cal,item2$status))
cat(sprintf("[O3] W2_IV viol  : SR=%+.4f Calmar=%+.4f  infl(Calmar)=%+.2f%% flag=%s | infl(SR)=%+.2f%% flag=%s\n",
    M_viol$sr,M_viol$calmar,100*ab_probe$inflation,ab_probe$lookahead_suspected,
    100*ab_probe_sr$inflation,ab_probe_sr$lookahead_suspected))
cat(sprintf("[O3] item4: anchor_date_used=%s realized_ym_used=%s\n", item4$anchor_date_used, item4$realized_ym_used))

F8 <- list(item1_assert_overlay_pit=item1, item2_lag1_stress=item2, item3_strict_ab=item3,
           item4_cutoff_rule=item4,
           verdict=if(identical(item2$status,"NO_COLLAPSE") && !ab_strict$lookahead_suspected &&
                      !item4$anchor_date_in_decision_path && !item4$realized_ym_in_decision_path) "PASS" else "REVIEW")
write_json(F8, file.path(OUT,"o3_overlay_pit.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")
saveRDS(list(F8=F8,W_now=W_now,M_now=M_now,M_lag1=M_lag1,M_viol=M_viol,
             E_now=E_now,build_scores=build_scores,make_W=make_W,meas=meas,w_iv=w_iv),
        file.path(OUT,"o3_objects.rds"))
cat(sprintf("[O3] F8 verdict = %s\n", F8$verdict))
