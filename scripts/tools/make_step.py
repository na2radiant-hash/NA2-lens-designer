#!/usr/bin/env python3
"""make_step.py - solid of revolution (STEP AP214, mm) from one element's meridional profile.

Called by scripts/lib/export/export_step.m (config key export.step), or by hand:

    python scripts/tools/make_step.py geometry/step/element1_profile.csv --out geometry/step \
           --name element1 [--cut -1.30] [--stl] [--check]

Input CSV (written by export_step.m, millimetres, header 'segment,x_mm,r_mm'):
    x_mm = position along the optical axis (focus at 0), r_mm = radius.
    Consecutive rows with the same 'segment' label form one piece of the outline, in
    order around the closed upper-half cross-section:
        S1 [S1_FILLET] CAP [S2_FILLET] S2        (S1 = inner surface, S2 = outer surface)
    Segments whose label starts with 'S' become interpolating B-splines through the
    points (G1 across a fillet join, radial tangent where a surface meets the axis);
    CAP becomes a straight line; the outline is closed along the axis (r = 0).
    A segment is reversed automatically when its last point, not its first, continues
    the previous segment (export_step.m writes S2 vertex -> tip like the .mat files).

Output (in --out):
    <name>.step               the element as ONE closed solid; optical axis = +Z, focus at origin
    <name>_front.step / _back.step   (with --cut z0) the two pieces either side of the plane z = z0
    <name>.stl                (with --stl) tessellation for quick viewing
    <name>_step_check.txt     (with --check) validity, volume vs. the polyline (Pappus), envelope,
                              spline-vs-polyline deviation, re-import test, STL watertightness

Exit code 0 = STEP written (check lines may still say FAIL - read the check file); 1 = error.
Requires: cadquery >= 2.4  (pip install cadquery)   optional: trimesh (STL watertightness)
"""
import argparse
import csv
import math
import os
import sys
import time


def read_profile(path):
    """-> list of (label, [(x, r), ...]) in file order."""
    segs = []
    with open(path, newline="") as f:
        rd = csv.reader(f)
        header = next(rd)
        if [h.strip().lower() for h in header[:3]] != ["segment", "x_mm", "r_mm"]:
            raise ValueError(f"{path}: expected header 'segment,x_mm,r_mm', got {header}")
        for row in rd:
            if not row or row[0].startswith("#"):
                continue
            lab, x, r = row[0].strip(), float(row[1]), float(row[2])
            if segs and segs[-1][0] == lab:
                segs[-1][1].append((x, r))
            else:
                segs.append((lab, [(x, r)]))
    if not segs:
        raise ValueError(f"{path}: no points")
    return segs


def polyline_outline(segs):
    """Closed polyline (x, r) of the outline as written (segments chained, S2 reversed if needed)."""
    pts = []
    for lab, p in order_segments(segs):
        if pts and dist(pts[-1], p[0]) < 1e-9:
            pts.extend(p[1:])
        else:
            pts.extend(p)
    if dist(pts[0], pts[-1]) > 1e-9:
        pts.append(pts[0])
    return pts


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def order_segments(segs, tol=1e-6):
    """Chain the segments head-to-tail, reversing any that is written the other way."""
    out = [(segs[0][0], list(segs[0][1]))]
    for lab, p in segs[1:]:
        end = out[-1][1][-1]
        if dist(end, p[0]) <= tol:
            out.append((lab, list(p)))
        elif dist(end, p[-1]) <= tol:
            out.append((lab, list(reversed(p))))
        else:
            raise ValueError(f"segment {lab} does not continue the outline "
                             f"(previous end {end}, this starts {p[0]} / ends {p[-1]})")
    return out


def pappus_volume(poly):
    """Volume of the solid of revolution of a closed (x, r) polygon about the x axis:
    V = 2*pi * integral of r dA = 2*pi * |first moment about the axis|."""
    m = 0.0
    for (x0, r0), (x1, r1) in zip(poly[:-1], poly[1:]):
        m += (x0 * r1 - x1 * r0) * (r0 + r1)
    return 2.0 * math.pi * abs(m) / 6.0


def dist_point_polyline(p, poly):
    best = float("inf")
    px, py = p
    for (x0, y0), (x1, y1) in zip(poly[:-1], poly[1:]):
        dx, dy = x1 - x0, y1 - y0
        L2 = dx * dx + dy * dy
        t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - x0) * dx + (py - y0) * dy) / L2))
        d = math.hypot(px - (x0 + t * dx), py - (y0 + t * dy))
        if d < best:
            best = d
    return best


def build(segs, name):
    import cadquery as cq
    from cadquery import Vector

    ordered = order_segments(segs)
    # (x, r) -> global (X = r, Y = 0, Z = x): optical axis = Z
    def V(p):
        x, r = p
        if abs(r) < 1e-9:
            r = 0.0                      # exactly on the axis: keeps the revolve closed
        return Vector(r, 0.0, x)

    edges = []
    dev_samples = []                     # (segment label, list of sampled 3D points) for the deviation check
    prev_tangent = None
    for k, (lab, p) in enumerate(ordered):
        if len(p) < 2:
            raise ValueError(f"segment {lab} has fewer than 2 points")
        if lab.upper().startswith("S"):
            pts = [V(q) for q in p]
            # end tangents: continue the previous spline across a fillet join, radial on the axis,
            # otherwise the chord of the first / last polyline segment
            t0 = (pts[1] - pts[0]).normalized()
            t1 = (pts[-1] - pts[-2]).normalized()
            if abs(p[0][1]) < 1e-9:
                t0 = Vector(1, 0, 0)                     # leaving the axis, radially outward
            if abs(p[-1][1]) < 1e-9:
                t1 = Vector(-1, 0, 0)                    # arriving at the axis, radially inward
            if prev_tangent is not None and lab.upper().endswith("FILLET"):
                t0 = prev_tangent
            if len(pts) == 2:
                e = cq.Edge.makeLine(pts[0], pts[1])
            else:
                e = cq.Edge.makeSpline(pts, tangents=(t0, t1), scale=True)
            prev_tangent = t1
            edges.append(e)
            dev_samples.append((lab, e, p))
        else:                                            # CAP or any straight piece
            a, b = V(p[0]), V(p[-1])
            if (b - a).Length < 1e-9:
                prev_tangent = None
                continue                                 # zero-length cap (pointy tip): nothing to add
            edges.append(cq.Edge.makeLine(a, b))
            prev_tangent = None
    first, last = ordered[0][1][0], ordered[-1][1][-1]
    if dist(first, last) > 1e-9:
        if abs(first[1]) > 1e-6 or abs(last[1]) > 1e-6:
            raise ValueError("outline is open and its ends are not on the axis; cannot close along r = 0")
        edges.append(cq.Edge.makeLine(V(last), V(first)))   # close along the optical axis

    wire = cq.Wire.assembleEdges(edges)
    if not wire.IsClosed():
        raise ValueError("profile wire is not closed")
    face = cq.Face.makeFromWires(wire)
    solid = cq.Solid.revolve(wire, [], 360.0, Vector(0, 0, 0), Vector(0, 0, 1))
    return solid, face, dev_samples, ordered


def save_step(shape, path, name):
    """STEP AP214 with the product named `name` (cadquery's plain exporter leaves it unnamed)."""
    import cadquery as cq
    assy = cq.Assembly(shape, name=name)
    if hasattr(assy, "export"):
        assy.export(path, exportType="STEP")
    else:                                   # cadquery < 2.5
        assy.save(path, exportType="STEP")


def volume(shape, eps=1e-7):
    """Adaptive-precision volume (cadquery's Shape.Volume() uses the fixed Gauss rule, which is
    only ~1e-4 accurate on B-spline surfaces of revolution)."""
    from OCP.BRepGProp import BRepGProp
    from OCP.GProp import GProp_GProps
    props = GProp_GProps()
    BRepGProp.VolumeProperties_s(shape.wrapped, props, eps)
    return props.Mass()


def check_solid(shape, label, lines):
    ok = True
    n_solids = len(shape.Solids()) if hasattr(shape, "Solids") else 1
    valid = shape.isValid()
    lines.append(f"{label:<28} isValid {str(valid):<5} solids {n_solids}")
    ok &= valid and n_solids == 1
    return ok


def preview_png(solid, poly, ordered, path, name):
    """Two panels: (left) the meridional section of the STEP solid (plane Y = 0) drawn over the
    profile points it was built from; (right) a shaded cut-away of the tessellated solid."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    import cadquery as cq
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    fig = plt.figure(figsize=(11, 5))
    ax = fig.add_subplot(1, 2, 1)
    # section of the solid by the plane y = 0 -> edges -> sampled points
    big = 4.0 * max(solid.BoundingBox().xlen, solid.BoundingBox().zlen) + 10
    plane = cq.Face.makePlane(big, big, cq.Vector(0, 0, 0), cq.Vector(0, 1, 0))
    sec = solid.intersect(plane)
    first = True
    for e in sec.Edges():
        n = 200
        P = np.array([[e.positionAt(i / n).z, e.positionAt(i / n).x] for i in range(n + 1)])
        ax.plot(P[:, 0], P[:, 1], "-", color="#1f77b4", lw=1.2, label="STEP section (y = 0)" if first else None)
        first = False
    for lab, p in ordered:
        p = np.array(p)
        ax.plot(p[:, 0], p[:, 1], ".", ms=2.5, color="#d62728", label="profile points" if lab == ordered[0][0] else None)
    ax.plot(0, 0, "k+", ms=9, mew=1.5)
    ax.set_aspect("equal"); ax.grid(True, lw=0.3)
    ax.set_xlabel("optical axis z (mm)"); ax.set_ylabel("r (mm)")
    ax.set_title(f"{name}: section of the STEP solid vs. the exported profile")
    ax.legend(loc="best", fontsize=8)

    ax3 = fig.add_subplot(1, 2, 2, projection="3d")
    # tessellate a cut-away (remove the y < 0 half so the cavity is visible)
    half = solid.intersect(cq.Solid.makeBox(big, big, big, cq.Vector(-big / 2, 0, -big / 2)))
    verts, tris = half.tessellate(0.01, 0.15)
    V = np.array([[v.x, v.y, v.z] for v in verts]); T = np.array(tris)
    mesh = Poly3DCollection(V[T], alpha=0.95, linewidths=0.05, edgecolor=(0, 0, 0, 0.15))
    # shade by the face normal's z component
    nrm = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    nrm /= (np.linalg.norm(nrm, axis=1)[:, None] + 1e-12)
    light = np.array([0.3, -0.8, 0.5]); light /= np.linalg.norm(light)
    shade = 0.45 + 0.55 * np.abs(nrm @ light)
    mesh.set_facecolor(np.c_[0.55 * shade, 0.75 * shade, 0.95 * shade, np.ones_like(shade)])
    ax3.add_collection3d(mesh)
    lim = np.abs(V).max()
    ax3.set_xlim(-lim, lim); ax3.set_ylim(-lim, lim); ax3.set_zlim(V[:, 2].min() - 0.05 * lim, V[:, 2].max() + 0.05 * lim)
    ax3.set_box_aspect((1, 1, (V[:, 2].max() - V[:, 2].min() + 0.1 * lim) / (2 * lim)))
    ax3.view_init(elev=22, azim=-60)
    ax3.set_xlabel("x (mm)"); ax3.set_ylabel("y (mm)"); ax3.set_zlabel("z = optical axis (mm)")
    ax3.set_title("cut-away (y >= 0 half)")
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)
    return path


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("profile_csv")
    ap.add_argument("--out", default=None, help="output folder (default: next to the CSV)")
    ap.add_argument("--name", default=None, help="file stem and STEP product name (default: from the CSV name)")
    ap.add_argument("--cut", type=float, default=None, help="also write the two pieces split by the plane z = CUT (mm)")
    ap.add_argument("--stl", action="store_true", help="also write an STL tessellation")
    ap.add_argument("--check", action="store_true", help="write <name>_step_check.txt")
    ap.add_argument("--png", action="store_true", help="also write <name>_step_preview.png (needs matplotlib): "
                    "meridional section of the STEP solid over the profile points + a cut-away 3-D view")
    ap.add_argument("--rev", default="", help="revision string recorded in the check file")
    a = ap.parse_args(argv)

    out = a.out or os.path.dirname(os.path.abspath(a.profile_csv))
    os.makedirs(out, exist_ok=True)
    name = a.name or os.path.splitext(os.path.basename(a.profile_csv))[0].replace("_profile", "")
    try:
        import cadquery as cq
    except ImportError:
        print("make_step.py: cadquery is not installed for this Python "
              f"({sys.executable}). Install it with:  pip install cadquery", file=sys.stderr)
        return 1

    t0 = time.time()
    segs = read_profile(a.profile_csv)
    poly = polyline_outline(segs)
    solid, face, dev_samples, ordered = build(segs, name)
    step_path = os.path.join(out, name + ".step")
    save_step(solid, step_path, name)
    written = [step_path]

    lines = []
    L = lines.append
    L(f"STEP CHECK  {name}   {time.strftime('%Y-%m-%d %H:%M:%S')}   {('rev ' + a.rev) if a.rev else ''}")
    L(f"profile     {os.path.abspath(a.profile_csv)}")
    L("frame       optical axis = +Z, focus at the origin, units mm, STEP AP214 (cadquery %s)" % cq.__version__)
    L("segments    " + "  ".join(f"{lab}[{len(p)}]" for lab, p in ordered))
    all_ok = True

    # 1. topology
    all_ok &= check_solid(solid, "solid", lines)

    # 2. volume vs. Pappus on the polyline profile
    v_pap = pappus_volume(poly)
    v_sol = volume(solid)
    rel = abs(v_sol - v_pap) / v_pap if v_pap else float("nan")
    vol_ok = rel < 1e-3
    all_ok &= vol_ok
    L(f"volume      solid {v_sol:.6f} mm^3   polyline (Pappus) {v_pap:.6f} mm^3   diff {100*rel:.4f} %   "
      f"{'PASS' if vol_ok else 'FAIL'} (< 0.1 %)")
    # cross-section area sanity (face vs. shoelace)
    A_poly = 0.5 * abs(sum(x0 * r1 - x1 * r0 for (x0, r0), (x1, r1) in zip(poly[:-1], poly[1:])))
    L(f"section     face area {face.Area():.6f} mm^2   polyline {A_poly:.6f} mm^2")

    # 3. envelope
    bb = solid.BoundingBox(tolerance=1e-6)
    xs = [p[0] for p in poly]; rs = [p[1] for p in poly]
    L(f"envelope    z [{bb.zmin:.4f}, {bb.zmax:.4f}]  (profile x [{min(xs):.4f}, {max(xs):.4f}])   "
      f"OD {max(bb.xmax - bb.xmin, bb.ymax - bb.ymin):.4f}  (profile 2*max r {2*max(rs):.4f})   length {bb.zlen:.4f}")

    # 4. spline vs. polyline deviation (per spline segment, densely sampled)
    worst = 0.0
    for lab, e, p in dev_samples:
        n = max(20, 8 * len(p))
        dmax = 0.0
        for i in range(n + 1):
            q = e.positionAt(i / n)          # normalized parameter along the edge
            d = dist_point_polyline((q.z, math.hypot(q.x, q.y)), p)
            dmax = max(dmax, d)
        worst = max(worst, dmax)
        L(f"deviation   {lab:<10} spline vs polyline max {1e3*dmax:8.3f} um  ({len(p)} points)")
    dev_ok = worst < 0.005
    all_ok &= dev_ok
    L(f"deviation   worst {1e3*worst:.3f} um   {'PASS' if dev_ok else 'WARN'} (< 5 um)")

    # 5. re-import the written STEP
    try:
        imp = cq.importers.importStep(step_path)
        sh = imp.val()
        vi = volume(sh)
        reimp_ok = sh.isValid() and abs(vi - v_sol) / v_sol < 1e-5 and len(imp.solids().vals()) == 1
        all_ok &= reimp_ok
        L(f"re-import   isValid {sh.isValid()}  solids {len(imp.solids().vals())}  volume {vi:.6f} mm^3  "
          f"size {os.path.getsize(step_path)/1024:.1f} KB   {'PASS' if reimp_ok else 'FAIL'}")
    except Exception as ex:  # noqa: BLE001
        all_ok = False
        L(f"re-import   FAIL ({ex})")

    # 6. STL (optional) + watertightness with trimesh when available
    if a.stl:
        stl_path = os.path.join(out, name + ".stl")
        cq.exporters.export(solid, stl_path, tolerance=0.005, angularTolerance=0.1)
        written.append(stl_path)
        try:
            import trimesh
            m = trimesh.load(stl_path, force="mesh")
            m.merge_vertices(merge_tex=True, merge_norm=True)      # STL repeats seam vertices
            m.update_faces(m.nondegenerate_faces())
            m.remove_unreferenced_vertices()
            wt = bool(m.is_watertight) and m.euler_number == 2
            all_ok &= wt
            L(f"stl         {len(m.faces)} triangles  watertight {m.is_watertight}  euler {m.euler_number}  "
              f"volume {m.volume:.4f} mm^3 (chordal, < solid)   {'PASS' if wt else 'FAIL'}")
        except ImportError:
            L("stl         written (trimesh not installed: watertightness not checked)")

    # 7. cut pieces
    if a.cut is not None:
        z0 = a.cut
        big = 10.0 * max(bb.xlen, bb.ylen, bb.zlen) + 10.0
        box_f = cq.Solid.makeBox(big, big, big, cq.Vector(-big / 2, -big / 2, z0))
        box_b = cq.Solid.makeBox(big, big, big, cq.Vector(-big / 2, -big / 2, z0 - big))
        front = solid.intersect(box_f)
        back = solid.intersect(box_b)
        vf, vb = volume(front), volume(back)
        vsum = vf + vb
        pieces_ok = check_solid(front, "front piece (z >= cut)", lines) & check_solid(back, "back piece (z <= cut)", lines)
        pieces_ok &= abs(vsum - v_sol) / v_sol < 1e-4
        all_ok &= pieces_ok
        for tag, sh in (("front", front), ("back", back)):
            pth = os.path.join(out, f"{name}_{tag}.step")
            save_step(sh, pth, f"{name}_{tag}")
            written.append(pth)
        L(f"cut z = {z0:+.4f}  front {vf:.6f} + back {vb:.6f} = {vsum:.6f} mm^3   "
          f"{'PASS' if pieces_ok else 'FAIL'}")

    # 8. preview picture (best effort)
    if a.png:
        try:
            png = preview_png(solid, poly, ordered, os.path.join(out, name + "_step_preview.png"), name)
            written.append(png)
            L("preview     " + os.path.basename(png))
        except Exception as ex:  # noqa: BLE001
            L(f"preview     not written ({type(ex).__name__}: {ex})")

    L(f"verdict     {'PASS' if all_ok else 'FAIL'}   ({time.time()-t0:.1f} s)")
    L("files       " + "  ".join(os.path.basename(w) for w in written))
    if a.check:
        with open(os.path.join(out, name + "_step_check.txt"), "w") as f:
            f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if all_ok else 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as ex:  # noqa: BLE001
        print(f"make_step.py: ERROR {type(ex).__name__}: {ex}", file=sys.stderr)
        sys.exit(1)
