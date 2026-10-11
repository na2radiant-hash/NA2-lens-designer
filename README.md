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
| Fig 1A, 1B | `fig1A_*`, `fig1B_*` | lens and ray fan |
| Fig 1F | `fig1F_rays3d.*` | 3-D rays |
| Fig 2C | `fig2C_simulation.*`, `fig2C_zoom.*` | 16-surface lens with the laser-photo rays |
| Fig 3B, 3C | `fig3BC_collection.*`, `*_nolabels.*` | dipole collection vs angle |
| Fig S (tolerances) | `figS_A/B/C.*`, `*_nolabels.*`, `tolerance_results.csv` | lambda/2 figure error, lambda/4 split-element alignment |

Every parameter of every panel is set in the `PAPER` block; `PAPER.<figure>.enable = false` skips a
figure. The tolerance Monte Carlo (Fig S) takes about 1.5 min; the whole run a few minutes.
`scripts/README.md` describes the pipeline, the library and the tolerance method in detail.

Tested with MATLAB R2024b. Requires only base MATLAB (`exportgraphics`, `spline`, `interp1`).

## Vendor mode

`RUN_MODE = 'vendor'` runs the config-driven design and vendor-export pipeline
(`LensConstructionGradual('<config>.json')`). The configuration files and glass catalogs it reads
are not part of this repository.

## Cite

See `CITATION.cff` (GitHub: "Cite this repository"). Pin a tag or a commit hash in a paper, not the
branch.

## License

CC BY 4.0, see `LICENSE`.
