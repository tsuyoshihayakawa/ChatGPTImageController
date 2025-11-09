# ChatGPTController

macOS 向けの ChatGPT API クライアントアプリ。  
OpenAI API を利用してプロンプトを送信し、レスポンスを履歴として管理できます。  
右下の **「loadPromptFileAndExecute」** ボタンから、テキストファイルに書かれた複数のプロンプトを一括処理（バッチ実行）できます。

---

## 🧩 主な機能

### ✅ 通常モード
- `API Key` に OpenAI の APIキーを入力
- 任意の `Model`, `Temperature`, `Max Tokens`, `System Message`, `Prompt` を設定
- **Send** ボタンでリクエストを送信し、結果を `Result` に表示
- 履歴は右側のテーブルに自動追加され、保存／読み込み可能

### ✅ バッチモード
複数のプロンプトを自動処理できる機能。  
右下の **「loadPromptFileAndExecute」** ボタンから開始。

#### 使い方
1. プロンプトを1行ずつ書いたテキストファイルを用意  
   例：

清水寺
金閣寺
銀閣寺

2. アプリ右下の「loadPromptFileAndExecute」をクリック  
3. ファイル選択ダイアログで `.txt` を選ぶ  
4. 各行の文字列が、現在の `Prompt` フィールドの内容と結合され、ChatGPTへ順次送信  
例：

金閣寺について、その見どころを教えて

5. ダイアログに進捗バーが表示され、処理の進行状況を確認可能  
6. 「キャンセル」ボタンで途中停止が可能  
7. 完了後、すべての結果が履歴テーブルに自動追加

---

## 💾 履歴機能
- **Save**：現在の履歴を `.plist` 形式で保存  
- **Open**：保存した履歴を再読み込み  
- **Export**：CSV 形式でエクスポート（Excel 対応）

---

## ⚙️ 技術仕様
| 項目 | 内容 |
|------|------|
| 対応OS | macOS (Cocoa / AppKit) |
| 言語 | Objective-C |
| 通信 | NSURLSession (非同期) |
| API | OpenAI Chat Completions |
| UI | NSTableView, NSTextView, NSProgressIndicator |

---

## 🪄 ビルド方法
1. OpenAI API Key を取得しておく  
2. Xcode で `ChatGPTController.xcodeproj` を開く  
3. `Command + R` で実行  
4. 初回起動時に API Key を入力  
→ 次回以降は自動で読み込み  

---

## 💡 使用上の注意
- `Max Tokens` が小さいとレスポンスが途中で切れる場合があります（推奨値：2048〜4096）  
- バッチ実行中はメインウィンドウのボタン操作が無効化されます  
- OpenAI API の利用料金は各自のアカウントに従って発生します  

---

## 📷 スクリーンショット

| メイン画面 | バッチ処理ダイアログ |
|-------------|--------------------|
| ![Main](docs/main.png) | ![Progress](docs/progress.png) |

---

## 🧑‍💻 作者
**早川 強 (AssistSystem)**  
教育アプリ開発者／AIツール制作者  

---

## 🪪 ライセンス
MIT License
