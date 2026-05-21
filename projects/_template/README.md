# Project REPLACE_ME

## Quickstart

```bash
draccus uv sync --frozen
draccus run --name foundation-smoke -- python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
draccus shell
```

## Adding dependencies

```bash
draccus uv pip install transformers accelerate
draccus uv sync
```

## Foundation packages

Do not install foundation packages into the project environment. They are owned
by the Draccus Spack `base-ml` layer and must resolve from
`/opt/draccus/view/base-ml`, not from `.venv`.

Do not add these to `pyproject.toml` or install them with `draccus uv`:

- `torch`
- `jax` / `jaxlib`
- `numpy`
- `scipy`
- `triton`
- Any `nvidia-*` pip package
