# controls.R — 대조군 정책 (양성 대조 · 상한 · 위반 주입)
#
# ★오라클은 **일부러 반칙한다**. 뷰가 아니라 세계 전체를 보고 최단 경로로 최고 칸을 연다.
#   정책이 아니라 상한선을 재는 계기다. 실루프에 실을 수 없다.
# ★엿보기는 **잡히라고 만든 것**이다. 뷰 밖 데이터를 만지려 시도한다.

# ── 오라클 상한 ──────────────────────────────────────────────────────────
# 전역 최고 칸을 알고, 그 칸이 합법이 될 때까지 필요한 최소 선행 칸만 연 뒤 정지.
make_oracle <- function(world) {
  nd <- world$nodes
  ev <- nd[nd$evaluated, , drop = FALSE]
  if (!nrow(ev)) return(function(view) list(batch = character(0), stop = TRUE))
  target <- ev$node_id[which.max(ev$score)]
  tgt_row <- nd[nd$node_id == target, ]
  function(view) {
    lg <- view$legal()
    if (!nrow(lg)) return(list(batch = character(0), stop = TRUE))
    if (target %in% lg$node_id) return(list(batch = target, stop = FALSE))
    # 목표의 바닥을 만들어야 한다 — 그 바닥 칸을 먼저 연다
    need <- tgt_row$parent
    cand <- lg$node_id[lg$cell_code == need]
    if (length(cand)) return(list(batch = cand[1], stop = FALSE))
    # 바닥이 아직 합법이 아니면 B1 을 하나씩 연다(바닥은 B1 승자에서 자란다)
    b1 <- lg$node_id[lg$block == "B1"]
    if (length(b1)) return(list(batch = b1[1], stop = FALSE))
    list(batch = lg$node_id[1], stop = FALSE)
  }
}

# 목표를 이미 열었으면 멈추는 래퍼
make_oracle_stop <- function(world) {
  f <- make_oracle(world)
  nd <- world$nodes; ev <- nd[nd$evaluated, , drop = FALSE]
  target <- if (nrow(ev)) ev$node_id[which.max(ev$score)] else NA_character_
  function(view) {
    r <- view$revealed()
    if (!is.na(target) && target %in% r$node_id) return(list(batch = character(0), stop = TRUE))
    f(view)
  }
}

# ── 위반 주입 ────────────────────────────────────────────────────────────
# 뷰 밖의 미공개 점수를 가져오려 시도한다. 성공하면 방어선이 뚫린 것이다.
pol_peek_violation <- function(view) {
  probes <- list(
    function() get("nd", envir = parent.frame(3)),
    function() get("world", envir = globalenv()),
    function() get("ws", envir = globalenv()),
    function() sys.frames()[[1]]$nd,
    function() parent.frame(2)$nd
  )
  stolen <- NULL
  for (p in probes) {
    v <- tryCatch(p(), error = function(e) NULL)
    if (!is.null(v) && is.data.frame(v) && "score" %in% names(v)) { stolen <- v; break }
  }
  lg <- view$legal()
  if (!nrow(lg)) return(list(batch = character(0), stop = TRUE, peeked = !is.null(stolen)))
  if (!is.null(stolen)) {
    # 훔친 점수로 최고 칸 직행
    s <- stolen[stolen$node_id %in% lg$node_id, , drop = FALSE]
    if (nrow(s)) return(list(batch = s$node_id[which.max(s$score)], stop = FALSE, peeked = TRUE))
  }
  list(batch = lg$node_id[1], stop = FALSE, peeked = FALSE)
}
