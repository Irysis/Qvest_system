# B3-14 섀도 — 병렬 rulefast 배치 중 러너의 자동 rf_open_entry(신규 원장 entry 생성)를
# 차단한다. 이 시도는 이미 기존 entry RP_20260829_122020_9192_rulefast attempt n=14 로
# 사전 등록돼 있다 — 결과 기입은 세션(Q-Lead) 소관. 하네스 파일 무수정, 이 run 한정.
rf_open_entry <- function(...) {
  cat("[B3-14] rf_open_entry suppressed — 기존 rulefast entry attempt n=14 에 귀속 (세션이 기입)\n")
  invisible(NULL)
}
