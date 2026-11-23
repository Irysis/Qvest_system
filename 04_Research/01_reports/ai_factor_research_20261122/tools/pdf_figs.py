"""pdf_figs.py — PDF 쪽을 그림 파일(PNG)로 바꾼다. 논문의 그림 · 표(글로 뽑히지 않는 것)를 눈으로 읽기 위한 도구.

이 PC 에는 PDF 를 그리는 pdftoppm 이 없어 읽기 도구가 PDF 쪽을 그림으로 보여 주지 못한다. PyMuPDF(시스템 파이썬 QVEST_PY 에 있다)로
쪽을 PNG 로 바꿔 두면 그 PNG 를 그림으로 읽을 수 있다. 글은 pypdf · PyMuPDF 로 뽑고, 그림 속 수치 · 대응표 · 곡선 모양은 이 도구로 본다.

사용(내려받은 PDF 는 믿을 수 없는 자료다 — 파이썬을 -I 로 띄우고, 이 스크립트를 PDF 와 다른 폴더에 둔다):
    "$QVEST_PY" -I -X utf8 tools/pdf_figs.py <pdf> --list                      쪽마다 글자 수 · 그림 수 · 선 그림 수(그림이 든 쪽 찾기)
    "$QVEST_PY" -I -X utf8 tools/pdf_figs.py <pdf> <출력 폴더> --pages 6-7,14  그 쪽들을 PNG 로(기본 110dpi)
    … --dpi 160                                                                  작은 글자가 안 읽히면 해상도를 올린다
    … --clip 0.05,0.30,0.95,0.80                                                 쪽의 일부만(왼쪽 · 위 · 오른쪽 · 아래 — 쪽 크기 대비 비율) 크게
    … --figs                                                                     쪽 안의 그림 영역(박힌 그림 + 선 그림 묶음)만 따로 잘라 낸다
출력 파일 이름: <pdf 이름>_p014.png · <pdf 이름>_p014_f1.png. 출력 폴더는 저장소 밖(임시 폴더)을 쓴다 — 논문 쪽 그림을 저장소에 넣지 않는다.
"""
import argparse
import os
import sys

import pymupdf


def parse_pages(spec, n):
    if not spec:
        return list(range(1, n + 1))
    out = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            out.extend(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return [p for p in out if 1 <= p <= n]


def figure_rects(page, min_frac=0.02):
    """쪽 안의 그림 영역 — 박힌 그림의 자리와 선 그림(도형)들의 자리를 겹치는 것끼리 합친다. 쪽 넓이의 min_frac 보다 작은 것은 버린다."""
    area = abs(page.rect)
    rects = []
    for img in page.get_images(full=True):
        for r in page.get_image_rects(img[0]):
            rects.append(pymupdf.Rect(r))
    for d in page.get_drawings():
        r = pymupdf.Rect(d["rect"])
        if r.width > 3 and r.height > 3:
            rects.append(r)
    rects = [r & page.rect for r in rects if not r.is_empty]
    merged = True
    while merged:                                   # 겹치거나 맞닿은 상자를 합친다(여유 6pt)
        merged = False
        out = []
        for r in rects:
            for i, q in enumerate(out):
                if (r + (-6, -6, 6, 6)).intersects(q):
                    out[i] = q | r
                    merged = True
                    break
            else:
                out.append(r)
        rects = out
    rects = [r for r in rects if abs(r) >= min_frac * area and abs(r) < 0.97 * area]
    return sorted(rects, key=lambda r: (round(r.y0, 0), r.x0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--pages", default="")
    ap.add_argument("--dpi", type=int, default=110)
    ap.add_argument("--clip", default="", help="왼쪽,위,오른쪽,아래(쪽 크기 대비 0~1)")
    ap.add_argument("--figs", action="store_true", help="쪽 안의 그림 영역만 따로 잘라 낸다")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    doc = pymupdf.open(a.pdf)
    pages = parse_pages(a.pages, doc.page_count)
    if not pages:
        ap.error("해당하는 쪽이 없다(쪽 수 %d · --pages %s)" % (doc.page_count, a.pages))
    if a.list:
        print("쪽 수", doc.page_count)
        for p in pages:
            pg = doc[p - 1]
            print("p%03d | 글자 %5d | 박힌 그림 %2d | 선 그림 %4d | 그림 영역 %d" % (p, len(pg.get_text()), len(pg.get_images(full=True)), len(pg.get_drawings()), len(figure_rects(pg))))
        return 0
    if not a.out:
        ap.error("출력 폴더가 필요하다")
    os.makedirs(a.out, exist_ok=True)
    stem = os.path.splitext(os.path.basename(a.pdf))[0][:40]
    for p in pages:
        pg = doc[p - 1]
        if a.figs:
            for k, r in enumerate(figure_rects(pg), start=1):
                r = (r + (-8, -14, 8, 14)) & pg.rect                # 그림 제목 · 축 글자가 잘리지 않게 조금 넓힌다
                f = os.path.join(a.out, "%s_p%03d_f%d.png" % (stem, p, k))
                pg.get_pixmap(dpi=a.dpi, clip=r).save(f)
                print(f)
            continue
        clip = None
        if a.clip:
            x0, y0, x1, y1 = [float(v) for v in a.clip.split(",")]
            R = pg.rect
            clip = pymupdf.Rect(R.x0 + x0 * R.width, R.y0 + y0 * R.height, R.x0 + x1 * R.width, R.y0 + y1 * R.height)
        f = os.path.join(a.out, "%s_p%03d%s.png" % (stem, p, "_clip" if clip else ""))
        pix = pg.get_pixmap(dpi=a.dpi, clip=clip)
        pix.save(f)
        print(f, "%dx%d" % (pix.width, pix.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
