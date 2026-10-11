"""Render the actual ApplicationSet Go/Sprig expressions with Helm, offline."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
HELM = os.environ.get("HELM_BIN", "helm")


def render(expression, values):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "templates").mkdir()
        (root / "Chart.yaml").write_text("apiVersion: v2\nname: expression-test\nversion: 0.1.0\n")
        (root / "values.yaml").write_text(json.dumps(values))
        (root / "templates" / "test.yaml").write_text(
            '{{- define "body" -}}\n{{- with .Values -}}\n' + expression +
            '\n{{- end -}}\n{{- end -}}\napiVersion: v1\nkind: ConfigMap\nmetadata: {name: expression-test}\ndata:\n  result: {{ include "body" . | quote }}\n')
        result = subprocess.run([HELM, "template", "test", str(root)], capture_output=True, text=True, check=True)
        return yaml.safe_load(result.stdout)["data"]["result"]


class ApplicationImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = yaml.safe_load((ROOT / "k8s/config/argocd/applicationset-apps.yaml").read_text())["spec"]
        cls.expression = cls.spec["generators"][0]["matrix"]["generators"][1]["list"]["elementsYaml"]

    def test_catalog_defaults_and_fullstack_components_are_preserved(self):
        elements = json.loads(render(self.expression, {"spec": {"apps": [
            {"name": "web", "type": "static", "repoURL": "https://github.com/example/web"},
            {"name": "full", "type": "fullstack", "repoURL": "https://github.com/example/full"}]}}))
        self.assertEqual([e["component"] for e in elements], ["app", "frontend", "backend"])
        for element in elements:
            self.assertEqual(element["sourceRevision"], "HEAD")
            self.assertEqual(element["chartRevision"], "HEAD")
            self.assertEqual(yaml.safe_load(render(self.spec["template"]["spec"]["sources"][0]["helm"]["values"], element)), {})

    def test_import_pins_source_chart_and_image_digest(self):
        app = {"name": "imported", "type": "static", "repoURL": "https://github.com/external/original",
               "sourceRevision": "a" * 40, "chartRevision": "b" * 40,
               "imageTag": "import-test", "imageDigest": "sha256:" + "c" * 64}
        element = json.loads(render(self.expression, {"spec": {"apps": [app]}}))[0]
        sources = self.spec["template"]["spec"]["sources"]
        self.assertEqual(render(sources[0]["targetRevision"], element), "b" * 40)
        self.assertEqual(render(sources[1]["targetRevision"], element), "a" * 40)
        self.assertEqual(render(sources[1]["repoURL"], element), app["repoURL"])
        self.assertEqual(yaml.safe_load(render(sources[0]["helm"]["values"], element)),
                         {"image": {"tag": "import-test@sha256:" + "c" * 64}})
        self.assertEqual(render(sources[0]["helm"]["valueFiles"][0], element), "$values/deploy/values.yaml")

    def test_project_without_apps_generates_no_application(self):
        self.assertEqual(json.loads(render(self.expression, {"spec": {"targetCloud": "onprem"}})), [])


if __name__ == "__main__":
    unittest.main()
