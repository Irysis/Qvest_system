## P1R02 평가 — 사전등록 규칙 그대로(M1 · M2 · M3 · H1) · 수치는 계약 함수만(beta_controlled_alpha · bc_monthly · .dp_read) · 손계산 없음(AX-008)
##   실패 의미: 기준 산출물 부재 · 판독 오류 · M1 계산 불가 = '미시험'(통과로 접지 않는다). 판 불일치 = M3 보고만.
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT)
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RD  <- file.path(ROOT, "04_Research/programs/P1_RETURN/P1R02_1801_long_leg")
SAP <- file.path(ROOT, "stage_artifacts/programs/P1_RETURN/P1R02_1801_long_leg/prereg.json")
pre <- fromJSON(SAP, simplifyVector = FALSE)
reg <- fromJSON(file.path(ROOT, "06_Registry/research_programs.json"), simplifyVector = FALSE)
rr <- NULL
for (p in reg$programs) if (identical(p$id, "P1_RETURN")) for (r in p$rounds) if (identical(r$round_id, "P1R02_1801_long_leg")) rr <- r
if (is.null(rr) || !identical(rr$prereg_md5, unname(tools::md5sum(SAP)))) stop("[P1R02] 사전등록 md5 ≠ 등록부(R2)")
TAU <- format(as.Date(pre$tau_d), "%Y-%m")
out <- list(schema = "p1r02_evaluation_v1", round_id = "P1R02_1801_long_leg", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
            prereg_md5 = rr$prereg_md5, tested = FALSE)
fin <- function(o) { dir.create(file.path(RD, "results"), showWarnings = FALSE)
  writeLines(toJSON(o, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RD, "results/evaluation.json")); quit(status = 0) }

m <- tryCatch(fromJSON(file.path(RD, "results/measure.json")), error = function(e) NULL)
if (is.null(m) || !dir.exists(m$out_dir %||% "")) { out$untested_reason <- "롱 레그 측정 산출물 없음"; fin(out) }
L_DIR <- m$out_dir
## 기준 산출물(롱숏 재검증판) — 사전등록 identify 규칙
cand <- Filter(function(d) file.exists(file.path(d, "authoritative_remeasure.json")),
               list.dirs(file.path(ROOT, "stage_artifacts/replication"), recursive = FALSE))
info <- rbindlist(lapply(cand, function(d) { a <- tryCatch(fromJSON(file.path(d, "authoritative_remeasure.json"), simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(a)) return(NULL); data.table(dir = d, name = a$strategy_name %||% "", at = a$remeasured_at %||% "") }), fill = TRUE)
info <- info[name == "RP_AUTO_180101777" & at >= "2026-10-17T02:02"][order(-at)]
if (!nrow(info)) { out$untested_reason <- "기준 산출물(롱숏 재검증판 · remeasured_at ≥ 2026-10-17T02:02) 없음"; fin(out) }
B_DIR <- gsub("\\\\", "/", info$dir[1])
## 같은 판 — 래퍼 로그의 기저 신호 출처(측정 로그 = 러너 stdout 을 measure.log 로 남긴다)
mlog <- tryCatch(readLines(file.path(RD, "results/measure.log"), warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
src  <- sub("^.*기저 신호 출처 = ([^ ]+).*$", "\\1", grep("기저 신호 출처 =", mlog, value = TRUE)[1])
same <- isTRUE(startsWith(src %||% "", "base_cache:"))

invisible(capture.output(suppressMessages({
  source(file.path(ROOT, "02_Infrastructure/contracts/diagnosis_packet.R"))
  source(file.path(ROOT, "02_Infrastructure/contracts/beta_controlled_alpha.R"))
})))
E <- .dp_deps(ROOT)
mon <- function(dir) { rd <- .dp_read(E, dir)
  S <- E$bc_monthly(rd$pr[, .(date, r = ret_net)], "r"); K <- E$bc_monthly(rd$br[, .(date, r = benchmark_ret)], "r")
  merge(S[, .(ym, s = r)], K[, .(ym, k = r)], by = "ym")[order(ym)] }
al <- function(D) { a <- tryCatch(beta_controlled_alpha(D$s, D$k, periods_per_year = 12, nw_lag = 3L), error = function(e) NULL)
  if (is.null(a)) return(list(ok = FALSE))
  list(ok = TRUE, alpha_ann = a$alpha_ann, t = a$t_alpha, beta = a$beta, port_t = a$port_t, n = a$n,
       window = if (nrow(D)) c(D$ym[1], D$ym[nrow(D)]) else NA) }
DL <- tryCatch(mon(L_DIR), error = function(e) NULL); DB <- tryCatch(mon(B_DIR), error = function(e) NULL)
if (is.null(DL) || is.null(DB)) { out$untested_reason <- "산출물 판독 오류"; out$long_dir <- L_DIR; out$base_dir <- B_DIR; fin(out) }
M1 <- al(DL[ym <= TAU]); M2 <- al(DB[ym <= TAU])
if (!isTRUE(M1$ok)) { out$untested_reason <- "M1 계산 불가"; fin(out) }
M3 <- if (isTRUE(M2$ok) && is.finite(M2$alpha_ann) && M2$alpha_ann > 0) M1$alpha_ann / M2$alpha_ann else NA_real_
band <- if (!is.finite(M3)) "NA(롱숏 알파 ≤ 0 또는 계산 불가)" else if (M3 >= 0.5) "알파 과반이 롱 레그" else if (M3 >= 0.2) "혼합" else "숏 레그 의존"
ar_L <- fromJSON(file.path(L_DIR, "authoritative_remeasure.json"), simplifyVector = FALSE)
ar_B <- fromJSON(file.path(B_DIR, "authoritative_remeasure.json"), simplifyVector = FALSE)
out$tested <- TRUE
out$long_dir <- L_DIR; out$base_dir <- B_DIR; out$signal_source <- src; out$same_vintage <- same
out$visible <- list(M1_long = M1, M2_long_short = M2, M3_long_share = if (same) M3 else NA_real_, M3_reported_unverified = if (same) NULL else M3,
                    band = if (same) band else paste0(band, " — 판 불일치 · 보고만"))
out$verdict <- list(H1 = if (is.finite(M1$t) && M1$t >= 2.0) "holds" else "rejected",
                    rule = "보는 창 M1 t ≥ 2.0", M1_t = M1$t)
out$report_only <- list(
  test_window = list(M1_long = al(DL[ym > TAU]), M2_long_short = al(DB[ym > TAU])),
  long = list(grade = ar_L$essence_grade, S = ar_L$grade_v3$S %||% NA, calmar = ar_L$essence$calmar %||% NA, cagr = ar_L$essence$cagr %||% NA,
              mdd = ar_L$essence$mdd %||% NA, port_t = ar_L$essence$portfolio_alpha_t_nw_lag3 %||% NA, cr = ar_L$grade_v3$cr$overall %||% NA),
  long_short = list(grade = ar_B$essence_grade, S = ar_B$grade_v3$S %||% NA, calmar = ar_B$essence$calmar %||% NA, cagr = ar_B$essence$cagr %||% NA,
                    mdd = ar_B$essence$mdd %||% NA, port_t = ar_B$essence$portfolio_alpha_t_nw_lag3 %||% NA, cr = ar_B$grade_v3$cr$overall %||% NA))
cat(sprintf("[P1R02] H1 %s · M1 α %.2f%%/년 t %.2f β %.2f · M2 α %.2f%%/년 t %.2f · 몫 %s · 판 %s\n", out$verdict$H1,
            100 * M1$alpha_ann, M1$t, M1$beta, 100 * (M2$alpha_ann %||% NA), M2$t %||% NA, format(round(M3, 3)), if (same) "같음" else "불일치"))
fin(out)
