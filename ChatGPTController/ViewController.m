//
//  ViewController.m
//  ChatGPTController
//
//  Created by 早川強 on 2025/11/05.
//

#import "ViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>  // ←これをファイル冒頭に追加

static NSString * const kAPIKeyDefaultsKey = @"OpenAI_API_Key";


@interface ViewController ()
@property (strong) NSWindow *progressWindow;
@property (strong) NSProgressIndicator *progressIndicator;
@property (strong) NSButton *cancelButton;
@property (assign) BOOL shouldCancelBatch;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *imageHistory;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.imageHistory = [NSMutableArray array];
    self.historyTable.delegate = self;
    self.historyTable.dataSource = self;

    // 🔹 起動時に保存されたAPIキーを読み込む
    NSString *savedKey = [[NSUserDefaults standardUserDefaults] stringForKey:kAPIKeyDefaultsKey];
    if (savedKey.length) self.apiKeyField.stringValue = savedKey;

    self.modelField.stringValue = @"dall-e-3";
    
    self.history = [NSMutableArray array];
    self.historyTable.delegate = self;
    self.historyTable.dataSource = self;

    // テーブルのカラム設定（Storyboardで設定している場合は不要）
    NSTableColumn *col = [self.historyTable tableColumnWithIdentifier:@"PromptColumn"];
    col.title = @"履歴";
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

- (IBAction)generateImageFromPrompt:(id)sender {
    NSString *apiKey = self.apiKeyField.stringValue ?: @"";
    [[NSUserDefaults standardUserDefaults] setObject:apiKey forKey:kAPIKeyDefaultsKey];
    NSString *prompt = self.promptField.stringValue;
    if (apiKey.length == 0 || prompt.length == 0) {
        self.resultView.string = @"APIキーとプロンプトを入力してください。";
        return;
    }

    self.sendButton.enabled = NO;
    [self.loadingIndicator startAnimation:nil];
    self.resultView.string = @"画像生成中...";

    NSURL *url = [NSURL URLWithString:@"https://api.openai.com/v1/images/generations"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];

    // ✅ 'response_format' は削除
    NSDictionary *body = @{
        @"model": @"dall-e-2",
        @"prompt": prompt,
        @"size": @"512x512"
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setHTTPBody:jsonData];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimation:nil];
            self.sendButton.enabled = YES;

            if (error) {
                self.resultView.string = [NSString stringWithFormat:@"通信エラー: %@", error.localizedDescription];
                return;
            }

            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSLog(@"🟩 Image API Response: %@", json);

            if (json[@"error"]) {
                NSString *errorMessage = json[@"error"][@"message"] ?: @"不明なAPIエラー";
                self.resultView.string = [NSString stringWithFormat:@"❌ APIエラー: %@", errorMessage];
                NSLog(@"🟥 APIエラー詳細: %@", json[@"error"]);
                return;
            }

            // ✅ URL形式で返ってくる
            NSString *imageURLString = json[@"data"][0][@"url"];
            if (!imageURLString) {
                self.resultView.string = @"⚠️ 画像URLが返されませんでした。";
                return;
            }

            imageURLString = json[@"data"][0][@"url"];
            if (!imageURLString) {
                self.resultView.string = @"⚠️ 画像URLが返されませんでした。";
                return;
            }

            NSURL *imageURL = [NSURL URLWithString:imageURLString];
            NSURLSessionDataTask *downloadTask =
            [[NSURLSession sharedSession] dataTaskWithURL:imageURL
                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                    if (error) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.resultView.string = [NSString stringWithFormat:@"⚠️ 画像のダウンロード失敗: %@", error.localizedDescription];
                        });
                        return;
                    }

                    if (!data) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.resultView.string = @"⚠️ 画像データが空です。";
                        });
                        return;
                    }

                    NSImage *image = [[NSImage alloc] initWithData:data];
                    if (!image) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.resultView.string = @"⚠️ 画像デコードに失敗しました。";
                        });
                        return;
                    }

                    // ✅ UI更新はメインスレッドで
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.resultImageView.image = image;
                        self.resultView.string = @"✅ 画像生成完了";
                    });
                }];
            [downloadTask resume];
        });
    }];
    [task resume];
}


#pragma mark - 同期版画像生成（保存込み）

// ---------------------------------------------
// 画像生成（同期）・保存込み（連番対応・safePrompt対応・安定版）
// ---------------------------------------------
- (NSString *)runChatSynchronouslyWithPrompt:(NSString *)prompt
                                saveDirectory:(NSURL *)saveDir
                                     fileName:(NSString *)fileName
                                        name:originalName {

    // -------------------------------------
    // UI操作禁止 → メインスレッドでコピー
    // -------------------------------------
    __block NSString *apiKey = nil;
    __block NSString *model = nil;

    dispatch_sync(dispatch_get_main_queue(), ^{
        apiKey = self.apiKeyField.stringValue.copy;
        model = self.modelField.stringValue.copy;
    });

    if (apiKey.length == 0) return nil;
    if (model.length == 0) model = @"dall-e-3"; // 予備

    // -------------------------------------
    // HTTP リクエストテンプレ
    // -------------------------------------
    NSURL *url = [NSURL URLWithString:@"https://api.openai.com/v1/images/generations"];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSString *resultPath = nil;
    __block int retryCount = 0;

    // -------------------------------------
    // 連番ファイル名を作成
    // -------------------------------------
    NSString * (^uniqueFilename)(NSString *, NSURL *) = ^NSString *(NSString *baseName, NSURL *dir) {

        if (![baseName.lowercaseString hasSuffix:@".png"])
            baseName = [baseName stringByAppendingString:@".png"];

        NSString *name = baseName;
        NSInteger index = 2;

        while ([[NSFileManager defaultManager]
                fileExistsAtPath:[[dir URLByAppendingPathComponent:name] path]]) {

            NSString *stem = [baseName stringByDeletingPathExtension];
            NSString *ext = @"png";
            name = [NSString stringWithFormat:@"%@%ld.%@", stem, (long)index, ext];
            index++;
        }

        return name;
    };

    // -------------------------------------
    // リクエスト実行ブロック
    // -------------------------------------
    __block void (^sendRequestBlock)(NSString *);

    sendRequestBlock = ^(NSString *currentPrompt) {

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        [req setHTTPMethod:@"POST"];
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [req setValue:[NSString stringWithFormat:@"Bearer %@", apiKey]
   forHTTPHeaderField:@"Authorization"];

        NSDictionary *body = @{
            @"model": model,
            @"prompt": currentPrompt,
            @"size": @"1024x1024"
        };

        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [req setHTTPBody:jsonData];

        NSURLSessionDataTask *task =
        [[NSURLSession sharedSession] dataTaskWithRequest:req
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
        {
            if (error) {
                NSLog(@"❌ 通信エラー: %@", error.localizedDescription);
                dispatch_semaphore_signal(sema);
                return;
            }

            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSDictionary *err = json[@"error"];

            // ================================
            // ① content_policy_violation → Safe Prompt再生成
            // ================================
            if (err &&
                [err[@"type"] isEqualToString:@"image_generation_user_error"] &&
                [err[@"code"] isEqualToString:@"content_policy_violation"]) {

                NSLog(@"⚠️ ポリシー違反 → 安全プロンプト生成へ");

                [self generateSafePrompt:currentPrompt completion:^(NSString *safePrompt) {

                    if (!safePrompt) {
                        NSLog(@"❌ Safe Promptの生成に失敗");
                        dispatch_semaphore_signal(sema);
                        return;
                    }

                    NSLog(@"🟩 Safe Prompt = %@", safePrompt);

                    // 再実行
                    sendRequestBlock(safePrompt);
                }];

                return;
            }

            // ================================
            // ② server_error → 最大3回リトライ
            // ================================
            if (err && [err[@"type"] isEqualToString:@"server_error"]) {

                if (retryCount < 3) {
                    retryCount++;
                    NSLog(@"⚠️ server_error → retry %d", retryCount);

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                   ^{
                                       sendRequestBlock(currentPrompt);
                                   });
                    return;
                }

                NSLog(@"❌ server_error 連続発生 → 中断");
                dispatch_semaphore_signal(sema);
                return;
            }

            // ================================
            // ③ 通常処理
            // ================================
            NSString *urlStr = json[@"data"][0][@"url"];
            if (!urlStr) {
                NSLog(@"⚠️ URLなし: %@", json);
                dispatch_semaphore_signal(sema);
                return;
            }

            NSData *imgData = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlStr]];
            if (!imgData) {
                NSLog(@"⚠️ 画像取得失敗");
                dispatch_semaphore_signal(sema);
                return;
            }

            // -------------------------------------
            // 連番付きファイル名を確定
            // -------------------------------------
            NSString *baseName = fileName ?: @"generated.png";
            NSString *finalName = uniqueFilename(baseName, saveDir);
            NSURL *saveURL = [saveDir URLByAppendingPathComponent:finalName];

            NSError *saveErr = nil;
            BOOL ok = [imgData writeToURL:saveURL options:NSDataWritingAtomic error:&saveErr];

            if (!ok || saveErr) {
                NSLog(@"❌ 保存失敗: %@", saveErr.localizedDescription);
            } else {
                NSLog(@"✅ 保存完了: %@", saveURL.path);
                resultPath = saveURL.path;
            }

            // -------------------------------------
            // UI更新（メインスレッド）
            // -------------------------------------
            dispatch_async(dispatch_get_main_queue(), ^{
                NSImage *img = [[NSImage alloc] initWithData:imgData];
                self.resultImageView.image = img;

                // Create thumbnail
                NSImage *thumb = [self resizedImage:img to:100];

                NSDictionary *entry = @{
                    @"thumbnail": thumb,
                    @"prompt": currentPrompt ?: @"",
                    @"model": model ?: @"",
                    @"filename": originalName ?: @""
                };

                [self.imageHistory addObject:entry];
                [self.historyTable reloadData];

                self.resultView.string = @"✅ 画像生成・保存完了";
            });

            dispatch_semaphore_signal(sema);
        }];

        [task resume];
    };

    // -------------------------------------
    // 初回実行
    // -------------------------------------
    sendRequestBlock(prompt);

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return resultPath;
}


// ※ バッチ用ラッパー
- (NSString *)runChatSynchronouslyWithPrompt:(NSString *)prompt {
    NSURL *tmpDir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    return [self runChatSynchronouslyWithPrompt:prompt saveDirectory:tmpDir fileName:nil name:nil];
}

// ------------------------------------------------------
// 重複ファイル名を回避して保存可能なURLを返す
// （例）foo.png → foo2.png → foo3.png …
// ------------------------------------------------------
- (NSURL *)uniqueFileURLForDirectory:(NSURL *)directory
                            fileName:(NSString *)baseFileName {

    // 拡張子付きでなければ .png を追加
    NSString *name = baseFileName;
    if (![name.lowercaseString hasSuffix:@".png"]) {
        name = [name stringByAppendingString:@".png"];
    }

    NSURL *candidate = [directory URLByAppendingPathComponent:name];

    // ファイルが無ければそれを返す
    if (![[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) {
        return candidate;
    }

    // 接尾辞の数字を増やし続ける
    NSString *nameWithoutExt = [name stringByDeletingPathExtension];
    NSString *ext = [name pathExtension];

    NSInteger counter = 2;
    while (true) {
        NSString *newName =
        [NSString stringWithFormat:@"%@%ld.%@", nameWithoutExt, (long)counter, ext];

        NSURL *newURL = [directory URLByAppendingPathComponent:newName];

        if (![[NSFileManager defaultManager] fileExistsAtPath:newURL.path]) {
            return newURL; // ← これが最終的な保存先
        }

        counter++;
    }
}

#pragma IBAction ==================================

- (IBAction)newEntry:(id)sender {
    self.promptField.stringValue = @"";
    self.resultView.string = @"";
    self.modelField.stringValue = @"dall-e-3";
    [self.historyTable deselectAll:nil];
    self.resultView.string = @"";
}

- (IBAction)generateAndSaveImage:(id)sender {
    NSImage *currentImage = self.resultImageView.image;
    if (!currentImage) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"画像がありません";
        alert.informativeText = @"保存する画像が表示されていません。";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    // 保存先フォルダ選択
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.prompt = @"保存フォルダを選択";

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSURL *directoryURL = panel.URL;

        // NSImage → PNGデータに変換
        CGImageRef cgRef = [currentImage CGImageForProposedRect:NULL context:nil hints:nil];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgRef];
        NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];

        if (!pngData) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"画像データの変換に失敗しました";
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
            return;
        }

        // ファイル名を自動生成（例：timestamp.png）
        NSString *timestamp = [[NSDate date] descriptionWithLocale:nil];
        timestamp = [timestamp stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        timestamp = [timestamp stringByReplacingOccurrencesOfString:@":" withString:@"-"];
        NSString *fileName = [NSString stringWithFormat:@"image_%@.png", timestamp];

        // ✅ 既存の保存メソッドを利用
        NSString *savedPath = [self saveImageData:pngData
                                         withName:fileName
                                       toDirectory:directoryURL];

        // 保存結果をアラート表示
        NSAlert *alert = [[NSAlert alloc] init];
        if (savedPath) {
            alert.messageText = @"✅ 画像を保存しました";
            alert.informativeText = savedPath;
        } else {
            alert.messageText = @"❌ 保存に失敗しました";
        }
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }];
}

#pragma mark - 保存／読み込み／書き出し

- (IBAction)deleteSelectedHistory:(id)sender {
    NSInteger row = self.historyTable.selectedRow;
    if (row >= 0 && row < self.history.count) {
        [self.history removeObjectAtIndex:row];
        [self.historyTable reloadData];
    }
}


#pragma mark - バッチ処理

- (IBAction)loadPromptFileAndExecute:(id)sender {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    openPanel.allowedContentTypes = @[UTTypePlainText];
    openPanel.prompt = @"リストを選択（テキスト形式）";

    [openPanel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSURL *fileURL = openPanel.URL;

        NSOpenPanel *savePanel = [NSOpenPanel openPanel];
        savePanel.canChooseFiles = NO;
        savePanel.canChooseDirectories = YES;
        savePanel.prompt = @"画像保存フォルダを選択";

        [savePanel beginWithCompletionHandler:^(NSModalResponse result2) {
            if (result2 != NSModalResponseOK) return;
            [self executeImageBatchFromFile:fileURL saveDirectory:savePanel.URL];
        }];
    }];
}

- (void)executeImageBatchFromFile:(NSURL *)fileURL saveDirectory:(NSURL *)saveDir {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfURL:fileURL encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"⚠️ 読み込み失敗: %@", error.localizedDescription);
        return;
    }

    NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *line in lines) {
        NSString *trim = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trim.length > 0) [names addObject:trim];
    }

    [self runImageBatchSequentially:names currentIndex:0 saveDirectory:saveDir];
}

- (void)runImageBatchSequentially:(NSArray<NSString *> *)names
                     currentIndex:(NSInteger)index
                    saveDirectory:(NSURL *)saveDir {

    if (index == 0) {
        [self showProgressDialogWithTotal:names.count];
    }

    if (self.shouldCancelBatch || index >= names.count) {
        [self.view.window endSheet:self.progressWindow];
        self.progressWindow = nil;
        NSLog(@"✅ 全ての画像生成が完了またはキャンセルされました");
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = self.shouldCancelBatch ? @"キャンセルしました" : @"✅ 全ての画像生成が完了しました";
        [alert runModal];
        return;
    }

    // 🔹 prompt組み立て
    NSString *name = names[index];
    NSString *userPrompt = self.promptField.stringValue;
    if (userPrompt == nil || userPrompt.length == 0) {
        userPrompt = @"挿絵風の鮮やかなイラスト。静謐で品格のある印象。縁はところどころ余白を残しラフにしあげる。余白は透明色に。でこぼこした髪の質感を表現して。";
    }
    NSString *prompt = [NSString stringWithFormat:@"%@の%@", name, userPrompt];

    NSLog(@"🎨 (%ld/%lu) 生成中: %@", (long)(index+1), (unsigned long)names.count, name);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *tmpName = [NSString stringWithFormat:@"tmp_%u.png", arc4random_uniform(999999)];
        NSString *tmpPath = [self runChatSynchronouslyWithPrompt:prompt
                                                    saveDirectory:[NSURL fileURLWithPath:NSTemporaryDirectory()]
                                                         fileName:tmpName
                                                            name:name];
        if (tmpPath) {
            NSString *safeName = name ?: @"unknown";
            safeName = [safeName stringByReplacingOccurrencesOfString:@" " withString:@"_"];
            NSString *baseName = [NSString stringWithFormat:@"%@.png", safeName];
            NSURL *dest = [self uniqueFileURLForDirectory:saveDir fileName:baseName];
            
            NSError *moveErr = nil;
            [[NSFileManager defaultManager] moveItemAtPath:tmpPath toPath:dest.path error:&moveErr];
            if (moveErr)
                NSLog(@"⚠️ 保存失敗: %@", moveErr.localizedDescription);
            else
                NSLog(@"✅ 保存完了: %@", dest.path);
        }

        // 🔹 進捗更新
        [self updateProgress:index + 1 total:names.count];

        if (self.shouldCancelBatch) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.view.window endSheet:self.progressWindow];
                self.progressWindow = nil;
                NSLog(@"⏹ バッチ処理をキャンセルしました");
            });
            return;
        }

        // 🔹 次の画像へ
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self runImageBatchSequentially:names currentIndex:index + 1 saveDirectory:saveDir];
        });
    });
}

- (void)generateSafePrompt:(NSString *)original
                 completion:(void (^)(NSString *safePrompt))completion {

    NSString *apiKey = self.apiKeyField.stringValue;
    if (!apiKey.length) {
        completion(nil);
        return;
    }

    NSURL *url = [NSURL URLWithString:@"https://api.openai.com/v1/chat/completions"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];

    NSDictionary *body = @{
        @"model": @"gpt-4o-mini",
        @"messages": @[
            @{@"role": @"system",
              @"content": @"あなたは画像生成向けに安全なプロンプトを作成するアシスタントです。人物名や著名人名は絶対に使わず、特徴だけで構成してください。"},
            @{@"role": @"user",
              @"content": original}
        ]
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [req setHTTPBody:jsonData];

    NSURLSessionDataTask *task =
    [[NSURLSession sharedSession] dataTaskWithRequest:req
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil);
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *safe = json[@"choices"][0][@"message"][@"content"];

        completion(safe);
    }];

    [task resume];
}

//- (void)runSequentialPrompts:(NSArray<NSString *> *)prompts
//                currentIndex:(NSInteger)index
//               saveDirectory:(NSURL *)saveDir {
//
//    if (index >= prompts.count) {
//        NSLog(@"✅ 全ての画像生成が完了しました");
//        NSAlert *alert = [[NSAlert alloc] init];
//        alert.messageText = @"すべての画像生成が完了しました";
//        [alert runModal];
//        return;
//    }
//
//    NSString *nameOnly = prompts[index];
//    NSString *prompt = [NSString stringWithFormat:
//        @"%@の水墨画風ラフスケッチ。薄い墨色で柔らかい顔立ちを描き、筆のタッチは豪快かつ流麗。"
//         "表情はややぼやかし、静謐で品のある印象。背景は無色またはごく淡い紙の質感だけ。", nameOnly];
//
//    NSLog(@"生成中: %@", nameOnly);
//    self.resultView.string = [NSString stringWithFormat:@"生成中 (%ld/%lu): %@",
//                              (long)(index+1), (unsigned long)prompts.count, nameOnly];
//
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//        NSString *imagePath = [self runChatSynchronouslyWithPrompt:prompt];
//        if (imagePath) {
//            // ファイル名＝人物名.png
//            NSString *safeName = [nameOnly stringByReplacingOccurrencesOfString:@" " withString:@"_"];
//            NSURL *dest = [saveDir URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", safeName]];
//            
//            NSError *moveErr = nil;
//            [[NSFileManager defaultManager] moveItemAtPath:imagePath toPath:dest.path error:&moveErr];
//            if (moveErr) NSLog(@"⚠️ 保存失敗: %@", moveErr.localizedDescription);
//            else NSLog(@"✅ 保存完了: %@", dest.path);
//        }
//
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [self runSequentialPrompts:prompts currentIndex:index + 1 saveDirectory:saveDir];
//        });
//    });
//}

// MARK: - 進捗ダイアログを表示
- (void)showProgressDialogWithTotal:(NSInteger)totalCount {
    self.shouldCancelBatch = NO;

    NSRect frame = NSMakeRect(0, 0, 400, 120);
    self.progressWindow = [[NSWindow alloc] initWithContentRect:frame
                                                      styleMask:(NSWindowStyleMaskTitled)
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
    [self.progressWindow setTitle:@"バッチ実行中"];
    [self.progressWindow center];

    NSView *content = self.progressWindow.contentView;

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 70, 360, 20)];
    [label setStringValue:@"画像を順次生成中..."];
    [label setBezeled:NO];
    [label setEditable:NO];
    [label setDrawsBackground:NO];
    [content addSubview:label];

    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 40, 360, 20)];
    [self.progressIndicator setIndeterminate:NO];
    [self.progressIndicator setMinValue:0];
    [self.progressIndicator setMaxValue:totalCount];
    [self.progressIndicator setDoubleValue:0];
    [self.progressIndicator setStyle:NSProgressIndicatorStyleBar];
    [content addSubview:self.progressIndicator];

    self.cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(150, 5, 100, 30)];
    [self.cancelButton setTitle:@"キャンセル"];
    [self.cancelButton setBezelStyle:NSBezelStyleRounded];
    [self.cancelButton setTarget:self];
    [self.cancelButton setAction:@selector(cancelBatchProcess)];
    [content addSubview:self.cancelButton];

    NSWindow *mainWindow = self.view.window;
    [mainWindow beginSheet:self.progressWindow completionHandler:nil];
}

// MARK: - キャンセル処理
- (void)cancelBatchProcess {
    self.shouldCancelBatch = YES;
    [self.view.window endSheet:self.progressWindow];
    self.progressWindow = nil;
}

// MARK: - 進捗バー更新
- (void)updateProgress:(NSInteger)current total:(NSInteger)total {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressIndicator setDoubleValue:current];
        NSString *status = [NSString stringWithFormat:@"進行状況: %ld / %ld", (long)current, (long)total];
        for (NSView *sub in self.progressWindow.contentView.subviews) {
            if ([sub isKindOfClass:[NSTextField class]]) {
                NSTextField *label = (NSTextField *)sub;
                [label setStringValue:status];
                break;
            }
        }
    });
}

// MARK: - 画像保存メソッド（共通化）
- (NSString *)saveImageData:(NSData *)data
                  withName:(NSString *)fileName
                toDirectory:(NSURL *)directoryURL {

    if (!data || !directoryURL) {
        NSLog(@"⚠️ 保存失敗: データまたはディレクトリが無効");
        return nil;
    }

    // 拡張子確認・追加
    if (![fileName.lowercaseString hasSuffix:@".png"]) {
        fileName = [fileName stringByAppendingString:@".png"];
    }

    // 保存先フルパス
    NSURL *saveURL = [directoryURL URLByAppendingPathComponent:fileName];

    NSError *error = nil;
    BOOL success = [data writeToURL:saveURL options:NSDataWritingAtomic error:&error];
    if (!success || error) {
        NSLog(@"❌ 画像保存失敗: %@", error.localizedDescription);
        return nil;
    }

    NSLog(@"✅ 画像保存完了: %@", saveURL.path);
    return saveURL.path;
}

// MARK: - ChatGPT API を逐次実行（非同期処理）
//// MARK: - バッチ処理部分の改修
//- (void)runSequentialPrompts:(NSArray<NSString *> *)prompts currentIndex:(NSInteger)index {
//    if (index == 0) {
//        [self showProgressDialogWithTotal:prompts.count];
//    }
//
//    if (self.shouldCancelBatch || index >= prompts.count) {
//        [self.view.window endSheet:self.progressWindow];
//        self.progressWindow = nil;
//        NSLog(@"全てのプロンプトを処理しました");
//        return;
//    }
//
//    NSString *prompt = prompts[index];
//    NSLog(@"実行中: %@", prompt);
//
//    [self sendPromptToChatGPT:prompt completion:^(NSString *imagePath) {
//        NSImage *img = [[NSImage alloc] initWithContentsOfFile:imagePath];
//        self.resultImageView.image = img;
//        NSLog(@"✅ 生成完了: %@", imagePath);
//
//        // 少し待って次へ
//        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
//                       dispatch_get_main_queue(), ^{
//            [self runSequentialPrompts:prompts currentIndex:index + 1];
//        });
//    }];
//}

//// MARK: - ChatGPT API呼び出し（既存のAPI呼び出しラッパを利用）
//- (void)sendPromptToChatGPT:(NSString *)prompt completion:(void (^)(NSString *response))completion {
//    // ここは既存のChatGPT呼び出し部分をラップする
//    // 例: [self runChatWithPrompt:prompt completion:completion];
//    [self runChatWithPrompt:prompt completion:^(NSString *result) {
//        if (completion) completion(result ?: @"(no response)");
//    }];
//}

// MARK: - 履歴保存の共通メソッド
- (void)saveHistoryWithPrompt:(NSString *)prompt response:(NSString *)response {
    if (!prompt || !response) return;

    NSDictionary *entry = @{
        @"prompt": prompt,
        @"response": response,
        @"model": self.modelField.stringValue ?: @"",
    };

    [self.history addObject:entry];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.historyTable reloadData];
    });
}

// MARK: - 履歴に追加（既存のメソッド）
- (void)appendToHistoryWithPrompt:(NSString *)prompt response:(NSString *)response {
    // 既に実装済みの履歴保存処理を呼ぶ
    [self saveHistoryWithPrompt:prompt response:response];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.imageHistory.count;
}

- (id)tableView:(NSTableView *)tableView
objectValueForTableColumn:(NSTableColumn *)tableColumn
            row:(NSInteger)row
{
    NSDictionary *entry = self.imageHistory[row];

    if ([tableColumn.identifier isEqualToString:@"ThumbnailColumn"]) {
        return entry[@"thumbnail"];
    } else if ([tableColumn.identifier isEqualToString:@"PromptColumn"]) {
        return entry[@"prompt"];
    } else if ([tableColumn.identifier isEqualToString:@"ModelColumn"]) {
        return entry[@"model"];
    } else if ([tableColumn.identifier isEqualToString:@"FileColumn"]) {
        return entry[@"filename"];
    }

    return @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.historyTable.selectedRow;
    if (row < 0 || row >= self.imageHistory.count) return;

    NSDictionary *entry = self.imageHistory[row];

    self.promptField.stringValue = entry[@"prompt"] ?: @"";
    self.modelField.stringValue = entry[@"model"] ?: @"";
    self.resultImageView.image = entry[@"thumbnail"];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return 80;   // ← 好きな高さに変更（例：80）
}

- (NSImage *)resizedImage:(NSImage *)img to:(CGFloat)size {
    NSImage *newImg = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [newImg lockFocus];
    [img drawInRect:NSMakeRect(0, 0, size, size)
           fromRect:NSZeroRect
          operation:NSCompositingOperationSourceOver
           fraction:1.0];
    [newImg unlockFocus];
    return newImg;
}

@end
