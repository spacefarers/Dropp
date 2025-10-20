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
    app.config.from_mapping(
        SECRET_KEY=config.secret_key,
        BLOB_READ_WRITE_TOKEN=config.blob_read_write_token,
        PRESIGN_TTL_SECONDS=config.presign_ttl_seconds,
        UPLOAD_POST_TTL_SECONDS=config.upload_post_ttl_seconds,
        CLERK_SECRET_KEY=config.clerk_secret_key,
        CLERK_PUBLISHABLE_KEY=config.clerk_publishable_key,
        CLERK_JWT_TEMPLATE=config.clerk_jwt_template,
        APP_REDIRECT_URI=config.app_redirect_uri,
    )

    # Initialize Mongo client and attach to the app for later reuse.
    mongo_client = MongoClient(config.mongo_uri, tz_aware=True)
    app.mongo_client = mongo_client
    app.mongo_db = mongo_client[config.mongo_db]

    CORS(app, supports_credentials=True)
    app.register_blueprint(api_bp)

    return app
