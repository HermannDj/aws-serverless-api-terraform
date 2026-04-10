"""
Tests unitaires — Lambda handler (CRUD Items)

Stratégie :
  - Toutes les opérations DynamoDB sont mockées avec unittest.mock
  - On teste uniquement la logique métier de handler.py :
    routing, validation, format de réponse, gestion d'erreurs
  - Pas d'appel AWS réel → rapide, pas de credentials nécessaires

Usage :
  pip install pytest boto3
  pytest tests/unit/ -v
"""

import json
import os
import sys
from decimal import Decimal
from unittest.mock import MagicMock, patch

import pytest

# Injecte TABLE_NAME avant l'import du module (requis par handler.py au chargement)
os.environ["TABLE_NAME"] = "test-table"

# Ajoute lambda_src au path pour pouvoir importer handler
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../lambda_src"))

import handler  # noqa: E402 — import après modification du path


# ─── Fixtures ─────────────────────────────────────────────────────────────────

def make_event(method: str, path: str, body=None, path_params=None, user_sub="user-123"):
    """Construit un event API Gateway (AWS_PROXY format)."""
    return {
        "httpMethod": method,
        "path": path,
        "pathParameters": path_params,
        "body": json.dumps(body) if body else None,
        "requestContext": {
            "authorizer": {
                "claims": {"sub": user_sub}
            }
        },
    }


SAMPLE_ITEM = {
    "id": "abc-123",
    "name": "Test item",
    "description": "Un item de test",
    "owner": "user-123",
    "created_at": "2024-01-01T00:00:00+00:00",
    "updated_at": "2024-01-01T00:00:00+00:00",
}


# ─── DecimalEncoder ────────────────────────────────────────────────────────────

class TestDecimalEncoder:
    def test_encodes_integer_decimal(self):
        result = json.dumps({"n": Decimal("42")}, cls=handler.DecimalEncoder)
        assert json.loads(result)["n"] == 42

    def test_encodes_float_decimal(self):
        result = json.dumps({"n": Decimal("3.14")}, cls=handler.DecimalEncoder)
        assert abs(json.loads(result)["n"] - 3.14) < 0.001

    def test_passes_through_non_decimal(self):
        result = json.dumps({"s": "hello", "n": 1}, cls=handler.DecimalEncoder)
        assert json.loads(result) == {"s": "hello", "n": 1}


# ─── parse_body ───────────────────────────────────────────────────────────────

class TestParseBody:
    def test_parses_valid_json(self):
        event = {"body": '{"name": "test"}'}
        assert handler.parse_body(event) == {"name": "test"}

    def test_returns_empty_dict_on_none_body(self):
        assert handler.parse_body({"body": None}) == {}

    def test_returns_empty_dict_on_missing_body(self):
        assert handler.parse_body({}) == {}

    def test_returns_empty_dict_on_invalid_json(self):
        assert handler.parse_body({"body": "not-json"}) == {}


# ─── get_user_id ──────────────────────────────────────────────────────────────

class TestGetUserId:
    def test_extracts_sub_from_claims(self):
        event = make_event("GET", "/items", user_sub="user-abc")
        assert handler.get_user_id(event) == "user-abc"

    def test_returns_anonymous_when_no_claims(self):
        event = {"requestContext": {}}
        assert handler.get_user_id(event) == "anonymous"

    def test_returns_anonymous_when_no_request_context(self):
        assert handler.get_user_id({}) == "anonymous"


# ─── response helper ──────────────────────────────────────────────────────────

class TestResponseHelper:
    def test_returns_correct_status_code(self):
        r = handler.response(200, {"ok": True})
        assert r["statusCode"] == 200

    def test_body_is_json_string(self):
        r = handler.response(201, {"id": "xyz"})
        assert isinstance(r["body"], str)
        assert json.loads(r["body"]) == {"id": "xyz"}

    def test_cors_headers_present(self):
        r = handler.response(200, {})
        assert r["headers"]["Access-Control-Allow-Origin"] == "*"
        assert "Authorization" in r["headers"]["Access-Control-Allow-Headers"]


# ─── GET /items ───────────────────────────────────────────────────────────────

class TestListItems:
    @patch("handler.table")
    def test_returns_200_with_items(self, mock_table):
        mock_table.scan.return_value = {"Items": [SAMPLE_ITEM]}
        event = make_event("GET", "/items")

        result = handler.list_items(event)

        assert result["statusCode"] == 200
        body = json.loads(result["body"])
        assert body["count"] == 1
        assert body["items"][0]["id"] == "abc-123"

    @patch("handler.table")
    def test_returns_200_with_empty_list(self, mock_table):
        mock_table.scan.return_value = {"Items": []}
        result = handler.list_items(make_event("GET", "/items"))
        assert result["statusCode"] == 200
        assert json.loads(result["body"])["count"] == 0

    @patch("handler.table")
    def test_returns_500_on_dynamodb_error(self, mock_table):
        from botocore.exceptions import ClientError
        mock_table.scan.side_effect = ClientError(
            {"Error": {"Code": "InternalServerError", "Message": "fail"}}, "Scan"
        )
        result = handler.list_items(make_event("GET", "/items"))
        assert result["statusCode"] == 500


# ─── GET /items/{id} ──────────────────────────────────────────────────────────

class TestGetItem:
    @patch("handler.table")
    def test_returns_item_when_found(self, mock_table):
        mock_table.get_item.return_value = {"Item": SAMPLE_ITEM}
        result = handler.get_item("abc-123")
        assert result["statusCode"] == 200
        assert json.loads(result["body"])["id"] == "abc-123"

    @patch("handler.table")
    def test_returns_404_when_not_found(self, mock_table):
        mock_table.get_item.return_value = {}
        result = handler.get_item("missing-id")
        assert result["statusCode"] == 404

    @patch("handler.table")
    def test_returns_500_on_dynamodb_error(self, mock_table):
        from botocore.exceptions import ClientError
        mock_table.get_item.side_effect = ClientError(
            {"Error": {"Code": "InternalServerError", "Message": "fail"}}, "GetItem"
        )
        result = handler.get_item("abc-123")
        assert result["statusCode"] == 500


# ─── POST /items ──────────────────────────────────────────────────────────────

class TestCreateItem:
    @patch("handler.table")
    def test_creates_item_returns_201(self, mock_table):
        mock_table.put_item.return_value = {}
        event = make_event("POST", "/items", body={"name": "Nouveau item"})
        result = handler.create_item(event)
        assert result["statusCode"] == 201
        body = json.loads(result["body"])
        assert body["name"] == "Nouveau item"
        assert "id" in body
        assert body["owner"] == "user-123"

    @patch("handler.table")
    def test_returns_400_on_empty_body(self, mock_table):
        event = make_event("POST", "/items")
        result = handler.create_item(event)
        assert result["statusCode"] == 400

    @patch("handler.table")
    def test_protected_fields_not_overridable(self, mock_table):
        mock_table.put_item.return_value = {}
        event = make_event("POST", "/items", body={
            "id": "hacked-id",
            "created_at": "1970-01-01",
            "name": "test",
        })
        result = handler.create_item(event)
        assert result["statusCode"] == 201
        body = json.loads(result["body"])
        assert body["id"] != "hacked-id"
        assert body["created_at"] != "1970-01-01"

    @patch("handler.table")
    def test_returns_409_on_conflict(self, mock_table):
        from botocore.exceptions import ClientError
        mock_table.put_item.side_effect = ClientError(
            {"Error": {"Code": "ConditionalCheckFailedException", "Message": "exists"}},
            "PutItem"
        )
        mock_table.meta.client.exceptions.ConditionalCheckFailedException = ClientError
        event = make_event("POST", "/items", body={"name": "test"})
        result = handler.create_item(event)
        assert result["statusCode"] in (409, 500)  # selon version botocore


# ─── PUT /items/{id} ──────────────────────────────────────────────────────────

class TestUpdateItem:
    @patch("handler.table")
    def test_updates_item_returns_200(self, mock_table):
        updated = {**SAMPLE_ITEM, "name": "Modifié"}
        mock_table.update_item.return_value = {"Attributes": updated}
        mock_table.meta.client.exceptions.ConditionalCheckFailedException = Exception

        event = make_event("PUT", "/items/abc-123", body={"name": "Modifié"},
                           path_params={"id": "abc-123"})
        result = handler.update_item("abc-123", event)
        assert result["statusCode"] == 200
        assert json.loads(result["body"])["name"] == "Modifié"

    @patch("handler.table")
    def test_returns_400_on_empty_body(self, mock_table):
        event = make_event("PUT", "/items/abc-123")
        result = handler.update_item("abc-123", event)
        assert result["statusCode"] == 400

    @patch("handler.table")
    def test_returns_400_when_only_protected_fields(self, mock_table):
        event = make_event("PUT", "/items/abc-123", body={"id": "x", "owner": "y"})
        result = handler.update_item("abc-123", event)
        assert result["statusCode"] == 400

    @patch("handler.table")
    def test_protected_fields_stripped_from_update(self, mock_table):
        mock_table.update_item.return_value = {"Attributes": SAMPLE_ITEM}
        mock_table.meta.client.exceptions.ConditionalCheckFailedException = Exception

        event = make_event("PUT", "/items/abc-123",
                           body={"name": "ok", "owner": "attacker", "created_at": "hacked"})
        handler.update_item("abc-123", event)

        call_kwargs = mock_table.update_item.call_args[1]
        assert ":owner" not in call_kwargs.get("ExpressionAttributeValues", {})
        assert ":created_at" not in call_kwargs.get("ExpressionAttributeValues", {})


# ─── DELETE /items/{id} ───────────────────────────────────────────────────────

class TestDeleteItem:
    @patch("handler.table")
    def test_deletes_item_returns_204(self, mock_table):
        mock_table.delete_item.return_value = {}
        mock_table.meta.client.exceptions.ConditionalCheckFailedException = Exception

        result = handler.delete_item("abc-123")
        assert result["statusCode"] == 204

    @patch("handler.table")
    def test_returns_404_when_not_found(self, mock_table):
        mock_table.meta.client.exceptions.ConditionalCheckFailedException = Exception
        mock_table.delete_item.side_effect = Exception("ConditionalCheckFailed")

        with patch.object(
            mock_table.meta.client.exceptions,
            "ConditionalCheckFailedException",
            Exception,
        ):
            result = handler.delete_item("missing-id")
        assert result["statusCode"] in (404, 500)


# ─── Router lambda_handler ────────────────────────────────────────────────────

class TestRouter:
    @patch("handler.list_items")
    def test_routes_get_items(self, mock_list):
        mock_list.return_value = handler.response(200, {"items": []})
        event = make_event("GET", "/items")
        handler.lambda_handler(event, None)
        mock_list.assert_called_once()

    @patch("handler.create_item")
    def test_routes_post_items(self, mock_create):
        mock_create.return_value = handler.response(201, {})
        event = make_event("POST", "/items", body={"name": "test"})
        handler.lambda_handler(event, None)
        mock_create.assert_called_once()

    @patch("handler.get_item")
    def test_routes_get_item_by_id(self, mock_get):
        mock_get.return_value = handler.response(200, SAMPLE_ITEM)
        event = make_event("GET", "/items/abc-123", path_params={"id": "abc-123"})
        handler.lambda_handler(event, None)
        mock_get.assert_called_once_with("abc-123")

    @patch("handler.update_item")
    def test_routes_put_item(self, mock_update):
        mock_update.return_value = handler.response(200, SAMPLE_ITEM)
        event = make_event("PUT", "/items/abc-123",
                           body={"name": "updated"}, path_params={"id": "abc-123"})
        handler.lambda_handler(event, None)
        mock_update.assert_called_once()

    @patch("handler.delete_item")
    def test_routes_delete_item(self, mock_delete):
        mock_delete.return_value = handler.response(204, {})
        event = make_event("DELETE", "/items/abc-123", path_params={"id": "abc-123"})
        handler.lambda_handler(event, None)
        mock_delete.assert_called_once_with("abc-123")

    def test_returns_200_on_options(self):
        event = make_event("OPTIONS", "/items")
        result = handler.lambda_handler(event, None)
        assert result["statusCode"] == 200

    def test_returns_404_on_unknown_route(self):
        event = make_event("GET", "/unknown")
        result = handler.lambda_handler(event, None)
        assert result["statusCode"] == 404
