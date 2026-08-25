# OKF ディレクトリ構造設計 & アレンジメントガイド

OKF v0.2 は特定のドメインや固定の階層構造を強制しません（§3）。
本ガイドでは、対象とする資料・ドキュメントの性質に合わせて最適なディレクトリ構造を選択・アレンジするための実践パターンと設計原則を解説します。

---

## 1. 構造設計のコア原則

1. **自己記述性（Self-describing）**: フォルダ名とファイル名だけで、何がどこにあるか人間・エージェント双方が直感的に把握できること。
2. **段階的開示（Progressive Disclosure）**: 各ディレクトリに `index.md` を配置し、上位から下位へと順を追って探索可能にすること。
3. **1コンセプト = 1ファイル**: 複数の関心事を1つのファイルに詰め込まず、リンク（`/path/to/doc.md`）で関係性を表現すること。
4. **安定したリンク（Bundle-relative）**: 構造変更に強くするため、ドキュメント間リンクはバンドルルートからの絶対パス `/subdir/concept.md` を推奨。

---

## 2. 推奨ディレクトリパターン集

### パターン 1: システム設計・アーキテクチャ資料 (`system-docs`)
システム開発、インフラ構成、API仕様、運用手順書を管理する場合。

```
bundle-root/
├── index.md                      # 全体概要・目次
├── log.md                        # システム変更・追加履歴
├── architecture/                 # 全体構成・設計方針
│   ├── index.md
│   ├── system-overview.md        # type: Architecture Overview
│   ├── network-topology.md       # type: Infrastructure
│   └── security-model.md         # type: Security Policy
├── components/                   # 各サブシステム・マイクロサービス
│   ├── index.md
│   ├── auth-service.md           # type: Service
│   └── order-pipeline.md         # type: Pipeline
├── playbooks/                    # 運用手順書・トラブルシューティング
│   ├── index.md
│   ├── deployment.md             # type: Playbook
│   └── incident-triage.md        # type: Playbook
└── references/                   # 外部連携仕様・スキーマ
    ├── index.md
    └── schemas/
```

---

### パターン 2: チームナレッジ・社内規程・業務マニュアル (`team-knowledge`)
開発チームのガイドライン、オンボーディング、運用ルールなどを管理する場合。

```
bundle-root/
├── index.md
├── log.md
├── guidelines/                   # 開発標準・コーディング規約
│   ├── index.md
│   ├── coding-standards.md       # type: Guideline
│   └── git-workflow.md           # type: Guideline
├── policies/                     # チーム方針・セキュリティ規程
│   ├── index.md
│   ├── access-control.md         # type: Policy
│   └── data-retention.md         # type: Policy
├── processes/                    # 定常業務プロセス
│   ├── index.md
│   ├── sprint-cadence.md         # type: Process
│   └── release-management.md     # type: Process
└── onboarding/                   # 入社・参画時オンボーディング
    ├── index.md
    ├── environment-setup.md      # type: Guide
    └── first-week-checklist.md   # type: Checklist
```

---

### パターン 3: データカタログ・分析アセット (`data-catalog`)
DWHテーブル、BI指標、算出クエリ、データ定義を管理する場合。

```
bundle-root/
├── index.md
├── log.md
├── datasets/                     # データセット定義
│   ├── index.md
│   └── sales_dw.md               # type: Dataset
├── tables/                       # 個別テーブル・ビュー
│   ├── index.md
│   ├── orders.md                 # type: Table
│   └── customers.md              # type: Table
├── metrics/                      # KPI・ビジネス指標
│   ├── index.md
│   └── mrr.md                    # type: Metric
├── computations/                 # 保証付き計算 (Attested Computation)
│   ├── index.md
│   └── calculate-mrr.md          # type: Attested Computation
└── references/                   # SQLファイル・検証スクリプト
    ├── computations/
    └── attesters/
```

---

### パターン 4: フラット / 単一ドメイン構成 (`minimal` / `flat`)
ドキュメント数が少なく（数件〜20件程度）、階層を深くしたくない場合。

```
bundle-root/
├── index.md
├── log.md
├── getting-started.md            # ルート直下に直接配置
├── architecture.md
├── operations.md
└── references/                   # 補助スクリプト・外部資料のみ隔離
```

---

## 3. ディレクトリ構造のアレンジ・変更手順

プロジェクトの成長に合わせてディレクトリを再配置（リファクタリング）する際は、以下のステップで行います：

### ステップ 1: 新しいディレクトリを作成・移動
```powershell
New-Item -Path ".\docs\new-section" -ItemType Directory
Move-Item -Path ".\docs\old-section\some-doc.md" -Destination ".\docs\new-section\"
```

### ステップ 2: 内部リンクの修正
- バンドルルート相対パス（`/new-section/some-doc.md`）を使用していれば、参照元ファイルの階層が変わってもリンク切れを起こしません。
- 相対パス（`../old-section/some-doc.md`）を使っている箇所があれば、`/new-section/some-doc.md` に統一します。

### ステップ 3: `index.md` の自動同期
スクリプトを実行して、各フォルダの `index.md` を最新状態に再生成します：
```powershell
.\scripts\Update-OkfIndex.ps1 -Path ".\docs" -Recurse -LogMessage "Reorganized documents into new-section"
```

### ステップ 4: 整合性検証
```powershell
.\scripts\Test-OkfBundle.ps1 -Path ".\docs" -CheckBrokenLinks
```
エラーやリンク切れ警告が 0 件になることを確認します。
