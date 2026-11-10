## trial_budget.R — 시행 예산 계산 (v10.2 · 2026-11-10 전수점검 결론 '시행은 소진되는 자원이다')
##
## 무엇: 스윕형 선택(여러 칸 중 하나를 고르는 라운드)에서 등급 계약의 DSR 관문(dsr_min)을 넘으려면
##   (a) 누적 시행 수 N 일 때 필요한 최소 활성 SR(연율)과 그에 해당하는 대략의 t 값,
##   (b) 기대하는 활성 SR 에서 허용되는 최대 N
##   을 **등급 계약의 DSR 함수 그대로**(contracts/essence_score.R::.essence_dsr — Bailey & López de Prado 2014, 'The Deflated Sharpe
##   Ratio', Journal of Portfolio Management 40(5):94-107, https://doi.org/10.3905/jpm.2014.40.5.094) 계산한다.
##   식을 여기 복제하지 않는다 — 계약 소스에서 함수 정의를 꺼내 쓴다(두 구현이 갈리면 계획 수치가 판정과 어긋난다).
## 왜: 현 축 B 47건 중 42건이 DSR 관문에 막혀 있고, 한 계보의 누적 시행 수는 216 → 264 로 늘기만 했다. 변형을 더 만들수록
##   같은 계보의 모든 후보에게 A 가 멀어진다. 라운드 설계 때 '몇 칸까지 재도 되는가'를 등록 전에 계산해 변형 수 상한의 근거로 쓴다.
## 쓰는 곳: 사전등록(변형 수 상한의 근거 — research-program SKILL §2 '시행 예산'). 측정 · 등급을 바꾸지 않는다(계획 계산).
## 한계: DSR 은 활성 수익(전략 − 벤치) 월별 계열로 계산된다. approx_t 는 자기상관을 무시한 근사(SR_월 × √n)이고 등급의 PORT_t
##   (Newey-West)와 같지 않다 — 규모 감을 주는 값이다. skew · kurt 는 기본값(0 · 3)이며 실제 계열 값으로 바꿔 넣을 수 있다.
## 사용: Rscript 02_Infrastructure/programs/trial_budget.R [n_obs=300] — 표 출력. 함수: tb_min_sr · tb_max_trials · tb_table.

.tb_root <- function(root = NULL) {
  r <- if (length(root) == 1L && !is.na(root) && nzchar(root)) root else
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
  gsub("\\\\", "/", r)
}

## 계약 소스에서 .essence_dsr 정의만 꺼낸다(파일 전체 source 는 다른 의존을 끌고 온다 · 계약 파일은 읽기만)
tb_load_dsr <- function(root = NULL) {
  f <- file.path(.tb_root(root), "02_Infrastructure", "contracts", "essence_score.R")
  if (!file.exists(f)) stop("[trial_budget] 등급 계약 부재: ", f)
  ex <- parse(f, keep.source = FALSE, encoding = "UTF-8")
  e <- new.env(parent = globalenv())                     # pnorm · qnorm(stats)을 찾을 수 있어야 한다
  for (x in ex) if (is.call(x) && identical(x[[1]], as.name("<-")) && is.name(x[[2]]) && identical(as.character(x[[2]]), ".essence_dsr")) eval(x, envir = e)
  if (!exists(".essence_dsr", envir = e, inherits = FALSE)) stop("[trial_budget] 계약에서 .essence_dsr 를 찾지 못했다 — 계약이 바뀌었다(이 도구도 따라가야 한다)")
  fn <- get(".essence_dsr", envir = e)
  if (!all(c("sr_ann", "n_obs", "n_trials") %in% names(formals(fn)))) stop("[trial_budget] .essence_dsr 인자 모양이 바뀌었다")
  fn
}

## DSR 관문 값 — 정본 = constraint_defaults.json::tier_graduation.min_deflated_sharpe_ratio
tb_dsr_min <- function(root = NULL) {
  p <- file.path(.tb_root(root), "02_Infrastructure", "worktask", "constraint_defaults.json")
  v <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE)$tier_graduation$min_deflated_sharpe_ratio, error = function(e) NULL)
  if (is.null(v) || !is.finite(as.numeric(v))) stop("[trial_budget] DSR 관문 값을 읽지 못했다: ", p)
  as.numeric(v)
}

## (a) 시행 수 N · 관측 수 n_obs 에서 DSR ≥ dsr_min 이 되는 최소 활성 SR(연율)
tb_min_sr <- function(n_trials, n_obs, A = 12, skew = 0, kurt = 3, dsr_min = NULL, root = NULL, dsr_fn = NULL) {
  fn <- if (is.null(dsr_fn)) tb_load_dsr(root) else dsr_fn
  dm <- if (is.null(dsr_min)) tb_dsr_min(root) else dsr_min
  g <- function(s) fn(s, n_obs, n_trials, skew, kurt, A = A) - dm
  lo <- 0; hi <- 20
  if (!is.finite(g(lo)) || !is.finite(g(hi))) return(NA_real_)
  if (g(lo) >= 0) return(0)
  if (g(hi) < 0) return(NA_real_)
  stats::uniroot(g, c(lo, hi), tol = 1e-10)$root
}

## (b) 활성 SR(연율) 에서 DSR ≥ dsr_min 을 유지하는 최대 시행 수(상한 max_n 까지 이분 탐색 · 못 넘으면 0 · 상한에서도 넘으면 max_n)
tb_max_trials <- function(sr_ann, n_obs, A = 12, skew = 0, kurt = 3, dsr_min = NULL, root = NULL, dsr_fn = NULL, max_n = 1e6) {
  fn <- if (is.null(dsr_fn)) tb_load_dsr(root) else dsr_fn
  dm <- if (is.null(dsr_min)) tb_dsr_min(root) else dsr_min
  ok <- function(n) { v <- fn(sr_ann, n_obs, n, skew, kurt, A = A); is.finite(v) && v >= dm }
  if (!ok(1)) return(0)
  if (ok(max_n)) return(as.numeric(max_n))
  lo <- 1; hi <- max_n                                    # ok(lo) TRUE · ok(hi) FALSE
  while (hi - lo > 1) { mid <- floor((lo + hi) / 2); if (ok(mid)) lo <- mid else hi <- mid }
  as.numeric(lo)
}

## 표 — 시행 수별 필요한 최소 활성 SR 과 근사 t
tb_table <- function(n_obs = 300, Ns = c(1, 5, 10, 20, 50, 100, 250, 500, 1000), A = 12, root = NULL) {
  fn <- tb_load_dsr(root); dm <- tb_dsr_min(root)
  ms <- vapply(Ns, function(n) tb_min_sr(n, n_obs, A = A, dsr_min = dm, dsr_fn = fn), numeric(1))
  data.frame(n_trials = Ns, min_active_sr_ann = round(ms, 3), approx_t = round(ms / sqrt(A) * sqrt(n_obs), 2), dsr_min = dm, n_obs = n_obs)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  n_obs <- if (length(a) && grepl("^[0-9]+$", a[1])) as.integer(a[1]) else 300L
  cat(sprintf("[trial_budget] 관측 %d개월 · DSR 관문 %.2f — 시행 수별로 필요한 최소 활성 SR(연율)과 근사 t\n", n_obs, tb_dsr_min()))
  print(tb_table(n_obs), row.names = FALSE)
}
