"""Asset catalogue: list/search (any signed-in user), create/edit/delete
(owner or admin), and the image stream route."""
from flask import Blueprint, Response, abort, redirect, render_template, request, session, url_for

from app.auth.security import csrf_token, login_required, require_csrf
from app.db import get_session
from app.models.asset import Asset
from app.storage import delete_image, load_image, save_image
from app.uploads import sniff_image_content_type

assets_blueprint = Blueprint("assets", __name__, url_prefix="/assets")

MAX_IMAGE_BYTES = 5 * 1024 * 1024


@assets_blueprint.route("/")
@login_required
def list_assets():
    db = get_session()
    q = request.args.get("q", "").strip()
    query = db.query(Asset)
    if q:
        like = f"%{q}%"
        query = query.filter((Asset.name.ilike(like)) | (Asset.category.ilike(like)))
    assets = query.order_by(Asset.created_at.desc()).all()
    return render_template(
        "assets/list.html",
        assets=assets,
        q=q,
        user_id=session["user_id"],
        is_admin=session.get("role") == "admin",
    )


@assets_blueprint.route("/new", methods=["GET", "POST"])
@login_required
@require_csrf
def new_asset():
    if request.method == "GET":
        return render_template("assets/form.html", asset=None, csrf_token=csrf_token(), error=None)

    error = _validate_upload()
    if error:
        return render_template("assets/form.html", asset=None, csrf_token=csrf_token(), error=error), 400

    db = get_session()
    asset = Asset(
        name=request.form["name"].strip(),
        category=request.form.get("category", "").strip(),
        description=request.form.get("description", "").strip(),
        owner_user_id=session["user_id"],
    )
    image = request.files.get("image")
    if image and image.filename:
        asset.image_blob_name = save_image(image)
    db.add(asset)
    db.commit()
    return redirect(url_for("assets.list_assets"))


@assets_blueprint.route("/<int:asset_id>/edit", methods=["GET", "POST"])
@login_required
@require_csrf
def edit_asset(asset_id: int):
    db = get_session()
    asset = db.get(Asset, asset_id)
    if asset is None:
        abort(404)
    _require_owner_or_admin(asset)

    if request.method == "GET":
        return render_template("assets/form.html", asset=asset, csrf_token=csrf_token(), error=None)

    error = _validate_upload()
    if error:
        return render_template("assets/form.html", asset=asset, csrf_token=csrf_token(), error=error), 400

    asset.name = request.form["name"].strip()
    asset.category = request.form.get("category", "").strip()
    asset.description = request.form.get("description", "").strip()
    image = request.files.get("image")
    if image and image.filename:
        if asset.image_blob_name:
            delete_image(asset.image_blob_name)
        asset.image_blob_name = save_image(image)
    db.commit()
    return redirect(url_for("assets.list_assets"))


@assets_blueprint.route("/<int:asset_id>/delete", methods=["POST"])
@login_required
@require_csrf
def delete_asset(asset_id: int):
    db = get_session()
    asset = db.get(Asset, asset_id)
    if asset is None:
        abort(404)
    _require_owner_or_admin(asset)
    if asset.image_blob_name:
        delete_image(asset.image_blob_name)
    db.delete(asset)
    db.commit()
    return redirect(url_for("assets.list_assets"))


@assets_blueprint.route("/<int:asset_id>/image")
@login_required
def asset_image(asset_id: int):
    db = get_session()
    asset = db.get(Asset, asset_id)
    if asset is None or not asset.image_blob_name:
        abort(404)
    data = load_image(asset.image_blob_name)
    if data is None:
        abort(404)
    content_type = sniff_image_content_type(data[:12]) or "application/octet-stream"
    return Response(data, mimetype=content_type)


def _require_owner_or_admin(asset: Asset) -> None:
    if session.get("role") != "admin" and asset.owner_user_id != session["user_id"]:
        abort(403)


def _validate_upload() -> str | None:
    if not request.form.get("name", "").strip():
        return "Name is required."
    image = request.files.get("image")
    if image and image.filename:
        head = image.stream.read(12)
        image.stream.seek(0)
        if sniff_image_content_type(head) is None:
            return "Image must be a JPEG, PNG or WebP file."
        image.stream.seek(0, 2)
        size = image.stream.tell()
        image.stream.seek(0)
        if size > MAX_IMAGE_BYTES:
            return "Image must be 5 MB or smaller."
    return None
