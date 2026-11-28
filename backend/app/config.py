from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str
    jwt_secret: str
    jwt_expire_minutes: int = 60 * 24 * 7
    cors_origins: str = "*"
    app_env: str = "production"
    superadmin_email: str | None = None
    superadmin_password: str | None = None
    superadmin_force_password_reset: bool = False

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @model_validator(mode="after")
    def validate_production_security(self):
        if self.superadmin_password and len(self.superadmin_password) < 12:
            raise ValueError("SUPERADMIN_PASSWORD must be at least 12 characters")

        if self.app_env.lower() == "production":
            origins = [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]
            if not origins or "*" in origins:
                raise ValueError(
                    "Production CORS_ORIGINS must list explicit trusted app origins; wildcard is forbidden"
                )
            if len(self.jwt_secret) < 32:
                raise ValueError("Production JWT_SECRET must be at least 32 characters")
            if self.superadmin_email and not self.superadmin_password:
                raise ValueError("SUPERADMIN_PASSWORD is required when SUPERADMIN_EMAIL is configured")

        return self


settings = Settings()
