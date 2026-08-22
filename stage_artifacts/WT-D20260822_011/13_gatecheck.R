## WT-D20260822_011 — ★관문의 양방향 검사 (검사기가 PASS 를 낼 수 있는가)
## FAIL 보고의 전제: 이 관문이 '진짜 양성'에는 PASS 를 낸다. 그렇지 않으면 FAIL 은 정보가 없다.
## 양성 대조 = WT-014 MAX5 상위10% 배제 (동일 base·창에서 ΔIR +0.164172178623249 기측정).
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_011")
say <- function(f, ...) cat(sprintf(paste0("[g] ", f, "\n"), ...))
G <- list()
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(fit,
    vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }
cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
kk <- function(d) paste(d$Date, d$Ticker)

O <- readRDS(file.path(OUT, "00_precheck_objects.rds"))
SEL <- as.data.table(O$SEL); RT <- as.data.table(O$RT); Wb <- as.data.table(O$Wb)
PC <- fromJSON(file.path(OUT, "00_precheck.json"))
M_ref <- PC$epsilon$M_ref; nm <- length(unique(SEL$Date))

## 임의 '표식 → 배제' 구성에 대해 관문 산술을 그대로 적용 (백테 없음)
gate_of <- function(flag_dt, tag) {
  X <- merge(SEL[, .(Date, Ticker, sc, Size)], flag_dt, by = c("Date","Ticker"), all.x = TRUE)
  X[is.na(flg), flg := FALSE]
  Y <- X[flg == FALSE]
  setorder(Y, Date, -sc); Y[, rk := seq_len(.N), by = Date]
  Wt <- Y[rk <= 25L][, w := cap_norm(Size), by = Date][, .(Date, Ticker, w, sc)]
  kb <- kk(Wb); kt <- kk(Wt)
  disp <- merge(Wb[!(kb %chin% kt)], RT, by = c("Date","Ticker"), all.x = TRUE)
  ins  <- merge(Wt[!(kt %chin% kb)], RT, by = c("Date","Ticker"), all.x = TRUE)
  disp[, th := is.finite(Ret_1m) & Ret_1m <= -0.20]; ins[, th := is.finite(Ret_1m) & Ret_1m <= -0.20]
  W_disp <- disp[, sum(w)]/nm; dtail <- disp[, mean(th)] - ins[, mean(th)]
  g <- merge(ins[, .(gi = sum(w*fifelse(is.finite(Ret_1m),Ret_1m,0)), wi = sum(w)), by = Date],
             disp[,.(gd = sum(w*fifelse(is.finite(Ret_1m),Ret_1m,0)), wd = sum(w)), by = Date], by = "Date")
  g[, raw := gi - gd]; g[, matched := wd*(gi/wi - gd/wd)]
  sd_gate <- sd(g$raw); n_m <- nrow(g)
  mde80 <- (qnorm(0.975)+qnorm(0.80))*sd_gate/sqrt(n_m)
  list(tag = tag, n_swap_pm = nrow(disp)/nm, W_disp = W_disp,
       tail_disp = disp[, mean(th)], tail_ins = ins[, mean(th)], dtail = dtail,
       benefit_monthly = W_disp*dtail*M_ref, sd_gate = sd_gate, n_months = n_m, mde80 = mde80,
       ceiling_ratio = (W_disp*dtail*M_ref)/mde80,
       realized_raw_monthly = g[, mean(raw)], realized_raw_nw_t = nw_t(g$raw),
       realized_matched_monthly = g[, mean(matched)], realized_matched_nw_t = nw_t(g$matched),
       realized_annual_pp = 1200*g[, mean(raw)]) }

## ── 양성 대조: MAX5 상위 10% 배제 ─────────────────────────────────────────
PANx <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_010/ot_panel.parquet"))[, Date := as.Date(Date)]
MAX5 <- PANx[is.finite(max5), .(Date, Ticker, max5)]
MM <- merge(SEL[, .(Date, Ticker)], MAX5, by = c("Date","Ticker"), all.x = TRUE)
MM[, thr5 := { v <- max5[is.finite(max5)]; if (length(v) >= 30L) quantile(v, 0.90, type=7, names=FALSE) else Inf }, by = Date]
MM[, flg := is.finite(max5) & max5 >= thr5]
PCx <- gate_of(MM[, .(Date, Ticker, flg)], "poscontrol_MAX5_top10pct_exclusion")
G$positive_control <- c(PCx, list(
  known_delta_ir = 0.164172178623249, known_paired_nw_t = 1.56552055710279,
  known_annual_pp = 1.90297642872904,
  source = "WT-D20260822_010/10_measure.json poscontrol (동일 base·창·하네스 실측)"))
say("양성대조 MAX5: 교체 %.2f종/월 | 꼬리 disp %.4f%% vs ins %.4f%% (dtail %+.6f)",
    PCx$n_swap_pm, 100*PCx$tail_disp, 100*PCx$tail_ins, PCx$dtail)
say("  기전-함의 편익 %.6g/월 | sd %.6f → MDE80 %.6f | ★관문 ceiling_ratio = %.4f (문턱 0.10) → %s",
    PCx$benefit_monthly, PCx$sd_gate, PCx$mde80, PCx$ceiling_ratio,
    ifelse(PCx$ceiling_ratio >= 0.10, "PASS — 관문이 진짜 양성을 통과시킨다", "FAIL — ★관문이 기측정 양성도 막는다"))
say("  (참고: 실현 교체손익 raw %+.6f/월 = 연 %+.3f%%p, NW t %+.2f | 기측정 ΔIR %+.4f)",
    PCx$realized_raw_monthly, PCx$realized_annual_pp, PCx$realized_raw_nw_t, 0.164172178623249)

## ── 음성 대조: 무작위 표식 (동일 배제 규모, seed 고정) ─────────────────────
set.seed(20260822L)
NN <- copy(SEL)[, .(Date, Ticker)]
NN[, u := runif(.N)]
NN[, thr := quantile(u, 0.10, type = 7, names = FALSE), by = Date]
NN[, flg := u <= thr]
NCx <- gate_of(NN[, .(Date, Ticker, flg)], "negcontrol_random10pct")
G$negative_control <- NCx
say("음성대조 무작위10%%: 교체 %.2f종/월 dtail %+.6f | ceiling_ratio = %.4f | 실현 raw %+.6f/월 (NW t %+.2f)",
    NCx$n_swap_pm, NCx$dtail, NCx$ceiling_ratio, NCx$realized_raw_monthly, NCx$realized_raw_nw_t)

## ── 본 라운드 대조 (사전고정 epsilon tie-break) ────────────────────────────
G$this_round <- list(fixed_epsilon_ratio = PC$gate$ratio,
  fixed_epsilon_ceiling = PC$gate$ceiling_ratio,
  design_space_sup_ceiling = PC$feasibility_bound$sup_ceiling_ratio)

G$verdict <- list(
  gate_conductive = (PCx$ceiling_ratio >= 0.10),
  reading = if (PCx$ceiling_ratio >= 0.10)
    paste0("관문은 전도성이 있다 — 동일 산술로 기측정 양성(MAX5, ΔIR +0.1642)에 ratio ",
           sprintf("%.4f", PCx$ceiling_ratio), " 를 부여해 통과시킨다. 따라서 본 라운드의 FAIL(사전고정 ",
           sprintf("%.4f", PC$gate$ratio), " / 설계공간 상한 ",
           sprintf("%.4f", PC$feasibility_bound$sup_ceiling_ratio), ")은 관문의 무능이 아니라 설계의 크기다.")
  else
    paste0("★관문이 기측정 양성도 막는다(MAX5 ratio ", sprintf("%.4f", PCx$ceiling_ratio),
           " < 0.10). 이 경우 본 라운드의 FAIL 은 '설계가 작다'가 아니라 '관문의 편익항이 좁다'로 읽어야 하며, ",
           "중단 근거로 쓸 수 없다 — 관문 편익항(꼬리-only)의 재설계가 선결이다."))
say("★★ 관문 전도성: %s", G$verdict$gate_conductive)
write_json(G, file.path(OUT, "13_gatecheck.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("done")
