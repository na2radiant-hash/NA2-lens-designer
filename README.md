# NA2 omnidirectional qubit lens: design and paper simulations (MATLAB)

Code behind the figures of the NA2 omnidirectional collimating-lens paper: the lens construction,
the ray-trace checks (collection efficiency, collimation) and the fabrication-tolerance Monte Carlo
of the supplementary figure. One script, no input files.

## Run the paper simulations

```matlab
cd <this folder>/scripts
LensConstructionGradual
```

`RUN_MODE = 'paper'` (the default at the top of the script) rebuilds every paper lens from the
parameters in the `PAPER` block of the script and writes the panels to `outputs/paper_figures/`:

| Figure | Files | Content |
|---|---|---|
| Fig 1A, 1B | `fig1A_zoom.*`, `fig1B_raytrace.*` | lens and ray fan, zoom and full view |
| Fig 1E, 1F | `fig1E_rays2d.*`, `fig1F_rays3d.*` | rays in 2-D and 3-D |
| Fig 2C | `fig2C_simulation.*`, `fig2C_zoom.*` | 16-surface lens with the laser-photo rays |
| Fig 3B, 3C | `fig3BC_collection.*`, `*_nolabels.*` | dipole collection vs angle |
| Fig S (tolerances) | `figS_A/B/C.*`, `*_nolabels.*`, `tolerance_results.csv` | lambda/2 figure error, lambda/4 split-element alignment |

Every parameter of every panel is set in the `PAPER` block; all figures are enabled as shipped and
`PAPER.<figure>.enable = false` skips one. The tolerance Monte Carlo (Fig S) takes about 2 min; the
whole run a few minutes. `scripts/README.md` describes the pipeline, the library and the tolerance
method in detail.

Tested with MATLAB R2024b on Windows. Paper mode needs base MATLAB only; vendor mode also needs the
Symbolic Math Toolbox. The EMF export of Fig 1E is Windows-only and is skipped elsewhere.

## Vendor mode

`RUN_MODE = 'vendor'` runs the config-driven design and vendor-export pipeline
(`LensConstructionGradual('<config>.json')`). The configuration files and glass catalogs it reads
are not part of this repository.

## Cite

See `CITATION.cff` (GitHub: "Cite this repository"). Pin a tag or a commit hash in a paper, not the
branch.

## License

CC BY 4.0, see `LICENSE`.
