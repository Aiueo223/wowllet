cat << 'EOF' > README.md
# wowllet

AWS AmplifyとGoogle ML Kitを活用した、スマートな家計簿アプリです。
レシートの画像から金額や店名を自動解析し、日々の収支を簡単に記録・分析することができます。

## 主な機能

- **ダッシュボード (Home)**
  - 今月の収支サマリーと円グラフによるカテゴリ別の支出割合の可視化。
- **分析 (Analysis)**
  - 月ごとの収支トレンドを棒グラフで比較。
  - 特定のカテゴリの月別推移や詳細履歴へのドリルダウン分析。
- **カレンダー (Calendar)**
  - 日別の収支をカレンダー上で直感的に確認。
- **スマート入力 (Smart Input)**
  - **レシートOCR解析:** Google ML Kitを用いたテキスト認識により、レシート画像から合計金額と店名を自動抽出。
  - 手入力での記録ももちろん可能。
- **クラウド連携 (Cloud Backend)**
  - AWS Amplifyを用いたバックエンド連携。
  - 支出データのGraphQL API経由での保存と、レシート画像のS3ストレージへのアップロード。

##  技術スタック

- **Frontend:** Flutter, Dart
- **Backend:** AWS Amplify Gen 2 (GraphQL API, Amazon S3)
- **Machine Learning:** Google ML Kit (Text Recognition)
- **UI/Charts:** fl_chart, table_calendar

##  セットアップ方法

### 前提条件
- Flutter SDK がインストールされていること
- Node.js および npm がインストールされていること
- AWS アカウントおよび IAM 権限の設定が完了していること

### ローカルでの動かし方

1. リポジトリをクローンします。
   `git clone https://github.com/Aiueo223/wowllet.git`
   `cd wowllet`

2. Flutterのパッケージをインストールします。
   `flutter pub get`

3. AWS Amplifyのバックエンド（サンドボックス環境）を立ち上げます。
   `npx ampx sandbox`

4. アプリを実行します。
   `flutter run`

##  今後の実装予定 (To-Do)
- [ ] Amazon Cognitoを用いたユーザー認証（ログイン機能）の実装
- [ ] オーナーベースの認可による、ユーザーごとのデータ分離設定
EOF

git add README.md
git commit -m "README.mdを追加"
git push
