import json

import pytest

from app import create_app

CONTACTS_CSV = b"name,email,phone\nAda Lovelace,ada@example.com,123\nAlan Turing,alan@example.com,456\n"


@pytest.fixture
def client():
    return create_app({"TESTING": True}).test_client()


def post_file(client, content: bytes, file_name="contacts.csv", template_id="contacts", output_format="csv", headers=None):
    from io import BytesIO

    return client.post(
        "/convert",
        data={"file": (BytesIO(content), file_name), "template_id": template_id, "output_format": output_format},
        content_type="multipart/form-data",
        headers=headers or {},
    )


def test_health(client):
    assert client.get("/healthz").get_json() == {"status": "ok"}


def test_form_shows_signed_in_user(client):
    page = client.get("/", headers={"X-MS-CLIENT-PRINCIPAL-NAME": "tester@example.com"})
    assert b"Signed in as tester@example.com" in page.data


def test_converts_csv_with_template(client):
    response = post_file(client, CONTACTS_CSV)
    assert response.status_code == 200
    assert response.headers["Content-Disposition"] == 'attachment; filename="contacts-contacts.csv"'
    assert response.data.decode() == "full_name,email_address\nAda Lovelace,ada@example.com\nAlan Turing,alan@example.com\n"


def test_converts_to_json_as_is(client):
    response = post_file(client, CONTACTS_CSV, template_id="as-is", output_format="json")
    assert json.loads(response.data)[0] == {"name": "Ada Lovelace", "email": "ada@example.com", "phone": "123"}


def test_rejects_missing_columns(client):
    response = post_file(client, b"first,last\nAda,Lovelace\n")
    assert response.status_code == 400
    assert b"Missing columns" in response.data


def test_rejects_other_file_types(client):
    response = post_file(client, CONTACTS_CSV, file_name="contacts.exe")
    assert response.status_code == 400
    assert b"Only .csv files" in response.data


def test_rejects_uploads_over_the_limit():
    small_client = create_app({"TESTING": True, "MAX_CONTENT_LENGTH": 100}).test_client()
    assert post_file(small_client, CONTACTS_CSV * 10).status_code == 413
