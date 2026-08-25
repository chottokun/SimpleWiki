# okf-organizer

**okf-organizer** は、Google Cloud が提唱するオープン知識表現仕様 **Open Knowledge Format (OKF) v0.2** に準拠して、各種ドキュメント・資料・ナレッジベースを整理・構築・運用・検証するための Antigravity カスタムスキルです。

---

## 主な機能

1. **ドキュメントのOKF v0.2 形式への構造化 & 整理**
   - 1ファイル1コンセプト化、YAML Frontmatter（`type`, `title`, `description`, `sources`, `generated`, `verified`, `status`, `stale_after`）の付与。
   - 保証付き計算（`Attested Computation`）の独立化とクロスリンク。
2. **アレンジ自在なディレクトリ構造設計**
   - システム設計書、チーム規約、データカタログなど、対象ドメインに応じた柔軟なディレクトリ配置（[directory-patterns.md](references/directory-patterns.md)）。
3. **自動化スクリプトによる運用支援**
   - `New-OkfBundle.ps1`: プリセット指定によるバンドル新規作成。
   - `New-OkfConcept.ps1`: 正しい Frontmatter を持ったコンセプトの追加。
   - `Update-OkfIndex.ps1`: ディレクトリごとの `index.md`（段階的開示）および `log.md`（更新履歴）の自動同期。
   - `Test-OkfBundle.ps1`: OKF v0.2 適合性・構文・リンク切れの自動検査。

---

## ディレクトリ構成

```
okf-organizer/
├── SKILL.md                          # スキルメイン定義（エージェント向け指示書）
├── README.md                         # 本ドキュメント
├── references/                       # 詳細リファレンス（Progressive Disclosure）
│   ├── spec-summary.md               # OKF v0.2 仕様要約
│   ├── directory-patterns.md         # ディレクトリ配置パターン集・アレンジガイド
│   └── frontmatter-cheatsheet.md     # Frontmatter記入例・チートシート
├── templates/                        # テンプレート集
│   ├── bundle-root/                  # index.md / log.md
│   └── concepts/                     # generic, resource-bound, playbook, attested-computation
├── scripts/                          # PowerShell 自動化スクリプト群 (UTF-8 with BOM)
│   ├── New-OkfBundle.ps1
│   ├── New-OkfConcept.ps1
│   ├── Update-OkfIndex.ps1
│   └── Test-OkfBundle.ps1
└── tests/                            # Pester 自動テスト
    └── OkfScripts.Tests.ps1
```

---

## 使い方クイックガイド

### 1. ナレッジバンドルの初期化
```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\okf-organizer\scripts\New-OkfBundle.ps1 `
    -Path ".\docs" `
    -Preset "system-docs" `
    -BundleTitle "システム設計書ナレッジベース"
```

### 2. コンセプトの追加
```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\okf-organizer\scripts\New-OkfConcept.ps1 `
    -Path ".\docs\components\payment-service.md" `
    -Type "Service" `
    -Title "Payment Service" `
    -Description "決済処理およびStripe連携サービス" `
    -Tags @("payment", "stripe", "backend")
```

### 3. 目次 (index.md) と更新履歴 (log.md) の自動同期
```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\okf-organizer\scripts\Update-OkfIndex.ps1 `
    -Path ".\docs" `
    -Recurse `
    -LogMessage "決済サービスの仕様書を追加"
```

### 4. 適合性チェック (Validation)
```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\okf-organizer\scripts\Test-OkfBundle.ps1 `
    -Path ".\docs" `
    -CheckBrokenLinks
```
