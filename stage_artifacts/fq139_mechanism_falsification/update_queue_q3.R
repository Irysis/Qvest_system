# update_queue_q3.R — Q3: FQ-138 mechanism 서술 갱신 + FQ-139 종결 반영
# 근거: 오늘(2026-08-08) FQ-139 아크에서 '기관 후속매수' 경로가 기각되고 '외국인 단독'으로 확정.
#   큐를 갱신하지 않으면 FQ-138 사전등록 라운드가 **기각된 경로를 전제로** 심사하게 된다
#   ([[project-registry-staleness-3near-misses-20260808]] 계열: 큐가 자기보다 나중 판정을 반영 안 함).
# ★원 hypothesis 텍스트는 역사 기록이므로 덮지 않고 별도 필드로 갱신을 병기한다.
suppressMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
QP <- "06_Registry/alpha_frontier_queue.json"
stopifnot(file.exists(QP))
bak <- sprintf("%s.bak_q3_%s", QP, format(Sys.time(), "%Y%m%d_%H%M%S"))
file.copy(QP, bak); cat(sprintf("[백업] %s\n", bak))

q <- fromJSON(QP, simplifyVector = FALSE)
stopifnot(!is.null(q$entries))
n_before <- length(q$entries)
hit <- c(FQ138 = 0L, FQ139 = 0L)
for (i in seq_along(q$entries)) {
  e <- q$entries[[i]]
  if (is.null(e$id)) next
  if (identical(e$id, "FQ-138")) {
    e$mechanism_update_20260808 <- paste0(
      "★기전 갱신(FQ-139 아크 실측): mechanism.path 의 '기관 후속 매수로 가격 반영'은 **기각**. ",
      "계약 신호 상위에서 기관 순매수는 11/11 분할·신호 조합에서 증가하지 않았고(유의 1/11), ",
      "대신 **외국인 순매수가 유의 증가**(확장표본 n=7,069, t=3.84, p=0.0001; 10/11 조합). ",
      "또한 그 외국인 경로는 **국면 의존을 설명하지 못한다** — 상호작용 −0.00613(p=0.338), ",
      "표본 2.1배 확대에도 부호·유의성 불변이며 수급 우위는 오히려 알파가 **약한** mega주도 국면에서 더 크다. ",
      "대안으로 검토한 소형주 유동성 사이클은 **전제부터 기각**(소형/대형 유동성비 broad 0.2044 vs mega 0.2026, p=0.880). ",
      "잔여 후보: 상대적 소형주 **비유동성**이 알파 강도와 동행(Spearman −0.3449, p=0.0021, 방향은 직관과 반대) — 사전등록 재판정 대상. ",
      "∴ 사전등록 라운드는 mechanism 서술을 '외국인 매수(국면 무관) + 국면 의존 기전 미해결'로 갱신한 뒤 착수할 것.")
    e$blocking_precondition <- "mechanism 서술 갱신 선행 — 구 서술('기관 후속매수')로 착수 시 기각된 경로를 전제로 심사하게 됨"
    q$entries[[i]] <- e; hit["FQ138"] <- 1L
  }
  if (identical(e$id, "FQ-139")) {
    e$status <- "done"
    e$verdict_20260808 <- paste0(
      "기전 검증 완료 — mechanism.path('기관 후속매수') **기각**, 경로는 **외국인 단독**으로 재서술. ",
      "F1 강건성(3분할×4신호): 부호 11/11 일관, 외국인 p<0.05 10/11 vs 기관 1/11. ",
      "F2/H2 국면 상호작용: −0.00613(p=0.338), 확장표본 7,069건에서도 불변 → 수급은 국면 의존 설명 못함. ",
      "G2 유동성 사이클: 전제 기각(p=0.880). 부수 발견: 소형/대형 유동성비 ↔ 월별 IC Spearman −0.3449(p=0.0021).")
    e$next_probes_20260808 <- list(
      "Q1 상대적 비유동성 조건화 사전등록 재판정(문턱·창·유동성 정의 사전 명시, 분포 q05)",
      "Q2 방향 기전 3후보(정보확산 지연/군집 회피/size 교락) — size 교락 배제 우선",
      "F3 순매수 정규화 축 강건성(시총·유통주식 기준)")
    q$entries[[i]] <- e; hit["FQ139"] <- 1L
  }
}
stopifnot("FQ-138 미발견" = hit["FQ138"] == 1L, "FQ-139 미발견" = hit["FQ139"] == 1L)
q$updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
write(toJSON(q, pretty = TRUE, auto_unbox = TRUE, null = "null"), QP)

chk <- fromJSON(QP, simplifyVector = FALSE)
stopifnot("항목수 변화" = length(chk$entries) == n_before)
ok138 <- any(vapply(chk$entries, function(e) identical(e$id,"FQ-138") && !is.null(e$mechanism_update_20260808), logical(1)))
ok139 <- any(vapply(chk$entries, function(e) identical(e$id,"FQ-139") && identical(e$status,"done"), logical(1)))
cat(sprintf("[검증] 항목 %d개 보존 | FQ-138 갱신 %s | FQ-139 done %s\n", length(chk$entries), ok138, ok139))
stopifnot(ok138, ok139)
cat("[Q3] 큐 갱신 완료 — 사전등록 라운드의 선행 조건 해소\n")
