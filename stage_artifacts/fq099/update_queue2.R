suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"; q <- fromJSON(p, simplifyVector=FALSE)
items <- q$entries
i <- which(sapply(items, function(x) isTRUE(identical(x$id,"FQ-099"))))[1]
cat("[q2] FQ-099 인덱스:", i, "\n")
items[[i]]$measured_20260808$scope <- paste(
  "★정정(2026-08-08): 진짜 영향 = 49/51 (레지스터리 373 의 13.1%).",
  "data_source 재분해 — fundamental 32(fundamental_merged 경유, 스케일혼합+계절성) /",
  "fundamental_xlsx 17(xlsx_factor_calculator.R:48 이 fundamental_xlsx.parquet 원시 분기값 직접, TTM 없음 — 계절성만) /",
  "consensus 2(무관: C14_Revenue_Surprise, M26_Revenue_Mom — 정의문 텍스트만 일치).",
  "구 표기 '51/373 13.7%' 는 텍스트매칭 기준이었고, 그 뒤 '32건' 으로 축소한 나의 정정도 틀렸다(fundamental_xlsx 를 오탐 처리).")
items[[i]]$measured_20260808$XF_seam_defect <- paste(
  "XF_* 17건의 소스 fundamental_xlsx.parquet 은 2014 에서 끝난다.",
  "그런데 xlsx_factor_calculator.R:5 주석은 'DART 가 2016+ 만 덮으니 우회한다' 고 적혀 있다 — 실제는 반대다.",
  "이 17개 팩터가 2015+ 에 무엇을 반환하는지 미확인(carry-forward 인지 결측인지). 신규 프론티어.")
items[[i]]$next_probe <- c(items[[i]]$next_probe,
  "FQ-099e 신규 — XF_* 17 팩터의 2015+ 거동 확인. 소스 XLSX 패널이 2014 종료인데 팩터는 계속 산출되는가(carry-forward = 만료된 값) 또는 결측인가. 오늘 아침 fundamental feed staleness 건과 같은 지점이며, carry-forward 라면 이 17건은 11년째 2014 값을 쓰는 셈이다.")
q$entries <- items
write(toJSON(q, auto_unbox=TRUE, pretty=TRUE, null="null"), p)
cat("[q2] 큐 갱신 완료\n")
