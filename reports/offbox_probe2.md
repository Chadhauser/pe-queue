# Off-box signature probe 2026-11-16 09:54 UTC
```
boto3 1.34.46 botocore 1.34.46 endpoint https://eu2.contabostorage.com
Traceback (most recent call last):
  File "<stdin>", line 6, in <module>
  File "/usr/lib/python3/dist-packages/botocore/config.py", line 268, in __init__
    self._user_provided_options = self._record_user_provided_options(
                                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3/dist-packages/botocore/config.py", line 301, in _record_user_provided_options
    raise TypeError(f"Got unexpected keyword argument '{key}'")
TypeError: Got unexpected keyword argument 'request_checksum_calculation'
```
no client setting worked (see the five FAIL lines): if all five say SignatureDoesNotMatch the secret in .env differs from the panel
