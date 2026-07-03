## run_fof_book_marginal.R — fof 최종전략(FoF_Seasoned_ICtilt = Tilt) book-marginal 기여 검증
## 세션 임무: standalone 졸업 ≠ book 기여. fof alpha(pt3.46)가 배포북(STR_1715)에 직교 기여하나?
## 측정: ① active 상관 ② PIT 확장윈도 잔차화 후 ΔactiveIR(≥0.05 게이트)
## 규율: 실측-only, metric_type 라벨, PIT, paired-NW-t(SR 비율비교 금지), R 단일스레드.
## ⚠ 날짜정렬: fof series date=t(결정월), net=[t,t+1m] 실현. book realized_ym=실현월. cor-offset로 실증정렬(retraction 교훈).
suppressPackageStartupMessages({library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "04_Research/factor_rotation/fof_first_slice"
con <- file(file.path(OUT,"_fof_book_marginal.txt"),"w",encoding="UTF-8")
w <- function(...) writeLines(paste0(...),con)
w("================ fof book-marginal 검증 ================")
w(sprintf("실행 %s", as.character(Sys.time())))

## ── 1. fof 최종전략 net 시리즈 (Tilt = whitepaper §4 authoritative) ──
ser <- readRDS(file.path(OUT,"_optsweep2_series.rds"))
stopifnot("Tilt" %in% names(ser))
fof <- as.data.table(ser[["Tilt"]])           # date(=결정월), net(=[t,t+1m] 실현 net)
fof <- fof[is.finite(net)]; setorder(fof, date)
fof[, ym_decision := format(date, "%Y-%m")]
w(sprintf("\n[fof Tilt 시리즈] n=%d, date범위 %s ~ %s (결정월 기준)",
          nrow(fof), min(fof$ym_decision), max(fof$ym_decision)))

## fof benchmark (cap-weight BM_Ret) — active = net - BM, realized-aligned
bo <- readRDS(".cache/_bo_fwdgic.rds"); fwd <- bo$fwd
bench_dt <- as.data.table(fwd$bench_dt)[,.(date=as.Date(Date), BM=BM_Ret)]
bench_dt[, ym_decision := format(date, "%Y-%m")]
fof <- merge(fof, bench_dt[,.(ym_decision, BM)], by="ym_decision", all.x=TRUE)
fof[, act := net - BM]
w(sprintf("[fof active] BM merge 결측=%d", sum(is.na(fof$BM))))

## ── 2. book 시리즈 (STR_1715 deployed V5) ──
bk <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
## ret_L5_V5 = deployed variant (regime_x_R05_interaction). realized_ym = 실현월.
book <- bk[, .(realized_ym, ret_book = ret_L5_V5)]
book <- book[is.finite(ret_book)]
## book active = book - BM. book의 벤치는 동일 KR cap-weight 지수. 정렬은 아래 offset으로 실증.
w(sprintf("\n[book V5 시리즈] n=%d, realized_ym 범위 %s ~ %s",
          nrow(book), min(book$realized_ym), max(book$realized_ym)))

## ── 3. ★날짜정렬 실증 (cor-offset, retraction 교훈) ──
## book ret_book(realized) vs fof net을 결정월/실현월 두 가설로 정렬해 상관 최대 offset 탐색.
## fof net@date=t 는 [t,t+1m] 실현 → realized_ym = month(t)+1.
## 가설 A: fof realized_ym = ym_decision (정렬 오류 가정)
## 가설 B: fof realized_ym = ym_decision + 1month (PIT 정석)
add_month <- function(ym, k){
  d <- as.Date(paste0(ym,"-01")); d2 <- seq(d, by=paste(k,"month"), length.out=2)[2]; format(d2,"%Y-%m")
}
fof[, ym_realA := ym_decision]
fof[, ym_realB := sapply(ym_decision, add_month, k=1)]

probe <- data.table()
for(off in -3:3){
  fof[, ym_probe := sapply(ym_decision, add_month, k=off)]
  m <- merge(fof[,.(ym_probe, net)], book[,.(ym_probe=realized_ym, ret_book)], by="ym_probe")
  if(nrow(m) >= 24){
    cc <- cor(m$net, m$ret_book, use="complete.obs")
    probe <- rbind(probe, data.table(offset=off, n=nrow(m), cor_raw=round(cc,3)))
  }
}
w("\n=== 날짜정렬 실증 (fof net vs book ret, raw 총수익 상관 by offset) ===")
for(i in 1:nrow(probe)) w(sprintf("  offset=%+d month : n=%d cor=%+.3f", probe$offset[i], probe$n[i], probe$cor_raw[i]))

## ★정렬 = 지상검증(ground-truth) 캘린더 핀(probe_align6 실증, authoritative):
##   fof BM_Ret@(label L)  → 시장 월 L-1 실현 (cor +0.997, fof BM=시장 그자체)
##   book ret@(realized_ym R) → 시장 월 R-1 실현 (cor +0.716, ret_orig=팩터슬리브)
##   ⇒ 두 시리즈 동일 라벨규약(label = 실현월+1). 따라서 fof date-label = book realized_ym 을
##     ★offset 0 으로 직접 매칭하면 동일 실현월. (strategy-vs-strategy gross cor는 V5가
##     beta-reduced라 음수여도 무방 — 캘린더 핀은 BM↔시장 +0.997이 authoritative.)
ALIGN <- 0L
w(sprintf("  → 채택 정렬 offset = %+d (ground-truth BM↔시장 캘린더 핀: fof BM cor +0.997, book ret_orig cor +0.716 둘 다 동일 offset). strategy gross cor는 V5 beta-mgmt로 비대표.", ALIGN))
fof[, realized_ym := ym_decision]

## ── 4. 공통 realized 패널 구성 (active basis) ──
## book active: book ret − BM. fof BM_Ret@label 과 book realized_ym@label 은 동일 실현월(offset 0).
## 따라서 book도 동일 label로 BM 직접 매칭 (fof와 같은 벤치·같은 월 = 공정 active).
bench_dt[, realized_ym := ym_decision]   # fof BM label = book realized_ym label (캘린더 핀)
book2 <- merge(book, bench_dt[,.(realized_ym, BM)], by="realized_ym", all.x=TRUE)
book2[, act_book := ret_book - BM]
w(sprintf("\n[book active] BM merge 결측=%d (offset0 정렬, fof와 동일 BM월)", sum(is.na(book2$BM))))

P <- merge(fof[,.(realized_ym, fof_net=net, fof_act=act)],
           book2[,.(realized_ym, book_net=ret_book, book_act=act_book)],
           by="realized_ym")
setorder(P, realized_ym)
P <- P[is.finite(fof_act) & is.finite(book_act)]
w(sprintf("\n[공통 realized 패널] n=%d, 범위 %s ~ %s",
          nrow(P), min(P$realized_ym), max(P$realized_ym)))

## ── 5. 상관 (gross & active, metric_type 라벨) ──
cor_gross <- cor(P$fof_net, P$book_net)
cor_active <- cor(P$fof_act, P$book_act)
w("\n=== 상관 (metric_type=canonical_screen for fof / backtested for book) ===")
w(sprintf("  gross(총수익) 상관  : %+.3f  [시장β 공유분 포함]", cor_gross))
w(sprintf("  active(−BM) 상관   : %+.3f  [book-marginal 핵심 — 낮을수록 직교]", cor_active))

## ── 6. PIT 확장윈도 잔차화 + ΔactiveIR (book-marginal 게이트 ≥0.05) ──
## incumbent book active IR (전기간) vs fof를 추가했을 때 결합 book active IR.
## 결합 비중: book-marginal 표준 = book에 fof를 Δ로 추가. 단순 균등 결합(0.5/0.5)은 임의 →
## measurement-graduation §4 book-marginal = "new_book vs incumbent ΔIR".
## 여기선 fof 자체의 incremental IR을 PIT 확장윈도 잔차화로 측정:
##   각 t에서 t 이전 데이터로만 book_act ~ fof_act 회귀 불필요 — 잔차화는 *동시점* 직교성.
## 표준 절차(measurement-graduation): fof_act를 book_act에 회귀한 잔차의 IR이 fof의 "book이 못 가진" 기여.
## 단 회귀계수도 PIT여야 함(확장윈도 β로 t시점 잔차 산출).
ann012 <- function(x) mean(x)/sd(x)*sqrt(12)  # active IR (월→연)

ir_book <- ann012(P$book_act)
ir_fof  <- ann012(P$fof_act)
w("\n=== active IR (전기간, 단일 기준) ===")
w(sprintf("  incumbent book(V5) active IR : %+.3f", ir_book))
w(sprintf("  fof standalone   active IR : %+.3f", ir_fof))

## (a) full-sample 잔차화 (진단·낙관 상한)
fit_full <- lm(fof_act ~ book_act, data=P)
P[, fof_resid_full := residuals(fit_full)]
ir_resid_full <- ann012(P$fof_resid_full)
beta_full <- coef(fit_full)[2]
w(sprintf("\n[full-sample 잔차화 (진단상한)] β(fof~book)=%+.3f, fof⊥book active IR=%+.3f", beta_full, ir_resid_full))

## (b) PIT 확장윈도 잔차화 (정석): 각 t에서 [first, t-1] OLS β로 t 잔차
P[, idx := .I]
minw <- 36L  # 최소 36개월 후 시작 (β 안정)
P[, fof_resid_pit := NA_real_]
for(i in (minw+1):nrow(P)){
  tr <- P[1:(i-1)]
  ft <- tryCatch(lm(fof_act ~ book_act, data=tr), error=function(e) NULL)
  if(is.null(ft)) next
  b0 <- coef(ft)[1]; b1 <- coef(ft)[2]
  P[i, fof_resid_pit := fof_act - (b0 + b1*book_act)]
}
pit_res <- P[is.finite(fof_resid_pit)]
ir_resid_pit <- ann012(pit_res$fof_resid_pit)
w(sprintf("[PIT 확장윈도 잔차화] n_eval=%d (start idx %d), fof⊥book active IR=%+.3f",
          nrow(pit_res), minw+1, ir_resid_pit))

## ── 7. ★book-marginal ΔIR (measurement-graduation §4 정석) ──
## new_book = book + λ·fof (active). incumbent = book. ΔIR = IR(new_book) − IR(book).
## λ 결정: book-marginal 표준은 "fof를 sleeve로 추가시 book IR 증분".
## 가장 정직한 측정 = book_act에 fof_act를 추가했을 때 결합 active IR 최대화 λ(단 in-sample 최적화는 낙관).
## 보고: ① 균등증분 λ=0.5 ② IR-최적 λ(진단) ③ PIT 점진 λ.
combine_ir <- function(lam) ann012((1-lam)*P$book_act + lam*P$fof_act)
lam_grid <- seq(0, 1, by=0.05)
irs <- sapply(lam_grid, combine_ir)
lam_opt <- lam_grid[which.max(irs)]
ir_combo_opt <- max(irs)
ir_combo_half <- combine_ir(0.5)
dIR_opt  <- ir_combo_opt - ir_book
dIR_half <- ir_combo_half - ir_book
w("\n=== book-marginal ΔIR (active basis, §4 게이트 ≥0.05) ===")
w(sprintf("  λ=0.50 균등결합 active IR=%+.3f  ΔIR=%+.3f", ir_combo_half, dIR_half))
w(sprintf("  λ-최적(=%.2f, 진단상한) active IR=%+.3f  ΔIR=%+.3f", lam_opt, ir_combo_opt, dIR_opt))

## PIT 점진 λ: 각 t에서 [first,t-1]로 IR최적 λ 산출 → t에 적용 → 결합 active 시계열 → 전기간 IR
P[, combo_pit := NA_real_]
for(i in (minw+1):nrow(P)){
  tr <- P[1:(i-1)]
  ig <- sapply(lam_grid, function(l) { v<-(1-l)*tr$book_act + l*tr$fof_act; mean(v)/sd(v)*sqrt(12) })
  lo <- lam_grid[which.max(ig)]
  P[i, combo_pit := (1-lo)*book_act + lo*fof_act]
}
pit_combo <- P[is.finite(combo_pit)]
ir_combo_pit <- ann012(pit_combo$combo_pit)
## incumbent over same eval window (공정 비교)
ir_book_evalwin <- ann012(pit_combo$book_act)
dIR_pit <- ir_combo_pit - ir_book_evalwin
w(sprintf("  PIT 점진 λ 결합 active IR=%+.3f vs incumbent(동창)=%+.3f  ΔIR=%+.3f  [n_eval=%d]",
          ir_combo_pit, ir_book_evalwin, dIR_pit, nrow(pit_combo)))

## ── 8. paired-NW-t: 결합 active vs incumbent active (SR 비율비교 금지 준수) ──
## 월별 (combo_act − book_act) on PIT 점진 결합 → NW lag3 t. >0 유의시 통계적 기여.
pairdt <- pit_combo[,.(d = combo_pit - book_act)]
fpt <- lm(d ~ 1, data=pairdt)
t_pair <- as.numeric(coeftest(fpt, vcov=NeweyWest(fpt, lag=3, prewhite=FALSE))[1,3])
w(sprintf("\n=== paired-NW-t (PIT결합active − incumbentactive, lag3) ==="))
w(sprintf("  mean Δactive/월=%+.4f%%  paired-NW-t=%+.2f  [>2 = 유의 증분]", 100*mean(pairdt$d), t_pair))

## fof_resid_pit IR이 0보다 유의한가 (직교 기여 자체 검정)
fres <- lm(fof_resid_pit ~ 1, data=pit_res)
t_resid <- as.numeric(coeftest(fres, vcov=NeweyWest(fres, lag=3, prewhite=FALSE))[1,3])
w(sprintf("  fof⊥book 잔차 mean=%+.4f%%/월 NW-t=%+.2f  [직교성분 자체의 유의성]", 100*mean(pit_res$fof_resid_pit), t_resid))

## ── 9. 판정 ──
w("\n================ 판정 ================")
gate_pass <- (dIR_pit >= 0.05)
w(sprintf("  active 상관 = %+.3f", cor_active))
w(sprintf("  ΔIR (PIT 점진, authoritative) = %+.3f  vs 게이트 0.05 → %s",
          dIR_pit, ifelse(gate_pass, "PASS", "FAIL")))
w(sprintf("  ΔIR (λ=0.5) = %+.3f / ΔIR(λ-opt 상한) = %+.3f", dIR_half, dIR_opt))
w(sprintf("  paired-NW-t = %+.2f", t_pair))
w(sprintf("  → book-marginal 판정: %s", ifelse(gate_pass && t_pair>0, "기여 있음 (등록 검토)",
       ifelse(dIR_opt>=0.05, "상한만 통과 — 약함/screen-tier", "기여 미입증 — screen-tier"))))

## 저장
out <- list(
  n_common=nrow(P), align_offset=ALIGN,
  cor_gross=cor_gross, cor_active=cor_active,
  ir_book=ir_book, ir_fof=ir_fof,
  ir_resid_full=ir_resid_full, ir_resid_pit=ir_resid_pit,
  dIR_half=dIR_half, dIR_opt=dIR_opt, lam_opt=lam_opt, dIR_pit=dIR_pit,
  t_pair=t_pair, t_resid=t_resid, gate_pass=gate_pass, probe=probe)
saveRDS(out, file.path(OUT,"_fof_book_marginal.rds"))
fwrite(P, file.path(OUT,"book_marginal_panel.csv"))
cat("BMARG|", sprintf("cor_act=%.3f dIR_pit=%.3f dIR_opt=%.3f t_pair=%.2f gate=%s",
    cor_active, dIR_pit, dIR_opt, t_pair, gate_pass), "\n")
close(con); cat("FOF_BOOK_MARGINAL_DONE\n")
