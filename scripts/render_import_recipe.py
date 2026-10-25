"""Generate a GitOps recipe for one project; all other records keep following main."""

import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import subprocess

import yaml


ROOT = Path(__file__).resolve().parents[1]


def git_nodes(value):
    if isinstance(value, dict):
        if "git" in value:
            yield value["git"]
        for child in value.values():
            yield from git_nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from git_nodes(child)


def recipe_generators(generators, project, registry_ref):
    result = []
    path = f"registry/projects/{project}.yaml"
    for generator in generators:
        original = deepcopy(generator)
        recipe = deepcopy(generator)
        selected = False
        for first, second in zip(git_nodes(original), git_nodes(recipe)):
            if first.get("repoURL", "").removesuffix(".git") != "https://github.com/3-Istor/cnp-projects":
                continue
            if first.get("revision") != "main":
                raise ValueError("Unexpected production registry revision")
            first.setdefault("files", []).append({"path": path, "exclude": True})
            second["revision"] = registry_ref
            second["files"] = [{"path": path}]
            selected = True
        if not selected:
            raise ValueError("Project registry generator not found")
        result.extend([original, recipe])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default="joetest")
    parser.add_argument("--registry-ref", default="import-fichier-joe-raph")
    parser.add_argument("--k3s-revision", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,38}[a-z0-9]", args.project):
        parser.error("Invalid project")
    if not re.fullmatch(r"[A-Za-z0-9/_-]+", args.registry_ref) or ".." in args.registry_ref:
        parser.error("Invalid registry ref")
    if not re.fullmatch(r"[a-f0-9]{40}", args.k3s_revision):
        parser.error("Pin the image updater chart to an exact K3s commit")
    branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
    if branch != "import-fichier-joe-raph":
        parser.error("Use the import-fichier-joe-raph branch")
    base = ROOT / "k8s/config/argocd"
    output = ROOT / "k8s/overlays" / ("import-" + args.project)
    output.mkdir(parents=True, exist_ok=True)
    patches = []
    for filename in ["applicationset-projects.yaml", "applicationset-apps.yaml", "applicationset-image-updaters.yaml"]:
        for document in yaml.safe_load_all((base / filename).read_text()):
            operations = [{"op": "replace", "path": "/spec/generators", "value": recipe_generators(document["spec"]["generators"], args.project, args.registry_ref)}]
            annotations = {**document.get("metadata", {}).get("annotations", {}),
                           "cnp.3istor.com/import-test-project": args.project,
                           "cnp.3istor.com/import-test-registry": args.registry_ref,
                           "cnp.3istor.com/import-test-k3s-revision": args.k3s_revision}
            operations.append({"op": "add", "path": "/metadata/annotations", "value": annotations})
            if filename == "applicationset-image-updaters.yaml":
                revision = '{{ if eq .metadata.name "' + args.project + '" }}' + args.k3s_revision + '{{ else }}HEAD{{ end }}'
                operations.append({"op": "replace", "path": "/spec/template/spec/source/targetRevision", "value": revision})
            patch = document["metadata"]["name"] + ".patch.yaml"
            (output / patch).write_text(yaml.safe_dump(operations, sort_keys=False))
            patches.append({"target": {"group": "argoproj.io", "version": "v1alpha1", "kind": "ApplicationSet", "name": document["metadata"]["name"]}, "path": patch})
    # The parent keeps following main for every other infrastructure Application.
    # Only this Argo config Application may retain its reviewed recipe path/ref.
    parent_patch = [
        {"op": "add", "path": "/spec/ignoreDifferences", "value": [{"group": "argoproj.io", "kind": "Application", "name": "argocd", "namespace": "argocd", "jsonPointers": ["/spec/source/path", "/spec/source/targetRevision"]}]},
        {"op": "add", "path": "/spec/syncPolicy/syncOptions", "value": ["CreateNamespace=true", "RespectIgnoreDifferences=true"]},
    ]
    (output / "apps.patch.yaml").write_text(yaml.safe_dump(parent_patch, sort_keys=False))
    patches.append({"target": {"group": "argoproj.io", "version": "v1alpha1", "kind": "Application", "name": "apps"}, "path": "apps.patch.yaml"})
    (output / "kustomization.yaml").write_text(yaml.safe_dump({"apiVersion": "kustomize.config.k8s.io/v1beta1", "kind": "Kustomization", "namespace": "argocd", "resources": ["../../config/argocd"], "patches": patches}, sort_keys=False))
    print(json.dumps({"project": args.project, "registry_ref": args.registry_ref, "k3s_revision": args.k3s_revision, "path": str(output.relative_to(ROOT))}))


if __name__ == "__main__":
    main()
