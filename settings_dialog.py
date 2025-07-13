import json
import os
from PyQt6.QtWidgets import (QDialog, QVBoxLayout, QLabel, QLineEdit, QHBoxLayout,
                             QCheckBox, QPushButton, QFormLayout)

APP_SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/Dropp")
SETTINGS_FILE = os.path.join(APP_SUPPORT_DIR, "settings.json")

class SettingsDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Settings")
        self.settings = self.load_settings()
        print(self.settings)

        self.s3_enabled_checkbox = QCheckBox("Enable S3")
        self.s3_enabled_checkbox.setChecked(self.settings.get("s3_enabled", False))
        self.access_key_input = QLineEdit(self.settings.get("aws_access_key", ""))
        self.secret_key_input = QLineEdit(self.settings.get("aws_secret_key", ""))
        self.bucket_name_input = QLineEdit(self.settings.get("s3_bucket_name", ""))
        self.region_input = QLineEdit(self.settings.get("aws_region", ""))
        self.gateway_url_input = QLineEdit(self.settings.get("s3_gateway_url", ""))

        self.save_button = QPushButton("Save")
        self.cancel_button = QPushButton("Cancel")

        # Disable S3 fields initially
        self.toggle_s3_fields(2 if self.settings.get("s3_enabled", False) else 0)

        layout = QVBoxLayout(self)
        form_layout = QFormLayout()
        form_layout.addRow("Enable S3:", self.s3_enabled_checkbox)
        form_layout.addRow("Access Key:", self.access_key_input)
        form_layout.addRow("Secret Key:", self.secret_key_input)
        form_layout.addRow("Bucket Name:", self.bucket_name_input)
        form_layout.addRow("Region:", self.region_input)
        form_layout.addRow("Gateway URL:", self.gateway_url_input)
        layout.addLayout(form_layout)

        button_layout = QHBoxLayout()
        button_layout.addWidget(self.save_button)
        button_layout.addWidget(self.cancel_button)
        layout.addLayout(button_layout)

        self.cancel_button.clicked.connect(self.reject)
        self.save_button.clicked.connect(self.save_settings_and_accept)

        self.s3_enabled_checkbox.stateChanged.connect(self.toggle_s3_fields)
        self.setLayout(layout)

    def toggle_s3_fields(self, state):
        enabled = state == 2 # 2 is checked, 0 is unchecked
        self.access_key_input.setEnabled(enabled)
        self.secret_key_input.setEnabled(enabled)
        self.bucket_name_input.setEnabled(enabled)
        self.region_input.setEnabled(enabled)
        self.gateway_url_input.setEnabled(enabled)
        # Also toggle cloud upload button in shelf window if available
        if hasattr(self.parent(), 'toggle_cloud_upload_button'):
            self.parent().toggle_cloud_upload_button(enabled)

    def save_settings_and_accept(self):
        self.settings["s3_enabled"] = self.s3_enabled_checkbox.isChecked()
        self.settings["aws_access_key"] = self.access_key_input.text()
        self.settings["aws_secret_key"] = self.secret_key_input.text()
        self.settings["s3_bucket_name"] = self.bucket_name_input.text()
        self.settings["aws_region"] = self.region_input.text()
        self.settings["s3_gateway_url"] = self.gateway_url_input.text()
        self.save_settings()
        self.accept()

    def load_settings(self):
        os.makedirs(APP_SUPPORT_DIR, exist_ok=True)
        if os.path.exists(SETTINGS_FILE):
            with open(SETTINGS_FILE, "r") as f:
                return json.load(f)
        return {}

    def save_settings(self):
        with open(SETTINGS_FILE, "w") as f:
            json.dump(self.settings, f, indent=4)