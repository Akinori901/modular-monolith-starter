# phoenix-context

Phoenix 1.8 の **Context** でモジュラモノリスを構成し、
境界を `boundary` で**コンパイル時に**強制する実装。

規約は [`.claude/rules/20-phoenix-context.md`](../../.claude/rules/20-phoenix-context.md)。

## 構成

| Context | 責務 | 依存先 |
|---|---|---|
| `AppWeb` | HTTP の入口。公開 API を呼ぶだけ | identity / storage / archiving |
| `App.Identity` | サインイン・トークン検証・ユーザー解決 | `App.Repo` のみ |
| `App.Storage` | ファイルの保存・取得・署名付きURL | なし |
| `App.Archiving` | 監査/アクセスログの永続化と検索 | なし |

Context 同士は依存せず、`:telemetry` のイベントで繋ぐ。

## 検証

```bash
make verify-phoenix     # リポジトリ直下から
```

内訳:

```bash
mix compile --force --warnings-as-errors   # ← Context 境界の検証（boundary）
mix deps.unlock --check-unused
mix format --check-formatted
mix credo
mix test
```

**`--warnings-as-errors` を外すと境界検証が素通りする。**
boundary はコンパイラとして動き、違反をコンパイル警告として出すため。

## 依存表を見る

```bash
mix boundary.spec
```

各 Context の `deps` と `exports` が出る。
`type: :strict` にしてあるので外部ライブラリも並び、
その Context が持ち込む技術スタックがそのまま読める。
