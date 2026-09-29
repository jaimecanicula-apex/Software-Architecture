"""Asset CRUD: any signed-in user can view every asset; only the owner or an
admin can change or delete one."""
import io
import re

from tests.conftest import login


def _csrf_from(page) -> str:
    return re.search(r'name="csrf_token" value="([^"]+)"', page.text).group(1)


def test_owner_can_create_and_see_their_asset(client):
    login(client, "demo", "demo-pass-123")
    token = _csrf_from(client.get("/assets/new"))
    resp = client.post(
        "/assets/new",
        data={"name": "Drill", "category": "Tools", "description": "Cordless", "csrf_token": token},
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"Drill" in resp.data


def test_another_user_cannot_edit_someone_elses_asset(client):
    login(client, "demo", "demo-pass-123")
    token = _csrf_from(client.get("/assets/new"))
    client.post("/assets/new", data={"name": "Drill", "csrf_token": token}, follow_redirects=True)
    client.post("/logout", data={"csrf_token": token})

    from app.db import get_session
    from app.models.user import ROLE_USER, User
    db = get_session()
    other = User(username="other", role=ROLE_USER)
    other.set_password("other-pass-123")
    db.add(other)
    db.commit()

    login(client, "other", "other-pass-123")
    resp = client.get("/assets/1/edit")
    assert resp.status_code == 403


def test_uploading_a_non_image_file_is_rejected(client):
    login(client, "demo", "demo-pass-123")
    token = _csrf_from(client.get("/assets/new"))
    resp = client.post(
        "/assets/new",
        data={"name": "Bad upload", "csrf_token": token, "image": (io.BytesIO(b"not an image"), "file.txt")},
        content_type="multipart/form-data",
    )
    assert resp.status_code == 400
    assert b"JPEG" in resp.data


def test_missing_asset_image_is_404(client):
    login(client, "demo", "demo-pass-123")
    resp = client.get("/assets/999/image")
    assert resp.status_code == 404


def test_a_lying_file_extension_is_still_rejected(client):
    """.jpg on the filename, but not a real JPEG (no JPEG magic bytes) —
    content-sniffing must catch this, since an extension is attacker-set."""
    login(client, "demo", "demo-pass-123")
    token = _csrf_from(client.get("/assets/new"))
    resp = client.post(
        "/assets/new",
        data={"name": "Fake jpg", "csrf_token": token, "image": (io.BytesIO(b"just some bytes, not a real image"), "photo.jpg")},
        content_type="multipart/form-data",
    )
    assert resp.status_code == 400
    assert b"JPEG" in resp.data


def test_a_real_image_round_trips_through_upload_and_download(client):
    login(client, "demo", "demo-pass-123")
    token = _csrf_from(client.get("/assets/new"))
    jpeg_bytes = b"\xff\xd8\xff\xe0" + b"\x00" * 16
    client.post(
        "/assets/new",
        data={"name": "Has a photo", "csrf_token": token, "image": (io.BytesIO(jpeg_bytes), "photo.jpg")},
        content_type="multipart/form-data",
        follow_redirects=True,
    )
    resp = client.get("/assets/1/image")
    assert resp.status_code == 200
    assert resp.mimetype == "image/jpeg"
    assert resp.data == jpeg_bytes


def test_another_user_cannot_delete_someone_elses_asset(client):
    login(client, "demo", "demo-pass-123")
    token = _csrf_from(client.get("/assets/new"))
    client.post("/assets/new", data={"name": "Drill", "csrf_token": token}, follow_redirects=True)
    client.post("/logout", data={"csrf_token": token})

    from app.db import get_session
    from app.models.user import ROLE_USER, User
    db = get_session()
    other = User(username="other2", role=ROLE_USER)
    other.set_password("other-pass-123")
    db.add(other)
    db.commit()

    login(client, "other2", "other-pass-123")
    fresh_token = _csrf_from(client.get("/assets/new"))
    resp = client.post("/assets/1/delete", data={"csrf_token": fresh_token})
    assert resp.status_code == 403


def test_uploaded_filename_never_overflows_the_stored_blob_name(client):
    """image_blob_name is a bounded database column; a very long,
    attacker-controlled upload filename must never be embedded verbatim."""
    login(client, "demo", "demo-pass-123")
    token = _csrf_from(client.get("/assets/new"))
    long_filename = ("a" * 500) + ".jpg"
    jpeg_bytes = b"\xff\xd8\xff\xe0" + b"\x00" * 16
    client.post(
        "/assets/new",
        data={"name": "Long filename", "csrf_token": token, "image": (io.BytesIO(jpeg_bytes), long_filename)},
        content_type="multipart/form-data",
        follow_redirects=True,
    )

    from app.db import get_session
    from app.models.asset import Asset
    db = get_session()
    asset = db.query(Asset).filter_by(name="Long filename").one()
    assert len(asset.image_blob_name) <= 255
