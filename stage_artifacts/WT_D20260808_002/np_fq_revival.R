## FQ-161~163 에 부활 조건(INV-7) 추가 — negative/보류 항목이 언제 되살아나는지 기계 기록
suppressPackageStartupMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[rev] ",fmt,"\n"),...))
QP <- "06_Registry/alpha_frontier_queue.json"
q <- fromJSON(QP, simplifyVector = FALSE)
ids <- vapply(q$entries, function(e) if (is.null(e$id)) "" else as.character(e$id), character(1))
say("★입력 실측: entries %d · 대상 3건 위치 = %s", length(q$entries),
    paste(which(ids %in% c("FQ-161","FQ-162","FQ-163")), collapse=" "))

rev <- list(
  "FQ-161" = paste0("재개 조건: ① 소비면 7종 중 하나에서 paired 한계기여가 관측되면 즉시 승격 ",
    "② 자본 자격 재도전은 cap-w PORT_t 가 2.95 를 넘거나 oos_retention 이 0.5 이상으로 회복될 때만 ",
    "(현행 1.544 / 0.123 — 랭킹 슬롯 경로는 이 구성에서 미달). ",
    "③ 상위 25종목 랭킹 재시도는 새 구성 근거(다른 결합·다른 horizon·다른 유니버스) 없이는 금지."),
  "FQ-162" = paste0("재개 조건: 컨센서스 원천에 제공시각 메타가 확보되거나 T-1 strict 재빌드가 가능해지면 즉시 착수. ",
    "★본 라운드에서 T+1 실행앵커 대리측정은 완료(t +2.305 유지율 0.90) — 따라서 이 항목은 ",
    "'후보 검증'이 아니라 '하네스 전역 33종(북 incumbent 포함) 절대수준 보정'이 목적이다."),
  "FQ-163" = paste0("재개 조건: 빌더 수리 배선 후 C10·C13·C15·C18 이 factor_db 에 실제로 산출되는 것을 ",
    "확인한 다음에만 재료 자격 라운드 착수. ★수리 전 착수 금지 — 없는 팩터는 잴 수 없다. ",
    "수리 시 위반 주입 테스트(살아있는 블록 하나를 일부러 무력화 → 경고 발화 확인) 통과가 착수 전제."))

n <- 0L
for (i in seq_along(q$entries)) {
  k <- ids[i]
  if (k %in% names(rev)) { q$entries[[i]]$revival_condition <- rev[[k]]; n <- n + 1L }
}
say("부활 조건 추가 %d건", n)
stopifnot(n == 3L)
q$updated <- "2026-08-08"
write(toJSON(q, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null"), QP)
say("저장 완료 — 후속 감사는 np_queue_diff_audit.R")
