# Accès Argo aux repositories importés

La base Argo conserve ses sources GitOps habituelles sur main. L'import exige
que les changements compatibles du registre, de l'ApplicationSet et du chart
soient disponibles par le chemin de livraison normal. Aucun overlay de recette
ne redirige l'Application argocd ni les générateurs du registre.

## Repo de 3-Istor ou repo externe

Pour le propriétaire GitHub exact `3-Istor` (comparaison insensible à la casse),
CMP n'appelle pas l'API de déclaration de repo Argo. Le template de credentials
existant `cnp-portal-github-creds` reste géré par la plateforme : Vault Secrets
Operator lit `kvv2/argocd/github-app` et matérialise ce Secret repo-creds dans le
namespace argocd. Le contrôle du repo et des droits utilisateur reste obligatoire.
Le template partagé n'est ni recréé ni modifié par l'import.

Pour un autre propriétaire, CMP vérifie à nouveau utilisateur, projet actif,
permissions sur le repo et révision source avant les effets externes. Il cherche
la connexion au repo avec le projet de l'import (paramètre de lecture
`appProject`) et crée uniquement une connexion manquante, avec `project`, l'URL HTTPS GitHub exacte, `githubAppID`, l'installation
GitHub propre à cet import et `githubAppPrivateKey`. Il ne transmet pas l'ID
d'installation fixe de l'organisation comme remplacement. Aucun upsert ne doit
écraser une connexion existante ; un désaccord demande une revue explicite.
Le POST scoped de v3.5.1 ne teste pas la connexion : CMP doit relire le repo avec
`appProject` et `forceRefresh=true`, puis exiger un état de connexion réussi.

L'AppProject tenant ne reçoit aucun wildcard de source : le chart
[cnp-project-base](https://github.com/3-Istor/cnp-project-base/blob/main/templates/app-project.yaml)
autorise infra-templates et chaque `apps[].repoURL` exact. Le générateur
cnp-project-appprojects transmet déjà ces URLs depuis le record validé. Les quatre
générateurs restent sur registry/main ; l'autorisation GitOps du nouveau repo
apparaît après la synchro de ce record, sans modification impérative du projet.

## Permissions de cmp-import

Le compte technique est API-only. La base autorise uniquement la lecture des
ApplicationSets cnp-apps/cnp-image-updaters, la lecture des Applications pour
suivre Synced/Healthy et get/create de connexions GitHub rattachées à un projet.
Elle n'accorde ni synchronisation, ni modification/suppression de connexion, ni
gestion des comptes. Le token court du compte reste un secret administrateur,
absent de Git et distinct de la clé GitHub App.

La configuration versionnée installe Argo CD **v3.5.1**. Dans cette version,
l'objet RBAC d'une connexion rattachée à un projet est
`<project>/https://github.com/<owner>/<repo>`, utilisé pour Create et Get. Le motif
`*/https://github.com/*` accepte les projets dynamiques du portail mais refuse une
connexion globale sans projet ainsi que les autres protocoles/hôtes. CMP conserve
la responsabilité de l'autorisation par utilisateur/projet/repo : cette règle
technique partagée n'est pas une preuve de droit utilisateur. Le code source et
le CLI de la version déclarée ont été vérifiés ; aucun état live n'a été interrogé.

Sources : [API repository v3.5.1](https://github.com/argoproj/argo-cd/blob/v3.5.1/server/repository/repository.go),
[schéma Repository](https://github.com/argoproj/argo-cd/blob/v3.5.1/pkg/apis/application/v1alpha1/repository_types.go),
[paramètres REST](https://github.com/argoproj/argo-cd/blob/v3.5.1/server/repository/repository.proto),
[stockage Secret](https://github.com/argoproj/argo-cd/blob/v3.5.1/util/db/repository_secrets.go),
[RBAC et glob](https://argo-cd.readthedocs.io/en/release-3.5/operator-manual/rbac/#glob-matching).

## Stockage de la clé et renouvellement

Le backend reçoit la clé GitHub App déjà protégée dans sa configuration serveur ;
le worker CI, les fichiers du repo importé et les tfvars publics ne la reçoivent
pas. Pour un repo externe, l'appel HTTPS authentifié à Argo transmet cette clé
avec l'App ID et l'installation vérifiée du job. Argo stocke cette configuration
dans son Secret Kubernetes de type repository, dans argocd, rattaché au projet et
à l'URL. Son repo-server utilise l'App et cette installation pour renouveler les
tokens d'installation GitHub ; aucun token GitHub temporaire ne remplace la clé.

Cette copie persistante de la clé dans un Secret Argo est un effet de sécurité à
relire : la clé appartient à l'App entière ; la portée projet/repo de la connexion
et l'installation sélectionnée ne réduisent pas cryptographiquement la portée de
la clé. Les droits de lecture des Secrets Argo, leur protection au repos, la
rotation et la révocation restent ceux de la plateforme. Ne journaliser ni clé,
ni token, ni corps de requête secret. L'import n'ajoute aucune permission Argo de
suppression automatique de ces connexions.

Les secrets runtime applicatifs et le pull GHCR suivent leur chemin Vault
existant ; ils ne sont pas des credentials de lecture Git Argo. L'import ne
configure aucun broker ou flow SSO. La préparation de cette branche n'a modifié
aucun Secret ni cluster réel.

## Contrôles locaux

`python3 -m unittest discover -s tests` vérifie les vrais templates et ConfigMaps.
Helm est requis pour les expressions Go. Définir `ARGOCD_BIN` sur le CLI v3.5.1
pour exécuter en plus validate/can sur le fichier RBAC local, avec kubeconfig et
configuration CLI vides. Ces commandes n'appellent pas le cluster. Le test couvre
les connexions avec projet, les refus globaux/hors GitHub, les opérations
update/delete et les mutations d'Applications interdites.

Configuration backend, secrets OAuth et réglages CI :
[guide CMP](../arcl-cmp/GITHUB_OAUTH_IMPORT_CONFIG.md).
