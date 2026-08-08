suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"; q <- fromJSON(p, simplifyVector=FALSE)
E <- q$entries; i <- which(sapply(E, function(x) isTRUE(identical(x$id,"FQ-123"))))[1]
cat("[123] 인덱스:", i, "\n")
E[[i]]$status <- "frontier_open_REFRAMED"
E[[i]]$superseded_note_20260808 <- paste(
  "★1순위 arm 은 하루 뒤 FQ-108(2026-08-03, L-MF-20260803_FQ108)이 사실상 답했다 —",
  "D35_RealVol_63d 의 factor-DB 횡단면 z 는 동일 63일 창 실현분산 레벨(rv63)과 spearman 0.9967 이고,",
  "rv63 위 증분 정보는 0(g35 계수 0.0045, FM-NW t 1.49).",
  "본 항목 전제('MAX5 증분이 vol63 통제 시 소멸, cor 0.939')와 결합하면 전이적으로 D35 가 MAX5 를 흡수한다 —",
  "★단 이는 **순위(rank) 기준**이다.",
  "⇒ 본 항목이 기대한 결론('흡수되면 신규 팩터 불요·배선만')의 후반부가 막힌다:",
  "FQ-108 이 함께 남긴 구조 발견 — load_month_factors 는 Z_Score_Aligned(횡단면 z)만 반환해 **변동성의 레벨을 소거**하므로,",
  "vol/tail 계열 8종(D34/D35/D36/D41/D42/D45/D47/D50)은 위험모델 입력으로 **형태가 부적합**할 수 있다.",
  "'D35 소비자 0' 의 일부는 무관심이 아니라 형태 불일치다.",
  "⇒ 남은 진짜 질문은 '흡수하는가'가 아니라 **'z 형태로 위험모델 소비가 가능한가'** 이다.")
E[[i]]$next_probe <- c(
  "FQ-123a — 레벨 보존 경로 확인: load_month_factors 우회 없이 vol 레벨을 위험모델에 넣을 방법이 있는가(Raw_Value 컬럼 존재 여부·C15 규약과의 정합). factor_db 스키마에 Raw_Value 가 있으므로(2026-08-08 실측: Date/Ticker/Factor_Name/Raw_Value/Z_Score/Z_Sector/Rank_Pct/Coverage) 레벨은 저장돼 있고 접근 규약이 z 로 좁혀져 있을 뿐일 수 있다 — ★있다면 이건 데이터 부재가 아니라 **인터페이스 결손**이다.",
  "FQ-123b — 그럼에도 FQ-108 PRIMARY 는 '실 book total-분산에서 증분 없음'(QLIKE DM t +0.724, lw_nls 가 97.5% 흡수)이었다. 즉 레벨 접근이 열려도 **집중 20종 북에서는 대각이 병목이 아니다**. 따라서 FQ-123a 가 성공해도 자본 효익은 기대 낮음 — 소비면을 위험모델이 아닌 곳(선별 필터·tripwire)에서 찾아야 한다.",
  "FQ-123c — D34_RealVol_21d(21일 창)는 아직 미측정 arm 이다. D35(63d)가 rv63 과 0.9967 이었으니 D34 도 rv21 과 유사할 것으로 예상되나 실측 전이다. 착수 시 '흡수 여부'가 아니라 '더 짧은 창이 별도 정보를 담는가'로 물어야 한다.")
q$entries <- E; write(toJSON(q, auto_unbox=TRUE, pretty=TRUE, null="null"), p)
cat("[123] 갱신 완료\n")
