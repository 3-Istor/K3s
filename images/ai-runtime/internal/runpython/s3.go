package runpython

import (
	"bytes"
	"context"
	"fmt"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/minio/minio-go/v7/pkg/lifecycle"
)

// S3Store keeps artifacts in the ai-artifacts bucket of the Ceph RGW.
type S3Store struct {
	client *minio.Client
	bucket string
}

// NewS3Store connects with the ObjectBucketClaim's keys (path-style, as RGW expects).
func NewS3Store(endpoint string, secure bool, bucket, accessKey, secretKey string) (*S3Store, error) {
	c, err := minio.New(endpoint, &minio.Options{
		Creds:        credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure:       secure,
		Region:       "us-east-1",
		BucketLookup: minio.BucketLookupPath,
	})
	if err != nil {
		return nil, err
	}
	return &S3Store{client: c, bucket: bucket}, nil
}

// EnsureExpiry makes the bucket delete objects older than days (idempotent).
func (s *S3Store) EnsureExpiry(ctx context.Context, days int) error {
	cfg := lifecycle.NewConfiguration()
	cfg.Rules = []lifecycle.Rule{{
		ID:         "expire-artifacts",
		Status:     "Enabled",
		RuleFilter: lifecycle.Filter{Prefix: ""},
		Expiration: lifecycle.Expiration{Days: lifecycle.ExpirationDays(days)},
	}}
	return s.client.SetBucketLifecycle(ctx, s.bucket, cfg)
}

// Put stores one artifact.
func (s *S3Store) Put(ctx context.Context, key, contentType string, data []byte) error {
	_, err := s.client.PutObject(ctx, s.bucket, key, bytes.NewReader(data), int64(len(data)), minio.PutObjectOptions{ContentType: contentType})
	return err
}

// Get opens one artifact.
func (s *S3Store) Get(ctx context.Context, key string) (*Object, error) {
	info, err := s.client.StatObject(ctx, s.bucket, key, minio.StatObjectOptions{})
	if err != nil {
		if minio.ToErrorResponse(err).StatusCode == 404 {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("stat %s: %w", key, err)
	}
	obj, err := s.client.GetObject(ctx, s.bucket, key, minio.GetObjectOptions{})
	if err != nil {
		return nil, fmt.Errorf("get %s: %w", key, err)
	}
	return &Object{Body: obj, Size: info.Size, LastModified: info.LastModified}, nil
}
