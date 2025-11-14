//
//  ViewController.h
//  ChatGPTController
//
//  Created by 早川強 on 2025/11/05.
//

#import <Cocoa/Cocoa.h>

@interface ViewController : NSViewController <NSTableViewDelegate, NSTableViewDataSource>

@property (weak) IBOutlet NSTextField *apiKeyField;
@property (weak) IBOutlet NSTextField *modelField;
@property (weak) IBOutlet NSTextField *promptField;
@property (weak) IBOutlet NSImageView *resultImageView;
@property (weak) IBOutlet NSTextField *promptSuffixField;
@property (weak) IBOutlet NSButton *sendButton;
@property (unsafe_unretained) IBOutlet NSTextView *resultView;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *history;
@property (weak) IBOutlet NSProgressIndicator *loadingIndicator;
@property (weak) IBOutlet NSTableView *historyTable;

// MARK: - ChatGPT API関連
//- (void)runChatWithPrompt:(NSString *)prompt completion:(void (^)(NSString *result))completion;
- (NSString *)runChatSynchronouslyWithPrompt:(NSString *)prompt;
- (IBAction)generateImageFromPrompt:(id)sender;

// MARK: - 履歴処理
- (void)appendToHistoryWithPrompt:(NSString *)prompt response:(NSString *)response;
- (void)saveHistoryWithPrompt:(NSString *)prompt response:(NSString *)response;

// MARK: - ファイル処理／逐次実行
- (IBAction)loadPromptFileAndExecute:(id)sender;
//- (void)executePromptsFromFile:(NSURL *)fileURL;
//- (void)runSequentialPrompts:(NSArray<NSString *> *)prompts currentIndex:(NSInteger)index;

//- (IBAction)sendToChatGPT:(id)sender;
- (IBAction)newEntry:(id)sender;
- (IBAction)generateAndSaveImage:(id)sender;
//- (IBAction)duplicateEntry:(id)sender;
//- (void)executePromptsFromFile:(NSURL *)fileURL saveDirectory:(NSURL *)saveDir;
//- (void)runSequentialPrompts:(NSArray<NSString *> *)prompts currentIndex:(NSInteger)index saveDirectory:(NSURL *)saveDir;

#pragma mark - 保存／読み込み／書き出し

//// 🔹 「名前をつけて保存」(plist)
//- (IBAction)saveHistoryAs:(id)sender;
//// 🔹 「読み込み」（plist）
//- (IBAction)openHistoryFile:(id)sender;
//// 🔹 「書き出し」（タブ区切りテキスト）
//- (IBAction)exportHistoryAsText:(id)sender;
//- (IBAction)deleteSelectedHistory:(id)sender;

@end


