setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table)})

# ---- 입력 실측 (가정 금지) ----
FN <- readLines("stage_artifacts/FQ176/factor_set.txt")
FN <- trimws(FN); FN <- FN[nzchar(FN)]
cat("[INPUT] factor_set.txt  n_factor_names =", length(FN), "\n")
cat("[INPUT] factor_set head :", paste(head(FN,3), collapse=", "), "\n")
cat("[INPUT] factor_set tail :", paste(tail(FN,3), collapse=", "), "\n")
cat("[INPUT] duplicated names =", sum(duplicated(FN)), "\n")

pn <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
cat("[INPUT] p0_panels class =", paste(class(pn), collapse="/"),
    " names =", paste(names(pn), collapse=", "), "\n")
ret <- pn$ret
cat("[INPUT] ret class =", paste(class(ret), collapse="/"), "\n")
cat("[INPUT] ret ncol =", ncol(ret), " nrow =", nrow(ret), "\n")
cat("[INPUT] ret colnames =", paste(names(ret), collapse=", "), "\n")
cat("[INPUT] ret Date class =", paste(class(ret$Date), collapse="/"), "\n")

ud <- sort(unique(as.Date(ret$Date)))
cat("[INPUT] ret unique Date n =", length(ud),
    " range =", format(min(ud)), "~", format(max(ud)), "\n")
# 관측 단위 확인: 연속 고유일자 간격
dif <- as.integer(diff(ud))
cat("[INPUT] diff(unique Date) : min =", min(dif), " median =", median(dif),
    " max =", max(dif), "\n")
cat("[INPUT] day-of-month table (top) :\n"); print(head(sort(table(as.integer(format(ud,"%d"))), decreasing=TRUE), 5))

sel <- ud[ud >= as.Date("2003-01-01") & ud <= as.Date("2026-06-30")]
cat("[INPUT] in-range unique dates n =", length(sel),
    " range =", format(min(sel)), "~", format(max(sel)), "\n")
cat("[INPUT] distinct YYYY-MM in range =", length(unique(format(sel,"%Y-%m"))), "\n")

idx <- seq(1+1, length(sel), by=4)
cat("[SLICE] slice=1 offset=1+1 by=4 -> n_months =", length(idx),
    " first =", format(sel[idx[1]]), " last =", format(sel[idx[length(idx)]]), "\n")
saveRDS(list(FN=FN, sel=sel, idx=idx), "stage_artifacts/FQ176/.slice_probe_1.rds")
