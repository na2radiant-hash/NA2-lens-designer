"""Generate config_schema.m (next to this file) from inputs/config_example.json.

Run:  python scripts/lib/config/gen_schema.py   (from the NA2 folder, or anywhere)

Leaf types (strings interpreted by validate_config.m):
  bool | num | int | num? | str | str? | enum:a|b|c | numvec | strlist
  objlist:<field>=<type>,<field>=<type>,...
      a JSON list of objects; every object has exactly these fields, each
      checked with the leaf type after '=' (optional field = 'num?' / 'str?')
"""
import json, sys

import os
HERE = os.path.dirname(os.path.abspath(__file__))
cfg = json.load(open(os.path.join(HERE, '..', '..', '..', 'inputs', 'config_example.json')))

# keys that need a stricter/looser type than the example value implies
OVERRIDES = {
    'run.elements': 'numvec',
    'run.material': 'str?',
    'design.from_mat': 'str?',
    'design.n_lens': 'num?',
    'design.material.name': 'str?',
    'design.material.wavelength_nm': 'num?',
    'process.cut.x0_mm': 'numvec',
    'run.on_exists': 'enum:error|suffix',
    'design.layers_count': 'int',
    'design.rays_count': 'int',
    'design.solver.method': 'enum:symbolic|analytic',
    'design.solver.max_attempts': 'int',
    'design.commercial_asphere.model': 'enum:edmund_22722_150mm|edmund_15003_100mm|custom',
    'design.glass_cell.before_elements': 'numvec',
    'emitter.type': 'enum:isotropic|dipole',
    'emitter.dipole_axis': 'enum:x|y',
    'trace.n_rays': 'int',
    'trace.sampling': 'enum:deterministic|stochastic',
    'trace.auto_max_iters': 'int',
    'analysis.fresnel.polarization': 'enum:unpolarized|s|p',
    'analysis.intensity_profile.n_bins': 'int',
    'export.grid_interp': 'enum:linear|pchip|makima',
    'export.profile_2d': 'enum:xt|none',
    'export.dxf_precision': 'int',
    'export.zemax_n_grid': 'int',
    'export.units': 'enum:mm|du',
    'figures.rfq.n_theta': 'int',
    'figures.rfq.png_dpi': 'int',
    'figures.rfq.ray_overlay.n_rays': 'int',
    'figures.paper.n_rays_drawn': 'int',
    'figures.paper.zoom_n_elements': 'int',
    'figures.paper.heatmap.res': 'int',
    'figures.paper.rays_3d.n_copies': 'int',
    'figures.paper.collection_plot.x_axis': 'enum:NA|deg',
    'figures.paper.collection_plot.y_scale': 'enum:linear|log|complement|power',
    'figures.paper.png_dpi': 'int',
    'figures.style': 'enum:b9e1f0|scientificblue|blue|darkyellow|green',
    'sweep.values': 'numvec',
    'checks.max_lost_rays': 'int',
    'checks.max_solver_fallbacks': 'int',
}

# lists of objects: their example values are [] (= feature off), so the item
# schema cannot be read off the example and is declared here instead.
# Field order is the order validate_config reports and normalise_objlist returns.
OBJLISTS = {
    'design.element_materials':  'element=int,name=str?,n=num?',
    'design.spherical_surfaces': 'surface=int,center_z_du=num?,radius_du=num',
    'design.slope_limits':       'surface=int,max_slope_deg=num,pull=enum:back|front',
}

def leaf_type(path, v):
    if path in OBJLISTS:
        if not isinstance(v, list):
            raise TypeError(f'{path}: OBJLISTS entry but the example value is not a list')
        return 'objlist:' + OBJLISTS[path]
    if path in OVERRIDES:
        return OVERRIDES[path]
    if isinstance(v, bool):
        return 'bool'
    if v is None:
        return 'num?'
    if isinstance(v, (int, float)):
        return 'num'
    if isinstance(v, str):
        return 'str'
    if isinstance(v, list):
        if all(isinstance(x, str) for x in v):
            return 'strlist'
        return 'numvec'
    raise TypeError(path)

lines = []
seen = set()
def emit(d, prefix):
    for k, v in d.items():
        if k.startswith('_'):
            continue
        path = f'{prefix}.{k}' if prefix else k
        seen.add(path)
        if isinstance(v, dict):
            emit(v, path)
        else:
            lines.append(f"S.{path} = '{leaf_type(path, v)}';")

emit(cfg, '')
missing = sorted(set(OBJLISTS) - seen)
if missing:
    raise KeyError(f'OBJLISTS keys not in config_example.json: {missing}')

header = """function S = config_schema()
%CONFIG_SCHEMA  Allowed keys and leaf types of the NA2 run configuration.
%
%   GENERATED from inputs/config_example.json by gen_schema.py - do not edit
%   by hand; regenerate when a key is added to the config.
%
%   Leaf type strings understood by validate_config:
%     'bool'     logical scalar
%     'num'      numeric scalar
%     'int'      numeric scalar with an integer value
%     'num?'     numeric scalar or [] (JSON null = "derive automatically")
%     'str'      character vector
%     'str?'     character vector or [] (JSON null)
%     'enum:a|b' character vector from the listed set
%     'numvec'   numeric vector (may be empty)
%     'strlist'  char or cell array of chars
%     'objlist:f1=t1,f2=t2,...'
%                [] or a list of objects (struct array / cell of structs) whose
%                items have exactly the fields f1, f2, ... of leaf types t1, t2, ...
%                (see normalise_objlist for the canonical 1 x N struct shape)
%
%   NKEYS keys.
S = struct();
"""
out = header.replace('NKEYS', str(len(lines))) + '\n'.join(lines) + '\nend\n'
open(os.path.join(HERE, 'config_schema.m'), 'w', newline='\n').write(out)
print(len(lines), 'leaf keys written')
