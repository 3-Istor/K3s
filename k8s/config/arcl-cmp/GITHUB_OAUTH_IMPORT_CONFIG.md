# Configuration CMP : OAuth GitHub et import de repositories

Cette configuration est préparée sur la branche de travail ; aucun Secret Vault,
cluster, callback GitHub ou déploiement n'a été modifié. L'import reste
explicitement désactivé par `env.backend.IMPORT_ENABLED: "false"`.

## Injection optionnelle et compatibilité

Le chart CMP rend `env.backend` et `extraEnv` ; il n'importe pas toutes les clés
d'un Secret par envFrom. Les nouveaux champs ont donc des références explicites,
avec `secretKeyRef.optional: true`, dans `cmp-values.yaml`.

Sans les deux nouveaux Secrets, Kubernetes laisse ces variables absentes : les
quatre réglages OAuth gardent leurs défauts vides dans CMP et la connexion GitHub
reste désactivée. Les autres réglages import gardent leurs défauts applicatifs,
et `IMPORT_ENABLED` reste false même si les Secrets sont renseignés. Les valeurs,
Secrets, allowlists Vault et routes existants ne sont pas remplacés.

Les deux manifestes sous `optional/` ne figurent pas dans `kustomization.yaml`.
Ils peuvent être inclus par une modification GitOps relue, chacun seulement après
préparation de toutes les clés de son chemin Vault. Le rôle existant
`arcl-cmp-role` autorise déjà la lecture de `kvv2/data/arcl-cmp/*`
(`terraform/policies/arcl_cmp.hcl`) ; aucune nouvelle permission Vault n'est ajoutée.
Les nouveaux chemins sont distincts de `kvv2/arcl-cmp/credentials`, dont le contenu
est déjà géré par le Terraform de plateforme.

## OAuth utilisateur GitHub

Manifeste opt-in : `optional/github-oauth-vaultsecret.yaml`.
Chemin Vault KV v2 : **kvv2/arcl-cmp/github-oauth**.
Secret Kubernetes produit : **arcl-cmp-github-oauth**, namespace arcl-cmp.

| Variable backend | Clé Vault / Secret | Valeur à préparer hors Git |
|---|---|---|
| GITHUB_OAUTH_CLIENT_ID | github-oauth-client-id | Client ID OAuth de CNP-Portal, distinct de son App ID |
| GITHUB_OAUTH_CLIENT_SECRET | github-oauth-client-secret | Client secret OAuth protégé, distinct de la clé PEM de l'App |
| GITHUB_OAUTH_REDIRECT_URI | github-oauth-redirect-uri | https://cmp.3istor.com/api/auth/github/callback |
| GITHUB_OAUTH_TOKEN_KEY | github-oauth-token-key | Clé Fernet stable, distincte des credentials GitHub, conservée hors Git |

Pour un autre hostname CMP, utiliser son origine HTTPS publique avec le même
chemin `/api/auth/github/callback`, et faire enregistrer cette URL exacte dans
les callbacks GitHub de la même App. Les routes Next.js `/api/auth/github/*`
réutilisent le routage frontend `/api/auth` existant ; le callback ne vise pas
FastAPI ni Keycloak. Le frontend dispose déjà de son origine publique
NEXTAUTH_URL ; les nouvelles routes doivent respecter cette configuration.

La clé Fernet chiffre les grants OAuth persistés dans la base CMP. Elle doit
rester identique entre redémarrages et réplicas utilisant cette base ; son
remplacement exige une stratégie de rotation ou une reconnexion des utilisateurs.
Ne pas y substituer la clé privée GitHub App ou le secret client OAuth. La
migration Alembic des tables OAuth doit être exécutée par le mécanisme de
migration CMP habituel avant utilisation du nouveau parcours.

Ajouter le manifeste Vault après préparation des quatre clés ne configure aucun
broker ou flow SSO, et n'active pas l'import. Un redémarrage contrôlé du backend
est nécessaire après injection/changement de variables d'environnement.

## Réglages de la CI d'import

Manifeste opt-in : `optional/repository-import-vaultsecret.yaml`.
Chemin Vault KV v2 : **kvv2/arcl-cmp/repository-import**.
Secret Kubernetes produit : **arcl-cmp-repository-import**, namespace arcl-cmp.

Toutes les clés suivantes sont attendues par ce manifeste lorsqu'il est inclus.
Les valeurs publiques indiquées correspondent aux défauts compatibles ; les SHA,
URLs et token doivent être ceux de la configuration approuvée, jamais des valeurs
factices. Une clé absente laisse le défaut applicatif ; une clé présente avec
une chaîne vide n'est pas équivalente. En particulier `import-max-image-bytes`
doit contenir un entier valide, par exemple `1073741824`, jamais une chaîne vide.
Le flag booléen IMPORT_ENABLED n'est volontairement pas mappé depuis un Secret.

| Variable backend | Clé Vault / Secret | Valeur / contrat |
|---|---|---|
| IMPORT_WORKFLOW_REPO | import-workflow-repo | 3-Istor/extern-project-analyzer |
| IMPORT_WORKFLOW_REF | import-workflow-ref | main, ou branche CI explicitement approuvée et épinglée |
| IMPORT_DISPATCH_WORKFLOW | import-dispatch-workflow | docker-image.yml |
| IMPORT_WORKFLOW_SHA | import-workflow-sha | SHA Git exact approuvé du caller et du workflow réutilisable |
| IMPORT_CHART_SHA | import-chart-sha | SHA Git exact approuvé d'infra-templates |
| IMPORT_OIDC_AUDIENCE | import-oidc-audience | cnp-repository-import, identique à la variable GitHub |
| IMPORT_USER_AUDIENCE | import-user-audience | account, audience CNP existante |
| IMPORT_IMAGE_PREFIX | import-image-prefix | ghcr.io/3-istor/cnp-imports |
| IMPORT_MAX_IMAGE_BYTES | import-max-image-bytes | 1073741824, sauf autre limite approuvée |
| IMPORT_DOMAIN | import-domain | 3istor.com |
| IMPORT_ALLOWED_PROJECT | import-allowed-project | Chaîne vide sur le CMP partagé ; joetest uniquement sur une instance CMP dédiée à la recette |
| IMPORT_CALLBACK_URL | import-callback-url | Base HTTPS des seuls callbacks worker, terminée par /api |
| IMPORT_ARGOCD_URL | import-argocd-url | Origine HTTPS du serveur API Argo CD |
| IMPORT_ARGOCD_TOKEN | import-argocd-token | Token court protégé du compte API cmp-import |

`IMPORT_ALLOWED_PROJECT` restreint aussi les mutations de projet et du catalogue :
le laisser vide sur le CMP partagé conserve leur comportement habituel.

`IMPORT_ENABLED` n'est pas lu depuis ce Secret. Son unique valeur dans la base
reste false ; l'activation ultérieure nécessite une modification explicite et
relue de cette valeur après tous les prérequis et le preflight.

Le callback worker est distinct du callback OAuth utilisateur. Il doit accepter
les JWT OIDC GitHub Actions et atteindre uniquement les routes worker du backend.
Le routage API public existant utilise une validation JWT Keycloak ; il ne faut
pas supposer qu'un JWT GitHub y sera accepté. Le proxy dédié de callbacks décrit
dans la recette CMP fournit ce chemin ; aucune route ou politique d'authentification
existante n'est assouplie par ces mappings.

Les variables GitHub `CMP_IMPORT_API_URL` et `CMP_IMPORT_OIDC_AUDIENCE` doivent
correspondre aux réglages backend. Le registre et les quatre générateurs Argo
restent sur main ; leurs changements compatibles, le chart approuvé et le module
app-templates en mode existing doivent être livrés par leur chemin normal avant
l'import. Aucun profil ne repointe l'Application argocd.

## Accès déjà injectés

Les mappings existants de `cmp-values.yaml` couvrent déjà :

- Terraform : TF_BACKEND_S3_ENABLED=true, bucket, région, préfixe et credentials S3 ;
- Vault : URL et token ; Cloudflare : token, compte et zone ;
- Keycloak : URL, client CNP et credentials administrateur applicatif existants ;
- GitHub App : clé privée et installation plateforme pour chart/registre ;
- GHCR : username et token de lecture des images privées.

Ils restent inchangés. L'installation GitHub choisie par l'utilisateur est
persistée par CMP et réutilisée pour son repo externe ; elle ne remplace pas
l'installation plateforme configurée pour les ressources internes.

Le contrôle de configuration ne remplace ni l'OAuth utilisateur, ni les droits
courants sur le repo, ni l'accès réel S3. Le code refuse un import sans bucket S3
explicite. Aucun plan ou apply réel ne doit être exécuté pour vérifier ces mappings.

## Revue et vérification locale

Les tests K3s vérifient que les nouveaux env sont optionnels, que chaque clé
correspond à son manifeste dédié, que les ressources optionnelles restent hors
base et que l'import ne peut pas être activé implicitement par leur présence.
Le rendu du vrai chart CMP est comparé à la base : seuls le flag import false et
les nouvelles références optionnelles du conteneur backend doivent différer.
Les routes, Secrets existants et configuration frontend restent identiques.
