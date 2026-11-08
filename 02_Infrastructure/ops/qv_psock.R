# qv_psock.R — PSOCK 클러스터를 '실제로 열 수 있는 포트'로 만든다 (2026-11-09 · 메인 PC 포트 예약 실측)
#
# 왜: Windows(Hyper-V/WSL 동적 예약)가 TCP 포트 묶음을 예약하면 R parallel 의 기본 포트가 막혀
#   parallel::makePSOCKcluster() 가 'creation of server socket failed: port N cannot be opened' 로 죽는다.
#   실측 2026-11-08 메인 PC(MAINCOMPUTER): 11004–11103 · 11186–11385 · 11491–11690 · 11969–12068 예약 →
#   R 기본 범위(11000–11999) 1000개 중 531개가 막힘(확인: netsh interface ipv4 show excludedportrange protocol=tcp).
#   ★parallel 은 기본 포트를 **패키지를 불러올 때 한 번** 정한다(initDefaultClusterOptions) — 그 프로세스의 모든
#   makePSOCKcluster() 가 같은 포트를 쓰므로 그 포트가 막혔으면 같은 프로세스에서 다시 불러도 계속 실패한다.
#   운영 피해 = 배치 재측정(remeasure_from_holdings) · 등급 재채점(grade_v3_backfill/retro) · MSM 적합 · 네이버 수집이 멈춤.
#
# 동작: R_PARALLEL_PORT 가 숫자면 그 포트 그대로(사람이 정한 값 · 재시도 없음). 아니면 후보 포트를 차례로
#   makePSOCKcluster(n, port = p) 로 시도하고 '서버 소켓을 못 엶' 오류일 때만 다음 후보로 넘어간다(다른 오류 = 그대로 stop).
#   후보 = 같은 범위(11000–11999)를 1000 과 서로소인 보폭으로 도는 순서(겹치지 않음) — 전역 난수(.Random.seed)를 쓰지 않는다.
#   후보가 다 막히면 stop(시도 수 · 예약 확인 명령) — 조용히 NULL 을 내지 않는다(순차 폴백 여부는 호출자가 정한다).
#   성공하면 클러스터에 attr(cl, "qv_port") = 쓴 포트.
#
# 사용: source(file.path(<루트>, "02_Infrastructure/ops/qv_psock.R")); cl <- qv_psock_cluster(n)
#       (정리는 종전대로 parallel::stopCluster(cl) — 함수 안 on.exit 또는 tryCatch(finally =))
# 검사 = 08_Tests/ops/test_qv_psock.R(점유 포트 주입 · 전부 막힘 · 포트 아닌 오류 · R_PARALLEL_PORT · 난수 불변 · 돌연변이 통제)

.QV_PSOCK_PORT_ERR <- "server socket|cannot be opened"

.qv_psock_candidates <- function(tries = 40L, base = 11000L, span = 1000L, step = 389L) {
  start <- (as.integer(Sys.getpid()) * 7919L + as.integer(as.numeric(Sys.time()) %% 100000) * 31L) %% span
  as.integer(base + (start + step * (seq_len(min(tries, span)) - 1L)) %% span)   # 389 ⊥ 1000 → 범위 안을 겹치지 않고 돈다
}

qv_psock_cluster <- function(n, ..., ports = NULL, tries = 40L) {
  n <- suppressWarnings(as.integer(n)[1])
  if (is.na(n) || n < 1L) stop("[qv_psock] 작업자 수 n 이 1 미만")
  env_port <- Sys.getenv("R_PARALLEL_PORT", "")
  if (is.null(ports) && grepl("^[0-9]+$", env_port)) return(parallel::makePSOCKcluster(n, ...))
  cand <- as.integer(if (is.null(ports)) .qv_psock_candidates(tries) else ports)
  tried <- integer(0)
  for (p in cand) {
    cl <- tryCatch(parallel::makePSOCKcluster(n, port = p, ...), error = function(e) e)
    if (!inherits(cl, "error")) {
      attr(cl, "qv_port") <- p
      return(cl)
    }
    if (!grepl(.QV_PSOCK_PORT_ERR, conditionMessage(cl), ignore.case = TRUE)) stop(cl)   # 작업자 기동 실패 등은 재시도하지 않는다
    tried <- c(tried, p)
  }
  stop(sprintf("[qv_psock] 서버 소켓을 열 포트를 못 찾았다(%d개 시도: %s%s) — 예약 확인: netsh interface ipv4 show excludedportrange protocol=tcp",
               length(tried), paste(head(tried, 8), collapse = ","), if (length(tried) > 8) ",…" else ""))
}
