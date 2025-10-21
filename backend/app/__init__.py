from __future__ import annotations

from flask import Flask
from flask_cors import CORS
from pymongo import MongoClient

from config import Config
from .routes import api_bp


def create_app(preconfigured: Config | None = None) -> Flask:
    """
    Application factory used by both the CLI and the WSGI server.
    """
    config = preconfigured or Config()

    app = Flask(__name__)
    jwt_secret_key = config.jwt_secret_key or config.secret_key
    app.config.from_mapping(
        SECRET_KEY=config.secret_key,
        JWT_SECRET_KEY=jwt_secret_key,
        BLOB_READ_WRITE_TOKEN=config.blob_read_write_token,
        PRESIGN_TTL_SECONDS=config.presign_ttl_seconds,
        UPLOAD_POST_TTL_SECONDS=config.upload_post_ttl_seconds,
        FIREBASE_SERVICE_ACCOUNT_BASE64=config.firebase_service_account_base64,
        APP_REDIRECT_URI=config.app_redirect_uri,
    )

    # Initialize Mongo client and attach to the app for later reuse.
    mongo_client = MongoClient(config.mongo_uri, tz_aware=True)
    app.mongo_client = mongo_client
    app.mongo_db = mongo_client[config.mongo_db]

    default_cors_origins = (
        "http://localhost:5173",
        "http://127.0.0.1:5173",
        "https://dropp.yangm.tech",
    )
    cors_origins = config.cors_allowed_origins or default_cors_origins
    CORS(
        app,
        supports_credentials=True,
        origins=cors_origins,
        allow_headers=["Content-Type", "Authorization"],
        methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    )
    app.register_blueprint(api_bp)

    return app
