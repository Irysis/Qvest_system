## 적대검증 §5-1 주장 독립 확인 — 발행 패널이 사전등록 고정 축(adv>=2e8)을 깨는가
## ★두 소스가 같은 결론을 냈어도 내가 행동하기 전엔 직접 잰다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[panel] ",fmt,"\n"),...))

f <- "stage_artifacts/WT_D20260808_001/alpha_scores.parquet"
say("발행 패널 존재: %s", file.exists(f))
if (!file.exists(f)) { say("★부재 — 주장 확인 불가. 여기서 멈춘다."); quit(status=0) }

P <- as.data.table(read_parquet(f))
say("--- 입력 실측 (가정 금지) ---")
say("  행 %s · 컬럼: %s", format(nrow(P), big.mark=","), paste(names(P), collapse=", "))
say("  유동성 컬럼 존재(adv/liq/Vol): %s",
    any(grepl("adv|liq|Vol", names(P), ignore.case=TRUE)))
dcol <- intersect(c("Date","date","Factor_Date"), names(P))[1]
if (!is.na(dcol)) {
  say("  월 수 %d · 기간 %s ~ %s", uniqueN(P[[dcol]]), min(P[[dcol]]), max(P[[dcol]]))
  say("  월평균 종목수 %.1f", nrow(P)/uniqueN(P[[dcol]]))
}

## ★양성 대조: 유동성 필터를 직접 적용하면 몇 행이 떨어지는가
R <- as.data.table(read_parquet(".cache/rawdata.parquet"))
say("--- rawdata 실측: 행 %s · 관측단위 확인 ---", format(nrow(R), big.mark=","))
say("  Date 고유 %d (일간이면 ~9000)", uniqueN(R$Date))
R[, adv20 := frollmean(Vol * Close, n = 20L, align = "right"), by = Ticker]
R[, ym := format(Date, "%Y-%m")]
LQ <- R[, .(adv_m = last(adv20)), by = .(Ticker, ym)]

if (!is.na(dcol)) {
  P[, ym := format(get(dcol), "%Y-%m")]
  M <- merge(P, LQ, by = c("Ticker","ym"), all.x = TRUE)
  n_all  <- nrow(M)
  n_pass <- sum(!is.na(M$adv_m) & M$adv_m >= 2e8)
  n_fail <- sum(!is.na(M$adv_m) & M$adv_m <  2e8)
  n_na   <- sum(is.na(M$adv_m))
  say("--- 유동성 축(adv >= 2e8) 사후 적용 ---")
  say("  전체 %s / 통과 %s / **미달 %s (%.2f%%)** / 매칭실패 %s",
      format(n_all,big.mark=","), format(n_pass,big.mark=","),
      format(n_fail,big.mark=","), 100*n_fail/n_all, format(n_na,big.mark=","))
  say("")
  if (n_fail > 0) {
    say("★주장 확인: 발행 패널에 유동성 미달 행이 **실재**한다.")
  } else {
    say("★주장 반증: 미달 행 0 — 필터 컬럼이 없어도 결과적으로 걸러져 있다.")
  }
  say("  ⚠매칭실패 %s 행은 판정에서 제외했다(있으면 상한/하한으로 병기 필요).", format(n_na,big.mark=","))
}
