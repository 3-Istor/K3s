# Init S3

## Current created Bucket:

```
user-avatars
```

## Current created Keys:

```
user-avatars-key
```

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
