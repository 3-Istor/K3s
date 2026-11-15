# Init S3

## Current created Bucket:

```
user-avatars
cnp-app-icons
cnp-project-exports
```

## Current created Keys:

```
user-avatars-key
cnp-app-icons-key
cnp-project-exports-key
```

## Bucket for a CMP feature (app icons, project exports)

One bucket and one key per feature, read and write on that bucket only, the
key in Vault `kvv2/arcl-cmp/credentials` and declared in
`terraform/secret_templates.tf` so an apply keeps it. Project exports
(EU Data Act, B1):

```sh
kubectl -n garage-s3 exec garage-0 -- /garage bucket create cnp-project-exports
kubectl -n garage-s3 exec garage-0 -- /garage key create cnp-project-exports-key
kubectl -n garage-s3 exec garage-0 -- /garage bucket allow --read --write cnp-project-exports --key cnp-project-exports-key
# Key ID and secret from the output of key create (or: /garage key info --show-secret cnp-project-exports-key)
vault kv patch kvv2/arcl-cmp/credentials \
  export-s3-access-key-id=GK... export-s3-secret-access-key=...
```

Then copy both values into the untracked `terraform/secrets_variables.tfvars`
(`export_s3_access_key_id`, `export_s3_secret_key`) and check that
`terraform plan -target=vault_kv_secret_v2.arcl_cmp_creds` is a no-op on
values. No website alias: archives are only reached through presigned links.

## Create an access key

```sh
kubectl exec -it garage-0 -n garage-s3 -- /garage key new --name project-access-key
```

## Create a S3 Bucket

```sh
kubectl exec -it garage-0 -n garage-s3 -- /garage bucket create project-bucket
```

## Config S3 Access Perms

```sh
kubectl exec -it garage-0 -n garage-s3 -- /garage bucket allow project-bucket --read --write --owner --key project-key
```

## Allow public RO

```sh
kubectl exec -it garage-0 -n garage-s3 -- /garage bucket allow user-avatars --key user-avatars-key --read
```
