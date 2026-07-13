## deltair_fix_alignment.R — 태스크 #66 정정 라운드: incumbent 월라벨 정렬 수리 후 그리드 재산출
##
## 1차 실행(deltair_diag.R)의 정렬검증 3a가 실측으로 잡은 결함:
##   incumbent bt(period_returns) date 라벨 = eval-anchor월 → 수익 실현 달력월보다 +1개월
##   ([[reference-book-benchmark-alignment-realized-ym]] realized_ym +1 라벨 규약 — 외부 조인은 −1 shift 의무).
##   증상: embedded vs canonical BM by ym cor 0.136 / S0 recon 0.848 ≠ stored 1.416.
##   variant는 calendar-correct(β-scan argmax 0) → 1차 그리드는 두 sleeve가 1개월 어긋난 채 blend = 무효(supersede).
## 본 스크립트: offset-scan으로 −1 확정 실증 → incumbent ym−1 정정 → S0·그리드·cor 재산출 → json 갱신.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setDTthreads(1)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM, "stage_artifacts/WT_RAMP_03C_RERUN_20260713")
DG <- file.path(WT, "deltair_diag")

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/portfolio/portfolio_governor.R")

save_rds_safe <- function(obj, path){tmp <- paste0(path, ".tmp_", Sys.getpid()); saveRDS(obj, tmp)
  if (file.exists(path)) file.remove(path); ok <- file.rename(tmp, path); if(!ok) stop("rename 실패: ", path)}
write_json_safe <- function(txt, path){tmp <- paste0(path, ".tmp_", Sys.getpid()); writeLines(txt, tmp, useBytes=TRUE)
  if (file.exists(path)) file.remove(path); ok <- file.rename(tmp, path); if(!ok) stop("rename 실패: ", path)}
ym_shift <- function(ym, k){mi <- as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7)) + as.integer(k)
  sprintf("%04d-%02d", (mi-1L)%/%12L, (mi-1L)%%12L+1L)}
`%||%` <- function(a,b) if (!is.null(a) && !all(is.na(a))) a else b

R1 <- readRDS(file.path(DG, "deltair_diag_results.rds"))   # 1차 실행 보존물 (vm_ew/vm_sc/inc_m/ir_stored/...)
inc_m <- R1$inc_m; vm_ew <- R1$vm_ew; vm_sc <- R1$vm_sc; ir_stored <- R1$ir_stored
bmm <- .pg_bm_monthly_returns(); stopifnot(!is.null(bmm$bm_m))

## ---- A) incumbent 라벨 offset-scan (embedded BM ↔ canonical BM 대조 + ret β-scan) ----
off_scan <- rbindlist(lapply(-3:3, function(k){
  sh <- copy(inc_m)[, ym:=ym_shift(ym, k)]
  mg <- merge(sh, bmm$bm_m[,.(ym, bm_canon=ret)], by="ym")
  fit <- lm(ret ~ bm_canon, data=mg)
  data.table(offset=k, n=nrow(mg),
             bm_max_abs_diff=max(abs(mg$bm_emb-mg$bm_canon), na.rm=TRUE),
             bm_cor=suppressWarnings(cor(mg$bm_emb, mg$bm_canon, use="complete.obs")),
             ret_beta=unname(coef(fit)[2]), ret_cor=cor(mg$ret, mg$bm_canon))}))
cat("incumbent offset-scan (embedded BM 일치 + ret beta):\n"); print(off_scan)
k_star <- off_scan[which.min(bm_max_abs_diff), offset]
cat(sprintf("확정 offset k*=%d (bm_max_abs_diff=%.3e, bm_cor=%.6f, ret_beta=%.3f)\n",
            k_star, off_scan[offset==k_star, bm_max_abs_diff], off_scan[offset==k_star, bm_cor],
            off_scan[offset==k_star, ret_beta]))
if (k_star != -1L) stop("예상(−1)과 다른 offset — 수동 점검 필요. 중단.")
if (off_scan[offset==k_star, bm_max_abs_diff] > 1e-6)
  cat("주의: k*에서도 embedded/canonical BM 잔차 >1e-6 — BM 집계 방식 차이 소지, 값 기록.\n")

## ---- B) incumbent shell 정정 (ym − 1 = return_ym) + S0 재산출 ----
inc_fix <- copy(inc_m)[, ym:=ym_shift(ym, -1L)]
mk_shell <- function(m) list(DAILY_NAV_DT=data.table(Date=as.Date(paste0(m$ym,"-15")), Strategy_Ret=m$ret))
save_rds_safe(mk_shell(inc_fix[,.(ym,ret)]), file.path(DG, "simshell_incumbent.rds"))
CATJ <- file.path(DG, "temp_module_catalog_deltair.json")
INC <- "STR_1715_on_M4_R05_noLayer4_PG2"; EWID <- "RAMP_03C_EW_VARIANT"; SCID <- "RAMP_03C_SCORETILT_VARIANT"

S0 <- .pg_book_ir_recon(INC, catalog_path=CATJ)
cat(sprintf("S0(정정) incumbent 단독 recon: IR=%.4f n=%d [%s~%s] (stored 1.416 diff=%+.4f)\n",
            S0$book_ir, S0$n_months, S0$period[1], S0$period[2], S0$book_ir-ir_stored))

## ---- C) 그리드 재산출 ----
grid_w <- c(0, 0.05, 0.10, 0.15, 0.20)
run_grid <- function(vid, vlab){rbindlist(lapply(grid_w, function(w){
  rec <- .pg_book_ir_recon(c(INC, vid), weights=c(1-w, w), catalog_path=CATJ)
  data.table(variant=vlab, w=w, new_book_ir=rec$book_ir, n_months=rec$n_months,
             period_start=rec$period[1], period_end=rec$period[2],
             port_alpha_t_nw3=rec$port_alpha_t_nw3, reason=rec$reason %||% NA_character_)}))}
G <- rbind(run_grid(EWID, "EW"), run_grid(SCID, "SCORETILT"))
G[, delta_ir_vs_stored := new_book_ir - ir_stored]
G[, delta_ir_windowmatched := new_book_ir - new_book_ir[w==0], by=variant]
V_ew <- .pg_book_ir_recon(EWID, catalog_path=CATJ); V_sc <- .pg_book_ir_recon(SCID, catalog_path=CATJ)

## ---- D) 상관 (정정 정렬, gross/active 양 basis) ----
cor_block <- function(vm, lab){
  mg <- merge(vm, inc_fix[,.(ym, book=ret)], by="ym")
  mg <- merge(mg, bmm$bm_m[,.(ym, bm=ret)], by="ym")
  data.table(variant=lab, n=nrow(mg),
             cor_gross=cor(mg$ret, mg$book),
             cor_active=cor(mg$ret-mg$bm, mg$book-mg$bm))}
CORS <- rbind(cor_block(vm_ew, "EW"), cor_block(vm_sc, "SCORETILT"))
G <- merge(G, CORS[,.(variant, cor_gross, cor_active)], by="variant")
G[, pass_deltair_stored := delta_ir_vs_stored >= 0.05]
G[, pass_deltair_matched := delta_ir_windowmatched >= 0.05]
G[, cor_lt_030_gross := abs(cor_gross) < 0.30]
G[, cor_lt_030_active := abs(cor_active) < 0.30]
setorder(G, variant, w)

cat("\n===== [정정] book-marginal ΔIR 진단 그리드 (net_active_recon_v1, incumbent return_ym 정렬) =====\n")
cat(sprintf("incumbent_book_ir(stored)=%.4f | S0 recon(정정, canonical BM 전체창)=%.4f\n", ir_stored, S0$book_ir))
cat(sprintf("  %-10s %-5s %4s %12s %14s %16s %8s %9s %10s\n",
            "variant","w","n","new_book_ir","dIR_vs_stored","dIR_windowmatch","pt_nw3","cor_gross","cor_active"))
for (i in seq_len(nrow(G))) {g <- G[i]
  cat(sprintf("  %-10s %5.2f %4d %12.4f %+14.4f %+16.4f %8.2f %9.3f %10.3f\n",
      g$variant, g$w, g$n_months, g$new_book_ir, g$delta_ir_vs_stored, g$delta_ir_windowmatched,
      g$port_alpha_t_nw3, g$cor_gross, g$cor_active))}
cat(sprintf("\nvariant 단독 net-active IR: EW=%.4f / SCORETILT=%.4f (n=%d/%d)\n",
            V_ew$book_ir, V_sc$book_ir, V_ew$n_months, V_sc$n_months))

## ---- E) json 갱신 (1차 무효 그리드 supersede + 정렬사고 기록 보존) ----
out <- list(
  task="#66 RAMP_03C EW/score-tilt variant book-marginal deltaIR 진단 (next_probe #2 소비) — v2 정렬 정정판",
  as_of="2026-07-13", pin_tag=R1$pin_tag,
  governance=paste0("진단 전용 — book_state 쓰기·admission 선언 없음(도훈 결정 재료). governor admit 수동(§4). ",
                    "w-그리드는 진단 목적 전수 보고(선택 연산자 없음) — DSR sweep 게이트 비적용(§3 selection operator 기준)."),
  ir_convention="net_active_recon_v1 (portfolio_governor.R::.pg_book_ir_recon — Return.portfolio 월리밸 + build_benchmark_compare ann=12)",
  engine_note=paste0("book_optimize QP는 incumbent 3-package mailbox 부재로 불가(book_state provenance note) — ",
                     "governor §4 recon 어댑터가 canonical 경로. 임시 카탈로그(deltair_diag/ 전용), 실 module_catalog 비오염."),
  alignment_incident=list(
    caught_by="1차 실행 정렬검증 3a (embedded vs canonical BM by ym: cor 0.136, max|diff| 0.387) + S0 0.848≠1.416",
    root_cause=paste0("incumbent bt(WT-D20260702_002 CLEAN) period_returns date = eval-anchor월 라벨 — 수익 실현 달력월+1 ",
                      "(realized_ym +1 규약, [[reference-book-benchmark-alignment-realized-ym]]). 외부 조인 시 −1 shift 의무."),
    fix="incumbent ym − 1개월 = return_ym. offset-scan 실증: k*=−1에서 embedded↔canonical BM 일치 + ret β 최대.",
    offset_scan=off_scan,
    first_run_grid="무효(supersede) — deltair_diag.log의 1차 그리드(incumbent 라벨 오정렬 blend)는 인용 금지.",
    note="incumbent IR 1.416 자체는 행-정렬 산출이라 불변(재현 diff 2.6e-05). 라벨만 정정."),
  incumbent=list(id=INC, ir_stored=ir_stored,
                 ir_recon_embedded_bm=1.416026,   # 1차 실행 contract 재계산(행-정렬 embedded BM) — 라벨 정정과 무관 불변

                 ir_recon_canonical_bm_fullwindow_aligned=S0$book_ir, n_months_full=S0$n_months,
                 s0_vs_stored_diff=S0$book_ir-ir_stored),
  fidelity_gate=list(pt_ew=unname(R1$fidelity["pt_ew"]), pt_scoretilt=unname(R1$fidelity["pt_sc"]),
                     recorded=c(4.25, 4.26), pass=TRUE),
  alignment=list(
    variant_month_key="ny(sig_date) = 수익 실현 달력월 — β-scan argmax offset 0 (EW β 0.907/cor 0.739 · SCORETILT β 0.901/cor 0.677)",
    incumbent_month_key="bt date월 − 1 = return_ym — offset-scan k*=−1 실증(본 json alignment_incident.offset_scan)",
    beta_scan_variants=R1$BS, pass=TRUE),
  bm_md5=list(pinned="c178d9b45b19692237e0e9564d5366ba", equal_live_pin=TRUE),
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
save_rds_safe(list(G=G, S0=S0, V_ew=V_ew, V_sc=V_sc, off_scan=off_scan, CORS=CORS,
                   inc_fix=inc_fix, vm_ew=vm_ew, vm_sc=vm_sc, ir_stored=ir_stored,
                   pin_tag=R1$pin_tag, superseded_v1=R1$G),
              file.path(DG, "deltair_diag_results_v2.rds"))
cat("\nDELTAIR_FIX_DONE\n")
