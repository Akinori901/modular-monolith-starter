# 設計メモ — 2リポジトリの役割分担

このリポジトリは **clean-arch-starter の対になるもの**として設計する。
「レイヤード化できないフレームワークは諦める」ではなく、
**切り方の軸が違うだけ**というのが主張の中心。

## 対比

| | clean-arch-starter | modular-monolith-starter（本リポ） |
|---|---|---|
| 対象 | 層で切れるフレームワーク | **層で切ると戦うことになるフレームワーク** |
| 切り方 | **層（水平）** | **機能パッケージ（垂直）** |
| 守るもの | 依存の**向き**（内側へのみ） | パッケージ間の**依存**と**公開面** |
| 破り方 | UseCase から Model を直接触る | 他パッケージの内部実装を直接触る |
| 検証 | import-linter / deptrac / go-arch-lint | packwerk / deptrac(モジュール軸) 等 |

**どちらも「規約を文章ではなく CI で落ちる形にする」点は同じ。**
違うのは境界の引き方だけ。

## フレームワークの分類（調査結果 / 2026-08）

### 層で切れる側 → clean-arch-starter

| FW | 根拠 |
|---|---|
| Go | go-clean-arch 10k★・go-clean-template 7.6k★。`internal/` が言語機能として境界を強制 |
| Hanami (Ruby) | DIコンテナ内蔵・ROM で Entity と永続化が分離 |
| Laravel | 規約次第で層に切れる（deptrac で検証可能） |
| Django | ORM を infrastructure に閉じ込めれば DDD 可能 |
| **C# / .NET** | クリーンアーキ勢が最大（Jason Taylor 20.5k★・Ardalis 18.4k★、いずれも現役）。**プロジェクト参照が言語機能として依存方向を強制する**ため、Go の `internal/` より強く縛れる。**ただし下記のとおりモジュール側にも入れられる** |

### モジュールで切る側 → 本リポ

| FW | 根拠 |
|---|---|
| **Rails** | ActiveRecord が「Model が永続化を知る」前提。Repository 層を挟むと戦い続ける。主流は Shopify 発 **packwerk** |
| **CakePHP** | Rails と同系統のフルスタック MVC。Table/Entity は分離されている分 Rails よりマシだが、Bake・慣習がすべて MVC 前提。deptrac でモジュール境界を見る |
| **Phoenix (Elixir)** | **Context** というモジュール境界が最初から FW に組み込まれている。むしろ FW 側が「機能で切れ」と言っている |

### 両方に入れられるフレームワーク

「層 or モジュール」は**フレームワークの制約というより、案件の規模と体制で決まる**ものもある。
以下は両リポに置く価値がある（**同じ言語で層とモジュールを比較できる**サンプルになる）。

| FW | 層で切る根拠 | モジュールで切る根拠 |
|---|---|---|
| **C# / .NET** | Jason Taylor 20.5k★・Ardalis 18.4k★ | `kgrzybek/modular-monolith-with-ddd` 14k★。**プロジェクト参照でモジュール間の依存も強制できる**ため相性が良い |

C# を両方に置くのは「同じ言語で層とモジュールを比較できる」という積極的な理由がある。
単なる重複ではない。

.NET の使い分けの目安:

- **大規模・複数チーム** → Modular Monolith（`Modules/Orders/`, `Modules/Billing/`）
- **単一チーム・単一ドメイン** → クリーンアーキ（Domain / Application / Infrastructure / Web）

star 数ではクリーンアーキ勢が上回るが、これは「モジュール分割が非主流」という意味ではない。
実案件でモジュール構成の .NET は普通に採られている。

## 検証ツールの候補

| FW | ツール | 状態 |
|---|---|---|
| Rails | packwerk (Shopify) | 3.3.1・現役 |
| CakePHP | deptrac（モジュール軸で使う） | 2.0.4・現役 |
| Phoenix | **boundary** + Credo | 0.10.4・**コンパイル時に強制** |
| （参考）C# | NetArchTest / ArchUnitNET | clean-arch 側で使う |

## 採用しないもの

**Laravel / Django のモジュール版は作らない。**

- **案件要項との接続がない。** これらの募集で見るのは「クリーンアーキ」「DDD」であり、
  「モジュラモノリス」はまず要項に出てこない
- **両方ともクリーンアーキ版が clean-arch-starter にある。**
  同じ FW で2種類作っても、増えるのは維持コストだけ
- **そのコミュニティ公認の答えが無い。** Rails の packwerk、Phoenix の Context のような
  「FW 側が示している解」が存在せず、「やろうと思えばできる」止まりになる

本リポに入れるのは、**モジュール分割がそのフレームワークの主流解であるもの**に限る。

### Phoenix は「自作チェッカ」ではなく boundary を使う（判断を更新）

当初は「自作チェッカ + Credo」を想定していたが、**`boundary` を採用した**。

- **コンパイラとして動く。** `mix compile --warnings-as-errors` で落ちる。
  packwerk のような別コマンドが要らず、検証を走らせ忘れようがない
- `deps` / `exports` が packwerk の `dependencies` / `app/public/` に
  そのまま対応しており、**Rails 版と同じ考え方を同じ粒度で書ける**
- 自作チェッカは「Credo のカスタムチェックで AST を見る」ことになるが、
  それは boundary が既に、かつより厳密にやっている

自作する理由が無くなったので採らない。

**ただし「動いているように見えて何も検知していない」状態は避けること。**
Rails 版で `packwerk-extensions` を入れ忘れ、`enforce_privacy` が
黙って無視されていた事故があった。boundary でも
`--warnings-as-errors` を外すと同じ状態になる。
`test/boundary_test.exs` で「コンパイラが有効か」「宣言が意図どおりか」
自体をテストしてある。

## 進め方

1. ~~**Rails を第1弾として完成させる**~~ → 完了
2. ~~対比が成立することを README で示す~~ → 完了
3. ~~CakePHP~~ → 完了 / ~~Phoenix~~ → **完了**
4. **C#** はモジュール版を本リポへ、層版を clean-arch-starter へ（両方に置いて比較できる形にする）

※ Laravel / Django のモジュール版は上記の理由で作らない。

### 3スタックが揃って言えるようになったこと

同じ API（認証 → S3 → DynamoDB アーカイブ）を3つのやり方で実装し、
**いずれも「境界を破ったら CI が落ちる」形にできた**。

| スタック | 境界の単位 | 検証 | 実行タイミング |
|---|---|---|---|
| Rails | パッケージ（`packages/*`） | packwerk | 別コマンド |
| CakePHP | モジュール（`modules/*`） | deptrac | 別コマンド |
| **Phoenix** | **Context（FW 標準）** | **boundary** | **コンパイル時** |

Phoenix だけは**フレームワーク自身が機能で切ることを前提にしている**ため、
「規約を後から被せる」のではなく「標準の構成に強制力を足す」形になった。
3つ並べると、本リポの主張（切り方の軸が違うだけ）が最も素直に出るのがこれ。
