# REST API 仕様書

SimpleWiki が提供する REST エンドポイントおよびデータ形式に関する仕様書です。

## エンドポイント一覧

| メソッド | パス | 説明 | 認証 |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/v1/pages` | ページ一覧の取得 | 不要 |
| `GET` | `/api/v1/pages/{id}` | 指定ページの Markdown 取得 | 不要 |
| `POST` | `/api/v1/pages` | 新規ページの作成 | 必要 |

## レスポンス例

```json
{
  "status": "success",
  "data": {
    "id": "docs/api/REST-API",
    "title": "REST API 仕様書",
    "updatedAt": "2026-08-08T16:00:00Z"
  }
}
```

[詳細仕様に戻る](../詳細仕様.md) | [トップへ](../../index.md)
