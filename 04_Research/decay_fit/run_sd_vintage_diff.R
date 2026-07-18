##=============================================================================
## run_sd_vintage_diff.R — FQ-055 S-D 신구 vintage diff (F4 재판정 재료)
## old = fdb_daily 20260717T2025(결함 판정분) 파생 / new = 20260718T1024(phase6 재실행분)
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/decay_fit"
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")

ICo <- as.data.table(read_parquet(file.path(OUT, "sd_ic_daily_panel_20260718_vintage0717suspect.parquet")))
ICn <- as.data.table(read_parquet(file.path(OUT, "sd_ic_daily_panel_20260718.parquet")))
SDo <- as.data.table(read_parquet(file.path(OUT, "decay_fit_SD_20260718_vintage0717suspect.parquet")))
SDn <- as.data.table(read_parquet(file.path(OUT, "decay_fit_SD_20260718.parquet")))

## 1) IC 패널 값 diff
m <- merge(ICo[, .(Date, factor, ic_o = ic)], ICn[, .(Date, factor, ic_n = ic)], by = c("Date", "factor"))
m[, d := ic_n - ic_o]
wf("[panel] 공통셀 n=%d | max|d|=%.3g | |d|>1e-10 비율=%.4f | |d|>0.01 비율=%.4f",
   nrow(m), m[, max(abs(d))], m[, mean(abs(d) > 1e-10)], m[, mean(abs(d) > 0.01)])
wf("[panel] 행수: old=%d new=%d (교집합 밖 old-only=%d new-only=%d)",
   nrow(ICo), nrow(ICn), nrow(ICo) - nrow(m), nrow(ICn) - nrow(m))
pf <- m[, .(mx = max(abs(d)), chg = mean(abs(d) > 1e-10)), by = factor][order(-mx)]
wf("[panel] 값 변경 팩터 수(max|d|>1e-10): %d / %d", pf[mx > 1e-10, .N], nrow(pf))
if (pf[mx > 1e-10, .N] > 0) { wf("[panel] 변경 상위 10:"); print(pf[1:min(10, .N)]) }
by_yr <- m[abs(d) > 1e-10, .N, by = .(yr = year(Date))][order(yr)]
if (nrow(by_yr)) { wf("[panel] 변경 셀 연도 분포:"); print(by_yr) }

## 2) SD 라벨 diff
lb <- merge(SDo[, .(factor, label_o = label, break_o = break_date)],
            SDn[, .(factor, label_n = label, break_n = break_date)], by = "factor")
wf("[fits] 라벨 동일 비율=%.3f (%d/%d)", lb[, mean(label_o == label_n)], lb[label_o == label_n, .N], nrow(lb))
chg <- lb[label_o != label_n]
if (nrow(chg)) { wf("[fits] 라벨 변경 %d건:", nrow(chg)); print(chg) }
bb <- lb[label_o == "break_dominated" & label_n == "break_dominated"]
if (nrow(bb)) {
  bb[, gap_m := round(as.numeric(difftime(as.Date(break_n), as.Date(break_o), units = "days")) / 30.44, 1)]
  wf("[fits] break 유지 %d건 | break_date 동일 %d | |shift|>6m %d", nrow(bb), bb[gap_m == 0, .N], bb[abs(gap_m) > 6, .N])
}
sdbn <- SDn[label == "break_dominated" & !is.na(break_date)]; sdbn[, yr := substr(break_date, 1, 4)]
wf("[fits] new break-year 분포:"); print(sdbn[, .N, by = yr][order(yr)])
wf("[fits] new 라벨 분포:"); print(SDn[, .N, by = label][order(-N)])

verdict <- if (pf[mx > 1e-10, .N] == 0) "IDENTICAL — 재빌드가 S-D 소비면(phase6 parquet 값)을 바꾸지 않음: F4는 vintage 무관으로 판정 상향 (결함은 S-D 비소비 영역)" else if (lb[, mean(label_o == label_n)] >= 0.95 && nrow(chg) <= 8) "VALUES_CHANGED_LABELS_STABLE — 값 변경 있었으나 F4 라벨·클러스터 실질 불변: F4 유효 승격(신 vintage 기준)" else "MATERIALLY_CHANGED — F4 구판 폐기, 신판 기준 재서술 필요"
wf("[VERDICT] %s", verdict)
write_json(list(verdict = verdict, panel_max_abs_d = m[, max(abs(d))], panel_changed_factor_n = pf[mx > 1e-10, .N],
                label_same_share = lb[, mean(label_o == label_n)], n_label_changed = nrow(chg),
                new_vintage = "fdb_daily 20260718T1024 (phase6 재실행·phase7 fdb parquet 무수정 확인)",
                generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
           file.path(OUT, "sd_vintage_diff_20260718.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8)
wf("[diff] done")
