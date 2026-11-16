# Off-box signature probe 2026-11-16 09:22 UTC
```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/usr/lib/python3/dist-packages/boto3/__init__.py", line 17, in <module>
    from boto3.session import Session
  File "/usr/lib/python3/dist-packages/boto3/session.py", line 17, in <module>
    import botocore.session
  File "/usr/lib/python3/dist-packages/botocore/session.py", line 26, in <module>
    import botocore.client
  File "/usr/lib/python3/dist-packages/botocore/client.py", line 15, in <module>
    from botocore import waiter, xform_name
  File "/usr/lib/python3/dist-packages/botocore/waiter.py", line 18, in <module>
    from botocore.docs.docstring import WaiterDocstring
  File "/usr/lib/python3/dist-packages/botocore/docs/__init__.py", line 15, in <module>
    from botocore.docs.service import ServiceDocumenter
  File "/usr/lib/python3/dist-packages/botocore/docs/service.py", line 14, in <module>
    from botocore.docs.client import (
  File "/usr/lib/python3/dist-packages/botocore/docs/client.py", line 18, in <module>
    from botocore.docs.example import ResponseExampleDocumenter
  File "/usr/lib/python3/dist-packages/botocore/docs/example.py", line 13, in <module>
    from botocore.docs.shape import ShapeDocumenter
  File "/usr/lib/python3/dist-packages/botocore/docs/shape.py", line 19, in <module>
    from botocore.utils import is_json_value_header
  File "/usr/lib/python3/dist-packages/botocore/utils.py", line 39, in <module>
    import botocore.httpsession
  File "/usr/lib/python3/dist-packages/botocore/httpsession.py", line 45, in <module>
    from urllib3.contrib.pyopenssl import (
  File "/usr/lib/python3/dist-packages/urllib3/contrib/pyopenssl.py", line 43, in <module>
    import OpenSSL.SSL  # type: ignore[import]
    ^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3/dist-packages/OpenSSL/__init__.py", line 8, in <module>
    from OpenSSL import SSL, crypto
  File "/usr/lib/python3/dist-packages/OpenSSL/SSL.py", line 20, in <module>
    from OpenSSL.crypto import (
  File "/usr/lib/python3/dist-packages/OpenSSL/crypto.py", line 765, in <module>
    class X509Extension:
  File "/usr/lib/python3/dist-packages/OpenSSL/crypto.py", line 846, in X509Extension
    _lib.GEN_EMAIL: "email",
    ^^^^^^^^^^^^^^
AttributeError: module 'lib' has no attribute 'GEN_EMAIL'
```
no client setting worked: the secret in .env does not match the panel
