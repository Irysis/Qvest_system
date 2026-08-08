suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"
q <- fromJSON(p, simplifyVector = FALSE)
items <- q$entries
key <- "entries"
idx <- which(sapply(items, function(x) isTRUE(identical(x$id, "FQ-099")) || isTRUE(identical(x$fq_id, "FQ-099"))))
cat("[fq099] 매칭 인덱스:", paste(idx, collapse=","), "\n")
if (!length(idx)) { cat("[fq099] FQ-099 미발견 — 중단\n"); quit(status=0) }
i <- idx[1]
items[[i]]$status <- "measured_repair_pending"
items[[i]]$measured_20260808 <- list(
  wiring = "TTM 은 parse_fundamental_xlsx.R:274 가 .cache/fundamental_xlsx_ttm.parquet 에 정확히 계산(non-NA 96.6%). 그러나 factor_db_builder.R:276 은 fundamental_merged.parquet 를 읽고 그 파일엔 TTM_Value 컬럼이 없어 compute_value.R:61 조건이 항상 거짓 -> use_val := Value(원시값). 표준 존재, 소비자 0.",
  seam = "XLSX 2000~2014(분기월 비중 0.739) -> DART 2015~2026(분기월 비중 0.000 = 연간 단독). 같은 종목 2014 분기평균 대비 2016 DART 연간 = Revenue 4.42 / OperatingProfit 4.72 / COGS 4.34.",
  cross_section = "생산 유니버스(K200 U KQ150) DART 비중 중앙 0.67~0.71 -> 잔여 약 31% 가 2014 분기 스케일로 동결된 채 연간 스케일과 같은 서열표에서 경쟁. 유량비율 평균 백분위 서열 격차 DART-XLSX = +0.207~+0.274 (5시점 전건).",
  selection_impact_CORRECTED = "★공통 지지집합 통제 후 top-25 자카드 중앙 0.429(OperatingProfit, Revenue) / 0.471(OperatingCF), 최소 0.316, 10시점 전건 <0.8. 기존 큐 서술 '자카드 중앙 0.786'은 본 측정으로 대체(더 큰 영향).",
  scope = "레지스터리 51/373 팩터(13.7%)가 유량 항목 의존 — quality 26 / value 12 / growth 10.",
  caveat_distortion_is_in_the_body = "극단 상위 25 는 0/25 DART(마이크로캡이 꼬리 점유). 왜곡은 분포의 몸통이며 '상위가 멀쩡하니 무해'로 읽으면 오독.",
  NOT_MEASURED = "PG2 북 합성 알파가 51개 중 무엇을 실제 소비하는지 미측정. forward_weights*.R 텍스트 검색 0건은 잘못된 계측(생산은 사전계산 합성 패널 사용). 교정 후 성과 개선 여부도 미측정.",
  repair_cost = "신규 산출 불요 — XLSX 계는 기존 TTM 파일의 TTM_Value, DART 는 연간값이 곧 TTM.",
  evidence = "stage_artifacts/fq099/findings.md · probe6/8/9/13/16.R · L-MF-20260808_SOURCE_AWARE_TTM_UNWIRED"
)
items[[i]]$next_probe <- c(
  "FQ-099a 북 소비 경로 확정 — PG2 합성 알파가 유량의존 51 팩터 중 무엇을 쓰는지 사전계산 패널의 팩터 구성에서 직접 확인. 이것이 확정돼야 '북 영향' 을 말할 수 있다(현재 미측정).",
  "FQ-099b 교정 후 재측정 — 소스-인지 TTM 패널로 유량의존 팩터를 재산출하고 canonical_screen_bt 로 IC/PORT_t 를 현행 대비 A/B. 자카드 0.43 이 성과 개선인지 단순 재배열인지 갈린다.",
  "FQ-099c 합성 단계 상쇄 여부 — 단항 비율에서의 자카드 0.43 이 다항 합성 점수에서 상쇄되는지 증폭되는지 측정."
)
q[[key]] <- items
write(toJSON(q, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
cat("[fq099] 큐 갱신 완료\n")
