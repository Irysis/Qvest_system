"""aif_features.py — 특성 저장소(월말 신호 × 종목 × 특성). 생성기와 잠재 모형이 함께 읽는다.

묶음(block) 하나 = 파일 둘:
  <묶음>.f32   원값 [신호 × 종목 × 특성] float32(결측 = NaN) — 신호일까지의 자료로만 만든 값
  <묶음>.json  특성 이름 · 설명 · 원천 · 가용 규칙 · 채움 비율
순위 판 <묶음>.rank.f32 = 그 달 유니버스 멤버 안 횡단면 순위 (−1, 1)(멤버가 아니면 NaN) — 달마다 따로 계산한다(다른 달 무접촉).
기존 팩터 묶음(existing)은 R 접근자가 이미 멤버 안 순위로 내보낸 값이라 순위 판만 있다.
"""
import glob
import os

import numpy as np

import aif_common as ac


class FeatureStore:
    def __init__(self, frame=None, path=None):
        self.frame = frame or ac.Frame()
        self.dir = path or ac.out("features")
        os.makedirs(self.dir, exist_ok=True)

    # ── 쓰기 ──
    def create(self, block, names, kind="raw"):
        """빈 memmap 을 만들어 돌려준다(쓰는 쪽이 채운 뒤 commit 을 부른다). kind = raw | rank."""
        f = self.frame
        p = self._file(block, kind) + ".tmp"
        mm = np.lib.format.open_memmap(p, mode="w+", dtype="<f4", shape=(f.ns, f.nt, len(names)))
        mm[:] = np.nan
        return mm

    def commit(self, block, mm, names, meta, kind="raw"):
        mm.flush()
        mm._mmap.close()                                  # 윈도에서는 열려 있는 파일의 이름을 바꿀 수 없다 — 매핑을 닫고 확정한다(이 뒤로 mm 을 쓰지 않는다)
        os.replace(self._file(block, kind) + ".tmp", self._file(block, kind))
        info = ac.read_json(self._meta(block), {}) or {}
        info.update({"block": block, "names": list(names), "n_features": len(names), "built_at": ac._now()})
        info.setdefault("kinds", [])
        if kind not in info["kinds"]:
            info["kinds"].append(kind)
        info.update(meta or {})
        ac.write_json(info, self._meta(block))

    def build_rank(self, block, chunk=24):
        """원값 → 그 달 멤버 안 순위. 특성마다 · 달마다 따로(횡단면 통계만 쓴다)."""
        f = self.frame
        raw, names = self.open(block, "raw")
        mm = self.create(block, names, "rank")
        for k in range(len(names)):
            mm[:, :, k] = ac.rank_pm1(np.asarray(raw[:, :, k]), f.mem)
        fill = [float(np.isfinite(mm[:, :, k])[f.mem].mean()) for k in range(len(names))]
        self.commit(block, mm, names, {"fill_members": dict(zip(names, [round(x, 4) for x in fill]))}, "rank")

    # ── 읽기 ──
    def open(self, block, kind="rank"):
        info = ac.read_json(self._meta(block))
        if not info or kind not in info.get("kinds", []):
            raise RuntimeError("[aif] 특성 묶음이 없다: %s(%s)" % (block, kind))
        return np.load(self._file(block, kind), mmap_mode="r"), info["names"]

    def info(self, block):
        return ac.read_json(self._meta(block))

    def blocks(self):
        return sorted(os.path.basename(p)[:-5] for p in glob.glob(self.dir + "/*.json"))

    def _file(self, block, kind):
        return "%s/%s.%s.npy" % (self.dir, block, "rank" if kind == "rank" else "raw")

    def _meta(self, block):
        return "%s/%s.json" % (self.dir, block)


def assemble_existing(store, log=ac.log):
    """R 이 달마다 내보낸 기존 팩터(결합용 뷰 · 등록부 방향 · 멤버 안 순위)를 한 묶음으로 모은다."""
    import pyarrow.parquet as pq
    f = store.frame
    files = sorted(glob.glob(f.path + "/fc/fc_*.parquet"))
    if not files:
        raise RuntimeError("[aif] 기존 팩터 내보내기가 없다 — run/03_export_frame.R")
    names, seen = [], set()
    for p in files:                                      # 1차: 이름의 합집합(처음 나온 순서)
        for c in pq.read_schema(p).names:
            if c != "Ticker" and c not in seen:
                seen.add(c)
                names.append(c)
    col = {c: k for k, c in enumerate(names)}
    ym = {str(d)[:7].replace("-", ""): s for s, d in enumerate(f.sig_dates)}
    mm = store.create("existing", names, "rank")
    n_used = 0
    for p in files:                                      # 2차: 달마다 채운다
        s = ym.get(os.path.basename(p)[3:9])
        if s is None:
            continue
        t = pq.read_table(p)
        ti = f.ticker_index(t.column("Ticker").to_pylist())
        ok = ti >= 0
        for c in t.column_names:
            if c == "Ticker":
                continue
            v = t.column(c).to_numpy(zero_copy_only=False).astype(np.float32)
            mm[s, ti[ok], col[c]] = v[ok]
        n_used += 1
    fill = [float(np.isfinite(mm[:, :, k])[f.mem].mean()) for k in range(len(names))]
    store.commit("existing", mm, names, {"source": "기존 팩터 DB 결합용 뷰(fc_load_month · direction = registry · 멤버 안 순위 · 별칭 접힘)",
                                         "asof": "월말 신호일 값(접근자가 그 달 기준일을 확인)", "months": n_used,
                                         "fill_members": dict(zip(names, [round(x, 4) for x in fill]))}, "rank")
    log("기존 팩터 묶음 — 특성 %d개 · 달 %d · 멤버 채움 중앙값 %.2f", len(names), n_used, float(np.median(fill)))
    return names
