# scripts/ — the NA2 pipeline

`LensConstructionGradual.m` is the only entry point. `RUN_MODE` near the top of the file picks
the mode used by Run / F5: `'paper'` (manual paper figures) or `'vendor'` (config-driven).

## Paper mode — the paper figures, manual parameters, no config file

Press Run / F5 (MATLAB or VS Code) with `RUN_MODE = 'paper'` (the default). The
parameters are typed in the `PAPER.*` block at the top of `LensConstructionGradual.m`
(section "PAPER FIGURES: manual parameters"): n2, layers, design rays, fan, drawn rays,
etc., one block per figure. The defaults are the
values behind the panels in *Paper/Final Figures.pptx*. Each figure builds its own lens
(`lib/paper_sim`: self-contained, independent of the vendor `lib/` code; verbatim ports of
the legacy construction and of the `StochasticRayTrace.m` / `Tracing3D.m` drawing code) and writes **only** its panels to
`outputs/paper_figures/`, overwriting the previous run:

| Panel | Files | Lens (default parameters) | Legacy source |
|---|---|---|---|
| Fig 1A | `fig1A_zoom.{pdf,svg}`, `_600dpi.png` | n2 2.003, 8 surfaces, 120 design rays, fan 0–162.54°; 10 drawn rays, window ±10 du | `StochasticRayTrace.m`, `FIGURE_VARIANT='fig1'`, zoom |
| Fig 1B | `fig1B_raytrace.{pdf,svg}`, `_600dpi.png` | same lens | same, full view |
| Fig 1E | `fig1E_rays2d.{pdf,emf}`, `_600dpi.png` | n2 2.003, 8 surfaces, 100 design rays, fan 0–179.9°; rays at 0/80/150/178° | `Tracing3D.m`, 2-D rays only |
| Fig 1F | `fig1F_rays3d.pdf`, `_600dpi.png` | same lens | `Tracing3D.m`, 3-D, 4 copies + circles |
| Fig 2C | `fig2C_simulation.{pdf,svg}`, `_600dpi.png` (full view) and `fig2C_zoom.*` (inset: inner elements fully enclosed) | n2 1.57, 16 surfaces (8 shells), 120 design rays, NA_hole 0.3; drawn rays at `PAPER.fig2C.ray_angles` = 0, 25, 59, 87, 117, 139, 161° (13 lines, matched to the laser photo's exit heights; 161.35° is the last collimated ray) | `StochasticRayTrace.m`, `FIGURE_VARIANT='fig2'`, same style as Fig 1A/1B |
| Fig 3B + 3C | `fig3BC_collection.pdf`, `_600dpi.png` and `fig3BC_collection_nolabels.*` | Fig 1A/1B lens; dipole collection curve vs NA with 99 % / 99.9 % marks (`PAPER.fig3BC.targets`); x axis `PAPER.fig3BC.x_axis` = `'theta'` (default: θ₀ = full opening angle of the inner lens mouth, tip to mirrored tip, 0–180°; same curve with the variable doubled; the Fig 3C arc spans the whole mouth) or `'NA'` (published panel: NA = sin of the half-angle, half-angle arc) | `StochasticRayTrace.m`, `FIGURE_VARIANT='fig1'`, collection figure `v6_NA_log_labeled` (left = 3B, right = 3C), labelled + label-free |
| Fig S (tolerances) | `figS_A.pdf`, `figS_B.pdf`, `figS_C.pdf`, `_600dpi.png`, and `figS_A/B/C_nolabels.*` with no text at all (no panel letters, titles, axis or tick labels, legends or annotations; graphics only, for labelling in PowerPoint), `tolerance_results.csv` | the paper's two tolerance checks on the sapphire design (n2 1.77, 8 surfaces, 400 design rays, NA_hole 0.3; surfaces traced as smooth splines through the design points): (1) λ/2 peak-to-valley figure error on every surface, random smooth height field with correlation lengths `PAPER.tol.corr_len_mm`, `n_trials` Monte Carlo realisations; (2) alignment error of the two parts of element 1 at `cut_x_mm` (transverse and axial offset; `align_sweep_waves`, spec `align_waves`), rays arriving at the step between the parts are lost. Dipole-weighted (`emitter`) power outside the design beam envelope | new: `sim_tolerance.m` + `sim_fig_tolerance.m` (A method schematic, B lost power vs distance, C lost power vs alignment error; one figure per panel) |

Set `PAPER.<figure>.enable = false` to skip a figure. EMF is Windows-only, as before.
Fig 3 is exported with `exportgraphics`: the original `print -dpdf` put the 26-cm-wide figure
on a letter page and cut its left edge off.

Verified (Octave 8, graphics stubbed): the default parameters rebuild the three paper lens
files (`lens_data_dipole_4_elements_no_glass.mat`, `lens_data_dipole_4_elements.mat`,
`lens_data_8_elements_n157.mat`) to ≤ 3e-10 du. The Fig 1B and Fig 2C ray and lens paths
match the Aug-2026 MATLAB SVGs (`ray_trace_figure.svg`, `ray_trace_figure_fig2.svg`) to
1e-4 px, the SVG's own rounding.

## Vendor mode — RFQ pipeline from a config

`LensConstructionGradual('inputs/config_example.json')` (a config argument is always vendor
mode), or Run with `RUN_MODE = 'vendor'`
(uses `DEFAULT_CONFIG`). Every setting comes from the JSON config;
`inputs/config_example.json` documents every key next to its value.

## Pipeline (one run)

| Stage | Function (lib/) | What it does |
|---|---|---|
| 1 | `config/read_config`, `validate_config`, `config_schema` | JSON → struct; unknown / missing / mistyped / out-of-range keys stop the run with the full list of problems. `config_schema.m` is generated from the example config by `config/gen_schema.py` — rerun it after adding a key. |
| 2 | `report/package_paths`, `make_output_folder` | `<output_root>/<vendor>/<material>_n<index>/Rev<X>_<date>/`; with a catalog glass and `run.material = null` the material folder is `<MAKER>_<glass>_<wavelength>nm` (e.g. `SCHOTT_N-LASF9_637nm_n1.844`); refuses to overwrite (`run.on_exists`). |
| 2b | `materials/resolve_material` → `material_lookup`, `read_agf`, `read_custom_materials`, `agf_index` | `design.material.name` set: `n_lens` := catalog index at `design.material.wavelength_nm` from the `*.agf` files (and `custom_materials.json`) in `inputs/materials/` (unknown/ambiguous glass, wavelength outside the catalog range or an empty folder stop the run before any folder is made). Not set: `n_lens` is used as written. `design.element_materials` gives listed elements their own material the same way (name → dispersion formula, n → as written + WARN). |
| 3 | `construction/build_lens` → `construct_lens` (`bend_weights`, `layer_angles`, `sphere_layer`, `check_demoldable`), `calculate_angles`, `construct_two_stage` | Builds the lens (or loads `design.from_mat`): one index pair per surface (`lens.n_surface`), prescribed spheres, slope clamps and the deficit carry — see "Isuzu molding variants". |
| 4 | `process/apply_process` | Manufacturing profile: tip truncation, edge fillet (both off = design geometry). |
| 5 | `trace/build_stack`, `auto_max_angle`, `trace_rays` | Validation ray trace through every surface (glass spacers and the asphere included). `trace.smooth_normals` (default off) interpolates the surface tangent between design rays instead of one constant normal per polyline segment. |
| 6 | `analysis/*` | Collimation, Fresnel loss + TIR margin, intensity profile, collection efficiency (3-D weighted, emitter applied once). CSVs in `analysis/`. |
| 7 | `checks/run_checks` | The pass-fail table (thresholds in `checks`). Any FAIL withholds the vendor files (stages 8 and 9) unless `run.export_on_fail`; the result pictures (8a) are always made. |
| 8 | `export/export_all` | XT profile, XYZ lines/half/grid, sag table + README, DXF revolve profile, Zemax Grid Sag. |
| 8a | `figures/fig_geometry`, `fig_raytrace`, `make_rfq_drawings(…,'pictures')`, `make_paper_figures` | Pictures of the result, written on PASS **and** FAIL: construction geometry (SVG + PNG, header = materials / indices, prescribed sphere, straight wall, design fan), `ray_trace.png` of the validation trace (lost rays red), 3-D preview, overview, and the paper panels when `figures.paper.enable`. |
| 9 | `figures/make_rfq_drawings(…,'vendor')` | Dimensioned element drawings (cross-section, cut pieces); withheld on FAIL like the vendor geometry. |
| 10 | `report/write_report` | `report.txt`, `report.json`, `runs_index.csv`. |

`run.close_figures_at_start` (default true) closes every open MATLAB figure before a run, so the screen
shows that run only. The Isuzu configs draw six figures: geometry, ray trace, 3-D preview, overview, the
3-D body (`figures.paper.panels.fig1c`) and the element cross-section; the other paper panels
(`fig1a`, `fig1b`, `fig1e`, `fig1f`) are switched off there and come back by setting them to `true`.

`sweep.enable` repeats stages 2–10 for each value of one config key (`sweep.parameter` is a dot
path such as `design.weights.k_shape`) into one sweep folder with `sweep_summary.csv`. A list of
objects is addressed by item: `design.spherical_surfaces[1].radius_du` (1-based) or
`design.slope_limits[].max_slope_deg` (every item).

## Isuzu molding variants (all OFF in the example config)

Three construction variants for the molded element-1 study. Surface numbering is the repo's:
S1 = cavity around the emitter, S2 = outer surface of element 1, surface j belongs to element
`ceil(j/2)`. Each is a list in `design`, `[]` by default, so `config_example.json` builds the same
lens bit for bit.

| Key | What it does |
|---|---|
| `design.element_materials` `{element, name \| n}` | Per-element material. `name` → index from the dispersion formula at `design.material.wavelength_nm` (AGF catalogs, or `inputs/materials/custom_materials.json` for polymers: `PMMA`, `PC`); `n` → used as written, WARN "no dispersion data". Unlisted elements keep `design.material` / `design.n_lens`. The lens carries one `(n_in, n_out)` pair per surface (`lens.n_surface`), used by the construction, the trace, Fresnel / TIR margin, the Zemax glass column and the drawing labels. With `run.material = null` the package folder reads `E1-PMMA_n1.489__SCHOTT_N-LASF9_637nm_n1.844`. |
| `design.spherical_surfaces` `{surface, center_z_du, radius_du}` | That surface is a prescribed sphere (centre on the axis, 0 = emitter), not constructed: the design rays leaving the previous surface are intersected with it and refracted by Snell with the local indices. `{1, 0, 1}` = concentric cavity, zero bending (surface 1 must keep its vertex at 1 du = `WD_mm`: `center + radius = 1`, or `center_z_du: null`). `{2, c, R}` = spherical outer surface of element 1; `scripts/tools/fit_sphere.m` prints `c`, `R` from a `lens.mat`. Exports, the validation trace and the drawings use the exact arc; Zemax gets a STANDARD surface (`SPHERE R=…`, conic 0). |
| `design.slope_limits` `{surface, max_slope_deg, pull}` | Draft: while the surface is built, a segment steeper than the limit (angle from the plane normal to the axis; 90 = straight wall, 87 = 3° draft, > 90 = undercut) is replaced by a straight cone at the limit. `pull` = direction the mold tool leaves (`back` = −x, toward the emitter; `front` = +x; inner surfaces are formed by a core, outer ones by the cavity block). Demoldability in that direction (radius monotonic from the mouth inward) is a FAIL row when violated. Intended: `{1, 87, "back"}` — no belly undercut in the cavity. |

**The deficit carry.** `bend_weights` gives every surface its share of each ray's total bend;
`construct_lens` now solves one surface at a time (`layer_angles`) from the angles the rays really
have. A constructed surface delivers its share exactly. A sphere or a clamped cone delivers what
its geometry allows; the shortfall per ray is spread over the following surfaces in proportion to
their weights, so the last free surface still ends every ray at its planned exit angle. With no
variant the carry is never touched — the geometry is bit-identical to the all-at-once schedule.
`lens.budget` keeps planned / carried / achieved / deficit per ray and surface; the report prints
the per-layer table, and `checks.bending_budget_tol_deg` FAILs a lens whose budget does not close
(a prescribed or clamped LAST surface, or a Snell solve that would need more than refraction can
give). A design ray that misses a prescribed sphere, is totally reflected at it, or a sphere that
crosses its neighbour stops the construction with the first ray angle named.

`lens.surfaces(j).kind` is `built`, `sphere` or `clamped` (+ the sphere's centre / radius / exact
arc, or the clamp's first ray, count and demoldability); `lens.mat` stores it with `n_surface`,
`element_n`, `budget` and `material` (`.default` = the catalog lookup, `.elements` = per element).

Configs: `inputs/config_isuzu_A.json` (element 1 PMMA), `_B.json` (S2 sphere, centre 0.17 / R 5.73 du — see the note below), `_C.json` (S1 87° draft, pull back), `_ABC.json` (all three; its sphere is refitted
on the PMMA + draft lens because that element is ~3.5× larger). They switch the split-and-bond cut
off (molded element).

`inputs/config_isuzu_BC.json` is Isuzu's combined request (S2 spherical **and** the cavity sides
straight): `slope_limits {1, 90, back}` + `spherical_surfaces {2, 0.6917, 4.0083}` +
`fan_max_deg_override = 140`. With both surfaces of element 1 prescribed, the rays that hit the
straight wall leave the sphere almost parallel and crowd into the knife-edge tip of element 2: at
the full 162.5° fan 18–30 % of the emission is lost or miscollimated for every sphere tried
(scan of 2026-09-18), and a sphere fitted to the natural S2 totally reflects the last 2–4 design
rays. Cutting the design fan at 140° keeps 99.9 % of the fan (dipole-weighted collection 0.9615 vs
0.998 for the free-form baseline), verdict PASS, and the lens shrinks (E1 Ø8.0, E4 Ø53.7 mm).
Best values found per fan limit: 150° → 0.952, 140° → 0.961, 132° → 0.926; an 87° taper instead
of the straight wall gives 0.954 at 140°.

`inputs/config_isuzu_ABC_n2.json` is the same request with element 1 in PMMA and elements 2–4 in a
high-index glass to shrink the lens (OHARA S-LAH99, n 1.9935 at 637 nm): S2 sphere (centre 1.8155,
R 8.7145 du), S1 straight, design fan 150°. Rays beyond ~150° are lost for every sphere with this
material pair, so the fan is cut there; that also halves the lens (E1 17.4 / E4 196 mm, against
34.9 / 416 mm at the full fan and 36 / 523 mm with N-LASF9). Dipole collection 0.987. By fan:
150° 0.987, E4 196 mm | 140° 0.962, E4 95 mm | 132° 0.926, E4 62 mm.

Three more Isuzu runs (2026-09-22): `inputs/config_isuzu_PC.json` = element 1 in polycarbonate
(`custom_materials.json`, n 1.5801 at 637 nm), no other constraint, E1 Ø19.8 mm, PASS;
`config_isuzu_n172_BC.json` and `config_isuzu_n185_BC.json` = every element a generic glass of
n 1.72 / 1.85 as written, S2 sphere + S1 straight, design fan 140° (at 150° and 145° every sphere
loses rays), E1 Ø7.1 / Ø8.0 mm, collection 0.962. These two set `run.export_on_fail = true` so the
sag table and element drawing are written whatever the verdict. The smooth-normal trace does not
interpolate across the corner where a straight wall starts (`stack.kinks`, from
`surfaces(j).first_clamped_ray`): the polyline IS the surface there. With that, only spheres whose
vertex sits at ≥ 3.85 du are clean for n 1.85; closer ones pass the 200-ray check but a dense probe
finds a sliver of bad rays at 133–135°, where the wall begins.

```matlab
addpath scripts/tools
fit_sphere('<package>/lens.mat', 2, 4.5)     % surface 2, front part r <= 4.5 mm -> c, R, residuals, JSON line
```

## What each legacy script became

| Legacy (now in `old stuff/`) | In the config |
|---|---|
| `LensConstructionGradual.m` | the baseline: `design`, `process.cut`, `export`, `figures.rfq` (the example config with `design.material.name = null`, `n_lens = 1.85`, `run.material = "N-LASF9"` reproduces its files byte for byte; as shipped it uses N-LASF9 at 637 nm) |
| `LensConstructionGradualTunedWeightsTest.m` | `design.truncation`, `design.NA_design_margin`; its weights k_shape 4.5 / layer_exp 1.5; inner vertex 0.5 mm → `WD_mm = 0.5` |
| `LensConstructionGradual2Omni1Aspherical.m` | `design.collimation_fraction < 1`, `design.fan_max_deg_override`, `design.solver.method = "analytic"` |
| `LensConstructionGradual_3Elem.m` | `design.commercial_asphere` (catalog or custom Edmund coefficients, Stage-3 correction), `design.layers_design_budget`; parity settings in the key docs (`WD_mm 0.5`, `jump_size_du 0.2`, `fan_epsilon_deg 0`) |
| `RelaxatedLensConstructionDipoleWithGlassGap.m` | `design.glass_cell` (experimental — see its doc), `weights.k_shape = 0` |
| `StochasticRayTrace.m` | `trace` (incl. `auto_max_angle`, `segment_overshoot`), `emitter`, `analysis.collection_efficiency`, `figures.paper` (fig1a/1b, heatmap, arrowheads, styles) |
| `Tracing3D.m`, `SolidOfRevolution.m` | `figures.paper.panels.fig1e/fig1f` + `rays_3d`; `fig1c/fig1d`; `figures.rfq.surfaces_3d` |
| `Figure2Simulation.m` | just a design: `n_lens 1.57`, `layers_count 16` (or `design.from_mat` on its .mat) + `figures.paper` |
| `TuningParameterSweep.m`, NA2_v2 Code3 variations | `sweep` |
| `AsphericalLensIntegration.m` | the asphere surface functions of `commercial_asphere`; `figures.asphere_check` is its plot |
| NA2_v2 (Code1–3 + lib) | `analysis.fresnel` (polarization), `analysis.intensity_profile`, `export.dxf_revolve`, `export.zemax`, `figures.paper.collection_plot`, `figures.paper` label-free exports |
| `GenerateAllVersions.m`, `StochasticRayTraceDipoleLensWithGlassGap.m` | retired (superseded; the first did not parse, the second never refracted in its gaps) |

## Glass catalogs (`inputs/materials/`)

The folder holds the makers' Zemax catalogs as downloaded (Ohara, Schott, Hoya today; drop in
CDGM/Sumita/Hikari the same way — every `*.agf` file is searched). `design.material.name`
picks a glass by its catalog spelling (`"S-LAH71"`, `"N-LASF9"`, `"TAFD55"`; case and `-`
ignored; `"OHARA:S-LAH71"` when a name exists in two catalogs), `design.material.wavelength_nm`
sets where the index is evaluated (null = d-line 587.56 nm, flagged WARN). The index comes
from the catalog dispersion formula, never from a typed number; the report's MATERIAL section
gives name, catalog, formula, nd/νd, validity range, status and internal transmittance, and
`report.json` / `lens.mat` keep the same provenance. `materials_table` writes
`inputs/materials/materials_index.csv` (one line per glass, n at 575 and 637 nm) for people —
regenerate it after adding a catalog:

```matlab
materials_table('inputs/materials', 'inputs/materials/materials_index.csv', [575 637])
```

Polymers are not in the makers' catalogs: `inputs/materials/custom_materials.json` is read as one
more catalog (name, maker, AGF formula number, coefficients, range, source URL). It holds PMMA and
PC (Sellmeier, Sultanova / Kasarova / Nikolov 2009 as listed on refractiveindex.info: PMMA 1.4886
at 637 nm and 1.4912 at 575 nm, PC 1.5801 at 637 nm); add an entry only with a citable source.

Verified: the parsed formulas reproduce the catalog nd of all 1038 glasses (Ohara ≤ 5e-7,
Schott ≤ 5e-6) except two Hoya precision-molding preforms (MC-FAD61, MC-TAF115) whose
coefficients and listed nd disagree in Hoya's own file — the report warns when that happens.

## Two facts about the lens that the port made visible

* **Scale.** `LensConstructionGradual.m` had the inner vertex at 1 design unit = `WD_mm`;
  the TunedWeights / 3Elem scripts had it at 0.5 mm. `WD_mm` sets the physical size in
  every case — `WD_mm = 1` is the Ø10.2 mm element-1 of the current RFQ package,
  `WD_mm = 0.5` the Ø5 mm version of the older scripts.
* **Solver.** `design.solver.method = "analytic"` reproduces the `vpasolve` geometry to
  3e-12 (verified on the 8-surface, 120-ray design) without the Symbolic toolbox and
  ~100× faster; `"symbolic"` is kept for reference.
* **Index vs wavelength.** n = 1.85 is N-LASF9 at the d-line (587.6 nm). From the Schott
  catalog it is 1.8520 at 575 nm and 1.8445 at 637 nm; a strictly collimating design is exact
  only at its design index, so set `design.material` + the working wavelength when the
  package is for a real emitter line.

## Verified for the molding variants (MATLAB R2024b, 2026-09-17; no Octave on that machine)

* `config_example.json` before / after the change, symbolic solver: all XYZ line / half / grid
  tables, the sag CSV and the XT profile byte-identical (26 files), the four analysis CSVs too,
  verdict PASS unchanged; the sag README differs in its date line only. Analytic solver:
  `final_lens`, the angle matrices, the trace stack and the manufacturing profile `isequal`.
* The four `config_isuzu_*.json` run to a report; both sweeps
  (`design.spherical_surfaces[1].radius_du`, `design.slope_limits[].max_slope_deg`) run through
  `sweep`. Findings worth knowing: PMMA (1.49) on element 1 roughly triples every element
  (E1 Ø10.2 → Ø29.7 mm) because the weak inner element moves all later surfaces outward; the
  87° draft removes the S1 undercut (max slope 109.5° → 87.0°, demoldable) at E1 Ø14.9 mm.
* **Choosing the S2 sphere (2026-09-19).** The least-squares sphere of the free-form S2
  (`fit_sphere`: c 0.6357, R 5.1778) FAILED with lost rays: it bends the outermost rays up to 6.3°
  more than their share and mid-fan rays 4.6° less, so beyond ~155° the rays cross their
  neighbours, S4–S8 fold back at their tips and the band 154.6–158.8° falls past the fold. A
  sphere centred closer to the emitter never over-bends (shortfall 0…+10°, carried forward):
  vertex 5.90 du with centre 0.14–0.20 du is loss-free (collimation 0.7° max, TIR margin 11°,
  collection 0.9984, elements ~14 % larger). Rule of thumb: the S2 row of the bending-budget
  table must show no negative deficit near the fan edge.
* **`trace.smooth_normals`.** With one constant normal per segment a ray landing just before or
  after a vertex is sent a whole design-ray step off target: that is the baseline's 0.94° / 0.47°
  rms collimation residual (0.38° / 0.03° with smooth normals) and, next to compressed crescent
  tips, single lost rays that are not a property of the lens. Config B turns it on; the default
  stays off so the example's analysis files are unchanged (trace paths and exit angles `isequal`).
* The new code avoids `string`, `table`, `datetime` and other MATLAB-only constructs, but it has
  not been executed in Octave.

## Verified so far (Octave 8, no MATLAB here)

Byte-identical to the 2026-09-05 MATLAB run: all XYZ line / half / grid tables and the
element-1 sag table. Analytic solver = vpasolve geometry (3e-12). 3Elem two-stage port =
the reference `.mat` files (1e-13). Every stage above was executed at least once
(regression, truncation, partial collimation, asphere with correction, fillet/truncation,
sweep, validator rejections). Figure functions were parse-checked and run against no-op
graphics stubs only — the first MATLAB run should look at every drawing and panel.
Zemax export (`table`/`string`) is MATLAB-only and untested here.
