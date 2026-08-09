## n5 — insider 신호 변수 이해 (★수익은 보지 않는다 — 방향 사전선언을 위한 변수 파악만)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[n5] ", fmt, "\n"), ...)); flush.console() }

f <- list.files(".", pattern="^insider_sell_panel\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
I <- as.data.table(read_parquet(f))
say("=== 패널 ===")
say("  %d행 x %d열 · %s", nrow(I), ncol(I), f)
say("  컬럼: %s", paste(names(I), collapse=", "))
say("  Date %s ~ %s · %d개월 · %d종목", min(I$Date), max(I$Date), uniqueN(I$ym), uniqueN(I$Ticker))
say("  t 컬럼 예시: %s (cls %s)", paste(head(as.character(I$t),3), collapse=" | "), class(I$t)[1])

SIG <- grep("^cnv_", names(I), value=TRUE)
say("=== 신호 변수 %d종 분포 ===", length(SIG))
say("  %-14s %8s %10s %10s %10s %10s %8s", "변수", "비결측%", "최소", "중앙", "최대", "sd", "0비율")
for (s in SIG) {
  v <- suppressWarnings(as.numeric(I[[s]]))
  vv <- v[is.finite(v)]
  say("  %-14s %7.1f%% %10.4f %10.4f %10.4f %10.4f %7.1f%%",
      s, 100*mean(is.finite(v)), min(vv), median(vv), max(vv), sd(vv), 100*mean(vv == 0))
}
say("=== 변수 간 상관 (중복 확인) ===")
M <- as.matrix(I[, lapply(.SD, function(x) suppressWarnings(as.numeric(x))), .SDcols = SIG])
CM <- suppressWarnings(cor(M, use="pairwise.complete.obs"))
print(round(CM, 3))
say("  ★최대 비대각 상관 %.4f — %s", max(abs(CM[upper.tri(CM)])),
    if (max(abs(CM[upper.tri(CM)])) > 0.95) "중복 있음(합성 시 주의)" else "충분히 구분됨")

say("=== 시간 안정성 (커버리지가 시대별로 쏠렸는가) ===")
I[, yr := substr(as.character(ym), 1, 4)]
D <- I[, .(n = .N, nz = sum(is.finite(suppressWarnings(as.numeric(cnv_all_12))) &
                            suppressWarnings(as.numeric(cnv_all_12)) != 0)), by = yr][order(yr)]
say("  연도별 행수/비영값: %s", paste(sprintf("%s:%d(%d)", D$yr, D$n, D$nz), collapse=" "))

say("=== ★방향 사전선언을 위한 경제 논리 (수익 미조회) ===")
say("  패널명 = insider_**sell**_panel · 변수 = cnv_* (conviction, off=임원 / all=전체)")
say("  창 3/6/12 = 최근 3·6·12개월 집계로 추정")
say("  ⇒ 경제적으로 **내부자 매도는 음(-) 신호**다(정보 우위자가 파는 것).")
say("     따라서 long 포트는 **매도 강도가 낮은 종목**을 담아야 한다 = 신호를 **오름차순** 랭킹.")
say("  ★이 방향을 측정 전에 고정한다. 반대 방향은 **부호 점검**으로만 보고(1급 아님).")
say("  ★C13 정합: 이 패널은 factor_db Z_Score_Aligned 가 아니라 raw 패널이므로")
say("     방향 선언이 필요하다. 선언을 측정 후에 바꾸면 그것이 위반이다.")
saveRDS(list(sig = SIG, file = f), file.path(ROOT, "stage_artifacts/pg2_hunt/n5_sig.rds"))
say("=== n5 완료 ===")
