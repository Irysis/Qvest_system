## deltair_diag.R — RAMP_03C 재현 next_probe #2 소비: EW/score-tilt variant book-marginal ΔIR 진단 (태스크 #66)
##
## 성격: 진단 전용. book_state 쓰기 없음 · admission 선언 없음 — 결과 = "도훈 결정 재료"(governor 수동, §4).
## 컨벤션: ΔIR = new_book_ir − incumbent_book_ir, ir_convention = net_active_recon_v1
##   (recon NAV 월수익 net − KOSPI200 active, mean/sd*sqrt(12) — contract build_benchmark_compare ann=12).
## 엔진: portfolio_governor.R::.pg_book_ir_recon() 재사용 (Return.portfolio 월리밸 + build_benchmark_compare).
##   book_optimize QP는 incumbent 3-package mailbox 부재로 불가(book_state.json provenance note) —
##   governor의 §4 recon 어댑터(2026-07-03 도훈 confirm 신설)가 본 케이스의 canonical 경로. 자체 IR 구현 없음.
## w-그리드 {0.05,0.10,0.15,0.20}: 진단 그리드 — 선택 연산자 없음(전 그리드 보고) → DSR sweep 게이트 비적용
##   (measurement-graduation §3 selection operator 기준). w=0 행 = 공통창-matched incumbent 기준선.
## pin: ramp03c_rerun_20260713_205545 재사용 (§7 vintage pinning). OneDrive 산출은 tmp+rename.
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
suppressMessages({library(sandwich); library(lmtest)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM, "stage_artifacts/WT_RAMP_03C_RERUN_20260713")
DG <- file.path(WT, "deltair_diag"); dir.create(DG, showWarnings=FALSE, recursive=TRUE)
SCR <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/3d6b0eb6-6786-4a56-916d-9681f94897fe/scratchpad"

source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/factor_validation.R")            # build_monthly_forward_returns
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/data/pin_cache.R")
source("02_Infrastructure/portfolio/portfolio_governor.R")      # .pg_book_ir_recon / .pg_bm_monthly_returns

## OneDrive 안전 저장: tmp 쓰기 후 rename
save_rds_safe <- function(obj, path){tmp <- paste0(path, ".tmp_", Sys.getpid()); saveRDS(obj, tmp)
  if (file.exists(path)) file.remove(path); ok <- file.rename(tmp, path); if(!ok) stop("rename 실패: ", path)}
write_json_safe <- function(txt, path){tmp <- paste0(path, ".tmp_", Sys.getpid()); writeLines(txt, tmp, useBytes=TRUE)
  if (file.exists(path)) file.remove(path); ok <- file.rename(tmp, path); if(!ok) stop("rename 실패: ", path)}

## helpers (rerun_ramp03c.R과 동일 — construction drift 방지 위해 verbatim)
zc <- function(x){m<-mean(x,na.rm=T); s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-m else (x-m)/s}
cap_norm <- function(w){w[!is.finite(w)|w<0]<-0; if(sum(w)<=0) return(rep(1/length(w),length(w))); w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break; w[w>0.20]<-0.20; rem<-1-sum(w); ix<-w<0.20
    if(sum(ix)==0||rem<=0)break; w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])}; w[w>0.20]<-0.20; w/sum(w)}
ny <- function(d){m<-as.integer(format(d,"%m")); y<-as.integer(format(d,"%Y"))
  sprintf("%04d-%02d", ifelse(m==12,y+1,y), ifelse(m==12,1,m+1))}
ym_shift <- function(ym, k){mi <- as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7)) + as.integer(k)
  sprintf("%04d-%02d", (mi-1L)%/%12L, (mi-1L)%%12L+1L)}

## ---- 0) vintage pin 재사용 (§7) ----
RAW <- ".cache/RAWDATA.parquet"; BM <- ".cache/benchmark.parquet"
PINTAG <- "ramp03c_rerun_20260713_205545"
RAWp <- read_pinned(RAW, PINTAG); BMp <- read_pinned(BM, PINTAG)
md5_bm_live <- unname(tools::md5sum(.PG_BENCHMARK_PARQUET))   # governor 내부 BM 소스
md5_bm_pin  <- unname(tools::md5sum(BMp))
cat("PIN_TAG=", PINTAG, "\n")
cat(sprintf("BM md5 live(%s)=%s / pin=%s / equal=%s\n", .PG_BENCHMARK_PARQUET, md5_bm_live, md5_bm_pin,
            identical(md5_bm_live, md5_bm_pin)))
if (!identical(md5_bm_live, md5_bm_pin))
  stop("canonical BM(.PG_BENCHMARK_PARQUET)이 pin과 불일치 — vintage 오염. 중단.")

## ---- 1) variant 시계열 재생성 (rerun_ramp03c.R §1~6 verbatim 재현 — EW/score-tilt만) ----
need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret")
rd <- as.data.table(read_parquet(RAWp, col_select=all_of(need))); rd[, Date:=as.Date(Date)]
rd <- rd[Date>=as.Date("2004-06-01")]
rd[, ym:=format(Date,"%Y-%m")]
mend <- rd[,.(md=max(Date)), by=ym]; setorder(mend, md)
sig_dates <- mend$md[format(mend$md,"%Y-%m")>="2005-01"]
fwd <- build_monthly_forward_returns(rd, sig_dates)
fwd_ret <- fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_proxy <- fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]
liq <- fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
dts <- sort(unique(fwd_ret$Date)); ND <- length(dts)
cat(sprintf("fwd dts: %d (%s ~ %s)\n", ND, as.character(min(dts)), as.character(max(dts))))

umend <- merge(rd, mend, by.x=c("ym","Date"), by.y=c("ym","md"))
umend[, inu:=(!is.na(K200)&K200==TRUE)|(!is.na(KQ150)&KQ150==TRUE)]
UNI <- umend[inu==TRUE, .(Date,Ticker,Size)]

bkp <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"
bk <- as.data.table(read_parquet(bkp))[,.(ym=format(as.Date(Date),"%Y-%m"),Ticker,se=score_eff)][is.finite(se)]

mom6 <- c("M05_Trended_Mom","M32_Composite_Mom_v2","M09_Composite_Mom","M13_VolAdj_Mom","M01_Mom_12_1","M08_Residual_Mom")
ZLpath <- file.path(SCR, "zl_mom6.rds")
if (file.exists(ZLpath)) {ZL <- readRDS(ZLpath); cat("ZL cache loaded\n")} else {
  ZL <- list(); for (d in as.character(dts)) {f <- tryCatch(as.data.table(load_month_factors(as.Date(d), factor_names=mom6)), error=function(e) NULL)
    if (is.null(f)||nrow(f)==0) next; w <- dcast(f, Ticker~Factor_Name, value.var="Z_Score_Aligned"); ZL[[d]] <- w}
  saveRDS(ZL, ZLpath); cat("ZL built + cached\n")}

SC <- list()
for (i in seq_len(ND)) {d <- dts[i]; dk <- as.character(d)
  uni <- UNI[Date==d]; if (nrow(uni)<25) next
  b <- bk[ym==ny(d), .(Ticker, bz=zc(se))]
  fw <- ZL[[dk]]
  dm <- data.table(Ticker=uni$Ticker, Size=uni$Size)
  if (!is.null(fw)) {
    mm <- copy(fw); for (mid in mom6) {if (mid %in% names(mm)) mm[[mid]] <- zc(mm[[mid]]) else mm[[mid]] <- NA_real_}
    mm[, mom6:=rowMeans(as.matrix(.SD), na.rm=TRUE), .SDcols=mom6]
    dm <- merge(dm, mm[,.(Ticker,mom6)], by="Ticker", all.x=TRUE)
  } else dm[, mom6:=NA_real_]
  dm <- merge(dm, b, by="Ticker", all.x=TRUE)
  dm[!is.finite(mom6), mom6:=0]
  dm <- dm[is.finite(bz)]
  dm <- merge(dm, liq[Date==d,.(Ticker,adv)], by="Ticker", all.x=TRUE); dm <- dm[is.na(adv)|adv>=2e8]
  if (nrow(dm)<25) next
  dm[, score:=0.5*bz+0.5*mom6]
  dm[, Date:=d]; SC[[dk]] <- dm}
SCdt <- rbindlist(SC, fill=TRUE)
cat(sprintf("SCdt months: %d (%s ~ %s)\n", uniqueN(SCdt$Date), as.character(min(SCdt$Date)), as.character(max(SCdt$Date))))

mk_weights <- function(scorecol, wtype){
  W <- list(); uds <- sort(unique(SCdt$Date))
  for (di in seq_along(uds)) {d <- uds[di]; sub <- SCdt[Date==d][is.finite(get(scorecol))]; if (nrow(sub)<5) next
    setorderv(sub, scorecol, order=-1L)
    hd <- head(sub, 25)
    w <- switch(wtype,
      ew    = rep(1/nrow(hd), nrow(hd)),
      score = {s<-hd[[scorecol]]; s<-pmax(s-min(s)+0.1, 0.01); cap_norm(s)},
      capw  = cap_norm(hd$Size))
    W[[as.character(d)]] <- data.table(Date=d, Ticker=hd$Ticker, w=w)}
  rbindlist(W)}

r_ew <- weighted_screen_bt(mk_weights("score","ew"),    fwd_ret, bench_proxy, cost_bps_oneway=15, run_id="ew_proxy_full",    strategy_id="RAMP_03C_EW")
r_sc <- weighted_screen_bt(mk_weights("score","score"), fwd_ret, bench_proxy, cost_bps_oneway=15, run_id="score_proxy_full", strategy_id="RAMP_03C_SCORETILT")

## 재생성 충실도 게이트 — 재현 기록(verdict §2: EW 4.25 / score 4.26, proxy full) 대비
pt_ew <- r_ew$portfolio_alpha_t_nw_lag3; pt_sc <- r_sc$portfolio_alpha_t_nw_lag3
cat(sprintf("FIDELITY: pt_EW=%.4f (기록 4.25) / pt_SCORE=%.4f (기록 4.26)\n", pt_ew, pt_sc))
if (abs(pt_ew-4.25)>0.02 || abs(pt_sc-4.26)>0.02) stop("재생성 충실도 게이트 FAIL — 재현과 불일치. 중단.")

## ---- 2) incumbent recon net 시계열 (WT-D20260702_002 CLEAN ann12 — incumbent_book_ir 1.416의 원천) ----
btC <- readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
inc_pr <- as.data.table(btC$period_returns)[,.(date=as.Date(date), ret_net=as.numeric(ret_net))]
inc_bm <- as.data.table(btC$benchmark_returns)[,.(date=as.Date(date), benchmark_ret=as.numeric(benchmark_ret))]
## 저장 baseline 재현 검증: contract 경유 IR가 book_state 1.416과 일치하는지
cmp_inc <- build_benchmark_compare(
  data.table(date=inc_pr$date, ret_net=inc_pr$ret_net, frequency="monthly"),
  data.table(date=inc_bm$date, benchmark_ret=inc_bm$benchmark_ret, benchmark_id="KOSPI200"),
  run_id="deltair_inc_check", strategy_id="STR_1715_on_M4_R05_noLayer4_PG2", annualization_factor=12)
ir_inc_embedded <- as.numeric(cmp_inc[metric_name=="Information_Ratio", active_value])
bs <- fromJSON("qepm/mailbox/governor/book_state.json", simplifyVector=FALSE)
ir_stored <- as.numeric(bs$incumbent_book_ir)
cat(sprintf("incumbent IR: 재계산(embedded BM)=%.6f / book_state 저장=%.6f / diff=%.2e\n",
            ir_inc_embedded, ir_stored, ir_inc_embedded-ir_stored))

## ---- 3) 정렬 검증 ----
## 3a) incumbent 월라벨 vs canonical BM(ym) 대조 — embedded benchmark_ret가 같은 달력월 BM인지
bmm <- .pg_bm_monthly_returns(); stopifnot(!is.null(bmm$bm_m))
inc_m <- data.table(ym=format(inc_pr$date, "%Y-%m"), ret=inc_pr$ret_net,
                    bm_emb=inc_bm$benchmark_ret[match(inc_pr$date, inc_bm$date)])
chk <- merge(inc_m, bmm$bm_m[,.(ym, bm_canon=ret)], by="ym")
align_inc <- list(n=nrow(chk), max_abs_diff=max(abs(chk$bm_emb-chk$bm_canon), na.rm=TRUE),
                  cor=suppressWarnings(cor(chk$bm_emb, chk$bm_canon, use="complete.obs")))
cat(sprintf("정렬 3a (incumbent embedded vs canonical BM by ym): n=%d max|diff|=%.3e cor=%.6f\n",
            align_inc$n, align_inc$max_abs_diff, align_inc$cor))

## 3b) variant β-scan (realized_ym 규약 — [[reference-book-benchmark-alignment-realized-ym]]):
##     variant 월키 = ny(sig_date) = 수익 실현 달력월. offset −3..+3 중 0이 β·cor 최대여야 정렬 정상.
variant_m <- function(r){pr <- as.data.table(r$period_returns)
  data.table(ym=vapply(as.Date(pr$date), ny, character(1)), ret=as.numeric(pr$ret_net))}
vm_ew <- variant_m(r_ew); vm_sc <- variant_m(r_sc)
beta_scan <- function(vm, lab){rbindlist(lapply(-3:3, function(k){
  sh <- copy(vm)[, ym:=ym_shift(ym, k)]
  mg <- merge(sh, bmm$bm_m[,.(ym, bm=ret)], by="ym")
  fit <- lm(ret ~ bm, data=mg)
  data.table(variant=lab, offset=k, n=nrow(mg), beta=unname(coef(fit)[2]), cor=cor(mg$ret, mg$bm))}))}
BS <- rbind(beta_scan(vm_ew, "EW"), beta_scan(vm_sc, "SCORETILT"))
cat("정렬 3b (β-scan, offset 0 = ny(sig_date) 매핑):\n"); print(BS)
best_off <- BS[, .SD[which.max(beta)], by=variant]$offset
cat(sprintf("β-scan argmax offset: EW=%d / SCORETILT=%d (0이어야 정상)\n", best_off[1], best_off[2]))
if (any(best_off != 0L)) stop("β-scan 정렬 검증 FAIL — variant 월키 매핑 재점검 필요. 중단.")

## ---- 4) sim shell + 임시 카탈로그 (.pg_sleeve_monthly_returns 어댑터 ① 경로용) ----
## 실 module_catalog.json 비오염 — 본 진단 전용 임시 카탈로그(deltair_diag/ 안).
INC <- "STR_1715_on_M4_R05_noLayer4_PG2"; EWID <- "RAMP_03C_EW_VARIANT"; SCID <- "RAMP_03C_SCORETILT_VARIANT"
mk_shell <- function(m) list(DAILY_NAV_DT=data.table(Date=as.Date(paste0(m$ym,"-15")), Strategy_Ret=m$ret))
## (월당 1행 → apply.monthly(Return.cumulative)는 그 값 자체 — 표준함수 경유, 값 불변)
save_rds_safe(mk_shell(inc_m[,.(ym,ret)]), file.path(DG, "simshell_incumbent.rds"))
save_rds_safe(mk_shell(vm_ew),             file.path(DG, "simshell_ew.rds"))
save_rds_safe(mk_shell(vm_sc),             file.path(DG, "simshell_scoretilt.rds"))
rel <- "stage_artifacts/WT_RAMP_03C_RERUN_20260713/deltair_diag"
catl <- list(modules=setNames(list(
  list(sim_result_path=paste0(rel,"/simshell_incumbent.rds"),
       metric_type="backtested(recon net — WT-D20260702_002 bt_result_C_noL4_CLEAN_ann12, incumbent_book_ir 1.416 원천)"),
  list(sim_result_path=paste0(rel,"/simshell_ew.rds"),
       metric_type="canonical_screen(weighted_screen_bt net 15bps, ym=return-month ny(sig_date))"),
  list(sim_result_path=paste0(rel,"/simshell_scoretilt.rds"),
       metric_type="canonical_screen(weighted_screen_bt net 15bps, ym=return-month ny(sig_date))")),
  c(INC, EWID, SCID)))
CATJ <- file.path(DG, "temp_module_catalog_deltair.json")
write_json_safe(toJSON(catl, auto_unbox=TRUE, pretty=TRUE), CATJ)

## ---- 5) ΔIR 그리드 (.pg_book_ir_recon — net_active_recon_v1) ----
## S0: incumbent 단독(전체창) — 저장 baseline과의 재현 대조 (canonical BM basis)
S0 <- .pg_book_ir_recon(INC, catalog_path=CATJ)
cat(sprintf("S0 incumbent 단독 recon: IR=%.4f n=%d [%s~%s] (stored 1.416 대비 diff=%.4f)\n",
            S0$book_ir, S0$n_months, S0$period[1], S0$period[2], S0$book_ir-ir_stored))

grid_w <- c(0, 0.05, 0.10, 0.15, 0.20)
run_grid <- function(vid, vlab){rbindlist(lapply(grid_w, function(w){
  rec <- .pg_book_ir_recon(c(INC, vid), weights=c(1-w, w), catalog_path=CATJ)
  data.table(variant=vlab, w=w, new_book_ir=rec$book_ir, n_months=rec$n_months,
             period_start=rec$period[1], period_end=rec$period[2],
             port_alpha_t_nw3=rec$port_alpha_t_nw3, reason=rec$reason %||% NA_character_)}))}
G_ew <- run_grid(EWID, "EW"); G_sc <- run_grid(SCID, "SCORETILT")
G <- rbind(G_ew, G_sc)
## ΔIR 양기준: (a) §4 canonical — 저장 baseline 1.416 대비 / (b) 공통창-matched — w=0 행 대비
G[, delta_ir_vs_stored := new_book_ir - ir_stored]
G[, delta_ir_windowmatched := new_book_ir - new_book_ir[w==0], by=variant]

## variant 단독 net-active IR (문맥, 동일 컨벤션 라벨)
V_ew <- .pg_book_ir_recon(EWID, catalog_path=CATJ); V_sc <- .pg_book_ir_recon(SCID, catalog_path=CATJ)

## ---- 6) 상관 (공통창) — gross(net-net)와 active(−BM) 양 basis 라벨 병기 (§6 규약) ----
cor_block <- function(vm, lab){
  mg <- merge(vm, inc_m[,.(ym, book=ret)], by="ym")
  mg <- merge(mg, bmm$bm_m[,.(ym, bm=ret)], by="ym")
  data.table(variant=lab, n=nrow(mg),
             cor_gross=cor(mg$ret, mg$book),
             cor_active=cor(mg$ret-mg$bm, mg$book-mg$bm))}
CORS <- rbind(cor_block(vm_ew, "EW"), cor_block(vm_sc, "SCORETILT"))

## ---- 7) 판정 라벨(진단) + 산출 저장 ----
G <- merge(G, CORS[,.(variant, cor_gross, cor_active)], by="variant")
G[, pass_deltair_stored := delta_ir_vs_stored >= 0.05]
G[, pass_deltair_matched := delta_ir_windowmatched >= 0.05]
G[, cor_lt_030_gross := abs(cor_gross) < 0.30]
G[, cor_lt_030_active := abs(cor_active) < 0.30]
setorder(G, variant, w)

cat("\n===== book-marginal ΔIR 진단 그리드 (net_active_recon_v1) =====\n")
cat(sprintf("incumbent_book_ir(stored, book_state)=%.4f | S0 recon(canonical BM, 전체창)=%.4f\n", ir_stored, S0$book_ir))
cat(sprintf("  %-10s %-5s %4s %12s %14s %16s %8s %9s %10s\n",
            "variant","w","n","new_book_ir","dIR_vs_stored","dIR_windowmatch","pt_nw3","cor_gross","cor_active"))
for (i in seq_len(nrow(G))) {g <- G[i]
  cat(sprintf("  %-10s %5.2f %4d %12.4f %+14.4f %+16.4f %8.2f %9.3f %10.3f\n",
      g$variant, g$w, g$n_months, g$new_book_ir, g$delta_ir_vs_stored, g$delta_ir_windowmatched,
      g$port_alpha_t_nw3, g$cor_gross, g$cor_active))}
cat(sprintf("\nvariant 단독 net-active IR (공통창, 문맥): EW=%.4f (n=%d) / SCORETILT=%.4f (n=%d)\n",
            V_ew$book_ir, V_ew$n_months, V_sc$book_ir, V_sc$n_months))

out <- list(
  task="#66 RAMP_03C EW/score-tilt variant book-marginal deltaIR 진단 (next_probe #2 소비)",
  as_of="2026-07-13", pin_tag=PINTAG,
  governance=paste0("진단 전용 — book_state 쓰기·admission 선언 없음(도훈 결정 재료). governor admit 수동(§4). ",
                    "w-그리드는 진단 목적 전수 보고(선택 연산자 없음) — DSR sweep 게이트 비적용(§3 selection operator 기준)."),
  ir_convention="net_active_recon_v1 (portfolio_governor.R::.pg_book_ir_recon — Return.portfolio 월리밸 + build_benchmark_compare ann=12)",
  engine_note=paste0("book_optimize QP는 incumbent 3-package mailbox 부재로 불가(book_state provenance note) — ",
                     "governor §4 recon 어댑터가 canonical 경로. 임시 카탈로그(deltair_diag/ 전용)로 시계열 공급, 실 module_catalog 비오염."),
  incumbent=list(id=INC, ir_stored=ir_stored,
                 ir_recon_embedded_bm=ir_inc_embedded,
                 ir_recon_canonical_bm_fullwindow=S0$book_ir, n_months_full=S0$n_months),
  fidelity_gate=list(pt_ew=pt_ew, pt_scoretilt=pt_sc, recorded=c(4.25, 4.26), pass=TRUE),
  alignment=list(
    incumbent_embedded_vs_canonical_bm=align_inc,
    variant_month_key="ny(sig_date) = 수익 실현 달력월 ([[reference-book-benchmark-alignment-realized-ym]] 규약)",
    beta_scan=BS, beta_scan_argmax_offset=as.list(setNames(best_off, c("EW","SCORETILT"))), pass=TRUE),
  bm_md5=list(live=md5_bm_live, pinned=md5_bm_pin, equal=identical(md5_bm_live, md5_bm_pin)),
  variant_standalone_net_active_ir=list(EW=V_ew$book_ir, SCORETILT=V_sc$book_ir,
                                        n_months=c(V_ew$n_months, V_sc$n_months),
                                        basis="net_active_recon_v1 — 단독 sleeve vs KOSPI200 (문맥용, 자본판정 아님)"),
  grid=G,
  labels=list(delta_ir_primary="delta_ir_vs_stored (§4 canonical: new_book_ir − book_state incumbent_book_ir 1.416)",
              delta_ir_secondary="delta_ir_windowmatched (공통창 w=0 기준 — 창 차이 진단용)",
              cor_note="cor_gross=net-net(시장성분 포함) / cor_active=(−BM) — §6 basis 라벨 의무. §3 보강증거 |cor|<0.30 인용 시 basis 명기")
)
write_json_safe(toJSON(out, auto_unbox=TRUE, pretty=TRUE, digits=8, dataframe="rows", na="null"),
                file.path(DG, "deltair_grid_results.json"))
save_rds_safe(list(G=G, S0=S0, V_ew=V_ew, V_sc=V_sc, BS=BS, CORS=CORS, align_inc=align_inc,
                   vm_ew=vm_ew, vm_sc=vm_sc, inc_m=inc_m, ir_stored=ir_stored,
                   fidelity=c(pt_ew=pt_ew, pt_sc=pt_sc), pin_tag=PINTAG),
              file.path(DG, "deltair_diag_results.rds"))
cat("\nDELTAIR_DIAG_DONE\n")
