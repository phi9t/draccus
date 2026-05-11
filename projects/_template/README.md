# Project REPLACE_ME

## Quickstart

```bash
# Sync dependencies from the frozen lockfile
../../bin/draccus-run uv sync --frozen

# Verify GPU foundation is intact
../../bin/draccus-run python -c "import torch; print(torch.__version__, torch.cuda.is_available())"

# Interactive shell
../../bin/draccus-run bash -l
```

## Adding dependencies

```bash
../../bin/draccus-run uv add <package>
../../bin/draccus-run uv sync
```

## Do NOT install these packages

The packages below are owned by the Spack `base-ml` environment and resolve from
`/opt/draccus/view/base-ml`. Adding them to `pyproject.toml` will be rejected by
`draccus-project-init` and flagged by `validate_uv_layering.sh`:

- `torch`
- `jax` / `jaxlib`
- `numpy`
- `scipy`
- `triton`
- Any `nvidia-*` pip package (e.g. `nvidia-cudnn-cu12`)
