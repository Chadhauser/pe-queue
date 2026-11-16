# Off-box signature probe 2026-11-16 09:56 UTC
```
boto3 1.34.46 botocore 1.34.46 endpoint https://eu2.contabostorage.com
FAIL v4 path default region: An error occurred (SignatureDoesNotMatch) when calling the ListBuckets operation: None
FAIL v4 virtual-host: An error occurred (SignatureDoesNotMatch) when calling the ListBuckets operation: None
FAIL v2 signature path: An error occurred (SignatureDoesNotMatch) when calling the ListBuckets operation: None
FAIL v4 region eu2 path: An error occurred (SignatureDoesNotMatch) when calling the ListBuckets operation: None
FAIL v4 region us-east-1 path: An error occurred (SignatureDoesNotMatch) when calling the ListBuckets operation: None
WORKING: None
```
no client setting worked (see the five FAIL lines): if all five say SignatureDoesNotMatch the secret in .env differs from the panel
