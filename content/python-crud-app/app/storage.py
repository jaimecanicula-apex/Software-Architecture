"""Image storage: Azure Blob Storage with the app's managed identity in
Azure, a local folder when no storage account is configured (tests, local
dev)."""
import os
import uuid
from pathlib import Path


def _local_dir() -> Path:
    return Path(os.environ.get("APP_DATA_DIR", "/tmp")) / "images"


def _account_url() -> str | None:
    name = os.environ.get("AZURE_STORAGE_ACCOUNT_NAME")
    return f"https://{name}.blob.core.windows.net" if name else None


def _container_client():
    from azure.identity import DefaultAzureCredential
    from azure.storage.blob import BlobServiceClient

    service = BlobServiceClient(account_url=_account_url(), credential=DefaultAzureCredential())
    return service.get_container_client(os.environ.get("AZURE_STORAGE_CONTAINER", "images"))


def save_image(file_storage) -> str:
    """Stores the uploaded file, returns the blob name to keep on the Asset row."""
    blob_name = f"{uuid.uuid4().hex}-{file_storage.filename}"
    data = file_storage.read()
    if _account_url():
        _container_client().upload_blob(blob_name, data, overwrite=True)
    else:
        local_dir = _local_dir()
        local_dir.mkdir(parents=True, exist_ok=True)
        (local_dir / blob_name).write_bytes(data)
    return blob_name


def load_image(blob_name: str) -> bytes | None:
    if _account_url():
        try:
            return _container_client().download_blob(blob_name).readall()
        except Exception:
            return None
    path = _local_dir() / blob_name
    return path.read_bytes() if path.exists() else None


def delete_image(blob_name: str) -> None:
    if _account_url():
        try:
            _container_client().delete_blob(blob_name)
        except Exception:
            pass
    else:
        (_local_dir() / blob_name).unlink(missing_ok=True)
