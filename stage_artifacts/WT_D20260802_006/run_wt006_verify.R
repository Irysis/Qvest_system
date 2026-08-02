# =============================================================================
# run_wt006_verify.R — WT-D20260802_006 구현 정확성 검증 (사전등록 의무 6종)
#   위반 주입 원칙: 이론값과의 대조 + 고의로 깨뜨린 구현이 잡히는지 확인.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_006/run_wt006_verify.R")'
# =============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("stage_artifacts/WT_D20260802_006/signature_lib.R")
say <- function(fmt, ...) cat(sprintf(paste0("[verify] ", fmt, "\n"), ...))
PASS <- list()
chk <- function(name, ok, detail = "") {
  PASS[[name]] <<- isTRUE(ok)
  say("%-38s %s %s", name, ifelse(isTRUE(ok), "PASS", "FAIL"), detail)
}
max_abs <- function(...) max(abs(unlist(list(...))))

set.seed(20260802)

# ── T1. 선형 경로: S2 = Δ⊗Δ/2, S3 = Δ⊗Δ⊗Δ/6, 전 area = 0 ──────────────────
delta <- c(0.7, -1.3, 2.1)
tt <- seq(0, 1, length.out = 15)
Xlin <- outer(tt, delta)                      # 15점 공선 경로
S <- sig3_ref(Xlin)
e2 <- outer(delta, delta) / 2
e3 <- array(0, c(3, 3, 3))
for (j in 1:3) for (k in 1:3) for (l in 1:3) e3[j, k, l] <- delta[j] * delta[k] * delta[l] / 6
d1 <- max_abs(S$s1 - delta); d2 <- max_abs(S$s2 - e2); d3 <- max_abs(S$s3 - e3)
areas <- max_abs(levy_area(S, 1, 2), levy_area(S, 1, 3), levy_area(S, 2, 3))
chk("T1 linear closed-form (lv1/2/3)", d1 < 1e-12 && d2 < 1e-12 && d3 < 1e-12,
    sprintf("max|diff|=%.2e", max(d1, d2, d3)))
chk("T1b linear Levy areas = 0", areas < 1e-12, sprintf("max|A|=%.2e", areas))

# ── T2. 단위원 1회전(반시계): A_12 → +π ─────────────────────────────────────
N <- 4000
th <- seq(0, 2 * pi, length.out = N + 1)
Xc <- cbind(cos(th), sin(th))
Sc <- sig3_ref(Xc)
Ac <- levy_area(Sc, 1, 2)
chk("T2 circle Levy area = pi", abs(Ac - pi) < 1e-5, sprintf("A=%.8f (pi=%.8f)", Ac, pi))
# 시계방향이면 −π (부호가 회전방향을 판별)
Scw <- sig3_ref(Xc[rev(seq_len(nrow(Xc))), ])
chk("T2b clockwise = -pi", abs(levy_area(Scw, 1, 2) + pi) < 1e-5,
    sprintf("A=%.8f", levy_area(Scw, 1, 2)))

# ── T3. Chen 항등식: sig(X∘Y) = sig(X)⊗sig(Y) ──────────────────────────────
X1 <- apply(matrix(rnorm(30 * 3), 30, 3), 2, cumsum)
X2s <- apply(matrix(rnorm(25 * 3), 25, 3), 2, cumsum)
X2 <- sweep(X2s, 2, X2s[1, ] - X1[nrow(X1), ])   # 연접점 이어붙임
Xfull <- rbind(X1, X2[-1, ])
Sfull <- sig3_ref(Xfull)
Scomb <- sig3_concat(sig3_ref(X1), sig3_ref(X2))
dch <- max_abs(Sfull$s1 - Scomb$s1, Sfull$s2 - Scomb$s2, Sfull$s3 - Scomb$s3)
chk("T3 Chen identity", dch < 1e-10, sprintf("max|diff|=%.2e", dch))

# ── T4. 재매개화 불변: 공선 중간점 삽입 → 시그니처 정확 불변 ─────────────────
Xr <- apply(matrix(rnorm(40 * 2), 40, 2), 2, cumsum)
ins <- function(X) {   # 각 세그먼트 중간점 삽입 (시간축 왜곡 등가)
  out <- X[1, , drop = FALSE]
  for (i in 2:nrow(X)) out <- rbind(out, (X[i - 1, ] + X[i, ]) / 2, X[i, ])
  out
}
Sa <- sig3_ref(Xr); Sb <- sig3_ref(ins(ins(Xr)))
drp <- max_abs(Sa$s1 - Sb$s1, Sa$s2 - Sb$s2, Sa$s3 - Sb$s3)
chk("T4 reparam invariance", drp < 1e-10, sprintf("max|diff|=%.2e", drp))

# ── T5. 위상차 사인파: A_pv = −π·sin(φ) — 사전등록 방향의 수치 확인 ─────────
for (phi in c(pi / 6, pi / 2)) {
  tg <- seq(0, 2 * pi, length.out = 3001)
  P <- cbind(p = sin(tg - phi), v = sin(tg))     # v가 p를 선행
  Sp <- sig3_ref(P)
  Apv <- levy_area(Sp, 1, 2)
  chk(sprintf("T5 lead-lag phi=%.2f A_pv=-pi*sin(phi)", phi),
      abs(Apv - (-pi * sin(phi))) < 1e-3,
      sprintf("A=%.6f theory=%.6f (v-선행 ⇒ A_pv<0 ⇒ score=-A_pv>0 확인)", Apv, -pi * sin(phi)))
}

# ── T6. 벡터화 == 참조 parity (무작위 3D 경로 50개) ─────────────────────────
worst <- 0
for (r in 1:50) {
  n <- sample(20:120, 1)
  Xp <- apply(matrix(rnorm(n * 3, sd = runif(1, 0.5, 3)), n, 3), 2, cumsum)
  Sr <- sig3_ref(Xp); Sf <- sig3_fast(diff(Xp))
  worst <- max(worst, max_abs(Sr$s1 - Sf$s1, Sr$s2 - Sf$s2, Sr$s3 - Sf$s3))
}
chk("T6 fast==ref parity (50 random)", worst < 1e-9, sprintf("worst=%.2e", worst))

# levy_pv_only == sig_features_pv A_pv parity
cl <- exp(cumsum(rnorm(63, 0, 0.02))) * 10000
vo <- exp(cumsum(rnorm(63, 0, 0.3))) * 1e5
f1 <- sig_features_pv(cl, vo)
f2 <- levy_pv_only(cl, vo)
chk("T6b features==pv_only parity", abs(f1[["A_pv"]] - f2) < 1e-10,
    sprintf("diff=%.2e", abs(f1[["A_pv"]] - f2)))

# ── T7. 위반 주입: 고의로 깨뜨린 구현이 검출되는가 (검사기 생존 확인) ────────
bad_area <- function(X) {  # 흔한 오류: shoelace를 원점 미평행이동으로 계산 → 평행이동 가변
  x <- X[, 1]; y <- X[, 2]; n <- nrow(X)
  sum(x[-n] * y[-1] - x[-1] * y[-n]) / 2
}
Xsh <- sweep(Xr, 2, c(100, -50))               # 평행이동한 열린 경로
inj <- abs(bad_area(Xr) - bad_area(Xsh)) > 1e-6   # bad는 평행이동에 흔들려야
tru <- abs(levy_area(sig3_ref(Xr), 1, 2) - levy_area(sig3_ref(Xsh), 1, 2)) < 1e-9
chk("T7 violation-injection (translation)", inj && tru,
    "bad 구현은 평행이동에 가변(검출), 시그니처 area는 불변")

# ── 요약 ─────────────────────────────────────────────────────────────────────
n_ok <- sum(unlist(PASS)); n_all <- length(PASS)
say("=== %d/%d PASS ===", n_ok, n_all)
res <- list(generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            results = PASS, n_pass = n_ok, n_total = n_all,
            all_pass = n_ok == n_all)
jsonlite::write_json(res, "stage_artifacts/WT_D20260802_006/verify_results.json",
                     auto_unbox = TRUE, pretty = TRUE)
if (n_ok != n_all) stop("[verify] FAIL 존재 — 패널 빌드 진행 금지")
