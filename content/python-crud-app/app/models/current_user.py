"""The signed-in user.

Container Apps built-in authentication signs users in with Entra ID before a
request reaches the app, then passes the identity in X-MS-CLIENT-PRINCIPAL-*
headers. Those headers are only trustworthy behind that platform feature, so
the app never handles passwords or tokens itself.
"""

from flask import Request

LOCAL_DEVELOPMENT_USER = "local-developer"


def current_user_name(request: Request) -> str:
    return request.headers.get("X-MS-CLIENT-PRINCIPAL-NAME", LOCAL_DEVELOPMENT_USER)
