# Profil de recette joetest

Ce profil n’est pas activé automatiquement. Il doit être publié et approuvé avant
de modifier la source de l’Application Argo `argocd`. Pendant la préparation locale,
aucune Application du cluster n’a été modifiée.

Les quatre ApplicationSets utilisent `cnp-projects/main` pour tous les projets
sauf joetest, et `cnp-projects/import-fichier-joe-raph` pour joetest uniquement.
Son chart ImageUpdater est figé au commit K3s contenant l’exclusion des imports.
Le parent `apps` suit toujours main ; il respecte seulement path/targetRevision
du child `argocd` pour maintenir le profil de recette validé.

Génération depuis la branche import-fichier-joe-raph :

    python3 scripts/render_import_recipe.py --project joetest \
      --registry-ref import-fichier-joe-raph \
      --k3s-revision <SHA K3s revu contenant la protection ImageUpdater>

Le générateur refuse une autre branche locale et exige un SHA exact. Les tests
dans tests/test_import_recipe.py vérifient la sélection sans doublon, la branche
main des autres projets et le pin réservé à joetest.

Validation hors cluster, sans apply :

    kubectl kustomize --enable-helm --load-restrictor LoadRestrictionsNone \
      k8s/overlays/import-joetest > /tmp/argocd-import-joetest.yaml

L’activation nécessite une action administrateur autorisée sur l’Application
argocd : path=k8s/overlays/import-joetest et targetRevision=<SHA publié approuvé>.
Le compte API cmp-import a uniquement les lectures Argo et la gestion des
connexions de repos nécessaires. Son token court doit être émis par un
administrateur autorisé, jamais dérivé d’une clé serveur ni committé.

Le CMP de recette doit aussi utiliser CNP_REGISTRY_BRANCH=import-fichier-joe-raph
et IMPORT_ALLOWED_PROJECT=joetest. Les autres imports et les mutations de
projet/catalogue y sont refusés. Le guide complet est dans le repo analyzer :
docs/import-recipe-joetest.md.

Avant de revenir sur main, supprimer explicitement l’app de recette ou promouvoir
son record validé. Revenir sur main alors que le record n’existe que sur la branche
de recette peut supprimer l’app via le pruning GitOps. Aucun nettoyage destructif
n’est automatique.
