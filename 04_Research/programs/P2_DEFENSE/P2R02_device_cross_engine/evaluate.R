## P2R02 평가 — P0R01 칸의 보는 창 진단 패킷으로 장치 6종 × 엔진 3종 × 보는 창 위기를 사전등록 규칙대로 기계 판정
## 실행: Rscript evaluate.R   (P0R01 evaluate.R --cells-only 이후)
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/program_registry.R")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
md5 <- function(f) unname(as.character(tools::md5sum(f)))
RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R02_device_cross_engine")
PR <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R02_device_cross_engine/prereg.json")
reg <- pr_load(ROOT); rr <- Filter(function(r) identical(r$round_id, "P2R02_device_cross_engine"), pr_get(reg, "P2_DEFENSE")$rounds)
if (!length(rr) || !identical(rr[[1]]$prereg_md5, md5(PR))) stop("[P2R02 평가] 사전등록 md5 불일치(R2)")
pre <- fromJSON(PR, simplifyVector = FALSE)
P0R <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results")
MAJ <- as.numeric(pre$rules$V1_device_effect$majority_share); UCF <- as.numeric(pre$rules$V3_participation$uc_floor)
TOL <- local({ e <- new.env(); invisible(capture.output(sys.source(file.path(ROOT, "02_Infrastructure/contracts/matched_controls.R"), envir = e))); e$.MC_TOL })
pk <- function(code) { f <- file.path(P0R, code, "visible", "diagnosis_packet.json"); if (file.exists(f)) fromJSON(f, simplifyVector = TRUE) else NULL }
ENG <- c("E1", "E2", "E3"); DEV <- names(pre$devices)
## 벤치 거래일(위기 유형 — 고점→저점 거래일 수)
BM <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache/benchmark.parquet"), col_select = c("Date")))[, Date := as.Date(Date)]
tdays <- function(a, b) sum(BM$Date > as.Date(a) & BM$Date <= as.Date(b))
rows <- list(); ucs <- list()
for (e in ENG) {
  b <- pk(sprintf("P0R01_%s_C0", e)); if (is.null(b)) { cat("[P2R02] 기준 칸 패킷 없음:", e, "\n"); next }
  bc <- as.data.table(b$behavior$crises)[, .(peak_date = as.Date(peak_date), trough_date = as.Date(trough_date), dd0 = dd_capture)]
  for (d in DEV) {
    x <- pk(sprintf("P0R01_%s_%s", e, d)); if (is.null(x)) next
    xc <- as.data.table(x$behavior$crises)[, .(peak_date = as.Date(peak_date), dd = dd_capture)]
    pc <- as.data.table(x$controls$per_crisis)
    pc <- if (nrow(pc)) pc[, .(peak_date = as.Date(peak_date), beats = as.logical(beats), placebo_p)] else data.table(peak_date = as.Date(character(0)), beats = logical(0), placebo_p = numeric(0))
    m <- merge(merge(bc, xc, by = "peak_date"), pc, by = "peak_date", all.x = TRUE)
    if (nrow(m)) rows[[length(rows) + 1L]] <- m[, .(engine = e, device = d, peak_date, trough_date, dd0, dd, beats, placebo_p,
                                                    effect = dd < dd0 - TOL)]
    ucs[[length(ucs) + 1L]] <- data.table(engine = e, device = d, uc = suppressWarnings(as.numeric(x$behavior$summary$bull_up_capture_median)))
  }
}
X <- rbindlist(rows); U <- rbindlist(ucs)
if (!nrow(X)) stop("[P2R02 평가] 판정 재료 없음 — P0R01 칸 평가 먼저")
X[, td := mapply(tdays, peak_date, trough_date)]
med_td <- stats::median(unique(X[, .(peak_date, td)])$td)
X[, type := fifelse(td <= med_td, "crash", "grind")]
V <- X[, .(n_pairs = .N, v1_share = mean(effect), v2_share = mean(beats, na.rm = TRUE), n_v2 = sum(!is.na(beats)),
           v1_crash = mean(effect[type == "crash"]), v1_grind = mean(effect[type == "grind"]),
           v2_crash = mean(beats[type == "crash"], na.rm = TRUE), v2_grind = mean(beats[type == "grind"], na.rm = TRUE)), by = device]
V <- merge(V, U[, .(n_uc_ok = sum(is.finite(uc) & uc >= UCF), n_eng = .N, uc_median = stats::median(uc, na.rm = TRUE)), by = device], by = "device")
V[, V1 := v1_share > MAJ][, V2 := v2_share > MAJ][, V3 := n_uc_ok >= ceiling((n_eng + 1) / 2)]
V[, verdict := fifelse(V1 & V2 & V3, "validated", "rejected")]
V[, fail_codes := mapply(function(a, b, c) paste(c(if (!a) "V1_no_device_effect", if (!b) "V2_not_beyond_controls", if (!c) "V3_participation"), collapse = ","), V1, V2, V3)]
V[, all_weather := v1_crash > MAJ & v1_grind > MAJ]
## 기대 방향 기록(사전등록 문장 → 기계 판독)
ex <- list(C1 = V[device == "C1", v1_grind > v1_crash], C2 = V[device == "C2", v1_crash > v1_grind], C3 = V[device == "C3", v1_grind > v1_crash],
           C4 = V[device == "C4", v1_crash > v1_grind], C5 = V[device == "C5", v1_share > 0.5],
           C6 = V[device == "C6", v1_share >= max(V[device %in% c("C1", "C4")]$v1_share)])
res <- list(schema = "p2r02_evaluation_v1", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = md5(PR),
            tol = TOL, majority_share = MAJ, uc_floor = UCF, crisis_type_median_tdays = med_td,
            n_crises_visible = uniqueN(X$peak_date), devices = V, pairs = X,
            expectations = lapply(ex, function(z) if (length(z)) z else NA),
            validated = V[verdict == "validated"]$device)
dir.create(file.path(RD, "results"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA, Date = "ISO8601"), file.path(RD, "results", "evaluation.json"))
fwrite(V, file.path(RD, "results", "devices.csv")); fwrite(X, file.path(RD, "results", "pairs.csv"))
print(V[, .(device, n_pairs, v1_share = round(v1_share, 3), v2_share = round(v2_share, 3), n_uc_ok, verdict, fail_codes, all_weather)])
cat(sprintf("[P2R02 평가] 보는 창 위기 %d개 · 급락/완만 경계 %s거래일 · 검증 장치 %s\n", uniqueN(X$peak_date), med_td,
            if (length(res$validated)) paste(res$validated, collapse = ",") else "없음"))
