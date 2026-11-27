from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str
    jwt_secret: str
    jwt_expire_minutes: int = 60 * 24 * 7
    cors_origins: str = "*"
    app_env: str = 'production'
    superadmin_email: str | None = None
    superadmin_password: str | None = None

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
