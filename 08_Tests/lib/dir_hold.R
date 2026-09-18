#==============================================================================
# dir_hold.R — 디렉터리를 **실물로** 지울 수 없게 붙잡는 검사 픽스처 (2026-09-19)
#
# 왜: claim 해제 판정(rf_claim_release)은 "디렉터리를 못 지웠다" 가 실재할 때만 갈린다. 함수를 덮는 흉내로는
#   unlink 이 owner.json 만 지우고 디렉터리를 남기는 실사고 모양을 못 만든다. Windows 는 어떤 프로세스의
#   **작업 디렉터리**를 지우지 못하게 한다 — 이 프로세스가 setwd() 로 그 자리에 앉아 있는 동안 unlink 은
#   안의 파일만 지우고 디렉터리는 남긴다(2026-09-19 실측 = 09-18 23:53 B5 레인 claim 과 같은 모양 ·
#   그 상태에서도 안에 새 파일은 쓸 수 있다 = 해제 표식은 남는다).
#
# 사용: Rscript dir_hold.R <dir> <ready_file> <stop_file> [max_sec=120]
#   <dir> 에 앉은 뒤 <ready_file> 에 자기 pid 를 쓴다 → <stop_file> 이 생기거나 max_sec 가 지나면 나간다.
#   ★ready/stop 은 **절대 경로**로 — 앉은 뒤의 상대 경로는 붙잡은 디렉터리 안을 가리킨다.
#   ★스스로 끝난다 — 검사가 도중에 죽어도 잠금이 max_sec 넘게 남지 않는다.
# 소비자: 08_Tests/reinforcement/test_rf_claim.R · 08_Tests/ops/test_reinforce_auto.sh(3d) · 08_Tests/ops/test_rf_b5_design.sh(S12)
#==============================================================================
a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 3L) { cat("usage: Rscript dir_hold.R <dir> <ready_file> <stop_file> [max_sec]\n"); quit(status = 2L) }
max_sec <- if (length(a) >= 4L) suppressWarnings(as.numeric(a[4])) else 120
if (!is.finite(max_sec) || max_sec <= 0) max_sec <- 120
setwd(a[1])
writeLines(as.character(Sys.getpid()), a[2])
t0 <- Sys.time()
while (!file.exists(a[3]) && as.numeric(difftime(Sys.time(), t0, units = "secs")) < max_sec) Sys.sleep(0.1)
quit(status = 0L)
