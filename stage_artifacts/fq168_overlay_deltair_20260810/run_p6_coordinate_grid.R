## FQ-168 P6(+P7) — 유효 영역의 **경계를 그린다** (기간 x 섹터레벨 격자, 공통 창)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P5: 부호 4/4 음수인데 유의 2/4. 무너지는 축 = **기간**(3개월 -1.278) · **섹터해상도**(Lv2 -1.916),
##      버티는 축 = 통계량 형태(z -4.534). ⇒ 단일 좌표 주장 대신 **지도**를 그린다.
##  ★P7 동시 처리: D3(Lv2)는 정의 변경과 **창 축소(335→258)** 가 섞여 있었다.
##    ⇒ 전 셀을 **공통 창**(모든 셀에서 관측 가능한 월의 교집합)에서 재서 두 효과를 분리한다.
##  격자: 기간 {1,2,3,6}개월 x 섹터 {Lv1, Lv2} = 8셀. 스코어 = 섹터 내 과거수익 역순위.
##  1급 = 하위25% − 전체(연율), 유의 = |NW t| >= 2 ∧ 음수.
##  판정:
##   F1_REGION   : 유효 셀 >= 3 ∧ **인접**(기간 축에서 연속) → 영역이 실재, P1 을 그 좌표로 재개
##   F2_ISOLATED : 유효 셀 1~2 → 단일 좌표 산물. 오버레이 근거로 부적합(P8 소비면 라우팅)
##   F3_NONE     : 0 → 공통 창에서는 서지 않음(창 효과였다는 뜻)
##  ★양성 대조: 공통 창의 (1개월, Lv1) 이 **원 창 -5.136 과 부호·대략 크기 유지**하는지 함께 본다.
##    크게 달라지면 그 자체가 **창 효과**의 증거다.
##  ★자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(sandwich) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq168_overlay_deltair_20260810")

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
RD <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
                                 col_select = c("Date","Ticker","Sector","Sector_Lv2")))
RD[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]; setorder(RD, Ticker, Date)
SEC <- RD[!is.na(Sector) & nzchar(Sector), .SD[.N], by = .(Ticker, ym), .SDcols = c("Sector","Sector_Lv2")]
rm(RD); invisible(gc())
U <- copy(ret)[, ym := format(Date, "%Y-%m")]
U <- merge(U, SEC, by = c("Ticker","ym"), all.x = TRUE)
U <- merge(U, liq[, .(Date,Ticker,adv)], by = c("Date","Ticker"), all.x = TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U <- merge(U, bench, by = "Date"); U[, exc := Ret_1m - BM_Ret]
setorder(U, Ticker, Date)
for (k in c(1L,2L,3L,6L)) U[, (paste0("r", k)) := shift(frollsum(Ret_1m, k), 1L), by = Ticker]
nw_t <- function(x){ x <- x[is.finite(x)]; if (length(x) < 24L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coef(m)[1]/sqrt(NeweyWest(m, lag=3L, prewhite=FALSE)[1,1])) }

cell_months <- function(pc, sc) {
  W <- U[is.finite(get(pc)) & !is.na(get(sc)) & nzchar(get(sc)) & !is.na(exc)]
  W[, n_sec := .N, by = c("Date", sc)]; W <- W[n_sec >= 5L]
  W[, nmo := .N, by = Date]; W <- W[nmo >= 125L]
  unique(W$Date)
}
grid <- CJ(k = c(1L,2L,3L,6L), sec = c("Sector","Sector_Lv2"), sorted = FALSE)
mons <- lapply(seq_len(nrow(grid)), function(i) cell_months(paste0("r", grid$k[i]), grid$sec[i]))
COMMON <- Reduce(intersect, mons)
cat(sprintf("[공통 창] 셀별 월수 %s → **교집합 %d개월** (%s~%s)\n",
            paste(vapply(mons, length, 1L), collapse="/"), length(COMMON),
            format(min(as.Date(COMMON, origin="1970-01-01"))),
            format(max(as.Date(COMMON, origin="1970-01-01")))))

run_cell <- function(pc, sc, lab) {
  W <- U[Date %in% COMMON & is.finite(get(pc)) & !is.na(get(sc)) & nzchar(get(sc)) & !is.na(exc)]
  W[, n_sec := .N, by = c("Date", sc)]; W <- W[n_sec >= 5L]
  W[, nmo := .N, by = Date]; W <- W[nmo >= 125L]
  if (uniqueN(W$Date) < 60L) return(NULL)
  W[, sc_v := 1 - (frank(get(pc), ties.method="average") - 0.5)/.N, by = c("Date", sc)]
  W[, q4 := cut(frank(sc_v, ties.method="first"),
                breaks = quantile(seq_len(.N), probs = seq(0,1,0.25)),
                include.lowest = TRUE, labels = FALSE), by = Date]
  S <- W[, .(bot = mean(exc[q4==1L], na.rm=TRUE), all = mean(exc, na.rm=TRUE)), by = Date][order(Date)]
  S[, rel := bot - all]
  data.table(cell = lab, k = NA_integer_, sec = NA_character_, n = nrow(S),
             rel_ann = round(mean(S$rel, na.rm=TRUE)*1200, 3), t = round(nw_t(S$rel), 3))
}
rows <- list()
for (i in seq_len(nrow(grid))) {
  lab <- sprintf("%d개월·%s", grid$k[i], ifelse(grid$sec[i]=="Sector","Lv1","Lv2"))
  r <- run_cell(paste0("r", grid$k[i]), grid$sec[i], lab)
  if (!is.null(r)) { r[, `:=`(k = grid$k[i], sec = ifelse(grid$sec[i]=="Sector","Lv1","Lv2"))]
    rows[[length(rows)+1L]] <- r }
}
R <- rbindlist(rows, fill=TRUE)
cat("\n=== 격자 (공통 창) ===\n"); print(dcast(R, k ~ sec, value.var = c("rel_ann","t")))
R[, valid := is.finite(t) & rel_ann < 0 & abs(t) >= 2]
cat(sprintf("\n유효 셀(음수 ∧ |t|>=2): **%d / %d**\n", sum(R$valid), nrow(R)))
if (any(R$valid)) print(R[valid == TRUE, .(cell, n, rel_ann, t)])
## 양성 대조: 공통 창의 (1개월, Lv1) vs 원 창 -5.136
ctl <- R[k == 1L & sec == "Lv1"]
cat(sprintf("\n[창 효과 확인] 공통창 1개월·Lv1 = %+.3f (원 창 335m: -5.136) → 차이 %+.3f\n",
            ctl$rel_ann, ctl$rel_ann - (-5.136)))
vk <- sort(unique(R[valid == TRUE, k]))
contiguous <- length(vk) >= 2L && all(diff(match(vk, c(1L,2L,3L,6L))) == 1L)
verdict <- if (sum(R$valid) >= 3L && contiguous) "F1_REGION" else
           if (sum(R$valid) >= 1L) "F2_ISOLATED" else "F3_NONE"
cat(sprintf("\n판정: %s (유효 기간축 %s · 인접 %s)\n", verdict,
            if (length(vk)) paste(vk, collapse=",") else "-", contiguous))
if (verdict == "F2_ISOLATED") cat("=> 단일/고립 좌표 — 오버레이 근거 부적합. **P8 monitoring 소비면으로 라우팅**\n")
if (verdict == "F3_NONE") cat("=> 공통 창에서 0셀 ⇒ 원 -5.136 은 **창 효과** 였다\n")
fwrite(R, file.path(OUT, "p6_grid.csv"))
write_json(list(verdict=verdict, n_common_months=length(COMMON), n_valid=sum(R$valid),
                contiguous=contiguous, control_common_window=ctl$rel_ann, results=R),
           file.path(OUT, "p6_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
