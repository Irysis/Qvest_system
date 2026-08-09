## FQ-176 CLAIM + ★내 등재 문구 정정 (오류 전파 차단)
## 정정 대상: FQ-176 등재 시 "검정력이 439개(월)에서 수만(종목×월)로 회복된다" 고 썼다. **부정확하다.**
##   조건부 IC 는 월별 계열이므로 유효표본 n = ON 개월수다. 종목수가 늘리는 것은 n 이 아니라 월별 IC 의 정밀도(sd).
##   실측(P0): 월별 30종목 IC sd 0.1852 → 240종목 0.0851 (정밀도는 오름) 이나 n_month 는 282 로 불변.
suppressPackageStartupMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[fix] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-176")
if (!length(i)) { say("★FQ-176 부재 — 중단"); quit(status = 1) }

own <- paste(Q$entries[[i]]$owner, collapse = " ")
if (grepl("CLAIMED", own) && !grepl("UNCLAIMED", own)) { say("★이미 CLAIMED — 착수 금지"); quit(status = 0) }

Q$entries[[i]]$owner <- paste0("CLAIMED Q-Lead session 2026-08-09 — 워크플로 wf_e36d0ab4-38a ",
  "(54팩터×282개월 병렬적재 → 팩터별 검정력 게이팅 → 조건부 IC → 적대검증 3렌즈). 완료 시 result_ref 기입.")
Q$entries[[i]]$status <- "in_flight_20260809"

Q$entries[[i]]$correction <- paste0(
  "★등재 문구 정정(2026-08-09, 착수 전 자가 적발): 원 hypothesis 의 ",
  "'검정력이 439개월에서 수만(종목×월)로 회복된다' 는 **부정확**하다. ",
  "조건부 rank-IC 는 월별 계열이므로 유효표본 n 은 여전히 **ON 개월수**이고, 종목수가 늘리는 것은 n 이 아니라 ",
  "**월별 IC 관측의 정밀도(sd)** 다. 실측: 월별 30종목 표본 IC sd 0.1852 → 60종 0.1504 → 120종 0.1094 → 240종 0.0851 ",
  "(정밀도는 실제로 개선) 이나 n_month 는 282 로 불변. ",
  "⇒ 필요 ΔIC = 2.0 × ic_sd × sqrt(1/n_ON + 1/n_OFF) × 1.25 이고, **팩터별 ic_sd 에 따라 자격이 갈린다**: ",
  "vol 계열(ic_sd 0.16~0.20)은 필요 ΔIC 가 무조건부 IC 의 3.0~4.8배로 **사정권 밖**, ",
  "M26 형(ic_sd 0.087)은 약 1.5배로 **사정권 안**. ",
  "따라서 라운드 설계를 '전 팩터 일괄 측정' 에서 **'팩터별 검정력 게이팅 후 자격분만 측정'** 으로 바꿨다 ",
  "(자격 규칙 사전 고정: required <= 2.0 × |unconditional IC|). ",
  "착수 전 사전 확인이 라운드 설계를 바꾼 5번째 사례.")

Q$entries[[i]]$wall_check <- paste0(Q$entries[[i]]$wall_check,
  " ★추가: 조건부 분할은 이 저장소에서 검정력 파괴가 반복 실증된 축이다 — 자격 미달 쌍은 **측정하지 않고 제외 사유와 함께 기록**한다(침묵 스킵 금지). INCONCLUSIVE 를 '효과 없음' 으로 읽지 않는다.")

Q$updated <- "2026-08-09"
write_frontier_queue(Q)
Q2 <- read_frontier_queue()
say("FQ-176 CLAIMED + 정정 기입 완료 — 재읽기 status=%s · correction 존재=%s",
    Q2$entries[[i]]$status, !is.null(Q2$entries[[i]]$correction))
