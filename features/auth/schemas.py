"""Auth feature schemas."""

from pydantic import BaseModel, EmailStr


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str


class RegisterResponse(BaseModel):
    message: str
    user_sub: str


class ConfirmRequest(BaseModel):
    email: EmailStr
    code: str


class ConfirmResponse(BaseModel):
    message: str


class ResendConfirmationRequest(BaseModel):
    email: EmailStr


class ResendConfirmationResponse(BaseModel):
    message: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    id_token: str
    refresh_token: str
    expires_in: int
    token_type: str = "Bearer"


class RefreshRequest(BaseModel):
    username: str  # Cognito sub (UUID), not email
    refresh_token: str


class RefreshResponse(BaseModel):
    access_token: str
    id_token: str
    expires_in: int
    token_type: str = "Bearer"


class LogoutRequest(BaseModel):
    access_token: str


class LogoutResponse(BaseModel):
    message: str


class UserResponse(BaseModel):
    sub: str
    email: str | None
    email_verified: bool | None


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ForgotPasswordResponse(BaseModel):
    message: str


class ConfirmForgotPasswordRequest(BaseModel):
    email: EmailStr
    code: str
    new_password: str


class ConfirmForgotPasswordResponse(BaseModel):
    message: str


class ChangePasswordRequest(BaseModel):
    access_token: str
    previous_password: str
    new_password: str


class ChangePasswordResponse(BaseModel):
    message: str


class DeleteAccountRequest(BaseModel):
    access_token: str


class DeleteAccountResponse(BaseModel):
    message: str
