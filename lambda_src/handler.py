"""
API CRUD serverless — Items
Lambda handler pour toutes les routes de l'API.

Routes gérées :
  GET    /items        -> liste tous les items
  POST   /items        -> cree un item
  GET    /items/{id}   -> recupere un item par ID
  PUT    /items/{id}   -> met a jour un item
  DELETE /items/{id}   -> supprime un item

API Gateway en mode AWS_PROXY transmet l'event entier a cette fonction.
La Lambda doit retourner un dict avec statusCode, headers, body.
"""

import json
import os
import uuid
from datetime import datetime, timezone, timedelta
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError


class DecimalEncoder(json.JSONEncoder):
    """
    DynamoDB retourne les nombres comme Decimal.
    json.dumps ne sait pas serialiser Decimal -> TypeError.
    Ce custom encoder convertit Decimal en int ou float.
    """

    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)


# ─── Initialisation globale ───────────────────────────────────────────────────
# Ces objets sont crees UNE SEULE FOIS lors du cold start de la Lambda.
# Ils sont reutilises sur les invocations suivantes (warm start).
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


# ─── Helper : reponse HTTP formatee ──────────────────────────────────────────
def response(status_code: int, body: dict) -> dict:
    """
    Formate la reponse au format attendu par API Gateway (AWS_PROXY mode).
    Sans ce format precis, API Gateway retourne une erreur 502.
    """
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,Authorization",
            "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
        },
        "body": json.dumps(body, cls=DecimalEncoder),
    }


def parse_body(event: dict) -> dict:
    """Parse le body JSON de la requete. Retourne {} si absent ou invalide."""
    body = event.get("body", "{}")
    if body is None:
        return {}
    try:
        return json.loads(body)
    except (json.JSONDecodeError, TypeError):
        return {}


def get_user_id(event: dict) -> str:
    """
    Extrait le sub (user ID) du token JWT valide par Cognito.
    API Gateway injecte les claims dans requestContext.authorizer.claims.
    """
    claims = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("claims", {})
    )
    return claims.get("sub", "anonymous")


# ─── Handlers CRUD ────────────────────────────────────────────────────────────

def list_items(event: dict) -> dict:
    """GET /items — retourne tous les items de la table."""
    try:
        result = table.scan()
        items = result.get("Items", [])
        return response(200, {"items": items, "count": len(items)})
    except ClientError as e:
        print(f"[ERROR] DynamoDB scan failed: {e}")
        return response(500, {"error": "Internal server error"})


def get_item(item_id: str) -> dict:
    """GET /items/{id} — retourne un item par son ID."""
    try:
        result = table.get_item(Key={"id": item_id})
        item = result.get("Item")
        if not item:
            return response(404, {"error": f"Item '{item_id}' not found"})
        return response(200, item)
    except ClientError as e:
        print(f"[ERROR] DynamoDB get_item failed: {e}")
        return response(500, {"error": "Internal server error"})


def create_item(event: dict) -> dict:
    """POST /items — cree un nouvel item."""
    body = parse_body(event)

    if not body:
        return response(400, {"error": "Request body is required"})

    item_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()
    expires_at = int(
        (datetime.now(timezone.utc) + timedelta(days=90)).timestamp()
    )

    item = {
        "id": item_id,
        "created_at": now,
        "updated_at": now,
        "expires_at": expires_at,
        "owner": get_user_id(event),
        **body,
    }
    # Securite : on ne laisse pas le client ecraser les champs systeme
    item["id"] = item_id
    item["created_at"] = now

    try:
        table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(id)",
        )
        return response(201, item)
    except table.meta.client.exceptions.ConditionalCheckFailedException:
        return response(409, {"error": "Item already exists"})
    except ClientError as e:
        print(f"[ERROR] DynamoDB put_item failed: {e}")
        return response(500, {"error": "Internal server error"})


def update_item(item_id: str, event: dict) -> dict:
    """PUT /items/{id} — met a jour un item existant."""
    body = parse_body(event)

    if not body:
        return response(400, {"error": "Request body is required"})

    for protected in ("id", "created_at", "owner"):
        body.pop(protected, None)

    if not body:
        return response(400, {"error": "No updatable fields provided"})

    update_expr_parts = ["#updated_at = :updated_at"]
    expr_names = {"#updated_at": "updated_at"}
    expr_values = {":updated_at": datetime.now(timezone.utc).isoformat()}

    for key, value in body.items():
        safe_key = f"#{key}"
        expr_names[safe_key] = key
        expr_values[f":{key}"] = value
        update_expr_parts.append(f"{safe_key} = :{key}")

    update_expression = "SET " + ", ".join(update_expr_parts)

    try:
        result = table.update_item(
            Key={"id": item_id},
            UpdateExpression=update_expression,
            ExpressionAttributeNames=expr_names,
            ExpressionAttributeValues=expr_values,
            ConditionExpression="attribute_exists(id)",
            ReturnValues="ALL_NEW",
        )
        return response(200, result.get("Attributes", {}))
    except table.meta.client.exceptions.ConditionalCheckFailedException:
        return response(404, {"error": f"Item '{item_id}' not found"})
    except ClientError as e:
        print(f"[ERROR] DynamoDB update_item failed: {e}")
        return response(500, {"error": "Internal server error"})


def delete_item(item_id: str) -> dict:
    """DELETE /items/{id} — supprime un item."""
    try:
        table.delete_item(
            Key={"id": item_id},
            ConditionExpression="attribute_exists(id)",
        )
        return response(204, {})
    except table.meta.client.exceptions.ConditionalCheckFailedException:
        return response(404, {"error": f"Item '{item_id}' not found"})
    except ClientError as e:
        print(f"[ERROR] DynamoDB delete_item failed: {e}")
        return response(500, {"error": "Internal server error"})


# ─── Router principal ──────────────────────────────────────────────────────────
def lambda_handler(event: dict, context) -> dict:
    """
    Point d'entree de la Lambda.
    API Gateway (AWS_PROXY) injecte :
      - event["httpMethod"]     : GET, POST, PUT, DELETE
      - event["path"]           : /items ou /items/{id}
      - event["pathParameters"] : {"id": "xxx"} si route avec {id}
      - event["body"]           : string JSON ou None
    """
    method = event.get("httpMethod", "")
    path = event.get("path", "")
    path_params = event.get("pathParameters") or {}
    item_id = path_params.get("id")

    print(f"[INFO] {method} {path} | user={get_user_id(event)}")

    if method == "OPTIONS":
        return response(200, {})

    if path == "/items":
        if method == "GET":
            return list_items(event)
        elif method == "POST":
            return create_item(event)

    elif item_id:
        if method == "GET":
            return get_item(item_id)
        elif method == "PUT":
            return update_item(item_id, event)
        elif method == "DELETE":
            return delete_item(item_id)

    return response(404, {"error": f"Route '{method} {path}' not found"})
