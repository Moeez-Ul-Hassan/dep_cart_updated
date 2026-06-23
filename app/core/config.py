from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "Enterprise Cart API"
    VERSION: str = "1.0.0"
    API_V1_STR: str = "/api/v1"
    
    DATABASE_URL: str = "mysql+pymysql://root:enterprise_password@localhost:3306/cart_db"
    REDIS_URL: str = "redis://localhost:6379/0" # Added for Idempotency Cache
    class Config:
        env_file = ".env"
        case_sensitive = True

settings = Settings()