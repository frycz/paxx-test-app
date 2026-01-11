"""Auth feature dependencies - JWT validation for protected routes."""

import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from settings import settings

security = HTTPBearer()

_jwks_cache: dict | None = None


def _get_jwks_url() -> str:
    """Get the JWKS URL for the Cognito user pool."""
    return f"https://cognito-idp.{settings.cognito_region}.amazonaws.com/{settings.cognito_user_pool_id}/.well-known/jwks.json"


def _get_issuer() -> str:
    """Get the token issuer URL for the Cognito user pool."""
    return f"https://cognito-idp.{settings.cognito_region}.amazonaws.com/{settings.cognito_user_pool_id}"


async def _get_jwks() -> dict:
    """Fetch and cache JWKS from Cognito."""
    global _jwks_cache
    if _jwks_cache is not None:
        return _jwks_cache

    async with httpx.AsyncClient() as client:
        response = await client.get(_get_jwks_url())
        response.raise_for_status()
        _jwks_cache = response.json()
        return _jwks_cache


def _get_signing_key(token: str, jwks: dict) -> dict:
    """Find the signing key for a token from the JWKS."""
    unverified_header = jwt.get_unverified_header(token)
    kid = unverified_header.get("kid")

    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return key

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Unable to find signing key",
    )


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> dict:
    """FastAPI dependency for validating JWT tokens and extracting user info.

    Usage:
        @router.get("/protected")
        async def protected_route(user: dict = Depends(get_current_user)):
            return {"user_id": user["sub"]}
    """
    token = credentials.credentials

    try:
        jwks = await _get_jwks()
        signing_key = _get_signing_key(token, jwks)

        payload = jwt.decode(
            token,
            signing_key,
            algorithms=["RS256"],
            audience=settings.cognito_client_id,
            issuer=_get_issuer(),
            options={"verify_at_hash": False},
        )

        # Cognito access tokens use "client_id" instead of "aud"
        # and id tokens use "aud", so we verify both cases
        token_use = payload.get("token_use")
        if token_use == "access":
            if payload.get("client_id") != settings.cognito_client_id:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid token audience",
                )
        elif token_use == "id":
            if payload.get("aud") != settings.cognito_client_id:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid token audience",
                )

        return {
            "sub": payload.get("sub"),
            "email": payload.get("email"),
            "email_verified": payload.get("email_verified"),
            "token_use": token_use,
        }
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid or expired token: {e}",
        )
    except httpx.HTTPError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to validate token",
        )
