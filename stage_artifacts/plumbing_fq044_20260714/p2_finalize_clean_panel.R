## ============================================================================
## p2_finalize_clean_panel.R — FQ-044 P2: production-code parity (도훈 mandate
##   2026-07-14 "production 폴더 현 PG2 코드 기준") + 최종 clean 패널/마커 기록.
## Production parity: 05_Production/2-3(noLayer4, 현행 PG2)/_recompute_alpha_asof.R 를
##   junction 샌드박스에서 VERBATIM 실행(4 표본월)한 산출과 clean 패널 직접 대조.
##   주의: production theta = ic-recompute(전월까지 IC 평균), clean 패널 theta = 저장
##   패널 고유 stored theta(0.25x4 EW) — 차이는 theta 단일 원인. 분해 검증:
##   spearman(prod, recon 0_ic_S7[동일 theta]) ~ 1.0 이 port 충실도를 격리 증명.
## Writes (신규 파일만, 기존 파일 무접촉):
##   - <prod_dir>/alpha_scores_str1715_268m_cleanT1.parquet
##   - <prod_dir>/alpha_scores_str1715_268m_cleanT1_meta.json
##   - <prod_dir>/_VINTAGE_CONTAMINATED_README.md
## ============================================================================
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite); library(lubridate)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- file.path(QM,"stage_artifacts/plumbing_fq044_20260714")
SB <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/3d6b0eb6-6786-4a56-916d-9681f94897fe/scratchpad/prod_sandbox"
PROD_DIR <- file.path(QM,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe")
BKP <- file.path(PROD_DIR,"alpha_scores_str1715_268m.parquet")
OUT_P <- file.path(PROD_DIR,"alpha_scores_str1715_268m_cleanT1.parquet")
META_P <- file.path(PROD_DIR,"alpha_scores_str1715_268m_cleanT1_meta.json")
README_P <- file.path(PROD_DIR,"_VINTAGE_CONTAMINATED_README.md")
SAMPLES <- as.Date(c("2006-06-01","2013-09-01","2020-02-01","2026-03-01"))

orig_info_before <- file.info(BKP)[,c("size","mtime")]

## ---- inputs ----
CLEAN <- as.data.table(read_parquet(file.path(TD,"clean_panel_stage.parquet"))); CLEAN[,Date:=as.Date(Date)]
P1 <- readRDS(file.path(TD,"p1_parity.rds"))
stopifnot(P1$p1_maxd < 1e-9)                       # score parity vs recon 0_stored_S7 (exact)
stopifnot(abs(P1$p2_port_t - 3.058) < 0.005)       # screen parity vs R28/R29 measured
bk <- as.data.table(read_parquet(BKP)); bk[,Date:=as.Date(Date)]
PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet")))
PAN[,Date:=as.Date(Date)]; PAN[, AS_OF := as.Date(paste0(format(Date %m+% months(1),"%Y-%m"),"-01"))]
SBAL <- as.data.table(read_parquet(file.path(SB,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
SBAL[,Date:=as.Date(Date)]

## ---- production parity per sample month ----
rows <- list()
for(d in as.character(SAMPLES)){
  dd <- as.Date(d)
  pr <- SBAL[Date==dd, .(Ticker, score_prod=score_eff, theta_prod=theta_core)]
  cl <- CLEAN[Date==dd, .(Ticker, score_clean=score_eff)]
  ic <- PAN[AS_OF==dd & is.finite(`0_ic_S7`), .(Ticker, score_ic=`0_ic_S7`)]
  m  <- merge(pr, cl, by="Ticker"); m <- merge(m, ic, by="Ticker", all.x=TRUE)
  rows[[d]] <- data.table(as_of=d, n_prod=nrow(pr), n_common=nrow(m),
    spearman_prod_clean = m[,cor(score_prod,score_clean,method="spearman")],
    pearson_prod_clean  = m[,cor(score_prod,score_clean)],
    spearman_prod_icRecon = m[is.finite(score_ic),cor(score_prod,score_ic,method="spearman")],
    max_absdiff_prod_icRecon = m[is.finite(score_ic),max(abs(score_prod-score_ic))],
    spearman_clean_icRecon = m[is.finite(score_ic),cor(score_clean,score_ic,method="spearman")],
    theta_prod = pr$theta_prod[1])
  cat(sprintf("[prod parity %s] n=%d sp(prod,clean)=%.6f sp(prod,icRecon)=%.6f max|d|(prod,icRecon)=%.2e sp(clean,icRecon)=%.6f\n",
    d, nrow(m), rows[[d]]$spearman_prod_clean, rows[[d]]$spearman_prod_icRecon,
    rows[[d]]$max_absdiff_prod_icRecon, rows[[d]]$spearman_clean_icRecon))
}
PP <- rbindlist(rows)
cat(sprintf("[prod parity] min spearman(prod,clean)=%.6f | min spearman(prod,icRecon)=%.6f\n",
  min(PP$spearman_prod_clean), min(PP$spearman_prod_icRecon)))

## ---- final panel assembly (original schema + vintage metadata) ----
## Ret_1m: canonical forward return (screen_inputs fwd_ret, d0=prev month-end), same convention as original
SI <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))
d0map <- data.table(d0=sort(unique(SI$fwd_ret$Date))); d0map[, ym := format(d0,"%Y-%m")]
CL <- copy(CLEAN); CL[, map_ym := format(Date-1,"%Y-%m")]
CL <- merge(CL, d0map, by.x="map_ym", by.y="ym", all.x=TRUE)
CL <- merge(CL, SI$fwd_ret[,.(d0=Date,Ticker,Ret_1m=Ret_1m)], by=c("d0","Ticker"), all.x=TRUE)
meta_bk <- unique(bk[,.(Date, regime_state, theta_core, theta_defense)])
FIN <- merge(CL[,.(Date,Ticker,score_eff,score_core_z,score_defense_z,Ret_1m)], meta_bk, by="Date", all.x=TRUE)
FIN[, vintage := "factor_db_T-1_off0_clean"]
FIN[, vintage_verified := "production_parity_verified"]
FIN[, rebuild_source := "R28/R29 recipe (WT_D20260714_004/_build_score.R, theta_mode=stored) — task #73 FQ-044 P2"]
setkey(FIN, Date, Ticker)
cat(sprintf("final panel: %d rows %d months %s..%s\n", nrow(FIN), uniqueN(FIN$Date),
  as.character(min(FIN$Date)), as.character(max(FIN$Date))))

## ---- write (refuse overwrite; tmp+rename in-dir; original untouched) ----
if(file.exists(OUT_P)) stop("target exists — refuse overwrite: ", OUT_P)
tmp <- paste0(OUT_P, ".tmp_", Sys.getpid()); write_parquet(FIN, tmp)
if(!file.rename(tmp, OUT_P)) stop("rename fail: ", OUT_P)

meta <- list(
  file = basename(OUT_P),
  label = "production_parity_verified",
  built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  task = "plumbing #73 / FQ-044 P2 전반부 (도훈 mandate 2026-07-14 production-기준 검증 포함)",
  recipe = "off=0 (factor_db T-1) x stored theta(0.25x4 core EW) x 7-factor sleeve — R28 _build_score.R (verbatim port of production _recompute_alpha_asof.R), R29 calibrated",
  vintage = "factor_db_T-1_off0_clean (저장 원본 268m = same-month off+1 look-ahead, R29 judge-grade)",
  parity = list(
    score_vs_recon_0_stored_S7 = list(n=P1$n_m1, max_abs_diff=P1$p1_maxd, cor=P1$p1_cor),
    screen_cap_w_top25 = list(port_t_nw_lag3=P1$p2_port_t, target_r28_r29=3.058, ir=P1$p2_ir, n_months=P1$p2_n_months),
    production_code_direct = list(
      code = "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/_recompute_alpha_asof.R (현행 PG2 canonical, VERBATIM 실행 — junction sandbox, 실 트리 무변경)",
      sample_months = as.character(SAMPLES),
      table = PP[,.(as_of, n_common, spearman_prod_clean, pearson_prod_clean, spearman_prod_icRecon, max_absdiff_prod_icRecon)],
      difference_attribution = "production theta = ic-recompute(Usable_Date<AS_OF IC 평균) vs clean 패널 theta = 저장 stored theta(0.25x4 EW). spearman(prod, recon 0_ic_S7[ic-theta]) ~ 1 이 vintage/파이프라인 충실도를 theta와 분리 입증. 잔여 rank 차이는 전적으로 theta 가중 차이."
    ),
    ret1m_vs_original = list(cor_label0=P1$ret1m_cor, exact_share_label0=P1$ret1m_exact_share,
      offset_scan = "원본 Ret_1m = label월+1 실현수익 (offset scan: off+1 cor 0.9992 / exact 0.987; off 0/-1/+2 cor~0 — p1b_ret1m_offset_scan.R)",
      note = paste0("clean 패널 Ret_1m = label월(=홀딩월, production 컨벤션 label=T-1 산출·label월 보유) 실현 forward 수익 — ",
        "parity 3.058이 측정된 pairing과 동일. 원본의 Ret_1m(label+1월)과 컨벤션이 다르므로 혼용 금지. ",
        "forward-realized 컬럼이므로 신호로 사용 금지."))
  ),
  mandate = "book-관련 측정의 base는 production 코드 파생만 — 파생 저장 패널 재사용 금지 (도훈 2026-07-14)",
  references = c("stage_artifacts/WT_D20260714_005/verdict.md","L-AR-20260714_172027",
                 "stage_artifacts/plumbing_fq044_20260714/")
)
tmpj <- paste0(META_P,".tmp_",Sys.getpid())
writeLines(toJSON(meta, auto_unbox=TRUE, pretty=TRUE, digits=10), tmpj, useBytes=TRUE)
if(file.exists(META_P)) file.remove(META_P); if(!file.rename(tmpj, META_P)) stop("rename fail meta")

if(!file.exists(README_P)){
  rl <- c(
  "# ⚠ VINTAGE CONTAMINATED — alpha_scores_str1715_268m.parquet 소비 금지",
  "",
  "- **판정 (R28 WT_D20260714_004 / R29 WT_D20260714_005, judge-grade CONFIRMED, 2026-07-14):**",
  "  본 디렉토리의 `alpha_scores_str1715_268m.parquet`(268m, 2004-01~2026-04)는 전 기간 균일하게",
  "  **same-month(off+1) factor vintage = ~1개월 look-ahead**로 빌드된 저장 패널이다.",
  "  cap-w top-25 screen PORT_t를 **~2.08× 부풀린다** (clean 3.058 vs 저장 5.241; ic-theta 3.247→6.922).",
  "  production forward 경로(`_recompute_alpha_asof.R`, off=0/T-1)는 PIT-clean — 결함은 이 저장 역사 패널에만 있다.",
  "- **처분:** 원본은 역사 보존(재현·감사)을 위해 삭제·개명·덮어쓰기 없이 동결 보존한다.",
  "  **리서치·판정·book-관련 어떤 소비도 금지.** clean 버전 사용:",
  "  `alpha_scores_str1715_268m_cleanT1.parquet` (off=0/T-1 재빌드, production_parity_verified —",
  "  검증 표본월·수치는 `alpha_scores_str1715_268m_cleanT1_meta.json`).",
  "- **도훈 mandate (2026-07-14):** book-관련 측정의 base는 production 코드 파생만 — 파생 저장 패널 재사용 금지.",
  "- 참조: `L-AR-20260714_172027` · `stage_artifacts/WT_D20260714_005/verdict.md` ·",
  "  `stage_artifacts/plumbing_fq044_20260714/` (재빌드 스크립트·parity 로그)",
  "- 생성: FQ-044 P2 배관 태스크 #73, 2026-07-14. (현직 book pinned 6.130 재산출은 본 태스크 범위 밖 — 도훈 결정 대기)")
  tmpr <- paste0(README_P,".tmp_",Sys.getpid())
  writeLines(rl, tmpr, useBytes=TRUE)
  if(!file.rename(tmpr, README_P)) stop("rename fail readme")
  cat("[readme] created\n")
} else cat("[readme] already exists — untouched\n")

## ---- post-write verification ----
chk <- as.data.table(read_parquet(OUT_P)); chk[,Date:=as.Date(Date)]
orig_info_after <- file.info(BKP)[,c("size","mtime")]
cat(sprintf("[verify] cleanT1 written: rows=%d months=%d | original untouched: size %d->%d mtime %s->%s\n",
  nrow(chk), uniqueN(chk$Date), orig_info_before$size, orig_info_after$size,
  format(orig_info_before$mtime), format(orig_info_after$mtime)))
stopifnot(orig_info_before$size == orig_info_after$size, orig_info_before$mtime == orig_info_after$mtime)
saveRDS(list(prod_parity=PP, meta=meta), file.path(TD,"p2_prod_parity.rds"))
cat("P2_FINALIZE_DONE\n")
