# diag_ckpt_census.R — WT-D20260803_008 Step 0: 체크포인트 코퍼스 실측 census
# 목적: "크롤 완주" 주장을 데이터로 확인 — 월 결측 / 행수 / parse_status / 스키마 변종
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(2)
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
CKDIR <- ".cache/dart/contract_backfill"
fs <- list.files(CKDIR, pattern = "^\\d{6}\\.csv$", full.names = TRUE)
yms <- sub("\\.csv$", "", basename(fs))
cat(sprintf("[census] 파일 %d개 / %s ~ %s\n", length(fs), min(yms), max(yms)))

# 월 연속성: 라벨 개수가 아니라 기대 월 시퀀스 대비 결측 확인
exp_ym <- format(seq(as.Date(paste0(substr(min(yms),1,4), "-", substr(min(yms),5,6), "-01")),
                     as.Date(paste0(substr(max(yms),1,4), "-", substr(max(yms),5,6), "-01")),
                     by = "month"), "%Y%m")
miss <- setdiff(exp_ym, yms)
cat(sprintf("[census] 기대월 %d / 실재 %d / 결측 %d %s\n", length(exp_ym), length(yms), length(miss),
            if (length(miss)) paste0("→ ", paste(miss, collapse = ",")) else ""))

L <- lapply(fs, function(f) fread(f, colClasses = list(character = "corp_code")))
names(L) <- yms
# 스키마 변종
schemas <- vapply(L, function(d) paste(sort(names(d)), collapse = "|"), character(1))
cat(sprintf("[census] 스키마 변종 %d종\n", length(unique(schemas))))
for (s in unique(schemas)) {
  w <- names(schemas)[schemas == s]
  cat(sprintf("  · %s ~ %s (%d개월): %s\n", min(w), max(w), length(w),
              paste(setdiff(strsplit(s, "\\|")[[1]], c("ym","rcept_no","corp_code","corp_name","rcept_dt",
                "report_nm","is_correction","contract_amount","recent_revenue","ratio_to_revenue",
                "is_amendment","rounding_flag","fx_flag","parse_status","parse_note")), collapse = ",")))
}
D <- rbindlist(L, fill = TRUE)
D <- D[!is.na(rcept_no)]
D[, seg := fifelse(ym >= 202308L, "pilot(2023-08+)",
            fifelse(ym >= 201901L, "new(2019-01~2023-07)", "pre2019(2017-03~2018-12)"))]
cat("\n[census] 구간별 행수 / parse_status:\n")
print(D[, .N, by = .(seg, parse_status)][order(seg, -N)])
cat("\n[census] 구간별 월 커버 / 정정비중:\n")
print(D[, .(n_rows = .N, n_months = uniqueN(ym), n_corr = sum(is_correction %in% TRUE),
            n_ok = sum(parse_status == "OK"),
            n_ok_noncorr = sum(parse_status == "OK" & is_correction %in% FALSE),
            n_firms = uniqueN(corp_code)), by = seg][order(seg)])
cat("\n[census] 월별 비정정 OK 건수 (연도 요약):\n")
print(D[parse_status == "OK" & is_correction %in% FALSE,
        .(n = .N, months = uniqueN(ym)), by = .(yr = substr(as.character(ym),1,4))][order(yr)])

# 원문제공 대비 OK
NO_SOURCE <- c("NO_SOURCE_CORRECTION", "NO_SOURCE_014")
n_avail <- nrow(D[!parse_status %in% NO_SOURCE])
cat(sprintf("\n[census] 전체 %d행 | 원문제공 %d | OK %d (%.1f%%) | 원문부재 %d\n",
            nrow(D), n_avail, nrow(D[parse_status == "OK"]),
            100 * nrow(D[parse_status == "OK"]) / n_avail, nrow(D) - n_avail))

# 기존 파일럿 패널 범위
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"
pa <- as.data.table(read_parquet(file.path(OUTD, "panel_A.parquet")))
cat(sprintf("[census] 기존 panel_A: %d행 / ym %s~%s / %d종목\n",
            nrow(pa), min(pa$ym), max(pa$ym), uniqueN(pa$Ticker)))
