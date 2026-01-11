"""Auth feature API routes."""

from botocore.exceptions import ClientError
from fastapi import APIRouter, Depends, HTTPException, status

from features.auth.dependencies import get_current_user
from features.auth.schemas import (
    ChangePasswordRequest,
    ChangePasswordResponse,
    ConfirmForgotPasswordRequest,
    ConfirmForgotPasswordResponse,
    ConfirmRequest,
    ConfirmResponse,
    DeleteAccountRequest,
    DeleteAccountResponse,
    ForgotPasswordRequest,
    ForgotPasswordResponse,
    LoginRequest,
    LogoutRequest,
    LogoutResponse,
    RefreshRequest,
    RefreshResponse,
    RegisterRequest,
    RegisterResponse,
    ResendConfirmationRequest,
    ResendConfirmationResponse,
    TokenResponse,
    UserResponse,
)
from features.auth.services import cognito_service

router = APIRouter()


@router.post("/register", response_model=RegisterResponse)
def register(request: RegisterRequest):
    """Register a new user.

    Creates a new user account and sends a verification code to the email.
    """
    try:
        response = cognito_service.sign_up(request.email, request.password)
        return RegisterResponse(
            message="Registration successful. Please check your email for verification code.",
            user_sub=response["UserSub"],
        )
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        error_message = e.response["Error"]["Message"]

        if error_code == "UsernameExistsException":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An account with this email already exists",
            )
        elif error_code == "InvalidPasswordException":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message,
            )
        elif error_code == "TooManyRequestsException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please try again later.",
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Registration failed",
            )


@router.post("/confirm", response_model=ConfirmResponse)
def confirm(request: ConfirmRequest):
    """Confirm user registration.

    Verifies the user's email with the confirmation code sent during registration.
    """
    try:
        cognito_service.confirm_sign_up(request.email, request.code)
        return ConfirmResponse(message="Email confirmed successfully. You can now log in.")
    except ClientError as e:
        error_code = e.response["Error"]["Code"]

        if error_code == "CodeMismatchException":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid verification code",
            )
        elif error_code == "ExpiredCodeException":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Verification code has expired. Please request a new one.",
            )
        elif error_code == "UserNotFoundException":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )
        elif error_code == "NotAuthorizedException":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User is already confirmed",
            )
        elif error_code == "TooManyRequestsException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please try again later.",
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Confirmation failed",
            )


@router.post("/resend-confirmation", response_model=ResendConfirmationResponse)
def resend_confirmation(request: ResendConfirmationRequest):
    """Resend confirmation code.

    Sends a new verification code to the user's email.
    """
    try:
        cognito_service.resend_confirmation_code(request.email)
        return ResendConfirmationResponse(
            message="Verification code sent. Please check your email."
        )
    except ClientError as e:
        error_code = e.response["Error"]["Code"]

        if error_code == "UserNotFoundException":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )
        elif error_code == "InvalidParameterException":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User is already confirmed",
            )
        elif error_code == "LimitExceededException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Attempt limit exceeded. Please try again later.",
            )
        elif error_code == "TooManyRequestsException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please try again later.",
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to resend verification code",
            )


@router.post("/login", response_model=TokenResponse)
def login(request: LoginRequest):
    """Login with email and password.

    Returns access, ID, and refresh tokens on successful authentication.
    """
    try:
        response = cognito_service.initiate_auth(request.email, request.password)
        auth_result = response["AuthenticationResult"]
        return TokenResponse(
            access_token=auth_result["AccessToken"],
            id_token=auth_result["IdToken"],
            refresh_token=auth_result["RefreshToken"],
            expires_in=auth_result["ExpiresIn"],
        )
    except ClientError as e:
        error_code = e.response["Error"]["Code"]

        if error_code == "NotAuthorizedException":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password",
            )
        elif error_code == "UserNotConfirmedException":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Email not verified. Please confirm your email first.",
            )
        elif error_code == "UserNotFoundException":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password",
            )
        elif error_code == "TooManyRequestsException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please try again later.",
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Login failed",
            )


@router.post("/refresh", response_model=RefreshResponse)
def refresh(request: RefreshRequest):
    """Refresh access token.

    Uses the refresh token to obtain new access and ID tokens.
    The username must be the Cognito sub (UUID), not the email.
    """
    try:
        response = cognito_service.refresh_token(request.refresh_token, request.username)
        auth_result = response["AuthenticationResult"]
        return RefreshResponse(
            access_token=auth_result["AccessToken"],
            id_token=auth_result["IdToken"],
            expires_in=auth_result["ExpiresIn"],
        )
    except ClientError as e:
        error_code = e.response["Error"]["Code"]

        if error_code == "NotAuthorizedException":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired refresh token",
            )
        elif error_code == "UserNotFoundException":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )
        elif error_code == "TooManyRequestsException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please try again later.",
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Token refresh failed",
            )


@router.post("/logout", response_model=LogoutResponse)
def logout(request: LogoutRequest):
    """Logout user.

    Invalidates all tokens and signs out the user from all sessions.
    """
    try:
        cognito_service.global_sign_out(request.access_token)
        return LogoutResponse(message="Successfully logged out")
    except ClientError as e:
        error_code = e.response["Error"]["Code"]

        if error_code == "NotAuthorizedException":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired access token",
            )
        elif error_code == "TooManyRequestsException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please try again later.",
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Logout failed",
            )


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: dict = Depends(get_current_user)):
    """Get current user info.

    Returns the authenticated user's profile information.
    Requires a valid Bearer token in the Authorization header.
    """
    return UserResponse(
        sub=current_user["sub"],
        email=current_user.get("email"),
        email_verified=current_user.get("email_verified"),
    )


@router.post("/forgot-password", response_model=ForgotPasswordResponse)
def forgot_password(request: ForgotPasswordRequest):
    """Initiate password reset.

    Sends a password reset code to the user's email.
    Returns the same message even if the user doesn't exist (security).
    """
    try:
        cognito_service.forgot_password(request.email)
        return ForgotPasswordResponse(
            message="Password reset code sent. Please check your email."
        )
    except ClientError as e:
        error_code = e.response["Error"]["Code"]

        if error_code == "UserNotFoundException":
            # Return success message even if user not found to prevent email enumeration
            return ForgotPasswordResponse(
                message="Password reset code sent. Please check your email."
            )
        elif error_code == "InvalidParameterException":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User account is not in a valid state for password reset",
            )
        elif error_code == "LimitExceededException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Attempt limit exceeded. Please try again later.",
            )
        elif error_code == "TooManyRequestsException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please try again later.",
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to initiate password reset",
            )


@router.post("/confirm-forgot-password", response_model=ConfirmForgotPasswordResponse)
def confirm_forgot_password(request: ConfirmForgotPasswordRequest):
    """Complete password reset.

    Resets the user's password using the verification code.
    """
    try:
        cognito_service.confirm_forgot_password(
            request.email, request.code, request.new_password
        )
        return ConfirmForgotPasswordResponse(
            message="Password reset successfully. You can now log in with your new password."
        )
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        error_message = e.response["Error"]["Message"]

        if error_code == "CodeMismatchException":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid verification code",
            )
        elif error_code == "ExpiredCodeException":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Verification code has expired. Please request a new one.",
            )
        elif error_code == "UserNotFoundException":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )
        elif error_code == "InvalidPasswordException":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message,
            )
        elif error_code == "TooManyRequestsException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please try again later.",
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Password reset failed",
            )


@router.post("/change-password", response_model=ChangePasswordResponse)
def change_password(request: ChangePasswordRequest):
    """Change password.

    Changes the password for an authenticated user.
    """
    try:
        cognito_service.change_password(
            request.access_token, request.previous_password, request.new_password
        )
        return ChangePasswordResponse(message="Password changed successfully.")
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        error_message = e.response["Error"]["Message"]

        if error_code == "NotAuthorizedException":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid access token or incorrect current password",
            )
        elif error_code == "InvalidPasswordException":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=error_message,
            )
        elif error_code == "LimitExceededException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Attempt limit exceeded. Please try again later.",
            )
        elif error_code == "TooManyRequestsException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please try again later.",
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Password change failed",
            )


@router.delete("/delete-account", response_model=DeleteAccountResponse)
def delete_account(request: DeleteAccountRequest):
    """Delete user account.

    Permanently deletes the user's account.
    """
    try:
        cognito_service.delete_user(request.access_token)
        return DeleteAccountResponse(message="Account deleted successfully.")
    except ClientError as e:
        error_code = e.response["Error"]["Code"]

        if error_code == "NotAuthorizedException":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired access token",
            )
        elif error_code == "UserNotFoundException":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )
        elif error_code == "TooManyRequestsException":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please try again later.",
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Account deletion failed",
            )
