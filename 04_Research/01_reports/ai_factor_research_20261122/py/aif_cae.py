"""aif_cae.py — 단계 4: 조건부 오토인코더(잠재팩터의 노출이 특성의 비선형 함수인 모형).

구조는 Gu, Kelly & Xiu (2021, Journal of Econometrics 222(1) https://doi.org/10.1016/j.jeconom.2020.07.009)의 CA2 를 따른다:
  노출 쪽   β(i, s) = 신경망(z(i, s))             — 은닉 32 · 16(ReLU · 배치 정규화) → K · 입력 = 간추린 특성 약 150개(aif_latent.py 와 같은 것)
  팩터 쪽   f(s+1)  = W · x̃(s+1)                 — 백색화한 관리 포트폴리오 수익 x̃(s+1) = Z̃_s' r_{s+1} ÷ N_s 의 선형 결합(백색화 = aif_latent.py 의 ① · 그때까지의 달만으로)
  출력      r̂(i, s+1) = β(i, s)' f(s+1)          — 실제 수익과의 제곱 오차 + 가중치 L1 벌점을 줄인다
  학습      Adam · 달 묶음 단위 · 조기 종료(인내 5) · 씨앗 10개의 평균 · 팩터 수 K = {3, 5} 는 시간순 검증 손실로 고른다
재추정 일정은 aif_latent.py 와 같다(해마다 12월 신호일 · 그때까지 실현된 달만 · 확장 창 · 뒤 20% 달 = 검증).
  종목 기대수익 점수 μ(i, s) = β(i, s)' λ — λ = 학습 창의 팩터 평균 수익(씨앗마다 구해 평균한다 · 씨앗마다 팩터의 회전이 달라도 이 값은 같다)
  잠재팩터 포트폴리오  씨앗마다 팩터가 다른 회전으로 나오므로, 씨앗 10개의 팩터를 모두 쌓아(학습 창 수익의 표준편차 1 로 맞춰) 주성분을 뽑아 '합의 팩터' 를 만든다.
                       합의 팩터 j = 백색화한 관리 포트폴리오의 가중 w_j(길이 1) → 종목 비중 = Z̃ w_j ÷ N(특성 가중 포트폴리오 · 노출 1 단위당 수익 — PCA 계열과 같은 척도)
산출: factors/LAT_CAE.parquet(종목 점수) · latent/LAT_CAE_F1~3.parquet(합의 팩터의 종목 비중) · 합의 팩터와 특성의 상관 상위 · 모형 설명력(씨앗별 값의 평균).
실행: python py/aif_cae.py [--smoke] [--force]   (해 하나 = 체크포인트 하나)
"""
import argparse
import os
import sys
import time

import numpy as np

import aif_common as ac
from aif_enumerate import Compact
from aif_features import FeatureStore
from aif_latent import latent_features, moments, structure, whiten

VERSION = 2                                    # 2 = 팩터 쪽 입력을 백색화한 관리 포트폴리오로 · 잠재팩터 포트폴리오 = 씨앗 합의 팩터
HIDDEN, K_GRID, N_SEEDS, N_PORT = (32, 16), (3, 5), 10, 3
LR, L1, MONTHS_PER_BATCH, MAX_EPOCH, PATIENCE, VAL_FRAC, BURN_YEARS, SEED0 = 0.001, 1e-4, 8, 200, 5, 0.2, 5, 20261123
PARAM_SRC = {"HIDDEN": "Gu, Kelly & Xiu 2021 의 CA2(은닉 32-16) — 논문에서 표본 밖 성과가 가장 좋았던 구조", "K_GRID": "팩터 수 3 · 5(논문은 1~6 을 본다 · 계산량 때문에 두 값)",
             "LR · L1": "논문 격자(학습률 0.001~0.01 · L1 1e-5~1e-3)의 가운데 값으로 고정", "N_SEEDS": "씨앗 10개 평균(논문과 같다)",
             "MAX_EPOCH · PATIENCE": "최대 200에폭 · 조기 종료 인내 5(논문과 같다)",
             "MONTHS_PER_BATCH": "한 걸음에 달 8개(팩터 쪽이 달 단면 전체를 쓰므로 달 단위로 묶는다) — 근거 논문 없음 · 이 연구의 설계 선택"}


def build_net(L, M, K, dev, seed):
    import torch
    import torch.nn as nn
    torch.manual_seed(seed)
    layers, d = [], L
    for h in HIDDEN:
        layers += [nn.Linear(d, h), nn.BatchNorm1d(h), nn.ReLU()]
        d = h
    return nn.Sequential(*layers, nn.Linear(d, K)).to(dev), nn.Linear(M, K, bias=False).to(dev)


def rows_of(cp, months, fin):
    """달 목록 → (행 번호, 행마다 그 달이 목록의 몇 번째인가). 수익이 없는 행은 뺀다."""
    idx, mi = [], []
    for j, s in enumerate(months):
        a, b = cp.seg[s], cp.seg[s + 1]
        r = np.arange(a, b)[fin[a:b]]
        idx.append(r)
        mi.append(np.full(len(r), j, dtype=np.int64))
    return np.concatenate(idx), np.concatenate(mi)


def forward(beta, fac, Zt, Xt, rows, mi, months):
    return (beta(Zt[rows]) * fac(Xt[months])[mi]).sum(1)          # [행] = 노출 [행 × K] · 그 달 팩터 수익 [달 × K]


def train(Zt, rt, Xt, cp, fin, tr_m, va_m, K, seed, dev):
    """한 씨앗 학습 → (노출 망, 팩터 쪽 가중, 가장 좋았던 검증 손실, 에폭 수). 검증 손실이 PATIENCE 에폭 동안 나아지지 않으면 멈추고 가장 좋았던 가중치로 되돌린다."""
    import torch
    beta, fac = build_net(Zt.shape[1], Xt.shape[1], K, dev, seed)
    params = list(beta.parameters()) + list(fac.parameters())
    opt = torch.optim.Adam(params, lr=LR)
    rng = np.random.default_rng(seed)
    vrows, vmi = rows_of(cp, va_m, fin)
    vrows_t, vmi_t, vm_t = torch.from_numpy(vrows).to(dev), torch.from_numpy(vmi).to(dev), torch.from_numpy(np.asarray(va_m)).to(dev)
    best, state, bad = float("inf"), None, 0
    for ep in range(MAX_EPOCH):
        beta.train()
        fac.train()
        order = rng.permutation(len(tr_m))
        for i in range(0, len(order), MONTHS_PER_BATCH):
            ms = [tr_m[j] for j in order[i:i + MONTHS_PER_BATCH]]
            rows, mi = rows_of(cp, ms, fin)
            if len(rows) < 2:
                continue
            rows_t, mi_t, ms_t = torch.from_numpy(rows).to(dev), torch.from_numpy(mi).to(dev), torch.from_numpy(np.asarray(ms)).to(dev)
            opt.zero_grad(set_to_none=True)
            loss = torch.mean((forward(beta, fac, Zt, Xt, rows_t, mi_t, ms_t) - rt[rows_t]) ** 2)
            loss = loss + L1 * sum(p.abs().sum() for p in params if p.dim() == 2)
            loss.backward()
            opt.step()
        beta.eval()
        fac.eval()
        with torch.no_grad():
            vl = float(torch.mean((forward(beta, fac, Zt, Xt, vrows_t, vmi_t, vm_t) - rt[vrows_t]) ** 2))
        if np.isfinite(vl) and vl < best - 1e-9:
            best, bad = vl, 0
            state = ({k: v.detach().clone() for k, v in beta.state_dict().items()}, {k: v.detach().clone() for k, v in fac.state_dict().items()})
        else:
            bad += 1
            if bad >= PATIENCE:
                break
    if state is None:
        raise RuntimeError("조건부 오토인코더 학습이 한 번도 유한한 검증 손실을 내지 못했다")
    beta.load_state_dict(state[0])
    fac.load_state_dict(state[1])
    beta.eval()
    fac.eval()
    return beta, fac, best, ep + 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--smoke", action="store_true", help="한 해(2010) · 씨앗 2개 · 최대 20에폭 — 코드 경로 시험용")
    a = ap.parse_args()
    ac.SMOKE["on"] = a.smoke
    global N_SEEDS, MAX_EPOCH
    if a.smoke:
        N_SEEDS, MAX_EPOCH = 2, 20
    import torch
    ac.low_priority()
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    torch.set_num_threads(ac.threads())
    f = ac.Frame()
    store = FeatureStore(f)
    cp = Compact(f)
    out_dir, res_dir = ac.out(ac.smoke_name("latent")), ac.results(ac.smoke_name("stage4_cae"))
    for d in (out_dir, res_dir, ac.out(ac.smoke_name("factors"))):
        os.makedirs(d, exist_ok=True)
    ac.stage_begin("cond_autoencoder", 1, "준비", 0.0, 0.03)
    Z0, names = latent_features(store, cp)
    np.nan_to_num(Z0, copy=False, nan=0.0)
    Zc = np.concatenate([np.ones((cp.n, 1), dtype=np.float32), Z0], axis=1)                # 상수항 + 특성(백색화 · 관리 포트폴리오용)
    names = ["const"] + names
    r = np.asarray(f.fwd(1))[cp.S, cp.J].astype(np.float32)
    fin = np.isfinite(r)
    b, n, A = moments(Zc, r.astype(np.float64), cp)
    Xraw = b / np.maximum(n, 1.0)[:, None]                                                 # 관리 포트폴리오 수익 [달 × 특성]
    Zt = torch.from_numpy(Z0).to(dev)                                                      # 노출 쪽 입력(상수항은 망의 절편이 맡는다)
    rt = torch.from_numpy(np.where(fin, r, 0.0).astype(np.float32)).to(dev)
    fp = "%s|v%d|%d" % (f.meta.get("rawdata_tag"), VERSION, Zc.shape[1])
    sel_years, dec = ac.december_signals(f, BURN_YEARS)
    if a.smoke:
        sel_years = [2010]
    ac.stage_begin("cond_autoencoder", len(sel_years), "재추정", 0.03, 0.9)
    ac.log("장치 %s · 특성 %d개 · 표본 %d칸", dev, Z0.shape[1], cp.n)
    score = np.full(cp.n, np.nan, dtype=np.float32)
    wts = [np.full(cp.n, np.nan, dtype=np.float32) for _ in range(N_PORT)]
    logs, sse_t, sse_p, ss = [], 0.0, 0.0, 0.0
    for u, yy in enumerate(sel_years):
        sY = dec[yy]
        nxt = list(range(sY, min(sY + 12, f.ns)))
        a1, b1 = cp.seg[nxt[0]], cp.seg[nxt[-1] + 1]
        ck = "%s/cae_%d.npz" % (out_dir, yy)
        if os.path.exists(ck) and not a.force:
            z = ac.load_ckpt(ck, fp) or {"fp": ""}              # 읽자마자 닫는다(열어 두면 같은 파일을 다시 쓸 수 없다)
            if str(z["fp"]) == fp:
                score[a1:b1] = z["score"]
                for k in range(N_PORT):
                    wts[k][a1:b1] = z["wts"][k]
                lg = z["log"].item()
                logs.append(lg)
                sse_t, sse_p, ss = sse_t + lg["sse_total"], sse_p + lg["sse_pred"], ss + lg["ss"]
                ac.stage_unit(u + 1, "%d년 — 저장분 사용" % yy)
                continue
        t0 = time.time()
        win = [int(s) for s in np.nonzero((np.arange(f.ns) < sY) & (n > 0))[0]]            # 다음 달 수익이 선택 시점까지 실현된 달
        cut = int(len(win) * (1 - VAL_FRAC))
        tr_m, va_m = win[:cut], win[cut:]
        T, C = whiten(A, n, np.asarray(win))                                               # 백색화 변환(그때까지의 달만으로)
        Xw = Xraw @ T                                                                      # 백색화한 관리 포트폴리오 수익 [달 × 성분]
        Xt = torch.from_numpy(Xw.astype(np.float32)).to(dev)
        win_t = torch.tensor(win, device=dev)
        val = {}
        for K in K_GRID:                                                                   # 팩터 수 고르기(검증 손실)
            val[K] = train(Zt, rt, Xt, cp, fin, tr_m, va_m, K, SEED0, dev)[2]
        K = min(K_GRID, key=lambda k: val[k])
        vrows = rows_of(cp, va_m, fin)[0]
        val_r2 = 1.0 - val[K] / float((r[vrows].astype(np.float64) ** 2).mean())          # 검증 구간에서 그 달 팩터 수익으로 설명되는 비율(0 이하면 학습이 무너진 것)
        sc = np.zeros(b1 - a1, dtype=np.float64)
        st, sp, s2, eps, Wn = 0.0, 0.0, 0.0, [], []
        for k in range(N_SEEDS):
            beta, fac, _, ep = train(Zt, rt, Xt, cp, fin, tr_m, va_m, K, SEED0 + 1 + k, dev)
            eps.append(ep)
            with torch.no_grad():
                Wf = fac.weight.detach()                                                   # [K × 성분]
                Ftr = Xt[win_t] @ Wf.T                                                     # 학습 창의 팩터 수익 [달 × K]
                lam = Ftr.mean(0)
                sc += (beta(Zt[a1:b1]) @ lam).double().cpu().numpy() / N_SEEDS
                Wn.append((Wf / Ftr.std(0).clamp_min(1e-12)[:, None]).double().cpu().numpy())   # 학습 창 팩터 수익의 표준편차 1 로 맞춘 가중
                for s in nxt:                                                              # 모형 설명력(표본 밖 달) — 씨앗별 값의 평균
                    if n[s] <= 0:
                        continue
                    lo, hi = cp.seg[s], cp.seg[s + 1]
                    kf = torch.from_numpy(fin[lo:hi]).to(dev)
                    Bs, rs = beta(Zt[lo:hi])[kf], rt[lo:hi][kf]
                    st += float(((rs - Bs @ (Xt[s] @ Wf.T)) ** 2).sum()) / N_SEEDS
                    sp += float(((rs - Bs @ lam) ** 2).sum()) / N_SEEDS
                    s2 += float((rs ** 2).sum()) / N_SEEDS
            del beta, fac
        # 합의 팩터: 씨앗 10개의 팩터(각 K개)를 모두 쌓아 학습 창 수익의 주성분을 뽑는다 — 씨앗마다 다른 회전을 하나로 모은다
        Wall = np.concatenate(Wn, axis=0)                                                  # [씨앗·K × 성분]
        Fall = Xw[win] @ Wall.T                                                            # [달 × 씨앗·K]
        sv, Vt = np.linalg.svd(Fall - Fall.mean(0), full_matrices=False)[1:]
        npf = min(N_PORT, K)
        Wc = Vt[:npf] @ Wall                                                               # 합의 팩터의 가중 [npf × 성분]
        Wc /= np.linalg.norm(Wc, axis=1, keepdims=True)                                    # 길이 1 → 노출의 합동 2차 적률 1(PCA 계열과 같은 척도)
        Wc *= np.where((Xw[win] @ Wc.T).mean(0) >= 0, 1.0, -1.0)[:, None]                  # 부호 = 학습 창 평균 수익이 양수
        share = float((sv[:K] ** 2).sum() / (sv ** 2).sum())                               # 씨앗들의 팩터 공간이 얼마나 겹치나(앞 K개 주성분의 설명 비율 · 1 이면 같은 공간)
        Gf = T @ Wc.T                                                                      # 원래 특성 공간의 가중 [특성 × npf]
        wz = np.full((N_PORT, b1 - a1), np.nan, dtype=np.float32)
        Bx = Zc[a1:b1].astype(np.float64) @ Gf                                             # 합의 팩터의 노출 [행 × npf]
        for s in nxt:                                                                      # 종목 비중 = 노출 ÷ 그 달 종목 수(특성 가중 포트폴리오)
            lo, hi = cp.seg[s] - a1, cp.seg[s + 1] - a1
            if hi - lo >= 30:
                wz[:npf, lo:hi] = (Bx[lo:hi].T / (hi - lo)).astype(np.float32)
        score[a1:b1] = sc
        for j in range(N_PORT):
            wts[j][a1:b1] = wz[j]
        R = structure(Gf, C)
        top = {"F%d" % (j + 1): [(names[i], round(float(R[i, j]), 3)) for i in np.argsort(-np.abs(R[1:, j]))[:12] + 1] for j in range(npf)}
        lg = {"year": yy, "K": int(K), "M": int(T.shape[1]), "months": int(len(win)), "val_loss_by_K": {int(k): float(v) for k, v in val.items()}, "val_r2": round(val_r2, 5),
              "epochs": eps, "seed_space_share": round(share, 4), "const_corr": [round(float(x), 3) for x in R[0]], "loadings_top": top,
              "sse_total": st, "sse_pred": sp, "ss": s2, "seconds": round(time.time() - t0, 1),
              "vram_peak_gb": round(torch.cuda.max_memory_allocated() / 2 ** 30, 2) if dev == "cuda" else 0.0}

        def _save(path, sc=sc, wz=wz, lg=lg):
            with open(path, "wb") as fh:
                np.savez(fh, fp=fp, score=sc.astype(np.float32), wts=wz, log=np.array(lg, dtype=object))
        ac.write_atomic(ck, _save)
        logs.append(lg)
        sse_t, sse_p, ss = sse_t + st, sse_p + sp, ss + s2
        del Xt
        torch.cuda.empty_cache()
        ac.log("%d년 — K %d · 성분 %d · 검증 R² %.3f · 씨앗 공간 겹침 %.2f · 에폭 %s · %.0f초", yy, K, T.shape[1], val_r2, share, eps, time.time() - t0)
        ac.stage_unit(u + 1, "%d년 재추정 끝" % yy)
    S = np.full((f.ns, f.nt), np.nan, dtype=np.float32)
    S[cp.S, cp.J] = score
    p = ac.out(ac.smoke_name("factors")) + "/LAT_CAE.parquet"
    ac.save_factor_panel(p, "LAT_CAE", S, f)
    manifest = [{"id": "LAT_CAE", "path": p, "direction": 1, "kind": "score", "method": "잠재팩터 · 조건부 오토인코더", "desc": "종목 기대수익 점수 = 신경망이 낸 잠재팩터 노출 × 학습 창의 팩터 평균 수익"}]
    for j in range(N_PORT):
        Wm = np.full((f.ns, f.nt), np.nan, dtype=np.float32)
        Wm[cp.S, cp.J] = wts[j]
        nm = "LAT_CAE_F%d" % (j + 1)
        pw = out_dir + "/%s.parquet" % nm
        ac.save_factor_panel(pw, nm, Wm, f)
        manifest.append({"id": nm, "path": pw, "direction": 1, "kind": "weights", "method": "잠재팩터 · 조건부 오토인코더",
                         "desc": "%d번째 합의 팩터의 종목 비중 — 특성 가중 포트폴리오(노출 ÷ 종목 수) · 노출 1 단위당 수익" % (j + 1)})
    r2 = {"total_r2": round(1 - sse_t / ss, 5) if ss > 0 else None, "pred_r2": round(1 - sse_p / ss, 6) if ss > 0 else None}
    ac.write_json({"model": "cae", "r2_oos": r2, "r2_note": "씨앗별 값의 평균(씨앗 평균 예측의 값이 아니다)", "retrains": logs}, res_dir + "/model_log_cae.json")
    ac.write_json({"at": ac._now(), "stage": "cond_autoencoder", "factors": manifest,
                   "params": {"HIDDEN": HIDDEN, "K_GRID": K_GRID, "N_SEEDS": N_SEEDS, "LR": LR, "L1": L1, "MONTHS_PER_BATCH": MONTHS_PER_BATCH, "MAX_EPOCH": MAX_EPOCH,
                              "PATIENCE": PATIENCE, "_source": PARAM_SRC}}, ac.out(ac.smoke_name("manifest_cae") + ".json"))
    ac.log("끝 — 표본 밖 전체 R² %s · 예측 R² %s", r2["total_r2"], r2["pred_r2"])
    ac.stage_end(done=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
