"""aif_terminals.py — 단계 2 뒷부분: 단말 묶음을 차례로 만들어 특성 저장소에 넣는다(묶음 하나 = 체크포인트 하나).

하는 일
  1. 묶음마다(price · flow · macro · cat · val · cons · fund) 원값 [신호 × 종목 × 특성] 저장 → 그 달 멤버 안 순위 판 저장
  2. 기존 팩터 묶음(existing) — R 접근자가 내보낸 달별 파일을 모은다
  3. 시장 · 거시 상태 변수(macro_state) · 업종 코드(sector) 저장
  4. 미래 행 잘라내기 자가 시험 — 원천을 날짜 d 뒤에서 잘라 다시 만든 값이 d 의 값과 같아야 한다(묶음 전부 · 신호일 2개)
실행: python py/aif_terminals.py [--only price,flow] [--force] [--no-selftest]
다시 띄우면 끝난 묶음은 건너뛴다(원자료 판이나 이 코드의 판 번호가 바뀌면 다시 만든다).
"""
import argparse
import sys
import time

import numpy as np

import aif_blocks as ab
import aif_common as ac
import aif_daily as ad
from aif_features import FeatureStore, assemble_existing

VERSION = 2            # 묶음 정의가 바뀌면 올린다(체크포인트 무효화). 2 = 유동시총을 원자료에서 직접 계산 · 회전율과 수급 강도의 분모를 시가총액으로
PART = (0.30, 1.0)     # 이 실행이 맡는 단계 진행 구간(앞 0.30 = R 의 틀 내보내기)


def fingerprint(frame):
    return "%s|v%d" % (frame.meta.get("rawdata_tag"), VERSION)


def done(store, block, fp):
    info = store.info(block)
    return bool(info) and info.get("fp") == fp and set(info.get("kinds", [])) >= {"raw", "rank"}


def run_block(store, ctx, block, fp):
    t0 = time.time()
    g, _ = ctx.price()
    names, X, meta = ab.BLOCKS[block](ctx)
    sector = meta.pop("_sector", None)
    full = ad.to_signals(store.frame, g.sig_sel, X)
    del X
    mm = store.create(block, names, "raw")
    mm[:] = full
    fill = [float(np.isfinite(full[:, :, k])[store.frame.mem].mean()) for k in range(len(names))]
    del full
    meta.update({"fp": fp, "seconds": round(time.time() - t0, 1), "fill_members_raw": dict(zip(names, [round(x, 4) for x in fill]))})
    store.commit(block, mm, names, meta, "raw")
    store.build_rank(block)
    if sector is not None:
        code, sec_names = sector
        np.save(store.frame.path + "/sector.npy", ad.to_signals(store.frame, g.sig_sel, code.astype(np.float32)).astype(np.float32))
        ac.write_json({"names": sec_names, "missing": -1, "note": "신호일의 업종 코드(RAWDATA Sector) [신호 × 종목] · NaN = 행 없음"}, store.frame.path + "/sector.json")
    ac.log("%s — 특성 %d개 · 멤버 채움 중앙값 %.2f · %.0f초", block, len(names), float(np.median(fill)), time.time() - t0)
    return len(names), float(np.median(fill))


def selftest(store, blocks, n_cuts=2):
    """미래 행 잘라내기 불변성 — 신호일 d 의 값은 d 뒤의 원천 행이 있든 없든 같아야 한다."""
    f = store.frame
    picks = [f.ns // 3, (2 * f.ns) // 3][:n_cuts]
    res = {"dates": [], "blocks": {}, "pass": True}
    for s in picks:
        cut = f.sig_dates[s]
        ctx = ab.Ctx(f, cut=cut)
        g, _ = ctx.price()
        if g.sig_sel[-1] != s:
            raise RuntimeError("[aif] 자른 문맥의 마지막 신호가 기대와 다르다")
        res["dates"].append(str(cut))
        for b in blocks:
            names, X, meta = ab.BLOCKS[b](ctx)
            meta.pop("_sector", None)
            a = X[-1]
            full, fn = store.open(b, "raw")
            if list(fn) != list(names):
                raise RuntimeError("[aif] 자른 문맥의 특성 이름이 다르다: " + b)
            ref = np.asarray(full[s])
            same = np.array_equal(a, ref, equal_nan=True)
            bad = 0 if same else int((~((a == ref) | (np.isnan(a) & np.isnan(ref)))).sum())
            mx = 0.0 if same else float(np.nanmax(np.abs(np.where(np.isfinite(a) & np.isfinite(ref), a - ref, 0.0))))
            only = 0 if same else int((np.isnan(a) != np.isnan(ref)).sum())
            r = res["blocks"].setdefault(b, {"cells_checked": 0, "cells_differ": 0, "max_abs_diff": 0.0, "nan_mismatch": 0})
            r["cells_checked"] += int(a.size)
            r["cells_differ"] += bad
            r["nan_mismatch"] += only
            r["max_abs_diff"] = max(r["max_abs_diff"], mx)
            if bad:
                res["pass"] = False
            ac.log("자가 시험 %s · %s — %s(다른 칸 %d · 결측 불일치 %d · 최대 차 %.3g)", str(cut), b, "통과" if not bad else "실패", bad, only, mx)
            del X, a, ref
        del ctx, g
    ac.write_json(res, ac.results("selftest_terminals.json"))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--no-selftest", action="store_true")
    a = ap.parse_args()
    ac.low_priority()
    frame = ac.Frame()
    store = FeatureStore(frame)
    fp = fingerprint(frame)
    blocks = [b for b in ab.ORDER if not a.only or b in a.only.split(",")]
    total = len(blocks) + 3
    ac.stage_begin("terminals", total, "묶음", PART[0], PART[1])
    ctx = ab.Ctx(frame)
    counts, k = {}, 0
    for b in blocks:
        if done(store, b, fp) and not a.force:
            info = store.info(b)
            counts[b] = (info["n_features"], float(np.median(list(info.get("fill_members_raw", {0: 0}).values()))))
            ac.log("%s — 이미 만듦(건너뜀)", b)
        else:
            ac.status_set(detail="%s 묶음 만드는 중" % b)
            counts[b] = run_block(store, ctx, b, fp)
        k += 1
        ac.stage_unit(k, "%s 묶음 끝" % b)
    # 기존 팩터 묶음
    info = store.info("existing")
    if info and info.get("fp") == fp and not a.force:
        ac.log("existing — 이미 만듦(건너뜀)")
        n_ex = info["n_features"]
    else:
        n_ex = len(assemble_existing(store))
        info = store.info("existing")
        info["fp"] = fp
        ac.write_json(info, store._meta("existing"))
    k += 1
    ac.stage_unit(k, "기존 팩터 묶음 끝")
    # 시장 · 거시 상태 변수
    g, _ = ctx.price()
    zn, Z = ab.macro_state(ctx)
    np.save(store.dir + "/macro_state.npy", ad.to_signals(frame, g.sig_sel, Z))
    ac.write_json({"names": zn, "shape": [frame.ns, len(zn)], "note": "월말 시점의 시장 · 거시 상태(모든 종목에 같은 값) · 가용 시점 규칙 적용", "fp": fp}, store.dir + "/macro_state_meta.json")
    k += 1
    ac.stage_unit(k, "시장 · 거시 상태 변수 끝")
    del ctx
    st = {"pass": None}
    if not a.no_selftest:
        ac.status_set(detail="미래 행 잘라내기 자가 시험")
        st = selftest(store, [b for b in blocks])
    n_new = sum(v[0] for v in counts.values())
    lines = ["원자료 묶음 %d개 · 특성 %d개 + 기존 팩터 %d개 + 시장 · 거시 상태 변수 %d개" % (len(counts), n_new, n_ex, len(zn)),
             " · ".join("%s %d개(채움 %.0f%%)" % (b, n, 100 * fl) for b, (n, fl) in counts.items()),
             "미래 행 잘라내기 자가 시험: %s" % ("통과(신호일 %s)" % " · ".join(st.get("dates", [])) if st["pass"] else ("실패 — 확인 필요" if st["pass"] is False else "생략"))]
    ac.write_json({"at": ac._now(), "title": "전 자료 단말 계층 — 기본 특성 집합", "lines": lines, "charts": [], "chart_names": []}, ac.out("stage_summary_terminals.json"))
    for ln in lines:
        ac.log(ln)
    if st["pass"] is False:
        ac.status_set(stage_state="error", error="미래 행 잘라내기 자가 시험 실패 — results/selftest_terminals.json")
        return 4
    ac.stage_end(done=not a.only and not a.no_selftest)      # 일부 묶음만 돌렸거나 자가 시험을 건너뛴 실행은 단계를 끝난 것으로 적지 않는다
    return 0


if __name__ == "__main__":
    sys.exit(main())
