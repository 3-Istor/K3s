FROM python:3.15.1-slim

RUN pip install --no-cache-dir numpy==2.5.5 pandas==3.1.1 matplotlib==3.11.2 \
 && useradd --uid 1000 --create-home sbx \
 && mkdir /workspace && chown sbx /workspace
COPY cnp_tools /usr/local/lib/python3.13/site-packages/cnp_tools
COPY exec_server.py /opt/exec/exec_server.py
# Font cache built once here: the root filesystem is read-only at run time.
RUN MPLCONFIGDIR=/opt/mpl python -c "import matplotlib.pyplot" && chmod -R a+rX /opt/mpl

ENV PYTHONDONTWRITEBYTECODE=1
USER 1000
WORKDIR /workspace
EXPOSE 8888
ENTRYPOINT ["python", "-u", "/opt/exec/exec_server.py"]
