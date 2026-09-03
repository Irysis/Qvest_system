#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rf_cycle_time.py — 무인 리서치 **사이클 시간 실측** (도훈 지시 2026-08-30)

추정이 아니라 .cache/reinforce_auto_log.jsonl 의 타임스탬프에서 재도출한다.
단계별 소요 + 전체 사이클(충실구현 → 강화 20칸 → 이월) 추정을 낸다.
"""
import io, json, os, sys, datetime, collections

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
LOG = os.path.join(ROOT, ".cache", "reinforce_auto_log.jsonl")


def ts(s):
    try:
        return datetime.datetime.strptime(str(s)[:19], "%Y-%m-%dT%H:%M:%S")
    except Exception:
        return None


def main():
    if not os.path.exists(LOG):
        print("로그 없음"); return 0
    ev = []
    for line in io.open(LOG, encoding="utf-8"):
        try:
            o = json.loads(line)
        except Exception:
            continue
        t = ts(o.get("ts"))
        if t:
            ev.append((t, o.get("src") or "", o.get("event") or "", o))
    ev.sort(key=lambda x: x[0])
    if not ev:
        print("이벤트 없음"); return 0

    # ── 단계별 소요 (쌍으로 재는 것만) ────────────────────────────────────────
    pairs = [
        ("충실구현 LLM",      "replication_auto",   "start",          "agent_done"),
        ("충실구현 검증+측정", "replication_verify", "installing_packages", "verified"),
        ("강화 셀 1칸",       "",                   "cell_start",     "cell_done"),
        ("병렬 배치",         "parallel",           "batch_start",    "batch_done"),
    ]
    print("=== 단계별 실측 (분) ===")
    rows = []
    for name, src, a, b in pairs:
        durs, open_t = [], None
        for t, s, e, o in ev:
            if src and s != src:
                continue
            if e == a:
                open_t = t
            elif e == b and open_t:
                durs.append((t - open_t).total_seconds() / 60.0)
                open_t = None
        if durs:
            durs.sort()
            med = durs[len(durs) // 2]
            print("  %-16s n=%-3d 중앙 %5.1f분  (최소 %.1f · 최대 %.1f)"
                  % (name, len(durs), med, durs[0], durs[-1]))
            rows.append((name, med, len(durs)))
        else:
            print("  %-16s 측정 없음" % name)

    # ── 전체 사이클 추정 ──────────────────────────────────────────────────────
    d = dict((r[0], r[1]) for r in rows)
    llm = d.get("충실구현 LLM")
    cell = d.get("강화 셀 1칸")
    batch = d.get("병렬 배치")
    try:
        cfg = json.load(io.open(os.path.join(ROOT, "06_Registry", "reinforce_auto_config.json"),
                                encoding="utf-8"))
        npar = int(cfg.get("parallel_cells") or 5)
    except Exception:
        npar = 5
    prog_n = 20
    print()
    print("=== 전체 사이클 추정 (논문 1편 = 충실구현 + 강화 %d칸) ===" % prog_n)
    if batch:
        blocks = (prog_n + npar - 1) // npar
        rf = batch * blocks
        print("  강화: 병렬배치 %.1f분 × %d블록(칸 %d÷%d) = %.0f분" % (batch, blocks, prog_n, npar, rf))
    elif cell:
        rf = cell * prog_n / max(1, npar)
        print("  강화: 셀 %.1f분 × %d칸 ÷ 병렬 %d = %.0f분 (배치 실측 없어 셀에서 환산)"
              % (cell, prog_n, npar, rf))
    else:
        rf = None
        print("  강화: 측정 없음")
    if llm and rf:
        print("  충실구현: %.0f분" % llm)
        print("  ── 합계 약 %.0f분 (%.1f시간)" % (llm + rf, (llm + rf) / 60.0))
        print()
        print("  ※ 스케줄러 tick 간격 8분이 대기로 더해질 수 있다(칸당 최대 +8분).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
