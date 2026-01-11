"""Auth feature services - AWS Cognito operations."""

import base64
import hashlib
import hmac

import boto3

from settings import settings


class CognitoService:
    """AWS Cognito service for user authentication and management."""

    def __init__(self):
        self.client = boto3.client(
            "cognito-idp", region_name=settings.cognito_region
        )
        self.user_pool_id = settings.cognito_user_pool_id
        self.client_id = settings.cognito_client_id
        self.client_secret = settings.cognito_client_secret

    def _get_secret_hash(self, username: str) -> str:
        """Generate HMAC-SHA256 secret hash for Cognito API calls."""
        message = username + self.client_id
        dig = hmac.new(
            self.client_secret.encode("utf-8"),
            message.encode("utf-8"),
            hashlib.sha256,
        ).digest()
        return base64.b64encode(dig).decode()

    def sign_up(self, email: str, password: str) -> dict:
        """Register a new user."""
        return self.client.sign_up(
            ClientId=self.client_id,
            SecretHash=self._get_secret_hash(email),
            Username=email,
            Password=password,
            UserAttributes=[{"Name": "email", "Value": email}],
        )

    def confirm_sign_up(self, email: str, code: str) -> dict:
        """Confirm user registration with verification code."""
        return self.client.confirm_sign_up(
            ClientId=self.client_id,
            SecretHash=self._get_secret_hash(email),
            Username=email,
            ConfirmationCode=code,
        )

    def resend_confirmation_code(self, email: str) -> dict:
        """Resend verification code to user email."""
        return self.client.resend_confirmation_code(
            ClientId=self.client_id,
            SecretHash=self._get_secret_hash(email),
            Username=email,
        )

    def initiate_auth(self, email: str, password: str) -> dict:
        """Authenticate user with email and password."""
        return self.client.initiate_auth(
            ClientId=self.client_id,
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={
                "USERNAME": email,
                "PASSWORD": password,
                "SECRET_HASH": self._get_secret_hash(email),
            },
        )

    def refresh_token(self, refresh_token: str, username: str) -> dict:
        """Refresh access token using refresh token.

        Note: username must be the Cognito sub (UUID), not the email.
        For REFRESH_TOKEN_AUTH, the secret hash must use the actual username.
        """
        return self.client.initiate_auth(
            ClientId=self.client_id,
            AuthFlow="REFRESH_TOKEN_AUTH",
            AuthParameters={
                "REFRESH_TOKEN": refresh_token,
                "SECRET_HASH": self._get_secret_hash(username),
            },
        )

    def global_sign_out(self, access_token: str) -> dict:
        """Sign out user from all sessions."""
        return self.client.global_sign_out(AccessToken=access_token)

    def forgot_password(self, email: str) -> dict:
        """Initiate password reset flow."""
        return self.client.forgot_password(
            ClientId=self.client_id,
            SecretHash=self._get_secret_hash(email),
            Username=email,
        )

    def confirm_forgot_password(
        self, email: str, code: str, new_password: str
    ) -> dict:
        """Complete password reset with verification code."""
        return self.client.confirm_forgot_password(
            ClientId=self.client_id,
            SecretHash=self._get_secret_hash(email),
            Username=email,
            ConfirmationCode=code,
            Password=new_password,
        )

    def change_password(
        self, access_token: str, previous_password: str, proposed_password: str
    ) -> dict:
        """Change password for authenticated user."""
        return self.client.change_password(
            PreviousPassword=previous_password,
            ProposedPassword=proposed_password,
            AccessToken=access_token,
        )

    def delete_user(self, access_token: str) -> dict:
        """Delete user account."""
        return self.client.delete_user(AccessToken=access_token)


cognito_service = CognitoService()
