## P1a — PG2 base 패널(월초)과 내 아크 패널(월말)의 앵커 정렬
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P1 스코핑: 문자열 Date 교집합 0개월. 원인 가설 = 앵커 규약(월초 vs 월말).
##  ⇒ ym(YYYY-MM) 키로 매칭해 실제 겹침을 잰다.
##  ★★결정적 확인 = **월초 앵커가 그 달 신호인가 전월 신호인가**.
##    잘못 맞추면 1개월 look-ahead 가 들어간다(2026-07-05/06 BearProb 사고 재현).
##    판별: PG2 패널의 Ret_1m 열과 내 패널의 Ret_1m 을 같은 ym 에서 비교한다.
##      - 같으면 두 패널의 ym 라벨이 **같은 실현월**을 가리킨다(정합)
##      - 다르면 한 쪽이 시프트돼 있고, 어느 방향인지 lag 스캔으로 찾는다
##   Q1 정합: 같은 ym 에서 Ret_1m 상관 >= 0.99 → ym 병합 안전, P1 본체 착수 가능
##   Q2 시프트: 최대 상관이 lag != 0 → 그 lag 만큼 보정 필요(방향 명시)
##   Q3 불일치: 어느 lag 에서도 < 0.9 → 두 패널의 수익 정의가 다름. 병합 보류
suppressPackageStartupMessages({ library(data.table); library(arrow) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")

A <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
A[, Date := as.Date(Date)][, ym := format(Date, "%Y-%m")]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
B[, ym := format(Date, "%Y-%m")]
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; ret[, ym := format(Date, "%Y-%m")]

cat(sprintf("[PG2] %d개월 %s~%s · 앵커일 분포: %s\n", uniqueN(A$ym), min(A$ym), max(A$ym),
            paste(head(sort(table(format(A$Date,"%d")), decreasing=TRUE),3), collapse=",")))
cat(sprintf("[내]  %d개월 %s~%s · 앵커일 분포: %s\n", uniqueN(B$ym), min(B$ym), max(B$ym),
            paste(head(sort(table(format(B$Date,"%d")), decreasing=TRUE),3), collapse=",")))
ov <- intersect(unique(A$ym), unique(B$ym))
cat(sprintf("\n★ym 키 겹침 = **%d개월** (Date 문자열 겹침은 0이었다)\n", length(ov)))

## ★핵심: Ret_1m 라벨 정합 — 같은 ym 에서 두 패널의 수익이 같은가
if (!("Ret_1m" %in% names(A))) { cat("PG2 패널에 Ret_1m 없음 — 판별 불가\n"); quit(status=0) }
cmp <- merge(A[ym %in% ov & !is.na(Ret_1m), .(ym, Ticker, r_pg2 = Ret_1m)],
             ret[ym %in% ov, .(ym, Ticker, r_mine = Ret_1m)], by = c("ym","Ticker"))
cat(sprintf("[대조 쌍] %d행 · %d개월\n", nrow(cmp), uniqueN(cmp$ym)))
cat(sprintf("lag0 상관 = **%.4f** · 평균절대차 %.6f\n",
            cor(cmp$r_pg2, cmp$r_mine, use="complete.obs"), mean(abs(cmp$r_pg2 - cmp$r_mine), na.rm=TRUE)))

## lag 스캔 (PG2 ym 을 +-1,2 shift 해 내 패널과 대조)
yms <- sort(ov); res <- list()
for (L in -2:2) {
  A2 <- copy(A[ym %in% yms & !is.na(Ret_1m), .(ym, Ticker, r_pg2 = Ret_1m)])
  idx <- match(A2$ym, yms); A2[, ym2 := yms[pmin(pmax(idx + L, 1L), length(yms))]]
  m <- merge(A2[, .(ym = ym2, Ticker, r_pg2)], ret[ym %in% yms, .(ym, Ticker, r_mine = Ret_1m)],
             by = c("ym","Ticker"))
  if (nrow(m) < 1000L) next
  res[[length(res)+1L]] <- data.table(lag = L, n = nrow(m),
                                      rho = round(cor(m$r_pg2, m$r_mine, use="complete.obs"), 4))
}
R <- rbindlist(res); print(R[])
best <- R[which.max(rho)]
cat(sprintf("\n최대 상관 lag = %d (rho %.4f)\n", best$lag, best$rho))
verdict <- { if (best$lag == 0L && best$rho >= 0.99) "Q1_ALIGNED"
             else if (best$rho >= 0.90) "Q2_SHIFTED" else "Q3_INCOMPATIBLE" }
cat(sprintf("판정: %s\n", verdict))
if (verdict == "Q2_SHIFTED") cat(sprintf("★보정 필요: PG2 ym 을 %+d 개월 시프트해야 내 패널과 같은 실현월\n", best$lag))
jsonlite::write_json(list(verdict=verdict, ym_overlap=length(ov), best_lag=best$lag,
                          best_rho=best$rho, lag_scan=R),
                     file.path(OUT,"p1a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
