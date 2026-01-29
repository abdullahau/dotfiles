## Remote Jupyter Server

```bash
jupyter lab --ip=0.0.0.0 --no-browser --port=9999
```

## Create an IPython Kernerl for Virtual Environment (Environment kernel for Jupyter Notebooks)

```bash
python -m ipykernel install --user --name "$(basename $PWD)" --display-name "Python ($(basename $PWD))"
```
