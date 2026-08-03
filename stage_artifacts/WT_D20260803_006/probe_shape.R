# probe_shape.R — WT-D20260803_006 구조 probe (측정 아님, shape만)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
SRC <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[p6] ", fmt, "\n"), ...))

CP <- readRDS(file.path(SRC, "canonical_pool.rds"))
say("canonical_pool 요소: %s", paste(names(CP), collapse = ", "))
RES <- CP$res
say("RES factor 수 %d | 첫 요소 컬럼: %s", length(RES), paste(names(RES[[1]]), collapse=","))
print(head(RES[[1]], 3))
SUMM <- as.data.table(CP$summary)
say("SUMM 컬럼: %s | 행 %d", paste(names(SUMM), collapse=","), nrow(SUMM))
say("cap 요소: %s", paste(names(CP$cap), collapse=", "))

DATES <- sort(unique(as.Date(unlist(lapply(RES, function(x) as.character(x$date))))))
say("월 범위 %s ~ %s (%d월)", min(DATES), max(DATES), length(DATES))

A <- matrix(NA_real_, nrow=length(DATES), ncol=length(RES),
            dimnames=list(as.character(DATES), names(RES)))
for (f in names(RES)) { r <- RES[[f]]; A[as.character(r$date), f] <- r$active }
say("A: %d x %d | 완전관측 %d | 월별 유효 factor 수 min %d max %d",
    nrow(A), ncol(A), sum(colSums(is.na(A))==0L),
    min(rowSums(is.finite(A))), max(rowSums(is.finite(A))))
say("월별 유효수 첫 12: %s", paste(rowSums(is.finite(A))[1:12], collapse=","))
saveRDS(list(A=A, DATES=DATES, SUMM=SUMM), file.path(ROOT,"stage_artifacts/WT_D20260803_006/A_probe.rds"))

# 기존 국면 라벨 존재 확인 (사용 금지 — 대조 진단 목적만)
p <- ".cache/unified_regime_signal.parquet"
say("regime parquet 존재: %s", file.exists(p))
say("PROBE DONE")
