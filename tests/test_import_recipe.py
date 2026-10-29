"""The branch recipe must select only its one project from the test registry."""

import fnmatch
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml

from test_application_import import render

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("recipe", ROOT / "scripts/render_import_recipe.py")
recipe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recipe)


class ImportRecipeTests(unittest.TestCase):
    def test_other_projects_keep_following_main_without_duplicate_test_record(self):
        for filename in ["applicationset-projects.yaml", "applicationset-apps.yaml", "applicationset-image-updaters.yaml"]:
            for document in yaml.safe_load_all((ROOT / "k8s/config/argocd" / filename).read_text()):
                generators = recipe.recipe_generators(document["spec"]["generators"], "joetest", "import-fichier-joe-raph")
                selected = []
                for generator in generators:
                    for git in recipe.git_nodes(generator):
                        for project in ["joetest", "sandbox", "production"]:
                            path = f"registry/projects/{project}.yaml"
                            includes = any(fnmatch.fnmatch(path, item["path"]) for item in git["files"] if not item.get("exclude"))
                            excludes = any(fnmatch.fnmatch(path, item["path"]) for item in git["files"] if item.get("exclude"))
                            if includes and not excludes:
                                selected.append((project, git["revision"]))
                self.assertCountEqual(selected, [("joetest", "import-fichier-joe-raph"), ("sandbox", "main"), ("production", "main")])

    def test_joetest_overlay_renders_offline_with_all_recipe_patches(self):
        # Render the real patches against their local targets. The Argo install
        # resources are unrelated to this recipe and would require remote fetches.
        resources = ["apps.yaml", "applicationset-projects.yaml",
                     "applicationset-apps.yaml", "applicationset-image-updaters.yaml"]
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            base = workspace / "k8s/config/argocd"
            base.mkdir(parents=True)
            for name in resources:
                shutil.copyfile(ROOT / "k8s/config/argocd" / name, base / name)
            (base / "kustomization.yaml").write_text(yaml.safe_dump({
                "apiVersion": "kustomize.config.k8s.io/v1beta1",
                "kind": "Kustomization", "resources": resources,
            }))
            overlay = workspace / "k8s/overlays/import-joetest"
            shutil.copytree(ROOT / "k8s/overlays/import-joetest", overlay)
            result = subprocess.run(
                [os.environ.get("KUBECTL_BIN", "kubectl"), "kustomize",
                 "--enable-helm", "--load-restrictor", "LoadRestrictionsNone", str(overlay)],
                capture_output=True, text=True, check=True, timeout=30,
                env={**os.environ, "KUBECONFIG": os.devnull},
            )
        objects = {obj["metadata"]["name"]: obj
                   for obj in yaml.safe_load_all(result.stdout) if obj}
        self.assertEqual(set(objects), {"apps", "cnp-project-appprojects",
                                       "cnp-project-systems", "cnp-apps", "cnp-image-updaters"})
        for filename in resources[1:]:
            for original in yaml.safe_load_all((ROOT / "k8s/config/argocd" / filename).read_text()):
                rendered = objects[original["metadata"]["name"]]
                self.assertEqual(rendered["metadata"]["namespace"], "argocd")
                self.assertEqual(rendered["spec"]["generators"], recipe.recipe_generators(
                    original["spec"]["generators"], "joetest", "import-fichier-joe-raph"))
                self.assertEqual(rendered["metadata"]["annotations"]["cnp.3istor.com/import-test-project"], "joetest")
                self.assertEqual(rendered["metadata"]["annotations"]["cnp.3istor.com/import-test-registry"], "import-fichier-joe-raph")
        parent = objects["apps"]["spec"]
        self.assertEqual(parent["source"]["path"], "k8s/app")
        self.assertEqual(parent["source"]["targetRevision"], "HEAD")
        self.assertIn("RespectIgnoreDifferences=true", parent["syncPolicy"]["syncOptions"])
        self.assertEqual(parent["ignoreDifferences"], [{
            "group": "argoproj.io", "kind": "Application", "name": "argocd",
            "namespace": "argocd", "jsonPointers": ["/spec/source/path", "/spec/source/targetRevision"],
        }])

    def test_only_test_project_uses_the_reviewed_updater_chart(self):
        operations = yaml.safe_load((ROOT / "k8s/overlays/import-joetest/cnp-image-updaters.patch.yaml").read_text())
        expression = next(item["value"] for item in operations if item["path"] == "/spec/template/spec/source/targetRevision")
        pinned = next(item["value"]["cnp.3istor.com/import-test-k3s-revision"] for item in operations if item["path"] == "/metadata/annotations")
        self.assertEqual(render(expression, {"metadata": {"name": "joetest"}}), pinned)
        self.assertEqual(render(expression, {"metadata": {"name": "production"}}), "HEAD")


if __name__ == "__main__":
    unittest.main()
